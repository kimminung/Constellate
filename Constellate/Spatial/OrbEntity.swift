import ConstellateKit
import Foundation
import RealityKit
import simd

/// Siri-like orb (ported from CoulsonAndJarvis' `CoulsonEntity`, made platform-neutral).
///
/// Layers: emissive core → inner halo → four translucent bands spinning on different axes →
/// additive particle aura (host only) → glass shell created LAST (RealityKit sorts same-centre
/// transparents by creation order) → point light (host only).
@MainActor
final class OrbEntity {

    enum Style {
        /// Host AI: full stack with particles and light.
        case host
        /// Cluster orb: core, halo, bands and shell only (there can be a hundred of these).
        case cluster
    }

    enum Presence: Equatable {
        case idle, listening, thinking, speaking

        var targetEnergy: Float {
            switch self {
            case .idle: 0.22
            case .listening: 0.55
            case .thinking: 1.0
            case .speaking: 0.75
            }
        }
    }

    private struct Band {
        let pivot: Entity
        let spin: Entity
        let model: ModelEntity
        let tiltAxis: SIMD3<Float>
        let baseTilt: Float
        let spinSpeed: Float
        let alpha: Float
    }

    let root = Entity()
    let style: Style
    let coreRadius: Float
    var shellRadius: Float { coreRadius * 2.3 }

    private let core: ModelEntity
    private let halo: ModelEntity
    private var shell = ModelEntity()
    private var bands: [Band] = []
    private let aura = Entity()
    private let light = Entity()
    private var decor: Entity?
    /// Floating title (cluster orbs). The controller orients it toward the viewer in windowed mode.
    private(set) var label: ModelEntity?

    private(set) var basePosition: SIMD3<Float> = .zero
    private var targetBase: SIMD3<Float> = .zero

    var presence: Presence = .idle
    var isDragging = false

    private var elapsed: TimeInterval = 0
    private var energy: Float = 0.22
    private var appliedEnergy: Float = -1
    private var summonPulse: Float = 0

    private var fromAccent: RGBA
    private var toAccent: RGBA
    private var fromBands: [RGBA]
    private var toBands: [RGBA]
    private var colorProgress: Float = 1

    init(style: Style, coreRadius: Float, accent: RGBA, bandColors: [RGBA], name: String) {
        self.style = style
        self.coreRadius = coreRadius
        fromAccent = accent
        toAccent = accent
        fromBands = bandColors
        toBands = bandColors

        core = ModelEntity(mesh: MeshFactory.unitSphere, materials: [PhysicallyBasedMaterial()])
        core.name = "Core"
        core.scale = SIMD3(repeating: coreRadius)
        halo = ModelEntity(mesh: MeshFactory.unitSphere, materials: [UnlitMaterial()])
        halo.name = "Halo"
        halo.scale = SIMD3(repeating: coreRadius * 1.28)

        root.name = name
        root.addChild(core)
        root.addChild(halo)
        buildBands()
        if style == .host {
            aura.name = "Aura"
            root.addChild(aura)
            light.name = "Glow"
            root.addChild(light)
            Task { await refreshAura(force: true) }
        }
        // Glass shell must be created and added last (see type comment).
        shell = ModelEntity(mesh: MeshFactory.unitSphere, materials: [PhysicallyBasedMaterial()])
        shell.name = "Shell"
        shell.scale = SIMD3(repeating: shellRadius)
        root.addChild(shell)

        root.components.set(InputTargetComponent())
        root.components.set(CollisionComponent(shapes: [.generateSphere(radius: shellRadius * 1.15)]))
#if os(visionOS)
        root.components.set(HoverEffectComponent())
#endif
        applyColors(accent: accent, bands: bandColors)
    }

    // MARK: - Build

    private func buildBands() {
        let ring = MeshFactory.ring(radius: coreRadius * 1.75, width: coreRadius * 0.3, depth: coreRadius * 0.05)
        let specs: [(axis: SIMD3<Float>, tilt: Float, speed: Float, alpha: Float)] = [
            ([1, 0, 0], 0.35, 0.9, 0.7),
            ([1, 0, 0.6], 1.15, -0.7, 0.58),
            ([0.2, 0, 1], 1.9, 1.15, 0.5),
            ([1, 0, -0.8], 0.8, -0.5, 0.42)
        ]
        for spec in specs {
            let pivot = Entity()
            let spin = Entity()
            let model = ModelEntity(mesh: ring, materials: [UnlitMaterial()])
            model.name = "Band"
            model.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
            spin.addChild(model)
            pivot.addChild(spin)
            root.addChild(pivot)
            bands.append(Band(pivot: pivot, spin: spin, model: model, tiltAxis: simd_normalize(spec.axis), baseTilt: spec.tilt, spinSpeed: spec.speed, alpha: spec.alpha))
        }
    }

