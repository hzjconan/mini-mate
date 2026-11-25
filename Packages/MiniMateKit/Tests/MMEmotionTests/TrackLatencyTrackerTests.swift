import Foundation
import Testing
import simd
import MMCore
import MMEmotion

@Suite("TrackLatencyTracker")
struct TrackLatencyTrackerTests {

    @Test("显著人脸位移后头部跨越阈值精准返回 M_track 样本并接入 LatencyRecorder")
    func recordsAccurateLatencyOnSignificantMoveAndHeadResponse() throws {
        var tracker = TrackLatencyTracker()
        var recorder = LatencyRecorder()

        // 初始位置基线
        tracker.observeFacePosition(SIMD3(0, 0, 0.5), currentHeadRotation: .zero, at: 1.000)
        let initial = tracker.observeAppliedHeadRotation(.zero, at: 1.010)
        #expect(initial == nil)

        // 2 cm 位移（> 1.5 cm 阈值）触发刺激
        tracker.observeFacePosition(SIMD3(0.02, 0, 0.5), currentHeadRotation: .zero, at: 1.020)

        // 未跨越 0.5° 阈值前不采样
        let tinyYaw: Float = 0.2 * .pi / 180
        let tinySample = tracker.observeAppliedHeadRotation(SIMD3(0, tinyYaw, 0), at: 1.040)
        #expect(tinySample == nil)

        // 45 ms 后头部旋转 1.0°（> 0.5°）产生样本
        let respondedYaw: Float = 1.0 * .pi / 180
        let rawSample = tracker.observeAppliedHeadRotation(SIMD3(0, respondedYaw, 0), at: 1.065)
        let sample = try #require(rawSample)
        #expect(abs(sample - 0.045) < 1e-6)

        recorder.record(sample, metric: "M_track")
        recorder.record(0.080, metric: "M_track")
        #expect(recorder.count(for: "M_track") == 2)
        #expect(abs((recorder.p50(for: "M_track") ?? 0) - 0.045) < 1e-6)
        #expect(abs((recorder.p90(for: "M_track") ?? 0) - 0.080) < 1e-6)
    }

    @Test("微小抖动不触发刺激，超时与人脸丢失丢弃待测刺激")
    func ignoresTinyJitterAndDropsTimedOutOrLostStimulus() {
        var tracker = TrackLatencyTracker(
            positionDeltaThreshold: 0.015,
            headRotationThreshold: 0.5 * .pi / 180,
            timeout: 1.0
        )

        // 基线
        tracker.observeFacePosition(SIMD3(0, 0, 0.5), currentHeadRotation: .zero, at: 0.0)
        // 0.5 cm 抖动（< 1.5 cm）不触发
        tracker.observeFacePosition(SIMD3(0.005, 0, 0.5), currentHeadRotation: .zero, at: 0.02)
        let jitterSample = tracker.observeAppliedHeadRotation(SIMD3(0, 2.0 * .pi / 180, 0), at: 0.05)
        #expect(jitterSample == nil)

        // 触发显著位移但 1.2s 后才响应（超 1.0s 上限）→ 丢弃
        tracker.observeFacePosition(SIMD3(0.05, 0, 0.5), currentHeadRotation: .zero, at: 1.0)
        let timeoutSample = tracker.observeAppliedHeadRotation(SIMD3(0, 2.0 * .pi / 180, 0), at: 2.2)
        #expect(timeoutSample == nil)

        // 触发显著位移后人脸丢失 → 清空待测刺激
        tracker.observeFacePosition(SIMD3(0.10, 0, 0.5), currentHeadRotation: .zero, at: 3.0)
        tracker.observeFacePosition(nil, currentHeadRotation: .zero, at: 3.02)
        let lostSample = tracker.observeAppliedHeadRotation(SIMD3(0, 2.0 * .pi / 180, 0), at: 3.05)
        #expect(lostSample == nil)

        // 异常时钟倒退（latency < 0）→ 丢弃不产生负样本
        tracker.observeFacePosition(SIMD3(0, 0, 0.5), currentHeadRotation: .zero, at: 5.0)
        tracker.observeFacePosition(SIMD3(0.05, 0, 0.5), currentHeadRotation: .zero, at: 5.1)
        let negativeSample = tracker.observeAppliedHeadRotation(SIMD3(0, 2.0 * .pi / 180, 0), at: 5.05)
        #expect(negativeSample == nil)

        // 纯 z 轴前后移动不触发转头延迟刺激
        tracker.reset()
        tracker.observeFacePosition(SIMD3(0, 0, 0.50), currentHeadRotation: .zero, at: 6.0)
        tracker.observeFacePosition(SIMD3(0, 0, 0.35), currentHeadRotation: .zero, at: 6.1)
        let zOnlySample = tracker.observeAppliedHeadRotation(SIMD3(0, 2.0 * .pi / 180, 0), at: 6.15)
        #expect(zOnlySample == nil)
    }
}
