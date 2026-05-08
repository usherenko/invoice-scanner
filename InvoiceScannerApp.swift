import SwiftUI

let IMAP_HOST: String  = "imap.secureserver.net"
let IMAP_PORT: UInt16  = 993

@main
struct InvoiceScannerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 460, height: 520)
    }
}
