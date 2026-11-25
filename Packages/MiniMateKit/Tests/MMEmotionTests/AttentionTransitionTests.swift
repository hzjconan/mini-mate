import Foundation
import Testing
import simd
import MMCore
import MMEmotion
import MMPerception

private struct FixedClock: MMCore.Clock {
    let now: Date

    init(timeIntervalSinceReferenceDate seconds: TimeInterval = 1_000) {
        self.now = Date(timeIntervalSinceReferenceDate: seconds)
    }

    func sleep(for duration: Duration) async throws {}
}

@Suite("AttentionTransition")
struct AttentionTransitionTests {

    private func makeFaceFeature(
        at t: TimeInterval,
        isTracked: Bool = true,
        isLooking: Bool = true,
        position: SIMD3<Float>? = SIMD3<Float>(0, 0, 0.5),
        rawBlendShapes: [String: Float] = [:]
    ) -> PerceptionFeatures {
        PerceptionFeatures(
            timestamp: t,
            isFaceTracked: isTracked,
            rawBlendShapes: rawBlendShapes,
            signals: FaceSignals(),
            facePosition: isTracked ? position : nil,
            isLookingAtScreen: isTracked ? isLooking : false,
            gesture: nil
        )
    }

    @Test("Idle 持续注视 199ms 保持 Idle，200ms 进入 Attending 且首次见人无 notice")
    func idleToAttendingRequires200msAndNoNoticeOnFirstSight() async {
        let sm = RuleBasedEmotionStateMachine(
            clock: FixedClock(timeIntervalSinceReferenceDate: 10),
            random: { 0.5 }
        )

        await sm.handle(makeFaceFeature(at: 10.000, isLooking: true))
        #expect(await sm.state.kind == .idle)

        await sm.handle(makeFaceFeature(at: 10.199, isLooking: true))
        #expect(await sm.state.kind == .idle)

        await sm.handle(makeFaceFeature(at: 10.200, isLooking: true))
        #expect(await sm.state.kind == .attending)

        let pose = await sm.pose(at: 10.200)
        #expect(pose.action == nil)
    }

    @Test("Attending 人脸丢失 2.9s 保持 Attending，3.0s 回 Idle 并边沿触发 lookAround")
    func attendingReturnsToIdleAfter3sFaceLostWithEdgeLookAround() async {
        let sm = RuleBasedEmotionStateMachine(
            clock: FixedClock(timeIntervalSinceReferenceDate: 10),
            random: { 0.5 }
        )

        await sm.handle(makeFaceFeature(at: 10.0, isLooking: true))
        await sm.handle(makeFaceFeature(at: 10.2, isLooking: true))
        #expect(await sm.state.kind == .attending)

        // 人脸从 10.3 开始丢失，lastFaceSeenAt == 10.2
        await sm.handle(makeFaceFeature(at: 13.1, isTracked: false, isLooking: false))
        #expect(await sm.state.kind == .attending)

        await sm.handle(makeFaceFeature(at: 13.2, isTracked: false, isLooking: false))
        #expect(await sm.state.kind == .idle)

        let firstPose = await sm.pose(at: 13.2)
        #expect(firstPose.action == .play(.lookAround))

        let nextPose = await sm.pose(at: 13.25)
        #expect(nextPose.action == nil)
    }

    @Test("离开 >3s 后回来并注视 200ms 触发 notice；仅离开 1.5s 再回不触发 notice")
    func noticeTriggersOnlyAfterLeavingOver3Seconds() async {
        let sm = RuleBasedEmotionStateMachine(
            clock: FixedClock(timeIntervalSinceReferenceDate: 10),
            random: { 0.5 }
        )

        // 先进入 Attending（lastFaceSeenAt = 10.2）
        await sm.handle(makeFaceFeature(at: 10.0, isLooking: true))
        await sm.handle(makeFaceFeature(at: 10.2, isLooking: true))
        #expect(await sm.state.kind == .attending)

        // 离开 5.0 秒（10.2 -> 15.2）
        await sm.handle(makeFaceFeature(at: 13.2, isTracked: false, isLooking: false))
        #expect(await sm.state.kind == .idle)
        _ = await sm.pose(at: 13.2) // 消费 lookAround

        // 15.2 回到画面（15.2 - 10.2 = 5.0 > 3.0）并持续注视 200 ms
        await sm.handle(makeFaceFeature(at: 15.2, isTracked: true, isLooking: true))
        #expect(await sm.state.kind == .idle)
        await sm.handle(makeFaceFeature(at: 15.4, isTracked: true, isLooking: true))
        #expect(await sm.state.kind == .attending)

        let noticePose = await sm.pose(at: 15.4)
        #expect(noticePose.action == .play(.notice))
        #expect(await sm.pose(at: 15.45).action == nil)

        // 仅离开 1.5s（不满足 >3s）再回：先模拟主动 resetToIdle 或短暂丢失后回到画面
        let smShort = RuleBasedEmotionStateMachine(
            clock: FixedClock(timeIntervalSinceReferenceDate: 10),
            random: { 0.5 }
        )
        await smShort.handle(makeFaceFeature(at: 10.0, isLooking: true))
        await smShort.handle(makeFaceFeature(at: 10.2, isLooking: true))
        await smShort.resetToIdle(at: 10.2)
        await smShort.handle(makeFaceFeature(at: 10.3, isTracked: false, isLooking: false))
        // 离开 1.5s（11.7 - 10.2 = 1.5 <= 3.0）再回并注视 200ms
        await smShort.handle(makeFaceFeature(at: 11.7, isTracked: true, isLooking: true))
        await smShort.handle(makeFaceFeature(at: 11.9, isTracked: true, isLooking: true))
        #expect(await smShort.state.kind == .attending)
        #expect(await smShort.pose(at: 11.9).action == nil)
    }

