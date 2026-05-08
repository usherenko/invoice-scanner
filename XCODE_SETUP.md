# Invoice Scanner — Xcode Setup

## Create the Xcode project

1. Open Xcode → **File → New → Project**
2. Choose **macOS → App** → Next
3. Fill in:
   - Product Name: `Invoice Scanner`
   - Team: your Apple ID (or None)
   - Bundle Identifier: `com.yourname.invoicescanner`
   - Interface: **SwiftUI**
   - Language: **Swift**
4. Save it somewhere (Desktop is fine)

## Add the source files

1. Delete the default `ContentView.swift` Xcode created
2. Drag all 6 `.swift` files from the `InvoiceScannerSwift` folder into the Xcode project navigator
   - Make sure "Copy items if needed" is checked
   - Add to the app target

The files are:
- `InvoiceScannerApp.swift`
- `ContentView.swift`
- `IMAPClient.swift`
- `MIMEParser.swift`
- `ScanManager.swift`
- `KeychainHelper.swift`

## Disable App Sandbox (required for network access)

1. Click the project in the navigator → select the **app target**
2. Go to **Signing & Capabilities**
3. Click the **×** next to **App Sandbox** to remove it

## Build & run

Press **⌘R** — the app window opens.

To export for your friend:
- **Product → Archive**
- Click **Distribute App → Copy App**
- Share the `.app` file — they just double-click it, no install needed
