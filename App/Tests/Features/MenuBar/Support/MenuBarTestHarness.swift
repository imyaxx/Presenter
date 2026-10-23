import Foundation
import ModeKit

@testable import PresenterApp

/// A view model over the fakes, following the fake controller's states the way `AppEnvironment` does.
@MainActor
final class MenuBarTestHarness {
    let session: FakeSessionController
    let profiles: FakeProfileLoader
    let revealer = FakeFolderRevealer()
    let model: MenuBarViewModel
    private var following: Task<Void, Never>?

    init(state: SessionState = .idle, profiles: [Profile] = [MenuBarFixtures.quick, MenuBarFixtures.full]) {
        session = FakeSessionController(state: state)
        self.profiles = FakeProfileLoader(profiles)
        model = MenuBarViewModel(
            services: MenuBarServices(session: session, profiles: self.profiles, folderRevealer: revealer))
    }

    /// Starts following the state stream; with `recovering`, also runs launch recovery and waits for it.
    func start(recovering: RecoveryStep = .recover) async {
        let updates = await session.stateUpdates()
        following = Task { [model] in await model.follow(updates) }
        if recovering == .recover {
            await model.recoverAtLaunch()
        }
    }

    enum RecoveryStep { case recover, skip }

    func stop() {
        following?.cancel()
    }

    /// Waits up to two seconds for `condition`; the state stream is delivered asynchronously.
    func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<200 {
            if condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}
