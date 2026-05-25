// ABOUTME: Tests OutlineFlags.enabled(for:) maps each item type to its own flag,
// ABOUTME: so the renderer outlines text, arrows, and pen strokes independently.

import Testing

@Suite("OutlineFlags")
struct OutlineFlagsTests {
    private func stroke() -> CanvasItem {
        .stroke(Stroke(id: "s", color: RGBA(r: 0, g: 0, b: 0, a: 1), width: 10, transform: .identity,
                       points: [StrokePoint(x: 0, y: 0)], pointerType: .mouse,
                       pressureEnabled: false, createdAt: 0))
    }
    private func text() -> CanvasItem {
        .text(TextItem(id: "t", string: "x", fontName: "Helvetica", fontSize: 20,
                       color: RGBA(r: 0, g: 0, b: 0, a: 1), transform: .identity,
                       bounds: Size(width: 20, height: 20), createdAt: 0))
    }
    private func arrow() -> CanvasItem {
        .arrow(ArrowItem(id: "a", color: RGBA(r: 0, g: 0, b: 0, a: 1), width: 10, transform: .identity,
                         tail: Point(x: 0, y: 0), head: Point(x: 10, y: 0), createdAt: 0))
    }

    @Test("each item type reads its own flag")
    func perType() {
        let flags = OutlineFlags(text: true, arrow: false, pen: true)
        #expect(flags.enabled(for: text()) == true)
        #expect(flags.enabled(for: arrow()) == false)
        #expect(flags.enabled(for: stroke()) == true)
    }

    @Test("none disables every type")
    func none() {
        #expect(OutlineFlags.none.enabled(for: text()) == false)
        #expect(OutlineFlags.none.enabled(for: arrow()) == false)
        #expect(OutlineFlags.none.enabled(for: stroke()) == false)
    }
}
