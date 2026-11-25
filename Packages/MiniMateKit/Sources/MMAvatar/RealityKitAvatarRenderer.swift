import Foundation
import RealityKit
import simd
import MMCore
import MMEmotion

/// 基于 RealityKit 的 `AvatarRenderer`：加载 USDZ 素材，驱动表情系数、动作与头部朝向。
///
/// 素材约定见 `specs/002-m1-presence/contracts/avatar-renderer.md`。
@MainActor
public final class RealityKitAvatarRenderer: AvatarRenderer {
    /// 挂到 RealityView 里的场景根节点；模型在 `load` 后成为其子节点。
    public let root = Entity()

    /// 每次加载后可用的能力；加载前为 `nil`。
    public private(set) var capabilities: AvatarCapabilities?

    /// 当前动作，供调试面板显示。
    public private(set) var playingAction: ActionTag?

    /// 动作播放倍速；调试面板可调到 0.25× 逐帧观察。
    public var playbackSpeed: Float = 1.0

    /// 调试预览：让动作在 RealityKit 内部循环，而不是每轮 stop/play。
    /// 后者在循环边界会出现一帧骨架叠加异常（真机可见），内部 repeat 没有边界。
    public var actionLooping = false

    /// 立即把速度套到正在播放的动作上（改变倍速时不必等下一轮）。
    public func setPlaybackSpeed(_ speed: Float) {
        playbackSpeed = speed
        playback?.controller.speed = speed
    }

    private let bundle: Bundle

    /// 单个 ARKit 名称在素材中的落点。
    private struct WeightTarget {
        let entity: Entity
        /// `BlendShapeWeightsSet` 中该组的 id；`nil` 表示默认组。
        let setID: String?
        let weightIndex: Int
    }

    private struct ActionEntry {
        let entity: Entity
        let resource: AnimationResource
    }

    private var weightTargets: [String: WeightTarget] = [:]
    private var lastWrittenWeights: [String: Float] = [:]
    private var actionEntries: [ActionTag: ActionEntry] = [:]
    private var loopingActionResources: [ActionTag: AnimationResource] = [:]
    private var playback: (tag: ActionTag, controller: AnimationPlaybackController)?
    private var warnedNames: Set<String> = []

    /// 本渲染器加载的模型；`reset` 只移除它，不动调用方挂在 `root` 上的灯光/相机目标。
    private var loadedModel: Entity?

    #if DEBUG
    /// 诊断开关：关闭待机头部叠加动画，用于区分动作数据与叠加层的相互影响。
    public var debugDisableHeadPose = false
    #endif

    /// 骨架里负责头部与脖子朝向的关节。VRM 导出为 `J_Bip_C_Neck` / `J_Bip_C_Head`，
    /// 直接写入 `ModelEntity.jointTransforms` 驱动，避免与动作 `SampledAnimation` 争抢动画层导致闪烁。
    private var neckJointIndex: Int?
    private var headJointIndex: Int?
    private var skeletonRestPoses: [Transform] = []
    private var skeletonModelEntity: ModelEntity?
    private var smoothedHeadRotation = SIMD3<Float>.zero
    private var lastWrittenHeadRotation = SIMD3<Float>.zero
    /// 动作结束后用柔和系数把头角从 rest pose 平滑过渡回当前目标的剩余帧数。
    private var headResumeFramesRemaining = 0

    /// `heart` 动作的爱心特效；锚点在加载后按模型包围盒计算。
    private var heartEffectEntity: Entity?
    private var heartEffectTask: Task<Void, Never>?
    private var heartEffectAnchor = SIMD3<Float>(0, 0.86, 0.2)
    private static let heartEffectSize: Float = 0.11

