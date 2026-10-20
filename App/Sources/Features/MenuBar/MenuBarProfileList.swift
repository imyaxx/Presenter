import ModeKit
import SwiftUI

/// The profiles to activate, a profiles problem, or the empty state.
struct MenuBarProfileList: View {
    let model: MenuBarViewModel

    var body: some View {
        VStack(alignment: .leading) {
            if let problem = model.profilesProblem {
                Text(L10n.Menu.profilesProblem(problem))
                    .fixedSize(horizontal: false, vertical: true)
            } else if model.profiles.isEmpty {
                Text(L10n.Menu.noProfilesTitle)
                    .font(.headline)
                Text(L10n.Menu.noProfilesDetail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(model.profiles, id: \.id) { profile in
                    profileButton(profile)
                }
            }
        }
    }

    private func profileButton(_ profile: Profile) -> some View {
        Button {
            // The view model handles every outcome; the task ends with the intent.
            Task { await model.activate(profile) }
        } label: {
            Text(verbatim: profile.name)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .disabled(!model.canActivate)
        .accessibilityHint(Text(L10n.Menu.activateHint))
    }
}
