import Foundation
import simd
import Testing
@testable import MMCore
@testable import MMPerception
@testable import MMEmotion

@Suite("ExpressionReaction")
struct ExpressionReactionTests {
    private func makeMachine(
        clock: any MMCore.Clock,
        randomValue: Double = 0.5,
        rules: ReactionRules = .defaults
    ) -> RuleBasedEmotionStateMachine {
        RuleBasedEmotionStateMachine(
            rules: rules,
            presets: ExpressionPreset.bundledDefaults,
            clock: clock,
            random: { randomValue },
            idleConfig: IdleMotionLayer.Config(blinkInterval: 100...100, breathAmplitude: 0)
        )
    }

    private func enterAttending(
        _ sm: RuleBasedEmotionStateMachine,
        at start: TimeInterval = 0
    ) async {
        await sm.handle(PerceptionFeatures(
            timestamp: start,
            isFaceTracked: true,
            facePosition: SIMD3<Float>(0, 0, 0.5),
            isLookingAtScreen: true
        ))
        await sm.handle(PerceptionFeatures(
            timestamp: start + 0.25,
            isFaceTracked: true,
            facePosition: SIMD3<Float>(0, 0, 0.5),
            isLookingAtScreen: true
        ))
    }

    @Test func smilingFrowningAndSurprisedMapToOwnEmotionsWithRandomDelayRange() async throws {
        let cases: [(UserExpression, EmotionTag, Double, TimeInterval)] = [
            (.smiling, .happy, 0.0, 0.300),
            (.frowning, .concerned, 0.5, 0.550),
            (.surprised, .surprised, 1.0, 0.800),
        ]

        for (expr, expectedEmotion, randVal, expectedDelay) in cases {
            let clock = FixedClock(initial: Date(timeIntervalSinceReferenceDate: 0))
            let sm = makeMachine(clock: clock, randomValue: randVal)
            await enterAttending(sm, at: 0)

            let triggerBase: TimeInterval = 1.0
            await sm.handle(PerceptionFeatures(
                timestamp: triggerBase,
                isFaceTracked: true,
                signals: FaceSignals(activeExpression: expr),
                facePosition: SIMD3<Float>(0, 0, 0.5),
                isLookingAtScreen: true
            ))

            let scheduledState = await sm.state
            #expect(scheduledState.kind == .attending)
            #expect(scheduledState.scheduled.count == 1)

            // 到期前 1 ms 尚未触发
            _ = await sm.pose(at: triggerBase + expectedDelay - 0.001)
            #expect(await sm.state.kind == .attending)

            // 恰好到期触发
            _ = await sm.pose(at: triggerBase + expectedDelay)
            let activeKind = await sm.state.kind
            guard case .reacting(let reaction) = activeKind else {
                Issue.record("预期进入 .reacting(\(expectedEmotion))，实际为 \(activeKind)")
                return
            }
            #expect(reaction.expression == expectedEmotion)
            #expect(reaction.expression != .sad)
            #expect(reaction.action == nil)
            #expect(reaction.returnTo == .attending)

            // 持续 1.5 s 后回到 .attending
            _ = await sm.pose(at: triggerBase + expectedDelay + 1.500)
            #expect(await sm.state.kind == .attending)
        }
    }

