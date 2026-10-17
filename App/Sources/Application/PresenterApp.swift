import AppKit
import SwiftUI

@main
struct PresenterApp: App {
    private static let menuBarSymbolName = "display"

    private let bundleMetadata = BundleMetadata(bundle: .main)

    var body: some Scene {
        MenuBarExtra(bundleMetadata.displayName, systemImage: Self.menuBarSymbolName) {
            MenuBarView(
                productName: bundleMetadata.displayName,
                version: bundleMetadata.version,
                quit: { NSApplication.shared.terminate(nil) },
            )
        }
        .menuBarExtraStyle(.window)
    }
}
