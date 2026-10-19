import ConstellateKit
import Foundation
import RealityKit

/// The Blender-rendered effect sprites in `Resources/Textures/FX_*.png` (white RGB + alpha mask, built by
/// `Blender/scripts/build_graph_assets.py`). Loaded once, shared by every scene controller, and tinted per use —
/// one texture serves every theme and relation colour.
///
/// | sprite | used by |
/// |---|---|
/// | `FX_Glow` | flow particles (normal), host-orb aura particles |
/// | `FX_Spark` | flow particles on focused relations (diffraction-spike star) |
/// | `FX_Ring` | beacon ripples |
/// | `FX_Beam` | beacon light pillar (when `Beacon.usdz` is missing) |
/// | `FX_EdgeRamp` | relation tubes: brightness rises from source to target, so direction reads without motion |
/// | `FX_CardGlow` | selection / highlight glow behind a code card |
///
/// Every accessor degrades gracefully: glow/spark fall back to the procedural `TextureFactory.glowDot`, the
/// others to `nil` (callers then use their original untextured look).
@MainActor
enum FXTextures {
    enum Sprite: String, CaseIterable, Sendable {
        case glow = "FX_Glow"
        case spark = "FX_Spark"
        case ring = "FX_Ring"
        case beam = "FX_Beam"
        case edgeRamp = "FX_EdgeRamp"
        case cardGlow = "FX_CardGlow"
    }

    private static var cache: [Sprite: TextureResource] = [:]
    private static var unavailable: Set<Sprite> = []

    /// Loads (once) and returns the sprite's texture.
    static func texture(_ sprite: Sprite) async -> TextureResource? {
        if let cached = cache[sprite] { return cached }
        if unavailable.contains(sprite) { return nil }
        var image = await AssetLoader.image(named: sprite.rawValue)
        if image == nil, sprite == .glow || sprite == .spark {
            image = await Task.detached(priority: .utility) { TextureFactory.glowDot(size: 128) }.value
        }
        guard let image, let texture = await AssetLoader.texture(image, semantic: .color) else {
            unavailable.insert(sprite)
            return nil
        }
        cache[sprite] = texture
        return texture
    }

    /// The sprite if it has already been loaded (synchronous; call `preload()` first).
    static func loaded(_ sprite: Sprite) -> TextureResource? { cache[sprite] }

    static func preload() async {
        for sprite in Sprite.allCases { _ = await texture(sprite) }
    }

    /// Unlit, alpha-blended material that tints a white-mask sprite: colour = tint, opacity = mask × `opacity`.
    static func material(_ texture: TextureResource, color: RGBA, opacity: Float) -> UnlitMaterial {
        var material = UnlitMaterial()
        material.color = .init(tint: color.withAlpha(1).platformColor, texture: .init(texture))
        material.blending = .transparent(opacity: .init(scale: opacity, texture: .init(texture)))
        material.faceCulling = .none
        return material
    }
}
