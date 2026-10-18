import ConstellateKit
import Foundation
import RealityKit
import simd

/// One floating code card. Shares the unit card mesh; size comes from `placement.radius` via scale.
@MainActor
final class CodeNodeEntity {
    static let namePrefix = "node:"

    let nodeID: NodeID
    let root = Entity()
    let card: ModelEntity
    private let frame: ModelEntity
    private var pinMarkers: [ModelEntity] = []
    private(set) var hasBespokeTexture = false
    /// Visual width in metres.
    let width: Float

    init(nodeID: NodeID, radius: Float, material: UnlitMaterial, highlightColor: RGBA) {
        self.nodeID = nodeID
        width = max(0.12, radius * 2)
        root.name = Self.namePrefix + nodeID.raw
        card = ModelEntity(mesh: MeshFactory.unitCard, materials: [material])
        card.name = root.name
        var frameMaterial = UnlitMaterial(color: highlightColor.platformColor)
        frameMaterial.blending = .transparent(opacity: .init(floatLiteral: 0.85))
        frame = ModelEntity(mesh: MeshFactory.unitFrame, materials: [frameMaterial])
        frame.name = "Frame"
        frame.position = [0, 0, -0.003]
        frame.isEnabled = false
        root.addChild(frame)
        root.addChild(card)
        root.scale = SIMD3(repeating: width)

        let height = width * Float(TextureFactory.cardHeight) / Float(TextureFactory.cardWidth)
        root.components.set(InputTargetComponent())
        root.components.set(CollisionComponent(shapes: [.generateBox(size: SIMD3(1, height / width, 0.04))]))
#if os(visionOS)
        root.components.set(HoverEffectComponent())
        root.components.set(BillboardComponent())
#endif
    }

    func setMaterial(_ material: UnlitMaterial, bespoke: Bool) {
        card.model?.materials = [material]
        hasBespokeTexture = bespoke
    }

    enum Emphasis { case none, highlighted, selected }

    func setEmphasis(_ emphasis: Emphasis, highlight: RGBA, selection: RGBA) {
        switch emphasis {
        case .none:
            frame.isEnabled = false
        case .highlighted, .selected:
            frame.isEnabled = true
            var material = UnlitMaterial(color: (emphasis == .selected ? selection : highlight).platformColor)
            material.blending = .transparent(opacity: .init(floatLiteral: 0.85))
            frame.model?.materials = [material]
        }
    }

    /// Small spheres along the top edge, one per review pin.
    func setPins(_ count: Int, color: RGBA, decor: Entity?) {
        for marker in pinMarkers { marker.removeFromParent() }
        pinMarkers.removeAll()
        guard count > 0 else { return }
        let height = Float(TextureFactory.cardHeight) / Float(TextureFactory.cardWidth)
        for i in 0..<min(count, 6) {
            var material = UnlitMaterial(color: color.platformColor)
            material.blending = .transparent(opacity: .init(floatLiteral: 0.95))
            let marker = ModelEntity(mesh: MeshFactory.pinSphere, materials: [material])
            marker.name = "Pin"
            marker.position = [-0.42 + Float(i) * 0.09, height / 2 + 0.02, 0.01]
            // Root is scaled to `width`; keep pins a constant visual size.
            marker.scale = SIMD3(repeating: 1 / max(width, 0.12))
            if let decor, let clone = decor.clone(recursive: true) as Entity? {
                AssetLoader.fit(clone, to: 0.08)
                clone.scale /= max(width, 0.12)
                marker.addChild(clone)
            }
            root.addChild(marker)
            pinMarkers.append(marker)
        }
    }

    /// Resolves a tapped entity (card, frame, pin…) back to its node id.
    static func nodeID(for entity: Entity) -> NodeID? {
        var current: Entity? = entity
        while let e = current {
            if e.name.hasPrefix(namePrefix) { return NodeID(String(e.name.dropFirst(namePrefix.count))) }
            current = e.parent
        }
        return nil
    }
}
