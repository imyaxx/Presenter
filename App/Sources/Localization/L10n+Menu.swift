import Foundation

extension L10n {
    /// Strings shown in the menu-bar popover and on the menu-bar icon.
    enum Menu {
        static let quit = LocalizedStringResource(
            "menu.quit",
            defaultValue: "Quit",
            comment: "Menu-bar popover button that terminates the app.",
        )

        static func version(_ version: String) -> LocalizedStringResource {
            LocalizedStringResource(
                "menu.version",
                defaultValue: "Version \(version)",
                comment: "Menu-bar popover line under the product name. The argument is the app version, e.g. 1.2.0.",
            )
        }

        static let inactive = LocalizedStringResource("menu.state.inactive", defaultValue: "Inactive")
        static let restoring = LocalizedStringResource("menu.state.restoring", defaultValue: "Restoring…")
        static let needsAttention = LocalizedStringResource(
            "menu.state.needsAttention",
            defaultValue: "Needs attention",
        )
        static let unavailable = LocalizedStringResource(
            "menu.state.unavailable",
            defaultValue: "Presenter could not start",
        )
        static let unavailableDetail = LocalizedStringResource(
            "menu.unavailable.detail",
            defaultValue: "Nothing on your Mac was changed. Quit and open Presenter again.",
        )
        static let elapsed = LocalizedStringResource("menu.elapsed", defaultValue: "Active for")

        static func applying(_ profileName: String) -> LocalizedStringResource {
            LocalizedStringResource("menu.state.applying", defaultValue: "Applying \(profileName)…")
        }

        static func active(_ profileName: String) -> LocalizedStringResource {
            LocalizedStringResource("menu.state.active", defaultValue: "Active: \(profileName)")
        }

        static func rollingBack(_ profileName: String) -> LocalizedStringResource {
            LocalizedStringResource("menu.state.rollingBack", defaultValue: "Undoing \(profileName)…")
        }

        static let noProfilesTitle = LocalizedStringResource(
            "menu.profiles.empty.title",
            defaultValue: "No profiles yet",
        )
        static let noProfilesDetail = LocalizedStringResource(
            "menu.profiles.empty.detail",
            defaultValue: """
                Profiles will be created in Settings in a later version. \
                For now, add them to profiles.json in the profiles folder.
                """,
        )
        static let activateHint = LocalizedStringResource(
            "menu.profile.activate.hint",
            defaultValue: "Activates the profile",
        )
        static let stop = LocalizedStringResource("menu.stop", defaultValue: "Stop")
        static let retryRestore = LocalizedStringResource("menu.retryRestore", defaultValue: "Retry Restore")
        static let discard = LocalizedStringResource("menu.discard", defaultValue: "Discard Session File…")
        static let discardConfirmation = LocalizedStringResource(
            "menu.discard.confirmation",
            defaultValue: "The session file will be deleted. Settings it describes will not be restored.",
        )
        static let discardConfirm = LocalizedStringResource("menu.discard.confirm", defaultValue: "Delete")
        static let discardCancel = LocalizedStringResource("menu.discard.cancel", defaultValue: "Cancel")
        static let showProfiles = LocalizedStringResource("menu.showProfiles", defaultValue: "Show Profiles in Finder")
        static let dismissNotice = LocalizedStringResource("menu.notice.dismiss", defaultValue: "Dismiss")
        static let unreadableSessionFile = LocalizedStringResource(
            "menu.attention.unreadable",
            defaultValue: "The session file could not be read. Presenter left it untouched.",
        )

        static func restoreFailed(_ actions: String) -> LocalizedStringResource {
            LocalizedStringResource("menu.attention.restoreFailed", defaultValue: "Could not restore: \(actions).")
        }

        static func iconLabel(_ shape: MenuBarIconShape) -> LocalizedStringResource {
            switch shape {
            case .idle: LocalizedStringResource("menu.icon.idle", defaultValue: "Presenter, inactive")
            case .active: LocalizedStringResource("menu.icon.active", defaultValue: "Presenter, active")
            case .needsAttention:
                LocalizedStringResource("menu.icon.needsAttention", defaultValue: "Presenter, needs attention")
            }
        }

        static func profilesProblem(_ problem: ProfilesProblem) -> LocalizedStringResource {
            switch problem {
            case .corrupted:
                LocalizedStringResource(
                    "menu.profiles.problem.corrupted",
                    defaultValue: "profiles.json could not be read. It was left unchanged.",
                )
            case .newerVersion:
                LocalizedStringResource(
                    "menu.profiles.problem.newerVersion",
                    defaultValue: "profiles.json was saved by a newer version of Presenter. It was left unchanged.",
                )
            case .unreadable:
                LocalizedStringResource(
                    "menu.profiles.problem.unreadable",
                    defaultValue: "The profiles folder could not be read.",
                )
            }
        }
    }
}
