import SwiftUI

private enum Tab { case outgoing, incoming, calculations }

struct ContentView: View {
    @AppStorage("outputDir")   private var outputDir   = "\(NSHomeDirectory())/Invoices"
    @AppStorage("incomingDir") private var incomingDir = "\(NSHomeDirectory())/Invoices/Incoming"
    @ObservedObject private var auth = AuthManager.shared

    @State private var activeTab        = Tab.outgoing
    @State private var isRunning        = false
    @State private var logLines:        [String] = []
    @State private var isScanning       = false
    @State private var incomingResults: [InvoiceResult] = []
    @State private var incomingScanned  = false
    @State private var selectedMonth    = Calendar.current.component(.month, from: Date())
    @State private var selectedYear     = Calendar.current.component(.year,  from: Date())
    @State private var countResults:    [InvoiceResult] = []
    @State private var isCounting       = false

    private let months = ["January","February","March","April","May","June",
                          "July","August","September","October","November","December"]
    private var years: [Int] { (2020...Calendar.current.component(.year, from: Date())).reversed().map { $0 } }
    private var selectedMonthLabel: String { "\(months[selectedMonth - 1]) \(selectedYear)" }
    private var grandTotal: Double { countResults.map(\.total).reduce(0, +) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            tabPicker
            Divider()
            if activeTab == .outgoing {
                if auth.isSignedIn {
                    form
                } else {
                    folderOnlyBar
                    signInView
                }
                if !countResults.isEmpty {
                    invoiceCountView
                }
                Divider()
                logArea
            } else if activeTab == .incoming {
                incomingForm
                incomingResultsArea
            } else {
                calculationsView
            }
        }
        .frame(width: 460)
        .background(
            Color.clear
                .onChange(of: incomingResults.count) { _ in fitWindowToContent() }
                .onChange(of: countResults.count)    { _ in fitWindowToContent() }
                .onChange(of: activeTab)             { _ in fitWindowToContent() }
        )
    }

    // MARK: - Tab picker

    private var tabPicker: some View {
        Picker("", selection: $activeTab) {
            Text("Outgoing").tag(Tab.outgoing)
            Text("Incoming").tag(Tab.incoming)
            Text("Calculations").tag(Tab.calculations)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.richtext")
                .font(.title2)
                .foregroundColor(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("Invoice Scanner")
                    .font(.headline)
                Text(auth.isSignedIn ? "Scanning \(selectedMonthLabel)" : "Sign in to get started")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if auth.isSignedIn {
                Button("Sign out") { auth.signOut() }
                    .buttonStyle(.borderless)
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Sign-in view

    private var signInView: some View {
        VStack(spacing: 16) {
            Image(systemName: "envelope.badge.shield.half.filled")
                .font(.system(size: 40))
                .foregroundColor(.blue)
                .padding(.top, 24)
            Text("Connect your Microsoft 365 account\nto download invoice PDFs.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .font(.callout)
            Button(action: startSignIn) {
                HStack(spacing: 8) {
                    Image(systemName: "person.badge.key.fill")
                    Text("Sign in with Microsoft")
                        .fontWeight(.medium)
                }
                .frame(minWidth: 220)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Outgoing form

    private var form: some View {
        VStack(spacing: 0) {
            formRow(label: "Account") {
                Text(auth.userEmail)
                    .foregroundColor(.secondary)
                    .font(.callout)
                Spacer()
            }
            Divider().padding(.leading, 80)
            formRow(label: "Month") {
                Picker("", selection: $selectedMonth) {
                    ForEach(1...12, id: \.self) { i in Text(months[i - 1]).tag(i) }
                }
                .labelsHidden().frame(width: 120)

                Picker("", selection: $selectedYear) {
                    ForEach(years, id: \.self) { y in Text(String(y)).tag(y) }
                }
                .labelsHidden().frame(width: 80)

                Button("This month") {
                    selectedMonth = Calendar.current.component(.month, from: Date())
                    selectedYear  = Calendar.current.component(.year,  from: Date())
                }
                .buttonStyle(.borderless).foregroundColor(.blue).font(.callout)
            }
            Divider().padding(.leading, 80)
            formRow(label: "Invoice Location") {
                TextField("~/Invoices", text: $outputDir)
                    .textFieldStyle(.roundedBorder)
                Button("…") { chooseFolder() }.buttonStyle(.borderless)
            }

            HStack(spacing: 10) {
                Spacer()
                Button(action: browseAndCount) {
                    HStack(spacing: 6) {
                        if isCounting && !isRunning {
                            ProgressView().scaleEffect(0.6).frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "sum")
                        }
                        Text("Count Folder").fontWeight(.medium)
                    }
                }
                .disabled(isCounting || isRunning)
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button(action: startScan) {
                    HStack(spacing: 6) {
                        if isRunning {
                            ProgressView().scaleEffect(0.6).frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "arrow.down.circle.fill")
                        }
                        Text(isRunning ? "Scanning…" : "Download Invoices").fontWeight(.medium)
                    }
                    .frame(minWidth: 160)
                }
                .disabled(isRunning || isCounting)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Spacer()
            }
            .padding(.vertical, 14)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Folder + count (shown without login)

    private var folderOnlyBar: some View {
        VStack(spacing: 0) {
            formRow(label: "Invoice Location") {
                TextField("~/Invoices", text: $outputDir)
                    .textFieldStyle(.roundedBorder)
                Button("…") { chooseFolder() }.buttonStyle(.borderless)
            }
            HStack {
                Spacer()
                Button(action: browseAndCount) {
                    HStack(spacing: 6) {
                        if isCounting {
                            ProgressView().scaleEffect(0.6).frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "sum")
                        }
                        Text("Count Folder").fontWeight(.medium)
                    }
                }
                .disabled(isCounting)
                .buttonStyle(.bordered)
                .controlSize(.large)
                Spacer()
            }
            .padding(.vertical, 8)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Incoming form

    private var incomingForm: some View {
        VStack(spacing: 0) {
            formRow(label: "Folder") {
                TextField("~/Invoices/Incoming", text: $incomingDir)
                    .textFieldStyle(.roundedBorder)
                Button("…") { chooseIncomingFolder() }.buttonStyle(.borderless)
            }

            HStack {
                Spacer()
                Button(action: startIncomingScan) {
                    HStack(spacing: 6) {
                        if isScanning {
                            ProgressView().scaleEffect(0.6).frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "magnifyingglass.circle.fill")
                        }
                        Text(isScanning ? "Scanning…" : "Scan Folder").fontWeight(.medium)
                    }
                    .frame(minWidth: 160)
                }
                .disabled(isScanning)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.vertical, 14)
                Spacer()
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Incoming results

    private var incomingResultsArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Invoice Totals")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer()
                if !incomingResults.isEmpty {
                    Button { incomingResults = []; incomingScanned = false } label: {
                        Image(systemName: "xmark").font(.caption2)
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 4)

            Divider()

            if incomingResults.isEmpty {
                Text(incomingScanned ? "No invoices found." : "Select a folder and scan.")
                    .foregroundColor(.secondary)
                    .font(.system(.caption, design: .monospaced))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(incomingResults) { result in
                            HStack(spacing: 6) {
                                Image(systemName: result.total > 0 ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                    .font(.caption2)
                                    .foregroundColor(result.total > 0 ? .green : .orange)
                                Text(result.filename)
                                    .font(.system(.caption2, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(result.source)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .frame(width: 76, alignment: .leading)
                                Text(String(format: "€%.2f", result.total))
                                    .font(.system(.caption2, design: .monospaced))
                                    .frame(width: 68, alignment: .trailing)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 2)
                        }
                    }
                }
                .frame(maxHeight: 160)

                Divider()

                HStack {
                    Text("\(incomingResults.count) PDF(s)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "Total: €%.2f", incomingResults.reduce(0) { $0 + $1.total }))
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    // MARK: - Outgoing invoice count results

    private var invoiceCountView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Invoice Totals")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer()
                Button { countResults = [] } label: {
                    Image(systemName: "xmark").font(.caption2)
                }
                .buttonStyle(.borderless)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 4)

            Divider()

            ForEach(countResults) { result in
                HStack(spacing: 6) {
                    Image(systemName: result.total > 0 ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.caption2)
                        .foregroundColor(result.total > 0 ? .green : .orange)
                    Text(result.filename)
                        .font(.system(.caption2, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(result.source)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(width: 76, alignment: .leading)
                    Text(String(format: "€%.2f", result.total))
                        .font(.system(.caption2, design: .monospaced))
                        .frame(width: 68, alignment: .trailing)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 2)
            }

            Divider()

            HStack {
                Text("\(countResults.count) PDF(s)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Text(String(format: "Total: €%.2f", grandTotal))
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    // MARK: - Calculations tab

    private var calculationsView: some View {
        let revenue = incomingResults.map(\.total).reduce(0, +)
        let costs   = countResults.map(\.total).reduce(0, +)
        let profit  = revenue - costs
        let hasData = !incomingResults.isEmpty || !countResults.isEmpty

        return VStack(spacing: 0) {
            // Revenue row
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Revenue (Incoming)")
                        .font(.callout)
                    Text(incomingResults.isEmpty
                         ? "Not scanned — use Incoming tab"
                         : "\(dateRangeLabel(for: incomingResults)) · \(incomingResults.count) invoice(s)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(incomingResults.isEmpty ? "—" : String(format: "€%.2f", revenue))
                    .font(.system(.callout, design: .monospaced))
                    .foregroundColor(incomingResults.isEmpty ? .secondary : .primary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            // Costs row
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Costs (Outgoing)")
                        .font(.callout)
                    Text(countResults.isEmpty
                         ? "Not scanned — use Outgoing tab"
                         : "\(selectedMonthLabel) · \(countResults.count) invoice(s)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(countResults.isEmpty ? "—" : String(format: "€%.2f", costs))
                    .font(.system(.callout, design: .monospaced))
                    .foregroundColor(countResults.isEmpty ? .secondary : .primary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            // Profit row
            HStack {
                Text("Profit")
                    .font(.callout)
                    .fontWeight(.semibold)
                Spacer()
                Text(hasData ? String(format: "€%.2f", profit) : "—")
                    .font(.system(.callout, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(hasData ? (profit >= 0 ? .green : .red) : .secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Spacer()
        }
        .frame(minHeight: 200)
    }

    // MARK: - Shared form row

    private func formRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .frame(width: 66, alignment: .trailing)
                .foregroundColor(.secondary)
                .font(.callout)
            content()
        }
        .padding(.vertical, 8)
    }

    // MARK: - Log area (outgoing)

    private var logArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    if logLines.isEmpty {
                        Text("Ready.")
                            .foregroundColor(.secondary)
                            .font(.system(.caption, design: .monospaced))
                            .padding(8)
                    }
                    ForEach(Array(logLines.enumerated()), id: \.offset) { idx, line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(lineColor(line))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(idx)
                    }
                }
                .padding(10)
            }
            .frame(height: 160)
            .background(Color(NSColor.textBackgroundColor))
            .onChange(of: logLines.count, perform: { _ in
                withAnimation { proxy.scrollTo(logLines.count - 1, anchor: .bottom) }
            })
        }
    }

    private func lineColor(_ line: String) -> Color {
        if line.hasPrefix("❌") { return .red }
        if line.hasPrefix("  ✓") { return .green }
        return .primary
    }

    // MARK: - Actions

    private func startSignIn() {
        logLines = []
        Task {
            do {
                try await auth.signIn()
                appendLog("Signed in as \(auth.userEmail)")
            } catch {
                appendLog("❌  \(error.localizedDescription)")
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories    = true
        panel.canChooseFiles          = false
        panel.allowsMultipleSelection = false
        panel.prompt                  = "Select"
        if panel.runModal() == .OK, let url = panel.url {
            outputDir = url.path
        }
    }

    private func chooseIncomingFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories    = true
        panel.canChooseFiles          = false
        panel.allowsMultipleSelection = false
        panel.prompt                  = "Select"
        if panel.runModal() == .OK, let url = panel.url {
            incomingDir = url.path
        }
    }

    private func browseAndCount() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories    = true
        panel.canChooseFiles          = false
        panel.allowsMultipleSelection = false
        panel.prompt                  = "Count"
        panel.directoryURL            = URL(fileURLWithPath: outputDir)
        if panel.runModal() == .OK, let url = panel.url {
            runCount(on: url)
        }
    }

    private func startScan() {
        logLines     = []
        countResults = []
        isRunning    = true
        let month    = String(format: "%04d-%02d", selectedYear, selectedMonth)
        let dirCopy  = outputDir
        Task {
            await ScanManager.scan(month: month, outputDir: dirCopy, log: appendLog)

            // Auto-count the folder that was just downloaded into
            let downloadedFolder = URL(fileURLWithPath: dirCopy).appendingPathComponent(month)
            if FileManager.default.fileExists(atPath: downloadedFolder.path) {
                await MainActor.run { isCounting = true }
                let results = await Task.detached(priority: .userInitiated) {
                    IncomingScanner.scan(folder: downloadedFolder)
                }.value
                await MainActor.run {
                    self.countResults = results
                    self.isCounting   = false
                    let total = results.map(\.total).reduce(0, +)
                    if !results.isEmpty {
                        self.appendLog("  ✓  \(results.count) PDF(s) counted — Total: €\(String(format: "%.2f", total))")
                    }
                }
            }

            await MainActor.run { isRunning = false }
        }
    }

    private func runCount(on folder: URL) {
        countResults = []
        isCounting   = true
        appendLog("Counting PDFs in \(folder.lastPathComponent)…")
        Task {
            let results = await Task.detached(priority: .userInitiated) {
                IncomingScanner.scan(folder: folder)
            }.value
            await MainActor.run {
                self.countResults = results
                self.isCounting   = false
                let total = results.map(\.total).reduce(0, +)
                if results.isEmpty {
                    self.appendLog("No PDFs found in \(folder.lastPathComponent).")
                } else {
                    self.appendLog("  ✓  \(results.count) PDF(s) — Total: €\(String(format: "%.2f", total))")
                }
            }
        }
    }

    private func startIncomingScan() {
        isScanning      = true
        incomingScanned = false
        incomingResults = []
        let folder = URL(fileURLWithPath: incomingDir)
        Task {
            let results = await Task.detached { IncomingScanner.scan(folder: folder) }.value
            incomingResults = results
            incomingScanned = true
            isScanning      = false
        }
    }

    private func dateRangeLabel(for results: [InvoiceResult]) -> String {
        let dates = results.compactMap(\.date).sorted()
        guard let first = dates.first, let last = dates.last else {
            return URL(fileURLWithPath: incomingDir).lastPathComponent
        }
        let df = DateFormatter()
        df.dateFormat = "MMM yyyy"
        let firstStr = df.string(from: first)
        let lastStr  = df.string(from: last)
        if firstStr == lastStr { return firstStr }
        let shortDf = DateFormatter()
        shortDf.dateFormat = "MMM"
        return "\(shortDf.string(from: first))–\(lastStr)"
    }

    private func fitWindowToContent() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard let window = NSApp.windows.first(where: { $0.isKeyWindow }) ?? NSApp.windows.first,
                  let contentView = window.contentView else { return }
            window.setContentSize(contentView.fittingSize)
        }
    }

    private nonisolated func appendLog(_ msg: String) {
        DispatchQueue.main.async { self.logLines.append(msg) }
    }
}
