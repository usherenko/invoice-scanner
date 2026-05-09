import SwiftUI

struct ContentView: View {
    @AppStorage("email")     private var email     = ""
    @AppStorage("outputDir") private var outputDir = "\(NSHomeDirectory())/Invoices"

    @State private var password     = ""
    @State private var isRunning    = false
    @State private var logLines: [String] = []
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
            form
            Divider()
            logArea
        }
        .frame(width: 460)
        .onAppear { password = KeychainHelper.load(account: email) ?? "" }
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.richtext")
                .font(.title2)
                .foregroundColor(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("Invoice Scanner")
                    .font(.headline)
                Text("Scanning \(selectedMonthLabel)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var form: some View {
        VStack(spacing: 0) {
            formRow(label: "Email") {
                TextField("you@yourdomain.com", text: $email)
                    .textFieldStyle(.roundedBorder)
            }
            Divider().padding(.leading, 80)
            formRow(label: "Password") {
                SecureField("••••••••", text: $password)
                    .textFieldStyle(.roundedBorder)
            }
            Divider().padding(.leading, 80)
            formRow(label: "Month") {
                Picker("", selection: $selectedMonth) {
                    ForEach(1...12, id: \.self) { i in
                        Text(months[i - 1]).tag(i)
                    }
                }
                .labelsHidden()
                .frame(width: 120)

                Picker("", selection: $selectedYear) {
                    ForEach(years, id: \.self) { y in
                        Text(String(y)).tag(y)
                    }
                }
                .labelsHidden()
                .frame(width: 80)

                Button("This month") {
                    selectedMonth = Calendar.current.component(.month, from: Date())
                    selectedYear  = Calendar.current.component(.year,  from: Date())
                }
                .buttonStyle(.borderless)
                .foregroundColor(.blue)
                .font(.callout)
            }
            Divider().padding(.leading, 80)
            formRow(label: "Save to") {
                TextField("~/Invoices", text: $outputDir)
                    .textFieldStyle(.roundedBorder)
                Button("…") { chooseFolder() }
                    .buttonStyle(.borderless)
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
                        Text(isRunning ? "Scanning…" : "Download Invoices")
                            .fontWeight(.medium)
                    }
                    .frame(minWidth: 160)
                }
                .disabled(isRunning || email.isEmpty || password.isEmpty)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.vertical, 14)
                Spacer()
            }
        }
        .padding(.horizontal, 16)
    }

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
            .frame(height: 180)
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

    private func startScan() {
        KeychainHelper.save(password: password, account: email)
        logLines  = []
        isRunning = true

        let emailCopy = email
        let passCopy  = password
        let dirCopy   = outputDir
        let month     = String(format: "%04d-%02d", selectedYear, selectedMonth)

        Task {
            await ScanManager.scan(
                email:     emailCopy,
                password:  passCopy,
                month:     month,
                outputDir: dirCopy,
                log:       appendLog
            )
            await MainActor.run { isRunning = false }
        }
    }

    private nonisolated func appendLog(_ msg: String) {
        DispatchQueue.main.async { self.logLines.append(msg) }
    }
}
