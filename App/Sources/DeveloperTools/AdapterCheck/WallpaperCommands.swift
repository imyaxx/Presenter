#if DEBUG
import Foundation
import ModeKit

/// `wallpaper-latency` and `wallpaper-interrupt`: the real adapter, renderer, inspector and restorer, measured
/// against the real wallpaper store (ADR-038, ADR-042). Each run restores the store it found.
struct WallpaperCommands: Sendable {
    struct LatencyRun: Encodable, Sendable {
        let run: Int
        let setCallMilliseconds: Double
        /// Time from the return of `setDesktopImage` to the first changed fingerprint; nil when none within the cap.
        let persistMilliseconds: Double?
    }

    struct LatencyDetails: Encodable, Sendable {
        let runs: [LatencyRun]
        let statistics: LatencyStatistics?
    }

    struct InterruptDetails: Encodable, Sendable {
        let changedBeforeRestore: Bool
        let equalsBaselineAfterRestore: Bool
        let equalsBaselineTenSecondsLater: Bool
    }

    static let pollInterval = Duration.milliseconds(10)
    static let pollCap = Duration.seconds(10)
    static let settleAfterRestore = Duration.seconds(2)
    static let lateWriteWait = Duration.seconds(10)

    let environment: AdapterCheckEnvironment

    func latency(runs: Int) async throws -> CheckResult<LatencyDetails> {
        var results: [LatencyRun] = []
        for run in 1...runs {
            let baseline = try await readStore()
            let image = try await makeImage(Self.color(forRun: run))
            let clock = ContinuousClock()
            let start = clock.now
            try await setOnEveryDisplay(image)
            let returned = clock.now
            let persisted = try await waitForChange(from: try fingerprint(baseline))
            results.append(
                LatencyRun(
                    run: run,
                    setCallMilliseconds: Self.milliseconds(returned - start),
                    persistMilliseconds: persisted.map(Self.milliseconds),
                ))
            _ = try await environment.makeWallpaperRestorer().restore(.init(storeData: baseline), expecting: nil)
            try await Task.sleep(for: Self.settleAfterRestore)
        }
        let statistics = LatencyStatistics(samplesMilliseconds: results.compactMap(\.persistMilliseconds))
        return .succeeded("wallpaper-latency", details: LatencyDetails(runs: results, statistics: statistics))
    }

    func interrupt() async throws -> CheckResult<InterruptDetails> {
        let baseline = try await readStore()
        let baselineFingerprint = try fingerprint(baseline)
        try await setOnEveryDisplay(try await makeImage(Self.color(forRun: 0)))
        let changedBeforeRestore = try fingerprint(try await readStore()) != baselineFingerprint
        _ = try await environment.makeWallpaperRestorer().restore(.init(storeData: baseline), expecting: nil)
        let afterRestore = try fingerprint(try await readStore())
        try await Task.sleep(for: Self.lateWriteWait)
        let later = try fingerprint(try await readStore())
        let details = InterruptDetails(
            changedBeforeRestore: changedBeforeRestore,
            equalsBaselineAfterRestore: afterRestore == baselineFingerprint,
            equalsBaselineTenSecondsLater: later == baselineFingerprint,
        )
        return .succeeded("wallpaper-interrupt", details: details)
    }

    /// A different, clearly visible color for each run.
    static func color(forRun run: Int) -> SolidColor {
        SolidColor(red: UInt8((run * 53 + 20) % 256), green: UInt8((run * 97 + 60) % 256), blue: 200)
    }

    private func readStore() async throws -> Data {
        guard let data = try await environment.ports.fileStore.read(environment.wallpaperLocations.storeURL) else {
            throw AdapterCheckCommandError.storeUnavailable
        }
        return data
    }

    private func fingerprint(_ store: Data) throws -> WallpaperStoreFingerprint {
        try environment.ports.storeInspector.fingerprint(of: store)
    }

    private func makeImage(_ color: SolidColor) async throws -> URL {
        let name = String(format: "check-%02x%02x%02x.png", color.red, color.green, color.blue)
        let url = environment.wallpaperLocations.generatedImagesDirectory.appending(path: name)
        try await environment.ports.fileStore.write(
            try await environment.ports.imageRenderer.pngData(for: color), to: url, )
        return url
    }

    private func setOnEveryDisplay(_ image: URL) async throws {
        for display in await environment.ports.workspace.connectedDisplays() {
            try await environment.ports.workspace.setDesktopImage(image, on: display)
        }
    }

    private func waitForChange(from baseline: WallpaperStoreFingerprint) async throws -> Duration? {
        let clock = ContinuousClock()
        let start = clock.now
        while clock.now - start < Self.pollCap {
            if try fingerprint(try await readStore()) != baseline {
                return clock.now - start
            }
            try await Task.sleep(for: Self.pollInterval)
        }
        return nil
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }
}
#endif
