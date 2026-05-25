// ABOUTME: Tests fitiBrushDabImage — the shared dab drawing used by both the
// ABOUTME: brush cursor and the size picker's pen preview.

import AppKit
import Testing

@Suite("fitiBrushDabImage")
@MainActor
struct BrushDabImageTests {
    @Test("image size is the fill diameter (width/2) plus the outline on both sides")
    func sizeMatchesSpec() {
        // diameter 10 -> fill 5, +1pt outline each side -> 7x7.
        let img = fitiBrushDabImage(color: RGBA(r: 1, g: 0, b: 0, a: 1),
                                    diameter: 10, outlineWidth: 1)
        #expect(abs(img.size.width - 7) < 0.01)
        #expect(abs(img.size.height - 7) < 0.01)
    }

    @Test("tiny diameters still produce a positive-size image")
    func tinyClamps() {
        let img = fitiBrushDabImage(color: RGBA(r: 0, g: 0, b: 0, a: 1),
                                    diameter: 1, outlineWidth: 1)
        #expect(img.size.width > 0)
    }
}