    private static let arkitNameSet = Set(BlendShapeIndex.arkitNames)
    private static let actionFadeIn: TimeInterval = 0.2
    /// 日常 60 Hz 头部追踪的指数平滑系数（约 2 帧达到 70%，低延迟且无抖动）。
    private static let headSmoothFactor: Float = 0.45
    /// 动作刚结束恢复头部追踪时的柔和指数平滑系数。
    private static let headResumeSmoothFactor: Float = 0.18
    /// 头部朝向变化小于该弧度时跳过写入 `jointTransforms`。
    private static let headWriteEpsilon: Float = 1e-4

    public init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    // MARK: - AvatarRenderer

    public func load(named name: String) async throws -> AvatarCapabilities {
        guard let url = assetURL(named: name) else {
            throw AvatarAssetError.notFound(name)
        }
        let model = try await Entity(contentsOf: url)

        reset()
        root.addChild(model)
        loadedModel = model
        updateHeartEffectAnchor(for: model)

        collectBlendShapes(in: model)
        if !installTimelineActions(forAssetNamed: name, in: model) {
            // 旧素材按动画名绑定；新素材走单条时间线 + actions.json。
            collectActions(in: model)
        }
        if actionEntries.isEmpty, firstSkeletalAnimation(in: model) != nil {
            warnMissingManifest()
        }
        findHeadJoint(in: model)

        let capabilities = AvatarCapabilities(
            blendShapeNames: Set(weightTargets.keys),
            actionNames: Set(actionEntries.keys.map(\.rawValue))
        )
        self.capabilities = capabilities
        return capabilities
    }

    public func apply(_ pose: AvatarPose) {
        applyExpressionWeights(pose.expressionWeights)
        updatePlayback()
        // 先处理动作再处理头部朝向：避免同一帧先播 headPose 又立刻切动作，
        // 留下正在交叉淡出的旧 headPose 与动作重叠导致闪烁。
        if pose.action == .stop {
            stopAction()
        } else if case .play(let tag)? = pose.action {
            play(tag)
        }
        applyHeadRotation(pose.headRotation)
    }

    // MARK: - 表情

    private func applyExpressionWeights(_ weights: [String: Float]) {
        var batches: [ObjectIdentifier: (entity: Entity, writes: [(WeightTarget, Float)])] = [:]

        for (name, rawValue) in weights {
            guard let target = weightTargets[name] else {
                warnMissing(name)
                continue
            }
            let value = min(max(rawValue, 0), 1)
            if let last = lastWrittenWeights[name], abs(last - value) < 0.001 {
                continue
            }
            lastWrittenWeights[name] = value
            batches[ObjectIdentifier(target.entity), default: (target.entity, [])]
                .writes.append((target, value))
        }

        // 兼容稀疏 AvatarPose：上帧非零但本帧省略的键自动写回 0
        for (name, lastValue) in lastWrittenWeights where weights[name] == nil && lastValue >= 0.001 {
            guard let target = weightTargets[name] else { continue }
            lastWrittenWeights[name] = 0
            batches[ObjectIdentifier(target.entity), default: (target.entity, [])]
                .writes.append((target, 0))
        }

        for (_, batch) in batches {
            write(batch.writes, to: batch.entity)
        }
    }

    private func write(_ writes: [(WeightTarget, Float)], to entity: Entity) {
        guard var component = entity.components[BlendShapeWeightsComponent.self] else { return }

        // 每帧只把变化过的系数写回；同一权重组只复制一次，避免逐个系数复制整个权重数组。
        var defaultWrites: [(index: Int, value: Float)] = []
        var grouped: [String: [(index: Int, value: Float)]] = [:]
        for (target, value) in writes {
            if let setID = target.setID {
                grouped[setID, default: []].append((target.weightIndex, value))
            } else {
                defaultWrites.append((target.weightIndex, value))
            }
        }

        if !defaultWrites.isEmpty, var data = component.weightSet.default {
            for item in defaultWrites {
                data.weights[item.index] = item.value
            }
            component.weightSet.default = data
        }
        for (setID, setWrites) in grouped {
            guard let setIndex = component.weightSet.index(of: setID) else { continue }
            var data = component.weightSet[setIndex]
            for item in setWrites {
                data.weights[item.index] = item.value
            }
            component.weightSet[setIndex] = data
        }

        entity.components[BlendShapeWeightsComponent.self] = component
    }

