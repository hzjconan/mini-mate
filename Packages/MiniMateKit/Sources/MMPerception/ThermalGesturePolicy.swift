import Foundation

/// 热状态驱动的手势采样频率上限策略（对应 plan.md 热降频与 contracts/perception-source.md P-4）。
public enum ThermalGesturePolicy: Sendable {
    /// 各热状态允许的最大手势检测频率（Hz）：
    /// - `.nominal` / `.fair` → `15.0`
    /// - `.serious` → `5.0`
    /// - `.critical` → `0.0`（暂停手势，保证人脸追踪优先）
    public static func maxRate(for state: ProcessInfo.ThermalState) -> Double {
        switch state {
        case .nominal, .fair:
            return 15.0
        case .serious:
            return 5.0
        case .critical:
            return 0.0
        @unknown default:
            return 5.0
        }
    }

    /// 结合外部配置频率（先夹紧至 `0...15`，非有限按 `0`）与当前热状态，返回实际生效频率（Hz）。
    public static func effectiveRate(
        configuredHz: Double,
        thermalState: ProcessInfo.ThermalState
    ) -> Double {
        guard configuredHz.isFinite, configuredHz > 0 else {
            return 0.0
        }
        let clamped = min(configuredHz, 15.0)
        return min(clamped, maxRate(for: thermalState))
    }
}
