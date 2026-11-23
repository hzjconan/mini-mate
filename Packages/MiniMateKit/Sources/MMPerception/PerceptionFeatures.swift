import Foundation

/// 每帧感知结果（约 60 Hz）。录制后按 JSON Lines 每行一条保存，供回放测试。
public struct PerceptionFeatures: Codable, Sendable, Equatable {
    public let timestamp: TimeInterval
    public let isFaceTracked: Bool
    /// 52 个 ARKit 原始系数，键为 ARKit 名称。只供 `FaceSignalDeriver` 使用，下游不得写入 `AvatarPose`。
    public let rawBlendShapes: [String: Float]
    public let signals: FaceSignals
    /// 用户脸在相机坐标系中的位置（米）。
    public let facePosition: SIMD3<Float>?
    public let isLookingAtScreen: Bool
    /// 本帧新识别出的手势，边沿触发。
    public let gesture: GestureEvent?

    public init(
        timestamp: TimeInterval,
        isFaceTracked: Bool,
        rawBlendShapes: [String: Float] = [:],
        signals: FaceSignals = FaceSignals(),
        facePosition: SIMD3<Float>? = nil,
        isLookingAtScreen: Bool = false,
        gesture: GestureEvent? = nil
    ) {
        self.timestamp = timestamp
        self.isFaceTracked = isFaceTracked
        self.rawBlendShapes = rawBlendShapes
        self.signals = signals
        self.facePosition = facePosition
        self.isLookingAtScreen = isLookingAtScreen
        self.gesture = gesture
    }
}

/// 平滑后的语义信号，取值 0–1。
public struct FaceSignals: Codable, Sendable, Equatable {
    public let smile: Float
    public let frown: Float
    public let surprise: Float
    /// 经阈值滞回与最短持续判定的当前表情。
    public let activeExpression: UserExpression?

    public init(
        smile: Float = 0,
        frown: Float = 0,
        surprise: Float = 0,
        activeExpression: UserExpression? = nil
    ) {
        self.smile = smile
        self.frown = frown
        self.surprise = surprise
        self.activeExpression = activeExpression
    }
}

public enum UserExpression: String, Codable, Sendable, CaseIterable {
    case smiling
    case frowning
    case surprised
}

public enum GestureKind: String, Codable, Sendable, CaseIterable {
    case wave
    case heart
    case thumbsUp
}

public struct GestureEvent: Codable, Sendable, Equatable {
    public let kind: GestureKind
    public let confidence: Float
    public let timestamp: TimeInterval

    public init(kind: GestureKind, confidence: Float, timestamp: TimeInterval) {
        self.kind = kind
        self.confidence = confidence
        self.timestamp = timestamp
    }
}
