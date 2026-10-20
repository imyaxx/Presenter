#if DEBUG
import Foundation
import ModeKit
import Testing

@testable import PresenterApp

/// Writes to closures and temporary files only.
struct CheckOutputTests {
    private struct RecordingLogger: SessionLogger {
        let events = CollectedLines()

        func log(_ event: SessionEvent) {
            events.output.emit(SessionLogMessage(event).publicText)
        }
    }

    private static func workspaceLine(operation: String) -> String {
        "{\"bundleIdentifier\":\"com.apple.TextEdit\",\"operation\":\"\(operation)\","
            + "\"result\":\"refused\",\"type\":\"workspace\"}"
    }

    @Test
    func theResultFileHasTheStatusTheCommandAndTheDetails() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "presenter-result-\(UUID().uuidString)/r.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        try CheckResult.succeeded("world", details: ["answer": 42]).write(to: url)
        let succeeded = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        try CheckResult<NoDetails>.failed("run", error: "denied").write(to: url)
        let failed = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]

        #expect(succeeded?["status"] as? String == "ok")
        #expect(succeeded?["command"] as? String == "world")
        #expect((succeeded?["details"] as? [String: Int])?["answer"] == 42)
        #expect(failed?["status"] as? String == "failed")
        #expect(failed?["error"] as? String == "denied")
    }

    @Test
    func theOutputWritesOneSortedJSONLinePerValue() {
        let lines = CollectedLines()

        lines.output.emit(["b": 1, "a": 2])

        #expect(lines.all == ["{\"a\":2,\"b\":1}"])
    }

    @Test
    func theSessionLoggerPrintsAndForwardsEveryEvent() {
        let lines = CollectedLines()
        let forwarded = RecordingLogger()
        let logger = PrintingSessionLogger(output: lines.output, forwardingTo: forwarded)
        let sessionID = UUID(uuidString: "6F1E5C0A-2B53-4F0B-9E5C-0D3C1A7B8E21") ?? UUID()

        logger.log(.actionFailed(sessionID: sessionID, .dock, phase: .apply, reason: "denied"))

        let expected =
            "{\"detail\":\"denied\",\"level\":\"error\",\"text\":\"action dock failed in apply "
            + "session=6F1E5C0A-2B53-4F0B-9E5C-0D3C1A7B8E21\",\"type\":\"session\"}"
        #expect(lines.all == [expected])
        #expect(forwarded.events.all.count == 1)
    }

    private struct StubProcessRunner: ProcessRunner {
        let result: Result<ProcessResult, ProcessError>

        func run(_ command: ProcessCommand) async throws -> ProcessResult {
            try result.get()
        }
    }

    @Test
    func theRecordingProcessRunnerPrintsEachCommandWithItsExitCodeOrError() async throws {
        let lines = CollectedLines()
        let killall = URL(filePath: "/usr/bin/killall")
        let command = ProcessCommand(executableURL: killall, arguments: ["Finder"], timeout: .seconds(10))
        let exitZero = StubProcessRunner(result: .success(ProcessResult(exitCode: 0)))
        let timeout = StubProcessRunner(result: .failure(.timedOut(.seconds(10))))
        let succeeding = RecordingProcessRunner(wrapping: exitZero, output: lines.output)
        let failing = RecordingProcessRunner(wrapping: timeout, output: lines.output)

        #expect(try await succeeding.run(command) == ProcessResult(exitCode: 0))
        await #expect(throws: ProcessError.timedOut(.seconds(10))) { try await failing.run(command) }

        #expect(
            lines.all == [
                "{\"command\":\"/usr/bin/killall Finder\",\"exitCode\":0,\"type\":\"process\"}",
                "{\"command\":\"/usr/bin/killall Finder\",\"error\":\"Process timed out after 10.0 seconds\","
                    + "\"type\":\"process\"}",
            ])
    }

    @Test
    func theRecordingWorkspacePrintsEachVisibilityRequestAndItsResult() async throws {
        let lines = CollectedLines()
        let wrapped = StubWorkspace(applications: [], displays: [], visibilityChange: .refused)
        let workspace = RecordingWorkspaceAdapter(wrapping: wrapped, output: lines.output)
        let textEdit = try BundleIdentifier("com.apple.TextEdit")

        #expect(await workspace.hide(textEdit) == .refused)
        #expect(await workspace.unhide(textEdit) == .refused)

        #expect(
            lines.all == [
                Self.workspaceLine(operation: "hide"),
                Self.workspaceLine(operation: "unhide"),
            ])
    }
}
#endif
