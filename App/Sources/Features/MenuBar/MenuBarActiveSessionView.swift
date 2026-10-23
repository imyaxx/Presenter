import ModeKit
import SwiftUI

/// The active profile with its Stop button; it replaces the profile list while a session is active. The profile name
/// wraps; Stop keeps its full label.
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
            .fixedSize()
            .disabled(!canStop)
            .keyboardShortcut(.defaultAction)
        }
    }
}
