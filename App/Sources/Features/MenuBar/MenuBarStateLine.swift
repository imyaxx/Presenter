import ModeKit
import SwiftUI

/// The first line of the popover: the session state, and the elapsed time while a profile is active.
struct MenuBarStateLine: View {
    let presentation: MenuBarPresentation

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            if case .active(let session) = presentation {
                Text(session.startedAt, style: .timer)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text(L10n.Menu.elapsed))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var title: LocalizedStringResource {
        switch presentation {
        case .unavailable: L10n.Menu.unavailable
        case .recoveringAtLaunch, .restoring: L10n.Menu.restoring
        case .idle: L10n.Menu.inactive
        case .applying(let name): L10n.Menu.applying(name)
        case .active(let session): L10n.Menu.active(session.profileName)
        case .rollingBack(let name): L10n.Menu.rollingBack(name)
        case .restoreFailed, .unreadableSessionFile: L10n.Menu.needsAttention
        }
    }
}
