import Foundation
import Testing
@testable import MMCore
@testable import MMEmotion
@testable import MMAvatar

@Suite("ExpressionPreset")
struct ExpressionPresetTests {
    @Test func loadBundledContainsAll8EmotionsWithValidARKitKeys() throws {
        let presets = try ExpressionPreset.loadBundled()

        #expect(presets.count == EmotionTag.allCases.count)
        let validKeys = Set(BlendShapeIndex.arkitNames)

        for emotion in EmotionTag.allCases {
            let preset = try #require(presets[emotion])
            #expect(preset.emotion == emotion)
            #expect(preset.blendIn >= .zero)
            #expect(preset.blendOut >= .zero)
            for (key, value) in preset.weights {
                #expect(validKeys.contains(key), "非法形态键: \(key)")
                #expect(value.isFinite && value >= 0 && value <= 1, "越界权重: \(key)=\(value)")
            }
        }

        #expect(presets[.neutral]?.weights.isEmpty == true)
        #expect(presets[.happy]?.weights["mouthSmileLeft"] == 0.8)
        #expect(presets[.concerned]?.weights["browInnerUp"] == 0.85)
        #expect(presets[.concerned]?.weights["eyeSquintLeft"] == 0.3)
        #expect(presets[.concerned]?.weights["eyeBlinkLeft"] == 0.2)
        #expect(presets[.concerned]?.weights["mouthFrownLeft"] == 0.75)
        #expect(presets[.surprised]?.weights["eyeWideLeft"] == 0.9)
        #expect(presets[.surprised]?.weights["browOuterUpLeft"] == 0.66)
        #expect(presets[.surprised]?.weights["jawOpen"] == 0.65)

        // encodeJSON 往返与原字典逐字段相等
        let encoded = try ExpressionPreset.encodeJSON(presets)
        let decoded = try ExpressionPreset.load(from: encoded, requireAllEmotions: true)
        #expect(decoded == presets)

        // encodeSingleJSON 可正常解码为单条预设
        let happy = try #require(presets[.happy])
        let singleData = try ExpressionPreset.encodeSingleJSON(happy)
        let singleDecoded = try JSONDecoder().decode(ExpressionPreset.self, from: singleData)
        #expect(singleDecoded == happy)
    }

    @Test func loadRejectsDuplicateEmotion() {
        let json = """
        [
          {"emotion": "happy", "weights": {"mouthSmileLeft": 0.5}, "blendInMs": 200, "blendOutMs": 300},
          {"emotion": "happy", "weights": {"mouthSmileRight": 0.5}, "blendInMs": 200, "blendOutMs": 300}
        ]
        """
        #expect(throws: ExpressionPresetError.duplicateEmotion(.happy)) {
            try ExpressionPreset.load(from: Data(json.utf8))
        }
    }

    @Test func loadRejectsMissingEmotionsWhenRequired() {
        let json = """
        [
          {"emotion": "happy", "weights": {"mouthSmileLeft": 0.5}, "blendInMs": 200, "blendOutMs": 300}
        ]
        """
        let expectedMissing = EmotionTag.allCases.filter { $0 != .happy }
        #expect(throws: ExpressionPresetError.missingEmotions(expectedMissing)) {
            try ExpressionPreset.load(from: Data(json.utf8), requireAllEmotions: true)
        }
    }

    @Test func loadRejectsOutOfRangeWeights() {
        let overJson = """
        [
          {"emotion": "happy", "weights": {"mouthSmileLeft": 1.2}, "blendInMs": 200, "blendOutMs": 300}
        ]
        """
        #expect(throws: ExpressionPresetError.invalidWeight(emotion: .happy, name: "mouthSmileLeft", value: 1.2)) {
            try ExpressionPreset.load(from: Data(overJson.utf8))
        }

        let underJson = """
        [
          {"emotion": "sad", "weights": {"mouthFrownLeft": -0.1}, "blendInMs": 200, "blendOutMs": 300}
        ]
        """
        #expect(throws: ExpressionPresetError.invalidWeight(emotion: .sad, name: "mouthFrownLeft", value: -0.1)) {
            try ExpressionPreset.load(from: Data(underJson.utf8))
        }
    }
}