    @Test func cooldownPreventsFullReactionWithSoftBoostAndResumesAfter8Seconds() async throws {
        let clock = FixedClock(initial: Date(timeIntervalSinceReferenceDate: 0))
        let sm = makeMachine(clock: clock, randomValue: 0.0) // delay = 0.3 s
        await enterAttending(sm, at: 0)

        // 首次微笑 -> t = 1.0 入队，t = 1.3 触发，冷却至 9.3
        await sm.handle(PerceptionFeatures(
            timestamp: 1.0,
            isFaceTracked: true,
            signals: FaceSignals(smile: 0.8, activeExpression: .smiling),
            facePosition: SIMD3<Float>(0, 0, 0.5),
            isLookingAtScreen: true
        ))
        _ = await sm.pose(at: 1.3)
        guard case .reacting(let firstReaction) = await sm.state.kind else {
            Issue.record("首次微笑应进入 .reacting")
            return
        }
        #expect(firstReaction.expression == .happy)

        // 等首次反应结束并退出微笑，t = 3.0 回到 .attending
        await sm.handle(PerceptionFeatures(
            timestamp: 3.0,
            isFaceTracked: true,
            signals: FaceSignals(smile: 0.1, activeExpression: nil),
            facePosition: SIMD3<Float>(0, 0, 0.5),
            isLookingAtScreen: true
        ))
        #expect(await sm.state.kind == .attending)

        // 冷却期内（t = 3.3 < 9.3）再次微笑：绝不进入 .reacting、不入队，但产生柔和底色增强
        await sm.handle(PerceptionFeatures(
            timestamp: 3.3,
            isFaceTracked: true,
            signals: FaceSignals(smile: 0.8, activeExpression: .smiling),
            facePosition: SIMD3<Float>(0, 0, 0.5),
            isLookingAtScreen: true
        ))
        let duringCooldown = await sm.state
        #expect(duringCooldown.kind == .attending)
        #expect(duringCooldown.scheduled.isEmpty)

        // 在柔和增强峰值期（+0.4 s），产生低强度愉悦权重且严格小于满反应 0.8
        let boostPose = await sm.pose(at: 3.7)
        let smileWeight = boostPose.expressionWeights["mouthSmileLeft"] ?? 0
        #expect(smileWeight > 0 && smileWeight <= 0.3)
        #expect(smileWeight < 0.8)

        // 1.5 s 后柔和增强自然回落至 0
        let afterBoost = await sm.pose(at: 4.9)
        #expect((afterBoost.expressionWeights["mouthSmileLeft"] ?? 0) == 0)

        // 先清除 activeExpression，等冷却（9.3 s）结束后再次微笑 -> 正常重新排程进入 .reacting(.happy)
        await sm.handle(PerceptionFeatures(
            timestamp: 9.0,
            isFaceTracked: true,
            signals: FaceSignals(smile: 0.0, activeExpression: nil),
            facePosition: SIMD3<Float>(0, 0, 0.5),
            isLookingAtScreen: true
        ))
        await sm.handle(PerceptionFeatures(
            timestamp: 9.4,
            isFaceTracked: true,
            signals: FaceSignals(smile: 0.8, activeExpression: .smiling),
            facePosition: SIMD3<Float>(0, 0, 0.5),
            isLookingAtScreen: true
        ))
        #expect(await sm.state.scheduled.count == 1)
        _ = await sm.pose(at: 9.7)
        guard case .reacting(let secondReaction) = await sm.state.kind else {
            Issue.record("冷却结束后再次微笑应重新进入 .reacting")
            return
        }
        #expect(secondReaction.expression == .happy)
    }

    @Test func blendInAndBlendOutEnvelopeInterpolatesAccurately() async throws {
        let clock = FixedClock(initial: Date(timeIntervalSinceReferenceDate: 0))
        let sm = makeMachine(clock: clock, randomValue: 0.0) // delay = 0.3 s
        await enterAttending(sm, at: 0)

        await sm.handle(PerceptionFeatures(
            timestamp: 1.0,
            isFaceTracked: true,
            signals: FaceSignals(smile: 0.8, activeExpression: .smiling),
            facePosition: SIMD3<Float>(0, 0, 0.5),
            isLookingAtScreen: true
        ))

        let start: TimeInterval = 1.3
        let happyPresetSmile: Float = 0.8

        // +0 ms -> 0
        let p0 = await sm.pose(at: start)
        #expect(abs((p0.expressionWeights["mouthSmileLeft"] ?? 0) - 0) < 1e-4)

        // +100 ms (blendIn = 200 ms) -> 0.5 * preset
        let p100 = await sm.pose(at: start + 0.100)
        #expect(abs((p100.expressionWeights["mouthSmileLeft"] ?? 0) - happyPresetSmile * 0.5) < 1e-4)

        // +200 ms & +1200 ms -> 1.0 * preset
        let p200 = await sm.pose(at: start + 0.200)
        #expect(abs((p200.expressionWeights["mouthSmileLeft"] ?? 0) - happyPresetSmile) < 1e-4)
        let p1200 = await sm.pose(at: start + 1.200)
        #expect(abs((p1200.expressionWeights["mouthSmileLeft"] ?? 0) - happyPresetSmile) < 1e-4)

        // +1350 ms (blendOut = 300 ms, 剩 150 ms) -> 0.5 * preset
        let p1350 = await sm.pose(at: start + 1.350)
        #expect(abs((p1350.expressionWeights["mouthSmileLeft"] ?? 0) - happyPresetSmile * 0.5) < 1e-4)

        // +1500 ms -> 0 且回到 .attending
        let p1500 = await sm.pose(at: start + 1.500)
        #expect(abs((p1500.expressionWeights["mouthSmileLeft"] ?? 0) - 0) < 1e-4)
        #expect(await sm.state.kind == .attending)
    }

