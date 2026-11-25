import Foundation
import simd
import MMCore
import MMPerception

/// 基于规则的情绪与注意力状态机（US2：Idle ↔ Attending、notice、lookAround、leanBack、视线与头部追踪、待机层合成）。
public actor RuleBasedEmotionStateMachine: EmotionStateMachine {
    public static let maxHeadAngleRadians: Float = 25 * .pi / 180

    private let rules: ReactionRules
    private let presets: [EmotionTag: ExpressionPreset]
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
        presets: [EmotionTag: ExpressionPreset] = [:],
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

        // 先检查 Reacting 到期回收
        checkReactingExpiration(at: now)

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

        // 2. 状态转移
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
            // 留给 US5
            break
        }
    }

    public func handle(_ event: ConversationEvent) async {
        // US5 实现对话事件转换，US2 保持无副作用空实现
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
    }

    public func pose(at time: TimeInterval) async -> AvatarPose {
        let evalTime: TimeInterval
        if let last = lastEvaluatedTime, time < last {
            evalTime = last
        } else {
            evalTime = time
        }
        lastEvaluatedTime = evalTime

        // 检查到期与超时转移
        checkReactingExpiration(at: evalTime)
        _ = checkFaceLostToIdle(at: evalTime)

        // Idle 低频张望调度
        if case .idle = currentState.kind {
            if nextLookAroundAt == nil {
                nextLookAroundAt = evalTime + Self.lerp(8.0, 14.0, unitRandom())
            } else if let due = nextLookAroundAt, evalTime >= due {
                pendingAction = .play(.lookAround)
                nextLookAroundAt = evalTime + Self.lerp(8.0, 14.0, unitRandom())
            }
        }

        // Step 1：底色情绪（0.3 强度）与 Reacting 表情（满强度）
        var weights: [String: Float] = [:]
        if let basePreset = presets[currentState.baseEmotion] {
            for (name, value) in basePreset.weights {
                weights[name] = value * 0.3
            }
        }
        if case .reacting(let reaction) = currentState.kind,
           let reactPreset = presets[reaction.expression] {
            for (name, value) in reactPreset.weights {
                weights[name] = max(weights[name] ?? 0, value)
            }
        }

        // Step 5：待机层（呼吸 + 眨眼）
        let idleMotion = idleLayer.update(at: evalTime)
        weights["eyeBlinkLeft"] = max(weights["eyeBlinkLeft"] ?? 0, idleMotion.eyeBlink)
        weights["eyeBlinkRight"] = max(weights["eyeBlinkRight"] ?? 0, idleMotion.eyeBlink)

        // Step 6：视线与头部朝向
        let gazePitch: Float
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

    // MARK: - Private helpers

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
            scheduled: currentState.scheduled,
            lastFaceSeenAt: currentState.lastFaceSeenAt
        )
        wasFaceTracked = false
        latestFacePosition = nil
        distanceHistory.removeAll()
        lookingStartedAt = nil
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
        pendingAction = .play(.leanBack)
        distanceHistory.removeAll()
        approachCooldownUntil = now + rules.cooldown
    }

    private func checkReactingExpiration(at now: TimeInterval) {
        guard case .reacting(let reaction) = currentState.kind else { return }
        let durationSec = Self.durationSeconds(reaction.duration)
        guard now - currentState.enteredAt + 1e-9 >= durationSec else { return }

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
        // smoothstep
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
