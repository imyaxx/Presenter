import ModeKit
import SwiftUI

/// The active profile with its Stop button; it replaces the profile list while a session is active.
struct MenuBarActiveSessionView: View {
    let session: ActiveSession
    let canStop: Bool
    let stop: () -> Void

    var body: some View {
        HStack {
            Text(verbatim: session.profileName)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(action: stop) {
                Text(L10n.Menu.stop)
            }
            .disabled(!canStop)
            .keyboardShortcut(.defaultAction)
        }
    }
}
