#if DEBUG
import Foundation
import ModeKit

/// `run`, `activate` and `recover`: the real session controller over the real adapters (ADR-042).
struct SessionCommands: Sendable {
    struct Details: Encodable, Sendable {
        var profile: String?
        var recoveryBeforeActivation: String?
        var activationSeconds: Double?
        var holdSeconds: Int?
        var deactivation: String?
        var report: ReportDetails?
    }

    struct ReportDetails: Encodable, Equatable, Sendable {
        let restored: [String]
        let skippedBecauseChangedByUser: [String]
        let failed: [String]

        init(_ report: RestoreReport) {
            restored = report.restored.map(\.rawValue)
            skippedBecauseChangedByUser = report.skippedBecauseChangedByUser.map(\.rawValue)
            failed = report.failed.map { "\($0.identifier.rawValue): \($0.reason)" }
        }
    }

    let environment: AdapterCheckEnvironment

    /// Activates, holds, deactivates and reports.
    func run(_ options: AdapterCheckInvocation.SessionOptions) async -> CheckResult<Details> {
        await withActivation(options, command: "run") { controller, details in
            let report: RestoreReport
            do {
                guard case .performed(let performed) = try await controller.deactivate() else {
                    return .failed("run", error: "deactivate was ignored", details: details)
                }
                report = performed
            } catch {
                return .failed("run", error: "deactivate failed: \(error)", details: details)
            }
            var finished = details
            finished.report = ReportDetails(report)
            finished.deactivation = report.failed.isEmpty ? "restored" : "degraded"
            return report.failed.isEmpty
                ? .succeeded("run", details: finished)
                : .failed("run", error: "some actions could not be restored", details: finished)
        }
    }

    /// Activates, holds, and exits without deactivating, leaving `session.json` as a crash would.
    func activate(_ options: AdapterCheckInvocation.SessionOptions) async -> CheckResult<Details> {
        await withActivation(options, command: "activate") { _, details in
            .succeeded("activate", details: details)
        }
    }

    /// Restores whatever `session.json` in the check directory describes.
    func recover() async -> CheckResult<Details> {
        let outcome = await environment.makeController().recoverIfNeeded()
        var details = Details()
        details.recoveryBeforeActivation = "\(outcome)"
        switch outcome {
        case .nothingToRecover, .alreadyAttempted:
            return .succeeded("recover", details: details)
        case .restored(let report):
            details.report = ReportDetails(report)
            return .succeeded("recover", details: details)
        case .partiallyRestored(let report):
            details.report = ReportDetails(report)
            return .failed("recover", error: "some actions could not be restored", details: details)
        case .blocked(let error):
            return .failed("recover", error: "session.json is unreadable: \(error)", details: details)
        }
    }

    private func withActivation(
        _ options: AdapterCheckInvocation.SessionOptions,
        command: String,
        then finish: (SessionController, Details) async -> CheckResult<Details>,
    ) async -> CheckResult<Details> {
        var details = Details()
        let profile: Profile
        do {
            profile = try await resolveProfile(options)
        } catch {
            return .failed(command, error: "\(error)", details: details)
        }
        details.profile = profile.name
        let controller = environment.makeController()
        let recovery = await controller.recoverIfNeeded()
        details.recoveryBeforeActivation = "\(recovery)"
        guard recovery == .nothingToRecover else {
            return .failed(
                command, error: "a previous session was recovered first; check, then run again", details: details, )
        }
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let result = try await controller.activate(profile)
            details.activationSeconds = Self.seconds(clock.now - start)
            guard case .performed = result else {
                return .failed(command, error: "activate was ignored", details: details)
            }
        } catch {
            details.activationSeconds = Self.seconds(clock.now - start)
            return .failed(command, error: "activate failed: \(error)", details: details)
        }
        details.holdSeconds = options.holdSeconds
        // A cancelled hold only shortens the wait; the session is still restored or left as requested.
        try? await Task.sleep(for: .seconds(options.holdSeconds))
        return await finish(controller, details)
    }

    private func resolveProfile(_ options: AdapterCheckInvocation.SessionOptions) async throws -> Profile {
        let running = await environment.ports.workspace.runningApplications()
        let allowed = options.hideOnly.map(Set.init)
        guard let name = options.profileName else {
            return HideOnlySelection.profile(running: running, hiding: allowed ?? [])
        }
        guard let profile = try await environment.loadProfiles().first(where: { $0.name == name }) else {
            throw AdapterCheckCommandError.unknownProfile(name)
        }
        return try HideOnlySelection.restricting(profile, running: running, hiding: allowed)
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}

enum AdapterCheckCommandError: Error, Equatable, Sendable, CustomStringConvertible {
    case unknownProfile(String)
    case storeUnavailable

    var description: String {
        switch self {
        case .unknownProfile(let name): "no profile named \(name) in the check directory's profiles.json"
        case .storeUnavailable: "the wallpaper store does not exist"
        }
    }
}
#endif
