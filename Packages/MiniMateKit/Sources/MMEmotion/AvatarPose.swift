import MMCore

/// 动作指令，边沿触发。
public enum ActionCommand: Sendable, Equatable {
    case play(ActionTag)
    case stop
}

/// 每帧送给渲染器的姿态。`expressionWeights` 只含形象自己的系数。
public struct AvatarPose: Sendable, Equatable {
    /// 键为 ARKit 名称，取值 0–1。
    public let expressionWeights: [String: Float]
    /// 欧拉角（弧度），限幅 ±25°。
    public let headRotation: SIMD3<Float>
    /// 归一化视线方向。
    public let eyeTarget: SIMD2<Float>
    public let action: ActionCommand?

    public init(
        expressionWeights: [String: Float] = [:],
        headRotation: SIMD3<Float> = .zero,
        eyeTarget: SIMD2<Float> = .zero,
        action: ActionCommand? = nil
    ) {
        self.expressionWeights = expressionWeights
        self.headRotation = headRotation
        self.eyeTarget = eyeTarget
        self.action = action
    }
}
