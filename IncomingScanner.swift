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

        // Try page-by-page extraction first, fall back to document-level string.
        var text = (0..<doc.pageCount)
            .compactMap { doc.page(at: $0)?.string }
            .joined(separator: "\n")

        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let docText = doc.string {
            text = docText
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
        // Match "total" (case-insensitive) NOT preceded by "sub", followed by
        // up to 20 non-digit characters (spaces, €, newlines), then a decimal amount.
        // [^\d]{0,20} bridges whitespace and currency symbols without crossing into
        // unrelated numbers.
        // Return the MAX across all matches — the grand total is always the
        // largest figure; line-item totals and column headers are smaller.
        guard let regex = try? NSRegularExpression(
            pattern: #"(?<![Ss]ub)total\b[^\d]{0,20}(\d+[.,]\d{2})"#,
            options: .caseInsensitive
        ) else { return nil }

        let range = NSRange(text.startIndex..., in: text)
        let amounts = regex.matches(in: text, range: range).compactMap { match -> Double? in
            guard let r = Range(match.range(at: 1), in: text) else { return nil }
            return Double(String(text[r]).replacingOccurrences(of: ",", with: "."))
        }
        return amounts.max()
    }

    private static func detectSource(from text: String) -> String {
        if text.contains("FACTURA") || text.contains("BASE IMPONIBLE") { return "Holded" }
        if text.contains("Invoice #WS") || text.contains("Online Order") { return "CommonGround" }
        return "Unknown"
    }
}
