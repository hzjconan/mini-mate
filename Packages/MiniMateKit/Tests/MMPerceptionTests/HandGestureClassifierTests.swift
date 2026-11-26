import Foundation
import Testing
@testable import MMPerception

@Suite("HandGestureClassifier")
struct HandGestureClassifierTests {

    // MARK: - 合成关节点构造工具

    private func makeOpenPalm(
        wristX cx: Float,
        wristY cy: Float,
        scale s: Float = 0.15,
        confidence c: Float = 0.9
    ) -> HandPoseFrame {
        var joints: [HandJointName: HandJointPoint] = [
            .wrist: HandJointPoint(x: cx, y: cy, confidence: c),
            .thumbCMC: HandJointPoint(x: cx - 0.35 * s, y: cy + 0.35 * s, confidence: c),
            .thumbMP: HandJointPoint(x: cx - 0.55 * s, y: cy + 0.65 * s, confidence: c),
            .thumbIP: HandJointPoint(x: cx - 0.75 * s, y: cy + 0.90 * s, confidence: c),
            .thumbTip: HandJointPoint(x: cx - 0.90 * s, y: cy + 1.15 * s, confidence: c),
        ]
        let fingers: [(HandJointName, HandJointName, HandJointName, HandJointName, Float)] = [
            (.indexMCP, .indexPIP, .indexDIP, .indexTip, -0.30),
            (.middleMCP, .middlePIP, .middleDIP, .middleTip, 0.00),
            (.ringMCP, .ringPIP, .ringDIP, .ringTip, 0.30),
            (.littleMCP, .littlePIP, .littleDIP, .littleTip, 0.55),
        ]
        for (mcp, pip, dip, tip, dxRatio) in fingers {
            let x = cx + dxRatio * s
            joints[mcp] = HandJointPoint(x: x, y: cy + 1.00 * s, confidence: c)
            joints[pip] = HandJointPoint(x: x, y: cy + 1.45 * s, confidence: c)
            joints[dip] = HandJointPoint(x: x, y: cy + 1.75 * s, confidence: c)
            joints[tip] = HandJointPoint(x: x, y: cy + 2.05 * s, confidence: c)
        }
        return HandPoseFrame(joints: joints)
    }

    private func makeThumbsUp(
        wristX cx: Float = 0.5,
        wristY cy: Float = 0.4,
        scale s: Float = 0.15,
        thumbAngleFromUpRadians angle: Float = 0,
        confidence c: Float = 0.92
    ) -> HandPoseFrame {
        let dirX = sin(angle)
        let dirY = cos(angle)
        let thumbCMC = HandJointPoint(x: cx + 0.35 * s, y: cy + 0.25 * s, confidence: c)
        let thumbMP = HandJointPoint(x: cx + 0.50 * s, y: cy + 0.55 * s, confidence: c)
        let thumbIP = HandJointPoint(x: thumbMP.x + 0.45 * s * dirX, y: thumbMP.y + 0.45 * s * dirY, confidence: c)
        let thumbTip = HandJointPoint(x: thumbMP.x + 0.90 * s * dirX, y: thumbMP.y + 0.90 * s * dirY, confidence: c)

        var joints: [HandJointName: HandJointPoint] = [
            .wrist: HandJointPoint(x: cx, y: cy, confidence: c),
            .thumbCMC: thumbCMC,
            .thumbMP: thumbMP,
            .thumbIP: thumbIP,
            .thumbTip: thumbTip,
        ]
        let fingers: [(HandJointName, HandJointName, HandJointName, HandJointName, Float)] = [
            (.indexMCP, .indexPIP, .indexDIP, .indexTip, 0.35),
            (.middleMCP, .middlePIP, .middleDIP, .middleTip, 0.00),
            (.ringMCP, .ringPIP, .ringDIP, .ringTip, -0.20),
            (.littleMCP, .littlePIP, .littleDIP, .littleTip, -0.40),
        ]
        for (mcp, pip, dip, tip, dyRatio) in fingers {
            let y = cy + dyRatio * s
            joints[mcp] = HandJointPoint(x: cx + 1.00 * s, y: y, confidence: c)
            joints[pip] = HandJointPoint(x: cx + 1.25 * s, y: y, confidence: c)
            joints[dip] = HandJointPoint(x: cx + 1.00 * s, y: y - 0.10 * s, confidence: c)
            joints[tip] = HandJointPoint(x: cx + 0.70 * s, y: y - 0.15 * s, confidence: c)
        }
        return HandPoseFrame(joints: joints)
    }

