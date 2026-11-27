import Darwin
import Foundation

/// 当前进程物理内存查询工具（与 Xcode Debug Navigator Memory Gauge 同源）。
public enum ProcessMemory: Sendable {
    /// 读取 `task_vm_info.phys_footprint`（字节）；失败返回 `nil`。
    public static func physicalFootprintBytes() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result: kern_return_t = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return nil
        }
        return UInt64(info.phys_footprint)
    }

    /// 读取 `task_vm_info.phys_footprint`（MiB，`1 MiB = 1_048_576 bytes`）；失败返回 `nil`。
    public static func physicalFootprintMB() -> Double? {
        physicalFootprintBytes().map { Double($0) / 1_048_576.0 }
    }
}

/// 平台无关的热状态档位（可比较、可序列化）。
public enum StabilityThermalLevel: String, CaseIterable, Sendable, Codable, Equatable, Comparable {
    case nominal
    case fair
    case serious
    case critical

    public init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal:
            self = .nominal
        case .fair:
            self = .fair
        case .serious:
            self = .serious
        case .critical:
            self = .critical
        @unknown default:
            self = .serious
        }
    }

    private var severity: Int {
        switch self {
        case .nominal: 0
        case .fair: 1
        case .serious: 2
        case .critical: 3
        }
    }

    public static func < (lhs: StabilityThermalLevel, rhs: StabilityThermalLevel) -> Bool {
        lhs.severity < rhs.severity
    }
}

/// 单个聚合采样点（默认每秒 1 条）。
public struct StabilitySample: Sendable, Equatable {
    public let elapsed: TimeInterval
    public let fps: Double
    public let memoryMB: Double
    public let thermalLevel: StabilityThermalLevel
    public let effectiveGestureRateHz: Double
    public let isFaceTracked: Bool

    public init(
        elapsed: TimeInterval,
        fps: Double,
        memoryMB: Double,
        thermalLevel: StabilityThermalLevel,
        effectiveGestureRateHz: Double,
        isFaceTracked: Bool
    ) {
        self.elapsed = elapsed
        self.fps = fps
        self.memoryMB = memoryMB
        self.thermalLevel = thermalLevel
        self.effectiveGestureRateHz = effectiveGestureRateHz
        self.isFaceTracked = isFaceTracked
    }
}

/// 热状态变迁事件（初始基线记录 `from == nil`）。
public struct ThermalTransition: Sendable, Equatable {
    public let elapsed: TimeInterval
    public let from: StabilityThermalLevel?
    public let to: StabilityThermalLevel

    public init(elapsed: TimeInterval, from: StabilityThermalLevel?, to: StabilityThermalLevel) {
        self.elapsed = elapsed
        self.from = from
        self.to = to
    }
}

/// SC-006 稳定性压测汇总报告。
public struct StabilityReport: Sendable, Equatable {
    public static let minRequiredFps: Double = 55.0
    public static let maxAllowedMemoryMB: Double = 1024.0

    public let targetDuration: TimeInterval
    public let duration: TimeInterval
    public let sampleCount: Int
    public let avgFps: Double
    public let p50Fps: Double
    public let p10Fps: Double
    public let minFps: Double
    public let avgMemoryMB: Double
    public let maxMemoryMB: Double
    public let peakThermalLevel: StabilityThermalLevel
    public let thermalTransitions: [ThermalTransition]
    public let thermalDurationSeconds: [StabilityThermalLevel: TimeInterval]
    public let sessionInterruptionCount: Int
    public let thermalSessionInterruptionCount: Int
    public let faceTrackedRatio: Double

    private let samples: [StabilitySample]

