import ConstellateKit
import Foundation
import RealityKit
import simd

/// Relations in RealityKit.
///
/// The Kit's `EdgeSceneBuilder` (a port of CoulsonPortfolioWeb's `rebuildEdges()`) runs off the main actor and
/// returns one merged `TubeMesh` per `EdgeBatchKey` (relation × emphasis × cycle) plus the flow paths. Here each
/// batch becomes one `ModelEntity` shaded with the Blender `FX_EdgeRamp` (every edge brightens toward its target, so
/// direction reads even with motion off), and `FlowParticles` animates glowing sprites along flow kinds.
/// Builds are generation-counted: a slow build that finishes after a newer request is dropped.
@MainActor
final class EdgeRenderer {
    let root: Entity
    private(set) var scene = EdgeScene()
    private var batchEntities: [EdgeBatchKey: ModelEntity] = [:]
    /// Latest theme: a build that finishes after a theme change must not install old tree-line colours.
    private var theme = ConstellateTheme.dark
    private let particles = FlowParticles()
    private var buildTask: Task<Void, Never>?
    private var generation = 0

    init(root: Entity) {
        self.root = root
        particles.root.name = "FlowParticles"
        root.addChild(particles.root)
    }

    /// Rebuilds every relation mesh; `completion` runs on the main actor with the new scene (for focus dimming).
    func rebuild(graph: CodeGraph, layout: ConstellationLayout, options: EdgeSceneOptions, theme: ConstellateTheme,
                 completion: @escaping @MainActor (EdgeScene) -> Void) {
        buildTask?.cancel()
        generation += 1
        self.theme = theme
        let token = generation
        buildTask = Task { [weak self] in
            let built = await Task.detached(priority: .userInitiated) {
                EdgeSceneBuilder.build(graph: graph, layout: layout, options: options)
            }.value
            let ramp = await FXTextures.texture(.edgeRamp)
            guard let self, !Task.isCancelled, token == self.generation else { return }
            self.install(built, theme: self.theme, ramp: ramp)
            completion(built)
        }
    }

    private func install(_ built: EdgeScene, theme: ConstellateTheme, ramp: TextureResource?) {
        for entity in batchEntities.values { entity.removeFromParent() }
        batchEntities.removeAll()
        for key in built.sortedBatchKeys {
            guard let tube = built.batches[key], let mesh = MeshFactory.mesh(from: tube, name: Self.name(for: key)) else { continue }
            let entity = ModelEntity(mesh: mesh, materials: [Self.material(for: key, theme: theme, ramp: ramp)])
            entity.name = Self.name(for: key)
            root.addChild(entity)
            batchEntities[key] = entity
        }
        scene = built
        particles.setPaths(built.flows)
    }

    func removeAll() {
        buildTask?.cancel()
        generation += 1
        for entity in batchEntities.values { entity.removeFromParent() }
        batchEntities.removeAll()
        particles.setPaths([])
        scene = EdgeScene()
    }

    /// Tree lines follow the theme's `edgeContains`; relation colours are fixed, so only tree batches change.
    func applyTheme(_ theme: ConstellateTheme) {
        self.theme = theme
        let ramp = FXTextures.loaded(.edgeRamp)
        for (key, entity) in batchEntities {
            entity.model?.materials = [Self.material(for: key, theme: theme, ramp: ramp)]
        }
    }

    func update(deltaTime: Float, viewer: SIMD3<Float>, faceViewer: Bool) {
        particles.update(deltaTime: deltaTime, viewer: viewer, faceViewer: faceViewer)
    }

    static func name(for key: EdgeBatchKey) -> String {
        "edges:\(key.relation?.rawValue ?? "contains"):\(key.emphasis)\(key.isCycle ? ":cycle" : "")"
    }