    private func makeHeartHands(
        centerX cx: Float = 0.5,
        centerY cy: Float = 0.5,
        scale s: Float = 0.15,
        wristGapRatio: Float = 1.60,
        indexTipGapRatio: Float = 0.20,
        thumbTipGapRatio: Float = 0.20,
        verticalSepRatio: Float = 0.75,
        indexMCPGapRatio: Float = 1.10,
        confidence c: Float = 0.88
    ) -> [HandPoseFrame] {
        let halfWrist = 0.5 * wristGapRatio * s
        let halfIndexTip = 0.5 * indexTipGapRatio * s
        let halfThumbTip = 0.5 * thumbTipGapRatio * s
        let halfIndexMCP = 0.5 * indexMCPGapRatio * s

        let leftWristX = cx - halfWrist
        let rightWristX = cx + halfWrist
        let wristY = cy - 0.60 * s
        let thumbTipY = cy + 0.10 * s
        let indexTipY = thumbTipY + verticalSepRatio * s
        let indexMCPY = cy + 0.35 * s

        let left = HandPoseFrame(joints: [
            .wrist: HandJointPoint(x: leftWristX, y: wristY, confidence: c),
            .middleMCP: HandJointPoint(x: leftWristX, y: wristY + s, confidence: c),
            .indexMCP: HandJointPoint(x: cx - halfIndexMCP, y: indexMCPY, confidence: c),
            .indexTip: HandJointPoint(x: cx - halfIndexTip, y: indexTipY, confidence: c),
            .thumbTip: HandJointPoint(x: cx - halfThumbTip, y: thumbTipY, confidence: c),
        ])
        let right = HandPoseFrame(joints: [
            .wrist: HandJointPoint(x: rightWristX, y: wristY, confidence: c),
            .middleMCP: HandJointPoint(x: rightWristX, y: wristY + s, confidence: c),
            .indexMCP: HandJointPoint(x: cx + halfIndexMCP, y: indexMCPY, confidence: c),
            .indexTip: HandJointPoint(x: cx + halfIndexTip, y: indexTipY, confidence: c),
            .thumbTip: HandJointPoint(x: cx + halfThumbTip, y: thumbTipY, confidence: c),
        ])
        return [left, right]
    }

    private func makeSingleHandHeart(
        wristX cx: Float = 0.50,
        wristY cy: Float = 0.35,
        scale s: Float = 0.16,
        mirrored: Bool = false,
        lowerFingersExtended: Bool = false,
        confidence c: Float = 0.90
    ) -> HandPoseFrame {
        let sign: Float = mirrored ? -1.0 : 1.0
        var joints: [HandJointName: HandJointPoint] = [
            .wrist: HandJointPoint(x: cx, y: cy, confidence: c),
            .thumbCMC: HandJointPoint(x: cx - 0.30 * s * sign, y: cy + 0.35 * s, confidence: c),
            .thumbMP: HandJointPoint(x: cx - 0.35 * s * sign, y: cy + 0.75 * s, confidence: c),
            .thumbIP: HandJointPoint(x: cx - 0.18 * s * sign, y: cy + 1.15 * s, confidence: c),
            .thumbTip: HandJointPoint(x: cx + 0.04 * s * sign, y: cy + 1.48 * s, confidence: c),
            .indexMCP: HandJointPoint(x: cx - 0.15 * s * sign, y: cy + 1.00 * s, confidence: c),
            .indexPIP: HandJointPoint(x: cx - 0.12 * s * sign, y: cy + 1.32 * s, confidence: c),
            .indexDIP: HandJointPoint(x: cx - 0.06 * s * sign, y: cy + 1.50 * s, confidence: c),
            .indexTip: HandJointPoint(x: cx - 0.02 * s * sign, y: cy + 1.58 * s, confidence: c),
        ]

        let lowerFingers: [(HandJointName, HandJointName, HandJointName, HandJointName, Float)] = [
            (.middleMCP, .middlePIP, .middleDIP, .middleTip, 0.10),
            (.ringMCP, .ringPIP, .ringDIP, .ringTip, 0.32),
            (.littleMCP, .littlePIP, .littleDIP, .littleTip, 0.52),
        ]
        for (mcp, pip, dip, tip, dxRatio) in lowerFingers {
            let x = cx + dxRatio * s * sign
            joints[mcp] = HandJointPoint(x: x, y: cy + 1.00 * s, confidence: c)
            if lowerFingersExtended {
                joints[pip] = HandJointPoint(x: x, y: cy + 1.45 * s, confidence: c)
                joints[dip] = HandJointPoint(x: x, y: cy + 1.75 * s, confidence: c)
                joints[tip] = HandJointPoint(x: x, y: cy + 2.05 * s, confidence: c)
            } else {
                joints[pip] = HandJointPoint(x: x, y: cy + 1.15 * s, confidence: c)
                joints[dip] = HandJointPoint(x: x, y: cy + 0.90 * s, confidence: c)
                joints[tip] = HandJointPoint(x: x, y: cy + 0.72 * s, confidence: c)
            }
        }
        return HandPoseFrame(joints: joints)
    }

    private func makeTiltedOpenPalm(
        wristX cx: Float,
        wristY cy: Float,
        tiltRadians theta: Float,
        scale s: Float = 0.15,
        confidence c: Float = 0.9
    ) -> HandPoseFrame {
        let base = makeOpenPalm(wristX: cx, wristY: cy, scale: s, confidence: c)
        let cosT = cos(theta)
        let sinT = sin(theta)
        var rotated: [HandJointName: HandJointPoint] = [:]
        for (name, pt) in base.joints {
            let dx = pt.x - cx
            let dy = pt.y - cy
            rotated[name] = HandJointPoint(
                x: cx + dx * cosT + dy * sinT,
                y: cy - dx * sinT + dy * cosT,
                confidence: pt.confidence
            )
        }
        return HandPoseFrame(joints: rotated)
    }

    // MARK: - 正例

    @Test func waveTriggersOnSecondHorizontalReversalWithinWindow() {
        var classifier = HandGestureClassifier()
        let xs: [(TimeInterval, Float)] = [
            (0.00, 0.50),
            (0.10, 0.60), // 确立向右 (+1)
            (0.25, 0.46), // 翻转 1 (+1 -> -1)
            (0.40, 0.60), // 翻转 2 (-1 -> +1) -> 触发 wave
        ]

        var events: [GestureEvent] = []
        for (t, x) in xs {
            if let event = classifier.update(hands: [makeOpenPalm(wristX: x, wristY: 0.40)], at: t) {
                events.append(event)
            }
            if t < 0.40 {
                #expect(events.isEmpty, "1 次翻转前不应触发挥手，t=\(t)")
            }
        }

        #expect(events.count == 1)
        #expect(events.first?.kind == .wave)
        #expect((events.first?.confidence ?? 0) > 0.3)
        #expect(events.first?.timestamp == 0.40)
        #expect(classifier.latchedGesture == .wave)
    }

