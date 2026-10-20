import SwiftUI

/// What went wrong with a restore, Retry Restore, and the two-step discard of an unreadable session file.
struct MenuBarAttentionView: View {
    let model: MenuBarViewModel

    var body: some View {
        VStack(alignment: .leading) {
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button {
                    // The view model handles every outcome; the task ends with the intent.
                    Task { await model.retryRestore() }
                } label: {
                    Text(L10n.Menu.retryRestore)
                }
                .disabled(!model.canRetryRestore)
                if model.canDiscardSessionFile, !model.isConfirmingDiscard {
                    Button(action: model.requestDiscardUnreadableSession) {
                        Text(L10n.Menu.discard)
                    }
                }
            }
            if model.isConfirmingDiscard {
                discardConfirmation
            }
        }
    }

    private var message: LocalizedStringResource {
        if case .restoreFailed(_, let actions) = model.presentation {
            return L10n.Menu.restoreFailed(L10n.Actions.list(actions))
        }
        return L10n.Menu.unreadableSessionFile
    }

    private var discardConfirmation: some View {
        VStack(alignment: .leading) {
            Text(L10n.Menu.discardConfirmation)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(action: model.cancelDiscard) {
                    Text(L10n.Menu.discardCancel)
                }
                .keyboardShortcut(.cancelAction)
                Button(role: .destructive) {
                    // The view model handles every outcome; the task ends with the intent.
                    Task { await model.confirmDiscard() }
                } label: {
                    Text(L10n.Menu.discardConfirm)
                }
            }
        }
    }
}
