import SwiftUI

/// Content of the menu-bar popover: product identity and the Quit command.
struct MenuBarView: View {
    let productName: String
    let version: String?
    let quit: () -> Void

    var body: some View {
        VStack(alignment: .leading) {
            Text(verbatim: productName)
                .font(.headline)
            if let version {
                Text(L10n.Menu.version(version))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Divider()
            Button(action: quit) {
                Text(L10n.Menu.quit)
            }
            .keyboardShortcut("q")
        }
        .padding()
    }
}
