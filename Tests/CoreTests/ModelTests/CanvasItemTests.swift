// ABOUTME: Tests for CanvasItem's shared accessors across the stroke and text
// ABOUTME: cases — id, transform get/set, createdAt, color.

import Testing

@Suite("CanvasItem")
struct CanvasItemTests {
    private func sampleStroke(id: ItemId = "s1") -> Stroke {
        Stroke(id: id, color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 6,
               transform: .identity, points: [StrokePoint(x: 0, y: 0)],
               pointerType: .mouse, pressureEnabled: false, createdAt: 10)
    }
    private func sampleText(id: ItemId = "t1") -> TextItem {
        TextItem(id: id, string: "hi", fontName: "Helvetica", fontSize: 24,
                 color: RGBA(r: 0, g: 0, b: 1, a: 0.8), transform: .identity,
                 bounds: Size(width: 24, height: 24), createdAt: 20)
    }

    @Test("id, createdAt, and color read through both cases")
    func sharedReads() {
        let s = CanvasItem.stroke(sampleStroke())
        let t = CanvasItem.text(sampleText())
        #expect(s.id == "s1")
        #expect(t.id == "t1")
        #expect(s.createdAt == 10)
        #expect(t.createdAt == 20)
        #expect(s.color == RGBA(r: 1, g: 0, b: 0, a: 1))
        #expect(t.color == RGBA(r: 0, g: 0, b: 1, a: 0.8))
    }

    @Test("transform set rewraps the same case")
    func transformSet() {
        var s = CanvasItem.stroke(sampleStroke())
        s.transform = Transform(x: 5, y: 6, scale: 2, rotate: 90)
        #expect(s.transform == Transform(x: 5, y: 6, scale: 2, rotate: 90))
        if case .stroke(let inner) = s { #expect(inner.transform.x == 5) } else { Issue.record("expected stroke") }

        var t = CanvasItem.text(sampleText())
        t.transform = Transform(x: 1, y: 2, scale: 1, rotate: 0)
        #expect(t.transform == Transform(x: 1, y: 2, scale: 1, rotate: 0))
        if case .text(let inner) = t { #expect(inner.transform.y == 2) } else { Issue.record("expected text") }
    }
}
