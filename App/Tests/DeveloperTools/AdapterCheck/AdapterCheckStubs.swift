#if DEBUG
import Foundation
import ModeKit
import os

@testable import PresenterApp

/// In-memory ports and a line collector for the adapter check tool's tests. None touches the real system.
final class CollectedLines: Sendable {
    private let lines = OSAllocatedUnfairLock(initialState: [String]())

    var all: [String] {
        lines.withLock { $0 }
    }

    var output: CheckOutput {
        CheckOutput { line in self.lines.withLock { $0.append(line) } }
    }
}

struct StubDefaultsStore: DefaultsStore {
    let values: [DefaultsKey: DefaultsValue]
    var unreadable: Set<DefaultsKey> = []

    func value(for key: DefaultsKey) async throws -> DefaultsValue? {
        if unreadable.contains(key) {
            throw DefaultsError.unsupportedValueType(key)
        }
        return values[key]
    }

    func set(_ value: DefaultsValue, for key: DefaultsKey) async throws {
        throw DefaultsError.failed(reason: "read-only stub")
    }

    func remove(_ key: DefaultsKey) async throws {
        throw DefaultsError.failed(reason: "read-only stub")
    }
}

struct StubFileStore: FileStore {
    let files: [URL: Data]

    func read(_ url: URL) async throws -> Data? {
        files[url]
    }

    func write(_ data: Data, to url: URL) async throws {
        throw CocoaError(.fileWriteNoPermission)
    }

    func remove(_ url: URL) async throws {
        throw CocoaError(.fileWriteNoPermission)
    }
}

struct StubInspector: WallpaperStoreInspector {
    let fingerprint: WallpaperStoreFingerprint?

    func fingerprint(of store: Data) throws -> WallpaperStoreFingerprint {
        guard let fingerprint else {
            throw WallpaperStoreError.unrecognizedFormat(reason: "stub")
        }
        return fingerprint
    }
}

struct StubWorkspace: WorkspaceAdapter {
    let applications: [RunningApplication]
    let displays: [DisplayIdentifier]
    var visibilityChange = ApplicationVisibilityChange.changed

    func runningApplications() async -> [RunningApplication] {
        applications
    }

    func hide(_ application: BundleIdentifier) async -> ApplicationVisibilityChange {
        visibilityChange
    }

    func unhide(_ application: BundleIdentifier) async -> ApplicationVisibilityChange {
        visibilityChange
    }

    func connectedDisplays() async -> [DisplayIdentifier] {
        displays
    }

    func setDesktopImage(_ image: URL, on display: DisplayIdentifier) async throws {
        throw CocoaError(.featureUnsupported)
    }
}

enum Stub {
    static func application(
        _ identifier: String,
        hidden: ApplicationVisibility = .visible,
        frontmost: ApplicationFocus = .background,
    ) throws -> RunningApplication {
        RunningApplication(
            bundleIdentifier: try BundleIdentifier(identifier),
            isHidden: hidden == .hidden,
            isFrontmost: frontmost == .frontmost,
            isThisApplication: false,
        )
    }

    enum ApplicationVisibility { case visible, hidden }
    enum ApplicationFocus { case background, frontmost }
}
#endif
