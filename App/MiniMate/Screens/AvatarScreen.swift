import Foundation
import Observation
import RealityKit
import SwiftUI
import MMCore
import MMAvatar

/// 素材（USDZ）就绪前的占位形象：球体头部 + 两只眼睛，用于验证渲染与每帧驱动。
/// T014 的 `RealityKitAvatarRenderer` 落地后由真实模型替换本类。
@MainActor
@Observable
final class PlaceholderAvatarScene {
    /// 调试面板写入。占位形象只映射 `jawOpen`，其余系数等真实模型接入后生效。
    var debugWeights: [String: Float] = [:]
    /// 正在播放的动作，供面板显示。
    private(set) var playingAction: ActionTag?

    let root = Entity()

    @ObservationIgnored private var idle = IdleMotionLayer()
    @ObservationIgnored private var head = Entity()
    @ObservationIgnored private var eyes: [Entity] = []
    @ObservationIgnored private var mouth = Entity()
    @ObservationIgnored private var subscription: EventSubscription?
    @ObservationIgnored private var action: ActionTag?
    @ObservationIgnored private var actionStartedAt: TimeInterval?

    private static let actionDuration: TimeInterval = 1.0

    init() {
        buildScene()
    }

    func play(_ action: ActionTag) {
        self.action = action
        actionStartedAt = Date.timeIntervalSinceReferenceDate
        playingAction = action
    }

    func resetWeights() {
        debugWeights.removeAll()
    }

    /// 订阅 RealityKit 的逐帧更新，持有订阅直到视图销毁。
    func subscribeToUpdates(in content: inout RealityViewCameraContent) {
        subscription = content.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
    }

    private func tick() {
        let now = Date.timeIntervalSinceReferenceDate
        let motion = idle.updateNow()

        var pitch = motion.headRotation.x
        var yaw: Float = 0
        if let tag = action, let startedAt = actionStartedAt {
            let elapsed = now - startedAt
            if elapsed >= Self.actionDuration {
                action = nil
                actionStartedAt = nil
                playingAction = nil
            } else {
                let progress = Float(elapsed / Self.actionDuration)
                if tag == .spin {
                    yaw = 2 * .pi * progress
                } else {
                    pitch += sin(progress * .pi) * 0.3
                }
            }
        }

        head.transform.rotation = simd_quatf(angle: pitch, axis: [1, 0, 0])
            * simd_quatf(angle: yaw, axis: [0, 1, 0])

        let lidScale = max(0.05, 1 - motion.eyeBlink)
        for eye in eyes {
            eye.scale = [1, lidScale, 1]
        }
        mouth.scale = [1, 0.6 + (debugWeights["jawOpen"] ?? 0) * 3, 1]
    }

    private func buildScene() {
        let light = DirectionalLight()
        light.light.intensity = 2000
        light.transform.rotation = simd_quatf(angle: -.pi / 4, axis: [1, 0, 0])
        root.addChild(light)

        head = ModelEntity(
            mesh: .generateSphere(radius: 0.12),
            materials: [SimpleMaterial(color: .systemPink, roughness: 0.6, isMetallic: false)]
        )
        root.addChild(head)

        let eyeMesh = MeshResource.generateSphere(radius: 0.018)
        let eyeMaterial = SimpleMaterial(color: .black, isMetallic: false)
        for x: Float in [-0.04, 0.04] {
            let eye = ModelEntity(mesh: eyeMesh, materials: [eyeMaterial])
            eye.position = [x, 0.015, 0.105]
            head.addChild(eye)
            eyes.append(eye)
        }

        mouth = ModelEntity(
            mesh: .generateBox(width: 0.05, height: 0.012, depth: 0.01),
            materials: [SimpleMaterial(color: .black, isMetallic: false)]
        )
        mouth.position = [0, -0.045, 0.11]
        head.addChild(mouth)
    }
}

struct AvatarScreen: View {
    @State private var scene = PlaceholderAvatarScene()

    var body: some View {
        RealityView { (content: inout RealityViewCameraContent) in
            content.camera = .virtual
            content.cameraTarget = scene.root
            content.add(scene.root)
            scene.subscribeToUpdates(in: &content)
        }
        .ignoresSafeArea()
        .overlay(alignment: .bottomTrailing) {
            NavigationLink {
                AvatarDebugPanel(scene: scene)
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.title3)
                    .padding(12)
                    .background(.thinMaterial, in: Circle())
            }
            .padding()
        }
        .navigationTitle("小瓜")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        AvatarScreen()
    }
}
