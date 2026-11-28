/// 实时语音会话连接状态。
public enum ConnectionState: Sendable, Equatable {
    case connecting
    case connected
    case reconnecting(attempt: Int)
    case lost
}
