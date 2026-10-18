import ConstellateKit
import Foundation
import RealityKit
import simd

/// 3 m light pillar with two expanding rings, raised under a summoned/located node.
@MainActor
final class BeaconEntity {
    static let lifetime: TimeInterval = 20
    static let height: Float = 3

    let root = Entity()
    let nodeID: NodeID
    var isPinned = false
    private(set) var age: TimeInterval = 0

    private let pillar: ModelEntity
    private let rings: [ModelEntity]
    private var color: RGBA
    private var lastOpacityBucket = -1

    init(nodeID: NodeID, color: RGBA, decor: Entity?) {
        self.nodeID = nodeID
        self.color = color
        root.name = "beacon:" + nodeID.raw

        var pillarMaterial = UnlitMaterial(color: color.lightened(0.15).platformColor)
        pillarMaterial.blending = .transparent(opacity: .init(floatLiteral: 0.5))
        pillar = ModelEntity(mesh: .generateCylinder(height: Self.height, radius: 0.022), materials: [pillarMaterial])
        pillar.name = "Pillar"
        pillar.position = [0, Self.height / 2, 0]
        root.addChild(pillar)

        let ringMesh = MeshFactory.ring(radius: 0.3, width: 0.05)
        rings = (0..<2).map { i in
            var m = UnlitMaterial(color: color.platformColor)
            m.blending = .transparent(opacity: .init(floatLiteral: 0.7))
            let ring = ModelEntity(mesh: ringMesh, materials: [m])
            ring.name = "Ring\(i)"
            ring.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
            ring.position = [0, 0.01, 0]
            return ring
        }
        for ring in rings { root.addChild(ring) }

        if let decor {
            AssetLoader.fit(decor, to: Self.height)
            decor.name = "Decor"
            root.addChild(decor)
            pillar.isEnabled = false
        }
    }

    var isExpired: Bool { !isPinned && age > Self.lifetime }

    func setColor(_ color: RGBA) {
        self.color = color
        var pillarMaterial = UnlitMaterial(color: color.lightened(0.15).platformColor)
        pillarMaterial.blending = .transparent(opacity: .init(floatLiteral: 0.5))
        pillar.model?.materials = [pillarMaterial]
        lastOpacityBucket = -1
    }

    func update(deltaTime: TimeInterval) {
        age += deltaTime
        let t = Float(age)
        // Pillar breathes.
        let pulse = 1 + sin(t * 2.6) * 0.18
        pillar.scale = [pulse, 1, pulse]
        // Rings expand 0.3 → 2.4 m over 2.4 s, staggered by half a cycle, fading out.
        for (i, ring) in rings.enumerated() {
            let phase = (t / 2.4 + Float(i) * 0.5).truncatingRemainder(dividingBy: 1)
            let scale = 1 + phase * 7
            ring.scale = [scale, scale, 1]
            // Only swap the material when opacity moved by ≥ 0.1 to avoid per-frame churn.
            let bucket = Int((1 - phase) * 10)
            if bucket != lastOpacityBucket || i == 1 {
                var m = UnlitMaterial(color: color.platformColor)
                m.blending = .transparent(opacity: .init(floatLiteral: max(0, 0.75 * (1 - phase))))
                ring.model?.materials = [m]
                if i == 0 { lastOpacityBucket = bucket }
            }
        }
    }
}
