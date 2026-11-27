import Foundation
import Testing
import simd
import MMCore
import MMEmotion
import MMPerception

private final class ManualClock: MMCore.Clock, @unchecked Sendable {
    private let lock = NSLock()
    private var currentSeconds: TimeInterval

    init(seconds: TimeInterval = 100.0) {
        self.currentSeconds = seconds
    }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return Date(timeIntervalSinceReferenceDate: currentSeconds)
    }

    func set(_ seconds: TimeInterval) {
        lock.lock()
        currentSeconds = seconds
        lock.unlock()
    }

    func advance(by delta: TimeInterval) {
        lock.lock()
        currentSeconds += delta
        lock.unlock()
    }

    func sleep(for duration: Duration) async throws {}
}

@Suite("ConversationTransition")
struct ConversationTransitionTests {

    private func makeFaceFeature(
        at t: TimeInterval,
        isTracked: Bool = true,
        isLooking: Bool = true,
        position: SIMD3<Float>? = SIMD3<Float>(0, 0, 0.5),
        activeExpression: UserExpression? = nil,
        gesture: GestureEvent? = nil
    ) -> PerceptionFeatures {
        PerceptionFeatures(
            timestamp: t,
            isFaceTracked: isTracked,
            rawBlendShapes: [:],
            signals: FaceSignals(activeExpression: activeExpression),
            facePosition: isTracked ? position : nil,
            isLookingAtScreen: isTracked ? isLooking : false,
            gesture: gesture
        )
    }

    private func enterAttending(
        _ sm: RuleBasedEmotionStateMachine,
        clock: ManualClock,
        at t0: TimeInterval = 100.0
    ) async {
        clock.set(t0)
        await sm.handle(makeFaceFeature(at: t0))
        clock.set(t0 + 0.25)
        await sm.handle(makeFaceFeature(at: t0 + 0.25))
    }

    // MARK: - 主干流程 & S-4

    @Test("全流程主干：Attending → Listening → Thinking → userEmotion → Speaking → assistantEmotion → Attending")
    func fullConversationFlowReturnsToAttendingWhenFacePresent() async {
        let clock = ManualClock(seconds: 100.0)
        let sm = RuleBasedEmotionStateMachine(clock: clock, random: { 0.5 })
        await enterAttending(sm, clock: clock, at: 100.0)
        #expect(await sm.state.kind == .attending)

        clock.set(101.0)
        await sm.handle(ConversationEvent.userSpeechStarted)
        #expect(await sm.state.kind == .listening)

        // S-4：userSpeechEnded 后 0 ms（< 100 ms）进入 Thinking
        clock.set(102.0)
        await sm.handle(ConversationEvent.userSpeechEnded)
        let thinkingState = await sm.state
        #expect(thinkingState.kind == .thinking)
        #expect(abs(thinkingState.enteredAt - 102.0) < 1e-6)

        clock.set(102.1)
        await sm.handle(ConversationEvent.userEmotion(.sad))
        #expect(await sm.state.kind == .thinking)
        #expect(await sm.state.baseEmotion == .concerned)

        clock.set(102.5)
        await sm.handle(ConversationEvent.assistantSpeechStarted)
        #expect(await sm.state.kind == .speaking(.concerned))

        clock.set(102.6)
        await sm.handle(ConversationEvent.assistantEmotion(.gentle))
        #expect(await sm.state.kind == .speaking(.gentle))

        clock.set(104.0)
        await sm.handle(ConversationEvent.assistantSpeechEnded)
        #expect(await sm.state.kind == .attending)
    }