    /// Adds a Blender-made static shell (HostOrb.usdz / ClusterOrb.usdz) inside the procedural shell.
    func attachDecor(_ entity: Entity) {
        decor?.removeFromParent()
        AssetLoader.fit(entity, to: shellRadius * 1.9)
        entity.name = "Decor"
        // Insert before the glass shell so transparency sorting keeps working.
        root.addChild(entity)
        shell.removeFromParent()
        root.addChild(shell)
        decor = entity
    }

    /// Floating title above the orb.
    func setLabel(_ text: String, color: RGBA) {
        label?.removeFromParent()
        let mesh = MeshFactory.label(text, size: coreRadius * 0.6)
        var material = UnlitMaterial(color: color.platformColor)
        material.blending = .transparent(opacity: .init(floatLiteral: 0.9))
        let entity = ModelEntity(mesh: mesh, materials: [material])
        entity.name = "Label"
        let extents = mesh.bounds.extents
        entity.position = SIMD3(-extents.x / 2, shellRadius + coreRadius * 0.35, 0)
        let pivot = Entity()
        pivot.name = "LabelPivot"
        pivot.addChild(entity)
#if os(visionOS)
        pivot.components.set(BillboardComponent())
#endif
        root.addChild(pivot)
        label = entity
    }

    var labelPivot: Entity? { label?.parent }

    private func refreshAura(force: Bool = false) async {
        guard style == .host, force || abs(energy - appliedEnergy) > 0.12 else { return }
        appliedEnergy = energy
        let accent = currentAccent()
        var emitter = ParticleEmitterComponent()
        emitter.emitterShape = .sphere
        emitter.emitterShapeSize = SIMD3(repeating: coreRadius * 1.9)
        emitter.birthLocation = .surface
        emitter.birthDirection = .normal
        emitter.speed = 0.03 + energy * 0.12
        emitter.speedVariation = 0.02
        var main = emitter.mainEmitter
        main.image = await AssetLoader.glowDot()
        main.birthRate = 18 + energy * 34
        main.lifeSpan = 1.5
        main.lifeSpanVariation = 0.4
        main.size = coreRadius * 0.16
        main.sizeVariation = coreRadius * 0.05
        main.sizeMultiplierAtEndOfLifespan = 1.5
        main.blendMode = .additive
        main.opacityCurve = .gradualFadeInOut
        main.isLightingEnabled = false
        main.noiseStrength = 0.06 + energy * 0.08
        main.noiseScale = 1.2
        main.color = .evolving(
            start: .single(accent.lightened(0.35).withAlpha(0.35).platformColor),
            end: .single(accent.withAlpha(0).platformColor)
        )
        emitter.mainEmitter = main
        aura.components.set(emitter)
    }

    // MARK: - Colour

    /// Re-tints the orb over ~1 s.
    func applyAccent(_ accent: RGBA, bands bandColors: [RGBA]) {
        fromAccent = currentAccent()
        fromBands = currentBands()
        toAccent = accent
        toBands = bandColors.isEmpty ? [accent, accent.shiftedHue(by: 40), accent.shiftedHue(by: -40), .white] : bandColors
        colorProgress = 0
    }

    private func currentAccent() -> RGBA {
        fromAccent.mixed(with: toAccent, Double(Self.easeInOut(colorProgress)))
    }

    private func currentBands() -> [RGBA] {
        let t = Double(Self.easeInOut(colorProgress))
        return (0..<4).map { i in
            let a = fromBands.indices.contains(i) ? fromBands[i] : fromAccent
            let b = toBands.indices.contains(i) ? toBands[i] : toAccent
            return a.mixed(with: b, t)
        }
    }

