#if DEBUG
import Foundation

/// Statistics of the measured wallpaper persist latencies and the polling calibration rule of ADR-038.
struct LatencyStatistics: Encodable, Equatable, Sendable {
    let samplesMilliseconds: [Double]
    let medianMilliseconds: Double
    let percentile95Milliseconds: Double
    let calibratedPollCount: Int

    /// The poll interval of `WallpaperAction`, kept by the rule.
    static let pollIntervalMilliseconds = 100.0
    /// The poll count before calibration, and the floor of the rule.
    static let minimumPollCount = 50

    /// Nil when there are no samples.
    init?(samplesMilliseconds: [Double]) {
        let sorted = samplesMilliseconds.sorted()
        guard !sorted.isEmpty else {
            return nil
        }
        self.samplesMilliseconds = samplesMilliseconds
        medianMilliseconds = Self.percentile(50, ofSorted: sorted)
        percentile95Milliseconds = Self.percentile(95, ofSorted: sorted)
        calibratedPollCount = Self.calibratedPollCount(percentile95Milliseconds: percentile95Milliseconds)
    }

    /// Nearest-rank percentile of a sorted, non-empty sample.
    static func percentile(_ percent: Double, ofSorted sorted: [Double]) -> Double {
        let rank = Int((percent / 100 * Double(sorted.count)).rounded(.up))
        return sorted[min(max(rank, 1), sorted.count) - 1]
    }

    /// `max(50, ceil(4 × p95 / 100 ms))` (ADR-038).
    static func calibratedPollCount(percentile95Milliseconds: Double) -> Int {
        max(minimumPollCount, Int((4 * percentile95Milliseconds / pollIntervalMilliseconds).rounded(.up)))
    }
}
#endif
