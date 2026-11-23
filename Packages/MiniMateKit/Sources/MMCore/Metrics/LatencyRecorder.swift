import Foundation

/// 按指标名收集时延样本，供真机验收时读取 p50 / p90 并导出 CSV。
public struct LatencyRecorder: Sendable {
    private var samplesByMetric: [String: [TimeInterval]] = [:]
    private var metricOrder: [String] = []

    public init() {}

    public mutating func record(_ seconds: TimeInterval, metric: String) {
        if samplesByMetric[metric] == nil {
            metricOrder.append(metric)
            samplesByMetric[metric] = []
        }
        samplesByMetric[metric]?.append(seconds)
    }

    public func count(for metric: String) -> Int {
        samplesByMetric[metric]?.count ?? 0
    }

    public func p50(for metric: String) -> TimeInterval? {
        percentile(0.5, for: metric)
    }

    public func p90(for metric: String) -> TimeInterval? {
        percentile(0.9, for: metric)
    }

    /// 最近秩法（nearest-rank）：升序样本中第 ⌈p × n⌉ 个值。
    public func percentile(_ p: Double, for metric: String) -> TimeInterval? {
        guard let sorted = samplesByMetric[metric]?.sorted(), !sorted.isEmpty else {
            return nil
        }
        let rank = Int((p * Double(sorted.count)).rounded(.up))
        let index = min(max(rank - 1, 0), sorted.count - 1)
        return sorted[index]
    }

    /// 每个指标一行：`metric,p50_ms,p90_ms,count`，按首次记录的先后排序。
    public func csv() -> String {
        var lines = ["metric,p50_ms,p90_ms,count"]
        for metric in metricOrder {
            guard let p50 = p50(for: metric), let p90 = p90(for: metric) else {
                continue
            }
            lines.append("\(escaped(metric)),\(millis(p50)),\(millis(p90)),\(count(for: metric))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func millis(_ seconds: TimeInterval) -> String {
        String(format: "%.1f", seconds * 1000)
    }

    private func escaped(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
