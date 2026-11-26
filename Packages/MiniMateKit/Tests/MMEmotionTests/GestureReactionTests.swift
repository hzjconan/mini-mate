import Foundation
import simd
import Testing
@testable import MMCore
@testable import MMPerception
@testable import MMEmotion

@Suite("GestureReaction")
struct GestureReactionTests {
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

    @Test func allThreeGesturesTriggerImmediatelyWithExpectedEmotionAndAction() async throws {
        let cases: [(GestureKind, EmotionTag, ActionTag)] = [
            (.wave, .happy, .wave),
            (.heart, .shy, .heart),
            (.thumbsUp, .happy, .nod),
        ]

        for (gestureKind, expectedEmotion, expectedAction) in cases {
            let clock = FixedClock(initial: Date(timeIntervalSinceReferenceDate: 0))
            let sm = makeMachine(clock: clock, randomValue: 0.5)
            await enterAttending(sm, at: 0)
            // 先消费掉可能存在的进入姿态
            let baselinePose = await sm.pose(at: 0.5)
            #expect(baselinePose.action == nil)

            let t: TimeInterval = 1.0
            await sm.handle(PerceptionFeatures(
                timestamp: t,
                isFaceTracked: true,
                facePosition: SIMD3<Float>(0, 0, 0.5),
                isLookingAtScreen: true,
                gesture: GestureEvent(kind: gestureKind, confidence: 0.9, timestamp: t)
            ))

            // 立即进入 .reacting（0 延迟 <= 300 ms），且不进 scheduled 队列
            let activeState = await sm.state
            #expect(activeState.scheduled.isEmpty)
            guard case .reacting(let reaction) = activeState.kind else {
                Issue.record("手势 \(gestureKind) 应立即进入 .reacting，实际为 \(activeState.kind)")
                return
            }
            #expect(reaction.expression == expectedEmotion)
            #expect(reaction.action == expectedAction)
            #expect(reaction.returnTo == .attending)

            // 立即求值姿态：应产出对应动作指令
            let immediatePose = await sm.pose(at: t)
            #expect(immediatePose.action == .play(expectedAction))

            // 峰值时刻：heart(.shy) 应包含 +8° 低头增量
            let peakPose = await sm.pose(at: t + 0.5)
            #expect(peakPose.action == nil)
            if gestureKind == .heart {
                let expectedShyPitch: Float = 8 * .pi / 180
                #expect(abs((peakPose.headRotation.x - baselinePose.headRotation.x) - expectedShyPitch) < 1e-3)
            }

            // 持续 1.5 s 后回到 .attending
            _ = await sm.pose(at: t + 1.5)
            #expect(await sm.state.kind == .attending)
        }
    }

    @Test func cooldownBlocksRepeatedSameGestureWithSoftBoostAndResumesAfter8Seconds() async throws {
        let clock = FixedClock(initial: Date(timeIntervalSinceReferenceDate: 0))
        let sm = makeMachine(clock: clock)
        await enterAttending(sm, at: 0)

        // 首次挥手：t = 1.0 立即触发，冷却至 9.0
        await sm.handle(PerceptionFeatures(
            timestamp: 1.0,
            isFaceTracked: true,
            facePosition: SIMD3<Float>(0, 0, 0.5),
            isLookingAtScreen: true,
            gesture: GestureEvent(kind: .wave, confidence: 0.9, timestamp: 1.0)
        ))
        let firstPose = await sm.pose(at: 1.0)
        #expect(firstPose.action == .play(.wave))

        // t = 3.0 反应已结束，回到 .attending
        _ = await sm.pose(at: 3.0)
        #expect(await sm.state.kind == .attending)

        // 冷却期内（t = 4.0 < 9.0）再次挥手：不进入 .reacting、不发动作，但产生柔和底色增强 ∈ (0, 0.3]
        await sm.handle(PerceptionFeatures(
            timestamp: 4.0,
            isFaceTracked: true,
            facePosition: SIMD3<Float>(0, 0, 0.5),
            isLookingAtScreen: true,
            gesture: GestureEvent(kind: .wave, confidence: 0.9, timestamp: 4.0)
        ))
        #expect(await sm.state.kind == .attending)
        let cooldownImmediate = await sm.pose(at: 4.0)
        #expect(cooldownImmediate.action == nil)

        let boostPose = await sm.pose(at: 4.5)
        let smileBoost = boostPose.expressionWeights["mouthSmileLeft"] ?? 0
        #expect(smileBoost > 0.01)
        #expect(smileBoost <= 0.30 + 1e-5)

        // 冷却结束后（t = 9.1 >= 9.0）再次挥手，正常重新进入 .reacting(happy, .wave)
        await sm.handle(PerceptionFeatures(
            timestamp: 9.1,
            isFaceTracked: true,
            facePosition: SIMD3<Float>(0, 0, 0.5),
            isLookingAtScreen: true,
            gesture: GestureEvent(kind: .wave, confidence: 0.9, timestamp: 9.1)
        ))
        guard case .reacting(let resumed) = await sm.state.kind else {
            Issue.record("冷却结束后再次挥手应进入 .reacting")
            return
        }
        #expect(resumed.expression == .happy)
        #expect(resumed.action == .wave)
        let resumedPose = await sm.pose(at: 9.1)
        #expect(resumedPose.action == .play(.wave))
    }

