// ABOUTME: Verifies the deterministic monospace fake used to test text geometry.
// ABOUTME: Covers single-line measure, multi-line measure, and caret index mapping.

import Testing

@Suite("FakeTextMeasurer")
struct FakeTextMeasurerTests {
    @Test("single line: width = chars * fontSize/2, height = fontSize")
    func singleLine() {
        let m = FakeTextMeasurer()
        #expect(m.measure(string: "hello world", fontName: "Helvetica", fontSize: 24)
                == Size(width: 132, height: 24))
    }

    @Test("newline adds 1.5x font height; width is widest line")
    func multiLine() {
        let m = FakeTextMeasurer()
        let s = m.measure(string: "ab\ncdef", fontName: "Helvetica", fontSize: 20)
        #expect(s.width == 40)   // "cdef" = 4 * 10
        #expect(s.height == 50)  // 20 + 1*20*1.5
    }

    @Test("caretIndex maps a click to a column on the right line")
    func caret() {
        let m = FakeTextMeasurer()
        // "abc" @24 -> charWidth 12; x=30 -> Int(30/12)=2 (clamped to len)
        #expect(m.caretIndex(at: Point(x: 30, y: 5), string: "abc", fontName: "Helvetica", fontSize: 24) == 2)
    }
}
