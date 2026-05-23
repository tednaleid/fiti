// ABOUTME: Smoke test for the CoreText-backed measurer — plausible sizes and a
// ABOUTME: caret index within range. Not glyph-exact.

import AppKit
import Testing

@Suite("CoreTextMeasurer")
struct CoreTextMeasurerTests {
    @Test("measure returns positive size; longer string is wider")
    func measure() {
        let m = CoreTextMeasurer()
        let a = m.measure(string: "i", fontName: "Helvetica", fontSize: 24)
        let b = m.measure(string: "wwww", fontName: "Helvetica", fontSize: 24)
        #expect(a.width > 0 && a.height > 0)
        #expect(b.width > a.width)
    }

    @Test("caretIndex is within [0, count]")
    func caret() {
        let m = CoreTextMeasurer()
        let i = m.caretIndex(at: Point(x: 1000, y: 0), string: "abc", fontName: "Helvetica", fontSize: 24)
        #expect(i >= 0 && i <= 3)
    }
}
