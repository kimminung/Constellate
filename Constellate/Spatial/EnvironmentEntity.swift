import ConstellateKit
import Foundation
import RealityKit
import simd

/// Sky dome (r = 40, inside faces) + floor disc (r = 12) + stage ring. Textures come from the Blender PNGs when
/// present (`Sky_Dark.png` / `Sky_Tint.png` / `Floor_Grid.png`) and fall back to CoreGraphics.
@MainActor
final class EnvironmentEntity {
    let root = Entity()
    /// Sky dome. On visionOS it carries a collision sphere so pinch-hold on "empty space" can be targeted.
    let dome: ModelEntity
    private let floor: ModelEntity
    private var stageRing: Entity?
    private var floorTexture: TextureResource?
    private var skyTintSource: SendableImage?
    private var skyDarkTexture: TextureResource?
    private var hasLoadedAssets = false
    private var themeTask: Task<Void, Never>?

    init() {
        root.name = "Environment"
        var domeMaterial = UnlitMaterial(color: ConstellateTheme.dark.skyHorizon.platformColor)
        domeMaterial.faceCulling = .front
        dome = ModelEntity(mesh: .generateSphere(radius: 40), materials: [domeMaterial])
        dome.name = "SkyDome"
#if os(visionOS)
        dome.components.set(InputTargetComponent())
        dome.components.set(CollisionComponent(shapes: [.generateSphere(radius: 40)]))
#endif
        root.addChild(dome)

        var floorMaterial = UnlitMaterial(color: ConstellateTheme.dark.floor.platformColor)
        floorMaterial.blending = .transparent(opacity: .init(floatLiteral: 0.9))
        floor = ModelEntity(mesh: .generatePlane(width: 24, depth: 24), materials: [floorMaterial])
        floor.name = "FloorDisc"
        floor.position = [0, -0.002, 0]
        root.addChild(floor)
    }

    /// Loads optional assets once, then applies the theme.
    func build(theme: ConstellateTheme) async {
        if !hasLoadedAssets {
            hasLoadedAssets = true
            var gridImage = await AssetLoader.image(named: "Floor_Grid")
            if gridImage == nil {
                gridImage = await Task.detached(priority: .utility) { TextureFactory.floorGridImage() }.value
            }
            if let gridImage {
                floorTexture = await AssetLoader.texture(gridImage, semantic: .color)
            }
            skyTintSource = await AssetLoader.image(named: "Sky_Tint")
            if let dark = await AssetLoader.image(named: "Sky_Dark") {
                skyDarkTexture = await AssetLoader.texture(dark, semantic: .color)
            }
            if let ring = await AssetLoader.entity(named: "Stage_Ring") {
                AssetLoader.fit(ring, to: AvatarEntity.seatRadius * 2.1)
                ring.name = "StageRing"
                root.addChild(ring)
                stageRing = ring
            } else {
                var m = UnlitMaterial(color: theme.floorGrid.lightened(0.2).platformColor)
                m.blending = .transparent(opacity: .init(floatLiteral: 0.7))
                let ring = ModelEntity(mesh: MeshFactory.ring(radius: AvatarEntity.seatRadius, width: 0.03), materials: [m])
                ring.name = "StageRing"
                ring.orientation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
                ring.position = [0, 0.004, 0]
                root.addChild(ring)
                stageRing = ring
            }
        }
        await apply(theme: theme)
    }

    /// Re-tints the floor in place and regenerates the sky texture off the main actor.
    func apply(theme: ConstellateTheme) async {
        var floorMaterial = UnlitMaterial()
        if let floorTexture {
            floorMaterial.color = .init(tint: theme.floorGrid.withAlpha(1).platformColor, texture: .init(floorTexture))
            floorMaterial.blending = .transparent(opacity: .init(scale: Float(theme.floorGrid.a), texture: .init(floorTexture)))
        } else {
            floorMaterial.color = .init(tint: theme.floor.platformColor)
            floorMaterial.blending = .transparent(opacity: .init(floatLiteral: 0.9))
        }
        floorMaterial.faceCulling = .none
        floor.model?.materials = [floorMaterial]

        if let ring = stageRing as? ModelEntity {
            var m = UnlitMaterial(color: theme.floorGrid.lightened(0.2).platformColor)
            m.blending = .transparent(opacity: .init(floatLiteral: 0.7))
            ring.model?.materials = [m]
        }

        // Sky: dark preset can use the baked texture directly; tinted themes multiply the luminance map or go procedural.
        if case .dark = theme.mode, let skyDarkTexture {
            var m = UnlitMaterial()
            m.color = .init(tint: RGBA.white.platformColor, texture: .init(skyDarkTexture))
            m.faceCulling = .front
            dome.model?.materials = [m]
            return
        }
        themeTask?.cancel()
        let tint = skyTintSource
        themeTask = Task { [weak self] in
            let image = await Task.detached(priority: .userInitiated) { TextureFactory.skyImage(theme: theme, tintSource: tint) }.value
            guard !Task.isCancelled, let self, let image, let texture = await AssetLoader.texture(image, semantic: .color) else { return }
            var m = UnlitMaterial()
            m.color = .init(tint: RGBA.white.platformColor, texture: .init(texture))
            m.faceCulling = .front
            self.dome.model?.materials = [m]
        }
    }
}