    @Test("无人脸或离屏 >= 3s 时，assistantSpeechEnded 返回 Idle 且不意外触发 lookAround")
    func assistantSpeechEndedReturnsToIdleWhenNoFaceOrFaceLost() async {
        // 1. 从 Idle 开始对话（从未见人脸）
        let clock1 = ManualClock(seconds: 100.0)
        let sm1 = RuleBasedEmotionStateMachine(clock: clock1, random: { 0.5 })
        await sm1.handle(ConversationEvent.userSpeechStarted)
        #expect(await sm1.state.kind == .listening)
        clock1.set(101.0)
        await sm1.handle(ConversationEvent.userSpeechEnded)
        clock1.set(101.2)
        await sm1.handle(ConversationEvent.assistantSpeechStarted)
        clock1.set(102.0)
        await sm1.handle(ConversationEvent.assistantSpeechEnded)
        #expect(await sm1.state.kind == .idle)
        let pose1 = await sm1.pose(at: 102.0)
        #expect(pose1.action == nil)

        // 2. 原本有人脸，在对话期间离屏 >= 3 s
        let clock2 = ManualClock(seconds: 200.0)
        let sm2 = RuleBasedEmotionStateMachine(clock: clock2, random: { 0.5 })
        await enterAttending(sm2, clock: clock2, at: 200.0)
        clock2.set(201.0)
        await sm2.handle(ConversationEvent.userSpeechStarted)
        clock2.set(201.5)
        await sm2.handle(makeFaceFeature(at: 201.5, isTracked: false, isLooking: false))
        clock2.set(202.0)
        await sm2.handle(ConversationEvent.userSpeechEnded)
        clock2.set(202.2)
        await sm2.handle(ConversationEvent.assistantSpeechStarted)
        // lastFaceSeenAt == 200.25，到 205.0 已离屏 4.75 s >= 3 s
        clock2.set(205.0)
        await sm2.handle(ConversationEvent.assistantSpeechEnded)
        #expect(await sm2.state.kind == .idle)
        let pose2 = await sm2.pose(at: 205.0)
        #expect(pose2.action == nil)
    }

    // MARK: - userEmotion 6 映射与 Thinking 姿态/微仰视视线

    @Test("userEmotion 全 6 值映射精确（按 3A：happy→happy, calm→neutral, sad/tired/anxious/angry→concerned）")
    func userEmotionSixMappingsInThinking() async {
        let cases: [(UserEmotion, EmotionTag)] = [
            (.happy, .happy),
            (.calm, .neutral),
            (.sad, .concerned),
            (.tired, .concerned),
            (.anxious, .concerned),
            (.angry, .concerned),
        ]

        for (userEmo, expectedBase) in cases {
            let clock = ManualClock(seconds: 100.0)
            let sm = RuleBasedEmotionStateMachine(clock: clock, random: { 0.5 })
            await sm.handle(ConversationEvent.userSpeechStarted)
            clock.set(101.0)
            await sm.handle(ConversationEvent.userSpeechEnded)
            #expect(await sm.state.kind == .thinking)

            clock.set(101.1)
            await sm.handle(ConversationEvent.userEmotion(userEmo))
            #expect(await sm.state.kind == .thinking)
            #expect(await sm.state.baseEmotion == expectedBase)
        }
    }

    @Test("Thinking 姿态：neutral 叠 gentle×0.35，非中性 baseEmotion 以 0.65 主导不叠 gentle，且确定性微仰视")
    func thinkingPoseExpressionAndUpwardGaze() async {
        let clock = ManualClock(seconds: 100.0)
        let idleConfig = IdleMotionLayer.Config(breathAmplitude: 0)
        let sm = RuleBasedEmotionStateMachine(clock: clock, random: { 0.5 }, idleConfig: idleConfig)

        await sm.handle(ConversationEvent.userSpeechStarted)
        clock.set(101.0)
        await sm.handle(ConversationEvent.userSpeechEnded)

        let neutralPose = await sm.pose(at: 101.0)
        let gentleSmile = ExpressionPreset.bundledDefaults[.gentle]?.weights["mouthSmileLeft"] ?? 0
        #expect(abs((neutralPose.expressionWeights["mouthSmileLeft"] ?? 0) - gentleSmile * 0.35) < 1e-4)
        // 确定性微仰视：抬头 headRotation.x < 0，eyeTarget.y > 0，eyeLookUpLeft/Right > 0
        #expect(neutralPose.headRotation.x < 0)
        #expect(neutralPose.eyeTarget.y > 0)
        #expect((neutralPose.expressionWeights["eyeLookUpLeft"] ?? 0) > 0)
        #expect((neutralPose.expressionWeights["eyeLookUpRight"] ?? 0) > 0)

        // 注入 <user:sad> → baseEmotion == .concerned
        clock.set(101.2)
        await sm.handle(ConversationEvent.userEmotion(.sad))
        let sadPose = await sm.pose(at: 101.2)
        let concernedFrown = ExpressionPreset.bundledDefaults[.concerned]?.weights["mouthFrownLeft"] ?? 0
        #expect((sadPose.expressionWeights["mouthFrownLeft"] ?? 0) >= concernedFrown * 0.65 - 1e-4)
        #expect((sadPose.expressionWeights["mouthSmileLeft"] ?? 0) == 0)
        #expect(sadPose.headRotation.x < 0)
        #expect(sadPose.eyeTarget.y > 0)
    }

