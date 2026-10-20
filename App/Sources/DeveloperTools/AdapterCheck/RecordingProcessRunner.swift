#if DEBUG
import Foundation
import ModeKit

/// A ``ProcessRunner`` that forwards to the real runner and writes each command with its exit code or error as a JSON
/// line, so the protocol records what `killall` returned (ADR-042).
struct RecordingProcessRunner: ProcessRunner {
    struct Line: Encodable, Equatable, Sendable {
        let type = "process"
        let command: String
        let exitCode: Int32?
        let error: String?
    }

    private let wrapped: any ProcessRunner
    private let output: CheckOutput

    init(wrapping wrapped: any ProcessRunner, output: CheckOutput) {
        self.wrapped = wrapped
        self.output = output
    }

    func run(_ command: ProcessCommand) async throws -> ProcessResult {
        let commandLine = ([command.executableURL.path(percentEncoded: false)] + command.arguments).joined(
            separator: " ")
        do {
            let result = try await wrapped.run(command)
            output.emit(Line(command: commandLine, exitCode: result.exitCode, error: nil))
            return result
        } catch {
            output.emit(Line(command: commandLine, exitCode: nil, error: "\(error)"))
            throw error
        }
    }
}
#endif