    @Test func waveTriggersWhenPivotingAtFixedWrist() {
        // 模拟真实对着镜头以手腕为轴左右扇动指尖（手腕坐标完全不动，仅手掌倾斜 ±28°）
        var classifier = HandGestureClassifier()
        let angle: Float = 28 * .pi / 180
        let sequence: [(TimeInterval, Float)] = [
            (0.00, 0),
            (0.12, angle),   // 确立向右
            (0.26, -angle),  // 翻转 1
            (0.40, angle),   // 翻转 2 -> 触发
        ]
        var triggered: GestureEvent?
        for (t, theta) in sequence {
            if let event = classifier.update(
                hands: [makeTiltedOpenPalm(wristX: 0.50, wristY: 0.40, tiltRadians: theta)],
                at: t
            ) {
                triggered = event
            }
        }
        #expect(triggered?.kind == .wave)
        #expect(triggered?.timestamp == 0.40)
    }

    @Test func waveDoesNotDeadlockAfterVerticalHandRepositioning() {
        // 回归：手先向右斜上抬起确立 direction=+1，随后降到较低高度水平挥手，绝不能被旧 anchor.y 永久卡死
        var classifier = HandGestureClassifier()
        let sequence: [(TimeInterval, Float, Float)] = [
            (0.00, 0.50, 0.55),
            (0.10, 0.62, 0.58), // 确立 +1，anchor = (0.62, 0.58)
            (0.22, 0.56, 0.28), // 手竖直下降 0.30 到新高度（应解锁旧 anchor.y）
            (0.34, 0.66, 0.28), // 在新高度向右
            (0.46, 0.50, 0.28), // 翻转 1
            (0.58, 0.66, 0.28), // 翻转 2 -> 触发 wave
        ]
        var triggered: GestureEvent?
        for (t, x, y) in sequence {
            if let event = classifier.update(hands: [makeOpenPalm(wristX: x, wristY: y)], at: t) {
                triggered = event
            }
        }
        #expect(triggered?.kind == .wave)
        #expect(triggered?.timestamp == 0.58)
    }

    @Test func waveTriggersWhenEndpointsTiltNearHorizontalButRejectsDownwardDroop() {
        // 左右端点大幅倾斜（±85° 时 ΔY≈0），不应被误判为掌0丢弃拐点
        var classifier = HandGestureClassifier()
        let bigTilt: Float = 85 * .pi / 180
        let seq: [(TimeInterval, Float)] = [
            (0.00, 0),
            (0.12, bigTilt),
            (0.24, -bigTilt),
            (0.36, bigTilt),
        ]
        var hit: GestureEvent?
        for (t, theta) in seq {
            if let e = classifier.update(hands: [makeTiltedOpenPalm(wristX: 0.50, wristY: 0.45, tiltRadians: theta)], at: t) {
                hit = e
            }
        }
        #expect(hit?.kind == .wave)

        // 自然朝下垂手（180°，ΔY < -palmScale）左右晃动绝不误触
        var droopClassifier = HandGestureClassifier()
        let droopXs: [(TimeInterval, Float)] = [
            (0.00, 0.50), (0.12, 0.65), (0.24, 0.45), (0.36, 0.65), (0.48, 0.45),
        ]
        for (t, x) in droopXs {
            #expect(droopClassifier.update(hands: [makeTiltedOpenPalm(wristX: x, wristY: 0.60, tiltRadians: .pi)], at: t) == nil)
        }
    }

    @Test func heartTriggersAtHalfSecondAcrossNearAndFarPalmScales() {
        for scale in [Float(0.24), Float(0.08)] {
            var classifier = HandGestureClassifier()
            let hands = makeHeartHands(scale: scale)

            #expect(classifier.update(hands: hands, at: 1.00) == nil)
            #expect(classifier.update(hands: hands, at: 1.25) == nil)
            #expect(classifier.update(hands: hands, at: 1.45) == nil)

            let triggered = classifier.update(hands: hands, at: 1.50)
            #expect(triggered?.kind == .heart)
            #expect((triggered?.confidence ?? 0) > 0.3)
            #expect(triggered?.timestamp == 1.50)
            #expect(classifier.latchedGesture == .heart)
        }
    }

