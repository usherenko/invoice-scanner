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

        var text = (0..<doc.pageCount)
            .compactMap { doc.page(at: $0)?.string }
            .joined(separator: "\n")

        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let docText = doc.string {
            text = docText
        }

        // Write extracted text next to the PDF so you can inspect what PDFKit sees.
        let debugURL = url.deletingPathExtension().appendingPathExtension("txt")
        try? text.write(to: debugURL, atomically: true, encoding: .utf8)

        guard let total = extractTotal(from: text) else { return nil }
        return InvoiceResult(
            filename: url.lastPathComponent,
            source: detectSource(from: text),
            total: total
        )
    }

    // MARK: - Private helpers

    private static func extractTotal(from text: String) -> Double? {
        // No \b after "total" — digits are word chars in regex, so "TOTAL529,50€"
        // (label and amount merged in the PDF stream with no separator) would fail \b.
        // [^\d\n]* allows unlimited spaces/symbols on the same line (right-aligned layouts).
        // \n? lets the amount sit on the very next line.
        // max() picks the grand total over any smaller line-item totals.
        guard let regex = try? NSRegularExpression(
            pattern: #"(?<![Ss]ub)total[^\d\n]*\n?[^\d\n]*(\d+[.,]\d{2})"#,
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