    private func applyColors(accent: RGBA, bands bandColors: [RGBA]) {
        var coreMaterial = PhysicallyBasedMaterial()
        coreMaterial.baseColor = .init(tint: accent.lightened(0.6).platformColor)
        coreMaterial.emissiveColor = .init(color: accent.lightened(0.3).platformColor)
        coreMaterial.emissiveIntensity = 3.2 + energy * 2.5
        coreMaterial.roughness = 0.25
        coreMaterial.metallic = 0.0
        core.model?.materials = [coreMaterial]

        var haloMaterial = UnlitMaterial(color: accent.lightened(0.3).platformColor)
        haloMaterial.blending = .transparent(opacity: .init(floatLiteral: 0.22 + energy * 0.12))
        halo.model?.materials = [haloMaterial]

        var shellMaterial = PhysicallyBasedMaterial()
        shellMaterial.baseColor = .init(tint: accent.lightened(0.75).platformColor)
        shellMaterial.roughness = 0.03
        shellMaterial.metallic = 0.0
        shellMaterial.clearcoat = 1.0
        shellMaterial.clearcoatRoughness = 0.05
        shellMaterial.blending = .transparent(opacity: .init(floatLiteral: 0.1))
        shell.model?.materials = [shellMaterial]

        for (index, band) in bands.enumerated() {
            let color = bandColors.indices.contains(index) ? bandColors[index] : accent
            var material = UnlitMaterial(color: color.lightened(0.2).platformColor)
            material.blending = .transparent(opacity: .init(floatLiteral: band.alpha))
            band.model.model?.materials = [material]
        }

        if style == .host {
            light.components.set(PointLightComponent(color: accent.platformColor, intensity: 70 + energy * 110, attenuationRadius: 1.3))
        }
    }

    // MARK: - Movement

    /// Immediate placement (no easing).
    func place(at position: SIMD3<Float>) {
        basePosition = position
        targetBase = position
        root.position = position
    }

    /// Eased move with a visible pulse.
    func summon(to position: SIMD3<Float>) {
        targetBase = position
        summonPulse = 1
    }

    func setBaseFromDrag(_ position: SIMD3<Float>) {
        basePosition = position
        targetBase = position
    }

    // MARK: - Frame update

    func update(deltaTime: TimeInterval) {
        elapsed += deltaTime
        let dt = Float(deltaTime)
        let t = Float(elapsed)

        energy += (presence.targetEnergy - energy) * min(1, dt * 2.5)
        summonPulse = max(0, summonPulse - dt * 1.4)

        if !isDragging {
            basePosition += (targetBase - basePosition) * min(1, dt * 3.5)
        }
        let bob = isDragging ? 0 : sin(t * 1.4) * (0.014 + energy * 0.01)
        let driftX = isDragging ? 0 : (sin(t * 0.63) + sin(t * 1.37) * 0.5) * 0.0035
        let driftZ = isDragging ? 0 : (cos(t * 0.51) + sin(t * 1.11) * 0.5) * 0.0035
        root.position = basePosition + [driftX, bob, driftZ]

        let breath = sin(t * 2.1) * 0.03
        let speakPulse = presence == .speaking ? abs(sin(t * 9.0) * sin(t * 2.3)) * 0.09 : 0
        let thinkJitter = presence == .thinking ? sin(t * 7.3) * 0.05 : 0
        let coreScale = (1 + breath + speakPulse + thinkJitter + summonPulse * 0.45) * coreRadius
        core.scale = SIMD3(repeating: coreScale)
        halo.scale = SIMD3(repeating: (1 + sin(t * 1.3 + 1) * 0.08 + energy * 0.12 + summonPulse * 0.6) * coreRadius * 1.28)
        shell.scale = SIMD3(repeating: (1 + breath * 0.3 + summonPulse * 0.25) * shellRadius)

        let spinBoost = 0.55 + energy * 2.4
        for (index, band) in bands.enumerated() {
            let phase = Float(index) * 1.7
            let wobble = sin(t * 0.37 + phase) * (0.25 + energy * 0.35)
            band.pivot.orientation = simd_quatf(angle: band.baseTilt + wobble, axis: band.tiltAxis)
            band.spin.orientation = simd_quatf(angle: t * band.spinSpeed * spinBoost + phase, axis: [0, 1, 0])
            let squash = sin(t * 1.7 + phase) * (0.05 + energy * 0.06)
            let grow = 1 + energy * 0.14 + summonPulse * 0.35
            band.model.scale = [(1 + squash) * grow, 1, (1 - squash) * grow]
        }
        if let decor {
            decor.orientation = simd_quatf(angle: t * 0.15, axis: [0, 1, 0])
        }

        var needsColorUpdate = false
        if colorProgress < 1 {
            colorProgress = min(1, colorProgress + dt / 0.9)
            needsColorUpdate = true
        }
        if abs(energy - appliedEnergy) > 0.12 {
            needsColorUpdate = true
            if style == .host { Task { await refreshAura() } } else { appliedEnergy = energy }
        }
        if needsColorUpdate {
            applyColors(accent: currentAccent(), bands: currentBands())
        }
    }

    private static func easeInOut(_ x: Float) -> Float {
        let c = max(0, min(1, x))
        return c * c * (3 - 2 * c)
    }
}