    @Test func singleHandHeartTriggersForBothLeftAndRightHandsAndRejectsOKSign() {
        // 左右手单手比心均在 0.5 s 触发 .heart
        for mirrored in [false, true] {
            var classifier = HandGestureClassifier()
            let hand = [makeSingleHandHeart(mirrored: mirrored)]
            #expect(classifier.update(hands: hand, at: 0.00) == nil)
            #expect(classifier.update(hands: hand, at: 0.45) == nil)
            let event = classifier.update(hands: hand, at: 0.50)
            #expect(event?.kind == .heart)
            #expect((event?.confidence ?? 0) > 0.3)
            #expect(classifier.latchedGesture == .heart)
        }

        // OK 手势（拇指食指相触，但中指/无名指/小指伸直）绝不误触发比心
        var okClassifier = HandGestureClassifier()
        let okHand = [makeSingleHandHeart(lowerFingersExtended: true)]
        for i in 0..<12 {
            #expect(okClassifier.update(hands: okHand, at: Double(i) * 0.08) == nil)
        }

        // 食指末节向内微勾交叉（2D 透视下 indexTip 略低于 indexPIP）的真实韩式比心也应触发
        var hookedClassifier = HandGestureClassifier()
        let s: Float = 0.16
        let cx: Float = 0.50
        let cy: Float = 0.35
        let hooked = HandPoseFrame(joints: [
            .wrist: HandJointPoint(x: cx, y: cy, confidence: 0.9),
            .thumbCMC: HandJointPoint(x: cx - 0.25 * s, y: cy + 0.30 * s, confidence: 0.9),
            .thumbMP: HandJointPoint(x: cx - 0.30 * s, y: cy + 0.65 * s, confidence: 0.9),
            .thumbIP: HandJointPoint(x: cx - 0.12 * s, y: cy + 0.95 * s, confidence: 0.9),
            .thumbTip: HandJointPoint(x: cx + 0.08 * s, y: cy + 1.10 * s, confidence: 0.9),
            .indexMCP: HandJointPoint(x: cx - 0.15 * s, y: cy + 0.98 * s, confidence: 0.9),
            .indexPIP: HandJointPoint(x: cx - 0.05 * s, y: cy + 1.25 * s, confidence: 0.9),
            .indexDIP: HandJointPoint(x: cx - 0.08 * s, y: cy + 1.12 * s, confidence: 0.9),
            .indexTip: HandJointPoint(x: cx - 0.10 * s, y: cy + 1.02 * s, confidence: 0.9),
            .middleMCP: HandJointPoint(x: cx + 0.05 * s, y: cy + 1.00 * s, confidence: 0.9),
            .middlePIP: HandJointPoint(x: cx + 0.05 * s, y: cy + 1.15 * s, confidence: 0.9),
            .middleTip: HandJointPoint(x: cx + 0.05 * s, y: cy + 0.70 * s, confidence: 0.9),
            .ringMCP: HandJointPoint(x: cx + 0.25 * s, y: cy + 0.95 * s, confidence: 0.9),
            .ringPIP: HandJointPoint(x: cx + 0.25 * s, y: cy + 1.10 * s, confidence: 0.9),
            .ringTip: HandJointPoint(x: cx + 0.25 * s, y: cy + 0.68 * s, confidence: 0.9),
            .littleMCP: HandJointPoint(x: cx + 0.45 * s, y: cy + 0.90 * s, confidence: 0.9),
            .littlePIP: HandJointPoint(x: cx + 0.45 * s, y: cy + 1.05 * s, confidence: 0.9),
            .littleTip: HandJointPoint(x: cx + 0.45 * s, y: cy + 0.65 * s, confidence: 0.9),
        ])
        #expect(hookedClassifier.update(hands: [hooked], at: 0.00) == nil)
        #expect(hookedClassifier.update(hands: [hooked], at: 0.50)?.kind == .heart)

        // 真机透视回归：wrist->middleMCP 透视缩短至 0.06，但食指/拇指在手腕上方 +0.32 处交叉，应正常触发 .heart
        var foreshortenedClassifier = HandGestureClassifier()
        let foreshortened = HandPoseFrame(joints: [
            .wrist: HandJointPoint(x: 0.50, y: 0.30, confidence: 0.9),
            .thumbCMC: HandJointPoint(x: 0.46, y: 0.36, confidence: 0.9),
            .thumbMP: HandJointPoint(x: 0.45, y: 0.46, confidence: 0.9),
            .thumbIP: HandJointPoint(x: 0.50, y: 0.56, confidence: 0.9),
            .thumbTip: HandJointPoint(x: 0.56, y: 0.60, confidence: 0.9),
            .indexMCP: HandJointPoint(x: 0.48, y: 0.37, confidence: 0.9),
            .indexPIP: HandJointPoint(x: 0.52, y: 0.55, confidence: 0.9),
            .indexDIP: HandJointPoint(x: 0.56, y: 0.60, confidence: 0.9),
            .indexTip: HandJointPoint(x: 0.60, y: 0.62, confidence: 0.9),
            .middleMCP: HandJointPoint(x: 0.50, y: 0.36, confidence: 0.9), // palmScale = 0.06
            .middlePIP: HandJointPoint(x: 0.52, y: 0.42, confidence: 0.9),
            .middleTip: HandJointPoint(x: 0.51, y: 0.34, confidence: 0.9),
            .ringMCP: HandJointPoint(x: 0.53, y: 0.35, confidence: 0.9),
            .ringPIP: HandJointPoint(x: 0.55, y: 0.40, confidence: 0.9),
            .ringTip: HandJointPoint(x: 0.54, y: 0.33, confidence: 0.9),
            .littleMCP: HandJointPoint(x: 0.56, y: 0.34, confidence: 0.9),
            .littlePIP: HandJointPoint(x: 0.58, y: 0.38, confidence: 0.9),
            .littleTip: HandJointPoint(x: 0.57, y: 0.32, confidence: 0.9),
        ])
        #expect(foreshortenedClassifier.update(hands: [foreshortened], at: 0.00) == nil)
        #expect(foreshortenedClassifier.update(hands: [foreshortened], at: 0.50)?.kind == .heart)

        // 真实 Vision 实测采样坐标（X 交叉 + 顶部 V 字开口：tipDist/scale ≈ 0.82），左右手（原版 + 水平镜像）均须触发 .heart
        let realVisionRight = HandPoseFrame(joints: [
            .wrist: HandJointPoint(x: 0.581, y: 0.035, confidence: 0.644),
            .thumbCMC: HandJointPoint(x: 0.463, y: 0.164, confidence: 0.583),
            .thumbMP: HandJointPoint(x: 0.456, y: 0.326, confidence: 0.503),
            .thumbIP: HandJointPoint(x: 0.447, y: 0.498, confidence: 0.696),
            .thumbTip: HandJointPoint(x: 0.366, y: 0.653, confidence: 0.896),
            .indexMCP: HandJointPoint(x: 0.366, y: 0.179, confidence: 0.841),
            .indexPIP: HandJointPoint(x: 0.453, y: 0.436, confidence: 0.839),
            .indexDIP: HandJointPoint(x: 0.548, y: 0.540, confidence: 0.907),
            .indexTip: HandJointPoint(x: 0.634, y: 0.638, confidence: 0.913),
            .middleMCP: HandJointPoint(x: 0.533, y: 0.110, confidence: 0.832),
            .middlePIP: HandJointPoint(x: 0.596, y: 0.426, confidence: 0.846),
            .middleDIP: HandJointPoint(x: 0.578, y: 0.357, confidence: 0.583),
            .middleTip: HandJointPoint(x: 0.572, y: 0.282, confidence: 0.686),
            .ringMCP: HandJointPoint(x: 0.677, y: 0.092, confidence: 0.827),
            .ringPIP: HandJointPoint(x: 0.726, y: 0.393, confidence: 0.891),
            .ringDIP: HandJointPoint(x: 0.697, y: 0.325, confidence: 0.648),
            .ringTip: HandJointPoint(x: 0.681, y: 0.258, confidence: 0.573),
            .littleMCP: HandJointPoint(x: 0.815, y: 0.082, confidence: 0.816),
            .littlePIP: HandJointPoint(x: 0.832, y: 0.316, confidence: 0.870),
            .littleDIP: HandJointPoint(x: 0.813, y: 0.267, confidence: 0.632),
            .littleTip: HandJointPoint(x: 0.796, y: 0.212, confidence: 0.563),
        ])
        let realVisionLeft = HandPoseFrame(
            joints: realVisionRight.joints.mapValues { HandJointPoint(x: 1.0 - $0.x, y: $0.y, confidence: $0.confidence) }
        )
        for sample in [realVisionRight, realVisionLeft] {
            var realClassifier = HandGestureClassifier()
            #expect(realClassifier.update(hands: [sample], at: 0.00) == nil)
            #expect(realClassifier.update(hands: [sample], at: 0.50)?.kind == .heart)
        }

        // L 字手枪手势（拇指与食指未交叉且上段分开）绝不误触发单手比心
        var lSignClassifier = HandGestureClassifier()
        let lSign = HandPoseFrame(joints: [
            .wrist: HandJointPoint(x: 0.50, y: 0.20, confidence: 0.9),
            .thumbCMC: HandJointPoint(x: 0.42, y: 0.28, confidence: 0.9),
            .thumbMP: HandJointPoint(x: 0.34, y: 0.35, confidence: 0.9),
            .thumbIP: HandJointPoint(x: 0.24, y: 0.42, confidence: 0.9),
            .thumbTip: HandJointPoint(x: 0.14, y: 0.48, confidence: 0.9),
            .indexMCP: HandJointPoint(x: 0.48, y: 0.38, confidence: 0.9),
            .indexPIP: HandJointPoint(x: 0.50, y: 0.52, confidence: 0.9),
            .indexDIP: HandJointPoint(x: 0.52, y: 0.62, confidence: 0.9),
            .indexTip: HandJointPoint(x: 0.54, y: 0.72, confidence: 0.9),
            .middleMCP: HandJointPoint(x: 0.54, y: 0.36, confidence: 0.9),
            .middlePIP: HandJointPoint(x: 0.56, y: 0.42, confidence: 0.9),
            .middleTip: HandJointPoint(x: 0.55, y: 0.30, confidence: 0.9),
            .ringMCP: HandJointPoint(x: 0.60, y: 0.34, confidence: 0.9),
            .ringPIP: HandJointPoint(x: 0.62, y: 0.39, confidence: 0.9),
            .ringTip: HandJointPoint(x: 0.61, y: 0.28, confidence: 0.9),
            .littleMCP: HandJointPoint(x: 0.66, y: 0.32, confidence: 0.9),
            .littlePIP: HandJointPoint(x: 0.67, y: 0.36, confidence: 0.9),
            .littleTip: HandJointPoint(x: 0.66, y: 0.27, confidence: 0.9),
        ])
        for i in 0..<12 {
            #expect(lSignClassifier.update(hands: [lSign], at: Double(i) * 0.08) == nil)
        }

        // 泛化矩阵：对单手比心施加 ±35° 歪手旋转、0.5x/1.4x 大小手缩放、左右镜像、遮挡 thumbMP/无名指/小指，全部应稳定触发
        let wrist = realVisionRight.joints[.wrist]!
        for angleDeg in [Float(-35), Float(0), Float(35)] {
            let rad = angleDeg * .pi / 180
            let cosA = cos(rad)
            let sinA = sin(rad)
            for scaleFactor in [Float(0.55), Float(1.0), Float(1.35)] {
                var transformed: [HandJointName: HandJointPoint] = [:]
                for (name, pt) in realVisionRight.joints {
                    let dx = (pt.x - wrist.x) * scaleFactor
                    let dy = (pt.y - wrist.y) * scaleFactor
                    let rx = 0.50 + dx * cosA + dy * sinA
                    let ry = 0.25 - dx * sinA + dy * cosA
                    transformed[name] = HandJointPoint(x: rx, y: ry, confidence: pt.confidence)
                }
                var c = HandGestureClassifier()
                #expect(c.update(hands: [HandPoseFrame(joints: transformed)], at: 0.00) == nil)
                #expect(c.update(hands: [HandPoseFrame(joints: transformed)], at: 0.50)?.kind == .heart)
            }
        }

        // 遮挡回归：手背挡住 thumbMP 与无名指/小指，仅中指弯曲可见时仍应稳定触发
        var occludedJoints = realVisionRight.joints
        occludedJoints.removeValue(forKey: .thumbMP)
        occludedJoints.removeValue(forKey: .ringTip)
        occludedJoints.removeValue(forKey: .littleTip)
        var occludedClassifier = HandGestureClassifier()
        #expect(occludedClassifier.update(hands: [HandPoseFrame(joints: occludedJoints)], at: 0.00) == nil)
        #expect(occludedClassifier.update(hands: [HandPoseFrame(joints: occludedJoints)], at: 0.50)?.kind == .heart)

        // 反例：剪刀手（食指与中指伸直）绝不误触发单手比心
        var peaceJoints = realVisionRight.joints
        peaceJoints[.middlePIP] = HandJointPoint(x: 0.55, y: 0.36, confidence: 0.9)
        peaceJoints[.middleDIP] = HandJointPoint(x: 0.56, y: 0.50, confidence: 0.9)
        peaceJoints[.middleTip] = HandJointPoint(x: 0.57, y: 0.65, confidence: 0.9)
        var peaceClassifier = HandGestureClassifier()
        for i in 0..<12 {
            #expect(peaceClassifier.update(hands: [HandPoseFrame(joints: peaceJoints)], at: Double(i) * 0.08) == nil)
        }

        // 近距离手腕裁出画面底边（完全缺失 wrist）+ 中间连续 2 帧抖动丢帧（166 ms <= 220 ms），单手比心仍应稳定触发
        var noWristJoints = realVisionRight.joints
        noWristJoints.removeValue(forKey: .wrist)
        let noWristFrame = HandPoseFrame(joints: noWristJoints)
        var closeUpClassifier = HandGestureClassifier()
        #expect(closeUpClassifier.update(hands: [noWristFrame], at: 0.00) == nil)
        #expect(closeUpClassifier.update(hands: [noWristFrame], at: 0.083) == nil)
        #expect(closeUpClassifier.update(hands: [], at: 0.166) == nil)
        #expect(closeUpClassifier.update(hands: [], at: 0.249) == nil)
        #expect(closeUpClassifier.update(hands: [noWristFrame], at: 0.300) == nil)
        #expect(closeUpClassifier.update(hands: [noWristFrame], at: 0.500)?.kind == .heart)

        // 回归：当 thumbMP / thumbCMC / indexMCP 同时缺失导致根部回退共享 wrist 时，张开不交叉的 V 字手绝不误触发单手比心
        let sharedWristOpenV = HandPoseFrame(joints: [
            .wrist: HandJointPoint(x: 0.50, y: 0.20, confidence: 0.9),
            .middleMCP: HandJointPoint(x: 0.50, y: 0.36, confidence: 0.9),
            .middlePIP: HandJointPoint(x: 0.50, y: 0.39, confidence: 0.9),
            .middleTip: HandJointPoint(x: 0.50, y: 0.28, confidence: 0.9),
            .thumbIP: HandJointPoint(x: 0.44, y: 0.36, confidence: 0.9),
            .thumbTip: HandJointPoint(x: 0.40, y: 0.45, confidence: 0.9),
            .indexPIP: HandJointPoint(x: 0.54, y: 0.38, confidence: 0.9),
            .indexTip: HandJointPoint(x: 0.58, y: 0.46, confidence: 0.9),
        ])
        var sharedWristClassifier = HandGestureClassifier()
        for i in 0..<12 {
            #expect(sharedWristClassifier.update(hands: [sharedWristOpenV], at: Double(i) * 0.08) == nil)
        }
    }

