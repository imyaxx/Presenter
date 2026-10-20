/// The process entry point. In a Debug build, `--adapter-check <command>` runs the adapter check tool instead of the
/// app (ADR-042); every other launch, and every Release launch, starts ``PresenterApp`` unchanged.
@main
enum PresenterMain {
    static func main() {
        #if DEBUG
        MainActor.assumeIsolated {
            AdapterCheckLauncher.runIfRequested(arguments: CommandLine.arguments)
        }
        #endif
        PresenterApp.main()
    }
}
