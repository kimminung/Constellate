import Foundation

/// How a node's "star" (the small 3-D glyph floating at the card's corner) looks. Each visual channel carries one
/// fact, so a developer can read a node without opening it — and from far away, when card text is unreadable,
/// stars plus relation arcs still form a legible constellation:
///
/// | channel | fact |
/// |---|---|
/// | shape (`glyph`) | role — App / View / ViewModel / Model / Service / Test … (`CodeRole`), hubs for folders |
/// | colour | architecture layer (same band colour as the card stripe) |
/// | size | coupling — files that depend on this one (Ca / fan-in) |
/// | glow | recency (`w`: newest code shines brightest) |
/// | halo ring | part of a dependency cycle |
public struct StarAppearance: Sendable, Hashable {
    /// Prim name inside `NodeStars.usdz` (see `CodeNode.starGlyphName`).
    public var glyph: String
    public var color: RGBA
    /// World size of the glyph's largest dimension, metres.
    public var size: Float
    /// 0…1 emissive strength multiplier.
    public var glow: Float
    public var inCycle: Bool
}

public enum StarEncoder {
    /// - Parameters:
    ///   - fanIn: files depending on this node's file (`GraphInsights.metrics(for:).fanIn`); ignored for hubs.
    ///   - recency: the placement's `w` (0 oldest … 1 newest).
    public static func appearance(for node: CodeNode, theme: ConstellateTheme, fanIn: Int, recency: Float, inCycle: Bool) -> StarAppearance {
        let size: Float
        switch node.kind {
        case .module: size = 0.12
        case .folder: size = 0.075
        default:
            // 4.5 cm for leaf files, growing with log2 of the dependents, capped so hubs stay glyphs, not planets.
            size = min(0.11, 0.045 + 0.012 * log2(1 + Float(max(0, fanIn))))
        }
        let glow = 0.45 + 0.55 * min(1, max(0, recency))
        return StarAppearance(glyph: node.starGlyphName, color: theme.color(for: node.layer), size: size, glow: glow, inCycle: inCycle)
    }

    /// Every glyph name the app may ask `NodeStars.usdz` for (roles + hubs), for preloading and fallbacks.
    public static let allGlyphNames: [String] = CodeRole.allCases.map(\.style.glyph) + ["Star_Folder", "Star_Module"]

    /// Ring drawn around stars whose file sits on the highlighted dependency cycle.
    public static let haloGlyphName = "Star_Halo"
    /// Largest dimension of every glyph in `NodeStars.usdz` (metres); scale = `size / glyphExtent`.
    public static let glyphExtent: Float = 0.1

    /// Where the star floats in its card's local frame (metres; x right, y up, z toward the viewer): just above
    /// the top-left corner, so it never covers the title. `Blender/scripts/render_graph.py` uses the same rule.
    public static func anchor(cardWidth: Float, size: Float, cardAspect: Float = 352.0 / 512.0) -> SIMD3<Float> {
        SIMD3(-cardWidth / 2 + size * 0.55, cardWidth * cardAspect / 2 + size * 0.65, 0.01)
    }
}
