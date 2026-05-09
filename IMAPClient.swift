import Foundation
import Network

actor IMAPClient {
    private var connection: NWConnection?
    private var buffer = Data()
    private var tagCounter = 0

    // MARK: - Public API

    func connect(host: String, port: UInt16) async throws {
        let conn = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tls
        )
        self.connection = conn

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            var resumed = false
            conn.stateUpdateHandler = { state in
                guard !resumed else { return }
                switch state {
                case .ready:
                    resumed = true
                    cont.resume()
                case .failed(let error):
                    resumed = true
                    cont.resume(throwing: error)
                case .cancelled:
                    resumed = true
                    cont.resume(throwing: IMAPError.cancelled)
                default:
                    break
                }
            }
            conn.start(queue: .global(qos: .userInitiated))
        }

        // Consume server greeting
        _ = try await readLine()
    }

    func login(user: String, password: String) async throws {
        // Use IMAP literals so any special character in the password works
        let tag = nextTag()
        let userBytes = user.utf8.count
        let passBytes = password.utf8.count

        try await send("\(tag) LOGIN {\(userBytes)}\r\n")
        _ = try await readLine()          // server sends "+ go ahead"
        try await send("\(user) {\(passBytes)}\r\n")
        _ = try await readLine()          // server sends "+ go ahead"
        try await send("\(password)\r\n")

        let lines = try await readUntilTagged(tag: tag)
        guard lines.last?.contains("OK") == true else {
            let serverMsg = lines.last ?? "no response from server"
            throw IMAPError.loginFailed(serverMsg)
        }
    }

    func selectInbox() async throws {
        let lines = try await command("SELECT INBOX")
        guard lines.last?.contains("OK") == true else {
            throw IMAPError.commandFailed("SELECT INBOX")
        }
    }

    func search(query: String) async throws -> [Int] {
        let lines = try await command("SEARCH \(query)")
        for line in lines {
            if line.uppercased().hasPrefix("* SEARCH") {
                let tokens = line.dropFirst(8).trimmingCharacters(in: .whitespaces)
                if tokens.isEmpty { return [] }
                return tokens.split(separator: " ").compactMap { Int($0) }
            }
        }
        return []
    }

    func fetchMessage(id: Int) async throws -> Data {
        let tag = nextTag()
        try await send("\(tag) FETCH \(id) RFC822\r\n")
        return try await readFetchResponse(tag: tag)
    }

    func logout() async throws {
        _ = try? await command("LOGOUT")
        connection?.cancel()
    }

    // MARK: - Private: Protocol

    private func nextTag() -> String {
        tagCounter += 1
        return String(format: "T%04d", tagCounter)
    }

    private func quoted(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private func command(_ cmd: String) async throws -> [String] {
        let tag = nextTag()
        try await send("\(tag) \(cmd)\r\n")
        return try await readUntilTagged(tag: tag)
    }

    private func readUntilTagged(tag: String) async throws -> [String] {
        var lines: [String] = []
        while true {
            let line = try await readLine()
            lines.append(line)
            if line.hasPrefix(tag) { break }
        }
        return lines
    }

    // Reads a FETCH RFC822 response, returning the raw message bytes from the literal.
    private func readFetchResponse(tag: String) async throws -> Data {
        var messageData = Data()
        while true {
            let line = try await readLine()
            if line.hasPrefix(tag) { break }
            if let size = literalSize(in: line) {
                messageData = try await readBytes(count: size)
                // Continue consuming lines (closing paren, tagged OK)
            }
        }
        return messageData
    }

    // Extracts n from a line ending in {n}
    private func literalSize(in line: String) -> Int? {
        guard line.hasSuffix("}"), let open = line.lastIndex(of: "{") else { return nil }
        let inner = line[line.index(after: open) ..< line.index(before: line.endIndex)]
        return Int(inner)
    }

    // MARK: - Private: I/O

    private func send(_ text: String) async throws {
        guard let data = text.data(using: .utf8) else { return }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection?.send(content: data, completion: .contentProcessed { error in
                if let error = error { cont.resume(throwing: error) }
                else { cont.resume() }
            })
        }
    }

    private func readLine() async throws -> String {
        let crlf = Data([0x0D, 0x0A])
        while true {
            if let range = buffer.range(of: crlf) {
                let lineData = buffer[buffer.startIndex ..< range.lowerBound]
                buffer.removeSubrange(buffer.startIndex ... range.upperBound - 1)
                return String(data: lineData, encoding: .utf8) ?? ""
            }
            buffer.append(try await receive())
        }
    }

    private func readBytes(count: Int) async throws -> Data {
        while buffer.count < count {
            buffer.append(try await receive())
        }
        let slice = buffer[buffer.startIndex ..< buffer.startIndex.advanced(by: count)]
        buffer.removeSubrange(buffer.startIndex ..< buffer.startIndex.advanced(by: count))
        return Data(slice)
    }

    private func receive() async throws -> Data {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            connection?.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, _, error in
                if let error = error { cont.resume(throwing: error) }
                else { cont.resume(returning: data ?? Data()) }
            }
        }
    }
}

enum IMAPError: LocalizedError {
    case cancelled
    case loginFailed(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .cancelled:              return "Connection was cancelled."
        case .loginFailed(let msg):   return "Login failed — \(msg)\n\nTip: make sure IMAP is enabled in your GoDaddy email settings."
        case .commandFailed(let c):   return "IMAP command failed: \(c)"
        }
    }
}