    @Test func continuousFramesDoNotDuplicateScheduleAndLeanBackIsNotInterrupted() async throws {
        let clock = FixedClock(initial: Date(timeIntervalSinceReferenceDate: 0))
        let sm = makeMachine(clock: clock, randomValue: 1.0) // delay = 0.8 s
        await enterAttending(sm, at: 0)

        // 连续 60 帧 smiling 只排程 1 次
        for frame in 0..<60 {
            let t = 1.0 + Double(frame) * (1.0 / 60.0)
            await sm.handle(PerceptionFeatures(
                timestamp: t,
                isFaceTracked: true,
                signals: FaceSignals(smile: 0.85, activeExpression: .smiling),
                facePosition: SIMD3<Float>(0, 0, 0.5),
                isLookingAtScreen: true
            ))
            #expect(await sm.state.scheduled.count <= 1)
        }

        // 重测：排程一个微笑反应后，在到期前触发 leanBack 动作，到期纯表情反应不得打断 leanBack
        let sm2 = makeMachine(clock: clock, randomValue: 1.0) // delay = 0.8 s
        await enterAttending(sm2, at: 0)
        await sm2.handle(PerceptionFeatures(
            timestamp: 1.0,
            isFaceTracked: true,
            signals: FaceSignals(smile: 0.85, activeExpression: .smiling),
            facePosition: SIMD3<Float>(0, 0, 0.5),
            isLookingAtScreen: true
        ))
        // 1.2 s 处触发快速靠近 -> leanBack（持续至 2.7 s）
        await sm2.handle(PerceptionFeatures(
            timestamp: 1.2,
            isFaceTracked: true,
            signals: FaceSignals(smile: 0.85, activeExpression: .smiling),
            facePosition: SIMD3<Float>(0, 0, 0.35),
            isLookingAtScreen: true
        ))
        guard case .reacting(let leanReaction) = await sm2.state.kind else {
            Issue.record("快速靠近应进入 leanBack 反应")
            return
        }
        #expect(leanReaction.action == .leanBack)

        // 1.8 s 微笑计划反应到期，但 leanBack 仍在播放，不得被打断
        _ = await sm2.pose(at: 1.85)
        guard case .reacting(let stillLean) = await sm2.state.kind else {
            Issue.record("leanBack 期间应保持在 .reacting")
            return
        }
        #expect(stillLean.action == .leanBack)

        // resetToIdle 清空 scheduled
        await sm2.resetToIdle(at: 2.0)
        #expect(await sm2.state.kind == .idle)
        #expect(await sm2.state.scheduled.isEmpty)

        // 离屏 3 s 回 Idle 同样清空 scheduled
        let sm3 = makeMachine(clock: clock, randomValue: 1.0) // delay = 0.8 s
        await enterAttending(sm3, at: 0)
        await sm3.handle(PerceptionFeatures(
            timestamp: 1.0,
            isFaceTracked: true,
            signals: FaceSignals(smile: 0.85, activeExpression: .smiling),
            facePosition: SIMD3<Float>(0, 0, 0.5),
            isLookingAtScreen: true
        ))
        #expect(await sm3.state.scheduled.count == 1)
        // 人脸丢失 3 s 后回 Idle（先经过生产路径 handle(isFaceTracked: false) 再 pose），scheduled 应被清空且不得触发 .reacting
        await sm3.handle(PerceptionFeatures(
            timestamp: 1.1,
            isFaceTracked: false,
            signals: FaceSignals(),
            facePosition: nil,
            isLookingAtScreen: false
        ))
        await sm3.handle(PerceptionFeatures(
            timestamp: 4.1,
            isFaceTracked: false,
            signals: FaceSignals(),
            facePosition: nil,
            isLookingAtScreen: false
        ))
        #expect(await sm3.state.kind == .idle)
        #expect(await sm3.state.scheduled.isEmpty)
        _ = await sm3.pose(at: 4.1)
        #expect(await sm3.state.kind == .idle)
        #expect(await sm3.state.scheduled.isEmpty)
    }

