import Foundation
import ModeKit

/// A session controller wired to fakes, the real ``SessionStore`` and an ``InMemoryFileStore``.
struct SessionControllerHarness {
    static let directory = URL(filePath: "/Store")
    static let sessionFileURL = directory.appending(path: "session.json")

    let log = FakeCallLog()
    let fileStore = InMemoryFileStore()
    let clock = FakeClock()
    let logger = RecordingSessionLogger()
    let actions: [ActionIdentifier: FakeModeAction]
    let controller: SessionController

    /// - Parameter registered: identifiers the factory knows; defaults to every action.
    init(registered: [ActionIdentifier] = ActionIdentifier.allCases) {
        let log = log
        actions = Dictionary(uniqueKeysWithValues: registered.map { ($0, FakeModeAction($0, log: log)) })
        controller = SessionController(
            actionFactory: FakeActionFactory(actions: actions),
            sessionStore: SessionStore(fileStore: fileStore, directory: Self.directory),
            clock: clock,
            logger: logger,
        )
    }

    struct UnregisteredAction: Error {
        let identifier: ActionIdentifier
    }

    func action(_ identifier: ActionIdentifier) throws -> FakeModeAction {
        guard let action = actions[identifier] else {
            throw UnregisteredAction(identifier: identifier)
        }
        return action
    }

    /// Runs recovery on an empty store so activation is allowed.
    func ready() async -> SessionController {
        _ = await controller.recoverIfNeeded()
        return controller
    }

    /// The session file as a fresh store reads it.
    func sessionFile() async throws -> SessionRecord? {
        try await SessionStore(fileStore: fileStore, directory: Self.directory).loadSession()
    }

    func writeSessionFile(_ record: SessionRecord) async throws {
        try await SessionStore(fileStore: fileStore, directory: Self.directory).saveSession(record)
    }

    static func profile(_ identifiers: [ActionIdentifier], autoExit: AutoExit? = nil) -> Profile {
        ProfileBuilder(steps: identifiers.map(step(for:)), autoExit: autoExit).build()
    }

    static func step(for identifier: ActionIdentifier) -> ProfileStep {
        switch identifier {
        case .desktopIcons: .hideDesktopIcons
        case .dock: .hideDock
        case .menuBar: .hideMenuBar
        case .hideApps: .hideApps(exclusions: [])
        case .wallpaper: .wallpaper(.solidColor(SolidColor(red: 21, green: 21, blue: 21)), displays: .allDisplays)
        }
    }

    static func snapshot(_ identifier: ActionIdentifier) -> FakeSnapshot {
        FakeSnapshot(value: "\(identifier.rawValue)-snapshot")
    }

    static func applied(_ identifier: ActionIdentifier) -> FakeAppliedState {
        FakeAppliedState(value: "\(identifier.rawValue)-applied")
    }
}

/// Reads exactly `count` states from a state stream. The stream buffers every change, so no waiting on time.
func take(_ count: Int, from stream: AsyncStream<SessionState>) async -> [SessionState] {
    var states: [SessionState] = []
    for await state in stream {
        states.append(state)
        if states.count == count {
            break
        }
    }
    return states
}

/// Records values produced inside fake actions, for assertions after the call returns.
actor ValueBox<Value: Sendable> {
    private(set) var value: Value?

    func set(_ newValue: Value?) {
        value = newValue
    }
}
