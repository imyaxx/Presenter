import ModeKit

@testable import PresenterApp

/// Returns scripted profiles or a scripted error, and counts the loads.
actor FakeProfileLoader: ProfileLoading {
    private(set) var loadCount = 0
    private var result: Result<[Profile], StoreError>

    init(_ profiles: [Profile] = []) {
        result = .success(profiles)
    }

    func set(_ result: Result<[Profile], StoreError>) {
        self.result = result
    }

    func loadProfiles() async throws -> [Profile] {
        loadCount += 1
        return try result.get()
    }
}
