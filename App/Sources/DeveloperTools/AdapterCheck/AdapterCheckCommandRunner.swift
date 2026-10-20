#if DEBUG
import Foundation
import ModeKit

/// Runs one parsed command and writes its result file (ADR-042). Commands that change the system run only after
/// ``BackupManifestGate`` accepts the backup.
struct AdapterCheckCommandRunner: Sendable {
    struct StructureDetails: Encodable, Sendable {
        let lines: [String]
    }

    let invocation: AdapterCheckInvocation
    let output: CheckOutput

    /// Returns whether the command succeeded.
    func execute() async -> Bool {
        let command = invocation.command
        if command.changesTheSystem {
            do {
                _ = try BackupManifestGate.check(invocation.backupDirectory, now: Date())
            } catch {
                return write(CheckResult<NoDetails>.failed(command.name, error: "\(error)"))
            }
        }
        let environment: AdapterCheckEnvironment
        do {
            let composition = try PlatformComposition(bundle: .main, fileManager: .default)
            environment = AdapterCheckEnvironment(
                composition: composition,
                checkDirectory: invocation.checkDirectory,
                output: output,
            )
        } catch {
            return write(CheckResult<NoDetails>.failed(command.name, error: "\(error)"))
        }
        return await execute(command, in: environment)
    }

    private func execute(
        _ command: AdapterCheckInvocation.Command,
        in environment: AdapterCheckEnvironment,
    ) async -> Bool {
        switch command {
        case .world:
            return write(CheckResult.succeeded(command.name, details: await environment.makeWorldReader().read()))
        case .storeStructure:
            return write(await storeStructure(environment))
        case .run(let options):
            return write(await SessionCommands(environment: environment).run(options))
        case .activate(let options):
            return write(await SessionCommands(environment: environment).activate(options))
        case .recover:
            return write(await SessionCommands(environment: environment).recover())
        case .wallpaperLatency(let runs):
            return write(
                await catching(command) {
                    try await WallpaperCommands(environment: environment).latency(runs: runs)
                })
        case .wallpaperInterrupt:
            return write(
                await catching(command) { try await WallpaperCommands(environment: environment).interrupt() })
        case .notifyMenuBar:
            await environment.ports.notifier.post(.menuBarHidingChanged)
            return write(CheckResult.succeeded(command.name, details: NoDetails()))
        }
    }

    private func storeStructure(_ environment: AdapterCheckEnvironment) async -> CheckResult<StructureDetails> {
        do {
            guard let data = try await environment.ports.fileStore.read(environment.wallpaperLocations.storeURL)
            else {
                return .failed("store-structure", error: "\(AdapterCheckCommandError.storeUnavailable)")
            }
            let lines = StoreStructure.lines(of: try PropertyListValue.decode(data))
            return .succeeded("store-structure", details: StructureDetails(lines: lines))
        } catch {
            return .failed("store-structure", error: "\(error)")
        }
    }

    private func catching<Details>(
        _ command: AdapterCheckInvocation.Command,
        _ body: () async throws -> CheckResult<Details>,
    ) async -> CheckResult<Details> {
        do {
            return try await body()
        } catch {
            return .failed(command.name, error: "\(error)")
        }
    }

    private func write(_ result: CheckResult<some Encodable & Sendable>) -> Bool {
        do {
            try result.write(to: invocation.resultURL)
        } catch {
            FileHandle.standardError.write(Data("adapter check: cannot write the result file: \(error)\n".utf8))
            return false
        }
        return result.status == .succeeded
    }
}
#endif
