import Foundation
import RealityKit
import simd

#if canImport(UIKit)
import UIKit
private typealias HeartColor = UIColor
#elseif canImport(AppKit)
import AppKit
private typealias HeartColor = NSColor
#endif

/// `heart` 动作的辅助特效：在胸前生成一个白边粉色小爱心，缩放出现后淡出。
///
/// 模型的手很小、连帽衫袖子很大，双手比心在 App 实际尺寸下心形轮廓不够清楚；
/// 爱心特效负责把动作含义明确传达出来，手仍然做出双手比心的姿势。
@MainActor
enum HeartEffect {
    /// 生成一个面向 +Z（镜头方向）的爱心容器。调用方负责整体缩放和位移动画。
    static func make() -> Entity? {
        guard let mesh = makeHeartMesh() else { return nil }
        let container = Entity()

        var borderMaterial = UnlitMaterial(color: .white)
        borderMaterial.faceCulling = .none
        let border = ModelEntity(mesh: mesh, materials: [borderMaterial])
        border.scale = .init(repeating: 1.16)
        border.position = SIMD3<Float>(0, 0, -0.002)
        container.addChild(border)

        var heartMaterial = UnlitMaterial(
            color: HeartColor(red: 1.0, green: 0.30, blue: 0.50, alpha: 1.0)
        )
        heartMaterial.faceCulling = .none
        let heart = ModelEntity(mesh: mesh, materials: [heartMaterial])
        heart.position = SIMD3<Float>(0, 0, 0.002)
        container.addChild(heart)

        return container
    }

    /// 0 → 1 → 1 → 0 的缩放/上浮动画，总长约 0.9 s。
    static func makeAnimation(anchor: SIMD3<Float>, size: Float) -> AnimationResource? {
        let start = Transform(
            scale: .init(repeating: 0.001),
            translation: anchor
        )
        let full = Transform(
            scale: .init(repeating: size),
            translation: anchor + SIMD3<Float>(0, 0.02, 0.02)
        )
        let end = Transform(
            scale: .init(repeating: 0.001),
            translation: anchor + SIMD3<Float>(0, 0.05, 0.03)
        )
        let definition = SampledAnimation<Transform>(
            frames: [start, full, full, end],
            name: "heartEffect",
            frameInterval: 0.3,
            bindTarget: .transform
        )
        return try? AnimationResource.generate(with: definition)
    }

    /// 参数方程心形曲线，三角化成一枚面向 +Z 的扁平爱心（单位宽度约 1）。
    private static func makeHeartMesh() -> MeshResource? {
        let count = 64
        var outline: [SIMD2<Float>] = []
        outline.reserveCapacity(count)
        for index in 0..<count {
            let t = Float(index) / Float(count) * 2 * .pi
            let s = sin(t)
            let x = 16 * s * s * s
            let y = 13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t)
            outline.append(SIMD2<Float>(x, y))
        }

        let minX = outline.map(\.x).min() ?? 0
        let maxX = outline.map(\.x).max() ?? 1
        let minY = outline.map(\.y).min() ?? 0
        let maxY = outline.map(\.y).max() ?? 1
        let scale = 1 / max(maxX - minX, 0.001)
        let center = SIMD2<Float>((minX + maxX) / 2, (minY + maxY) / 2)

        var positions: [SIMD3<Float>] = [SIMD3<Float>(0, 0, 0)]
        positions.reserveCapacity(count + 1)
        positions += outline.map {
            SIMD3<Float>(($0.x - center.x) * scale, ($0.y - center.y) * scale, 0)
        }

        // 正反两面都写入，材质再关掉背面剔除，保证从任何相机角度都可见。
        var indices: [UInt32] = []
        indices.reserveCapacity(count * 6)
        for index in 0..<count {
            let a = UInt32(1 + index)
            let b = UInt32(1 + (index + 1) % count)
            indices.append(contentsOf: [0, a, b, 0, b, a])
        }

        var descriptor = MeshDescriptor(name: "heartEffect")
        descriptor.positions = MeshBuffers.Positions(positions)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }
}
