import ConstellateKit
import CoreGraphics
import SwiftUI

#if canImport(UIKit)
import UIKit
/// Platform colour used by RealityKit materials (UIColor on iPad/visionOS, NSColor on Mac).
typealias PlatformColor = UIColor
#elseif canImport(AppKit)
import AppKit
typealias PlatformColor = NSColor
#endif

/// Bridges the Kit's platform-neutral `RGBA` to the colour types each framework wants.
extension RGBA {
    var cgColor: CGColor {
        CGColor(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a))
    }

    var platformColor: PlatformColor {
        PlatformColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a))
    }

    var swiftUIColor: Color {
        Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    /// Linear blend; `t == 1` returns `other`.
    func mixed(with other: RGBA, _ t: Double) -> RGBA {
        let k = min(max(t, 0), 1)
        return RGBA(r: r + (other.r - r) * k, g: g + (other.g - g) * k, b: b + (other.b - b) * k, a: a + (other.a - a) * k)
    }

    /// Shifts the hue by `degrees`, keeping saturation and lightness.
    func shiftedHue(by degrees: Double) -> RGBA {
        let c = hsl
        return RGBA(hue: c.hue + degrees, saturation: c.saturation, lightness: c.lightness, alpha: a)
    }

    func lightened(_ amount: Double) -> RGBA { mixed(with: RGBA(hex: 0xFFFFFF), amount) }

    static let white = RGBA(hex: 0xFFFFFF)
    static let black = RGBA(hex: 0x000000)
}
