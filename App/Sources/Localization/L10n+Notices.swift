import Foundation

extension L10n {
    /// Notices shown under the popover's state line.
    enum Notices {
        /// The lines of a notice, first the main sentence.
        static func lines(_ notice: MenuBarNotice) -> [String] {
            switch notice {
            case .activationFailed(let action, let outcome):
                let first = String(localized: activationFailed(String(localized: Actions.name(action)), outcome))
                return notice.mentionsAutomationPermission ? [first, String(localized: automationPermission)] : [first]
            case .keptUserChanges(let actions):
                return [String(localized: keptUserChanges(Actions.list(actions)))]
            case .recoveredAfterInterruption(let kept):
                let first = String(localized: recovered)
                return kept.isEmpty ? [first] : [first, String(localized: keptUserChanges(Actions.list(kept)))]
            case .invalidProfile: return [String(localized: invalidProfile)]
            case .notReady: return [String(localized: notReady)]
            case .sessionFileNotSaved: return [String(localized: sessionFileNotSaved)]
            case .sessionFileNotRemoved: return [String(localized: sessionFileNotRemoved)]
            case .profilesFolderUnavailable: return [String(localized: profilesFolderUnavailable)]
            case .discardFailed: return [String(localized: discardFailed)]
            }
        }

        private static func activationFailed(
            _ action: String,
            _ outcome: MenuBarNotice.ActivationOutcome,
        ) -> LocalizedStringResource {
            switch outcome {
            case .nothingChanged:
                LocalizedStringResource(
                    "notice.activation.nothingChanged",
                    defaultValue: "\(action): the current setting could not be read. Nothing was changed.",
                )
            case .undone:
                LocalizedStringResource(
                    "notice.activation.undone",
                    defaultValue: "\(action) could not be applied. Everything was undone.",
                )
            case .partlyUndone:
                LocalizedStringResource(
                    "notice.activation.partlyUndone",
                    defaultValue: "\(action) could not be applied, and some changes could not be undone.",
                )
            }
        }

        private static let automationPermission = LocalizedStringResource(
            "notice.automationPermission",
            defaultValue: """
                Presenter needs permission to control System Events: \
                System Settings > Privacy & Security > Automation.
                """,
        )
        private static let recovered = LocalizedStringResource(
            "notice.recovered",
            defaultValue: "Restored your settings after an interrupted session.",
        )

        private static func keptUserChanges(_ actions: String) -> LocalizedStringResource {
            LocalizedStringResource("notice.keptUserChanges", defaultValue: "Left as you changed them: \(actions).")
        }

        private static let invalidProfile = LocalizedStringResource(
            "notice.invalidProfile",
            defaultValue: "This profile is not valid. Check it in profiles.json.",
        )
        private static let notReady = LocalizedStringResource(
            "notice.notReady",
            defaultValue: "Presenter is still restoring. Try again in a moment.",
        )
        private static let sessionFileNotSaved = LocalizedStringResource(
            "notice.sessionFileNotSaved",
            defaultValue: "The session file could not be saved. Nothing was changed.",
        )
        private static let sessionFileNotRemoved = LocalizedStringResource(
            "notice.sessionFileNotRemoved",
            defaultValue: "Your settings were restored, but the session file could not be removed.",
        )
        private static let profilesFolderUnavailable = LocalizedStringResource(
            "notice.profilesFolderUnavailable",
            defaultValue: "The profiles folder could not be opened.",
        )
        private static let discardFailed = LocalizedStringResource(
            "notice.discardFailed",
            defaultValue: "The session file could not be deleted.",
        )
    }
}