    @Test("Attending 1s 内快速靠近 >10cm 触发 leanBack，1.5s 后恢复且冷却期不重复触发")
    func rapidApproachTriggersLeanBackWithRecoveryAndCooldown() async {
        let sm = RuleBasedEmotionStateMachine(
            clock: FixedClock(timeIntervalSinceReferenceDate: 10),
            random: { 0.5 }
        )

        await sm.handle(makeFaceFeature(at: 10.0, position: SIMD3(0, 0, 0.60)))
        await sm.handle(makeFaceFeature(at: 10.2, position: SIMD3(0, 0, 0.60)))
        #expect(await sm.state.kind == .attending)

        // 0.3s 内仅靠近 8cm（<= 10cm 阈值）不触发
        await sm.handle(makeFaceFeature(at: 10.5, position: SIMD3(0, 0, 0.52)))
        #expect(await sm.state.kind == .attending)

        // 0.5s 内从 0.60m 靠近到 0.48m（Δ = 0.12m > 0.10m）触发 leanBack
        await sm.handle(makeFaceFeature(at: 10.7, position: SIMD3(0, 0, 0.48)))
        let stateAfterApproach = await sm.state
        let expectedReaction = Reaction(
            expression: .surprised,
            action: .leanBack,
            duration: .milliseconds(1500),
            returnTo: .attending
        )
        #expect(stateAfterApproach.kind == .reacting(expectedReaction))

        let reactPose = await sm.pose(at: 10.7)
        #expect(reactPose.action == .play(.leanBack))

        // 1.4s 时仍在 reacting
        _ = await sm.pose(at: 12.1)
        #expect(await sm.state.kind == .reacting(expectedReaction))

        // 1.5s 后（10.7 + 1.5 = 12.2）回到 attending
        _ = await sm.pose(at: 12.2)
        #expect(await sm.state.kind == .attending)

        // 冷却期内（默认 8s，12.5 < 18.7）再次快速靠近不重复触发
        await sm.handle(makeFaceFeature(at: 12.5, position: SIMD3(0, 0, 0.65)))
        await sm.handle(makeFaceFeature(at: 12.9, position: SIMD3(0, 0, 0.40)))
        #expect(await sm.state.kind == .attending)
        #expect(await sm.pose(at: 12.9).action == nil)
    }

    @Test("人脸在右上方时头部与眼部方向正确，极端偏角严格限幅在 ±25° 内")
    func gazeDirectionAndHeadAngleClamping() async {
        let sm = RuleBasedEmotionStateMachine(
            clock: FixedClock(timeIntervalSinceReferenceDate: 0),
            random: { 0.5 },
            idleConfig: IdleMotionLayer.Config(breathAmplitude: 0)
        )

        await sm.handle(makeFaceFeature(at: 0.0, position: SIMD3(0.3, 0.2, 0.5)))
        await sm.handle(makeFaceFeature(at: 0.2, position: SIMD3(0.3, 0.2, 0.5)))

        let pose = await sm.pose(at: 0.2)
        #expect(pose.headRotation.y > 0)
        #expect(pose.headRotation.x < 0)
        #expect(pose.eyeTarget.x > 0)
        #expect(pose.eyeTarget.y > 0)
        #expect((pose.expressionWeights["eyeLookOutLeft"] ?? 0) > 0)
        #expect((pose.expressionWeights["eyeLookInRight"] ?? 0) > 0)
        #expect((pose.expressionWeights["eyeLookUpLeft"] ?? 0) > 0)
        #expect((pose.expressionWeights["eyeLookUpRight"] ?? 0) > 0)

        // 极端大偏角时每轴 <= 25° + 1e-5
        await sm.handle(makeFaceFeature(at: 0.4, position: SIMD3(2.0, 2.0, 0.2)))
        let clampedPose = await sm.pose(at: 0.4)
        let maxRad = RuleBasedEmotionStateMachine.maxHeadAngleRadians + 1e-5
        #expect(abs(clampedPose.headRotation.x) <= maxRad)
        #expect(abs(clampedPose.headRotation.y) <= maxRad)
        #expect(abs(clampedPose.headRotation.z) <= maxRad)
    }