    @Test func thumbsUpTriggersAtHalfSecondWithSingleFrameDropoutTolerance() {
        var classifier = HandGestureClassifier()
        let thumb = [makeThumbsUp()]

        #expect(classifier.update(hands: thumb, at: 0.00) == nil)
        #expect(classifier.update(hands: thumb, at: 0.16) == nil)
        // 插入 1 帧空手丢帧（83 ms <= 220 ms 容忍窗）
        #expect(classifier.update(hands: [], at: 0.243) == nil)
        #expect(classifier.update(hands: thumb, at: 0.33) == nil)
        #expect(classifier.update(hands: thumb, at: 0.45) == nil)

        let triggered = classifier.update(hands: thumb, at: 0.50)
        #expect(triggered?.kind == .thumbsUp)
        #expect((triggered?.confidence ?? 0) > 0.3)
        #expect(triggered?.timestamp == 0.50)
        #expect(classifier.latchedGesture == .thumbsUp)
    }

    // MARK: - 边界：P-3 边沿触发与释放重触发

    @Test func edgeTriggerLatchesAndRetriggersAfterReleaseForAllGestures() {
        // 1. heart
        do {
            var classifier = HandGestureClassifier()
            let heart = makeHeartHands()
            #expect(classifier.update(hands: heart, at: 0.00) == nil)
            #expect(classifier.update(hands: heart, at: 0.50)?.kind == .heart)
            // 继续保持 1.0 s 全部返回 nil
            for step in 1...10 {
                let t = 0.50 + Double(step) * 0.10
                #expect(classifier.update(hands: heart, at: t) == nil)
                #expect(classifier.latchedGesture == .heart)
            }
            // 收手满释放时长 0.25 s
            #expect(classifier.update(hands: [], at: 1.60) == nil)
            #expect(classifier.update(hands: [], at: 1.85) == nil)
            #expect(classifier.latchedGesture == nil)
            // 再次比心满 0.5 s 可重新触发第 2 次
            #expect(classifier.update(hands: heart, at: 2.00) == nil)
            #expect(classifier.update(hands: heart, at: 2.50)?.kind == .heart)
        }

        // 2. thumbsUp
        do {
            var classifier = HandGestureClassifier()
            let thumb = [makeThumbsUp()]
            #expect(classifier.update(hands: thumb, at: 0.00) == nil)
            #expect(classifier.update(hands: thumb, at: 0.50)?.kind == .thumbsUp)
            for step in 1...10 {
                #expect(classifier.update(hands: thumb, at: 0.50 + Double(step) * 0.10) == nil)
                #expect(classifier.latchedGesture == .thumbsUp)
            }
            #expect(classifier.update(hands: [], at: 1.60) == nil)
            #expect(classifier.update(hands: [], at: 1.85) == nil)
            #expect(classifier.latchedGesture == nil)
            #expect(classifier.update(hands: thumb, at: 2.00) == nil)
            #expect(classifier.update(hands: thumb, at: 2.50)?.kind == .thumbsUp)
        }

        // 3. wave
        do {
            var classifier = HandGestureClassifier()
            let firstWave: [(TimeInterval, Float)] = [
                (0.00, 0.50), (0.10, 0.62), (0.20, 0.45), (0.30, 0.62), (0.40, 0.45),
            ]
            var firstHit: GestureEvent?
            for (t, x) in firstWave {
                if let e = classifier.update(hands: [makeOpenPalm(wristX: x, wristY: 0.40)], at: t) {
                    firstHit = e
                }
            }
            #expect(firstHit?.kind == .wave)
            #expect(classifier.latchedGesture == .wave)

            // 持续继续挥手 1.0 s 内保持边沿锁存，不再重复触发
            let continuedWave: [(TimeInterval, Float)] = [
                (0.50, 0.62), (0.60, 0.45), (0.70, 0.62), (0.80, 0.45),
                (0.90, 0.62), (1.00, 0.45), (1.10, 0.62), (1.20, 0.45), (1.40, 0.62),
            ]
            for (t, x) in continuedWave {
                #expect(classifier.update(hands: [makeOpenPalm(wristX: x, wristY: 0.40)], at: t) == nil)
                #expect(classifier.latchedGesture == .wave)
            }

            // 收手静默满 0.45 s 释放锁存
            #expect(classifier.update(hands: [], at: 1.50) == nil)
            #expect(classifier.update(hands: [], at: 1.96) == nil)
            #expect(classifier.latchedGesture == nil)

            // 再次挥手可触发第 2 次
            let secondWave: [(TimeInterval, Float)] = [
                (2.10, 0.50), (2.20, 0.62), (2.30, 0.45), (2.40, 0.62), (2.50, 0.45),
            ]
            var secondHit: GestureEvent?
            for (t, x) in secondWave {
                if let e = classifier.update(hands: [makeOpenPalm(wristX: x, wristY: 0.40)], at: t) {
                    secondHit = e
                }
            }
            #expect(secondHit?.kind == .wave)
        }
    }

