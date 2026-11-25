import Foundation
import MMCore

/// USDZ 随包的 `<asset>.actions.json`：8 个动作在同一条 `SkelAnimation` 时间线上的帧区间。
///
/// 时间线从第 1 帧开始，RealityKit 导入后把第 1 帧映射到 t=0，因此
/// `start = (startFrame - 1) / fps`、`duration = (endFrame - startFrame) / fps`。
struct ActionClipManifest: Decodable, Sendable {
    struct Clip: Decodable, Sendable, Equatable {
        let startFrame: Int
        let endFrame: Int
    }

    struct TimelineClip: Sendable, Equatable {
        let tag: ActionTag
        let start: TimeInterval
        let duration: TimeInterval
    }

    private let version: Int
    private let fps: Double
    private let totalFrames: Int?
    private let clips: [String: Clip]

    static let supportedVersion = 1

    static func decode(_ data: Data) throws -> ActionClipManifest {
        try JSONDecoder().decode(ActionClipManifest.self, from: data)
    }

    /// 按 `ActionTag.allCases` 顺序返回可用片段；位置或时长非法的片段会抛错。
    func timelineClips() throws -> [TimelineClip] {
        guard version == Self.supportedVersion else {
            throw ActionClipManifestError.unsupportedVersion(version)
        }
        guard fps.isFinite, fps > 0 else {
            throw ActionClipManifestError.invalidFPS(fps)
        }

        var result: [TimelineClip] = []
        for tag in ActionTag.allCases {
            guard let clip = clips[tag.rawValue] else { continue }
            guard clip.startFrame >= 1,
                  clip.endFrame > clip.startFrame,
                  totalFrames.map({ clip.endFrame <= $0 }) ?? true
            else {
                throw ActionClipManifestError.invalidClip(tag.rawValue)
            }
            result.append(
                TimelineClip(
                    tag: tag,
                    start: TimeInterval(clip.startFrame - 1) / fps,
                    duration: TimeInterval(clip.endFrame - clip.startFrame) / fps
                )
            )
        }
        return result
    }
}

enum ActionClipManifestError: Error, Equatable {
    case unsupportedVersion(Int)
    case invalidFPS(Double)
    case invalidClip(String)
}
