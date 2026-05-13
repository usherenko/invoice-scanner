import Foundation

struct ScanManager {

    static func scan(
        month:     String,
        outputDir: String,
        log:       @escaping (String) -> Void
    ) async {
        do {
            log("Getting access token…")
            let token  = try await AuthManager.shared.getValidToken()
            let client = GraphClient(token: token)

            log("Searching inbox for \(month) invoices…")
            let messages = try await client.invoiceMessages(month: month)

            guard !messages.isEmpty else {
                log("No invoice emails found for \(month).")
                return
            }

            log("Found \(messages.count) email(s) — downloading PDFs…\n")

            let outDir = URL(fileURLWithPath: outputDir).appendingPathComponent(month)
            try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

            var downloaded = loadManifest(from: outDir)
            var savedCount = 0
            var skippedCount = 0

            for msg in messages {
                if downloaded.contains(msg.id) {
                    log("  –  Already have: \(msg.subject ?? "(no subject)")")
                    skippedCount += 1
                    continue
                }
                let pdfs = try await client.pdfAttachments(messageId: msg.id)
                if pdfs.isEmpty {
                    log("  –  No PDF in: \(msg.subject ?? "(no subject)")")
                } else {
                    for (filename, data) in pdfs {
                        let dest = uniqueURL(for: filename, in: outDir)
                        try data.write(to: dest)
                        log("  ✓  \(dest.lastPathComponent)")
                        savedCount += 1
                    }
                    downloaded.insert(msg.id)
                    saveManifest(downloaded, to: outDir)
                }
            }

            if skippedCount > 0 {
                log("\nDone — \(savedCount) new PDF(s) saved, \(skippedCount) already downloaded.")
            } else {
                log("\nDone — \(savedCount) PDF(s) saved to \(outputDir)/\(month)")
            }

        } catch {
            log("❌  \(error.localizedDescription)")
        }
    }

    private static let manifestName = ".downloaded.json"

    private static func loadManifest(from dir: URL) -> Set<String> {
        let url = dir.appendingPathComponent(manifestName)
        guard let data = try? Data(contentsOf: url),
              let ids  = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return Set(ids)
    }

    private static func saveManifest(_ ids: Set<String>, to dir: URL) {
        let url = dir.appendingPathComponent(manifestName)
        if let data = try? JSONEncoder().encode(Array(ids)) {
            try? data.write(to: url)
        }
    }

    private static func uniqueURL(for filename: String, in dir: URL) -> URL {
        var dest = dir.appendingPathComponent(filename)
        var n = 1
        while FileManager.default.fileExists(atPath: dest.path) {
            let stem = dest.deletingPathExtension().lastPathComponent
            let ext  = dest.pathExtension
            dest = dir.appendingPathComponent("\(stem)_\(n).\(ext)")
            n += 1
        }
        return dest
    }
}