    // MARK: - 异常反例：负样本抗误触

    @Test func negativeSamplesProduceZeroFalseTriggers() {
        // 1. 竖直抬手（上下往复移动，无水平主导摆动）
        do {
            var classifier = HandGestureClassifier()
            let ys: [Float] = [0.20, 0.45, 0.22, 0.48, 0.20, 0.46, 0.24]
            for (i, y) in ys.enumerated() {
                let x: Float = 0.50 + (i % 2 == 0 ? 0.02 : -0.02)
                #expect(classifier.update(hands: [makeOpenPalm(wristX: x, wristY: y)], at: Double(i) * 0.12) == nil)
            }
        }

        // 2. 静止张手叠加 ±0.01 确定性抖动
        do {
            var classifier = HandGestureClassifier()
            let jitter: [Float] = [0.0, 0.01, -0.01, 0.008, -0.009, 0.01, -0.01, 0.005, -0.007, 0.009]
            for (i, dx) in jitter.enumerated() {
                #expect(classifier.update(hands: [makeOpenPalm(wristX: 0.50 + dx, wristY: 0.45)], at: Double(i) * 0.10) == nil)
            }
        }

        // 3. 摸脸（手向上移到面部附近停住并微小偏移，无水平来回）
        do {
            var classifier = HandGestureClassifier()
            let path: [(Float, Float)] = [
                (0.45, 0.20), (0.47, 0.38), (0.49, 0.55), (0.50, 0.62),
                (0.51, 0.61), (0.49, 0.62), (0.50, 0.60), (0.48, 0.58),
            ]
            for (i, pt) in path.enumerated() {
                #expect(classifier.update(hands: [makeOpenPalm(wristX: pt.0, wristY: pt.1)], at: Double(i) * 0.12) == nil)
            }
        }

        // 4. 单次左右晃手（仅 1 次翻转，不足 2 次）
        do {
            var classifier = HandGestureClassifier()
            let xs: [Float] = [0.50, 0.64, 0.46, 0.46, 0.46]
            for (i, x) in xs.enumerated() {
                #expect(classifier.update(hands: [makeOpenPalm(wristX: x, wristY: 0.40)], at: Double(i) * 0.12) == nil)
            }
        }

        // 5. 双手平合拍手（indexMCP 间距不大于 indexTip 间距，且食指/拇指未形成弧顶）
        do {
            var classifier = HandGestureClassifier()
            let clap = makeHeartHands(
                wristGapRatio: 0.80,
                indexTipGapRatio: 0.15,
                thumbTipGapRatio: 0.15,
                verticalSepRatio: 0.10,
                indexMCPGapRatio: 0.15
            )
            for i in 0..<12 {
                #expect(classifier.update(hands: clap, at: Double(i) * 0.08) == nil)
            }
        }

        // 6. 单手重复检出（两手观测手腕几乎重合，wristGapRatio = 0.05 < 0.60）
        do {
            var classifier = HandGestureClassifier()
            let duplicateHand = makeHeartHands(wristGapRatio: 0.05)
            for i in 0..<12 {
                #expect(classifier.update(hands: duplicateHand, at: Double(i) * 0.08) == nil)
            }
        }

        // 7. 大拇指朝下与水平
        for badAngle in [Float.pi, Float.pi / 2, -Float.pi / 2] {
            var classifier = HandGestureClassifier()
            let hand = [makeThumbsUp(thumbAngleFromUpRadians: badAngle)]
            for i in 0..<12 {
                #expect(classifier.update(hands: hand, at: Double(i) * 0.08) == nil)
            }
        }

        // 8. 平行双指（合法 verticalSepRatio，但 indexMCPGap <= indexTipGap，排除非弧顶收拢）
        do {
            var classifier = HandGestureClassifier()
            let parallelHands = makeHeartHands(
                wristGapRatio: 1.20,
                indexTipGapRatio: 0.30,
                thumbTipGapRatio: 0.30,
                verticalSepRatio: 0.60,
                indexMCPGapRatio: 0.30
            )
            for i in 0..<12 {
                #expect(classifier.update(hands: parallelHands, at: Double(i) * 0.08) == nil)
            }
        }

        // 9. 挥手翻转间隔拉长超过 1.5 s 滑动窗，旧翻转过期不累计触发
        do {
            var classifier = HandGestureClassifier()
            let slowWave: [(TimeInterval, Float)] = [
                (0.00, 0.50),
                (0.20, 0.65), // +1
                (0.40, 0.45), // 翻转 1 (t=0.40)
                (2.05, 0.65), // t=2.05 时 t=0.40 已过期（2.05 - 0.40 = 1.65 > 1.5），窗内仅 1 次翻转
            ]
            for (t, x) in slowWave {
                #expect(classifier.update(hands: [makeOpenPalm(wristX: x, wristY: 0.40)], at: t) == nil)
            }
        }
    }

