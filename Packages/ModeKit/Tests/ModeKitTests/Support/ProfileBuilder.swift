import Foundation
import ModeKit

/// Builds valid profiles with overridable fields for tests.
struct ProfileBuilder {
    var id = UUID(uuidString: "6F1E5C0A-2B53-4F0B-9E5C-0D3C1A7B8E21") ?? UUID()
    var name = "Screen share"
    var steps: [ProfileStep] = [.hideDesktopIcons, .hideDock]
    var autoExit: AutoExit?

    func build() -> Profile {
        Profile(id: id, name: name, steps: steps, autoExit: autoExit)
    }
}
