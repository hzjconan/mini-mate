import Foundation
import simd

/// 1€ 低通平滑滤波器，静止时强抑抖动、快速运动时自动提高截止频率以降低滞后。
public struct OneEuroFilter: Sendable, Equatable {
    public let minCutoff: Double
    public let beta: Double
    public let dCutoff: Double

    private var xPrev: Double?
    private var dxPrev: Double = 0
    private var tPrev: TimeInterval?

    /// 无效参数夹紧而非崩溃：minCutoff/dCutoff 下限 1e-4，beta 下限 0；非有限值回退默认。
    public init(minCutoff: Double = 1.0, beta: Double = 0.0, dCutoff: Double = 1.0) {
        self.minCutoff = minCutoff.isFinite ? max(minCutoff, 1e-4) : 1.0
        self.beta = beta.isFinite ? max(beta, 0.0) : 0.0
        self.dCutoff = dCutoff.isFinite ? max(dCutoff, 1e-4) : 1.0
    }

    /// 输入新采样值与时间戳（秒），返回平滑后的值。
    public mutating func filter(_ value: Double, at timestamp: TimeInterval) -> Double {
        guard value.isFinite, timestamp.isFinite else {
            return xPrev ?? 0.0
        }
        guard let prevX = xPrev, let prevT = tPrev else {
            xPrev = value
            dxPrev = 0
            tPrev = timestamp
            return value
        }
        let dt = timestamp - prevT
        guard dt > 0 else {
            return prevX
        }

        let dx = (value - prevX) / dt
        let aD = Self.alpha(cutoff: dCutoff, dt: dt)
        let edx = Self.lerp(dxPrev, dx, aD)

        let cutoff = minCutoff + beta * abs(edx)
        let aX = Self.alpha(cutoff: cutoff, dt: dt)
        let xHat = Self.lerp(prevX, value, aX)

        xPrev = xHat
        dxPrev = edx
        tPrev = timestamp
        return xHat
    }

    /// 清空历史状态（如人脸丢失重获时调用）。
    public mutating func reset() {
        xPrev = nil
        dxPrev = 0
        tPrev = nil
    }

    private static func alpha(cutoff: Double, dt: Double) -> Double {
        let tau = 1.0 / (2.0 * .pi * cutoff)
        return 1.0 / (1.0 + tau / dt)
    }

    private static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }
}

/// 三轴 1€ 平滑封装，分别对 X/Y/Z 独立滤波。
public struct OneEuroFilter3D: Sendable, Equatable {
    private var filterX: OneEuroFilter
    private var filterY: OneEuroFilter
    private var filterZ: OneEuroFilter
    private var lastValid: SIMD3<Float>?

    public init(minCutoff: Double = 1.5, beta: Double = 0.4, dCutoff: Double = 1.0) {
        self.filterX = OneEuroFilter(minCutoff: minCutoff, beta: beta, dCutoff: dCutoff)
        self.filterY = OneEuroFilter(minCutoff: minCutoff, beta: beta, dCutoff: dCutoff)
        self.filterZ = OneEuroFilter(minCutoff: minCutoff, beta: beta, dCutoff: dCutoff)
    }

    public mutating func filter(_ value: SIMD3<Float>, at timestamp: TimeInterval) -> SIMD3<Float> {
        guard value.x.isFinite, value.y.isFinite, value.z.isFinite, timestamp.isFinite else {
            return lastValid ?? .zero
        }
        let x = Float(filterX.filter(Double(value.x), at: timestamp))
        let y = Float(filterY.filter(Double(value.y), at: timestamp))
        let z = Float(filterZ.filter(Double(value.z), at: timestamp))
        let result = SIMD3<Float>(x, y, z)
        lastValid = result
        return result
    }

    public mutating func reset() {
        filterX.reset()
        filterY.reset()
        filterZ.reset()
        lastValid = nil
    }
}
