import Foundation
import Testing

@testable import PresenterApp

struct LaunchModeTests {
    @Test
    func theTestRunnerVariableMakesTheProcessATestHost() {
        #expect(LaunchMode.current(environment: [:]) == .application)
        #expect(
            LaunchMode.current(environment: ["XCTestConfigurationFilePath": "/tmp/x.xctestconfiguration"]) == .testHost)
    }

    @Test
    func thisProcessIsATestHostSoItBuiltNoSessionGraph() {
        #expect(LaunchMode.current(environment: ProcessInfo.processInfo.environment) == .testHost)
    }
}
