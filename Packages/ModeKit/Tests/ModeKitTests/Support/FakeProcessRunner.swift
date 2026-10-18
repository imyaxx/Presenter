import ModeKit

/// A ``ProcessRunner`` that records commands and returns a scripted result or error per command (exit 0 by default).
actor FakeProcessRunner: ProcessRunner {
    private(set) var commands: [ProcessCommand] = []
    private var scripted: [ProcessCommand: Result<ProcessResult, any Error>] = [:]
    private var hook: (@Sendable (ProcessCommand) async -> Void)?

    func script(_ command: ProcessCommand, _ result: Result<ProcessResult, any Error>) {
        scripted[command] = result
    }

    /// Runs `hook` inside every call, before the result is returned.
    func onRun(_ hook: @escaping @Sendable (ProcessCommand) async -> Void) {
        self.hook = hook
    }

    func run(_ command: ProcessCommand) async throws -> ProcessResult {
        commands.append(command)
        await hook?(command)
        return try (scripted[command] ?? .success(ProcessResult(exitCode: 0))).get()
    }
}
