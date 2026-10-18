import Testing
@testable import ConstellateKit

@Suite struct ThemeTests {
    @Test func darkThemeIsValid() {
        #expect(ConstellateTheme.dark.validate().isEmpty)
    }

    @Test(arguments: Array(stride(from: 0.0, to: 360.0, by: 15.0)))
    func tintedThemesAreValid(hue: Double) {
        let t = ConstellateTheme.tinted(hue: hue)
        #expect(t.validate().isEmpty, "hue \(hue): \(t.validate())")
    }
}
