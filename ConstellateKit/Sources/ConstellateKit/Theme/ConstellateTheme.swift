import Foundation

/// Platform-independent colour. Components are 0…1, sRGB.
public struct RGBA: Hashable, Codable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double
    public var a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    public init(hex: UInt32, alpha: Double = 1) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
        a = alpha
    }

    /// hue 0…360, saturation 0…1, lightness 0…1
    public init(hue: Double, saturation: Double, lightness: Double, alpha: Double = 1) {
        let h = ((hue.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360) / 360
        let s = min(max(saturation, 0), 1)
        let l = min(max(lightness, 0), 1)
        if s == 0 {
            self.init(r: l, g: l, b: l, a: alpha)
            return
        }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        func channel(_ t0: Double) -> Double {
            var t = t0
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1 / 6 { return p + (q - p) * 6 * t }
            if t < 1 / 2 { return q }
            if t < 2 / 3 { return p + (q - p) * (2 / 3 - t) * 6 }
            return p
        }
        self.init(r: channel(h + 1 / 3), g: channel(h), b: channel(h - 1 / 3), a: alpha)
    }

    public var hsl: (hue: Double, saturation: Double, lightness: Double) {
        let maxC = max(r, g, b), minC = min(r, g, b)
        let l = (maxC + minC) / 2
        guard maxC != minC else { return (0, 0, l) }
        let d = maxC - minC
        let s = l > 0.5 ? d / (2 - maxC - minC) : d / (maxC + minC)
        var h: Double
        if maxC == r { h = (g - b) / d + (g < b ? 6 : 0) }
        else if maxC == g { h = (b - r) / d + 2 }
        else { h = (r - g) / d + 4 }
        return (h * 60, s, l)
    }

    /// Chroma = max − min channel (0…1). Better than HSL saturation for judging how "colourful" a dark colour looks.
    public var chroma: Double { max(r, g, b) - min(r, g, b) }

    /// WCAG relative luminance.
    public var luminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    public func contrastRatio(against other: RGBA) -> Double {
        let l1 = luminance, l2 = other.luminance
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    public func withAlpha(_ alpha: Double) -> RGBA { RGBA(r: r, g: g, b: b, a: alpha) }

    public var hexString: String {
        String(format: "#%02X%02X%02X", Int(r * 255 + 0.5), Int(g * 255 + 0.5), Int(b * 255 + 0.5))
    }
}

/// Syntax colours used for floating code. These are deliberately bright and saturated so they
/// always separate from the (dark, desaturated) environment.
public struct CodePalette: Hashable, Codable, Sendable {
    public var plain: RGBA
    public var keyword: RGBA
    public var type: RGBA
    public var function: RGBA
    public var string: RGBA
    public var number: RGBA
    public var comment: RGBA
    public var cardBackground: RGBA
    public var cardBorder: RGBA

    public static let standard = CodePalette(
        plain: RGBA(hex: 0xF4F6FB),
        keyword: RGBA(hex: 0xFF7AB6),   // pink
        type: RGBA(hex: 0x5EE1FF),      // cyan
        function: RGBA(hex: 0xFFD166),  // amber
        string: RGBA(hex: 0xB8FF7A),    // lime
        number: RGBA(hex: 0xB89CFF),    // lavender
        comment: RGBA(hex: 0x8A93A6),
        cardBackground: RGBA(hex: 0x0E1220, alpha: 0.78),
        cardBorder: RGBA(hex: 0xFFFFFF, alpha: 0.14)
    )

    /// Hues reserved by the code palette. Environment colours must stay away from these
    /// (see `ConstellateTheme.validate`).
    public var reservedHues: [Double] {
        [keyword, type, function, string, number].map { $0.hsl.hue }
    }
}

/// Colours for one architecture layer band (used on cards / edges / orbit rings).
public struct LayerBand: Hashable, Codable, Sendable {
    public var layer: ArchitectureLayer
    public var color: RGBA
}

public enum ThemeMode: Hashable, Codable, Sendable {
    case dark
    /// Tinted immersive. `hue` 0…360 chosen by the user.
    case tinted(hue: Double)
}

/// Full visual theme. The rule set that keeps floating code readable:
/// - environment colours: chroma ≤ 0.16, lightness ≤ 0.30 (dark and nearly grey)
/// - code colours: chroma ≥ 0.35, lightness ≥ 0.62 (bright and colourful)
/// - a visibly tinted environment (chroma > 0.10) keeps its hue ≥ 20° away from any code hue
/// - contrast(code.plain, skyHorizon) ≥ 7, contrast(code.*, cardBackground) ≥ 4.5
public struct ConstellateTheme: Hashable, Codable, Sendable, Identifiable {
    public var id: String { name }
    public var name: String
    public var mode: ThemeMode
    public var skyTop: RGBA
    public var skyHorizon: RGBA
    public var skyBottom: RGBA
    public var floor: RGBA
    public var floorGrid: RGBA
    public var fog: RGBA
    /// Halo colour of the host AI orb. Core is always near-white.
    public var orbHalo: RGBA
    public var orbBands: [RGBA]
    /// Participant avatar accent (each participant gets a hue offset from this).
    public var avatarAccent: RGBA
    /// Beacon pillar for "summoned" code.
    public var beacon: RGBA
    /// Highlight ring for AI-located nodes.
    public var highlight: RGBA
    public var edgeContains: RGBA
    public var edgeImports: RGBA
    public var edgeReferences: RGBA
    public var edgeInherits: RGBA
    public var edgeCalls: RGBA
    public var layerBands: [LayerBand]
    public var code: CodePalette

    // MARK: Presets

    public static let dark = ConstellateTheme(
        name: "Dark",
        mode: .dark,
        skyTop: RGBA(hex: 0x05070F),
        skyHorizon: RGBA(hex: 0x121733),
        skyBottom: RGBA(hex: 0x0A0B14),
        floor: RGBA(hex: 0x0B0E1A),
        floorGrid: RGBA(hex: 0x2A3150, alpha: 0.55),
        fog: RGBA(hex: 0x0B0F1F),
        orbHalo: RGBA(hex: 0x9B8CFF),
        orbBands: [RGBA(hex: 0x7F7CFF), RGBA(hex: 0x58D7E8), RGBA(hex: 0xFF8FD1), RGBA(hex: 0xFFFFFF)],
        avatarAccent: RGBA(hex: 0x6FB6FF),
        beacon: RGBA(hex: 0xFFD166),
        highlight: RGBA(hex: 0x5EE1FF),
        edgeContains: RGBA(hex: 0x6B7390, alpha: 0.55),
        edgeImports: RGBA(hex: 0x58D7E8, alpha: 0.7),
        edgeReferences: RGBA(hex: 0xFF8FD1, alpha: 0.7),
        edgeInherits: RGBA(hex: 0xC9B6FF, alpha: 0.8),
        edgeCalls: RGBA(hex: 0xFFD166, alpha: 0.7),
        layerBands: [
            LayerBand(layer: .presentation, color: RGBA(hex: 0x5EE1FF)),
            LayerBand(layer: .domain, color: RGBA(hex: 0xC9B6FF)),
            LayerBand(layer: .data, color: RGBA(hex: 0xFFD166)),
            LayerBand(layer: .infrastructure, color: RGBA(hex: 0x8A93A6)),
            LayerBand(layer: .test, color: RGBA(hex: 0xB8FF7A)),
            LayerBand(layer: .unknown, color: RGBA(hex: 0xA7ADBF))
        ],
        code: .standard
    )

    /// Tinted theme derived from a user hue. Environment keeps low saturation / lightness so code stays legible.
    public static func tinted(hue rawHue: Double, name: String? = nil) -> ConstellateTheme {
        let hue = ConstellateTheme.safeEnvironmentHue(rawHue, avoiding: CodePalette.standard.reservedHues)
        var t = ConstellateTheme.dark
        t.name = name ?? "Tint \(Int(hue.rounded()))°"
        t.mode = .tinted(hue: rawHue)
        t.skyTop = RGBA(hue: hue, saturation: 0.30, lightness: 0.06)
        t.skyHorizon = RGBA(hue: hue, saturation: 0.34, lightness: 0.17)
        t.skyBottom = RGBA(hue: hue, saturation: 0.28, lightness: 0.07)
        t.floor = RGBA(hue: hue, saturation: 0.22, lightness: 0.08)
        t.floorGrid = RGBA(hue: hue, saturation: 0.26, lightness: 0.28, alpha: 0.55)
        t.fog = RGBA(hue: hue, saturation: 0.30, lightness: 0.10)
        t.orbHalo = RGBA(hue: hue, saturation: 0.75, lightness: 0.72)
        t.orbBands = [
            RGBA(hue: hue, saturation: 0.8, lightness: 0.7),
            RGBA(hue: hue + 40, saturation: 0.7, lightness: 0.7),
            RGBA(hue: hue - 40, saturation: 0.7, lightness: 0.72),
            RGBA(hex: 0xFFFFFF)
        ]
        t.avatarAccent = RGBA(hue: hue + 180, saturation: 0.6, lightness: 0.68)
        return t
    }

    public static let presets: [ConstellateTheme] = [
        .dark,
        .tinted(hue: 210, name: "Ocean"),
        .tinted(hue: 150, name: "Moss"),
        .tinted(hue: 20, name: "Ember"),
        .tinted(hue: 275, name: "Nebula")
    ]

    // MARK: Rules

    /// Moves `hue` at least `minDistance` degrees away from any reserved code hue.
    public static func safeEnvironmentHue(_ hue: Double, avoiding reserved: [Double], minDistance: Double = 22) -> Double {
        var h = ((hue.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360)
        for _ in 0..<12 {
            guard let clash = reserved.first(where: { hueDistance($0, h) < minDistance }) else { return h }
            // push away from the clash in the shorter direction
            let delta = signedHueDelta(from: clash, to: h)
            h = ((clash + (delta >= 0 ? minDistance : -minDistance)) + 360).truncatingRemainder(dividingBy: 360)
        }
        return h
    }

    public static func hueDistance(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(d, 360 - d)
    }

    static func signedHueDelta(from a: Double, to b: Double) -> Double {
        var d = (b - a).truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return d
    }

    public struct Violation: Hashable, Sendable, CustomStringConvertible {
        public var rule: String
        public var detail: String
        public var description: String { "\(rule): \(detail)" }
    }

    /// Checks the legibility rules. An empty array means the theme is valid.
    public func validate() -> [Violation] {
        var v: [Violation] = []
        for (label, c) in [("skyTop", skyTop), ("skyHorizon", skyHorizon), ("skyBottom", skyBottom), ("floor", floor), ("floorGrid", floorGrid), ("fog", fog)] {
            let hsl = c.hsl
            if c.chroma > 0.16 { v.append(Violation(rule: "env.chroma", detail: "\(label) chroma \(c.chroma) > 0.16")) }
            if hsl.lightness > 0.30 { v.append(Violation(rule: "env.lightness", detail: "\(label) lightness \(hsl.lightness) > 0.30")) }
            if c.chroma > 0.10 {
                for rh in code.reservedHues where ConstellateTheme.hueDistance(rh, hsl.hue) < 20 {
                    v.append(Violation(rule: "env.hueClash", detail: "\(label) hue \(Int(hsl.hue)) within 20° of code hue \(Int(rh))"))
                }
            }
        }
        for (label, c) in [("keyword", code.keyword), ("type", code.type), ("function", code.function), ("string", code.string), ("number", code.number)] {
            let hsl = c.hsl
            if c.chroma < 0.35 { v.append(Violation(rule: "code.chroma", detail: "\(label) chroma \(c.chroma) < 0.35")) }
            if hsl.lightness < 0.62 { v.append(Violation(rule: "code.lightness", detail: "\(label) lightness \(hsl.lightness) < 0.62")) }
            let cr = c.contrastRatio(against: code.cardBackground)
            if cr < 4.5 { v.append(Violation(rule: "code.contrast", detail: "\(label) vs card \(cr) < 4.5")) }
        }
        let skyContrast = code.plain.contrastRatio(against: skyHorizon)
        if skyContrast < 7 { v.append(Violation(rule: "code.skyContrast", detail: "plain vs skyHorizon \(skyContrast) < 7")) }
        return v
    }

    public func color(for layer: ArchitectureLayer) -> RGBA {
        layerBands.first { $0.layer == layer }?.color ?? code.plain
    }

    /// Relation colours are fixed across themes (like the code palette) so the legend never changes meaning;
    /// routed through the theme so a future theme can override them in one place.
    public func color(for relation: RelationKind) -> RGBA {
        relation.style.color
    }

    public func color(for edge: EdgeKind) -> RGBA {
        switch edge {
        case .contains: edgeContains
        case .imports: edgeImports
        case .references: edgeReferences
        case .inherits: edgeInherits
        case .calls: edgeCalls
        }
    }
}
