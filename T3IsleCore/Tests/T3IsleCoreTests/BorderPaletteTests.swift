import XCTest
@testable import T3IsleCore

final class BorderPaletteTests: XCTestCase {
    func testEveryThemeOffersFiveDistinctSwatches() {
        XCTAssertEqual(BorderPalette.themes.map(\.title),
                       ["Catppuccin Mocha", "Tokyo Night", "Rosé Pine", "Nord", "Gruvbox Dark", "Dracula"])
        for theme in BorderPalette.themes {
            XCTAssertEqual(theme.swatches.count, 5, theme.title)
        }
        let hexes = BorderPalette.themes.flatMap(\.swatches).map(\.hex) + [BorderPalette.standardHex]
        XCTAssertEqual(Set(hexes).count, hexes.count)
    }

    func testSwatchLabelUsesShortThemeName() {
        let peach = BorderPalette.themes[0].swatches[0]
        XCTAssertEqual(peach.label, "Mocha · Peach")
        XCTAssertEqual(peach.hex, "#FAB387")
    }

    func testChoiceRecognisesStandardPresetAndCustomHexes() {
        XCTAssertEqual(BorderPalette.choice(forHex: "#ff8a1f"), .standard)
        guard case .preset(let swatch) = BorderPalette.choice(forHex: "7aa2f7") else {
            return XCTFail("Tokyo Night blue should match its preset")
        }
        XCTAssertEqual(swatch.label, "Tokyo Night · Blue")
        XCTAssertEqual(BorderPalette.choice(forHex: "#12abef"), .custom(hex: "#12ABEF"))
    }
}
