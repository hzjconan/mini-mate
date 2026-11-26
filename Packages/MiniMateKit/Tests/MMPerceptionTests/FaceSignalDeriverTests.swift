import Foundation
import Testing
@testable import MMPerception

@Suite("FaceSignalDeriver")
struct FaceSignalDeriverTests {
    struct D5FormulaCase: Sendable {
        let label: String
        let blendShapes: [String: Float]
        let expectedSmile: Float
        let expectedFrown: Float
        let expectedSurprise: Float
    }

    @Test(arguments: [
        D5FormulaCase(
            label: "全零输入",
            blendShapes: [:],
            expectedSmile: 0,
            expectedFrown: 0,
            expectedSurprise: 0
        ),
        D5FormulaCase(
            label: "对称微笑",
            blendShapes: ["mouthSmileLeft": 0.8, "mouthSmileRight": 0.6],
            expectedSmile: 0.7,
            expectedFrown: 0,
            expectedSurprise: 0
        ),
        D5FormulaCase(
            label: "单侧皱眉取 max(browDownLeft, browDownRight)",
            blendShapes: [
                "browDownLeft": 0.9,
                "browDownRight": 0.1,
                "mouthFrownLeft": 0.5,
                "mouthFrownRight": 0.3,
            ],
            expectedSmile: 0,
            expectedFrown: 0.9 * 0.6 + 0.4 * 0.4,
            expectedSurprise: 0
        ),
        D5FormulaCase(
            label: "惊讶组合公式",
            blendShapes: [
                "browInnerUp": 0.8,
                "jawOpen": 0.5,
                "eyeWideLeft": 0.6,
                "eyeWideRight": 0.4,
            ],
            expectedSmile: 0,
            expectedFrown: 0,
            expectedSurprise: 0.8 * 0.5 + 0.5 * 0.3 + 0.5 * 0.2
        ),
        D5FormulaCase(
            label: "非法值与越界夹紧",
            blendShapes: [
                "mouthSmileLeft": 1.5,
                "mouthSmileRight": -0.4,
                "browDownLeft": .nan,
                "browDownRight": .infinity,
                "browInnerUp": 0.4,
            ],
            expectedSmile: 0.5,
            expectedFrown: 0,
            expectedSurprise: 0.2
        ),
    ])
    func d5RawFormulasMatchSpec(testCase: D5FormulaCase) {
        let raw = FaceSignalDeriver.rawSignals(from: testCase.blendShapes)
        #expect(abs(raw.smile - testCase.expectedSmile) < 1e-5, "\(testCase.label)")
        #expect(abs(raw.frown - testCase.expectedFrown) < 1e-5, "\(testCase.label)")
        #expect(abs(raw.surprise - testCase.expectedSurprise) < 1e-5, "\(testCase.label)")
    }

    @Test func smileRequires400msAndRespectsHysteresis() {
        var deriver = FaceSignalDeriver()
        let smileShapes: [String: Float] = ["mouthSmileLeft": 0.7, "mouthSmileRight": 0.7]

        // t = 0.0 启动候选，t = 0.399 未满 400 ms
        let s0 = deriver.update(blendShapes: smileShapes, at: 0.0)
        #expect(s0.activeExpression == nil)
        let s399 = deriver.update(blendShapes: smileShapes, at: 0.399)
        #expect(s399.activeExpression == nil)

        // t = 0.400 满 400 ms 激活 .smiling
        let s400 = deriver.update(blendShapes: smileShapes, at: 0.400)
        #expect(s400.activeExpression == .smiling)

        // 回落至滞回带 0.35（>= exit 0.30 且 < enter 0.50），多帧稳定后仍保持 .smiling
        let holdShapes: [String: Float] = ["mouthSmileLeft": 0.35, "mouthSmileRight": 0.35]
        var last = s400
        for step in 1...40 {
            last = deriver.update(blendShapes: holdShapes, at: 0.400 + Double(step) * 0.02)
        }
        #expect(last.smile >= 0.30 && last.smile < 0.50)
        #expect(last.activeExpression == .smiling)

        // 跌至 0.25（< exit 0.30），平滑收敛后退出
        let exitShapes: [String: Float] = ["mouthSmileLeft": 0.25, "mouthSmileRight": 0.25]
        for step in 1...40 {
            last = deriver.update(blendShapes: exitShapes, at: 1.200 + Double(step) * 0.02)
        }
        #expect(last.smile < 0.30)
        #expect(last.activeExpression == nil)
    }

