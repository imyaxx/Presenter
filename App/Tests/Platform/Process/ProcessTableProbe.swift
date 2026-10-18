import Foundation
import ModeKit

@testable import PresenterApp

/// Asks `pgrep` whether a process with exactly this command line still exists. Read only.
enum ProcessTableProbe {
    static func isRunning(commandLine: String) async throws -> Bool {
        let probe = ProcessCommand(
            executableURL: URL(filePath: "/usr/bin/pgrep"),
            arguments: ["-f", "^\(commandLine)$"],
            timeout: .seconds(5),
        )
        // pgrep exits 0 when a process matches and 1 when none does.
        return try await FoundationProcessRunner().run(probe).exitCode == 0
    }
}
