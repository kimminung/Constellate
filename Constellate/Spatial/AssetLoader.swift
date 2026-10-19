import ConstellateKit
import Foundation
import RealityKit

/// Finds Blender-authored assets in the bundle (`Resources/Assets3D/*.usdz`, `Resources/Textures/*.png`).
/// Every loader returns `nil` when the file is missing so callers fall back to procedural geometry.
@MainActor
enum AssetLoader {

    private static let subdirectories = ["", "Assets3D", "Textures", "Resources/Assets3D", "Resources/Textures", "Resources"]

    static func url(forResource name: String, extension ext: String) -> URL? {
        for dir in subdirectories {
            if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: dir.isEmpty ? nil : dir) {
                return url
            }
        }
        return nil
    }

    /// Loads `<name>.usdz` if present.
    static func entity(named name: String) async -> Entity? {
        guard let url = url(forResource: name, extension: "usdz") else { return nil }
        do {
            return try await Entity(contentsOf: url)
        } catch {
            print("[AssetLoader] \(name).usdz failed: \(error)")
            return nil
        }
    }

    /// Loads `<name>.png` as a CGImage (on a background task).
    static func image(named name: String) async -> SendableImage? {
        guard let url = url(forResource: name, extension: "png") else { return nil }
        return await Task.detached(priority: .utility) { TextureFactory.loadPNG(at: url) }.value
    }

    static func texture(_ image: SendableImage, semantic: TextureResource.Semantic = .color, mipmaps: Bool = true) async -> TextureResource? {
        do {
            let options = TextureResource.CreateOptions(semantic: semantic, mipmapsMode: mipmaps ? .allocateAndGenerateAll : .none)
            return try await TextureResource(image: image.image, options: options)
        } catch {
            print("[AssetLoader] texture creation failed: \(error)")
            return nil
        }
    }

    private static var glowDotTexture: TextureResource?

    /// Shared additive particle sprite: the Blender `FX_Glow` (premultiplied, so additive blending fades with
    /// it), else the CoreGraphics dot.
    static func glowDot() async -> TextureResource? {
        if let glowDotTexture { return glowDotTexture }
        let sprite: SendableImage?
        if let fx = await image(named: FXTextures.Sprite.glow.rawValue) {
            sprite = await Task.detached(priority: .utility) { TextureFactory.premultiplied(fx) }.value
        } else {
            sprite = await Task.detached(priority: .utility) { TextureFactory.glowDot() }.value
        }
        guard let sprite else { return nil }
        let texture = await texture(sprite, semantic: .raw, mipmaps: false)
        glowDotTexture = texture
        return texture
    }

    /// Accent colours the Blender exporter uses for the `Accent` material slot.
    private static let exportedAccents: [RGBA] = [RGBA(hex: 0x6FB6FF), RGBA(hex: 0xFFD166), RGBA(hex: 0xFF8FD1), RGBA(hex: 0x5EE1FF)]

    /// Walks `entity` and replaces every `Accent` material with an emissive PBR in `color`.
    /// Matches by material / entity name when the importer preserves it, else by colour ≈ an exported accent.
    @discardableResult
    static func retintAccent(in entity: Entity, color: RGBA) -> Int {
        var count = 0
        var stack: [Entity] = [entity]
        while let current = stack.popLast() {
            stack.append(contentsOf: current.children)
            guard let modelEntity = current as? ModelEntity, var component = modelEntity.model else { continue }
            var changed = false
            for (index, material) in component.materials.enumerated() where isAccent(material, entityName: current.name) {
                component.materials[index] = accentMaterial(color)
                changed = true
                count += 1
            }
            if changed { modelEntity.model = component }
        }
        return count
    }

    static func accentMaterial(_ color: RGBA) -> PhysicallyBasedMaterial {
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(tint: color.mixed(with: .black, 0.35).platformColor)
        material.emissiveColor = .init(color: color.platformColor)
        material.emissiveIntensity = 2.2
        material.roughness = 0.35
        material.metallic = 0.0
        return material
    }

    private static func isAccent(_ material: any Material, entityName: String) -> Bool {
        if entityName.localizedCaseInsensitiveContains("accent") { return true }
        if let shader = material as? ShaderGraphMaterial, (shader.name ?? "").localizedCaseInsensitiveContains("accent") { return true }
        if let pbr = material as? PhysicallyBasedMaterial {
            if let emissive = (pbr.emissiveColor.color as PlatformColor?)?.rgba, matchesAccent(emissive) { return true }
            if let tint = (pbr.baseColor.tint as PlatformColor?)?.rgba, matchesAccent(tint) { return true }
        }
        if let unlit = material as? UnlitMaterial, let tint = (unlit.color.tint as PlatformColor?)?.rgba, matchesAccent(tint) { return true }
        return false
    }

    private static func matchesAccent(_ color: RGBA) -> Bool {
        exportedAccents.contains { $0.distance(to: color) < 0.12 }
    }

    /// Scales `entity` uniformly so its largest visual extent equals `size` metres.
    static func fit(_ entity: Entity, to size: Float) {
        let bounds = entity.visualBounds(relativeTo: nil)
        let largest = max(bounds.extents.x, bounds.extents.y, bounds.extents.z)
        guard largest > 0.0001 else { return }
        entity.scale = SIMD3(repeating: size / largest)
    }
}
