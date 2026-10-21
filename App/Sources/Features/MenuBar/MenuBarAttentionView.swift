import SwiftUI

/// What went wrong with a restore, Retry Restore, and the two-step discard of an unreadable session file. The two
/// confirmation buttons share a row; ``MenuBarLabelWidthTests`` checks that they fit in every language.
struct MenuBarAttentionView: View {
    let model: MenuBarViewModel

    var body: some View {
        VStack(alignment: .leading) {
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
            // One button per row at full width: in Russian the two labels do not fit side by side (Q9, 2026-10-21).
            Button {
                // The view model handles every outcome; the task ends with the intent.
                Task { await model.retryRestore() }
            } label: {
                fullWidthLabel(L10n.Menu.retryRestore)
            }
            .disabled(!model.canRetryRestore)
            if model.canDiscardSessionFile, !model.isConfirmingDiscard {
                Button(action: model.requestDiscardUnreadableSession) {
                    fullWidthLabel(L10n.Menu.discard)
                }
            }
            if model.isConfirmingDiscard {
                discardConfirmation
            }
        }
    }

    private func fullWidthLabel(_ title: LocalizedStringResource) -> some View {
        Text(title)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
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