    @Test func frownRequires500msAndSurpriseRequires300ms() {
        var frownDeriver = FaceSignalDeriver()
        let frownShapes: [String: Float] = [
            "browDownLeft": 0.8,
            "browDownRight": 0.8,
            "mouthFrownLeft": 0.6,
            "mouthFrownRight": 0.6,
        ]
        #expect(frownDeriver.update(blendShapes: frownShapes, at: 0.0).activeExpression == nil)
        #expect(frownDeriver.update(blendShapes: frownShapes, at: 0.499).activeExpression == nil)
        #expect(frownDeriver.update(blendShapes: frownShapes, at: 0.500).activeExpression == .frowning)

        var surpriseDeriver = FaceSignalDeriver()
        let surpriseShapes: [String: Float] = [
            "browInnerUp": 0.9,
            "jawOpen": 0.8,
            "eyeWideLeft": 0.8,
            "eyeWideRight": 0.8,
        ]
        #expect(surpriseDeriver.update(blendShapes: surpriseShapes, at: 0.0).activeExpression == nil)
        #expect(surpriseDeriver.update(blendShapes: surpriseShapes, at: 0.299).activeExpression == nil)
        #expect(surpriseDeriver.update(blendShapes: surpriseShapes, at: 0.300).activeExpression == .surprised)
    }

    @Test func briefDropResetsCandidateDurationTimer() {
        var deriver = FaceSignalDeriver()
        let smileShapes: [String: Float] = ["mouthSmileLeft": 0.8, "mouthSmileRight": 0.8]
        let neutralShapes: [String: Float] = ["mouthSmileLeft": 0.0, "mouthSmileRight": 0.0]

        _ = deriver.update(blendShapes: smileShapes, at: 0.0)
        _ = deriver.update(blendShapes: smileShapes, at: 0.25)

        // 中途连续跌破 enter 阈值，候选计时器清零
        var t = 0.26
        for _ in 0..<25 {
            _ = deriver.update(blendShapes: neutralShapes, at: t)
            t += 0.02
        }
        #expect(deriver.lastSignals.smile < 0.50)

        // 重新微笑后必须再持续完整 400 ms 才激活
        let restart = t
        var firstQualifiedTime: TimeInterval?
        for step in 0...60 {
            let now = restart + Double(step) * 0.015
            let signals = deriver.update(blendShapes: smileShapes, at: now)
            if signals.smile >= 0.50 && firstQualifiedTime == nil {
                firstQualifiedTime = now
            }
            if let start = firstQualifiedTime, now - start < 0.38 {
                #expect(signals.activeExpression == nil)
            }
        }
        #expect(deriver.lastSignals.activeExpression == .smiling)
    }

    @Test func hysteresisBandAllowsStrongerQualifiedExpressionTakeover() {
        var deriver = FaceSignalDeriver()
        let smileShapes: [String: Float] = ["mouthSmileLeft": 0.8, "mouthSmileRight": 0.8]

        _ = deriver.update(blendShapes: smileShapes, at: 0.0)
        let active = deriver.update(blendShapes: smileShapes, at: 0.45)
        #expect(active.activeExpression == .smiling)

        // 微笑回落至滞回带 [0.30, 0.50)，同时出现强烈惊讶并持续 >= 300 ms
        let mixedShapes: [String: Float] = [
            "mouthSmileLeft": 0.38,
            "mouthSmileRight": 0.38,
            "browInnerUp": 0.95,
            "jawOpen": 0.9,
            "eyeWideLeft": 0.9,
            "eyeWideRight": 0.9,
        ]
        var last = active
        for step in 1...40 {
            last = deriver.update(blendShapes: mixedShapes, at: 0.45 + Double(step) * 0.02)
        }
        #expect(last.activeExpression == .surprised)
    }

