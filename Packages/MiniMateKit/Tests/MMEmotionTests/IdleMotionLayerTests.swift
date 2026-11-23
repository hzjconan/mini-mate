import Foundation
import Testing
import MMCore
import MMAvatar

@Suite("IdleMotionLayer")
struct IdleMotionLayerTests {
    /// 固定随机值，使眨眼间隔可预测（0 → 2 s，1 → 6 s）。
    private func makeLayer(
        config: IdleMotionLayer.Config = .init(),
        random: Double = 0.5,
        clock: any Clock = SystemClock()
    ) -> IdleMotionLayer {
        IdleMotionLayer(config: config, clock: clock, random: { random })
    }

    @Test func firstBlinkStartsNoEarlierThanShortestInterval() {
        var layer = makeLayer(random: 0)

        #expect(layer.update(at: 0).eyeBlink == 0)
        #expect(layer.update(at: 1.99).eyeBlink == 0)
        #expect(layer.update(at: 2.0).eyeBlink == 0)
    }

    @Test func blinkPeaksMidwayThroughItsDuration() {
        var layer = makeLayer(random: 0)
        layer.update(at: 0)
        layer.update(at: 2.0)

        let peak = layer.update(at: 2.0 + 0.075)

        #expect(peak.eyeBlink > 0.99)
    }

    @Test func blinkEndsAndNextStartsOneIntervalAfterPreviousStart() {
        var layer = makeLayer(random: 0)
        layer.update(at: 0)

        layer.update(at: 2.0)
        #expect(layer.update(at: 2.2).eyeBlink == 0)
        // 第二次眨眼仍在 [2, 6] s 内，且从上次起始算起正好 2 s
        #expect(layer.update(at: 3.99).eyeBlink == 0)
        #expect(layer.update(at: 4.1).eyeBlink > 0)
    }

    @Test func longestIntervalIsSixSeconds() {
        var layer = makeLayer(random: 1)
        layer.update(at: 0)

        #expect(layer.update(at: 5.99).eyeBlink == 0)
        #expect(layer.update(at: 6.075).eyeBlink > 0.99)
    }

    @Test func weightsStayWithinUnitRange() {
        var layer = makeLayer(random: 0.5)
        var time: TimeInterval = 0

        while time <= 20 {
            let motion = layer.update(at: time)
            #expect(motion.eyeBlink >= 0 && motion.eyeBlink <= 1)
            #expect(abs(motion.headRotation.x) <= layer.config.breathAmplitude + 1e-6)
            time += 1.0 / 60
        }
    }

    @Test func breathFollowsConfiguredPeriod() {
        let config = IdleMotionLayer.Config(breathPeriod: 4, breathAmplitude: 0.05)
        var layer = makeLayer(config: config)
        let amplitude = config.breathAmplitude

        layer.update(at: 0)
        #expect(abs(layer.update(at: 1).headRotation.x - amplitude) < 1e-6)
        #expect(abs(layer.update(at: 2).headRotation.x) < 1e-6)
        #expect(abs(layer.update(at: 3).headRotation.x + amplitude) < 1e-6)
        #expect(abs(layer.update(at: 4).headRotation.x) < 1e-6)
    }

    @Test func updateNowReadsInjectedClock() {
        let clock = FakeClock(now: Date(timeIntervalSinceReferenceDate: 1))
        var layer = makeLayer(clock: clock)

        // 1 s 处于 4 s 呼吸周期的四分之一处，头部倾角达到正向最大
        #expect(abs(layer.updateNow().headRotation.x - layer.config.breathAmplitude) < 1e-6)
    }
}

private final class FakeClock: Clock, @unchecked Sendable {
    var now: Date

    init(now: Date) {
        self.now = now
    }

    func sleep(for duration: Duration) async throws {}
}
