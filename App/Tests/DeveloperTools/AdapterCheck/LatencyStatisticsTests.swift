#if DEBUG
import Testing

@testable import PresenterApp

struct LatencyStatisticsTests {
    @Test
    func percentilesUseTheNearestRank() {
        let sorted = (1...20).map(Double.init)

        #expect(LatencyStatistics.percentile(50, ofSorted: sorted) == 10)
        #expect(LatencyStatistics.percentile(95, ofSorted: sorted) == 19)
        #expect(LatencyStatistics.percentile(100, ofSorted: sorted) == 20)
        #expect(LatencyStatistics.percentile(95, ofSorted: [7]) == 7)
    }

    @Test
    func statisticsAreComputedFromUnsortedSamples() throws {
        let statistics = try #require(LatencyStatistics(samplesMilliseconds: [300, 100, 200, 400]))

        #expect(statistics.medianMilliseconds == 200)
        #expect(statistics.percentile95Milliseconds == 400)
        #expect(statistics.samplesMilliseconds == [300, 100, 200, 400])
    }

    @Test
    func noSamplesGiveNoStatistics() {
        #expect(LatencyStatistics(samplesMilliseconds: []) == nil)
    }

    @Test(arguments: [(0.0, 50), (1250.0, 50), (1251.0, 51), (1500.0, 60), (2499.0, 100)])
    func theCalibrationRuleKeepsAtLeastFiftyPolls(percentile95: Double, expected: Int) {
        #expect(LatencyStatistics.calibratedPollCount(percentile95Milliseconds: percentile95) == expected)
    }
}
#endif
