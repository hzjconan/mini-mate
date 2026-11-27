/// 一段 App 主动播放的音频（拍照短句、预置短句）是否完整播完。供 `MMPhoto` 与 `004` 共用。
public enum PlaybackResult: String, CaseIterable, Codable, Sendable {
    case completed
    case stopped
}
