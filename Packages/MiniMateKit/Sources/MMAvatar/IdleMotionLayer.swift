import Foundation
import MMCore

/// 待机层的输出，始终叠加在其他表情之上。
public struct IdleMotion: Sendable, Equatable {
    /// 0–1，覆盖 `eyeBlinkLeft` / `eyeBlinkRight`。
    public let eyeBlink: Float
    /// 头部微动（弧度），叠加到头部旋转。
    public let headRotation: SIMD3<Float>

    public init(eyeBlink: Float = 0, headRotation: SIMD3<Float> = .zero) {
        self.eyeBlink = eyeBlink
        self.headRotation = headRotation
    }
}

/// 呼吸与眨眼。时间由调用方按帧传入，随机源可注入以便测试。
public struct IdleMotionLayer: Sendable {
    public struct Config: Sendable, Equatable {
        /// 相邻两次眨眼起始的间隔。
        public var blinkInterval: ClosedRange<TimeInterval>
        public var blinkDuration: TimeInterval
        public var breathPeriod: TimeInterval
        /// 呼吸引起的头部俯仰幅度（弧度）。
        public var breathAmplitude: Float

        public init(
            blinkInterval: ClosedRange<TimeInterval> = 2...6,
            blinkDuration: TimeInterval = 0.15,
            breathPeriod: TimeInterval = 4,
            breathAmplitude: Float = 0.035
        ) {
            self.blinkInterval = blinkInterval
            self.blinkDuration = blinkDuration
            self.breathPeriod = breathPeriod
            self.breathAmplitude = breathAmplitude
        }
    }

    public let config: Config
    private let clock: any Clock
    private let random: @Sendable () -> Double
    private var nextBlinkAt: TimeInterval?
    private var blinkStartedAt: TimeInterval?

    public init(
        config: Config = Config(),
        clock: any Clock = SystemClock(),
        random: @escaping @Sendable () -> Double = { Double.random(in: 0...1) }
    ) {
        self.config = config
        self.clock = clock
        self.random = random
    }

    /// 按当前时间求值。时间须单调递增。
    public mutating func update(at time: TimeInterval) -> IdleMotion {
        if nextBlinkAt == nil {
            nextBlinkAt = time + nextInterval()
        }

        var eyeBlink: Float = 0
        // 起跳点取计划时刻而非当前帧时刻，避免帧间隔稀疏时眨眼中段被跳过
        if blinkStartedAt == nil, let due = nextBlinkAt, time >= due {
            blinkStartedAt = due
        }
        if let startedAt = blinkStartedAt {
            let elapsed = time - startedAt
            if elapsed >= config.blinkDuration {
                blinkStartedAt = nil
                nextBlinkAt = startedAt + nextInterval()
            } else {
                let progress = elapsed / config.blinkDuration
                eyeBlink = Float(1 - abs(2 * progress - 1))
            }
        }

        let cycle = time.truncatingRemainder(dividingBy: config.breathPeriod) / config.breathPeriod
        let pitch = sin(Float(cycle) * 2 * .pi) * config.breathAmplitude

        return IdleMotion(eyeBlink: eyeBlink, headRotation: SIMD3(pitch, 0, 0))
    }

    /// 以注入时钟的当前时刻求值，供渲染循环使用。
    public mutating func updateNow() -> IdleMotion {
        update(at: clock.now.timeIntervalSinceReferenceDate)
    }

    private func nextInterval() -> TimeInterval {
        let unit = min(max(random(), 0), 1)
        return config.blinkInterval.lowerBound
            + (config.blinkInterval.upperBound - config.blinkInterval.lowerBound) * unit
    }
}
