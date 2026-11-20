# Contract: AvatarRenderer 与形象素材

**Module**: `MMAvatar` | **Feature**: `002-m1-presence`

## 接口

```swift
@MainActor
public protocol AvatarRenderer {
    /// 加载形象素材，返回素材中实际可用的 blendShape 名称与动作名称。
    func load(named: String) async throws -> AvatarCapabilities
    /// 每帧调用。
    func apply(_ pose: AvatarPose)
}

public struct AvatarCapabilities: Sendable {
    public let blendShapeNames: Set<String>   // ARKit 命名
    public let actionNames: Set<String>       // 与 ActionTag.rawValue 对应
}
```

## 行为约定

| 编号 | 约定 |
|---|---|
| R-1 | `apply` 中出现素材不存在的 blendShape 名称时忽略，并在调试模式下记录一次警告 |
| R-2 | `action = .play(a)` 时从当前姿态平滑过渡到动作（200 ms），播完平滑回到待机（300 ms）；新动作到达时打断旧动作 |
| R-3 | 动作播放期间，面部 blendShape 仍按 `expressionWeights` 驱动 |
| R-4 | 头部旋转在动作播放期间叠加到动作的头部骨骼上，而不是覆盖 |
| R-5 | `apply` 的耗时 MUST < 2 ms（主线程预算） |

## 素材规范（USDZ）

| 项 | 要求 |
|---|---|
| 文件 | `App/MiniMate/Resources/Avatar/minimate.usdz` |
| blendShape | 必须包含 ARKit 52 个名称（如 `eyeBlinkLeft`、`jawOpen`、`mouthSmileLeft`……），大小写一致 |
| 动作 | 动画名称与 `ActionTag` 一致：`nod`、`wave`、`spin`、`heart`、`shyCover`、`leanBack`、`lookAround`、`notice`；每个 0.8–2.5 s |
| 骨骼 | 头部骨骼命名为 `Head`、颈部 `Neck`，用于视线跟随 |
| 面数 | 建议 < 50k 三角面；贴图 ≤ 2048² |
| 许可 | 来源与许可写在 `Assets/avatar/README.md` |

## 实现

| 实现 | 用途 |
|---|---|
| `RealityKitAvatarRenderer` | 真机与模拟器 |
| `RecordingAvatarRenderer` | 测试：记录收到的 `AvatarPose` 序列，用于断言 S-1 等不变式与 SC-004 的相关系数计算 |
