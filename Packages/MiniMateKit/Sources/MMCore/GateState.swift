/// 本地人声闸门判定阈值档位。
public enum GateThreshold: String, CaseIterable, Codable, Sendable {
    case normal
    case raised
    case playback
}

/// 本地收音闸门状态。仅 `.open` 允许向云端推送音频（audio-gating.md PV-1）。
public enum GateState: Sendable, Equatable {
    case muted
    case paused
    case closed(threshold: GateThreshold = .normal)
    case open(threshold: GateThreshold = .normal)

    /// 是否正在向云端上传音频。
    public var isUploading: Bool {
        if case .open = self { return true }
        return false
    }

    /// 当前生效的闸门阈值；`muted` 与 `paused` 下未监听，返回 `nil`。
    public var threshold: GateThreshold? {
        switch self {
        case .muted, .paused: nil
        case .closed(let threshold), .open(let threshold): threshold
        }
    }
}
