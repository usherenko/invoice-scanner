import SwiftUI

private enum Tab { case outgoing, incoming }

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
    @State private var selectedMonth = Calendar.current.component(.month, from: Date())
    @State private var selectedYear  = Calendar.current.component(.year,  from: Date())

    private let months = ["January","February","March","April","May","June",
                          "July","August","September","October","November","December"]
    private var years: [Int] { (2020...Calendar.current.component(.year, from: Date())).reversed().map { $0 } }
    private var selectedMonthLabel: String { "\(months[selectedMonth - 1]) \(selectedYear)" }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            tabPicker
            Divider()
            if activeTab == .outgoing {
                if auth.isSignedIn { form } else { signInView }
            } else {
                incomingForm
            }
            Divider()
            if activeTab == .outgoing {
                logArea
            } else {
                incomingResultsArea
            }
        }
        .frame(width: 460)
    }

    // MARK: - Tab picker

    private var tabPicker: some View {
        Picker("", selection: $activeTab) {
            Text("Outgoing").tag(Tab.outgoing)
            Text("Incoming").tag(Tab.incoming)
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
            formRow(label: "Save to") {
                TextField("~/Invoices", text: $outputDir)
                    .textFieldStyle(.roundedBorder)
                Button("…") { chooseFolder() }.buttonStyle(.borderless)
            }

            HStack {
                Spacer()
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
                .disabled(isRunning)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.vertical, 14)
                Spacer()
            }
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
        VStack(spacing: 0) {
            if incomingResults.isEmpty {
                Text(incomingScanned ? "No invoices found." : "Select a folder and scan.")
                    .foregroundColor(.secondary)
                    .font(.system(.caption, design: .monospaced))
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(incomingResults) { result in
                            HStack(spacing: 8) {
                                Text(result.filename)
                                    .font(.system(.caption, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Text(result.source)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(width: 90, alignment: .trailing)
                                Text(String(format: "€%.2f", result.total))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.green)
                                    .frame(width: 64, alignment: .trailing)
                            }
                            .padding(.horizontal, 10)
                        }
                    }
                    .padding(.vertical, 6)
                }
                Divider()
                HStack {
                    Spacer()
                    Text("Total")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text(String(format: "€%.2f", incomingResults.reduce(0) { $0 + $1.total }))
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                        .frame(width: 64, alignment: .trailing)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            }
        }
        .frame(height: 160)
        .background(Color(NSColor.textBackgroundColor))
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

    private func startScan() {
        logLines  = []
        isRunning = true
        let month   = String(format: "%04d-%02d", selectedYear, selectedMonth)
        let dirCopy = outputDir
        Task {
            await ScanManager.scan(month: month, outputDir: dirCopy, log: appendLog)
            await MainActor.run { isRunning = false }
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

    private nonisolated func appendLog(_ msg: String) {
        DispatchQueue.main.async { self.logLines.append(msg) }
    }
}
