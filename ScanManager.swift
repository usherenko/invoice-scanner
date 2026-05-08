import Foundation

struct ScanManager {

    static func scan(
        email:     String,
        password:  String,
        month:     String,
        outputDir: String,
        log:       @escaping (String) -> Void
    ) async {
        let client = IMAPClient()

        do {
            log("Connecting to \(IMAP_HOST)…")
            try await client.connect(host: IMAP_HOST, port: IMAP_PORT)

            log("Logging in…")
            try await client.login(user: email, password: password)

            log("Searching inbox for \(month) invoices…")
            try await client.selectInbox()

            let (since, before) = imapDateRange(for: month)
            let ids = try await client.search(
                query: "TEXT \"invoice\" SINCE \"\(since)\" BEFORE \"\(before)\""
            )

            guard !ids.isEmpty else {
                log("No invoice emails found for \(month).")
                try await client.logout()
                return
            }

            log("Found \(ids.count) email(s) — downloading PDFs…\n")

            let outDir = URL(fileURLWithPath: outputDir).appendingPathComponent(month)
            try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

            var savedCount = 0
            for id in ids {
                let rawMessage = try await client.fetchMessage(id: id)
                let pdfs = MIMEParser.extractPDFs(from: rawMessage)

                if pdfs.isEmpty {
                    log("  –  No PDF in message #\(id)")
                } else {
                    for (filename, data) in pdfs {
                        let dest = uniqueURL(for: filename, in: outDir)
                        try data.write(to: dest)
                        log("  ✓  \(dest.lastPathComponent)")
                        savedCount += 1
                    }
                }
            }

            try await client.logout()
            log("\nDone — \(savedCount) PDF(s) saved to \(outputDir)/\(month)")

        } catch {
            log("❌  \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    private static func imapDateRange(for month: String) -> (String, String) {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM"
        df.locale = Locale(identifier: "en_US_POSIX")
        guard let date = df.date(from: month) else { return ("", "") }

        let cal       = Calendar.current
        let nextMonth = cal.date(byAdding: .month, value: 1, to: date)!

        return (imapDateString(date), imapDateString(nextMonth))
    }

    private static func imapDateString(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "dd-MMM-yyyy"
        df.locale = Locale(identifier: "en_US_POSIX")
        return df.string(from: date)
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
