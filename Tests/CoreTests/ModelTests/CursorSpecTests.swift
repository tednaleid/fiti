// ABOUTME: Tests for CursorSpec data and adaptive outline-color helper.

import Testing

@Suite("CursorSpec")
struct CursorSpecTests {
    @Test("equal specs are ==")
    func equality() {
        let red = RGBA(r: 1, g: 0, b: 0, a: 0.8)
        #expect(CursorSpec.brush(color: red, diameter: 10) == CursorSpec.brush(color: red, diameter: 10))
    }

    @Test("different diameter is !=")
    func diameterDiffers() {
        let red = RGBA(r: 1, g: 0, b: 0, a: 1)
        #expect(CursorSpec.brush(color: red, diameter: 10) != CursorSpec.brush(color: red, diameter: 11))
    }

    @Test("dark fill picks white outline at 50% alpha")
    func darkFillGetsWhiteOutline() {
        // BT.601 luminance is heavily weighted by green; bright red registers as dark.
        let red = RGBA(r: 1, g: 0, b: 0, a: 1)
        let outline = CursorSpec.outlineColor(for: red)
        #expect(outline == RGBA(r: 1, g: 1, b: 1, a: 0.5))
    }

    @Test("bright fill picks black outline at 50% alpha")
    func brightFillGetsBlackOutline() {
        let green = RGBA(r: 0, g: 1, b: 0, a: 1)
        let outline = CursorSpec.outlineColor(for: green)
        #expect(outline == RGBA(r: 0, g: 0, b: 0, a: 0.5))
    }

    @Test("pure white fill picks black outline at 50% alpha")
    func whiteFillGetsBlackOutline() {
        let white = RGBA(r: 1, g: 1, b: 1, a: 1)
        #expect(CursorSpec.outlineColor(for: white) == RGBA(r: 0, g: 0, b: 0, a: 0.5))
    }

    @Test("pure black fill picks white outline at 50% alpha")
    func blackFillGetsWhiteOutline() {
        let black = RGBA(r: 0, g: 0, b: 0, a: 1)
        #expect(CursorSpec.outlineColor(for: black) == RGBA(r: 1, g: 1, b: 1, a: 0.5))
    }

    @Test("alpha does not influence outline choice — low-opacity color keeps its identity")
    func alphaIgnoredForLuminance() {
        let translucentRed = RGBA(r: 1, g: 0, b: 0, a: 0.1)
        let opaqueRed = RGBA(r: 1, g: 0, b: 0, a: 1)
        #expect(CursorSpec.outlineColor(for: translucentRed) == CursorSpec.outlineColor(for: opaqueRed))
    }

    @Test("outline is semi-transparent so it stays subtle against any background")
    func outlineAlpha() {
        let translucent = RGBA(r: 1, g: 0, b: 0, a: 0.05)
        let outline = CursorSpec.outlineColor(for: translucent)
        #expect(outline.a == 0.5)
    }
}
