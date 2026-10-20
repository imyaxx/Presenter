import AppKit
import Foundation

/// The process entry point. In a Debug build, `--adapter-check <command>` runs the adapter check tool instead of the
/// app (ADR-042). A second launch of the app activates the first instance and ends before building anything
/// (ADR-043). Otherwise it starts ``PresenterApp``.
@main
enum PresenterMain {
    static func main() {
        #if DEBUG
        MainActor.assumeIsolated {
            AdapterCheckLauncher.runIfRequested(arguments: CommandLine.arguments)
        }
        #endif
        let mode = LaunchMode.current(environment: ProcessInfo.processInfo.environment)
        if mode == .application, let bundleIdentifier = Bundle.main.bundleIdentifier {
            let anotherInstanceRuns = MainActor.assumeIsolated {
                NSRunningApplicationInstanceGuard(bundleIdentifier: bundleIdentifier).activateOtherInstance()
            }
            if anotherInstanceRuns {
                return
            }
        }
        PresenterApp.main()
    }
}