    // MARK: - 边界转换

    @Test("Listening 直接收 assistantSpeechStarted；非 Speaking 忽略 assistantEmotion；Speaking 情绪切换平滑过渡")
    func listeningDirectToSpeakingAndEmotionTransitions() async {
        let clock = ManualClock(seconds: 100.0)
        let sm = RuleBasedEmotionStateMachine(clock: clock, random: { 0.5 })

        // Idle / Attending 收到 assistantEmotion 忽略
        await sm.handle(ConversationEvent.assistantEmotion(.happy))
        #expect(await sm.state.kind == .idle)

        await enterAttending(sm, clock: clock, at: 100.0)
        clock.set(100.5)
        await sm.handle(ConversationEvent.assistantEmotion(.happy))
        #expect(await sm.state.kind == .attending)

        // Listening 直接收 assistantSpeechStarted
        clock.set(101.0)
        await sm.handle(ConversationEvent.userSpeechStarted)
        clock.set(101.2)
        await sm.handle(ConversationEvent.assistantSpeechStarted)
        #expect(await sm.state.kind == .speaking(.neutral))

        // Speaking(.happy) 切 Speaking(.sad)：在 t+0.1s 同时存在淡出微笑与淡入撇嘴
        clock.set(101.5)
        await sm.handle(ConversationEvent.assistantEmotion(.happy))
        _ = await sm.pose(at: 101.8) // 充分渐入 happy

        clock.set(102.0)
        await sm.handle(ConversationEvent.assistantEmotion(.sad))
        #expect(await sm.state.kind == .speaking(.sad))

        let transitionPose = await sm.pose(at: 102.1)
        #expect((transitionPose.expressionWeights["mouthSmileLeft"] ?? 0) > 0)
        #expect((transitionPose.expressionWeights["mouthFrownLeft"] ?? 0) > 0)

        // Thinking 收到 assistantEmotion 忽略
        clock.set(103.0)
        await sm.handle(ConversationEvent.userSpeechStarted)
        clock.set(103.5)
        await sm.handle(ConversationEvent.userSpeechEnded)
        clock.set(103.6)
        await sm.handle(ConversationEvent.assistantEmotion(.happy))
        #expect(await sm.state.kind == .thinking)
    }

    // MARK: - 打断清空计划反应 & 003 E-2 乱序保护

    @Test("Listening/Thinking/Speaking 收到 userSpeechStarted 均切 Listening、清空计划反应，且 003 E-2 乱序不误踢")
    func interruptionClearsScheduledAndResistsOutOfOrderSpeechEnded() async {
        let clock = ManualClock(seconds: 100.0)
        let sm = RuleBasedEmotionStateMachine(clock: clock, random: { 0.5 })
        await enterAttending(sm, clock: clock, at: 100.0)

        // 排程一个微笑反应（延迟 0.55 s，将在 101.05 到期）
        clock.set(100.5)
        await sm.handle(makeFaceFeature(at: 100.5, activeExpression: .smiling))
        #expect(!(await sm.state.scheduled.isEmpty))

        // 100.7 打断进入 Listening，应清空 scheduled
        clock.set(100.7)
        await sm.handle(ConversationEvent.userSpeechStarted)
        #expect(await sm.state.kind == .listening)
        #expect(await sm.state.scheduled.isEmpty)

        // 到 101.2（已超过原定 101.05）不触发 .reacting
        _ = await sm.pose(at: 101.2)
        #expect(await sm.state.kind == .listening)

        // Thinking -> userSpeechStarted -> Listening
        clock.set(102.0)
        await sm.handle(ConversationEvent.userSpeechEnded)
        #expect(await sm.state.kind == .thinking)
        clock.set(102.2)
        await sm.handle(ConversationEvent.userSpeechStarted)
        #expect(await sm.state.kind == .listening)

        // Speaking -> userSpeechStarted -> 迟到的旧轮 assistantSpeechEnded（003 E-2）
        clock.set(103.0)
        await sm.handle(ConversationEvent.assistantSpeechStarted)
        #expect(await sm.state.kind == .speaking(.neutral))

        clock.set(103.5)
        await sm.handle(ConversationEvent.userSpeechStarted)
        #expect(await sm.state.kind == .listening)

        clock.set(103.6)
        await sm.handle(ConversationEvent.assistantSpeechEnded)
        #expect(await sm.state.kind == .listening)
    }

    // MARK: - assistantAction 高优先级动作 & Speaking S-5 保护

