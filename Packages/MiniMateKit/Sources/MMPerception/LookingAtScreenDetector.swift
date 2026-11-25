import Foundation
import simd

/// 判断用户视线是否持续指向屏幕（默认夹角 < 20° 且持续 >= 200 ms）。
public struct LookingAtScreenDetector: Sendable, Equatable {
    public let maxAngleRadians: Float
    public let minDuration: TimeInterval
    public private(set) var isLookingAtScreen: Bool = false

    private var candidateStartedAt: TimeInterval?

    public init(maxAngleDegrees: Float = 20, minDuration: TimeInterval = 0.2) {
        let clampedDegrees = maxAngleDegrees.isFinite ? max(maxAngleDegrees, 0.1) : 20
        self.maxAngleRadians = clampedDegrees * .pi / 180
        self.minDuration = minDuration.isFinite ? max(minDuration, 0) : 0.2
    }

    /// 在 ARFaceAnchor 局部坐标系中计算视线与相机方向夹角（弧度 ∈ [0, π]）。
    /// 任一向量含非有限值或模长 < 1e-5 返回 nil。
    public static func gazeAngleRadians(
        lookAtPointInFaceSpace: SIMD3<Float>,
        cameraPositionInFaceSpace: SIMD3<Float>
    ) -> Float? {
        guard isFinite(lookAtPointInFaceSpace), isFinite(cameraPositionInFaceSpace) else {
            return nil
        }
        let lookLen = simd_length(lookAtPointInFaceSpace)
        let camLen = simd_length(cameraPositionInFaceSpace)
        guard lookLen >= 1e-5, camLen >= 1e-5 else {
            return nil
        }
        let cosValue = simd_dot(lookAtPointInFaceSpace, cameraPositionInFaceSpace) / (lookLen * camLen)
        let clamped = min(max(cosValue, -1.0), 1.0)
        return acos(clamped)
    }

    /// 更新状态并返回当前是否满足“持续看向屏幕”。
    public mutating func update(
        isFaceTracked: Bool,
        gazeAngleRadians: Float?,
        at timestamp: TimeInterval
    ) -> Bool {
        guard timestamp.isFinite,
              isFaceTracked,
              let angle = gazeAngleRadians,
              angle.isFinite,
              angle < maxAngleRadians
        else {
            candidateStartedAt = nil
            isLookingAtScreen = false
            return false
        }

        if let started = candidateStartedAt {
            if timestamp < started {
                candidateStartedAt = timestamp
                isLookingAtScreen = minDuration <= 0
            } else if timestamp - started + 1e-9 >= minDuration {
                isLookingAtScreen = true
            } else {
                isLookingAtScreen = false
            }
        } else {
            candidateStartedAt = timestamp
            isLookingAtScreen = minDuration <= 0
        }
        return isLookingAtScreen
    }

    public mutating func reset() {
        candidateStartedAt = nil
        isLookingAtScreen = false
    }

    private static func isFinite(_ v: SIMD3<Float>) -> Bool {
        v.x.isFinite && v.y.isFinite && v.z.isFinite
    }
}
