import AppKit
import SwiftUI

/// The menu bar app. Started by ``PresenterMain``; ``AppDelegate`` owns the session graph.
struct PresenterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra(isInserted: .constant(appDelegate.environment != nil)) {
            if let environment = appDelegate.environment {
                MenuBarView(
                    model: environment.viewModel,
                    version: environment.version,
                    quit: { NSApplication.shared.terminate(nil) },
                )
            }
        } label: {
            MenuBarIconLabel(shape: appDelegate.environment?.viewModel.iconShape ?? .idle)
        }
        .menuBarExtraStyle(.window)
    }
}
