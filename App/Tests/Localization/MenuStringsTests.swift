import Foundation
import ModeKit
import Testing

@testable import PresenterApp

/// Every notice, state and action resolves to catalog text, not to its key, with the expected number of lines.
struct MenuStringsTests {
    static let notices: [MenuBarNotice] = [
        .activationFailed(.dock, .nothingChanged),
        .activationFailed(.dock, .undone),
        .activationFailed(.wallpaper, .partlyUndone),
        .invalidProfile,
        .notReady,
        .sessionFileNotSaved,
        .sessionFileNotRemoved,
        .keptUserChanges([.dock, .wallpaper]),
        .recoveredAfterInterruption(kept: []),
        .recoveredAfterInterruption(kept: [.menuBar]),
        .profilesFolderUnavailable,
        .discardFailed,
    ]

    private static func isCatalogText(_ text: String) -> Bool {
        !text.isEmpty && !text.hasPrefix("notice.") && !text.hasPrefix("menu.") && !text.hasPrefix("action.")
    }

    @Test(arguments: notices)
    func everyNoticeHasCatalogText(notice: MenuBarNotice) {
        let lines = L10n.Notices.lines(notice)

        #expect(!lines.isEmpty)
        #expect(lines.allSatisfy(Self.isCatalogText))
    }

    @Test
    func aDockFailureAddsThePermissionLineAndAKeptListAddsItsLine() {
        #expect(L10n.Notices.lines(.activationFailed(.dock, .undone)).count == 2)
        #expect(L10n.Notices.lines(.activationFailed(.menuBar, .undone)).count == 1)
        #expect(L10n.Notices.lines(.recoveredAfterInterruption(kept: [])).count == 1)
        #expect(L10n.Notices.lines(.recoveredAfterInterruption(kept: [.dock])).count == 2)
    }

    @Test
    func aFailureNamesItsAction() {
        let dock = String(localized: L10n.Actions.name(.dock))

        #expect(L10n.Notices.lines(.activationFailed(.dock, .undone)).first?.contains(dock) == true)
    }

    @Test(arguments: ActionIdentifier.allCases)
    func everyActionHasAName(action: ActionIdentifier) {
        #expect(Self.isCatalogText(String(localized: L10n.Actions.name(action))))
    }

    @Test
    func aListJoinsEveryName() {
        let list = L10n.Actions.list([.dock, .wallpaper])

        #expect(list.contains(String(localized: L10n.Actions.name(.dock))))
        #expect(list.contains(String(localized: L10n.Actions.name(.wallpaper))))
    }

    @Test
    func menuStatesIconsAndProblemsHaveCatalogText() {
        let resources: [LocalizedStringResource] = [
            L10n.Menu.inactive, L10n.Menu.restoring, L10n.Menu.needsAttention, L10n.Menu.unavailable,
            L10n.Menu.unavailableDetail, L10n.Menu.elapsed, L10n.Menu.applying("Quick"), L10n.Menu.active("Quick"),
            L10n.Menu.rollingBack("Quick"), L10n.Menu.noProfilesTitle, L10n.Menu.noProfilesDetail,
            L10n.Menu.activateHint, L10n.Menu.stop, L10n.Menu.retryRestore, L10n.Menu.discard,
            L10n.Menu.discardConfirmation, L10n.Menu.discardConfirm, L10n.Menu.discardCancel, L10n.Menu.showProfiles,
            L10n.Menu.dismissNotice, L10n.Menu.unreadableSessionFile, L10n.Menu.restoreFailed("Dock"),
            L10n.Menu.iconLabel(.idle), L10n.Menu.iconLabel(.active), L10n.Menu.iconLabel(.needsAttention),
            L10n.Menu.profilesProblem(.corrupted), L10n.Menu.profilesProblem(.newerVersion),
            L10n.Menu.profilesProblem(.unreadable),
        ]

        for resource in resources {
            #expect(Self.isCatalogText(String(localized: resource)))
        }
        #expect(String(localized: L10n.Menu.active("Quick")).contains("Quick"))
    }
}
