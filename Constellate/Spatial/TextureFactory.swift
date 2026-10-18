import ConstellateKit
import CoreGraphics
import CoreText
import Foundation

/// Wrapper so CoreGraphics images can cross task boundaries (they are immutable).
nonisolated struct SendableImage: @unchecked Sendable {
    let image: CGImage
}

/// CoreGraphics renderers for every procedural texture: code cards, sky dome, floor grid, particle dot.
/// All functions are pure and safe to call from `Task.detached`.
nonisolated enum TextureFactory {

    static let cardWidth = 512
    static let cardHeight = 352

    // MARK: - Context

    static func makeContext(width: Int, height: Int) -> CGContext? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                         space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    /// Draws one line of text with CoreText. Returns the typographic width used.
    @discardableResult
    static func drawText(_ text: String, at origin: CGPoint, font: CTFont, color: CGColor, maxWidth: CGFloat, in ctx: CGContext) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
        ]
        var line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        if CTLineGetTypographicBounds(line, nil, nil, nil) > maxWidth,
           let truncated = CTLineCreateTruncatedLine(line, maxWidth, .end, nil) {
            line = truncated
        }
        ctx.textMatrix = .identity
        ctx.textPosition = origin
        CTLineDraw(line, ctx)
        return CTLineGetTypographicBounds(line, nil, nil, nil)
    }

    // MARK: - Code cards

    /// Title + kind + a few highlighted code lines on the card background, with a layer-band stripe and border.
    static func cardImage(title: String, subtitle: String, lines: [String], palette: CodePalette, band: RGBA) -> SendableImage? {
        let w = cardWidth, h = cardHeight
        guard let ctx = makeContext(width: w, height: h) else { return nil }
        let W = CGFloat(w), H = CGFloat(h)
        let radius: CGFloat = 22
        let rect = CGRect(x: 0, y: 0, width: W, height: H)
        let path = CGPath(roundedRect: rect.insetBy(dx: 2, dy: 2), cornerWidth: radius, cornerHeight: radius, transform: nil)

        ctx.clear(rect)
        ctx.addPath(path)
        ctx.setFillColor(palette.cardBackground.withAlpha(1).cgColor)
        ctx.fillPath()

        // Band stripe on the left edge, clipped to the rounded shape.
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.setFillColor(band.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: 12, height: H))
        // Soft band glow across the header.
        if let space = CGColorSpace(name: CGColorSpace.sRGB),
           let gradient = CGGradient(colorsSpace: space, colors: [band.withAlpha(0.22).cgColor, band.withAlpha(0).cgColor] as CFArray, locations: [0, 1]) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: H), end: CGPoint(x: 0, y: H - 90), options: [])
        }
        ctx.restoreGState()

        // Border.
        ctx.addPath(path)
        ctx.setStrokeColor(band.withAlpha(0.75).cgColor)
        ctx.setLineWidth(3)
        ctx.strokePath()

        let titleFont = CTFontCreateWithName("Menlo-Bold" as CFString, 24, nil)
        let subFont = CTFontCreateWithName("Menlo" as CFString, 14, nil)
        let codeFont = CTFontCreateWithName("Menlo" as CFString, 15, nil)
        let left: CGFloat = 30
        drawText(title, at: CGPoint(x: left, y: H - 40), font: titleFont, color: palette.plain.cgColor, maxWidth: W - left - 20, in: ctx)
        drawText(subtitle, at: CGPoint(x: left, y: H - 62), font: subFont, color: palette.comment.cgColor, maxWidth: W - left - 20, in: ctx)

        ctx.setStrokeColor(palette.cardBorder.cgColor)
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: left, y: H - 76))
        ctx.addLine(to: CGPoint(x: W - 20, y: H - 76))
        ctx.strokePath()

        var y = H - 100
        let lineHeight: CGFloat = 20
        for raw in lines {
            guard y > 14 else { break }
            let line = Substring(raw.replacingOccurrences(of: "\t", with: "    "))
            var x = left
            for token in SyntaxHighlighter.tokenize(line: line) {
                guard x < W - 24 else { break }
                let color = SyntaxHighlighter.color(for: token.kind, palette: palette).cgColor
                let advance = drawText(String(token.text), at: CGPoint(x: x, y: y), font: codeFont, color: color, maxWidth: W - 24 - x, in: ctx)
                x += advance
            }
            y -= lineHeight
        }
        return ctx.makeImage().map(SendableImage.init)
    }

    /// Shared card for nodes that did not get a bespoke texture (large projects).
    static func genericCardImage(kindLabel: String, palette: CodePalette, band: RGBA) -> SendableImage? {
        cardImage(title: kindLabel, subtitle: "…", lines: ["// tap to load preview"], palette: palette, band: band)
    }

    // MARK: - Sky

    /// Equirectangular sky. If `tintSource` (grayscale luminance map) is given it is multiplied by the theme hue;
    /// otherwise a procedural gradient from the theme colours with a sparse star field.
    static func skyImage(theme: ConstellateTheme, tintSource: SendableImage?, width: Int = 2048) -> SendableImage? {
        let height = width / 2
        guard let ctx = makeContext(width: width, height: height), let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let W = CGFloat(width), H = CGFloat(height)
        let full = CGRect(x: 0, y: 0, width: W, height: H)

        if let tint = tintSource {
            ctx.draw(tint.image, in: full)
            let hue = theme.skyHorizon.hsl.hue
            ctx.setBlendMode(.multiply)
            ctx.setFillColor(RGBA(hue: hue, saturation: 0.45, lightness: 0.42).cgColor)
            ctx.fill(full)
            ctx.setBlendMode(.normal)
        } else {
            let colors: [CGColor] = [
                theme.skyBottom.cgColor,
                theme.skyBottom.mixed(with: theme.skyHorizon, 0.5).cgColor,
                theme.skyHorizon.cgColor,
                theme.skyHorizon.mixed(with: theme.skyTop, 0.55).cgColor,
                theme.skyTop.cgColor
            ]
            let locations: [CGFloat] = [0, 0.40, 0.5, 0.68, 1]
            if let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations) {
                ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: H), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            }
            // Horizon haze in the grid colour.
            let haze = theme.floorGrid.withAlpha(1)
            if let glow = CGGradient(colorsSpace: space, colors: [haze.withAlpha(0).cgColor, haze.withAlpha(0.28).cgColor, haze.withAlpha(0).cgColor] as CFArray, locations: [0, 0.5, 1]) {
                ctx.drawLinearGradient(glow, start: CGPoint(x: 0, y: H * 0.44), end: CGPoint(x: 0, y: H * 0.56), options: [])
            }
            // Stars: tiny and dim so the dome never competes with code.
            var rng = SeededGenerator(seed: 0xC0D3)
            for _ in 0..<900 {
                let x = CGFloat.random(in: 0..<W, using: &rng)
                let y = H * (0.53 + 0.47 * pow(CGFloat.random(in: 0..<1, using: &rng), 0.7))
                let r = CGFloat.random(in: 0.5...1.2, using: &rng)
                let a = CGFloat.random(in: 0.18...0.6, using: &rng)
                ctx.setFillColor(CGColor(gray: 1, alpha: a))
                ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            }
        }
        return ctx.makeImage().map(SendableImage.init)
    }

    // MARK: - Floor

    /// White grid on transparent with a radial fade → a disc when mapped on a square plane.
    static func floorGridImage(size: Int = 1024, divisions: Int = 24) -> SendableImage? {
        guard let ctx = makeContext(width: size, height: size), let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let s = CGFloat(size)
        ctx.clear(CGRect(x: 0, y: 0, width: s, height: s))
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.6))
        ctx.setLineWidth(2)
        for k in 0...divisions {
            let p = s * CGFloat(k) / CGFloat(divisions)
            ctx.move(to: CGPoint(x: p, y: 0)); ctx.addLine(to: CGPoint(x: p, y: s))
            ctx.move(to: CGPoint(x: 0, y: p)); ctx.addLine(to: CGPoint(x: s, y: p))
        }
        ctx.strokePath()
        // Concentric rings every 2 m (plane is 24 m wide → 12 rings).
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.35))
        ctx.setLineWidth(1.5)
        for ring in 1...6 {
            let r = s / 2 * CGFloat(ring) / 6
            ctx.strokeEllipse(in: CGRect(x: s / 2 - r, y: s / 2 - r, width: r * 2, height: r * 2))
        }
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.9))
        ctx.setLineWidth(3)
        ctx.move(to: CGPoint(x: s / 2, y: 0)); ctx.addLine(to: CGPoint(x: s / 2, y: s))
        ctx.move(to: CGPoint(x: 0, y: s / 2)); ctx.addLine(to: CGPoint(x: s, y: s / 2))
        ctx.strokePath()
        if let fade = CGGradient(colorsSpace: space, colors: [CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 0)] as CFArray, locations: [0, 0.3, 1]) {
            ctx.setBlendMode(.destinationIn)
            let c = CGPoint(x: s / 2, y: s / 2)
            ctx.drawRadialGradient(fade, startCenter: c, startRadius: 0, endCenter: c, endRadius: s / 2, options: [])
            ctx.setBlendMode(.normal)
        }
        return ctx.makeImage().map(SendableImage.init)
    }

    // MARK: - Particles

    static func glowDot(size: Int = 64) -> SendableImage? {
        guard let ctx = makeContext(width: size, height: size), let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let s = CGFloat(size)
        ctx.clear(CGRect(x: 0, y: 0, width: s, height: s))
        if let g = CGGradient(colorsSpace: space, colors: [CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 0.35), CGColor(gray: 1, alpha: 0)] as CFArray, locations: [0, 0.35, 1]) {
            let c = CGPoint(x: s / 2, y: s / 2)
            ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: s / 2, options: [])
        }
        return ctx.makeImage().map(SendableImage.init)
    }

    /// Loads a PNG from disk into a CGImage (used for the Blender textures).
    static func loadPNG(at url: URL) -> SendableImage? {
        guard let provider = CGDataProvider(url: url as CFURL),
              let image = CGImage(pngDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        return SendableImage(image: image)
    }
}

/// Deterministic generator so procedural textures look identical on every launch.
nonisolated struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