    @Test("assistantAction 在任意状态不改 state.kind 且高于同帧感知动作；Speaking 期间 S-5 保护")
    func assistantActionPriorityAndSpeakingProtection() async {
        let clock = ManualClock(seconds: 100.0)
        let sm = RuleBasedEmotionStateMachine(clock: clock, random: { 0.5 })

        // Idle 状态
        await sm.handle(ConversationEvent.assistantAction(.spin))
        #expect(await sm.state.kind == .idle)
        #expect(await sm.pose(at: 100.0).action == .play(.spin))

        // Attending 状态 + 同帧感知手势不覆盖 assistantAction
        await enterAttending(sm, clock: clock, at: 101.0)
        clock.set(102.0)
        await sm.handle(ConversationEvent.assistantAction(.spin))
        await sm.handle(makeFaceFeature(
            at: 102.0,
            gesture: GestureEvent(kind: .wave, confidence: 0.9, timestamp: 102.0)
        ))
        // 动作保持 .spin 不被 .wave 覆写
        #expect(await sm.pose(at: 102.0).action == .play(.spin))

        // Reacting 态收到 assistantAction 不改状态且动作高优先级生效
        clock.set(105.0)
        await sm.handle(ConversationEvent.assistantCue(AvatarCue(emotion: .playful, hold: true)))
        let reactingBefore = await sm.state.kind
        await sm.handle(ConversationEvent.assistantAction(.heart))
        #expect(await sm.state.kind == reactingBefore)
        #expect(await sm.pose(at: 105.0).action == .play(.heart))
        await sm.handle(ConversationEvent.assistantCueEnded)

        // Thinking 态收到 assistantAction 不改状态且动作生效
        clock.set(108.0)
        await sm.handle(ConversationEvent.userSpeechStarted)
        clock.set(108.2)
        await sm.handle(ConversationEvent.userSpeechEnded)
        #expect(await sm.state.kind == .thinking)
        await sm.handle(ConversationEvent.assistantAction(.wave))
        #expect(await sm.state.kind == .thinking)
        #expect(await sm.pose(at: 108.2).action == .play(.wave))

        // Speaking(.gentle) 期间：微笑、挥手、快速靠近均不打断
        clock.set(110.0)
        await sm.handle(ConversationEvent.userSpeechStarted)
        clock.set(110.2)
        await sm.handle(ConversationEvent.assistantSpeechStarted)
        clock.set(110.3)
        await sm.handle(ConversationEvent.assistantEmotion(.gentle))
        #expect(await sm.state.kind == .speaking(.gentle))

        // Speaking 中发 assistantAction 仍可执行且不改 state
        clock.set(110.5)
        await sm.handle(ConversationEvent.assistantAction(.nod))
        #expect(await sm.state.kind == .speaking(.gentle))
        #expect(await sm.pose(at: 110.5).action == .play(.nod))

        // Speaking 中微笑 / 挥手 / 快速靠近
        clock.set(111.0)
        await sm.handle(makeFaceFeature(
            at: 111.0,
            position: SIMD3<Float>(0, 0, 0.6),
            activeExpression: .smiling
        ))
        clock.set(111.2)
        await sm.handle(makeFaceFeature(
            at: 111.2,
            position: SIMD3<Float>(0, 0, 0.35),
            activeExpression: .smiling,
            gesture: GestureEvent(kind: .wave, confidence: 0.9, timestamp: 111.2)
        ))
        #expect(await sm.state.kind == .speaking(.gentle))
        let speakingPose = await sm.pose(at: 111.5)
        #expect(speakingPose.action == nil)
        // gentle 本身无 cheekSquintLeft，叠加 happy 最多 0.25 * 0.5 <= 0.30
        #expect((speakingPose.expressionWeights["cheekSquintLeft"] ?? 0) <= 0.30 + 1e-4)
    }

    // MARK: - Step 4 口型层