    init(
        targetDuration: TimeInterval,
        duration: TimeInterval,
        sampleCount: Int,
        avgFps: Double,
        p50Fps: Double,
        p10Fps: Double,
        minFps: Double,
        avgMemoryMB: Double,
        maxMemoryMB: Double,
        peakThermalLevel: StabilityThermalLevel,
        thermalTransitions: [ThermalTransition],
        thermalDurationSeconds: [StabilityThermalLevel: TimeInterval],
        sessionInterruptionCount: Int,
        thermalSessionInterruptionCount: Int,
        faceTrackedRatio: Double,
        samples: [StabilitySample]
    ) {
        self.targetDuration = targetDuration
        self.duration = duration
        self.sampleCount = sampleCount
        self.avgFps = avgFps
        self.p50Fps = p50Fps
        self.p10Fps = p10Fps
        self.minFps = minFps
        self.avgMemoryMB = avgMemoryMB
        self.maxMemoryMB = maxMemoryMB
        self.peakThermalLevel = peakThermalLevel
        self.thermalTransitions = thermalTransitions
        self.thermalDurationSeconds = thermalDurationSeconds
        self.sessionInterruptionCount = sessionInterruptionCount
        self.thermalSessionInterruptionCount = thermalSessionInterruptionCount
        self.faceTrackedRatio = faceTrackedRatio
        self.samples = samples
    }

    public static func == (lhs: StabilityReport, rhs: StabilityReport) -> Bool {
        lhs.targetDuration == rhs.targetDuration
            && lhs.duration == rhs.duration
            && lhs.sampleCount == rhs.sampleCount
            && lhs.avgFps == rhs.avgFps
            && lhs.p50Fps == rhs.p50Fps
            && lhs.p10Fps == rhs.p10Fps
            && lhs.minFps == rhs.minFps
            && lhs.avgMemoryMB == rhs.avgMemoryMB
            && lhs.maxMemoryMB == rhs.maxMemoryMB
            && lhs.peakThermalLevel == rhs.peakThermalLevel
            && lhs.thermalTransitions == rhs.thermalTransitions
            && lhs.thermalDurationSeconds == rhs.thermalDurationSeconds
            && lhs.sessionInterruptionCount == rhs.sessionInterruptionCount
            && lhs.thermalSessionInterruptionCount == rhs.thermalSessionInterruptionCount
            && lhs.faceTrackedRatio == rhs.faceTrackedRatio
    }

    public var passedDuration: Bool { duration + 1e-9 >= targetDuration }
    public var passedFps: Bool { sampleCount > 0 && avgFps >= Self.minRequiredFps && p10Fps >= Self.minRequiredFps }
    public var passedMemory: Bool { sampleCount > 0 && maxMemoryMB < Self.maxAllowedMemoryMB }
    public var passedThermalTracking: Bool { thermalSessionInterruptionCount == 0 }
    public var passed: Bool { passedDuration && passedFps && passedMemory && passedThermalTracking }

