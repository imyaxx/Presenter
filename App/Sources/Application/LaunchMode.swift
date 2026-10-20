/// Whether the process is the app or the host of the unit tests (ADR-043).
///
/// `make test` launches the app as the tests' host. As a host it builds no session graph, so no test can recover or
/// restore the user's real session, and it skips the single-instance guard, so it can run next to the real app.
enum LaunchMode: Equatable, Sendable {
    case application
    case testHost

    /// Set by Xcode's test runner in the host process.
    static let testConfigurationKey = "XCTestConfigurationFilePath"

    static func current(environment: [String: String]) -> LaunchMode {
        environment[testConfigurationKey] == nil ? .application : .testHost
    }
}
