import Foundation
import simd
import MMCore
import MMPerception

/// 基于规则的情绪与注意力状态机（US2 注意力追踪 + US3 语义表情反应、随机延迟队列、冷却与柔和底色增强、blendIn/blendOut 合成）。
public actor RuleBasedEmotionStateMachine: EmotionStateMachine {
    public static let maxHeadAngleRadians: Float = 25 * .pi / 180
    private static let shyPitchOffsetRadians: Float = 8 * .pi / 180

    private struct CooldownBoost: Sendable, Equatable {
        let emotion: EmotionTag
        let startedAt: TimeInterval
        let duration: TimeInterval
    }

    private struct SpeakingOverlay: Sendable, Equatable {
        let emotion: EmotionTag
        let startedAt: TimeInterval
        let duration: TimeInterval
    }

    private struct FadingLayer: Sendable, Equatable {
        let weights: [String: Float]
        let startedAt: TimeInterval
        let fadeOutDuration: TimeInterval
    }

    private var rules: ReactionRules
    private var presets: [EmotionTag: ExpressionPreset]
    private let clock: any MMCore.Clock
    private let random: @Sendable () -> Double
    private var idleLayer: IdleMotionLayer

    private var currentState: AvatarState
    private var wasFaceTracked: Bool = false
    private var pendingNoticeOnAttend: Bool = false
    private var lookingStartedAt: TimeInterval?
    private var latestFacePosition: SIMD3<Float>?
    private var distanceHistory: [(time: TimeInterval, distance: Float)] = []
    private var approachCooldownUntil: TimeInterval?
    private var nextLookAroundAt: TimeInterval?
    private var pendingAction: ActionCommand?
    private var lastEvaluatedTime: TimeInterval?

    // US3 表情反应与过渡状态
    private var previousActiveExpression: UserExpression?
    private var activeReactionKey: ReactionKey?
    private var cooldownBoost: CooldownBoost?
    private var speakingOverlay: SpeakingOverlay?
    private var fadingLayers: [FadingLayer] = []

    // Idle 期间缓慢随机游走状态
    private var wanderStartYaw: Float = 0
    private var wanderStartPitch: Float = 0
    private var wanderStartEye: SIMD2<Float> = .zero
    private var wanderTargetYaw: Float = 0
    private var wanderTargetPitch: Float = 0
    private var wanderTargetEye: SIMD2<Float> = .zero
    private var wanderStartedAt: TimeInterval?
    private var nextWanderAt: TimeInterval?
    private let wanderTransitionDuration: TimeInterval = 0.8

    public init(
        rules: ReactionRules = .defaults,
        presets: [EmotionTag: ExpressionPreset] = ExpressionPreset.bundledDefaults,
        clock: any MMCore.Clock = SystemClock(),
        random: @escaping @Sendable () -> Double = { Double.random(in: 0...1) },
        idleConfig: IdleMotionLayer.Config = .init()
    ) {
        self.rules = rules
        self.presets = presets
        self.clock = clock
        self.random = random
        self.idleLayer = IdleMotionLayer(config: idleConfig, clock: clock, random: random)
        self.currentState = AvatarState(
            kind: .idle,
            enteredAt: clock.now.timeIntervalSinceReferenceDate
        )
    }

    public var state: AvatarState {
        currentState
    }

    public func handle(_ features: PerceptionFeatures) async {
        // 不变式 S-1：严禁读取 features.rawBlendShapes
        let now = features.timestamp
        guard now.isFinite else { return }

        // 先推进定时队列与过期清理（无脸帧先判定离屏超时回 Idle，避免人脸已丢失 >= 3 s 仍触发过期排程）
        checkReactingExpiration(at: now)
        if !features.isFaceTracked {
            _ = checkFaceLostToIdle(at: now)
        }
        processScheduledReactions(at: now)
        pruneTransientLayers(at: now)

        // 1. 人脸重现时先锁存离开时长 > idleAfterFaceLost，避免被 lastFaceSeenAt 覆写
        if features.isFaceTracked && !wasFaceTracked {
            if let lastSeen = currentState.lastFaceSeenAt,
               now - lastSeen > rules.idleAfterFaceLost {
                pendingNoticeOnAttend = true
            }
        }
        wasFaceTracked = features.isFaceTracked

        if features.isFaceTracked {
            currentState = AvatarState(
                kind: currentState.kind,
                enteredAt: currentState.enteredAt,
                baseEmotion: currentState.baseEmotion,
                cooldowns: currentState.cooldowns,
                scheduled: currentState.scheduled,
                lastFaceSeenAt: now
            )
            if let pos = features.facePosition,
               pos.x.isFinite, pos.y.isFinite, pos.z.isFinite {
                latestFacePosition = pos
            }
        }

        // 2. 注意力与动作状态转移
        switch currentState.kind {
        case .idle:
            if features.isFaceTracked && features.isLookingAtScreen {
                if lookingStartedAt == nil {
                    lookingStartedAt = now
                }
                if let started = lookingStartedAt,
                   now - started + 1e-9 >= rules.attendingEnter {
                    enterAttending(at: now)
                }
            } else {
                lookingStartedAt = nil
            }

        case .attending:
            if checkFaceLostToIdle(at: now) {
                break
            }
            if features.isFaceTracked, let pos = features.facePosition,
               pos.x.isFinite, pos.y.isFinite, pos.z.isFinite {
                evaluateRapidApproach(distance: abs(pos.z), at: now)
            }

        case .reacting:
            // Reacting 到期已在入口检查；期间继续追踪人脸位置即可
            break

        case .listening, .thinking, .speaking:
            // 对话事件完整转换留给 US5
            break
        }

        // 2.5 手势即时反应（contracts/emotion-state-machine.md 第 34 行：延迟 <= 300 ms，状态机内 0 ms 立即进入）
        if let gesture = features.gesture {
            handleGestureTrigger(gesture, at: now)
        }

        // 3. 语义表情边沿触发（仅读取 features.signals.activeExpression）
        let newExpr = features.isFaceTracked ? features.signals.activeExpression : nil
        if newExpr != previousActiveExpression {
            previousActiveExpression = newExpr
            if let expr = newExpr {
                handleExpressionTrigger(expr, at: now)
            }
        }
    }

    public func handle(_ event: ConversationEvent) async {
        // US5 实现对话事件转换，US3 保持无副作用空实现
    }

    /// 运行时热更新单个情绪预设，供调试面板真机调参后立即在真实反应中生效。
    public func updatePreset(_ preset: ExpressionPreset) {
        presets[preset.emotion] = preset
    }

    /// 运行时热更新同类反应冷却时间（夹紧至 3...8 s），供调试面板真机调参并立即生效。
    public func updateCooldown(_ seconds: TimeInterval, at time: TimeInterval? = nil) {
        guard seconds.isFinite else { return }
        let clamped = min(max(seconds, 3.0), 8.0)
        rules.cooldown = clamped

        let candidateNow = time ?? lastEvaluatedTime ?? clock.now.timeIntervalSinceReferenceDate
        let now = candidateNow.isFinite ? candidateNow : clock.now.timeIntervalSinceReferenceDate
        let maxUntil = now + clamped
        if let approachUntil = approachCooldownUntil, approachUntil > maxUntil {
            approachCooldownUntil = maxUntil
        }
        var adjusted = currentState.cooldowns
        var changed = false
        for (key, until) in adjusted where until > maxUntil {
            adjusted[key] = maxUntil
            changed = true
        }
        if changed {
            currentState = AvatarState(
                kind: currentState.kind,
                enteredAt: currentState.enteredAt,
                baseEmotion: currentState.baseEmotion,
                cooldowns: adjusted,
                scheduled: currentState.scheduled,
                lastFaceSeenAt: currentState.lastFaceSeenAt
            )
        }
    }

    /// 仅限单元测试设置特定状态（如在 US5 完成前测试 `.speaking` 的 S-5 保护）。
    internal func _setStateKindForTesting(_ kind: AvatarStateKind, at time: TimeInterval) {
        currentState = AvatarState(
            kind: kind,
            enteredAt: time,
            baseEmotion: currentState.baseEmotion,
            cooldowns: currentState.cooldowns,
            scheduled: currentState.scheduled,
            lastFaceSeenAt: currentState.lastFaceSeenAt
        )
    }

    public func resetToIdle(at time: TimeInterval? = nil) async {
        let now = time ?? clock.now.timeIntervalSinceReferenceDate
        currentState = AvatarState(
            kind: .idle,
            enteredAt: now,
            baseEmotion: currentState.baseEmotion,
            cooldowns: currentState.cooldowns,
            scheduled: [],
            lastFaceSeenAt: currentState.lastFaceSeenAt
        )
        wasFaceTracked = false
        pendingNoticeOnAttend = false
        lookingStartedAt = nil
        latestFacePosition = nil
        distanceHistory.removeAll()
        nextLookAroundAt = nil
        pendingAction = nil
        previousActiveExpression = nil
        activeReactionKey = nil
        cooldownBoost = nil
        speakingOverlay = nil
        fadingLayers.removeAll()
    }

    public func pose(at time: TimeInterval) async -> AvatarPose {
        let evalTime: TimeInterval
        if let last = lastEvaluatedTime, time < last {
            evalTime = last
        } else {
            evalTime = time
        }
        lastEvaluatedTime = evalTime

        // 检查到期、人脸丢失超时回 Idle、再处理计划反应（避免人脸已丢失 >= 3 s 后仍触发过期排程）
        checkReactingExpiration(at: evalTime)
        _ = checkFaceLostToIdle(at: evalTime)
        processScheduledReactions(at: evalTime)
        pruneTransientLayers(at: evalTime)

        // Idle 低频张望调度
        if case .idle = currentState.kind {
            if nextLookAroundAt == nil {
                nextLookAroundAt = evalTime + Self.lerp(8.0, 14.0, unitRandom())
            } else if let due = nextLookAroundAt, evalTime >= due {
                pendingAction = .play(.lookAround)
                nextLookAroundAt = evalTime + Self.lerp(8.0, 14.0, unitRandom())
            }
        }

        // Step 1：底色层（baseEmotion 0.3，冷却期柔和增强 2A）
        var weights: [String: Float] = [:]
        var boostFactor: Float = 0
        if let boost = cooldownBoost {
            let preset = presets[boost.emotion]
            let blendIn = preset.map { Self.durationSeconds($0.blendIn) } ?? 0.2
            let blendOut = preset.map { Self.durationSeconds($0.blendOut) } ?? 0.3
            boostFactor = Self.envelope(
                elapsed: evalTime - boost.startedAt,
                duration: boost.duration,
                blendIn: blendIn,
                blendOut: blendOut
            )
        }

        if currentState.baseEmotion != .neutral,
           let basePreset = presets[currentState.baseEmotion] {
            let baseStrength: Float = 0.3 + 0.15 * boostFactor
            for (name, value) in basePreset.weights {
                weights[name] = value * baseStrength
            }
        } else if let boost = cooldownBoost,
                  boostFactor > 0,
                  let boostPreset = presets[boost.emotion] {
            let strength: Float = 0.25 * boostFactor
            for (name, value) in boostPreset.weights {
                weights[name] = max(weights[name] ?? 0, value * strength)
            }
        }

        // Step 2 + Step 3：状态层 + 过渡插值（含 .shy 轻微低头因子）
        var shyFactor: Float = 0

        switch currentState.kind {
        case .reacting(let reaction):
            if let reactPreset = presets[reaction.expression] {
                let factor = Self.envelope(
                    elapsed: evalTime - currentState.enteredAt,
                    duration: Self.durationSeconds(reaction.duration),
                    blendIn: Self.durationSeconds(reactPreset.blendIn),
                    blendOut: Self.durationSeconds(reactPreset.blendOut)
                )
                if factor > 0 {
                    for (name, value) in reactPreset.weights {
                        weights[name] = max(weights[name] ?? 0, value * factor)
                    }
                    if reaction.expression == .shy {
                        shyFactor = max(shyFactor, factor)
                    }
                }
            }

        case .speaking(let emotion):
            if let speakPreset = presets[emotion] {
                for (name, value) in speakPreset.weights {
                    weights[name] = max(weights[name] ?? 0, value)
                }
                if emotion == .shy {
                    shyFactor = 1.0
                }
            }
            if let overlay = speakingOverlay,
               let overlayPreset = presets[overlay.emotion] {
                let factor = Self.envelope(
                    elapsed: evalTime - overlay.startedAt,
                    duration: overlay.duration,
                    blendIn: Self.durationSeconds(overlayPreset.blendIn),
                    blendOut: Self.durationSeconds(overlayPreset.blendOut)
                )
                if factor > 0 {
                    let strength: Float = 0.25 * factor
                    for (name, value) in overlayPreset.weights {
                        weights[name] = max(weights[name] ?? 0, value * strength)
                    }
                }
            }

        case .thinking:
            if let gentlePreset = presets[.gentle] {
                for (name, value) in gentlePreset.weights {
                    weights[name] = max(weights[name] ?? 0, value * 0.35)
                }
            }

        case .idle, .attending, .listening:
            break
        }

        // 被打断旧反应的平滑淡出层
        for layer in fadingLayers {
            guard layer.fadeOutDuration > 0 else { continue }
            let elapsed = evalTime - layer.startedAt
            let remaining = Float(Self.clamp(1.0 - elapsed / layer.fadeOutDuration, 0, 1))
            if remaining > 0 {
                for (name, value) in layer.weights {
                    weights[name] = max(weights[name] ?? 0, value * remaining)
                }
            }
        }

        // Step 5：待机层（呼吸 + 眨眼）
        let idleMotion = idleLayer.update(at: evalTime)
        weights["eyeBlinkLeft"] = max(weights["eyeBlinkLeft"] ?? 0, idleMotion.eyeBlink)
        weights["eyeBlinkRight"] = max(weights["eyeBlinkRight"] ?? 0, idleMotion.eyeBlink)

        // Step 6：视线与头部朝向
        var gazePitch: Float
        let gazeYaw: Float
        let eyeTarget: SIMD2<Float>

        let isEngaged: Bool = switch currentState.kind {
        case .attending, .listening, .speaking, .reacting: true
        case .idle, .thinking: false
        }

        if isEngaged, let pos = latestFacePosition {
            let dist = max(abs(pos.z), 0.15)
            let rawYaw = atan2(pos.x, dist)
            let rawPitch = -atan2(pos.y, dist)
            let maxAngle = Self.maxHeadAngleRadians
            let maxUpPitch: Float = 6 * .pi / 180
            let maxDownPitch: Float = 12 * .pi / 180
            let eyeRefAngle: Float = 10 * .pi / 180

            // 人脸暂时丢失（尚未满 3s 回 Idle）时，0.5s~1.5s 内平滑回中，避免切 Idle 触发 lookAround 时头角突跳闪烁
            let lostFade: Float
            if !wasFaceTracked, let lastSeen = currentState.lastFaceSeenAt {
                let lostDuration = evalTime - lastSeen
                let progress = Self.clamp((lostDuration - 0.5) / 1.0, 0.0, 1.0)
                lostFade = Float(1.0 - progress * progress * (3.0 - 2.0 * progress))
            } else {
                lostFade = 1.0
            }

            gazeYaw = Self.clamp(rawYaw * 3.2, -maxAngle, maxAngle) * lostFade
            gazePitch = Self.clamp(rawPitch * 0.8, -maxUpPitch, maxDownPitch) * lostFade
            eyeTarget = SIMD2<Float>(
                Self.clamp(rawYaw / eyeRefAngle, -1, 1) * lostFade,
                Self.clamp(atan2(pos.y, dist) / eyeRefAngle, -1, 1) * lostFade
            )
        } else {
            let wander = evaluateIdleWander(at: evalTime)
            gazePitch = wander.pitch
            gazeYaw = wander.yaw
            eyeTarget = wander.eye
        }

        // .shy 轻微低头（+8° * factor，最终经 ±25° 限幅）
        if shyFactor > 0 {
            gazePitch += Self.shyPitchOffsetRadians * shyFactor
        }

        let maxAngle = Self.maxHeadAngleRadians
        let headRotation = SIMD3<Float>(
            Self.clamp(gazePitch + idleMotion.headRotation.x, -maxAngle, maxAngle),
            Self.clamp(gazeYaw + idleMotion.headRotation.y, -maxAngle, maxAngle),
            Self.clamp(idleMotion.headRotation.z, -maxAngle, maxAngle)
        )

        // 映射 eyeTarget 到 8 个 eyeLook* 形态键（缩放系数 0.85）
        let eyeScale: Float = 0.85
        let rightLook = max(eyeTarget.x, 0) * eyeScale
        let leftLook = max(-eyeTarget.x, 0) * eyeScale
        let upLook = max(eyeTarget.y, 0) * eyeScale
        let downLook = max(-eyeTarget.y, 0) * eyeScale

        if rightLook > 0 {
            weights["eyeLookOutLeft"] = max(weights["eyeLookOutLeft"] ?? 0, rightLook)
            weights["eyeLookInRight"] = max(weights["eyeLookInRight"] ?? 0, rightLook)
        }
        if leftLook > 0 {
            weights["eyeLookInLeft"] = max(weights["eyeLookInLeft"] ?? 0, leftLook)
            weights["eyeLookOutRight"] = max(weights["eyeLookOutRight"] ?? 0, leftLook)
        }
        if upLook > 0 {
            weights["eyeLookUpLeft"] = max(weights["eyeLookUpLeft"] ?? 0, upLook)
            weights["eyeLookUpRight"] = max(weights["eyeLookUpRight"] ?? 0, upLook)
        }
        if downLook > 0 {
            weights["eyeLookDownLeft"] = max(weights["eyeLookDownLeft"] ?? 0, downLook)
            weights["eyeLookDownRight"] = max(weights["eyeLookDownRight"] ?? 0, downLook)
        }

        // 不变式 S-6：所有权重夹紧至 [0, 1]
        for (key, value) in weights {
            weights[key] = Self.clamp(value.isFinite ? value : 0, 0, 1)
        }

        // 边沿消费动作指令
        let cmd = pendingAction
        pendingAction = nil

        return AvatarPose(
            expressionWeights: weights,
            headRotation: headRotation,
            eyeTarget: eyeTarget,
            action: cmd
        )
    }

    // MARK: - Envelope helper (internal for direct testing)

    static func envelope(
        elapsed: TimeInterval,
        duration: TimeInterval,
        blendIn: TimeInterval,
        blendOut: TimeInterval
    ) -> Float {
        guard duration > 0, elapsed >= 0, elapsed < duration else {
            return 0
        }
        var effIn = max(blendIn, 0)
        var effOut = max(blendOut, 0)
        if effIn + effOut > duration {
            let scale = duration / (effIn + effOut)
            effIn *= scale
            effOut *= scale
        }
        if effIn > 0, elapsed < effIn {
            return Float(Self.clamp(elapsed / effIn, 0, 1))
        }
        if effOut > 0, elapsed > duration - effOut {
            return Float(Self.clamp((duration - elapsed) / effOut, 0, 1))
        }
        return 1.0
    }

    // MARK: - Private helpers

    private func handleExpressionTrigger(_ expr: UserExpression, at now: TimeInterval) {
        let (key, emotion) = Self.reactionMapping(for: expr)

        // S-5：Speaking 期间不被打断，仅在非冷却时叠加轻量微表情（<= 0.3）
        if case .speaking = currentState.kind {
            let inCooldown = currentState.cooldowns[key].map { now < $0 } ?? false
            if !inCooldown {
                speakingOverlay = SpeakingOverlay(
                    emotion: emotion,
                    startedAt: now,
                    duration: Self.durationSeconds(rules.reactionDuration)
                )
                var cooldowns = currentState.cooldowns
                cooldowns[key] = now + rules.cooldown
                currentState = AvatarState(
                    kind: currentState.kind,
                    enteredAt: currentState.enteredAt,
                    baseEmotion: currentState.baseEmotion,
                    cooldowns: cooldowns,
                    scheduled: currentState.scheduled,
                    lastFaceSeenAt: currentState.lastFaceSeenAt
                )
            }
            return
        }

        // S-2 + 决策 2A：冷却期内绝不进入 .reacting、不入队，仅激活柔和底色增强
        if let until = currentState.cooldowns[key], now < until {
            cooldownBoost = CooldownBoost(
                emotion: emotion,
                startedAt: now,
                duration: Self.durationSeconds(rules.reactionDuration)
            )
            return
        }

        // 去重：队列中已有同 key 或当前正在执行同 key 反应，不重复排程
        if currentState.scheduled.contains(where: { $0.key == key }) {
            return
        }
        if case .reacting = currentState.kind, activeReactionKey == key {
            return
        }

        // S-3：300–800 ms 均匀随机延迟排程
        let delay = Self.lerp(rules.reactionDelay.lowerBound, rules.reactionDelay.upperBound, unitRandom())
        let returnTo = Self.underlyingStateKind(of: currentState.kind)
        let reaction = Reaction(
            expression: emotion,
            action: nil,
            duration: rules.reactionDuration,
            returnTo: returnTo
        )
        let scheduledItem = ScheduledReaction(
            key: key,
            reaction: reaction,
            triggerAt: now + delay
        )

        var updatedScheduled = currentState.scheduled
        updatedScheduled.append(scheduledItem)
        updatedScheduled.sort { $0.triggerAt < $1.triggerAt }

        currentState = AvatarState(
            kind: currentState.kind,
            enteredAt: currentState.enteredAt,
            baseEmotion: currentState.baseEmotion,
            cooldowns: currentState.cooldowns,
            scheduled: updatedScheduled,
            lastFaceSeenAt: currentState.lastFaceSeenAt
        )
    }

    private func processScheduledReactions(at evalTime: TimeInterval) {
        guard !currentState.scheduled.isEmpty else { return }

        var due: [ScheduledReaction] = []
        var remaining: [ScheduledReaction] = []
        for item in currentState.scheduled {
            if evalTime + 1e-9 >= item.triggerAt {
                due.append(item)
            } else {
                remaining.append(item)
            }
        }
        guard !due.isEmpty else { return }

        currentState = AvatarState(
            kind: currentState.kind,
            enteredAt: currentState.enteredAt,
            baseEmotion: currentState.baseEmotion,
            cooldowns: currentState.cooldowns,
            scheduled: remaining,
            lastFaceSeenAt: currentState.lastFaceSeenAt
        )

        for item in due {
            // 二次兜底 S-2：冷却中跳过
            if let until = currentState.cooldowns[item.key], evalTime < until {
                continue
            }
            // 二次兜底 S-5：Speaking 期间跳过
            if case .speaking = currentState.kind {
                continue
            }
            // 若当前正在播带动作的反应（如 leanBack），纯表情计划反应不得打断动作
            if case .reacting(let active) = currentState.kind,
               active.action != nil,
               item.reaction.action == nil {
                continue
            }

            // 若打断了另一个 .reacting，将其当前快照推入 fadingLayers 平滑淡出
            snapshotCurrentReactingIfNeeded(at: evalTime)

            let returnTo = Self.underlyingStateKind(of: currentState.kind)
            let reaction = Reaction(
                expression: item.reaction.expression,
                action: item.reaction.action,
                duration: item.reaction.duration,
                returnTo: returnTo
            )
            var cooldowns = currentState.cooldowns
            cooldowns[item.key] = evalTime + rules.cooldown

            currentState = AvatarState(
                kind: .reacting(reaction),
                enteredAt: evalTime,
                baseEmotion: currentState.baseEmotion,
                cooldowns: cooldowns,
                scheduled: currentState.scheduled,
                lastFaceSeenAt: currentState.lastFaceSeenAt
            )
            activeReactionKey = item.key
            if let action = reaction.action {
                pendingAction = .play(action)
            }
        }
    }

    private func pruneTransientLayers(at evalTime: TimeInterval) {
        if let boost = cooldownBoost, evalTime - boost.startedAt + 1e-9 >= boost.duration {
            cooldownBoost = nil
        }
        if let overlay = speakingOverlay, evalTime - overlay.startedAt + 1e-9 >= overlay.duration {
            speakingOverlay = nil
        }
        if !fadingLayers.isEmpty {
            fadingLayers.removeAll { evalTime - $0.startedAt + 1e-9 >= $0.fadeOutDuration }
        }
    }

    private func enterAttending(at now: TimeInterval) {
        currentState = AvatarState(
            kind: .attending,
            enteredAt: now,
            baseEmotion: currentState.baseEmotion,
            cooldowns: currentState.cooldowns,
            scheduled: currentState.scheduled,
            lastFaceSeenAt: currentState.lastFaceSeenAt
        )
        lookingStartedAt = nil
        nextLookAroundAt = nil
        distanceHistory.removeAll()
        if let pos = latestFacePosition {
            distanceHistory.append((now, abs(pos.z)))
        }
        if pendingNoticeOnAttend {
            pendingNoticeOnAttend = false
            pendingAction = .play(.notice)
        }
    }

    @discardableResult
    private func checkFaceLostToIdle(at now: TimeInterval) -> Bool {
        guard case .attending = currentState.kind,
              let lastSeen = currentState.lastFaceSeenAt,
              now - lastSeen + 1e-9 >= rules.idleAfterFaceLost
        else {
            return false
        }
        transitionToIdleWithLookAround(at: now)
        return true
    }

    private func transitionToIdleWithLookAround(at now: TimeInterval) {
        currentState = AvatarState(
            kind: .idle,
            enteredAt: now,
            baseEmotion: currentState.baseEmotion,
            cooldowns: currentState.cooldowns,
            scheduled: [],
            lastFaceSeenAt: currentState.lastFaceSeenAt
        )
        wasFaceTracked = false
        latestFacePosition = nil
        distanceHistory.removeAll()
        lookingStartedAt = nil
        previousActiveExpression = nil
        activeReactionKey = nil
        cooldownBoost = nil
        speakingOverlay = nil
        fadingLayers.removeAll()
        pendingAction = .play(.lookAround)
        nextLookAroundAt = now + Self.lerp(8.0, 14.0, unitRandom())
    }

    private func evaluateRapidApproach(distance: Float, at now: TimeInterval) {
        distanceHistory.removeAll { now - $0.time > rules.approachWindow }
        distanceHistory.append((now, distance))

        if let cooldownUntil = approachCooldownUntil, now < cooldownUntil {
            return
        }
        guard let maxDist = distanceHistory.map(\.distance).max(),
              maxDist - distance > rules.approachDistance
        else {
            return
        }

        let reaction = Reaction(
            expression: .surprised,
            action: .leanBack,
            duration: rules.reactionDuration,
            returnTo: .attending
        )
        currentState = AvatarState(
            kind: .reacting(reaction),
            enteredAt: now,
            baseEmotion: currentState.baseEmotion,
            cooldowns: currentState.cooldowns,
            scheduled: currentState.scheduled,
            lastFaceSeenAt: currentState.lastFaceSeenAt
        )
        activeReactionKey = nil
        pendingAction = .play(.leanBack)
        distanceHistory.removeAll()
        approachCooldownUntil = now + rules.cooldown
    }

    private func checkReactingExpiration(at now: TimeInterval) {
        guard case .reacting(let reaction) = currentState.kind else { return }
        let durationSec = Self.durationSeconds(reaction.duration)
        guard now - currentState.enteredAt + 1e-9 >= durationSec else { return }

        activeReactionKey = nil
        if let lastSeen = currentState.lastFaceSeenAt,
           now - lastSeen + 1e-9 >= rules.idleAfterFaceLost {
            transitionToIdleWithLookAround(at: now)
        } else {
            currentState = AvatarState(
                kind: reaction.returnTo,
                enteredAt: now,
                baseEmotion: currentState.baseEmotion,
                cooldowns: currentState.cooldowns,
                scheduled: currentState.scheduled,
                lastFaceSeenAt: currentState.lastFaceSeenAt
            )
        }
    }

    private func evaluateIdleWander(at time: TimeInterval) -> (pitch: Float, yaw: Float, eye: SIMD2<Float>) {
        if nextWanderAt == nil {
            wanderStartedAt = time
            nextWanderAt = time + Self.lerp(2.5, 5.0, unitRandom())
        } else if let due = nextWanderAt, time >= due {
            let current = currentWanderSample(at: time)
            wanderStartPitch = current.pitch
            wanderStartYaw = current.yaw
            wanderStartEye = current.eye

            let maxYaw: Float = 4 * .pi / 180
            let maxPitch: Float = 3 * .pi / 180
            wanderTargetYaw = Float(Self.lerp(Double(-maxYaw), Double(maxYaw), unitRandom()))
            wanderTargetPitch = Float(Self.lerp(Double(-maxPitch), Double(maxPitch), unitRandom()))
            wanderTargetEye = SIMD2<Float>(
                Float(Self.lerp(-0.45, 0.45, unitRandom())),
                Float(Self.lerp(-0.35, 0.35, unitRandom()))
            )
            wanderStartedAt = time
            nextWanderAt = time + Self.lerp(2.5, 5.0, unitRandom())
        }
        return currentWanderSample(at: time)
    }

    private func currentWanderSample(at time: TimeInterval) -> (pitch: Float, yaw: Float, eye: SIMD2<Float>) {
        guard let started = wanderStartedAt else {
            return (0, 0, .zero)
        }
        let t = Float(Self.clamp((time - started) / wanderTransitionDuration, 0, 1))
        let s = t * t * (3 - 2 * t)
        let pitch = wanderStartPitch + (wanderTargetPitch - wanderStartPitch) * s
        let yaw = wanderStartYaw + (wanderTargetYaw - wanderStartYaw) * s
        let eye = wanderStartEye + (wanderTargetEye - wanderStartEye) * s
        return (pitch, yaw, eye)
    }

    private func unitRandom() -> Double {
        let value = random()
        guard value.isFinite else { return 0.5 }
        return min(max(value, 0), 1)
    }

    private func handleGestureTrigger(_ gesture: GestureEvent, at now: TimeInterval) {
        let (key, emotion, action) = Self.gestureMapping(for: gesture.kind)

        // S-5：Speaking 期间不被打断，仅在非冷却时叠加轻量微表情（<= 0.3）
        if case .speaking = currentState.kind {
            let inCooldown = currentState.cooldowns[key].map { now < $0 } ?? false
            if !inCooldown {
                speakingOverlay = SpeakingOverlay(
                    emotion: emotion,
                    startedAt: now,
                    duration: Self.durationSeconds(rules.reactionDuration)
                )
                var cooldowns = currentState.cooldowns
                cooldowns[key] = now + rules.cooldown
                currentState = AvatarState(
                    kind: currentState.kind,
                    enteredAt: currentState.enteredAt,
                    baseEmotion: currentState.baseEmotion,
                    cooldowns: cooldowns,
                    scheduled: currentState.scheduled,
                    lastFaceSeenAt: currentState.lastFaceSeenAt
                )
            }
            return
        }

        // S-2 + 决策 2A：冷却期内绝不进入 .reacting、不发动作，仅激活柔和底色增强
        if let until = currentState.cooldowns[key], now < until {
            cooldownBoost = CooldownBoost(
                emotion: emotion,
                startedAt: now,
                duration: Self.durationSeconds(rules.reactionDuration)
            )
            return
        }

        // 立即进入 .reacting（0 ms 延迟），旧反应推入 fadingLayers 平滑淡出
        snapshotCurrentReactingIfNeeded(at: now)

        let returnTo = Self.underlyingStateKind(of: currentState.kind)
        let reaction = Reaction(
            expression: emotion,
            action: action,
            duration: rules.reactionDuration,
            returnTo: returnTo
        )
        var cooldowns = currentState.cooldowns
        cooldowns[key] = now + rules.cooldown

        currentState = AvatarState(
            kind: .reacting(reaction),
            enteredAt: now,
            baseEmotion: currentState.baseEmotion,
            cooldowns: cooldowns,
            scheduled: currentState.scheduled,
            lastFaceSeenAt: currentState.lastFaceSeenAt
        )
        activeReactionKey = key
        pendingAction = .play(action)
    }

    private func snapshotCurrentReactingIfNeeded(at evalTime: TimeInterval) {
        if case .reacting(let prev) = currentState.kind,
           let prevPreset = presets[prev.expression] {
            let prevFactor = Self.envelope(
                elapsed: evalTime - currentState.enteredAt,
                duration: Self.durationSeconds(prev.duration),
                blendIn: Self.durationSeconds(prevPreset.blendIn),
                blendOut: Self.durationSeconds(prevPreset.blendOut)
            )
            let fadeOut = Self.durationSeconds(prevPreset.blendOut)
            if prevFactor > 0, fadeOut > 0 {
                var snapshot: [String: Float] = [:]
                for (name, val) in prevPreset.weights {
                    snapshot[name] = val * prevFactor
                }
                fadingLayers.append(FadingLayer(
                    weights: snapshot,
                    startedAt: evalTime,
                    fadeOutDuration: fadeOut
                ))
            }
        }
    }

    private static func gestureMapping(for kind: GestureKind) -> (ReactionKey, EmotionTag, ActionTag) {
        switch kind {
        case .wave: (.wave, .happy, .wave)
        case .heart: (.heart, .shy, .heart)
        case .thumbsUp: (.thumbsUp, .happy, .nod)
        }
    }

    private static func reactionMapping(for expr: UserExpression) -> (ReactionKey, EmotionTag) {
        switch expr {
        case .smiling: (.smile, .happy)
        case .frowning: (.frown, .concerned)
        case .surprised: (.surprise, .surprised)
        }
    }

    private static func underlyingStateKind(of kind: AvatarStateKind) -> AvatarStateKind {
        var cursor = kind
        while case .reacting(let reaction) = cursor {
            cursor = reaction.returnTo
        }
        return cursor
    }

    private static func durationSeconds(_ duration: Duration) -> TimeInterval {
        let c = duration.components
        return Double(c.seconds) + Double(c.attoseconds) * 1e-18
    }

    private static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    private static func clamp<T: Comparable>(_ value: T, _ lower: T, _ upper: T) -> T {
        min(max(value, lower), upper)
    }
}
