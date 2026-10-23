/// The three shapes of the menu-bar icon. They differ in shape, not color, so the state reads on any wallpaper and in
/// a hidden menu bar (docs/04).
///
/// Interim SF Symbols until `feat/design-system-foundation` replaces them with the vector assets of docs/04.
enum MenuBarIconShape: Equatable, Sendable {
    case idle, active, needsAttention

    /// The SF Symbol drawn as a template image.
    var symbolName: String {
        switch self {
        case .idle: "display"
        case .active: "eye.slash"
        case .needsAttention: "exclamationmark.triangle"
        }
    }
}