    @Test func speakingProtectionIdleTriggerAndGestureInterruption() async throws {
        // 1. Speaking 保护（S-5）：不改 state.kind、不发 action、仅叠加 <= 0.3 轻量微表情
        do {
            let clock = FixedClock(initial: Date(timeIntervalSinceReferenceDate: 0))
            let sm = makeMachine(clock: clock)
            await sm._setStateKindForTesting(.speaking(.neutral), at: 0)

            await sm.handle(PerceptionFeatures(
                timestamp: 1.0,
                isFaceTracked: true,
                facePosition: SIMD3<Float>(0, 0, 0.5),
                isLookingAtScreen: true,
                gesture: GestureEvent(kind: .wave, confidence: 0.95, timestamp: 1.0)
            ))
            #expect(await sm.state.kind == .speaking(.neutral))
            let poseAtTrigger = await sm.pose(at: 1.0)
            #expect(poseAtTrigger.action == nil)

            let overlayPose = await sm.pose(at: 1.5)
            let smileOverlay = overlayPose.expressionWeights["mouthSmileLeft"] ?? 0
            #expect(smileOverlay > 0.01)
            #expect(smileOverlay <= 0.30 + 1e-5)
        }

        // 2. Idle（含无脸遮挡场景）收到手势立即进入 .reacting(returnTo: .idle)
        do {
            let clock = FixedClock(initial: Date(timeIntervalSinceReferenceDate: 0))
            let sm = makeMachine(clock: clock)
            #expect(await sm.state.kind == .idle)

            await sm.handle(PerceptionFeatures(
                timestamp: 1.0,
                isFaceTracked: false,
                facePosition: nil,
                isLookingAtScreen: false,
                gesture: GestureEvent(kind: .wave, confidence: 0.9, timestamp: 1.0)
            ))
            guard case .reacting(let reaction) = await sm.state.kind else {
                Issue.record("Idle 收到 wave 应立即进入 .reacting")
                return
            }
            #expect(reaction.expression == .happy)
            #expect(reaction.action == .wave)
            #expect(reaction.returnTo == .idle)
            #expect((await sm.pose(at: 1.0)).action == .play(.wave))

            _ = await sm.pose(at: 2.5)
            #expect(await sm.state.kind == .idle)
        }

        // 3. wave 进行中收到 heart 立即切换至 heart，且旧权重进入平滑淡出层
        do {
            let clock = FixedClock(initial: Date(timeIntervalSinceReferenceDate: 0))
            let sm = makeMachine(clock: clock)
            await enterAttending(sm, at: 0)

            await sm.handle(PerceptionFeatures(
                timestamp: 1.0,
                isFaceTracked: true,
                facePosition: SIMD3<Float>(0, 0, 0.5),
                isLookingAtScreen: true,
                gesture: GestureEvent(kind: .wave, confidence: 0.9, timestamp: 1.0)
            ))
            _ = await sm.pose(at: 1.0) // 消费 .wave 动作
            let wavePeakPose = await sm.pose(at: 1.5)
            let waveSmilePeak = wavePeakPose.expressionWeights["mouthSmileLeft"] ?? 0
            #expect(waveSmilePeak > 0.4)

            // t = 1.6 时收到 heart，立即打断 wave
            await sm.handle(PerceptionFeatures(
                timestamp: 1.6,
                isFaceTracked: true,
                facePosition: SIMD3<Float>(0, 0, 0.5),
                isLookingAtScreen: true,
                gesture: GestureEvent(kind: .heart, confidence: 0.92, timestamp: 1.6)
            ))
            guard case .reacting(let interrupted) = await sm.state.kind else {
                Issue.record("heart 应打断 wave 进入新 .reacting")
                return
            }
            #expect(interrupted.expression == .shy)
            #expect(interrupted.action == .heart)
            #expect(interrupted.returnTo == .attending)

            let switchPose = await sm.pose(at: 1.6)
            #expect(switchPose.action == .play(.heart))
            // 切换瞬间旧 happy 权重由 fadingLayers 平滑保持而非骤降为 0
            let fadingSmile = switchPose.expressionWeights["mouthSmileLeft"] ?? 0
            #expect(fadingSmile > 0.3)
        }
    }