    private func collectBlendShapes(in entity: Entity) {
        if let component = entity.components[BlendShapeWeightsComponent.self] {
            let sets = Array(component.weightSet)
            for data in sets {
                // 只有一个权重组时按默认组处理；RealityKit 默认组的 id 可能是空串。
                let setID: String? = sets.count == 1 ? nil : data.id
                for (weightIndex, name) in data.weightNames.enumerated()
                where Self.arkitNameSet.contains(name) && weightTargets[name] == nil {
                    weightTargets[name] = WeightTarget(
                        entity: entity,
                        setID: setID,
                        weightIndex: weightIndex
                    )
                }
            }
        }
        for child in entity.children {
            collectBlendShapes(in: child)
        }
    }

    private func warnMissing(_ name: String) {
        guard warnedNames.insert(name).inserted else { return }
        #if DEBUG
        print("[MMAvatar] 素材缺少 blendShape：\(name)")
        #endif
    }

    // MARK: - 动作

    /// 从单条时间线裁出 8 个片段；素材没有清单或裁剪失败时返回 false，回退到按名称匹配。
    private func installTimelineActions(forAssetNamed name: String, in model: Entity) -> Bool {
        guard let manifestURL = actionManifestURL(forAssetNamed: name),
              let data = try? Data(contentsOf: manifestURL),
              let manifest = try? ActionClipManifest.decode(data),
              let clips = try? manifest.timelineClips(),
              !clips.isEmpty,
              let (host, resource) = firstSkeletalAnimation(in: model)
        else {
            return false
        }

        let definition = resource.definition
        for clip in clips {
            // 浮点误差可能让 end 略超定义时长；夹紧后再生成。
            let end = min(clip.start + clip.duration, definition.duration)
            guard end > clip.start else { continue }

            var trimmed = definition.trimmed(start: clip.start, end: end)
            trimmed.name = clip.tag.rawValue
            guard let trimmedResource = try? AnimationResource.generate(with: trimmed) else {
                warnMissingAction(clip.tag)
                continue
            }
            actionEntries[clip.tag] = ActionEntry(entity: host, resource: trimmedResource)
        }
        return !actionEntries.isEmpty
    }

