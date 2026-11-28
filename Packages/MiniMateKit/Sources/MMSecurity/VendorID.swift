import Foundation

/// Cloud vendors whose API keys the user may configure (M2a 后按实际厂商增删).
public enum VendorID: String, CaseIterable, Codable, Sendable {
    case aliyun
    case volcengine
    case openai

    public var title: String {
        switch self {
        case .aliyun: "阿里云"
        case .volcengine: "火山引擎"
        case .openai: "OpenAI"
        }
    }
}
