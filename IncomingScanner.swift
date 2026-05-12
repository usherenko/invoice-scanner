import Foundation
import PDFKit

struct InvoiceResult: Identifiable {
    let id = UUID()
    let filename: String
    let source: String   // "Holded" | "CommonGround" | "Unknown"
    let total: Double
}

enum IncomingScanner {

    static func scan(folder: URL) -> [InvoiceResult] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil
        )) ?? []
        return files
            .filter { $0.pathExtension.lowercased() == "pdf" }
            .compactMap { parse(url: $0) }
            .sorted { $0.filename < $1.filename }
    }

    static func parse(url: URL) -> InvoiceResult? {
        guard let doc = PDFDocument(url: url) else { return nil }
        var text = ""
        for i in 0..<doc.pageCount {
            text += doc.page(at: i)?.string ?? ""
        }
        guard let total = extractTotal(from: text) else { return nil }
        return InvoiceResult(
            filename: url.lastPathComponent,
            source: detectSource(from: text),
            total: total
        )
    }

    // MARK: - Private helpers

    private static func extractTotal(from text: String) -> Double? {
        let lines = text.components(separatedBy: .newlines)
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let upper = trimmed.uppercased()
            guard upper.hasPrefix("TOTAL"), !upper.hasPrefix("SUBTOTAL") else { continue }
            let pool = [trimmed] + (i + 1 < lines.count ? [lines[i + 1]] : [])
            for candidate in pool {
                if let v = parseAmount(from: candidate) { return v }
            }
        }
        return nil
    }

    private static func parseAmount(from line: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: #"€?([\d]+[.,][\d]{2})€?"#),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line) else { return nil }
        let raw = String(line[range]).replacingOccurrences(of: ",", with: ".")
        return Double(raw)
    }

    private static func detectSource(from text: String) -> String {
        if text.contains("FACTURA") || text.contains("BASE IMPONIBLE") { return "Holded" }
        if text.contains("Invoice #WS") || text.contains("Online Order") { return "CommonGround" }
        return "Unknown"
    }
}
