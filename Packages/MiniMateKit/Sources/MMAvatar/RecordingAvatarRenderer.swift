import MMCore
import MMEmotion

/// 测试用渲染器替身：完整记录收到的 `AvatarPose` 序列，用于 S-1 与 SC-004 自动化断言。
@MainActor
public final class RecordingAvatarRenderer: AvatarRenderer {
    public private(set) var loadedAssetNames: [String] = []
    public private(set) var poses: [AvatarPose] = []
    private let capabilities: AvatarCapabilities

    public init(
        capabilities: AvatarCapabilities = AvatarCapabilities(
            blendShapeNames: Set(BlendShapeIndex.arkitNames),
            actionNames: Set(ActionTag.allCases.map(\.rawValue))
        )
    ) {
        self.capabilities = capabilities
    }

    public func load(named name: String) async throws -> AvatarCapabilities {
        loadedAssetNames.append(name)
        return capabilities
    }

    public func apply(_ pose: AvatarPose) {
        poses.append(pose)
    }

    public func reset() {
        loadedAssetNames.removeAll()
        poses.removeAll()
    }
}
