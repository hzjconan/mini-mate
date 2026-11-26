# Contract: PerceptionSource

**Module**: `MMPerception` | **Feature**: `002-m1-presence`

## 接口

```swift
public protocol PerceptionSource: Sendable {
    /// 每帧感知结果，约 60 Hz。订阅者取消后应停止推送。
    var features: AsyncStream<PerceptionFeatures> { get }

    /// 开始感知。首次调用时请求摄像头权限。
    func start() async throws

    /// 停止感知并释放摄像头。
    func stop()

    /// 当前手势检测频率上限（热降频时由外部调低）。
    func setGestureRate(_ hz: Double)
}

public enum PerceptionError: Error {
    case cameraPermissionDenied
    case faceTrackingUnsupported
    case sessionInterrupted
}
```

## 行为约定

| 编号 | 约定 |
|---|---|
| P-1 | `features` 在 `start()` 成功后开始推送；人脸丢失时仍推送，`isFaceTracked = false` |
| P-2 | `rawBlendShapes` 仅供推导语义信号；下游 MUST NOT 把它写入 `AvatarPose` |
| P-3 | `gesture` 为边沿触发：同一次手势只推送一次，直到手势结束后才可再次触发 |
| P-4 | 手势检测频率默认 12 Hz，范围 0（关闭）– 15 Hz |
| P-5 | App 进入后台时 session 中断，恢复前台后自动恢复；中断期间不推送 |
| P-6 | `features` 不访问网络，不保存图像。同一实现提供的 `PhotoCaptureSource`（005）仅在用户指令下取单帧，结果交给调用方，不在感知层保存；`MouthActivitySource`（005）只输出数值 |

## 拍照与口型能力（005 增补）

`ARKitPerceptionSource` 同时实现 005 定义在 `MMPerception` 中的 `PhotoCaptureSource`（抓帧、取景预览、照片人脸框）与 `MouthActivitySource`（两路嘴部开合度），契约见 `specs/005-voice-photo/contracts/photo-capture.md`。约束：

- 与感知共用同一个 `ARSession`，不暂停、不重新配置运行中的 session，不创建 `AVCaptureSession`；`maximumNumberOfTrackedFaces` 保持 1。
- 口型检测（Vision 关键点）只在调用方订阅期间运行，调用方负责在此期间把手势检测频率设为 0。
- 为支持扩展文件，`state`、`sessionQueue`、`gestureQueue` 由 `private` 改为 `internal`，行为不变。

## 实现

| 实现 | 用途 |
|---|---|
| `ARKitPerceptionSource` | 真机（iOS only） |
| `ScriptedPerceptionSource` | 测试与调试：按脚本或录制文件回放 `PerceptionFeatures` 序列 |
| `ScriptedPhotoCaptureSource` / `ScriptedMouthActivitySource` | 005：测试与调试 |

`ScriptedPerceptionSource` 读取的录制格式为 JSON Lines，每行一个 `PerceptionFeatures`，由调试面板的"录制"按钮导出，用于离线调参与回归测试。
