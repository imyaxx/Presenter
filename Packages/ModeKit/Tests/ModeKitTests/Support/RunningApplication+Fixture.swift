import ModeKit

/// Readable construction of ``RunningApplication`` values for tests, without boolean arguments.
extension RunningApplication {
    enum Visibility: Sendable {
        case visible, hidden
    }

    enum Role: Sendable {
        case background, frontmost, thisApplication
    }

    static func fixture(
        _ bundleIdentifier: BundleIdentifier,
        _ visibility: Visibility = .visible,
        role: Role = .background,
    ) -> RunningApplication {
        RunningApplication(
            bundleIdentifier: bundleIdentifier,
            isHidden: visibility == .hidden,
            isFrontmost: role == .frontmost,
            isThisApplication: role == .thisApplication,
        )
    }

    func with(_ visibility: Visibility) -> RunningApplication {
        RunningApplication(
            bundleIdentifier: bundleIdentifier,
            isHidden: visibility == .hidden,
            isFrontmost: isFrontmost,
            isThisApplication: isThisApplication,
        )
    }
}