    /// Ramp-textured (direction) for relations; flat for tree lines. Opacity: `EdgeBatchKey.opacity`.
    static func material(for key: EdgeBatchKey, theme: ConstellateTheme, ramp: TextureResource?) -> UnlitMaterial {
        let color = key.color(theme: theme).withAlpha(1)
        var material = UnlitMaterial(color: color.platformColor)
        if let ramp, key.relation != nil {
            material.color = .init(tint: color.platformColor, texture: .init(ramp))
            material.blending = .transparent(opacity: .init(scale: key.opacity, texture: .init(ramp)))
        } else {
            material.blending = .transparent(opacity: .init(floatLiteral: key.opacity))
        }
        material.faceCulling = .none
        return material
    }
}

/// Glowing sprites travelling along flow relations (the portfolio's `flowParticles`): `FX_Spark` on focused
/// relations, `FX_Glow` elsewhere, tinted with the relation colour. Positions are advanced once per frame on
/// the main actor (≤ `EdgeSceneOptions.particleCap` entities); sprites face the viewer (BillboardComponent on
/// visionOS, a per-frame look-at in windowed mode) and shrink in and out at the ends of their path.
@MainActor
final class FlowParticles {
    let root = Entity()

    private struct Particle {
        var entity: ModelEntity
        var path: Int
        var phase: Float
        var size: Float
    }

    private var paths: [FlowPath] = []
    private var particles: [Particle] = []
    private var materials: [String: UnlitMaterial] = [:]

    func setPaths(_ flows: [FlowPath]) {
        for particle in particles { particle.entity.removeFromParent() }
        particles.removeAll()
        paths = flows
        for (index, flow) in flows.enumerated() {
            let focused = flow.emphasis == .focus
            let texture = FXTextures.loaded(focused ? .spark : .glow)
            let material = particleMaterial(flow.relation, focused: focused, texture: texture)
            let mesh = texture == nil ? MeshFactory.particleSphere : MeshFactory.spriteQuad
            let size: Float = texture == nil ? 0.02 : (focused ? 0.075 : 0.045)
            for k in 0..<max(0, flow.particleCount) {
                let entity = ModelEntity(mesh: mesh, materials: [material])
                entity.name = "flow"
#if os(visionOS)
                if texture != nil { entity.components.set(BillboardComponent()) }
#endif
                root.addChild(entity)
                // Spread along the path; offset each path a little so neighbouring edges don't pulse in sync.
                let phase = (Float(k) / Float(max(1, flow.particleCount)) + Float((index * 37) % 100) / 100)
                    .truncatingRemainder(dividingBy: 1)
                particles.append(Particle(entity: entity, path: index, phase: phase, size: size))
            }
        }
        update(deltaTime: 0, viewer: .zero, faceViewer: false)
    }

    private func particleMaterial(_ relation: RelationKind, focused: Bool, texture: TextureResource?) -> UnlitMaterial {
        let key = "\(relation.rawValue)-\(focused)-\(texture == nil)"
        if let cached = materials[key] { return cached }
        let color = relation.style.color.lightened(focused ? 0.25 : 0.1)
        let material: UnlitMaterial
        if let texture {
            material = FXTextures.material(texture, color: color, opacity: focused ? 1 : 0.85)
        } else {
            var flat = UnlitMaterial(color: color.platformColor)
            flat.blending = .transparent(opacity: .init(floatLiteral: 0.9))
            material = flat
        }
        materials[key] = material
        return material
    }

    func update(deltaTime: Float, viewer: SIMD3<Float>, faceViewer: Bool) {
        guard !particles.isEmpty else { return }
        for i in particles.indices {
            let path = paths[particles[i].path]
            let length = max(path.totalLength, 0.05)
            var phase = particles[i].phase + deltaTime * path.speed / length
            phase -= phase.rounded(.down)
            particles[i].phase = phase
            let position = path.point(atFraction: phase)
            let entity = particles[i].entity
            entity.position = position
            // Grow in over the first 12 % of the path and fade out over the last 12 %.
            let fade = min(1, phase / 0.12, (1 - phase) / 0.12)
            entity.scale = SIMD3(repeating: particles[i].size * max(0.05, fade))
            if faceViewer {
                let toViewer = viewer - position
                let distance = simd_length(toViewer)
                if distance > 0.001 { entity.orientation = simd_quatf(from: [0, 0, 1], to: toViewer / distance) }
            }
        }
    }
}
