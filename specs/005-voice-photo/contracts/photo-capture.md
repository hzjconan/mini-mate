# Contract: PhotoCaptureSource 与 MouthActivitySource

**Module**: `MMPerception`（协议、值类型、纯逻辑工具、`ARKitPerceptionSource` 实现、Scripted 实现） | **Feature**: `005-voice-photo`（2026-11-26 按两轮外部评审修订）

协议与值类型放在 `MMPerception`，`MMPhoto` 依赖它们；`MMPerception` 不依赖 `MMPhoto`（plan.md"模块依赖"）。

## PhotoCaptureSource

```swift
public protocol PhotoCaptureSource: Sendable {
    /// 当前设备与配置下实际使用的取帧方式（research D1 运行时探测）。
    var captureMethod: CaptureMethod { get }
    /// 取景预览帧（镜像、竖屏、降采样）。只在被订阅期间转换，取消订阅即停止。
    func previewFrames(maxFPS: Double) -> AsyncStream<PreviewFrame>
    /// 取一张照片：竖屏、不镜像，附带照片中全部人脸框。
    func capture() async throws -> CapturedPhoto
}

public enum PhotoCaptureError: Error { case sessionNotRunning, captureFailed, timeout }
```

| 编号 | 约定 |
|---|---|
| PC-1 | 与感知共用同一个 `ARSession`；MUST NOT 创建 `AVCaptureSession`，MUST NOT 暂停或重新配置正在运行的 session（R2 若决定换视频格式，只在 `start()` 时生效） |
| PC-2 | 方式 A：`captureHighResolutionFrame`；方式 B：取调用之后到达的第一个 `ARFrame`，深拷贝 `capturedImage` 后立即释放该帧 |
| PC-3 | 超过 1 s 未返回 → `timeout`；方式 A 失败时自动用方式 B 重试一次，并在 `CapturedPhoto.method` 中如实标注 |
| PC-4 | 方向转换（竖屏、不镜像，research D7）在本实现内完成；预览帧为镜像 |
| PC-5 | 人脸框：在输出照片上运行 `VNDetectFaceRectanglesRequest`，得到全部人脸框（归一化、左上原点）；无人脸时为空数组 |
| PC-6 | 预览转换在独立队列上单飞行（上一帧未完成时丢弃新帧），不得阻塞 `sessionQueue` |
| PC-7 | 热状态 `serious` 及以上时预览帧率上限为 10 fps |
| PC-8 | session 中断（P-5）期间 `capture()` 抛出 `sessionNotRunning`，预览流不推送 |
| PC-9 | 不写文件、不访问网络；感知流 `features` 的行为不变 |

## MouthActivitySource

```swift
public protocol MouthActivitySource: Sendable {
    /// 订阅期间输出两路嘴部开合度（ARKit 通道、Vision 通道）；取消订阅即停止检测。
    func mouthActivity() -> AsyncStream<MouthActivityFrame>
}
```

| 编号 | 约定 |
|---|---|
| MA-1 | ARKit 通道：每个 `ARFrame`（约 60 Hz）输出被追踪那张脸的 `jawOpen − mouthClose`（夹紧到 0–1）；无追踪人脸时输出空 `faces` |
| MA-2 | Vision 通道：在 `gestureQueue` 上对 `capturedImage` 运行 `VNDetectFaceLandmarksRequest`，单飞行；默认 12 Hz，热状态 `serious` 起 8 Hz，`critical` 时关闭（只剩 ARKit 通道）；对每张脸用 `InnerLipOpenness` 计算开合比，用 `FaceTrackAssociator` 分配 `trackID` |
| MA-3 | 两路独立输出，不做 ARKit 与 Vision 人脸之间的匹配（research D11） |
| MA-4 | 调用方负责在订阅期间把手势检测频率设为 0（photo-flow.md PF-14）；本实现不修改手势频率 |
| MA-5 | 不保存图像、不访问网络；输出只有数值与人脸框 |
| MA-6 | Vision 通道的 `faces` 数量可作为"画面中人脸数"的兜底来源（research D12、R11） |

## 纯逻辑工具（可在 macOS 测试）

```swift
public struct FaceTrackAssociator: Sendable {
    public init(minIoU: Double = 0.3, maxMissedFrames: Int = 3)
    /// 按 IoU 最近邻把本帧人脸框匹配到已有 trackID；未匹配的分配新 ID；连续缺失超过上限的 track 被移除。
    public mutating func assign(_ rects: [CGRect]) -> [Int]
}

public enum InnerLipOpenness {
    /// 上下内唇中点距离 ÷ 嘴角宽度，按经验上限归一化到 0–1；关键点不足时返回 nil。
    public static func compute(innerLips: [CGPoint]) -> Float?
}
```

## 对 ARKitPerceptionSource 的改动

- `state`、`sessionQueue`、`gestureQueue` 由 `private` 改为 `internal`，以便 `ARKitPerceptionSource+PhotoCapture.swift`、`+MouthActivity.swift` 两个扩展文件使用；行为不变。
- `ARKitPerceptionSource` 同时实现 `PerceptionSource`、`PhotoCaptureSource`、`MouthActivitySource`。

## 对 002 perception-source.md 的修改（2026-11-26 已写入）

P-6 改为：

> P-6 | `features` 不访问网络，不保存图像。同一实现提供的 `PhotoCaptureSource`（005）仅在用户指令下取单帧，结果交给调用方，不在感知层保存；`MouthActivitySource`（005）只输出数值。

## 实现

| 实现 | 用途 |
|---|---|
| `ARKitPerceptionSource`（扩展） | 真机 |
| `ScriptedPhotoCaptureSource` | 测试与调试：返回固定测试图与指定人脸框，可配置延迟与失败 |
| `ScriptedMouthActivitySource` | 测试与调试：按脚本输出两路开合度序列 |

## 测试要求

- `FaceTrackAssociatorTests`：稳定跟踪、交叉移动、短暂缺失后恢复同一 ID、超过上限后分配新 ID。
- `InnerLipOpennessTests`：闭嘴、张嘴、关键点不足返回 nil、归一化上限。