    @Test func gestureProtectsActionFromExpressionAndIsolatesReflexLatencyTracker() async throws {
        let clock = FixedClock(initial: Date(timeIntervalSinceReferenceDate: 0))
        let sm = makeMachine(clock: clock, randomValue: 0.0) // 表情延迟 0.3 s
        await enterAttending(sm, at: 0)

        // t = 1.0 触发微笑排程（将于 1.3 s 到期）并立即武装 ReflexLatencyTracker
        await sm.handle(PerceptionFeatures(
            timestamp: 1.0,
            isFaceTracked: true,
            signals: FaceSignals(smile: 0.85, activeExpression: .smiling),
            facePosition: SIMD3<Float>(0, 0, 0.5),
            isLookingAtScreen: true
        ))
        let scheduledState = await sm.state
        #expect(scheduledState.scheduled.count == 1)

        var tracker = ReflexLatencyTracker()
        tracker.observePerception(activeExpression: .smiling, state: scheduledState, at: 1.0)

        // t = 1.1 触发挥手手势（持续至 2.6 s）
        await sm.handle(PerceptionFeatures(
            timestamp: 1.1,
            isFaceTracked: true,
            signals: FaceSignals(smile: 0.85, activeExpression: .smiling),
            facePosition: SIMD3<Float>(0, 0, 0.5),
            isLookingAtScreen: true,
            gesture: GestureEvent(kind: .wave, confidence: 0.9, timestamp: 1.1)
        ))
        _ = await sm.pose(at: 1.1)

        // t = 1.35 微笑计划反应到期，但手势动作仍在播，不得打断动作
        _ = await sm.pose(at: 1.35)
        let activeKind = await sm.state.kind
        guard case .reacting(let active) = activeKind else {
            Issue.record("手势动作期间应维持 .reacting")
            return
        }
        #expect(active.action == .wave)

        // ReflexLatencyTracker 已武装，但收到带动作的手势 .reacting 时必须返回 nil（不污染 M_reflex）
        #expect(tracker.observeAppliedState(activeKind, at: 1.35) == nil)

        // 正例对照：同一已武装的 tracker 收到无动作纯表情 .reacting(.happy, action: nil) 时应精准返回 0.35 s
        let pureExpressionKind: AvatarStateKind = .reacting(Reaction(
            expression: .happy,
            action: nil,
            duration: .milliseconds(1500),
            returnTo: .attending
        ))
        let pureSample = tracker.observeAppliedState(pureExpressionKind, at: 1.35)
        #expect(pureSample != nil)
        #expect(abs((pureSample ?? 0) - 0.35) < 1e-6)
    }