    @Test func envelopeScalesProportionallyWhenBlendExceedsDuration() {
        // blendIn(0.6) + blendOut(0.6) > duration(0.6) -> 各缩放为 0.3
        #expect(abs(RuleBasedEmotionStateMachine.envelope(elapsed: 0.15, duration: 0.6, blendIn: 0.6, blendOut: 0.6) - 0.5) < 1e-5)
        #expect(abs(RuleBasedEmotionStateMachine.envelope(elapsed: 0.30, duration: 0.6, blendIn: 0.6, blendOut: 0.6) - 1.0) < 1e-5)
        #expect(abs(RuleBasedEmotionStateMachine.envelope(elapsed: 0.45, duration: 0.6, blendIn: 0.6, blendOut: 0.6) - 0.5) < 1e-5)
        #expect(RuleBasedEmotionStateMachine.envelope(elapsed: -0.1, duration: 0.6, blendIn: 0.2, blendOut: 0.3) == 0)
        #expect(RuleBasedEmotionStateMachine.envelope(elapsed: 0.6, duration: 0.6, blendIn: 0.2, blendOut: 0.3) == 0)
    }

    @Test func updatePresetAppliesImmediatelyToSubsequentReaction() async throws {
        let clock = FixedClock(initial: Date(timeIntervalSinceReferenceDate: 0))
        let sm = makeMachine(clock: clock, randomValue: 0.0) // delay = 0.3 s
        await enterAttending(sm, at: 0)

        let customConcerned = ExpressionPreset(
            emotion: .concerned,
            weights: ["eyeSquintLeft": 0.72, "eyeSquintRight": 0.72, "eyeBlinkLeft": 0.25, "eyeBlinkRight": 0.25]
        )
        await sm.updatePreset(customConcerned)

        await sm.handle(PerceptionFeatures(
            timestamp: 1.0,
            isFaceTracked: true,
            signals: FaceSignals(frown: 0.8, activeExpression: .frowning),
            facePosition: SIMD3<Float>(0, 0, 0.5),
            isLookingAtScreen: true
        ))
        _ = await sm.pose(at: 1.3)
        let peakPose = await sm.pose(at: 1.6)
        #expect(abs((peakPose.expressionWeights["eyeSquintLeft"] ?? 0) - 0.72) < 1e-4)
        #expect(abs((peakPose.expressionWeights["eyeBlinkLeft"] ?? 0) - 0.25) < 1e-4)
    }