    /// 可直接粘贴至 `specs/002-m1-presence/research.md` 的 Markdown 汇总文本。
    public func summaryMarkdown() -> String {
        let verdict = passed ? "通过" : "未通过"
        let transitionText: String
        if thermalTransitions.isEmpty {
            transitionText = "无记录"
        } else {
            transitionText = thermalTransitions.map { item in
                let ts = String(format: "%.1fs", item.elapsed)
                if let from = item.from {
                    return "\(ts): \(from.rawValue) → \(item.to.rawValue)"
                } else {
                    return "\(ts): 初始 \(item.to.rawValue)"
                }
            }.joined(separator: "；")
        }

        let durationBreakdown = StabilityThermalLevel.allCases.compactMap { level -> String? in
            guard let sec = thermalDurationSeconds[level], sec > 0 else { return nil }
            return String(format: "%@ %.1fs", level.rawValue, sec)
        }.joined(separator: ", ")

        return """
        ### SC-006 稳定性压测报告

        - **判定**：\(verdict)（时长 \(passedDuration ? "✓" : "✗") · FPS \(passedFps ? "✓" : "✗") · 内存 \(passedMemory ? "✓" : "✗") · 热态追踪 \(passedThermalTracking ? "✓" : "✗")）
        - **时长 / 样本数**：\(String(format: "%.1f / %.0f s", duration, targetDuration))（\(sampleCount) 采样）
        - **FPS**：avg \(String(format: "%.2f", avgFps)) / p50 \(String(format: "%.2f", p50Fps)) / p10 \(String(format: "%.2f", p10Fps)) / min \(String(format: "%.2f", minFps))（门槛 ≥ \(String(format: "%.0f", Self.minRequiredFps))）
        - **物理内存（phys_footprint）**：avg \(String(format: "%.1f", avgMemoryMB)) MiB / max \(String(format: "%.1f", maxMemoryMB)) MiB（门槛 < \(String(format: "%.0f", Self.maxAllowedMemoryMB)) MiB）
        - **热状态峰值**：\(peakThermalLevel.rawValue)\(durationBreakdown.isEmpty ? "" : "（\(durationBreakdown)）")
        - **热状态变迁**：\(transitionText)
        - **ARSession 中断**：总计 \(sessionInterruptionCount) 次 / 热降频态（serious/critical）\(thermalSessionInterruptionCount) 次
        - **人脸追踪占比**：\(String(format: "%.1f%%", faceTrackedRatio * 100.0))
        """
    }

