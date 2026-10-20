#if DEBUG
import Foundation
import ModeKit

/// Restricts the `hideApps` step to the applications the protocol opened itself (`--hide-only`, ADR-042).
///
/// The exclusions become every running regular application except the listed ones, so nothing else can be hidden.
/// A profile with a `hideApps` step and no restriction is refused: it could hide the user's own applications.
enum HideOnlySelection {
    static let profileID = UUID(uuidString: "A0000000-0000-4000-8000-0000000000FF") ?? UUID()
    static let profileName = "hide-only"

    static func exclusions(
        running: [RunningApplication],
        hiding allowed: Set<BundleIdentifier>,
    ) -> Set<BundleIdentifier> {
        Set(running.map(\.bundleIdentifier)).subtracting(allowed)
    }

    /// A profile with a single `hideApps` step that can hide only `allowed`.
    static func profile(running: [RunningApplication], hiding allowed: Set<BundleIdentifier>) -> Profile {
        Profile(
            id: profileID,
            name: profileName,
            steps: [.hideApps(exclusions: exclusions(running: running, hiding: allowed))],
            autoExit: nil,
        )
    }

    /// `profile` with its `hideApps` step restricted to `allowed`; with `allowed` nil, the profile unchanged if it has
    /// no `hideApps` step.
    ///
    /// - Throws: ``HideOnlySelectionError/unrestrictedHideApps`` for a `hideApps` step without `allowed`.
    static func restricting(
        _ profile: Profile,
        running: [RunningApplication],
        hiding allowed: Set<BundleIdentifier>?,
    ) throws(HideOnlySelectionError) -> Profile {
        let steps = try profile.steps.map { step throws(HideOnlySelectionError) -> ProfileStep in
            guard case .hideApps = step else {
                return step
            }
            guard let allowed else {
                throw HideOnlySelectionError.unrestrictedHideApps
            }
            return .hideApps(exclusions: exclusions(running: running, hiding: allowed))
        }
        return Profile(id: profile.id, name: profile.name, steps: steps, autoExit: profile.autoExit)
    }
}

enum HideOnlySelectionError: Error, Equatable, Sendable, CustomStringConvertible {
    case unrestrictedHideApps

    var description: String {
        "the profile hides applications: pass --hide-only with the applications the protocol opened"
    }
}
#endif
