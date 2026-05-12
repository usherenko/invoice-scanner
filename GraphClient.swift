import Foundation

struct GraphClient {
    private let token:   String
    private let base = "https://graph.microsoft.com/v1.0"

    init(token: String) { self.token = token }

    // MARK: - Public

    /// Returns all messages in the inbox that contain "invoice" and fall within `month` (yyyy-MM).
    func invoiceMessages(month: String) async throws -> [Message] {
        let (start, end) = dateRange(for: month)
        var results: [Message] = []
        var url: String? = "\(base)/me/mailFolders/inbox/messages"
            + "?$search=%22invoice%22"
            + "&$select=id,subject,receivedDateTime,hasAttachments"
            + "&$top=50"

        while let next = url {
            let page: PageResponse<Message> = try await get(next)
            let inRange = page.value.filter { msg in
                guard let d = iso8601(msg.receivedDateTime) else { return false }
                return d >= start && d < end
            }
            results.append(contentsOf: inRange)

            // Stop paging once we've gone past the start of our target month
            if let oldest = page.value.last.flatMap({ iso8601($0.receivedDateTime) }),
               oldest < start { break }

            url = page.nextLink
        }

        return results.filter { $0.hasAttachments == true }
    }

    /// Returns PDF attachments for a given message as (filename, Data) pairs.
    func pdfAttachments(messageId: String) async throws -> [(String, Data)] {
        let url = "\(base)/me/messages/\(messageId)/attachments"
        let page: PageResponse<Attachment> = try await get(url)

        return page.value.compactMap { att in
            guard att.contentType?.lowercased().contains("pdf") == true
                    || att.name?.lowercased().hasSuffix(".pdf") == true,
                  let b64  = att.contentBytes,
                  let data = Data(base64Encoded: b64, options: .ignoreUnknownCharacters)
            else { return nil }
            return (att.name ?? "invoice.pdf", data)
        }
    }

    // MARK: - Networking

    private func get<T: Decodable>(_ urlString: String) async throws -> T {
        guard let url = URL(string: urlString) else { throw GraphError.badURL }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw GraphError.badResponse }

        if http.statusCode == 401 { throw GraphError.unauthorized }
        guard (200...299).contains(http.statusCode) else {
            throw GraphError.apiError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Helpers

    private func dateRange(for month: String) -> (Date, Date) {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM"
        df.locale = Locale(identifier: "en_US_POSIX")
        let start = df.date(from: month) ?? Date()
        let end   = Calendar.current.date(byAdding: .month, value: 1, to: start) ?? start
        return (start, end)
    }

    private func iso8601(_ string: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: string) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: string)
    }
}

// MARK: - Response models

struct Message: Decodable {
    let id:                  String
    let subject:             String?
    let receivedDateTime:    String
    let hasAttachments:      Bool?
}

struct Attachment: Decodable {
    let id:           String
    let name:         String?
    let contentType:  String?
    let contentBytes: String?
}

private struct PageResponse<T: Decodable>: Decodable {
    let value:    [T]
    let nextLink: String?
    enum CodingKeys: String, CodingKey {
        case value
        case nextLink = "@odata.nextLink"
    }
}

enum GraphError: LocalizedError {
    case badURL, badResponse, unauthorized
    case apiError(Int, String)
    var errorDescription: String? {
        switch self {
        case .badURL:        return "Invalid URL."
        case .badResponse:   return "Invalid server response."
        case .unauthorized:  return "Session expired — please sign out and sign in again."
        case .apiError(let c, let m): return "Graph API error \(c): \(m)"
        }
    }
}
