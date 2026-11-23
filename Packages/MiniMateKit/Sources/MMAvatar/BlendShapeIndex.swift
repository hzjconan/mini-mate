/// ARKit 名称 → 模型 blendShape 索引的映射。
///
/// 模型里的形态键顺序由素材决定，不可假设与 ARKit 一致；缺失项需要在
/// `research.md` 的 V10 结果里记录（缺失的形态键无法驱动）。
public struct BlendShapeIndex: Sendable {
    /// ARKit 规范的 52 个名称。调试面板的滑杆顺序也以此为准。
    public static let arkitNames: [String] = [
        "browDownLeft", "browDownRight", "browInnerUp", "browOuterUpLeft", "browOuterUpRight",
        "cheekPuff", "cheekSquintLeft", "cheekSquintRight",
        "eyeBlinkLeft", "eyeBlinkRight",
        "eyeLookDownLeft", "eyeLookDownRight",
        "eyeLookInLeft", "eyeLookInRight",
        "eyeLookOutLeft", "eyeLookOutRight",
        "eyeLookUpLeft", "eyeLookUpRight",
        "eyeSquintLeft", "eyeSquintRight",
        "eyeWideLeft", "eyeWideRight",
        "jawForward", "jawLeft", "jawOpen", "jawRight",
        "mouthClose", "mouthDimpleLeft", "mouthDimpleRight",
        "mouthFrownLeft", "mouthFrownRight", "mouthFunnel",
        "mouthLeft", "mouthLowerDownLeft", "mouthLowerDownRight",
        "mouthPressLeft", "mouthPressRight", "mouthPucker",
        "mouthRight", "mouthRollLower", "mouthRollUpper",
        "mouthShrugLower", "mouthShrugUpper",
        "mouthSmileLeft", "mouthSmileRight",
        "mouthStretchLeft", "mouthStretchRight",
        "mouthUpperUpLeft", "mouthUpperUpRight",
        "noseSneerLeft", "noseSneerRight",
        "tongueOut",
    ]

    private let indexByName: [String: Int]

    /// 素材中缺失的 ARKit 名称，按 `arkitNames` 顺序。
    public let missingNames: [String]

    /// - Parameter availableNames: 素材中的形态键名称，顺序即其索引。
    public init(availableNames: [String]) {
        var available: [String: Int] = [:]
        for (index, name) in availableNames.enumerated() where available[name] == nil {
            available[name] = index
        }
        indexByName = Self.arkitNames.reduce(into: [:]) { result, name in
            if let index = available[name] {
                result[name] = index
            }
        }
        missingNames = Self.arkitNames.filter { available[$0] == nil }
    }

    /// 非 ARKit 名称（包括素材多出来的）返回 `nil`。
    public func index(for arkitName: String) -> Int? {
        indexByName[arkitName]
    }
}
