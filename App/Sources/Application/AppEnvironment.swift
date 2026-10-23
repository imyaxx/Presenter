import Foundation
import ModeKit

/// Builds the app's object graph once at launch and starts the session (ADR-043). The only place that instantiates
/// the concrete session types; `PlatformComposition` builds the adapters.
///
/// When the graph cannot be built the menu shows that the app could not start and nothing is ever activated.
@MainActor
final class AppEnvironment {
    let viewModel: MenuBarViewModel
    let quitCoordinator: QuitCoordinator?
    let version: String?
    private let session: (any SessionControlling)?
    private var sessionTask: Task<Void, Never>?

    /// Builds the graph. No side effect: nothing is read, written or created until ``start()``.
    init(bundle: Bundle, fileManager: FileManager) {
        version = BundleMetadata(bundle: bundle).version
        guard let composition = try? PlatformComposition(bundle: bundle, fileManager: fileManager) else {
            // PlatformCompositionError has no detail the menu could show beyond "could not start".
            viewModel = .unavailable()
            quitCoordinator = nil
            session = nil
            return
        }
        let ports = composition.actionPorts
        let controller = SessionController(
            actionFactory: StandardActionFactory(ports: ports, wallpaperLocations: composition.wallpaperLocations),
            sessionStore: SessionStore(fileStore: ports.fileStore, directory: composition.supportDirectory),
            clock: ports.clock,
            logger: composition.sessionLogger,
        )
        let services = MenuBarServices(
            session: controller,
            profiles: ProfileStore(fileStore: ports.fileStore, directory: composition.supportDirectory),
            folderRevealer: NSWorkspaceProfilesFolderRevealer(directory: composition.supportDirectory),
        )
        viewModel = MenuBarViewModel(services: services)
        quitCoordinator = QuitCoordinator(session: controller, clock: ports.clock)
        session = controller
    }

    /// Follows the session's states and runs launch recovery, before any trigger is offered. Called once from the
    /// launch path; ``stop()`` cancels it.
    func start() {
        guard let session, sessionTask == nil else {
            return
        }
        sessionTask = Task { [viewModel] in
            let updates = await session.stateUpdates()
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await viewModel.follow(updates) }
                group.addTask { await viewModel.recoverAtLaunch() }
            }
        }
    }

    func stop() {
        sessionTask?.cancel()
        sessionTask = nil
    }
}
