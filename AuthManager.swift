import Foundation
import AuthenticationServices
import CryptoKit

@MainActor
class AuthManager: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {

    static let shared = AuthManager()

    @Published var isSignedIn = false
    @Published var userEmail  = ""

    // ── Paste your Azure client ID here ───────────────────────────────────────
    let clientId    = "YOUR_CLIENT_ID"
    // ─────────────────────────────────────────────────────────────────────────

    private let redirectUri    = "invoicescanner://auth"
    private let redirectScheme = "invoicescanner"
    private let scopes         = "https://graph.microsoft.com/Mail.Read offline_access"
    private let tokenURL       = URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/token")!

    private var accessToken:  String?
    private var refreshToken: String?
    private var tokenExpiry:  Date?

    override init() {
        super.init()
        accessToken  = KeychainHelper.load(account: "ms_access_token")
        refreshToken = KeychainHelper.load(account: "ms_refresh_token")
        if let exp = UserDefaults.standard.object(forKey: "ms_token_expiry") as? Date {
            tokenExpiry = exp
        }
        userEmail   = UserDefaults.standard.string(forKey: "ms_user_email") ?? ""
        isSignedIn  = refreshToken != nil
    }

    // MARK: - Public

    func signIn() async throws {
        let verifier   = codeVerifier()
        let challenge  = codeChallenge(for: verifier)

        var comps = URLComponents(string: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize")!
        comps.queryItems = [
            .init(name: "client_id",             value: clientId),
            .init(name: "response_type",          value: "code"),
            .init(name: "redirect_uri",           value: redirectUri),
            .init(name: "scope",                  value: scopes),
            .init(name: "code_challenge",         value: challenge),
            .init(name: "code_challenge_method",  value: "S256"),
            .init(name: "response_mode",          value: "query"),
        ]

        let callbackURL: URL = try await withCheckedThrowingContinuation { cont in
            let session = ASWebAuthenticationSession(
                url: comps.url!,
                callbackURLScheme: redirectScheme
            ) { url, error in
                if let error = error { cont.resume(throwing: error) }
                else if let url = url { cont.resume(returning: url) }
                else { cont.resume(throwing: AuthError.cancelled) }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }

        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value
        else { throw AuthError.noCode }

        try await exchangeCode(code, verifier: verifier)
        try await fetchEmail()
        isSignedIn = true
    }

    func signOut() {
        accessToken = nil; refreshToken = nil; tokenExpiry = nil
        KeychainHelper.delete(account: "ms_access_token")
        KeychainHelper.delete(account: "ms_refresh_token")
        UserDefaults.standard.removeObject(forKey: "ms_token_expiry")
        UserDefaults.standard.removeObject(forKey: "ms_user_email")
        userEmail = ""; isSignedIn = false
    }

    func getValidToken() async throws -> String {
        if let t = accessToken, let exp = tokenExpiry, exp > Date().addingTimeInterval(60) {
            return t
        }
        guard let refresh = refreshToken else { throw AuthError.notSignedIn }
        try await refreshAccessToken(refresh)
        return accessToken ?? ""
    }

    // MARK: - ASWebAuthenticationPresentationContextProviding

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.windows.first(where: { $0.isKeyWindow }) ?? NSWindow()
    }

    // MARK: - Private

    private func exchangeCode(_ code: String, verifier: String) async throws {
        let body: [String: String] = [
            "client_id":     clientId,
            "grant_type":    "authorization_code",
            "code":          code,
            "redirect_uri":  redirectUri,
            "code_verifier": verifier,
        ]
        try await postToken(body: body)
    }

    private func refreshAccessToken(_ token: String) async throws {
        let body: [String: String] = [
            "client_id":     clientId,
            "grant_type":    "refresh_token",
            "refresh_token": token,
            "scope":         scopes,
        ]
        try await postToken(body: body)
    }

    private func postToken(body: [String: String]) async throws {
        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = body.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
                           .joined(separator: "&")
                           .data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: req)
        let json = try JSONDecoder().decode(TokenResponse.self, from: data)

        if let error = json.error { throw AuthError.tokenError(error, json.errorDescription ?? "") }

        accessToken  = json.accessToken
        tokenExpiry  = Date().addingTimeInterval(TimeInterval(json.expiresIn ?? 3600))
        if let rt = json.refreshToken { refreshToken = rt }

        KeychainHelper.save(password: accessToken!,  account: "ms_access_token")
        if let rt = refreshToken { KeychainHelper.save(password: rt, account: "ms_refresh_token") }
        UserDefaults.standard.set(tokenExpiry, forKey: "ms_token_expiry")
    }

    private func fetchEmail() async throws {
        let token = try await getValidToken()
        var req = URLRequest(url: URL(string: "https://graph.microsoft.com/v1.0/me?$select=mail,userPrincipalName")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let email = json["mail"] as? String ?? json["userPrincipalName"] as? String ?? ""
            userEmail = email
            UserDefaults.standard.set(email, forKey: "ms_user_email")
        }
    }

    // MARK: - PKCE helpers

    private func codeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func codeChallenge(for verifier: String) -> String {
        let data    = Data(verifier.utf8)
        let digest  = SHA256.hash(data: data)
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Supporting types

private struct TokenResponse: Decodable {
    let accessToken:      String?
    let refreshToken:     String?
    let expiresIn:        Int?
    let error:            String?
    let errorDescription: String?
    enum CodingKeys: String, CodingKey {
        case accessToken      = "access_token"
        case refreshToken     = "refresh_token"
        case expiresIn        = "expires_in"
        case error
        case errorDescription = "error_description"
    }
}

enum AuthError: LocalizedError {
    case cancelled, noCode, notSignedIn
    case tokenError(String, String)
    var errorDescription: String? {
        switch self {
        case .cancelled:               return "Sign-in was cancelled."
        case .noCode:                  return "No authorisation code returned."
        case .notSignedIn:             return "Please sign in first."
        case .tokenError(let e, let d): return "Token error: \(e) — \(d)"
        }
    }
}
