import Foundation
import Testing
@testable import MMCore
@testable import MMPerception
@testable import MMEmotion
@testable import MMAvatar

@Suite("NoMirroring")
struct NoMirroringTests {
    @Test func pearsonHandlesConstantZeroVarianceWithoutNaN() {
        let xs = [0.0, 0.2, 0.5, 0.8, 0.3]
        let constantYs = [0.0, 0.0, 0.0, 0.0, 0.0]

        let r = MirrorCorrelationEvaluator.pearson(xs, constantYs)
        #expect(!r.isNaN)
        #expect(r == 0.0)

        let shortR = MirrorCorrelationEvaluator.pearson([1.0], [1.0])
        #expect(!shortR.isNaN)
        #expect(shortR == 0.0)
    }

    @Test func evaluatorExcludesGazeChannelsAndFlagsDeliberateMirroring() {
        var mirroredPairs: [(user: [String: Float], avatar: [String: Float])] = []
        for i in 0..<120 {
            let v = Float(sin(Double(i) * 0.2) * 0.5 + 0.5)
            let user: [String: Float] = [
                "mouthSmileLeft": v,
                "cheekPuff": v * 0.8,
                "eyeLookOutLeft": v,
            ]
            // 故意直接拷贝 rawBlendShapes 作为形象输出
            mirroredPairs.append((user: user, avatar: user))
        }

        let report = MirrorCorrelationEvaluator.evaluate(pairs: mirroredPairs, duration: 2.0)
        #expect(report.sampleCount == 120)
        #expect(!report.perChannel.keys.contains("eyeLookOutLeft"))
        #expect(report.maxAbsCorrelation > 0.99)
        #expect(report.passed == false)
    }

    @Test func evaluatorIgnoresEyeLookEvenWhenPerfectlyCorrelated() {
        var pairs: [(user: [String: Float], avatar: [String: Float])] = []
        for i in 0..<100 {
            let v = Float(sin(Double(i) * 0.15) * 0.5 + 0.5)
            let user: [String: Float] = [
                "eyeLookOutLeft": v,
                "eyeLookInRight": v,
                "cheekPuff": v,
            ]
            let avatar: [String: Float] = [
                "eyeLookOutLeft": v,
                "eyeLookInRight": v,
                "cheekPuff": 0,
            ]
            pairs.append((user: user, avatar: avatar))
        }

        let report = MirrorCorrelationEvaluator.evaluate(pairs: pairs, duration: 2.0)
        #expect(!report.perChannel.keys.contains("eyeLookOutLeft"))
        #expect(!report.perChannel.keys.contains("eyeLookInRight"))
        #expect(report.perChannel["cheekPuff"] == 0.0)
        #expect(report.maxAbsCorrelation == 0.0)
        #expect(report.passed == true)
    }

    @Test @MainActor func recordingAvatarRendererCapturesLoadsAndPoses() async throws {
        let renderer = RecordingAvatarRenderer()
        let caps = try await renderer.load(named: "minimate")
        #expect(renderer.loadedAssetNames == ["minimate"])
        #expect(caps.blendShapeNames.count == 52)
        #expect(caps.actionNames == Set(ActionTag.allCases.map(\.rawValue)))

        let pose = AvatarPose(expressionWeights: ["mouthSmileLeft": 0.7])
        renderer.apply(pose)
        #expect(renderer.poses.count == 1)
        #expect(renderer.poses[0].expressionWeights["mouthSmileLeft"] == 0.7)

        renderer.reset()
        #expect(renderer.poses.isEmpty)
        #expect(renderer.loadedAssetNames.isEmpty)
    }

