# Contract: 照片输出（快照、合成、写入相册）

**Module**: `MMPhoto`（`AvatarSnapshotter` 协议、`CornerPlacement`、`PhotoCompositor`、`PhotoLibraryWriter`）、`MMAvatar`（`AvatarFraming`、`AvatarOffscreenSnapshotter`）、App（`AvatarSnapshotAdapter`、`PhotoUIState`） | **Feature**: `005-voice-photo`（2026-11-26 按两轮外部评审修订）

## AvatarSnapshotter（MMPhoto 协议）

```swift
public protocol AvatarSnapshotter: Sendable {
    /// 以快门时刻的姿态渲染一张透明背景的形象图，主体紧贴边界裁切。
    func snapshot(pixelHeight: Int) async throws -> AvatarSnapshot
}
```

`MMAvatar` 提供 `AvatarOffscreenSnapshotter`（不依赖 `MMPhoto`，返回 `CGImage`），App 的 `AvatarSnapshotAdapter` 把它适配为本协议；R4 失败时适配器改用随包贴纸。

| 编号 | 约定 |
|---|---|
| AS-1 | 在 `capture` 副作用发出的同一时刻调用（与取帧并行），保证姿态是快门那一刻的 |
| AS-2 | 使用**影子克隆实体**：初始化时克隆形象实体放入离屏场景；快照时把在屏实体的骨骼 `jointTransforms`、`BlendShapeWeightsComponent` 与 `HeartEffect` 状态同步到影子实体再渲染。MUST NOT 把在屏实体移入离屏场景，MUST NOT 修改在屏相机，在屏帧率不受影响 |
| AS-3 | 离屏相机使用 `MMAvatar.AvatarFraming`（与 `AvatarScreen` 共用的视场角、相机位置与取景参数），保证构图与屏幕一致 |
| AS-4 | 500 ms 超时 → 抛错，调用方跳过合影版 |
| AS-5 | 兜底贴纸返回 `isLivePose = false` |

| 实现 | 所在 | 用途 |
|---|---|---|
| `AvatarOffscreenSnapshotter` + `AvatarSnapshotAdapter` | MMAvatar + App | 真机（依 R4） |
| `StickerAvatarSnapshotter` | App | D3 兜底 |
| `FakeAvatarSnapshotter` | MMPhoto/Fakes | 测试：返回带透明边的纯色测试图 |

## CornerPlacement（纯逻辑）

```swift
public enum CornerPlacement {
    public static func layout(faceRects: [CGRect], photoSize: CGSize, avatarAspect: Double) -> CompositeLayout
}
```

| 编号 | 约定 |
|---|---|
| CP-1 | 在照片像素坐标下计算：人脸框（归一化输入）先乘以 `photoSize` 转为像素，再各外扩 10% |
| CP-2 | 形象宽 = `photoSize.width × widthRatio`（0.30），高 = 形象宽 ÷ `avatarAspect`（宽 / 高）；边距 = `photoSize.width × 0.04`（水平与竖直相同像素值） |
| CP-3 | 候选顺序：`bottomRight` → `bottomLeft` → `topRight` → `topLeft`；取第一个与所有人脸都不重叠的角落 |
| CP-4 | 四角都重叠：`widthRatio = 0.20` 重新计算，选与全部人脸重叠面积之和最小的角，`overlapsFace = true` |
| CP-5 | `faceRects` 为空：`bottomRight` |
| CP-6 | 输出 `rect` 为像素坐标、左上原点 |

## PhotoCompositor

```swift
public struct PhotoCompositor: Sendable {
    public func composite(photo: CGImage, avatar: CGImage, layout: CompositeLayout) throws -> CGImage
    public func encode(_ image: CGImage, quality: Double = 0.9) throws -> EncodedImage
}
```

| 编号 | 约定 |
|---|---|
| PO-1 | 使用 CoreImage（共享 `CIContext`）；macOS 与 iOS 行为一致 |
| PO-2 | 只负责合成与编码；输入照片已是最终方向（photo-capture.md PC-4） |
| PO-3 | 合成保持原照片尺寸与色彩空间；形象按透明通道叠加（source-over）到 `layout.rect` |
| PO-4 | `encode` 优先 HEIC（`uti = .heic`）；失败时回退 JPEG（`uti = .jpeg`） |

## PhotoLibraryWriter

```swift
public protocol PhotoLibraryWriter: Sendable {
    func authorizationStatus() -> PhotoPermission
    func requestAuthorization() async -> PhotoPermission
    /// 一次事务写入：original 必写，composite 可为 nil。
    func save(original: EncodedImage, composite: EncodedImage?, creationDate: Date) async throws
}
```

| 编号 | 约定 |
|---|---|
| PL-1 | 只使用 `PHAccessLevel.addOnly` |
| PL-2 | 一次 `performChanges` 内创建两个 `PHAssetCreationRequest`，`addResource(with: .photo, data:, options:)` 的 `uniformTypeIdentifier` 取自 `EncodedImage.uti`；`creationDate` 相同；失败时两张都不写入 |
| PL-3 | 不读取相册、不建相簿 |
| PL-4 | 状态为 `notDetermined` 时由 Runner 在 `checkingPermission` 中调用 `requestAuthorization()`；授权弹窗导致的 `.inactive` 不算中断（RN-6） |

| 实现 | 用途 |
|---|---|
| `PhotosLibraryWriter`（MMPhoto，`#if os(iOS)`） | 真机 |
| `InMemoryLibraryWriter`（MMPhoto/Fakes） | 测试：记录写入内容与格式，可配置权限状态与失败 |

## 缩略图与大图

- 拍照流程的 `presenting` 只管缩略图：显示 `thumbnailDuration`（4 s）后发出 `hideThumbnail` 并结束流程。
- 点击缩略图打开的大图由 `PhotoUIState` 独立持有，不受 4 s 限制，也不阻塞下一次拍照指令以外的任何流程；大图打开期间若缩略图到时，缩略图照常消失。

## 图像生命周期

| 阶段 | 持有者 | 释放时机 |
|---|---|---|
| `CapturedPhoto.image`、`AvatarSnapshot.image` | Runner | 写入相册完成（或失败）后 |
| `PhotoSaveResult` | `PhotoUIState` | 缩略图已消失**且**大图已关闭 |
| `EncodedImage.data` | Runner 调用栈 | 写入完成后 |

任何阶段都不写入 App 沙盒文件（FR-017）。

## 测试要求

- `CornerPlacementTests`：CP-1–CP-6；竖屏（3:4、9:16）与横屏照片；四个象限的人脸、居中大脸、空数组、2–3 人（占满三个角、占满四个角）。
- `PhotoCompositorTests`：形象区域像素变化、其他区域不变；HEIC 可解码且尺寸一致；HEIC 失败时回退 JPEG 且 `uti` 正确。
- Runner 测试（Fakes）：快照超时 / 失败时只写原图；成功时两张同一事务写入且格式随数据传递；写入失败走 `saveFailed`。
