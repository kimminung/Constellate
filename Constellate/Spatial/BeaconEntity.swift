import ConstellateKit
import Foundation
import RealityKit
import simd

/// 3 m light pillar with two expanding ripples, raised under a summoned/located node.
///
/// Pillar: `Beacon.usdz` when present; else two crossed `FX_Beam` quads (a soft volumetric shaft from any angle);
/// else a plain cylinder. Ripples: flat `FX_Ring` quads (a soft wave with an inner line) or, without the texture,
/// extruded rings. All three paths animate identically.
@MainActor
final class BeaconEntity {
    static let lifetime: TimeInterval = 20
    static let height: Float = 3

    let root = Entity()
    let nodeID: NodeID
    var isPinned = false
    private(set) var age: TimeInterval = 0

    private let pillar: Entity
    private let rings: [ModelEntity]
    private let ringTexture: TextureResource?
    private let beamTexture: TextureResource?
    private var color: RGBA
    private var lastOpacityBucket = [-1, -1]
    private var decor: Entity?

    /// Ripple sprite size: FX_Ring draws its ring at 0.4 × the quad width, so a 0.75 m quad = the 0.3 m ring.
    private static let rippleQuad: Float = 0.75

    init(nodeID: NodeID, color: RGBA, decor: Entity?) {
        let ringSprite = FXTextures.loaded(.ring)
        let beamSprite = FXTextures.loaded(.beam)
        self.nodeID = nodeID
        self.color = color
        ringTexture = ringSprite
        beamTexture = beamSprite
        root.name = "beacon:" + nodeID.raw

        if let beamSprite {
            let shaft = Entity()
            for k in 0..<2 {
                let quad = ModelEntity(mesh: MeshFactory.spriteQuad, materials: [FXTextures.material(beamSprite, color: color.lightened(0.2), opacity: 0.9)])
                quad.name = "Beam\(k)"
                quad.scale = [0.32, Self.height, 1]
                quad.orientation = simd_quatf(angle: Float(k) * .pi / 2, axis: [0, 1, 0])
                shaft.addChild(quad)
            }
            shaft.position = [0, Self.height / 2, 0]
            pillar = shaft
        } else {
            var pillarMaterial = UnlitMaterial(color: color.lightened(0.15).platformColor)
            pillarMaterial.blending = .transparent(opacity: .init(floatLiteral: 0.5))
            let cylinder = ModelEntity(mesh: .generateCylinder(height: Self.height, radius: 0.022), materials: [pillarMaterial])
            cylinder.position = [0, Self.height / 2, 0]
            pillar = cylinder
        }
        pillar.name = "Pillar"
        root.addChild(pillar)

        rings = (0..<2).map { i in
            let ring: ModelEntity
            if let ringSprite {
                ring = ModelEntity(mesh: MeshFactory.spriteQuad, materials: [FXTextures.material(ringSprite, color: color, opacity: 0.8)])
                ring.scale = SIMD3(repeating: Self.rippleQuad)
            } else {
                var m = UnlitMaterial(color: color.platformColor)
                m.blending = .transparent(opacity: .init(floatLiteral: 0.7))
                ring = ModelEntity(mesh: MeshFactory.ring(radius: 0.3, width: 0.05), materials: [m])
            }
            ring.name = "Ring\(i)"
            ring.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
            ring.position = [0, 0.012 + Float(i) * 0.002, 0]
            return ring
        }
        for ring in rings { root.addChild(ring) }

        if let decor {
            AssetLoader.fit(decor, to: Self.height)
            decor.name = "Decor"
            AssetLoader.retintAccent(in: decor, color: color)
            root.addChild(decor)
            self.decor = decor
            pillar.isEnabled = false
        }
    }

    var isExpired: Bool { !isPinned && age > Self.lifetime }

    func setColor(_ color: RGBA) {
        self.color = color
        if let decor { AssetLoader.retintAccent(in: decor, color: color) }
        if let beamTexture {
            for case let quad as ModelEntity in pillar.children {
                quad.model?.materials = [FXTextures.material(beamTexture, color: color.lightened(0.2), opacity: 0.9)]
            }
        } else if let cylinder = pillar as? ModelEntity {
            var pillarMaterial = UnlitMaterial(color: color.lightened(0.15).platformColor)
            pillarMaterial.blending = .transparent(opacity: .init(floatLiteral: 0.5))
            cylinder.model?.materials = [pillarMaterial]
        }
        lastOpacityBucket = [-1, -1]
    }

    func update(deltaTime: TimeInterval) {
        age += deltaTime
        let t = Float(age)
        // Pillar breathes.
        let pulse = 1 + sin(t * 2.6) * 0.18
        pillar.scale = [pulse, 1, pulse]
        // Ripples expand 0.3 → 2.4 m over 2.4 s, staggered by half a cycle, fading out.
        for (i, ring) in rings.enumerated() {
            let phase = (t / 2.4 + Float(i) * 0.5).truncatingRemainder(dividingBy: 1)
            let grow = 1 + phase * 7
            if ringTexture != nil {
                ring.scale = SIMD3(repeating: Self.rippleQuad * grow)
            } else {
                ring.scale = [grow, grow, 1]
            }
            // Swap the material only when opacity moved by ≥ 0.1 to avoid per-frame churn.
            let bucket = Int((1 - phase) * 10)
            guard bucket != lastOpacityBucket[i] else { continue }
            lastOpacityBucket[i] = bucket
            let opacity = max(0, 0.8 * (1 - phase))
            if let ringTexture {
                ring.model?.materials = [FXTextures.material(ringTexture, color: color, opacity: opacity)]
            } else {
                var m = UnlitMaterial(color: color.platformColor)
                m.blending = .transparent(opacity: .init(floatLiteral: opacity))
                ring.model?.materials = [m]
            }
        }
    }
}
