import ConstellateKit
import Foundation
import RealityKit
import simd

/// One floating code card. Shares the unit card mesh; size comes from `placement.radius` via scale.
///
/// root (scaled to `width`, billboarded on visionOS)
/// ├─ Glow   FX_CardGlow quad behind the card (selection / highlight); `Frame` is the untextured fallback
/// ├─ Card   the code texture
/// ├─ Star   role glyph above the top-left corner (`StarEncoder`), with an optional cycle `StarHalo`
/// └─ Pin…   review-pin markers along the top edge
@MainActor
final class CodeNodeEntity {
    static let namePrefix = "node:"

    let nodeID: NodeID
    let root = Entity()
    let card: ModelEntity
    private let frame: ModelEntity
    private var glow: ModelEntity?
    private var pinMarkers: [Entity] = []
    private var pinsUseDecor = false
    private var star: Entity?
    /// Visual size of the role star in metres (0 = no star); pins line up to its right.
    private var starSize: Float = 0
    private var halo: Entity?
    private(set) var isDimmed = false
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

    /// Children are in the root's scaled space (1 unit = `width` metres); divide metric sizes by this.
    private var inverseScale: Float { 1 / max(width, 0.12) }

    func setMaterial(_ material: UnlitMaterial, bespoke: Bool) {
        card.model?.materials = [material]
        hasBespokeTexture = bespoke
    }

    enum Emphasis { case none, highlighted, selected }

    /// Selection / highlight: the Blender `FX_CardGlow` halo when available, else the flat coloured frame.
    func setEmphasis(_ emphasis: Emphasis, highlight: RGBA, selection: RGBA) {
        switch emphasis {
        case .none:
            frame.isEnabled = false
            glow?.isEnabled = false
        case .highlighted, .selected:
            let color = emphasis == .selected ? selection : highlight
            if let texture = FXTextures.loaded(.cardGlow) {
                let material = FXTextures.material(texture, color: color, opacity: emphasis == .selected ? 1 : 0.8)
                if let glow {
                    glow.model?.materials = [material]
                    glow.isEnabled = true
                } else {
                    let quad = ModelEntity(mesh: MeshFactory.unitCardGlow, materials: [material])
                    quad.name = "Glow"
                    quad.position = [0, 0, -0.004]
                    root.addChild(quad)
                    glow = quad
                }
                frame.isEnabled = false
            } else {
                frame.isEnabled = true
                var material = UnlitMaterial(color: color.platformColor)
                material.blending = .transparent(opacity: .init(floatLiteral: 0.85))
                frame.model?.materials = [material]
            }
        }
    }

    /// Places the role star (see `StarEncoder`): above the top-left corner, sized by fan-in, at a constant metric
    /// size whatever the card width. `nil` removes it.
    func setStar(_ entity: Entity?, appearance: StarAppearance?) {
        star?.removeFromParent()
        star = nil
        halo = nil
        defer { layoutPins() }
        guard let entity, let appearance else {
            starSize = 0
            return
        }
        let k = inverseScale
        starSize = appearance.size
        entity.scale = SIMD3(repeating: appearance.size / StarEncoder.glyphExtent * k)
        entity.position = StarEncoder.anchor(cardWidth: width, size: appearance.size) * k
        root.addChild(entity)
        star = entity
    }

    /// Cycle halo around the star (a child of the star, so it inherits its size). `nil` removes it.
    func setHalo(_ entity: Entity?) {
        halo?.removeFromParent()
        halo = nil
        guard let entity, let star else { return }
        star.addChild(entity)
        halo = entity
    }

    var hasHalo: Bool { halo != nil }

    /// Focus dimming: cards unrelated to the selection recede (relations mode ≠ off).
    func setDimmed(_ dimmed: Bool) {
        guard dimmed != isDimmed else { return }
        isDimmed = dimmed
        if dimmed {
            root.components.set(OpacityComponent(opacity: 0.22))
        } else {
            root.components.remove(OpacityComponent.self)
        }
    }

    static let maxPins = 6
    /// `ReviewPin.usdz` is fitted to this height (metres); its gem head is ≈ 0.018 m in radius.
    static let pinHeight: Float = 0.08

    /// One marker per open review pin along the top edge: the Blender `ReviewPin` (needle tip on the edge, gem up,
    /// tinted with `color`) or, without the asset, a small sphere.
    func setPins(_ count: Int, color: RGBA, decor: Entity?) {
        for marker in pinMarkers { marker.removeFromParent() }
        pinMarkers.removeAll()
        pinsUseDecor = decor != nil
        guard count > 0 else { return }
        for _ in 0..<min(count, Self.maxPins) {
            let marker: Entity
            if let decor {
                let clone = decor.clone(recursive: true)
                AssetLoader.fit(clone, to: Self.pinHeight)   // metric: the holder cancels the card scale
                AssetLoader.retintAccent(in: clone, color: color)
                marker = Entity()
                marker.addChild(clone)
            } else {
                var material = UnlitMaterial(color: color.platformColor)
                material.blending = .transparent(opacity: .init(floatLiteral: 0.95))
                marker = ModelEntity(mesh: MeshFactory.pinSphere, materials: [material])
            }
            marker.name = "Pin"
            root.addChild(marker)
            pinMarkers.append(marker)
        }
        layoutPins()
    }

    /// Pins form a row that starts just right of the role star (so the two never overlap) at a constant metric
    /// size; on cards too narrow for the whole row the pins shrink (down to 35 %) instead of spilling far past
    /// the edge. Positions are computed in metres, then divided into the root's card-width units.
    private func layoutPins() {
        guard !pinMarkers.isEmpty else { return }
        let k = inverseScale
        let top = width * Float(TextureFactory.cardHeight) / Float(TextureFactory.cardWidth) / 2
        let start = starSize > 0
            ? StarEncoder.anchor(cardWidth: width, size: starSize).x + starSize / 2 + 0.008
            : -width / 2 + 0.01
        let radius: Float = pinsUseDecor ? 0.018 : 0.035   // gem head / fallback sphere (MeshFactory.pinSphere)
        let step = 2 * radius + 0.006
        let room = max(0.02, width / 2 - start)
        let fit = min(1, max(0.35, room / (Float(pinMarkers.count) * step)))
        for (i, marker) in pinMarkers.enumerated() {
            let x = start + (radius + Float(i) * step) * fit
            // The asset's needle tip is its origin: stand it on the edge. Spheres float just above it.
            let y = pinsUseDecor ? top : top + (radius + 0.008) * fit
            marker.position = SIMD3(x, y, 0.01) * k
            marker.scale = SIMD3(repeating: fit * k)
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
