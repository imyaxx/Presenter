#if DEBUG
import Foundation
import ModeKit

/// A ``WorkspaceAdapter`` that forwards every call to the real adapter and writes each `hide` and `unhide` result as
/// a JSON line, so the protocol records what `NSRunningApplication` returned (ADR-042).
struct RecordingWorkspaceAdapter: WorkspaceAdapter {
    struct Line: Encodable, Equatable, Sendable {
        let type = "workspace"
        let operation: String
        let bundleIdentifier: String
        let result: String
    }

    private let wrapped: any WorkspaceAdapter
    private let output: CheckOutput

    init(wrapping wrapped: any WorkspaceAdapter, output: CheckOutput) {
        self.wrapped = wrapped
        self.output = output
    }

    func runningApplications() async -> [RunningApplication] {
        await wrapped.runningApplications()
    }

    func hide(_ application: BundleIdentifier) async -> ApplicationVisibilityChange {
        record("hide", application, await wrapped.hide(application))
    }

    func unhide(_ application: BundleIdentifier) async -> ApplicationVisibilityChange {
        record("unhide", application, await wrapped.unhide(application))
    }

    func connectedDisplays() async -> [DisplayIdentifier] {
        await wrapped.connectedDisplays()
    }

    func setDesktopImage(_ image: URL, on display: DisplayIdentifier) async throws {
        try await wrapped.setDesktopImage(image, on: display)
    }

    private func record(
        _ operation: String,
        _ application: BundleIdentifier,
        _ result: ApplicationVisibilityChange,
    ) -> ApplicationVisibilityChange {
        output.emit(Line(operation: operation, bundleIdentifier: application.rawValue, result: "\(result)"))
        return result
    }
}
#endif
