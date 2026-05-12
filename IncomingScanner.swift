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
        // Match "Total" or "TOTAL" (not "Subtotal"/"SUBTOTAL") followed by a decimal amount
        // within 10 characters (spans newlines to handle multi-line layouts).
        // Take the LAST match — summary totals appear after column headers in the table.
        guard let regex = try? NSRegularExpression(
            pattern: #"(?<![Ss]ub)[Tt]otal\b.{0,10}([\d]+[.,][\d]{2})"#,
            options: .dotMatchesLineSeparators
        ) else { return nil }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)

        guard let last = matches.last,
              let numRange = Range(last.range(at: 1), in: text) else { return nil }

        let raw = String(text[numRange]).replacingOccurrences(of: ",", with: ".")
        return Double(raw)
    }

    private static func detectSource(from text: String) -> String {
        if text.contains("FACTURA") || text.contains("BASE IMPONIBLE") { return "Holded" }
        if text.contains("Invoice #WS") || text.contains("Online Order") { return "CommonGround" }
        return "Unknown"
    }
}
