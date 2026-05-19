// ABOUTME: Tests for QuickPickPalette — the 8 named quick-pick colors shared
// ABOUTME: between ToolbarController, the menubar Drawing submenu, and tooltips.

import Testing

@Suite("QuickPickPalette")
struct QuickPickPaletteTests {
    @Test("palette has exactly 8 entries")
    func paletteSize() {
        #expect(QuickPickPalette.colors.count == 8)
    }

    @Test("each color has a non-empty name")
    func allColorsNamed() {
        for color in QuickPickPalette.colors {
            #expect(!color.name.isEmpty)
        }
    }

    @Test("RGB values are in 0...1")
    func rgbRange() {
        for color in QuickPickPalette.colors {
            #expect(color.r >= 0 && color.r <= 1)
            #expect(color.g >= 0 && color.g <= 1)
            #expect(color.b >= 0 && color.b <= 1)
        }
    }

    @Test("first entry is Black at (0,0,0)")
    func firstIsBlack() {
        let first = QuickPickPalette.colors[0]
        #expect(first.name == "Black")
        #expect(first.r == 0)
        #expect(first.g == 0)
        #expect(first.b == 0)
    }

    @Test("third entry is Red matching the original toolbar palette")
    func redIsCorrect() {
        let red = QuickPickPalette.colors[2]
        #expect(red.name == "Red")
        #expect(abs(red.r - 224.0/255.0) < 0.0001)
        #expect(abs(red.g - 49.0/255.0) < 0.0001)
        #expect(abs(red.b - 49.0/255.0) < 0.0001)
    }

    @Test("eighth entry is Violet")
    func eighthIsViolet() {
        let v = QuickPickPalette.colors[7]
        #expect(v.name == "Violet")
        #expect(abs(v.r - 156.0/255.0) < 0.0001)
        #expect(abs(v.g - 54.0/255.0) < 0.0001)
        #expect(abs(v.b - 181.0/255.0) < 0.0001)
    }
}