    @Test func invalidTimestampsAndResetAreSafe() {
        var deriver = FaceSignalDeriver()
        let smileShapes: [String: Float] = ["mouthSmileLeft": 0.85, "mouthSmileRight": 0.85]

        _ = deriver.update(blendShapes: smileShapes, at: 1.0)
        let active = deriver.update(blendShapes: smileShapes, at: 1.5)
        #expect(active.activeExpression == .smiling)

        // NaN / Inf 时间戳返回 lastSignals 且不污染内部状态
        let nanResult = deriver.update(blendShapes: ["mouthSmileLeft": .nan], at: .nan)
        #expect(nanResult == active)
        let infResult = deriver.update(blendShapes: [:], at: .infinity)
        #expect(infResult == active)

        // 非单调时间戳安全不崩溃且所有信号在 [0, 1]
        let backward = deriver.update(blendShapes: smileShapes, at: 0.5)
        #expect(backward.smile >= 0 && backward.smile <= 1)
        #expect(backward.frown >= 0 && backward.frown <= 1)
        #expect(backward.surprise >= 0 && backward.surprise <= 1)

        // reset 立即清空 activeExpression 与平滑状态
        deriver.reset()
        #expect(deriver.lastSignals == FaceSignals())
        let afterReset = deriver.update(blendShapes: smileShapes, at: 2.0)
        #expect(afterReset.activeExpression == nil)
    }

    @Test func thresholdConfigClampsInvalidValuesAndTieBreaksByPriority() {
        let clamped = FaceSignalDeriver.ThresholdConfig(enter: 0.4, exit: 0.9, minDuration: -1.0)
        #expect(clamped.enter == 0.4)
        #expect(clamped.exit == 0.4)
        #expect(clamped.minDuration == 0.0)

        let nanCfg = FaceSignalDeriver.ThresholdConfig(enter: .nan, exit: .infinity, minDuration: .nan)
        #expect(nanCfg.enter == 0.5)
        #expect(nanCfg.exit <= nanCfg.enter)
        #expect(nanCfg.minDuration >= 0)

        // 余量相等（全 1.0，避免 0.8 乘法 1-ULP 误差）时按 .surprised > .frowning > .smiling 裁决
        let tieConfig = FaceSignalDeriver.Config(
            smile: .init(enter: 0.5, exit: 0.3, minDuration: 0.0),
            frown: .init(enter: 0.5, exit: 0.3, minDuration: 0.0),
            surprise: .init(enter: 0.5, exit: 0.3, minDuration: 0.0)
        )
        var deriver = FaceSignalDeriver(config: tieConfig)
        let equalMarginShapes: [String: Float] = [
            "mouthSmileLeft": 1.0,
            "mouthSmileRight": 1.0,
            "browDownLeft": 1.0,
            "browDownRight": 1.0,
            "mouthFrownLeft": 1.0,
            "mouthFrownRight": 1.0,
            "browInnerUp": 1.0,
            "jawOpen": 1.0,
            "eyeWideLeft": 1.0,
            "eyeWideRight": 1.0,
        ]
        let signals = deriver.update(blendShapes: equalMarginShapes, at: 0.0)
        #expect(signals.activeExpression == .surprised)
    }

    @Test func legacyARKitRawSuffixKeysAlsoDeriveAllThreeSignals() {
        let legacyShapes: [String: Float] = [
            "mouthSmile_L": 0.8,
            "mouthSmile_R": 0.6,
            "browDown_L": 0.9,
            "browDown_R": 0.2,
            "mouthFrown_L": 0.5,
            "mouthFrown_R": 0.3,
            "browInnerUp": 0.8,
            "jawOpen": 0.5,
            "eyeWide_L": 0.6,
            "eyeWide_R": 0.4,
        ]
        let raw = FaceSignalDeriver.rawSignals(from: legacyShapes)
        #expect(abs(raw.smile - 0.7) < 1e-5)
        #expect(abs(raw.frown - (0.9 * 0.6 + 0.4 * 0.4)) < 1e-5)
        #expect(abs(raw.surprise - (0.8 * 0.5 + 0.5 * 0.3 + 0.5 * 0.2)) < 1e-5)
    }
}