    @Test("Step 4 口型层：覆盖而非 max，0 闭嘴，越界/NaN 满足 S-6，结束后释放")
    func lipSyncOverridesAndReleasesCleanly() async {
        let clock = ManualClock(seconds: 100.0)
        let sm = RuleBasedEmotionStateMachine(clock: clock, random: { 0.5 })
        await enterAttending(sm, clock: clock, at: 100.0)

        clock.set(101.0)
        await sm.handle(ConversationEvent.userSpeechStarted)
        clock.set(101.1)
        await sm.handle(ConversationEvent.assistantSpeechStarted)
        clock.set(101.2)
        await sm.handle(ConversationEvent.assistantEmotion(.surprised))

        // 充分渐入 surprised（jawOpen == 0.65, eyeWideLeft == 0.90）
        clock.set(102.0)
        await sm.handle(ConversationEvent.assistantAudioLevel(0.5))
        let poseHalf = await sm.pose(at: 102.0)
        // 严格覆盖：0.5 * 0.80 == 0.40（而非 max(0.65, 0.40)）
        #expect(abs((poseHalf.expressionWeights["jawOpen"] ?? -1) - 0.40) < 1e-4)
        #expect(abs((poseHalf.expressionWeights["mouthFunnel"] ?? -1) - 0.175) < 1e-4)
        #expect(abs((poseHalf.expressionWeights["eyeWideLeft"] ?? -1) - 0.90) < 1e-4)

        // Speaking 期间 0.0 保持覆盖闭嘴
        clock.set(102.2)
        await sm.handle(ConversationEvent.assistantAudioLevel(0.0))
        let poseZero = await sm.pose(at: 102.2)
        #expect((poseZero.expressionWeights["jawOpen"] ?? -1) == 0)
        #expect((poseZero.expressionWeights["mouthFunnel"] ?? -1) == 0)

        // 越界与 NaN 满足 S-6 ∈ [0, 1]
        for level: Float in [1.5, -0.2, .nan, .infinity] {
            clock.advance(by: 0.05)
            await sm.handle(ConversationEvent.assistantAudioLevel(level))
            let pose = await sm.pose(at: clock.now.timeIntervalSinceReferenceDate)
            for (_, v) in pose.expressionWeights {
                #expect(v.isFinite)
                #expect(v >= 0 && v <= 1)
            }
        }

        // assistantSpeechEnded 释放覆盖
        clock.set(103.0)
        await sm.handle(ConversationEvent.assistantAudioLevel(0.8))
        clock.set(103.1)
        await sm.handle(ConversationEvent.assistantSpeechEnded)
        let afterPose = await sm.pose(at: 103.5)
        #expect((afterPose.expressionWeights["jawOpen"] ?? 0) == 0)
        #expect((afterPose.expressionWeights["mouthFunnel"] ?? 0) == 0)
    }

    // MARK: - FeedbackLatencyTracker

    @Test("FeedbackLatencyTracker：Listening 武装记录精确时延、非 Listening 忽略、超时/负值/reset 清理")
    func feedbackLatencyTrackerBehavior() {
        var tracker = FeedbackLatencyTracker(timeout: 3.0)

        // 1. Listening 正常武装 + 12 ms 后观测 .thinking
        tracker.observeUserSpeechEnded(previousState: .listening, at: 10.000)
        #expect(tracker.observeAppliedState(.listening, at: 10.005) == nil)
        let sample = tracker.observeAppliedState(.thinking, at: 10.012)
        #expect(sample != nil)
        if let sample {
            #expect(abs(sample - 0.012) < 1e-6)
        }
        // 已解除武装，再次观测返回 nil
        #expect(tracker.observeAppliedState(.thinking, at: 10.020) == nil)

        // 2. 非 Listening（如 Idle / Attending / Speaking / Cue Reacting）不武装
        tracker.observeUserSpeechEnded(previousState: .attending, at: 20.0)
        #expect(tracker.observeAppliedState(.thinking, at: 20.010) == nil)

        let cueReaction = Reaction(expression: .happy, returnTo: .listening, isCue: true, holdsUntilEnded: true)
        tracker.observeUserSpeechEnded(previousState: .reacting(cueReaction), at: 21.0)
        #expect(tracker.observeAppliedState(.thinking, at: 21.010) == nil)

        // 3. 超时 (>= 3.0 s) 返回 nil 并清零
        tracker.observeUserSpeechEnded(previousState: .listening, at: 30.0)
        #expect(tracker.observeAppliedState(.thinking, at: 33.0) == nil)
        #expect(tracker.observeAppliedState(.thinking, at: 30.5) == nil)

        // 4. 负时间返回 nil 并清零
        tracker.observeUserSpeechEnded(previousState: .listening, at: 40.0)
        #expect(tracker.observeAppliedState(.thinking, at: 39.9) == nil)
        #expect(tracker.observeAppliedState(.thinking, at: 40.01) == nil)

        // 5. reset() 清理状态
        tracker.observeUserSpeechEnded(previousState: .listening, at: 50.0)
        tracker.reset()
        #expect(tracker.observeAppliedState(.thinking, at: 50.01) == nil)
    }
}
