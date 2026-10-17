import Foundation

extension L10n {
    /// Strings shown in the menu-bar popover.
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
    }
}
