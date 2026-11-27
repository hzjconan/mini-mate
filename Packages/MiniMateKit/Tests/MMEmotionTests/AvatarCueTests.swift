import Foundation
import Testing
import simd
import MMCore
import MMEmotion
import MMPerception

private final class CueManualClock: MMCore.Clock, @unchecked Sendable {
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

    func sleep(for duration: Duration) async throws {}
}

@Suite("AvatarCue")
struct AvatarCueTests {

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
        clock: CueManualClock,
        at t0: TimeInterval = 100.0
    ) async {
        clock.set(t0)
        await sm.handle(makeFaceFeature(at: t0))
        clock.set(t0 + 0.25)
        await sm.handle(makeFaceFeature(at: t0 + 0.25))
    }

    // MARK: - EM-1 / EM-4：非对话态收到提示、hold 持久保持、提示替换与非 hold 过期

    @Test("EM-1/EM-4：非对话态收到 hold 提示持久保持满强度，新提示替换且非 hold 1.5s 过期")
    func nonConversationCueHoldAndReplacement() async {
        let clock = CueManualClock(seconds: 100.0)
        let sm = RuleBasedEmotionStateMachine(clock: clock, random: { 0.5 })
        await enterAttending(sm, clock: clock, at: 100.0)

        // 先排程一个微笑，确认 assistantCue 会清空 scheduled
        clock.set(100.5)
        await sm.handle(makeFaceFeature(at: 100.5, activeExpression: .smiling))
        #expect(!(await sm.state.scheduled.isEmpty))

        let cue1 = AvatarCue(emotion: .playful, action: .lookAround, hold: true)
        clock.set(100.6)
        await sm.handle(ConversationEvent.assistantCue(cue1))

        let state1 = await sm.state
        guard case .reacting(let r1) = state1.kind else {
            Issue.record("Expected .reacting for cue1, got \(state1.kind)")
            return
        }
        #expect(r1.expression == .playful)
        #expect(r1.action == .lookAround)
        #expect(r1.isCue == true)
        #expect(r1.holdsUntilEnded == true)
        #expect(state1.heldCue == cue1)
        #expect(state1.scheduled.isEmpty)
        #expect(await sm.pose(at: 100.6).action == .play(.lookAround))

        // 10 s 后仍保持 .reacting 且满强度 1.0
        clock.set(110.6)
        let pose10s = await sm.pose(at: 110.6)
        #expect(await sm.state.kind == state1.kind)
        let playfulSmile = ExpressionPreset.bundledDefaults[.playful]?.weights["mouthSmileLeft"] ?? 0
        #expect(abs((pose10s.expressionWeights["mouthSmileLeft"] ?? 0) - playfulSmile) < 1e-4)

        // 新提示（hold: false）立即替换旧提示
        let cue2 = AvatarCue(emotion: .happy, action: .heart, hold: false)
        clock.set(111.0)
        await sm.handle(ConversationEvent.assistantCue(cue2))
        let state2 = await sm.state
        guard case .reacting(let r2) = state2.kind else {
            Issue.record("Expected .reacting for cue2, got \(state2.kind)")
            return
        }
        #expect(r2.expression == .happy)
        #expect(r2.isCue == true)
        #expect(r2.holdsUntilEnded == false)
        #expect(state2.heldCue == nil)
        #expect(await sm.pose(at: 111.0).action == .play(.heart))

        // 保持人脸在场，1.5 s 后非 hold 提示过期回到 .attending
        clock.set(112.0)
        await sm.handle(makeFaceFeature(at: 112.0))
        clock.set(112.6)
        _ = await sm.pose(at: 112.6)
        #expect(await sm.state.kind == .attending)
    }

    // MARK: - EM-2 / S-8：对话态收到提示、多轮恢复不重复播动作、assistantCueEnded 取消

    @Test("EM-2/S-8：对话态收到提示暂存，assistantSpeechEnded 恢复且二次恢复不重复播动作，Speaking 中 assistantCueEnded 不打断说话")
    func conversationCueDeferralRecoveryAndCancel() async {
        let clock = CueManualClock(seconds: 100.0)
        let sm = RuleBasedEmotionStateMachine(clock: clock, random: { 0.5 })
        await enterAttending(sm, clock: clock, at: 100.0)

        // 进入 Speaking
        clock.set(101.0)
        await sm.handle(ConversationEvent.userSpeechStarted)
        clock.set(101.2)
        await sm.handle(ConversationEvent.assistantSpeechStarted)
        #expect(await sm.state.kind == .speaking(.neutral))

        // Speaking 期间收到 hold: true 提示：不打断 Speaking，暂存 heldCue
        let cue = AvatarCue(emotion: .happy, action: .nod, hold: true)
        clock.set(101.5)
        await sm.handle(ConversationEvent.assistantCue(cue))
        #expect(await sm.state.kind == .speaking(.neutral))
        #expect(await sm.state.heldCue == cue)

        // 说话结束：进入提示且首进播放 .nod
        clock.set(102.0)
        await sm.handle(ConversationEvent.assistantSpeechEnded)
        guard case .reacting(let r1) = await sm.state.kind else {
            Issue.record("Expected .reacting after assistantSpeechEnded")
            return
        }
        #expect(r1.isCue == true)
        #expect(r1.holdsUntilEnded == true)
        #expect(await sm.pose(at: 102.0).action == .play(.nod))

        // 再走一轮对话（打断提示 → 说话结束）→ 恢复提示，但动作不重复播放
        clock.set(103.0)
        await sm.handle(ConversationEvent.userSpeechStarted)
        #expect(await sm.state.kind == .listening)
        #expect(await sm.state.heldCue == cue)

        clock.set(103.5)
        await sm.handle(ConversationEvent.assistantSpeechStarted)
        clock.set(104.0)
        await sm.handle(ConversationEvent.assistantSpeechEnded)
        guard case .reacting(let r2) = await sm.state.kind else {
            Issue.record("Expected .reacting after second assistantSpeechEnded")
            return
        }
        #expect(r2.isCue == true)
        #expect(r2.expression == .happy)
        #expect(await sm.pose(at: 104.0).action == nil)

        // 再走一轮对话，Speaking 中收到 assistantCueEnded（如 photoCancel）：不打断 Speaking，结束后回 Attending
        clock.set(105.0)
        await sm.handle(ConversationEvent.userSpeechStarted)
        clock.set(105.2)
        await sm.handle(ConversationEvent.assistantSpeechStarted)
        clock.set(105.5)
        await sm.handle(ConversationEvent.assistantCueEnded)
        #expect(await sm.state.kind == .speaking(.neutral))
        #expect(await sm.state.heldCue == nil)

        clock.set(106.0)
        await sm.handle(ConversationEvent.assistantSpeechEnded)
        #expect(await sm.state.kind == .attending)
    }

    // MARK: - EM-3 / S-7 & 005 CV-2 口型联动

    @Test("EM-3/S-7：提示期间表情/手势/快速靠近被抑制且不写冷却；结束后可立即反应；005 CV-2 口型联动")
    func cueSuppressesPerceptionWithoutCooldownAndSupportsLipSync() async {
        let clock = CueManualClock(seconds: 100.0)
        let sm = RuleBasedEmotionStateMachine(clock: clock, random: { 0.5 })
        await enterAttending(sm, clock: clock, at: 100.0)

        let cue = AvatarCue(emotion: .happy, action: nil, hold: true)
        clock.set(101.0)
        await sm.handle(ConversationEvent.assistantCue(cue))
        let cueKind = await sm.state.kind

        // 1. 注入微笑、挥手、比心、点赞、快速靠近（1 s 内从 0.60 m → 0.35 m）
        clock.set(101.2)
        await sm.handle(makeFaceFeature(
            at: 101.2,
            position: SIMD3<Float>(0, 0, 0.60),
            activeExpression: .smiling
        ))
        clock.set(101.4)
        await sm.handle(makeFaceFeature(
            at: 101.4,
            position: SIMD3<Float>(0, 0, 0.35),
            activeExpression: .smiling,
            gesture: GestureEvent(kind: .wave, confidence: 0.9, timestamp: 101.4)
        ))
        clock.set(101.6)
        await sm.handle(makeFaceFeature(
            at: 101.6,
            gesture: GestureEvent(kind: .heart, confidence: 0.9, timestamp: 101.6)
        ))
        clock.set(101.8)
        await sm.handle(makeFaceFeature(
            at: 101.8,
            gesture: GestureEvent(kind: .thumbsUp, confidence: 0.9, timestamp: 101.8)
        ))
        clock.set(102.5)
        let poseDuringCue = await sm.pose(at: 102.5)

        let stateDuringCue = await sm.state
        #expect(stateDuringCue.kind == cueKind)
        #expect(stateDuringCue.cooldowns.isEmpty)
        #expect(stateDuringCue.scheduled.isEmpty)
        #expect(poseDuringCue.action == nil)

        // 2. 005 CV-2：提示期间收到 assistantAudioLevel(0.5) 驱动口型，0.0 释放回 happy 预设 jawOpen(0.2)
        clock.set(102.6)
        await sm.handle(ConversationEvent.assistantAudioLevel(0.5))
        let lipPose = await sm.pose(at: 102.6)
        #expect(abs((lipPose.expressionWeights["jawOpen"] ?? -1) - 0.40) < 1e-4)
        #expect(abs((lipPose.expressionWeights["mouthFunnel"] ?? -1) - 0.175) < 1e-4)

        clock.set(102.7)
        await sm.handle(ConversationEvent.assistantAudioLevel(0.0))
        let restoredPose = await sm.pose(at: 102.7)
        let happyJaw = ExpressionPreset.bundledDefaults[.happy]?.weights["jawOpen"] ?? 0
        #expect(abs((restoredPose.expressionWeights["jawOpen"] ?? -1) - happyJaw) < 1e-4)

        // 3. assistantCueEnded 后立刻挥手能正常进入感知反应（证明未写冷却）
        clock.set(103.0)
        await sm.handle(ConversationEvent.assistantCueEnded)
        #expect(await sm.state.kind == .attending)

        clock.set(103.1)
        await sm.handle(makeFaceFeature(
            at: 103.1,
            gesture: GestureEvent(kind: .wave, confidence: 0.9, timestamp: 103.1)
        ))
        guard case .reacting(let waveReaction) = await sm.state.kind else {
            Issue.record("Expected wave perception reaction immediately after assistantCueEnded")
            return
        }
        #expect(waveReaction.isCue == false)
        #expect(waveReaction.action == .wave)
    }

    // MARK: - EM-5：assistantCueEnded 边界

    @Test("EM-5：assistantCueEnded 有人脸回 Attending、无人脸/离屏回 Idle、普通感知 Reacting 不被打断")
    func assistantCueEndedBoundaries() async {
        // 1. 无人脸：回 Idle 且旧提示权重平滑淡出
        let clock1 = CueManualClock(seconds: 100.0)
        let sm1 = RuleBasedEmotionStateMachine(clock: clock1, random: { 0.5 })
        await sm1.handle(ConversationEvent.assistantCue(AvatarCue(emotion: .happy, hold: true)))
        _ = await sm1.pose(at: 100.5)
        clock1.set(101.0)
        await sm1.handle(ConversationEvent.assistantCueEnded)
        #expect(await sm1.state.kind == .idle)
        #expect(await sm1.state.heldCue == nil)
        let fadePose = await sm1.pose(at: 101.1)
        #expect((fadePose.expressionWeights["mouthSmileLeft"] ?? 0) > 0)

        // 2. 原本有人脸但离屏 >= 3s：回 Idle
        let clock2 = CueManualClock(seconds: 200.0)
        let sm2 = RuleBasedEmotionStateMachine(clock: clock2, random: { 0.5 })
        await enterAttending(sm2, clock: clock2, at: 200.0)
        clock2.set(200.5)
        await sm2.handle(ConversationEvent.assistantCue(AvatarCue(emotion: .playful, hold: true)))
        clock2.set(200.6)
        await sm2.handle(makeFaceFeature(at: 200.6, isTracked: false, isLooking: false))
        clock2.set(204.0)
        await sm2.handle(ConversationEvent.assistantCueEnded)
        #expect(await sm2.state.kind == .idle)

        // 3. 普通感知 .reacting(isCue: false) 收到 assistantCueEnded 不被打断
        let clock3 = CueManualClock(seconds: 300.0)
        let sm3 = RuleBasedEmotionStateMachine(clock: clock3, random: { 0.5 })
        await enterAttending(sm3, clock: clock3, at: 300.0)
        clock3.set(301.0)
        await sm3.handle(makeFaceFeature(
            at: 301.0,
            gesture: GestureEvent(kind: .wave, confidence: 0.9, timestamp: 301.0)
        ))
        let perceptionKind = await sm3.state.kind
        clock3.set(301.2)
        await sm3.handle(ConversationEvent.assistantCueEnded)
        #expect(await sm3.state.kind == perceptionKind)
    }

    // MARK: - assistantCommand 忽略 & ReflexLatencyTracker 隔离

    @Test("assistantCommand 全部 3 个值在任意状态无副作用；ReflexLatencyTracker 不被无动作 assistantCue 误触发")
    func assistantCommandIgnoredAndReflexTrackerIsolated() async {
        let clock = CueManualClock(seconds: 100.0)
        let sm = RuleBasedEmotionStateMachine(clock: clock, random: { 0.5 })
        await enterAttending(sm, clock: clock, at: 100.0)

        for cmd in AssistantCommand.allCases {
            let before = await sm.state
            await sm.handle(ConversationEvent.assistantCommand(cmd))
            #expect(await sm.state == before)
            #expect(await sm.pose(at: 100.25).action == nil)
        }

        // 微笑排程武装 ReflexLatencyTracker
        clock.set(101.0)
        await sm.handle(makeFaceFeature(at: 101.0, activeExpression: .smiling))
        var reflexTracker = ReflexLatencyTracker()
        reflexTracker.observePerception(
            activeExpression: .smiling,
            state: await sm.state,
            at: 101.0
        )

        // 在排程到期前注入无动作 assistantCue(.happy)
        clock.set(101.2)
        await sm.handle(ConversationEvent.assistantCue(AvatarCue(emotion: .happy, action: nil, hold: true)))
        let cueStateKind = await sm.state.kind
        #expect(reflexTracker.observeAppliedState(cueStateKind, at: 101.2) == nil)
    }

    // MARK: - 回归测试：对话态叠加感知反应收到 assistantCue & 非持久提示自然过期清理口型

    @Test("回归：Listening/Thinking 叠加感知 Reacting 时收到 assistantCue 走 EM-2 暂存，不阻断整轮对话")
    func cueDuringPerceptionReactionInConversationDefersWithoutBlockingTurn() async {
        let clock = CueManualClock(seconds: 100.0)
        let sm = RuleBasedEmotionStateMachine(clock: clock, random: { 0.5 })
        await enterAttending(sm, clock: clock, at: 100.0)

        // 1. Listening 期间挥手进入感知 .reacting(isCue: false, returnTo: .listening)
        clock.set(101.0)
        await sm.handle(ConversationEvent.userSpeechStarted)
        clock.set(101.2)
        await sm.handle(makeFaceFeature(
            at: 101.2,
            gesture: GestureEvent(kind: .wave, confidence: 0.9, timestamp: 101.2)
        ))
        guard case .reacting(let waveR) = await sm.state.kind else {
            Issue.record("Expected perception reacting over listening")
            return
        }
        #expect(waveR.isCue == false)
        #expect(waveR.returnTo == .listening)

        // 2. 此时收到 assistantCue 必须走 EM-2 暂存，不得替换为 isCue: true 吞掉后续对话事件
        let cue = AvatarCue(emotion: .playful, action: .heart, hold: true)
        clock.set(101.3)
        await sm.handle(ConversationEvent.assistantCue(cue))
        #expect(await sm.state.kind == .reacting(waveR))
        #expect(await sm.state.heldCue == cue)

        // 3. 后续整轮对话正常流转：userSpeechEnded → Thinking → userEmotion → Speaking → assistantSpeechEnded → 恢复 cue
        clock.set(101.5)
        await sm.handle(ConversationEvent.userSpeechEnded)
        #expect(await sm.state.kind == .thinking)

        clock.set(101.6)
        await sm.handle(ConversationEvent.userEmotion(.sad))
        #expect(await sm.state.baseEmotion == .concerned)

        // Thinking 态同样支持直接收到新 cue 覆盖暂存
        let cue2 = AvatarCue(emotion: .happy, action: .nod, hold: true)
        clock.set(101.7)
        await sm.handle(ConversationEvent.assistantCue(cue2))
        #expect(await sm.state.kind == .thinking)
        #expect(await sm.state.heldCue == cue2)

        clock.set(102.0)
        await sm.handle(ConversationEvent.assistantSpeechStarted)
        #expect(await sm.state.kind == .speaking(.concerned))

        clock.set(103.0)
        await sm.handle(ConversationEvent.assistantSpeechEnded)
        guard case .reacting(let restored) = await sm.state.kind else {
            Issue.record("Expected restored cue after assistantSpeechEnded")
            return
        }
        #expect(restored.isCue == true)
        #expect(restored.expression == .happy)
        #expect(restored.returnTo == .attending)
        #expect(await sm.pose(at: 103.0).action == .play(.nod))
    }

    @Test("回归：非持久提示 (hold: false) 注入非零口型后未归零，1.5 s 自然过期回 Attending 时自动清空 activeAudioLevel")
    func nonHoldCueExpirationClearsActiveAudioLevel() async {
        let clock = CueManualClock(seconds: 100.0)
        let sm = RuleBasedEmotionStateMachine(clock: clock, random: { 0.5 })
        await enterAttending(sm, clock: clock, at: 100.0)

        let cue = AvatarCue(emotion: .happy, action: .spin, hold: false)
        clock.set(101.0)
        await sm.handle(ConversationEvent.assistantCue(cue))
        clock.set(101.2)
        await sm.handle(ConversationEvent.assistantAudioLevel(0.6))

        let duringPose = await sm.pose(at: 101.2)
        #expect(abs((duringPose.expressionWeights["jawOpen"] ?? -1) - 0.48) < 1e-4)

        // 播放异常截断未发 0.0，1.5 s 后提示自然过期回到 .attending
        clock.set(102.0)
        await sm.handle(makeFaceFeature(at: 102.0))
        clock.set(102.6)
        let expiredPose = await sm.pose(at: 102.6)
        #expect(await sm.state.kind == .attending)
        #expect((expiredPose.expressionWeights["jawOpen"] ?? 0) == 0)
        #expect((expiredPose.expressionWeights["mouthFunnel"] ?? 0) == 0)
    }
}
