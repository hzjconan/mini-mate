import Foundation
import MMCore
import MMPerception

/// 把感知与对话事件转成形象自己的姿态。实现 MUST 可注入时钟与随机源以便确定性测试。
public protocol EmotionStateMachine: Sendable {
    func handle(_ features: PerceptionFeatures) async
    func handle(_ event: ConversationEvent) async

    /// 按时间求值：根据当前状态与时间返回插值后的姿态，渲染循环每帧调用。
    func pose(at time: TimeInterval) async -> AvatarPose

    /// 当前状态，供调试与测试读取。
    var state: AvatarState { get async }
}
