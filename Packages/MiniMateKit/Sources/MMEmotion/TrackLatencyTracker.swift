import Foundation
import simd

/// 测量 M_track：用户人脸位置显著变化 → 形象头部朝向跨越阈值的时间差（秒）。
public struct TrackLatencyTracker: Sendable, Equatable {
    private struct PendingStimulus: Sendable, Equatable {
        let timestamp: TimeInterval
        let baselineHeadRotation: SIMD3<Float>
    }

    public let positionDeltaThreshold: Float
    public let headRotationThreshold: Float
    public let timeout: TimeInterval

    private var lastObservedPosition: SIMD3<Float>?
    private var pendingStimulus: PendingStimulus?

    public init(
        positionDeltaThreshold: Float = 0.015,
        headRotationThreshold: Float = 0.5 * .pi / 180,
        timeout: TimeInterval = 1.0
    ) {
        self.positionDeltaThreshold = positionDeltaThreshold.isFinite ? max(positionDeltaThreshold, 1e-4) : 0.015
        self.headRotationThreshold = headRotationThreshold.isFinite ? max(headRotationThreshold, 1e-5) : 0.5 * .pi / 180
        self.timeout = timeout.isFinite ? max(timeout, 0.05) : 1.0
    }

    /// 在收到感知帧时调用；记录显著位移起点。
    public mutating func observeFacePosition(
        _ position: SIMD3<Float>?,
        currentHeadRotation: SIMD3<Float>,
        at timestamp: TimeInterval
    ) {
        guard timestamp.isFinite,
              let position,
              position.x.isFinite, position.y.isFinite, position.z.isFinite
        else {
            lastObservedPosition = nil
            pendingStimulus = nil
            return
        }

        if let prev = lastObservedPosition {
            // 仅统计横向/纵向 (x, y) 平面位移：前后 z 轴移动不驱动头部转向
            let delta = simd_distance(
                SIMD2<Float>(position.x, position.y),
                SIMD2<Float>(prev.x, prev.y)
            )
            if delta >= positionDeltaThreshold {
                lastObservedPosition = position
                // 仅在无未完成刺激或旧刺激已超时时创建新刺激，避免连续移动不断推迟起点
                if let existing = pendingStimulus, timestamp - existing.timestamp < timeout {
                    return
                }
                pendingStimulus = PendingStimulus(
                    timestamp: timestamp,
                    baselineHeadRotation: currentHeadRotation
                )
            }
        } else {
            lastObservedPosition = position
        }
    }

    /// 在渲染器应用姿态时调用；若满足响应条件返回单次 M_track 样本（秒），否则返回 nil。
    public mutating func observeAppliedHeadRotation(
        _ headRotation: SIMD3<Float>,
        at timestamp: TimeInterval
    ) -> TimeInterval? {
        guard timestamp.isFinite, let stimulus = pendingStimulus else {
            return nil
        }

        let latency = timestamp - stimulus.timestamp
        if latency < 0 || latency >= timeout {
            pendingStimulus = nil
            return nil
        }

        let diff = abs(headRotation - stimulus.baselineHeadRotation)
        let maxAxisDelta = max(diff.x, max(diff.y, diff.z))
        guard maxAxisDelta >= headRotationThreshold else {
            return nil
        }

        pendingStimulus = nil
        return latency
    }

    public mutating func reset() {
        lastObservedPosition = nil
        pendingStimulus = nil
    }
}
