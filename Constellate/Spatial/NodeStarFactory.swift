import ConstellateKit
import Foundation
import RealityKit
import simd

/// Star glyphs for code nodes, from `Resources/Assets3D/NodeStars.usdz` (`Blender/scripts/build_graph_assets.py`).
///
/// The file holds one prim per glyph (`Star_App`, `Star_View`, … `Star_Folder`, `Star_Module`, `Star_Halo`), laid
/// out in a row and authored Z-up. `load()` turns each into a prototype at the origin with the file's
/// Z-up → Y-up root rotation baked in, so a clone's front faces +Z and its up is +Y — the same frame as a card.
/// Materials are shared per (colour, glow bucket), so 2 500 stars cost a handful of materials.
/// Without the file every star is a small emissive sphere, so nothing depends on the asset being present.
@MainActor
final class NodeStarFactory {
    private var prototypes: [String: Entity] = [:]
    private var materials: [String: PhysicallyBasedMaterial] = [:]
    private var loadTask: Task<Void, Never>?
    private static let fallbackMesh: MeshResource = .generateSphere(radius: StarEncoder.glyphExtent * 0.32)

    var hasGlyphs: Bool { !prototypes.isEmpty }

    /// Loads the USDZ once (concurrent callers await the same load).
    func load() async {
        if let loadTask { return await loadTask.value }
        let task = Task { [weak self] in
            guard let file = await AssetLoader.entity(named: "NodeStars") else { return }
            self?.extractPrototypes(from: file)
        }
        loadTask = task
        await task.value
    }

    private func extractPrototypes(from file: Entity) {
        for name in StarEncoder.allGlyphNames + [StarEncoder.haloGlyphName] {
            guard let found = file.findEntity(named: name) else { continue }
            // Transform inside the file = root rotation (Z-up → Y-up) × the prim's own row offset.
            let world = found.transformMatrix(relativeTo: nil)
            let geometry = found.clone(recursive: true)
            geometry.transform = Transform(matrix: world)
            geometry.position = .zero
            let prototype = Entity()
            prototype.name = name
            prototype.addChild(geometry)
            prototypes[name] = prototype
        }
    }

    /// A star for `appearance`, at unit scale for a glyph of `StarEncoder.glyphExtent` metres (callers scale it).
    func makeStar(_ appearance: StarAppearance) -> Entity {
        let star: Entity
        if let prototype = prototypes[appearance.glyph] ?? prototypes["Star_Other"] {
            star = prototype.clone(recursive: true)
        } else {
            star = ModelEntity(mesh: Self.fallbackMesh, materials: [])
        }
        star.name = "Star"
        Self.apply(material(color: appearance.color, glow: appearance.glow), to: star)
        return star
    }

    /// Cycle halo (same unit scale as the glyphs), tinted `color`; nil when the asset is missing.
    func makeHalo(color: RGBA) -> Entity? {
        guard let prototype = prototypes[StarEncoder.haloGlyphName] else { return nil }
        let halo = prototype.clone(recursive: true)
        halo.name = "StarHalo"
        Self.apply(material(color: color, glow: 1), to: halo)
        return halo
    }

    /// Emissive PBR: flat facets catch the environment light, emission carries the layer colour and the recency glow.
    private func material(color: RGBA, glow: Float) -> PhysicallyBasedMaterial {
        let bucket = Int((max(0, min(1, glow)) * 4).rounded())
        let key = "\(color.hexString)-\(bucket)"
        if let cached = materials[key] { return cached }
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color.mixed(with: .black, 0.3).platformColor)
        material.emissiveColor = .init(color: color.platformColor)
        material.emissiveIntensity = 0.5 + Float(bucket) * 0.5
        material.roughness = 0.3
        material.metallic = 0.1
        materials[key] = material
        return material
    }

    private static func apply(_ material: PhysicallyBasedMaterial, to entity: Entity) {
        var stack: [Entity] = [entity]
        while let current = stack.popLast() {
            stack.append(contentsOf: current.children)
            guard let model = current as? ModelEntity, var component = model.model else { continue }
            component.materials = Array(repeating: material, count: max(1, component.materials.count))
            model.model = component
        }
    }
}
