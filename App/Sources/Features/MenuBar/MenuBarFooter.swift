import SwiftUI

/// Show Profiles in Finder, Quit, and the version. No Settings item until the Settings window exists.
struct MenuBarFooter: View {
    let model: MenuBarViewModel
    let version: String?
    let quit: () -> Void

    var body: some View {
        VStack(alignment: .leading) {
            Button {
                // The view model handles every outcome; the task ends with the intent.
                Task { await model.revealProfilesFolder() }
            } label: {
                Text(L10n.Menu.showProfiles)
            }
            .disabled(model.presentation == .unavailable)
            HStack {
                if let version {
                    Text(L10n.Menu.version(version))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: quit) {
                    Text(L10n.Menu.quit)
                }
                .keyboardShortcut("q")
            }
        }
        .buttonStyle(.borderless)
    }
}