    #if DEBUG
    /// 诊断：把某个动作停在中段，便于真机静态截图核对姿态。
    public func debugPoseAction(_ tag: ActionTag, at fraction: Double) {
        guard let entry = actionEntries[tag] else {
            print("[MMAvatar] 调试：没有动作 \(tag.rawValue)")
            return
        }
        playback?.controller.stop(blendOutDuration: 0)
        let controller = entry.entity.playAnimation(entry.resource, transitionDuration: 0)
        playback = (tag, controller)
        playingAction = tag
        let clamped = min(max(fraction, 0), 0.999)
        let seconds = entry.resource.definition.duration * clamped
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            controller.pause()
            print("[MMAvatar] 调试：\(tag.rawValue) 暂停在 \(seconds)s")
        }
    }

    /// 诊断：直接播放未经裁剪的整条时间线，用于判断问题出在胶片数据还是 trimmed。
    public func debugPlayFullTimeline() {
        guard let model = loadedModel,
              let (host, resource) = firstSkeletalAnimation(in: model)
        else { return }
        host.playAnimation(resource)
        print("[MMAvatar] 调试：播放完整时间线 duration=\(resource.definition.duration)")
    }
    #endif

    private func firstSkeletalAnimation(in entity: Entity) -> (Entity, AnimationResource)? {
        for resource in entity.availableAnimations {
            if resource.definition is SampledAnimation<JointTransforms> {
                return (entity, resource)
            }
        }
        if let library = entity.components[AnimationLibraryComponent.self] {
            for (_, resource) in library.animations {
                if resource.definition is SampledAnimation<JointTransforms> {
                    return (entity, resource)
                }
            }
        }
        for child in entity.children {
            if let found = firstSkeletalAnimation(in: child) {
                return found
            }
        }
        return nil
    }

    private func actionManifestURL(forAssetNamed name: String) -> URL? {
        let stem = (name as NSString).deletingPathExtension
        if let asset = assetURL(named: name) {
            let sibling = asset.deletingLastPathComponent()
                .appendingPathComponent("\(stem).actions.json")
            if FileManager.default.fileExists(atPath: sibling.path) {
                return sibling
            }
        }
        return bundle.url(forResource: "\(stem).actions", withExtension: "json")
            ?? bundle.url(forResource: "\(stem).actions", withExtension: "json", subdirectory: "Avatar")
    }

    private func warnMissingAction(_ tag: ActionTag) {
        #if DEBUG
        print("[MMAvatar] 无法从时间线裁剪动作：\(tag.rawValue)")
        #endif
    }

    private func warnMissingManifest() {
        #if DEBUG
        print("[MMAvatar] 素材是时间线动画，但缺少同级的 <asset>.actions.json，动作不可用")
        #endif
    }

    // MARK: - 爱心特效

    private func updateHeartEffectAnchor(for model: Entity) {
        let bounds = model.visualBounds(recursive: true, relativeTo: root)
        guard bounds.extents.y > 0 else { return }
        heartEffectAnchor = SIMD3<Float>(
            (bounds.min.x + bounds.max.x) / 2,
            bounds.min.y + bounds.extents.y * 0.565,
            bounds.max.z + 0.12
        )
    }

    private func startHeartEffect() {
        stopHeartEffect()
        let anchor = heartEffectAnchor
        let size = Self.heartEffectSize
        heartEffectTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(0.28))
                guard let self, !Task.isCancelled, self.playback?.tag == .heart else {
                    break
                }
                self.spawnHeartEffect(anchor: anchor, size: size)
                try? await Task.sleep(for: .seconds(1.02))
                self.removeHeartEffect()
                guard !Task.isCancelled, self.actionLooping else { break }
                // 预览循环时跟着动作一起反复冒爱心；正式一次性动作只冒一次。
                try? await Task.sleep(for: .seconds(0.2))
            }
        }
    }

    private func spawnHeartEffect(anchor: SIMD3<Float>, size: Float) {
        removeHeartEffect()
        guard let effect = HeartEffect.make(),
              let animation = HeartEffect.makeAnimation(anchor: anchor, size: size)
        else { return }
        // 先放到起始缩放，避免动画第一帧前在原点闪一下。
        effect.transform = Transform(
            scale: .init(repeating: 0.001),
            translation: anchor
        )
        root.addChild(effect)
        heartEffectEntity = effect
        effect.playAnimation(animation)
    }

    private func removeHeartEffect() {
        heartEffectEntity?.removeFromParent()
        heartEffectEntity = nil
    }

    private func stopHeartEffect() {
        heartEffectTask?.cancel()
        heartEffectTask = nil
        removeHeartEffect()
    }

    private func collectActions(in entity: Entity) {
        if let library = entity.components[AnimationLibraryComponent.self] {
            for (key, resource) in library.animations {
                guard !(resource.definition is SampledAnimation<BlendShapeWeights>) else { continue }
                guard let tag = AnimationNameMatcher.tag(for: key), actionEntries[tag] == nil else { continue }
                actionEntries[tag] = ActionEntry(entity: entity, resource: resource)
            }
        }
        for resource in entity.availableAnimations {
            // 形态键动画与关节动画同名；只取关节动画，避免动作播放变成空动画。
            guard !(resource.definition is SampledAnimation<BlendShapeWeights>) else { continue }
            guard let name = resource.name,
                  let tag = AnimationNameMatcher.tag(for: name),
                  actionEntries[tag] == nil
            else { continue }
            actionEntries[tag] = ActionEntry(entity: entity, resource: resource)
        }
        for child in entity.children {
            collectActions(in: child)
        }
    }

    private func play(_ tag: ActionTag) {
        guard let entry = actionEntries[tag] else { return }
        if let current = playback, current.tag == tag, !current.controller.isComplete {
            return
        }
        // 从无动作状态（直接写 jointTransforms）切入动作时，动作首帧本就是 rest pose，
        // 使用 transitionDuration: 0 直接启动，避免 RealityKit 从静态骨架淡入 SampledAnimation 出现闪烁；
        // 若是打断正在播放的另一个动作（同为 SampledAnimation），再用 actionFadeIn 平滑过渡。
        let transition: TimeInterval = (playback != nil) ? Self.actionFadeIn : 0
        smoothedHeadRotation = .zero
        lastWrittenHeadRotation = .zero
        headResumeFramesRemaining = 0

        let controller = entry.entity.playAnimation(
            playbackResource(for: tag, entry: entry),
            transitionDuration: transition,
            blendLayerOffset: 0,
            handoffType: .replace()
        )
        controller.speed = playbackSpeed
        playback = (tag, controller)
        playingAction = tag
        if tag == .heart {
            startHeartEffect()
        } else {
            stopHeartEffect()
        }
    }

    /// 循环预览时返回 RealityKit 内部的 repeat 资源；其它情况返回一次性片段。
    private func playbackResource(for tag: ActionTag, entry: ActionEntry) -> AnimationResource {
        guard actionLooping else { return entry.resource }
        if let cached = loopingActionResources[tag] {
            return cached
        }
        guard let generated = try? AnimationResource.generate(
            with: entry.resource.definition.repeatingForever()
        ) else {
            return entry.resource
        }
        loopingActionResources[tag] = generated
        return generated
    }

    private func updatePlayback() {
        guard let current = playback, current.controller.isComplete else { return }
        // 动作末帧就是静置姿态，直接停掉即可。
        current.controller.stop(blendOutDuration: 0)
        playback = nil
        playingAction = nil
        smoothedHeadRotation = .zero
        lastWrittenHeadRotation = .zero
        headResumeFramesRemaining = 12
        if let modelEntity = skeletonModelEntity, !skeletonRestPoses.isEmpty {
            modelEntity.jointTransforms = skeletonRestPoses
        }
        stopHeartEffect()
    }

    private func stopAction() {
        guard let current = playback else { return }
        current.controller.stop(blendOutDuration: 0)
        playback = nil
        playingAction = nil
        smoothedHeadRotation = .zero
        lastWrittenHeadRotation = .zero
        headResumeFramesRemaining = 12
        if let modelEntity = skeletonModelEntity, !skeletonRestPoses.isEmpty {
            modelEntity.jointTransforms = skeletonRestPoses
        }
        stopHeartEffect()
    }

    // MARK: - 头部朝向

    private func findHeadJoint(in entity: Entity) {
        guard let modelEntity = entity as? ModelEntity,
              let mesh = modelEntity.components[ModelComponent.self]?.mesh
        else {
            for child in entity.children { findHeadJoint(in: child) }
            return
        }
        for skeleton in mesh.contents.skeletons {
            let names = skeleton.joints.map(\.name)
            if let index = names.firstIndex(where: { isHeadJointName($0) }) {
                headJointIndex = index
                neckJointIndex = names.firstIndex(where: { isNeckJointName($0) })
                skeletonRestPoses = skeleton.joints.map(\.restPoseTransform)
                skeletonModelEntity = modelEntity
                #if DEBUG
                print("[MMAvatar] head joint index=\(index) name=\(names[index]) neck=\(neckJointIndex.map { names[$0] } ?? "none") joints=\(names.count)")
                #endif
                return
            }
        }
        for child in entity.children { findHeadJoint(in: child) }
    }

    private func isHeadJointName(_ name: String) -> Bool {
        name == "Head" || name.hasSuffix("_Head") || name.hasSuffix(".Head")
    }

    private func isNeckJointName(_ name: String) -> Bool {
        name == "Neck" || name.hasSuffix("_Neck") || name.hasSuffix(".Neck")
    }

    /// 待机与视线追踪期间直接通过 `ModelEntity.jointTransforms` 驱动头部与脖子朝向。
    ///
    /// 不再使用 `FromToByAnimation` 占用 RealityKit 动画层，彻底避免与动作 `SampledAnimation`
    /// 切换时的跨类型混合闪烁，也消除了 60 Hz 反复生成 `AnimationResource` 的开销。
    private func applyHeadRotation(_ euler: SIMD3<Float>) {
        #if DEBUG
        if debugDisableHeadPose { return }
        #endif
        guard playback == nil else { return }
        guard let modelEntity = skeletonModelEntity,
              let index = headJointIndex,
              !skeletonRestPoses.isEmpty
        else { return }

        let alpha: Float
        if headResumeFramesRemaining > 0 {
            headResumeFramesRemaining -= 1
            alpha = Self.headResumeSmoothFactor
        } else {
            alpha = Self.headSmoothFactor
        }
        smoothedHeadRotation += (euler - smoothedHeadRotation) * alpha
        if simd_length(euler - smoothedHeadRotation) < Self.headWriteEpsilon {
            smoothedHeadRotation = euler
        }
        guard simd_length(smoothedHeadRotation - lastWrittenHeadRotation) >= Self.headWriteEpsilon else { return }
        lastWrittenHeadRotation = smoothedHeadRotation

        var transforms = skeletonRestPoses
        if smoothedHeadRotation != .zero {
            if let neckIndex = neckJointIndex {
                let neckEuler = smoothedHeadRotation * 0.35
                let headEuler = smoothedHeadRotation * 0.65
                transforms[neckIndex].rotation = skeletonRestPoses[neckIndex].rotation * Self.rotationQuat(from: neckEuler)
                transforms[index].rotation = skeletonRestPoses[index].rotation * Self.rotationQuat(from: headEuler)
            } else {
                transforms[index].rotation = skeletonRestPoses[index].rotation * Self.rotationQuat(from: smoothedHeadRotation)
            }
        }
        modelEntity.jointTransforms = transforms
    }

    private static func rotationQuat(from euler: SIMD3<Float>) -> simd_quatf {
        simd_quatf(angle: euler.y, axis: [0, 1, 0])
            * simd_quatf(angle: euler.x, axis: [1, 0, 0])
            * simd_quatf(angle: euler.z, axis: [0, 0, 1])
    }

    // MARK: - 杂项

    private func assetURL(named name: String) -> URL? {
        if name.contains(".") {
            return bundle.url(forResource: name, withExtension: nil)
        }
        return bundle.url(forResource: name, withExtension: "usdz")
    }

    private func reset() {
        // 只移除本渲染器加载的模型；root 上可能还挂着调用方的灯光与相机目标。
        stopHeartEffect()
        loadedModel?.removeFromParent()
        loadedModel = nil
        weightTargets.removeAll()
        lastWrittenWeights.removeAll()
        actionEntries.removeAll()
        loopingActionResources.removeAll()
        playback?.controller.stop(blendOutDuration: 0)
        playback = nil
        playingAction = nil
        headJointIndex = nil
        neckJointIndex = nil
        skeletonRestPoses.removeAll()
        skeletonModelEntity = nil
        smoothedHeadRotation = .zero
        lastWrittenHeadRotation = .zero
        headResumeFramesRemaining = 0
        capabilities = nil
        warnedNames.removeAll()
    }
}

enum AvatarAssetError: Error {
    case notFound(String)
}
