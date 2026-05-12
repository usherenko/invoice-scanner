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
        // Split into lines and find any line that contains "total" but not "subtotal".
        // Search that line and the next 2 lines for a decimal amount.
        // Keep the LAST amount found — summary totals appear after column headers.
        let lines = text.components(separatedBy: .newlines)
        var lastAmount: Double? = nil

        for (i, line) in lines.enumerated() {
            let lower = line.lowercased()
            guard lower.contains("total"), !lower.contains("subtotal") else { continue }

            for j in i..<min(i + 3, lines.count) {
                if let v = decimalAmount(in: lines[j]) {
                    lastAmount = v
                    break
                }
            }
        }
        return lastAmount
    }

    private static func decimalAmount(in line: String) -> Double? {
        // Match any decimal number: one or more digits, comma or period, exactly 2 digits.
        guard let regex = try? NSRegularExpression(pattern: #"(\d+[.,]\d{2})"#),
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
