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

    /// Shared additive particle sprite.
    static func glowDot() async -> TextureResource? {
        if let glowDotTexture { return glowDotTexture }
        guard let image = await Task.detached { TextureFactory.glowDot() }.value else { return nil }
        let texture = await texture(image, semantic: .raw, mipmaps: false)
        glowDotTexture = texture
        return texture
    }

    /// Scales `entity` uniformly so its largest visual extent equals `size` metres.
    static func fit(_ entity: Entity, to size: Float) {
        let bounds = entity.visualBounds(relativeTo: nil)
        let largest = max(bounds.extents.x, bounds.extents.y, bounds.extents.z)
        guard largest > 0.0001 else { return }
        entity.scale = SIMD3(repeating: size / largest)
    }
}