    @Test func updateCooldownClampsTo3Through8AndTakesEffectImmediately() async throws {
        let clock = FixedClock(initial: Date(timeIntervalSinceReferenceDate: 0))
        let sm = makeMachine(clock: clock)
        await enterAttending(sm, at: 0)

        // 设为 5 秒冷却
        await sm.updateCooldown(5.0, at: 0.5)
        await sm.handle(PerceptionFeatures(
            timestamp: 1.0,
            isFaceTracked: true,
            facePosition: SIMD3<Float>(0, 0, 0.5),
            isLookingAtScreen: true,
            gesture: GestureEvent(kind: .wave, confidence: 0.9, timestamp: 1.0)
        ))
        _ = await sm.pose(at: 1.0)
        _ = await sm.pose(at: 3.0) // 回到 .attending

        // t = 5.5 < 6.0 仍在 5 秒冷却内
        await sm.handle(PerceptionFeatures(
            timestamp: 5.5,
            isFaceTracked: true,
            facePosition: SIMD3<Float>(0, 0, 0.5),
            isLookingAtScreen: true,
            gesture: GestureEvent(kind: .wave, confidence: 0.9, timestamp: 5.5)
        ))
        #expect(await sm.state.kind == .attending)

        // t = 6.1 >= 6.0 冷却结束，可重新触发
        await sm.handle(PerceptionFeatures(
            timestamp: 6.1,
            isFaceTracked: true,
            facePosition: SIMD3<Float>(0, 0, 0.5),
            isLookingAtScreen: true,
            gesture: GestureEvent(kind: .wave, confidence: 0.9, timestamp: 6.1)
        ))
        guard case .reacting(let second) = await sm.state.kind else {
            Issue.record("5 秒冷却结束后应重新触发 wave")
            return
        }
        #expect(second.action == .wave)

        // 传入越界值 1.0 秒应被夹紧到最低 3.0 秒
        await sm.updateCooldown(1.0, at: 6.1)
        _ = await sm.pose(at: 8.0) // 回到 .attending
        // 8.5 < 6.1 + 3.0 (9.1)，仍在 3 秒最低冷却内
        await sm.handle(PerceptionFeatures(
            timestamp: 8.5,
            isFaceTracked: true,
            facePosition: SIMD3<Float>(0, 0, 0.5),
            isLookingAtScreen: true,
            gesture: GestureEvent(kind: .wave, confidence: 0.9, timestamp: 8.5)
        ))
        #expect(await sm.state.kind == .attending)

        // 9.2 >= 9.1 冷却结束
        await sm.handle(PerceptionFeatures(
            timestamp: 9.2,
            isFaceTracked: true,
            facePosition: SIMD3<Float>(0, 0, 0.5),
            isLookingAtScreen: true,
            gesture: GestureEvent(kind: .wave, confidence: 0.9, timestamp: 9.2)
        ))
        guard case .reacting(let third) = await sm.state.kind else {
            Issue.record("3 秒最低冷却结束后应重新触发 wave")
            return
        }
        #expect(third.action == .wave)

        // 传入越界上限 20.0 秒应被夹紧到最高 8.0 秒，传入 .nan 应忽略不破坏当前 8.0 秒配置
        await sm.updateCooldown(20.0, at: 9.2)
        await sm.updateCooldown(.nan, at: 9.2)
        _ = await sm.pose(at: 11.0) // 回到 .attending（此前第 3 次按 3 秒冷却，12.2 结束）
        // 在 12.5 触发第 4 次，新触发应按夹紧后的 8.0 秒冷却至 20.5
        await sm.handle(PerceptionFeatures(
            timestamp: 12.5,
            isFaceTracked: true,
            facePosition: SIMD3<Float>(0, 0, 0.5),
            isLookingAtScreen: true,
            gesture: GestureEvent(kind: .wave, confidence: 0.9, timestamp: 12.5)
        ))
        guard case .reacting(let fourth) = await sm.state.kind else {
            Issue.record("第 4 次 wave 应在 12.5 触发")
            return
        }
        #expect(fourth.action == .wave)

        _ = await sm.pose(at: 14.5) // 回到 .attending
        // 20.4 < 12.5 + 8.0 (20.5)，仍在 8 秒最高冷却内
        await sm.handle(PerceptionFeatures(
            timestamp: 20.4,
            isFaceTracked: true,
            facePosition: SIMD3<Float>(0, 0, 0.5),
            isLookingAtScreen: true,
            gesture: GestureEvent(kind: .wave, confidence: 0.9, timestamp: 20.4)
        ))
        #expect(await sm.state.kind == .attending)

        // 20.6 >= 20.5 冷却结束（而非 20 秒）
        await sm.handle(PerceptionFeatures(
            timestamp: 20.6,
            isFaceTracked: true,
            facePosition: SIMD3<Float>(0, 0, 0.5),
            isLookingAtScreen: true,
            gesture: GestureEvent(kind: .wave, confidence: 0.9, timestamp: 20.6)
        ))
        guard case .reacting(let fifth) = await sm.state.kind else {
            Issue.record("8 秒最高冷却结束后应重新触发 wave")
            return
        }
        #expect(fifth.action == .wave)
    }
}

private final class FixedClock: MMCore.Clock, @unchecked Sendable {
    var now: Date

    init(initial: Date) {
        self.now = initial
    }

    func sleep(for duration: Duration) async throws {}
}
