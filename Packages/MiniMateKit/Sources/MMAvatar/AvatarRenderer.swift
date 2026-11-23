import MMEmotion

/// 素材中实际可用的 blendShape 与动作。
public struct AvatarCapabilities: Sendable {
    /// ARKit 名称。
    public let blendShapeNames: Set<String>
    /// 与 `ActionTag.rawValue` 对应。
    public let actionNames: Set<String>

    public init(blendShapeNames: Set<String>, actionNames: Set<String>) {
        self.blendShapeNames = blendShapeNames
        self.actionNames = actionNames
    }
}

@MainActor
public protocol AvatarRenderer {
    /// 加载形象素材，返回素材中实际可用的 blendShape 名称与动作名称。
    func load(named name: String) async throws -> AvatarCapabilities

    /// 每帧调用。
    func apply(_ pose: AvatarPose)
}
