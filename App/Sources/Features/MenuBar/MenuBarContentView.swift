import SwiftUI

/// The middle of the popover: what the user can do in the current state.
struct MenuBarContentView: View {
    let model: MenuBarViewModel

    var body: some View {
        switch model.presentation {
        case .unavailable:
            Text(L10n.Menu.unavailableDetail)
                .fixedSize(horizontal: false, vertical: true)
        case .idle:
            MenuBarProfileList(model: model)
        case .active(let session):
            MenuBarActiveSessionView(session: session, canStop: model.canStop) {
                // The view model handles every outcome; the task ends with the intent.
                Task { await model.deactivate() }
            }
        case .restoreFailed, .unreadableSessionFile:
            MenuBarAttentionView(model: model)
        case .recoveringAtLaunch, .applying, .restoring, .rollingBack:
            ProgressView()
                .controlSize(.small)
        }
    }
}
