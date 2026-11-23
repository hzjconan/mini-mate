import Foundation
import Testing
@testable import MMCore

@Suite("LatencyRecorder")
struct LatencyRecorderTests {
    @Test func percentileUsesNearestRankOnEvenCount() {
        var recorder = LatencyRecorder()
        for value in [0.10, 0.20, 0.30, 0.40] {
            recorder.record(value, metric: "M_track")
        }

        // nearest-rank：p50 取第 2 个、p90 取第 4 个（已排序样本）
        #expect(recorder.p50(for: "M_track") == 0.20)
        #expect(recorder.p90(for: "M_track") == 0.40)
    }

    @Test func percentileSortsSamplesBeforeRanking() {
        var recorder = LatencyRecorder()
        for value in [0.30, 0.10, 0.20] {
            recorder.record(value, metric: "M_track")
        }

        #expect(recorder.p50(for: "M_track") == 0.20)
        #expect(recorder.p90(for: "M_track") == 0.30)
    }

    @Test func singleSampleIsBothPercentiles() {
        var recorder = LatencyRecorder()
        recorder.record(0.25, metric: "M_reflex")

        #expect(recorder.p50(for: "M_reflex") == 0.25)
        #expect(recorder.p90(for: "M_reflex") == 0.25)
    }

    @Test func emptyMetricsHaveNoPercentile() {
        let recorder = LatencyRecorder()

        #expect(recorder.count(for: "M_track") == 0)
        #expect(recorder.p50(for: "M_track") == nil)
        #expect(recorder.p90(for: "M_track") == nil)
        #expect(recorder.p50(for: "未记录的指标") == nil)
    }

    @Test func metricsAreIndependent() {
        var recorder = LatencyRecorder()
        recorder.record(0.10, metric: "M_track")
        recorder.record(0.20, metric: "M_track")
        recorder.record(0.70, metric: "M_reflex")

        #expect(recorder.count(for: "M_track") == 2)
        #expect(recorder.count(for: "M_reflex") == 1)
        #expect(recorder.p50(for: "M_track") == 0.10)
        #expect(recorder.p50(for: "M_reflex") == 0.70)
    }

    @Test func emptyRecorderExportsHeaderOnly() {
        let recorder = LatencyRecorder()

        #expect(recorder.csv() == "metric,p50_ms,p90_ms,count\n")
    }

    @Test func csvListsMetricsInFirstRecordedOrder() {
        var recorder = LatencyRecorder()
        recorder.record(0.0123, metric: "M_track")
        recorder.record(0.4000, metric: "M_track")
        recorder.record(0.3000, metric: "M_reflex")

        let expected = """
        metric,p50_ms,p90_ms,count
        M_track,12.3,400.0,2
        M_reflex,300.0,300.0,1

        """

        #expect(recorder.csv() == expected)
    }

    @Test func csvEscapesMetricNamesContainingCommas() {
        var recorder = LatencyRecorder()
        recorder.record(0.5, metric: "门控,打断")

        #expect(recorder.csv().contains("\"门控,打断\",500.0,500.0,1"))
    }
}
