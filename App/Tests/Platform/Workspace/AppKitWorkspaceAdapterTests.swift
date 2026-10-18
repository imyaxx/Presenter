import AppKit
import Foundation
import ModeKit
import Testing

@testable import PresenterApp

/// Reads the live system only: running applications and screens. Never hides, unhides or sets a desktop image; the
/// `setDesktopImage` tests fail before the system is asked (ADR-040).
@Suite(.timeLimit(.minutes(1)))
struct AppKitWorkspaceAdapterTests {
    private let adapter = AppKitWorkspaceAdapter()

    @Test
    func runningApplicationsHaveValidIdentifiersAndAtMostOneIsThisApplication() async {
        let applications = await adapter.runningApplications()

        for application in applications {
            #expect((try? BundleIdentifier(application.bundleIdentifier.rawValue)) != nil)
        }
        #expect(applications.filter(\.isThisApplication).count <= 1)
        #expect(applications.filter(\.isFrontmost).count <= 1)
    }

    @Test
    func anApplicationThatIsNotRunningIsReportedWithoutAnyRequest() async throws {
        let absent = try BundleIdentifier("dev.imyaxx.presenter.tests.not-running")

        #expect(await adapter.hide(absent) == .notRunning)
        #expect(await adapter.unhide(absent) == .notRunning)
    }

    @Test(arguments: [
        ([Bool](), ApplicationVisibilityChange.notRunning),
        ([false, false], .refused),
        ([false, true], .changed),
        ([true], .changed),
    ])
    func everyInstanceDecidesTheOutcome(results: [Bool], expected: ApplicationVisibilityChange) {
        #expect(AppKitWorkspaceAdapter.visibilityChange(fromRequestResults: results) == expected)
    }

    @Test
    @MainActor
    func everyConnectedScreenMapsToItsDisplayAndBack() async {
        let screens = NSScreen.screens

        let displays = await adapter.connectedDisplays()

        #expect(displays.count == screens.compactMap(DisplayIdentifierMapping.identifier(of:)).count)
        for screen in screens {
            let display = DisplayIdentifierMapping.identifier(of: screen)
            #expect(display != nil)
            if let display {
                #expect(DisplayIdentifierMapping.screen(for: display) === screen)
            }
        }
    }

    @Test
    func anUnknownDisplayFailsBeforeTheSystemIsAsked() async throws {
        let image = FileManager.default.temporaryDirectory.appending(path: "presenter-tests-\(UUID().uuidString).png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: image)
        defer { try? FileManager.default.removeItem(at: image) }
        let unknown = DisplayIdentifier(uuid: UUID())

        await #expect(throws: WorkspaceError.displayNotFound(unknown)) {
            try await adapter.setDesktopImage(image, on: unknown)
        }
    }

    @Test
    func aMissingImageFailsBeforeTheSystemIsAsked() async {
        let missing = FileManager.default.temporaryDirectory.appending(
            path: "presenter-missing-\(UUID().uuidString).png")

        await #expect(throws: WorkspaceError.imageNotFound(fileName: missing.lastPathComponent)) {
            try await adapter.setDesktopImage(missing, on: DisplayIdentifier(uuid: UUID()))
        }
    }

    @Test
    func errorsNameTheFileNotThePath() {
        let display = DisplayIdentifier(uuid: UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID())

        #expect(WorkspaceError.imageNotFound(fileName: "a.png").description == "Desktop image not found: a.png")
        #expect(
            WorkspaceError.displayNotFound(display).description
                == "No connected display 00000000-0000-0000-0000-000000000001")
    }
}