    @Test("不变式 S-1 与 S-6：rawBlendShapes 绝不透传至输出且所有权重在 [0, 1]")
    func invariantsS1AndS6Hold() async {
        let sm = RuleBasedEmotionStateMachine(
            clock: FixedClock(timeIntervalSinceReferenceDate: 0),
            random: { 0.5 }
        )

        await sm.handle(makeFaceFeature(
            at: 0.0,
            position: SIMD3(0.1, 0.1, 0.5),
            rawBlendShapes: ["jawOpen": 0.95, "mouthSmileLeft": 0.9, "browInnerUp": 0.85]
        ))
        await sm.handle(makeFaceFeature(
            at: 0.2,
            position: SIMD3(0.1, 0.1, 0.5),
            rawBlendShapes: ["jawOpen": 0.95, "mouthSmileLeft": 0.9, "browInnerUp": 0.85]
        ))

        let pose = await sm.pose(at: 0.2)
        #expect((pose.expressionWeights["jawOpen"] ?? 0) == 0)
        #expect((pose.expressionWeights["mouthSmileLeft"] ?? 0) == 0)
        #expect((pose.expressionWeights["browInnerUp"] ?? 0) == 0)
        for (_, value) in pose.expressionWeights {
            #expect(value >= 0 && value <= 1)
        }
    }

    @Test("resetToIdle 立即回到 Idle，且 Idle 期间持续产出 [2, 6]s 眨眼与呼吸")
    func resetToIdleAndIdleBlinkBreath() async {
        let sm = RuleBasedEmotionStateMachine(
            clock: FixedClock(timeIntervalSinceReferenceDate: 0),
            random: { 0.0 } // blinkInterval 下界 2.0s
        )

        await sm.handle(makeFaceFeature(at: 0.0))
        await sm.handle(makeFaceFeature(at: 0.2))
        #expect(await sm.state.kind == .attending)

        await sm.resetToIdle(at: 0.2)
        #expect(await sm.state.kind == .idle)

        // 0.2 初始化下次眨眼在 2.2s，2.2 + 0.075 = 2.275 为峰值
        _ = await sm.pose(at: 0.2)
        let blinkPeak = await sm.pose(at: 2.275)
        #expect((blinkPeak.expressionWeights["eyeBlinkLeft"] ?? 0) > 0.9)
        #expect((blinkPeak.expressionWeights["eyeBlinkRight"] ?? 0) > 0.9)
    }

    @Test("Idle 期间按 8-14s 周期触发低频 lookAround")
    func idleTriggersPeriodicLookAroundBetween8And14Seconds() async {
        let sm = RuleBasedEmotionStateMachine(
            clock: FixedClock(timeIntervalSinceReferenceDate: 0),
            random: { 0.5 } // lerp(8, 14, 0.5) == 11.0s
        )

        // t=0 初始化 nextLookAroundAt = 11.0
        #expect(await sm.pose(at: 0.0).action == nil)
        #expect(await sm.pose(at: 10.9).action == nil)
        #expect(await sm.pose(at: 11.0).action == .play(.lookAround))
        #expect(await sm.pose(at: 11.1).action == nil)
        #expect(await sm.pose(at: 22.0).action == .play(.lookAround))
    }

    @Test("Reacting 到期时若人脸已丢失 >= 3s 直接回 Idle 并触发 lookAround")
    func reactingExpirationTransitionsToIdleWhenFaceLostOver3Seconds() async {
        let rules = ReactionRules(
            reactionDuration: .seconds(4),
            idleAfterFaceLost: 3
        )
        let sm = RuleBasedEmotionStateMachine(
            rules: rules,
            clock: FixedClock(timeIntervalSinceReferenceDate: 10),
            random: { 0.5 }
        )

        await sm.handle(makeFaceFeature(at: 10.0, position: SIMD3(0, 0, 0.60)))
        await sm.handle(makeFaceFeature(at: 10.2, position: SIMD3(0, 0, 0.60)))
        await sm.handle(makeFaceFeature(at: 10.7, position: SIMD3(0, 0, 0.40)))
        _ = await sm.pose(at: 10.7) // 消费 leanBack

        // 人脸从 10.8 起不再出现，lastFaceSeenAt == 10.7；4s 后（14.7）Reacting 到期且 14.7 - 10.7 == 4.0 >= 3.0
        let expiredPose = await sm.pose(at: 14.7)
        #expect(await sm.state.kind == .idle)
        #expect(expiredPose.action == .play(.lookAround))
    }
}