    @Test @MainActor func thirtySecondFreeExpressionReplaySatisfiesNoMirroringAndSC004() async throws {
        let totalFrames = 1800 // 30 s @ 60 Hz
        let dt: TimeInterval = 1.0 / 60.0

        var rawFrames: [PerceptionFeatures] = []
        rawFrames.reserveCapacity(totalFrames)

        for i in 0..<totalFrames {
            let t = Double(i) * dt
            var shapes: [String: Float] = [:]

            // 头部左右缓慢摆动（驱动 eyeLook* 视线通道）
            let faceX = Float(0.08 * sin(t * 0.7))
            let facePos = SIMD3<Float>(faceX, 0.01 * Float(cos(t * 0.5)), 0.50)

            // 自由表情：未映射通道全程大幅度变化
            shapes["cheekPuff"] = Float(0.5 + 0.5 * sin(t * 1.9))
            shapes["mouthPucker"] = Float(0.5 + 0.5 * cos(t * 1.3))
            shapes["jawLeft"] = Float(0.5 + 0.5 * sin(t * 2.3 + 0.4))
            shapes["noseSneerLeft"] = Float(0.5 + 0.5 * cos(t * 1.7 + 0.8))
            shapes["eyeLookOutLeft"] = max(0, Float(sin(t * 0.7))) * 0.8

            // 分时段做出明显微笑、皱眉、惊讶，真实触发状态机反应（5.0–5.8 s 落在首次微笑 8 s 冷却期内，同时覆盖非冷却与冷却场景）
            if (t >= 1.0 && t <= 2.2) || (t >= 5.0 && t <= 5.8) || (t >= 12.0 && t <= 13.0) || (t >= 23.0 && t <= 24.0) {
                shapes["mouthSmileLeft"] = 0.85
                shapes["mouthSmileRight"] = 0.85
            } else {
                // 加入非触发级小幅波动
                let noise = Float(0.2 * (0.5 + 0.5 * sin(t * 3.1)))
                shapes["mouthSmileLeft"] = noise
                shapes["mouthSmileRight"] = noise
            }

            if (t >= 4.5 && t <= 5.8) || (t >= 16.0 && t <= 17.2) {
                shapes["browDownLeft"] = 0.85
                shapes["browDownRight"] = 0.80
                shapes["mouthFrownLeft"] = 0.70
                shapes["mouthFrownRight"] = 0.70
            }

            if (t >= 8.0 && t <= 9.0) || (t >= 19.5 && t <= 20.4) {
                shapes["browInnerUp"] = 0.90
                shapes["jawOpen"] = 0.80
                shapes["eyeWideLeft"] = 0.85
                shapes["eyeWideRight"] = 0.85
            }

            rawFrames.append(PerceptionFeatures(
                timestamp: t,
                isFaceTracked: true,
                rawBlendShapes: shapes,
                signals: FaceSignals(),
                facePosition: facePos,
                isLookingAtScreen: true
            ))
        }

        // 通过 ScriptedPerceptionSource 回放完整 30 s 序列
        let source = ScriptedPerceptionSource(frames: rawFrames, replayMode: .immediate)
        var deriver = FaceSignalDeriver()
        let clock = ReplayFixedClock(initial: Date(timeIntervalSinceReferenceDate: 0))
        // 固定确定性随机序列（延迟 0.55 s），确保测试 100% 确定性
        let stateMachine = RuleBasedEmotionStateMachine(
            rules: .defaults,
            presets: ExpressionPreset.bundledDefaults,
            clock: clock,
            random: { 0.5 },
            idleConfig: IdleMotionLayer.Config(blinkInterval: 100...100, breathAmplitude: 0)
        )
        let renderer = RecordingAvatarRenderer()

        let stream = source.features
        try await source.start()

        var pairs: [(user: [String: Float], avatar: [String: Float])] = []
        pairs.reserveCapacity(totalFrames)
        var reactedCount = 0

        for await frame in stream {
            let derived = deriver.update(blendShapes: frame.rawBlendShapes, at: frame.timestamp)
            let enriched = PerceptionFeatures(
                timestamp: frame.timestamp,
                isFaceTracked: frame.isFaceTracked,
                rawBlendShapes: frame.rawBlendShapes,
                signals: derived,
                facePosition: frame.facePosition,
                isLookingAtScreen: frame.isLookingAtScreen,
                gesture: frame.gesture
            )
            await stateMachine.handle(enriched)
            let pose = await stateMachine.pose(at: frame.timestamp)
            renderer.apply(pose)
            if case .reacting = await stateMachine.state.kind {
                reactedCount += 1
            }
            pairs.append((user: frame.rawBlendShapes, avatar: pose.expressionWeights))
        }

        #expect(renderer.poses.count == totalFrames)
        #expect(reactedCount > 0, "30 s 自由表情回放期间应实际触发过状态机反应")

        // S-1：未映射通道全程严格为 0
        for pose in renderer.poses {
            #expect((pose.expressionWeights["cheekPuff"] ?? 0) == 0)
            #expect((pose.expressionWeights["mouthPucker"] ?? 0) == 0)
            #expect((pose.expressionWeights["jawLeft"] ?? 0) == 0)
            #expect((pose.expressionWeights["noseSneerLeft"] ?? 0) == 0)
        }

        // SC-004：排除 eyeLook* 后全部非视线表情通道 |r| < 0.3
        let report = MirrorCorrelationEvaluator.evaluate(pairs: pairs, duration: 30.0)
        #expect(report.sampleCount == totalFrames)
        #expect(!report.perChannel.keys.contains("eyeLookOutLeft"))
        #expect(report.maxAbsCorrelation < 0.3, "实际最大 |r|=\(report.maxAbsCorrelation) (\(report.maxChannelName ?? "nil"))")
        #expect(report.passed == true)
    }
}

private final class ReplayFixedClock: MMCore.Clock, @unchecked Sendable {
    var now: Date

    init(initial: Date) {
        self.now = initial
    }

    func sleep(for duration: Duration) async throws {}
}
