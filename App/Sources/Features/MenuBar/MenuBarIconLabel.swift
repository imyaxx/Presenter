import SwiftUI

/// The menu-bar icon: an SF Symbol drawn as a template image, labelled for VoiceOver (interim, docs/04).
struct MenuBarIconLabel: View {
    let shape: MenuBarIconShape

    var body: some View {
        Image(systemName: shape.symbolName)
            .accessibilityLabel(Text(L10n.Menu.iconLabel(shape)))
    }
}
