import Foundation

struct MIMEParser {

    /// Returns all PDF attachments found in a raw RFC822 email message.
    static func extractPDFs(from raw: Data) -> [(filename: String, data: Data)] {
        let text = String(data: raw, encoding: .utf8)
                ?? String(data: raw, encoding: .isoLatin1)
                ?? ""
        var results: [(String, Data)] = []
        walk(text: text, into: &results)
        return results
    }

    // MARK: - Recursive walk

    private static func walk(text: String, into results: inout [(String, Data)]) {
        let (headers, body) = splitHeadersAndBody(text)
        let contentType = headers["content-type"] ?? ""

        if contentType.lowercased().contains("multipart") {
            if let boundary = parameter("boundary", in: contentType) {
                for part in splitMultipart(body: body, boundary: boundary) {
                    walk(text: part, into: &results)
                }
            }
            return
        }

        let disposition = headers["content-disposition"] ?? ""
        let isPDF = contentType.lowercased().contains("pdf")
        let isAttachment = disposition.lowercased().contains("attachment")
                        || disposition.lowercased().contains("inline")

        guard isPDF || isAttachment else { return }

        guard let decoded = decodedBody(body, encoding: headers["content-transfer-encoding"] ?? ""),
              decoded.count > 0 else { return }

        // Skip non-PDF attachments
        let rawFilename = parameter("filename", in: disposition)
                       ?? parameter("name", in: contentType)
                       ?? "invoice.pdf"
        let filename = decodeRFC2047(rawFilename)

        guard filename.lowercased().hasSuffix(".pdf") || isPDF else { return }
        let finalName = filename.lowercased().hasSuffix(".pdf") ? filename : filename + ".pdf"

        results.append((finalName, decoded))
    }

    // MARK: - Helpers

    private static func splitHeadersAndBody(_ text: String) -> ([String: String], String) {
        // Split on first blank line
        let separators = ["\r\n\r\n", "\n\n"]
        for sep in separators {
            if let range = text.range(of: sep) {
                return (
                    parseHeaders(String(text[..<range.lowerBound])),
                    String(text[range.upperBound...])
                )
            }
        }
        return (parseHeaders(text), "")
    }

    private static func parseHeaders(_ raw: String) -> [String: String] {
        var headers: [String: String] = [:]
        var key = ""
        var value = ""

        for line in raw.components(separatedBy: .newlines) {
            if line.first == " " || line.first == "\t" {
                value += " " + line.trimmingCharacters(in: .whitespaces)
            } else {
                if !key.isEmpty { headers[key.lowercased()] = value.trimmingCharacters(in: .whitespaces) }
                let parts = line.split(separator: ":", maxSplits: 1)
                if parts.count == 2 {
                    key   = String(parts[0])
                    value = String(parts[1]).trimmingCharacters(in: .whitespaces)
                } else {
                    key = ""; value = ""
                }
            }
        }
        if !key.isEmpty { headers[key.lowercased()] = value.trimmingCharacters(in: .whitespaces) }
        return headers
    }

    private static func splitMultipart(body: String, boundary: String) -> [String] {
        let delimiter = "--" + boundary
        let parts = body.components(separatedBy: delimiter)
        // First part (before first boundary) and last (after closing --boundary--) are preamble/epilogue
        return Array(parts.dropFirst().dropLast())
    }

    private static func parameter(_ name: String, in header: String) -> String? {
        for segment in header.split(separator: ";").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            let kv = segment.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if kv.count == 2, kv[0].lowercased() == name {
                return kv[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
        }
        return nil
    }

    private static func decodedBody(_ body: String, encoding: String) -> Data? {
        let enc = encoding.lowercased().trimmingCharacters(in: .whitespaces)
        if enc.contains("base64") {
            let stripped = body.components(separatedBy: .newlines).joined()
            return Data(base64Encoded: stripped, options: .ignoreUnknownCharacters)
        }
        if enc.contains("quoted-printable") {
            return decodeQuotedPrintable(body)
        }
        return body.data(using: .isoLatin1)
    }

    private static func decodeQuotedPrintable(_ text: String) -> Data {
        var result = Data()
        var lines = text.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            var l = line.hasSuffix("\r") ? String(line.dropLast()) : line
            let softBreak = l.hasSuffix("=")
            if softBreak { l = String(l.dropLast()) }
            var idx = l.startIndex
            while idx < l.endIndex {
                if l[idx] == "=", l.distance(from: idx, to: l.endIndex) >= 3 {
                    let hex = String(l[l.index(after: idx)...].prefix(2))
                    if let byte = UInt8(hex, radix: 16) {
                        result.append(byte)
                        idx = l.index(idx, offsetBy: 3)
                        continue
                    }
                }
                result.append(contentsOf: String(l[idx]).utf8)
                idx = l.index(after: idx)
            }
            if !softBreak && i < lines.count - 1 { result.append(0x0A) }
        }
        return result
    }

    /// Decodes RFC 2047 encoded words like =?UTF-8?B?...?= or =?UTF-8?Q?...?=
    private static func decodeRFC2047(_ input: String) -> String {
        var result = input
        let pattern = #"=\?([^?]+)\?([BbQq])\?([^?]*)\?="#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return input }
        let range = NSRange(input.startIndex..., in: input)
        let matches = regex.matches(in: input, range: range).reversed()
        for match in matches {
            guard let charsetRange  = Range(match.range(at: 1), in: input),
                  let encodingRange = Range(match.range(at: 2), in: input),
                  let textRange     = Range(match.range(at: 3), in: input),
                  let fullRange     = Range(match.range(at: 0), in: input) else { continue }

            let charset  = String(input[charsetRange])
            let encoding = String(input[encodingRange]).uppercased()
            let encoded  = String(input[textRange])

            var decoded: String?
            let cfEncoding = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
            let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
            let strEncoding = String.Encoding(rawValue: nsEncoding)

            if encoding == "B" {
                if let data = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters) {
                    decoded = String(data: data, encoding: strEncoding)
                            ?? String(data: data, encoding: .utf8)
                }
            } else if encoding == "Q" {
                let qp = encoded.replacingOccurrences(of: "_", with: " ")
                if let data = decodeQuotedPrintable(qp) as Data? {
                    decoded = String(data: data, encoding: strEncoding)
                            ?? String(data: data, encoding: .utf8)
                }
            }

            if let d = decoded {
                result = result.replacingCharacters(in: fullRange, with: d)
            }
        }
        return result
    }
}
