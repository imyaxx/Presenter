import Foundation
import ModeKit

struct FakeSnapshot: Codable, Equatable, Sendable {
    let value: String
}

struct FakeAppliedState: Codable, Equatable, Sendable {
    let value: String
}

struct FakeActionFailure: Error, Equatable, CustomStringConvertible {
    let message: String
    var description: String { message }
}

/// One call to a fake action, as recorded in the shared ``FakeCallLog``.
enum FakeCall: Equatable, Sendable {
    case capture(ActionIdentifier)
    case apply(ActionIdentifier)
    case restore(ActionIdentifier, snapshot: FakeSnapshot, applied: FakeAppliedState?)
}

/// The ordered log of calls across all fake actions of one test.
actor FakeCallLog {
    private(set) var calls: [FakeCall] = []

    func record(_ call: FakeCall) {
        calls.append(call)
    }
}

/// A ``ModeAction`` with scripted results, an optional gate inside one phase, and an optional hook inside `apply`.
actor FakeModeAction: ModeAction {
    enum Phase: Sendable {
        case capture, apply, restore
    }

    let identifier: ActionIdentifier
    private let log: FakeCallLog
    private var captureResult: Result<FakeSnapshot, FakeActionFailure>
    private var applyResult: Result<FakeAppliedState, FakeActionFailure>
    private var restoreResults: [Result<RestoreOutcome, FakeActionFailure>] = [.success(.restored)]
    private var gates: [Phase: AsyncGate] = [:]
    private var applyHook: (@Sendable () async -> Void)?

    init(_ identifier: ActionIdentifier, log: FakeCallLog) {
        self.identifier = identifier
        self.log = log
        captureResult = .success(FakeSnapshot(value: "\(identifier.rawValue)-snapshot"))
        applyResult = .success(FakeAppliedState(value: "\(identifier.rawValue)-applied"))
    }

    func failCapture() { captureResult = .failure(FakeActionFailure(message: "capture \(identifier.rawValue)")) }
    func failApply() { applyResult = .failure(FakeActionFailure(message: "apply \(identifier.rawValue)")) }
    func failRestore() { restoreResults = [.failure(FakeActionFailure(message: "restore \(identifier.rawValue)"))] }

    /// Results for successive restores; the last one repeats.
    func scriptRestores(_ results: [Result<RestoreOutcome, FakeActionFailure>]) { restoreResults = results }

    func suspend(in phase: Phase, at gate: AsyncGate) { gates[phase] = gate }

    func onApply(_ hook: @escaping @Sendable () async -> Void) { applyHook = hook }

    func capture() async throws -> FakeSnapshot {
        await log.record(.capture(identifier))
        await gates[.capture]?.pass()
        return try captureResult.get()
    }

    func apply() async throws -> FakeAppliedState {
        await log.record(.apply(identifier))
        await applyHook?()
        await gates[.apply]?.pass()
        return try applyResult.get()
    }

    func restore(_ snapshot: FakeSnapshot, expecting applied: FakeAppliedState?) async throws -> RestoreOutcome {
        await log.record(.restore(identifier, snapshot: snapshot, applied: applied))
        await gates[.restore]?.pass()
        let result = restoreResults.count > 1 ? restoreResults.removeFirst() : restoreResults[0]
        return try result.get()
    }
}
