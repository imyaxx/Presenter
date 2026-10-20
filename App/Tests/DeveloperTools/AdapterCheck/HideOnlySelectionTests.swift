#if DEBUG
import Foundation
import ModeKit
import Testing

@testable import PresenterApp

struct HideOnlySelectionTests {
    private let textEdit: BundleIdentifier
    private let calculator: BundleIdentifier
    private let running: [RunningApplication]

    init() throws {
        textEdit = try BundleIdentifier("com.apple.TextEdit")
        calculator = try BundleIdentifier("com.apple.calculator")
        running = [
            try Stub.application("com.apple.TextEdit"),
            try Stub.application("com.apple.calculator"),
            try Stub.application("com.example.mail"),
            try Stub.application("com.example.editor", frontmost: .frontmost),
        ]
    }

    @Test
    func everyRunningApplicationExceptTheListedOnesIsExcluded() throws {
        let exclusions = HideOnlySelection.exclusions(running: running, hiding: [textEdit, calculator])

        #expect(exclusions == [try BundleIdentifier("com.example.mail"), try BundleIdentifier("com.example.editor")])
    }

    @Test
    func theHideOnlyProfileHasOneRestrictedStep() throws {
        let profile = HideOnlySelection.profile(running: running, hiding: [textEdit])

        #expect(profile.name == "hide-only")
        #expect(profile.steps == [.hideApps(exclusions: Set(running.map(\.bundleIdentifier)).subtracting([textEdit]))])
    }

    @Test
    func aProfileIsRestrictedOnlyInItsHideAppsStep() throws {
        let profile = Profile(id: UUID(), name: "all", steps: [.hideDock, .hideApps(exclusions: [])], autoExit: nil)

        let restricted = try HideOnlySelection.restricting(profile, running: running, hiding: [calculator])

        #expect(restricted.steps.first == .hideDock)
        #expect(
            restricted.steps.last
                == .hideApps(exclusions: Set(running.map(\.bundleIdentifier)).subtracting([calculator])))
    }

    @Test
    func aProfileWithoutHideAppsNeedsNoRestriction() throws {
        let profile = Profile(id: UUID(), name: "dock", steps: [.hideDock], autoExit: nil)

        #expect(try HideOnlySelection.restricting(profile, running: running, hiding: nil) == profile)
    }

    @Test
    func anUnrestrictedHideAppsStepIsRefused() {
        let profile = Profile(id: UUID(), name: "all", steps: [.hideApps(exclusions: [])], autoExit: nil)

        #expect(throws: HideOnlySelectionError.unrestrictedHideApps) {
            try HideOnlySelection.restricting(profile, running: running, hiding: nil)
        }
    }
}
#endif
