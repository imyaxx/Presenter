#if DEBUG
import AppKit
import Foundation

/// Starts the adapter check tool when the app is launched with `--adapter-check` (ADR-042).
///
/// In check mode the app creates no menu bar item and no window, runs the main run loop so AppKit calls can hop to
/// the main actor, and exits when the command finishes: 0 on success, 1 on failure, 2 for a bad command line.
@MainActor
enum AdapterCheckLauncher {
    static let checkDirectoryName = "presenter-check"

    /// Returns at once for a normal launch; otherwise runs the command and never returns.
    static func runIfRequested(arguments: [String]) {
        let invocation: AdapterCheckInvocation?
        do {
            let defaultDirectory = FileManager.default.homeDirectoryForCurrentUser
                .appending(path: checkDirectoryName, directoryHint: .isDirectory)
            invocation = try AdapterCheckInvocation.parse(arguments, defaultCheckDirectory: defaultDirectory)
        } catch {
            FileHandle.standardError.write(Data("adapter check: \(error)\n".utf8))
            exit(2)
        }
        guard let invocation else {
            return
        }
        NSApplication.shared.setActivationPolicy(.prohibited)
        Task {
            let succeeded = await AdapterCheckCommandRunner(invocation: invocation, output: .standardOutput)
                .execute()
            exit(succeeded ? 0 : 1)
        }
        NSApplication.shared.run()
    }
}
#endif
