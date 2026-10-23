import Foundation
import ModeKit

extension L10n {
    /// Names of the settings Presenter changes, for sentences and lists.
    enum Actions {
        static func name(_ action: ActionIdentifier) -> LocalizedStringResource {
            switch action {
            case .desktopIcons: LocalizedStringResource("action.desktopIcons", defaultValue: "Desktop icons")
            case .dock: LocalizedStringResource("action.dock", defaultValue: "Dock")
            case .menuBar: LocalizedStringResource("action.menuBar", defaultValue: "Menu bar")
            case .hideApps: LocalizedStringResource("action.hideApps", defaultValue: "Hiding apps")
            case .wallpaper: LocalizedStringResource("action.wallpaper", defaultValue: "Wallpaper")
            }
        }

        /// The names joined as a localized list, for example "Dock and Wallpaper".
        static func list(_ actions: [ActionIdentifier]) -> String {
            actions.map { String(localized: name($0)) }.formatted(.list(type: .and))
        }
    }
}