    @Test func reflexLatencyTrackerMeasuresAccurateDelayAndIgnoresCooldown() async throws {
        let clock = FixedClock(initial: Date(timeIntervalSinceReferenceDate: 0))
        let sm = makeMachine(clock: clock, randomValue: 0.5) // delay = 0.550 s
        var tracker = ReflexLatencyTracker()
        await enterAttending(sm, at: 0)

        let t0: TimeInterval = 2.0
        await sm.handle(PerceptionFeatures(
            timestamp: t0,
            isFaceTracked: true,
            signals: FaceSignals(smile: 0.8, activeExpression: .smiling),
            facePosition: SIMD3<Float>(0, 0, 0.5),
            isLookingAtScreen: true
        ))
        tracker.observePerception(activeExpression: .smiling, state: await sm.state, at: t0)

        // 到期前不产生样本
        _ = await sm.pose(at: t0 + 0.500)
        #expect(tracker.observeAppliedState(await sm.state.kind, at: t0 + 0.500) == nil)

        // 到期进入 .reacting(.happy)，精准测出 0.550 s
        _ = await sm.pose(at: t0 + 0.550)
        let sample = tracker.observeAppliedState(await sm.state.kind, at: t0 + 0.550)
        #expect(sample != nil)
        #expect(abs((sample ?? 0) - 0.550) < 1e-6)

        // 结束反应后，在冷却期内再次微笑，不应武装也不产生样本
        await sm.handle(PerceptionFeatures(
            timestamp: t0 + 2.5,
            isFaceTracked: true,
            signals: FaceSignals(smile: 0, activeExpression: nil),
            facePosition: SIMD3<Float>(0, 0, 0.5),
            isLookingAtScreen: true
        ))
        tracker.observePerception(activeExpression: nil, state: await sm.state, at: t0 + 2.5)

        await sm.handle(PerceptionFeatures(
            timestamp: t0 + 3.0,
            isFaceTracked: true,
            signals: FaceSignals(smile: 0.85, activeExpression: .smiling),
            facePosition: SIMD3<Float>(0, 0, 0.5),
            isLookingAtScreen: true
        ))
        tracker.observePerception(activeExpression: .smiling, state: await sm.state, at: t0 + 3.0)
        _ = await sm.pose(at: t0 + 3.6)
        #expect(tracker.observeAppliedState(await sm.state.kind, at: t0 + 3.6) == nil)

        // 回归：同一表情排程窗口内短暂退出再重入，不得覆写原 startedAt
        let smReenter = makeMachine(clock: clock, randomValue: 1.0) // delay = 0.800 s
        var reenterTracker = ReflexLatencyTracker()
        await enterAttending(smReenter, at: 0)

        await smReenter.handle(PerceptionFeatures(
            timestamp: 1.00,
            isFaceTracked: true,
            signals: FaceSignals(surprise: 0.9, activeExpression: .surprised),
            facePosition: SIMD3<Float>(0, 0, 0.5),
            isLookingAtScreen: true
        ))
        reenterTracker.observePerception(activeExpression: .surprised, state: await smReenter.state, at: 1.00)

        // 1.15 短暂退出，1.60 重入同一表情（原排程 triggerAt 仍为 1.80）
        await smReenter.handle(PerceptionFeatures(
            timestamp: 1.15,
            isFaceTracked: true,
            signals: FaceSignals(surprise: 0.1, activeExpression: nil),
            facePosition: SIMD3<Float>(0, 0, 0.5),
            isLookingAtScreen: true
        ))
        reenterTracker.observePerception(activeExpression: nil, state: await smReenter.state, at: 1.15)

        await smReenter.handle(PerceptionFeatures(
            timestamp: 1.60,
            isFaceTracked: true,
            signals: FaceSignals(surprise: 0.9, activeExpression: .surprised),
            facePosition: SIMD3<Float>(0, 0, 0.5),
            isLookingAtScreen: true
        ))
        reenterTracker.observePerception(activeExpression: .surprised, state: await smReenter.state, at: 1.60)

        _ = await smReenter.pose(at: 1.80)
        let reenterSample = reenterTracker.observeAppliedState(await smReenter.state.kind, at: 1.80)
        #expect(reenterSample != nil)
        #expect(abs((reenterSample ?? 0) - 0.800) < 1e-6)
    }
}

private final class FixedClock: MMCore.Clock, @unchecked Sendable {
    var now: Date

    init(initial: Date) {
        self.now = initial
    }

    func sleep(for duration: Duration) async throws {}
}