    /// 逐秒明细 CSV：`elapsed_s,fps,memory_mb,thermal_state,gesture_hz,face_tracked\n`。
    public func csv() -> String {
        var lines = ["elapsed_s,fps,memory_mb,thermal_state,gesture_hz,face_tracked"]
        lines.reserveCapacity(samples.count + 1)
        for sample in samples {
            let line = String(
                format: "%.2f,%.2f,%.2f,%@,%.1f,%@",
                sample.elapsed,
                sample.fps,
                sample.memoryMB,
                sample.thermalLevel.rawValue,
                sample.effectiveGestureRateHz,
                sample.isFaceTracked ? "true" : "false"
            )
            lines.append(line)
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

/// 纯逻辑 SC-006 稳定性采样聚合器（无时钟/UI 依赖，由调用方注入时间戳）。
public struct StabilitySessionRecorder: Sendable {
    public let targetDuration: TimeInterval
    public let sampleInterval: TimeInterval
    public let maxSamples: Int

    public private(set) var isRunning: Bool = false
    public private(set) var isPaused: Bool = false
    public private(set) var elapsed: TimeInterval = 0
    public private(set) var samples: [StabilitySample] = []
    public private(set) var thermalTransitions: [ThermalTransition] = []
    public private(set) var sessionInterruptionCount: Int = 0
    public private(set) var thermalSessionInterruptionCount: Int = 0
    public var latestSample: StabilitySample? { samples.last }

    private var thermalDurationSeconds: [StabilityThermalLevel: TimeInterval] = [:]
    private var lastThermalLevel: StabilityThermalLevel?
    private var windowStartAt: TimeInterval?
    private var lastFrameAt: TimeInterval?
    private var windowFrameCount: Int = 0

    public init(
        targetDuration: TimeInterval = 600.0,
        sampleInterval: TimeInterval = 1.0,
        maxSamples: Int = 3600
    ) {
        self.targetDuration = targetDuration.isFinite ? max(targetDuration, 1.0) : 600.0
        self.sampleInterval = sampleInterval.isFinite ? max(sampleInterval, 0.2) : 1.0
        self.maxSamples = max(maxSamples, 1)
    }

    public mutating func start(
        at timestamp: TimeInterval,
        initialThermalLevel: StabilityThermalLevel = .nominal
    ) {
        guard timestamp.isFinite else { return }
        reset()
        isRunning = true
        isPaused = false
        elapsed = 0
        lastThermalLevel = initialThermalLevel
        thermalTransitions = [ThermalTransition(elapsed: 0, from: nil, to: initialThermalLevel)]
    }

    /// 暂停采样计时（例如打开全屏调试面板时），丢弃当前未满窗口的局部帧计数，防止恢复后产生假 0 fps。
    public mutating func pause(at timestamp: TimeInterval) {
        guard isRunning, !isPaused, timestamp.isFinite else { return }
        isPaused = true
        windowStartAt = nil
        lastFrameAt = nil
        windowFrameCount = 0
    }

    /// 恢复采样计时，下一帧 `recordFrame` 重新锚定采样窗口起点。
    public mutating func resume(at timestamp: TimeInterval) {
        guard isRunning, isPaused, timestamp.isFinite else { return }
        isPaused = false
        windowStartAt = nil
        lastFrameAt = nil
        windowFrameCount = 0
    }

    /// 每帧渲染回调调用；仅在达到 `sampleInterval` 时调用一次 `memoryMBProvider` 并产出 `StabilitySample`。
    @discardableResult
    public mutating func recordFrame(
        at timestamp: TimeInterval,
        thermalLevel: StabilityThermalLevel,
        effectiveGestureRateHz: Double,
        isFaceTracked: Bool,
        memoryMBProvider: () -> Double?
    ) -> StabilitySample? {
        guard isRunning, !isPaused, timestamp.isFinite else {
            return nil
        }

        // 首次调用或刚 resume：仅锚定窗口起点，不调用 memoryMBProvider
        guard let windowStart = windowStartAt, let lastFrame = lastFrameAt else {
            windowStartAt = timestamp
            lastFrameAt = timestamp
            windowFrameCount = 0
            recordThermalTransitionIfNeeded(thermalLevel)
            return nil
        }

        // 忽略时间回退
        guard timestamp >= lastFrame else {
            return nil
        }

        let dt = timestamp - lastFrame
        elapsed += dt
        lastFrameAt = timestamp
        windowFrameCount += 1
        recordThermalTransitionIfNeeded(thermalLevel)

        let windowDuration = timestamp - windowStart
        guard windowDuration + 1e-9 >= sampleInterval else {
            return nil
        }

        let rawMem = memoryMBProvider() ?? 0.0
        let safeMemoryMB = (rawMem.isFinite && rawMem >= 0.0) ? rawMem : 0.0
        let safeGestureHz = (effectiveGestureRateHz.isFinite && effectiveGestureRateHz >= 0.0) ? effectiveGestureRateHz : 0.0
        let fps = Double(windowFrameCount) / windowDuration

        thermalDurationSeconds[thermalLevel, default: 0.0] += windowDuration

        let sample = StabilitySample(
            elapsed: elapsed,
            fps: fps,
            memoryMB: safeMemoryMB,
            thermalLevel: thermalLevel,
            effectiveGestureRateHz: safeGestureHz,
            isFaceTracked: isFaceTracked
        )
        if samples.count < maxSamples {
            samples.append(sample)
        }
        windowStartAt = timestamp
        windowFrameCount = 0
        return sample
    }

    /// 记录一次 `ARSession` 被系统中断的事件；若中断发生时 `thermalLevel >= .serious`，同时计入 `thermalSessionInterruptionCount`。
    public mutating func recordSessionInterruption(
        at timestamp: TimeInterval,
        thermalLevel: StabilityThermalLevel
    ) {
        guard isRunning, !isPaused, timestamp.isFinite else { return }
        recordThermalTransitionIfNeeded(thermalLevel)
        sessionInterruptionCount += 1
        if thermalLevel >= .serious {
            thermalSessionInterruptionCount += 1
        }
    }

    /// 生成当前实时快照报告（不改变运行状态）。
    public func makeReport() -> StabilityReport {
        guard !samples.isEmpty else {
            let peak = thermalTransitions.map(\.to).max() ?? lastThermalLevel ?? .nominal
            return StabilityReport(
                targetDuration: targetDuration,
                duration: elapsed,
                sampleCount: 0,
                avgFps: 0.0,
                p50Fps: 0.0,
                p10Fps: 0.0,
                minFps: 0.0,
                avgMemoryMB: 0.0,
                maxMemoryMB: 0.0,
                peakThermalLevel: peak,
                thermalTransitions: thermalTransitions,
                thermalDurationSeconds: thermalDurationSeconds,
                sessionInterruptionCount: sessionInterruptionCount,
                thermalSessionInterruptionCount: thermalSessionInterruptionCount,
                faceTrackedRatio: 0.0,
                samples: []
            )
        }

        let count = Double(samples.count)
        let fpsValues = samples.map(\.fps).sorted()
        let avgFps = fpsValues.reduce(0.0, +) / count
        let p50Fps = Self.nearestRankPercentile(0.50, sorted: fpsValues)
        let p10Fps = Self.nearestRankPercentile(0.10, sorted: fpsValues)
        let minFps = fpsValues.first ?? 0.0

        let memValues = samples.map(\.memoryMB)
        let avgMemoryMB = memValues.reduce(0.0, +) / count
        let maxMemoryMB = memValues.max() ?? 0.0

        let samplePeak = samples.map(\.thermalLevel).max() ?? .nominal
        let transitionPeak = thermalTransitions.map(\.to).max() ?? .nominal
        let peakThermalLevel = max(samplePeak, transitionPeak)

        let trackedCount = samples.reduce(into: 0) { acc, sample in
            if sample.isFaceTracked { acc += 1 }
        }
        let faceTrackedRatio = Double(trackedCount) / count

        return StabilityReport(
            targetDuration: targetDuration,
            duration: elapsed,
            sampleCount: samples.count,
            avgFps: avgFps,
            p50Fps: p50Fps,
            p10Fps: p10Fps,
            minFps: minFps,
            avgMemoryMB: avgMemoryMB,
            maxMemoryMB: maxMemoryMB,
            peakThermalLevel: peakThermalLevel,
            thermalTransitions: thermalTransitions,
            thermalDurationSeconds: thermalDurationSeconds,
            sessionInterruptionCount: sessionInterruptionCount,
            thermalSessionInterruptionCount: thermalSessionInterruptionCount,
            faceTrackedRatio: faceTrackedRatio,
            samples: samples
        )
    }

    /// 结束本次压测并返回最终报告。
    public mutating func finish() -> StabilityReport {
        isRunning = false
        isPaused = false
        windowStartAt = nil
        lastFrameAt = nil
        windowFrameCount = 0
        return makeReport()
    }

    /// 重置全部状态与已收集样本。
    public mutating func reset() {
        isRunning = false
        isPaused = false
        elapsed = 0
        samples.removeAll()
        thermalTransitions.removeAll()
        sessionInterruptionCount = 0
        thermalSessionInterruptionCount = 0
        thermalDurationSeconds.removeAll()
        lastThermalLevel = nil
        windowStartAt = nil
        lastFrameAt = nil
        windowFrameCount = 0
    }

    private mutating func recordThermalTransitionIfNeeded(_ thermalLevel: StabilityThermalLevel) {
        if let previous = lastThermalLevel {
            if thermalLevel != previous {
                thermalTransitions.append(ThermalTransition(elapsed: elapsed, from: previous, to: thermalLevel))
                lastThermalLevel = thermalLevel
            }
        } else {
            thermalTransitions.append(ThermalTransition(elapsed: elapsed, from: nil, to: thermalLevel))
            lastThermalLevel = thermalLevel
        }
    }

    private static func nearestRankPercentile(_ p: Double, sorted: [Double]) -> Double {
        guard !sorted.isEmpty else { return 0.0 }
        let rank = Int((p * Double(sorted.count)).rounded(.up))
        let index = min(max(rank - 1, 0), sorted.count - 1)
        return sorted[index]
    }
}
