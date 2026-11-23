/// 感知源：真机（ARKit）与脚本回放共用。
public protocol PerceptionSource: Sendable {
    /// 每帧感知结果，约 60 Hz；订阅者取消后停止推送。
    var features: AsyncStream<PerceptionFeatures> { get }

    /// 开始感知，首次调用时请求摄像头权限。
    func start() async throws

    /// 停止感知并释放摄像头。
    func stop()

    /// 设置手势检测频率上限（0 关闭，最高 15 Hz），用于热降频。
    func setGestureRate(_ hz: Double)
}

public enum PerceptionError: Error, Sendable {
    case cameraPermissionDenied
    case faceTrackingUnsupported
    case sessionInterrupted
}
