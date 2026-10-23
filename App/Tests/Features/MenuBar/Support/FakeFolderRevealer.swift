import Foundation

@testable import PresenterApp

/// Counts reveals and fails on request.
actor FakeFolderRevealer: ProfilesFolderRevealing {
    private(set) var revealCount = 0
    private var failure: CocoaError?

    func fail(with error: CocoaError) {
        failure = error
    }

    func revealProfilesFolder() async throws {
        revealCount += 1
        if let failure {
            throw failure
        }
    }
}