    // MARK: - 异常反例：低置信度、超小手掌、非有限/回退时间戳与 reset

    @Test func invalidInputsAreIgnoredAndResetClearsState() {
        // 低置信度 (< 0.30)
        do {
            var classifier = HandGestureClassifier()
            let lowConf = [makeThumbsUp(confidence: 0.20)]
            for i in 0..<10 {
                #expect(classifier.update(hands: lowConf, at: Double(i) * 0.10) == nil)
            }
        }

        // 超小手掌 (< 0.03)
        do {
            var classifier = HandGestureClassifier()
            let tiny = [makeThumbsUp(scale: 0.02)]
            for i in 0..<10 {
                #expect(classifier.update(hands: tiny, at: Double(i) * 0.10) == nil)
            }
        }

        // NaN / 回退时间戳不破坏既有状态，reset 清零锁存与计时器
        do {
            var classifier = HandGestureClassifier()
            let thumb = [makeThumbsUp()]
            #expect(classifier.update(hands: thumb, at: 1.00) == nil)
            #expect(classifier.update(hands: thumb, at: .nan) == nil)
            #expect(classifier.update(hands: thumb, at: .infinity) == nil)
            #expect(classifier.update(hands: thumb, at: 0.50) == nil) // 严格回退
            #expect(classifier.update(hands: thumb, at: 1.50)?.kind == .thumbsUp)
            #expect(classifier.latchedGesture == .thumbsUp)

            classifier.reset()
            #expect(classifier.latchedGesture == nil)
            // reset 后从 0 开始计时，0.2 s 不应直接触发
            #expect(classifier.update(hands: thumb, at: 2.00) == nil)
            #expect(classifier.update(hands: thumb, at: 2.20) == nil)
            #expect(classifier.update(hands: thumb, at: 2.50)?.kind == .thumbsUp)
        }
    }

    // MARK: - ThermalGesturePolicy

    @Test func thermalGesturePolicyEffectiveRateMatchesSpec() {
        #expect(ThermalGesturePolicy.effectiveRate(configuredHz: 12, thermalState: .nominal) == 12)
        #expect(ThermalGesturePolicy.effectiveRate(configuredHz: 12, thermalState: .fair) == 12)
        #expect(ThermalGesturePolicy.effectiveRate(configuredHz: 12, thermalState: .serious) == 5)
        #expect(ThermalGesturePolicy.effectiveRate(configuredHz: 12, thermalState: .critical) == 0)
        #expect(ThermalGesturePolicy.effectiveRate(configuredHz: 3, thermalState: .serious) == 3)
        #expect(ThermalGesturePolicy.effectiveRate(configuredHz: 20, thermalState: .nominal) == 15)
        #expect(ThermalGesturePolicy.effectiveRate(configuredHz: .nan, thermalState: .nominal) == 0)
        #expect(ThermalGesturePolicy.effectiveRate(configuredHz: .infinity, thermalState: .nominal) == 0)
        #expect(ThermalGesturePolicy.effectiveRate(configuredHz: -5, thermalState: .nominal) == 0)
    }
}
