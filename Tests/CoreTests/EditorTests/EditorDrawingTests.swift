// ABOUTME: Tests for appendPoint + endStroke — the rest of the drawing path.
// ABOUTME: Covers appending points to in-progress strokes and finalizing them.

import Testing

@Suite("Editor draw cycle")
@MainActor
struct EditorDrawingTests {
    private func makeEditor() -> Editor {
        Editor(clock: VirtualClock(now: 0), ids: SeededIdGenerator(prefix: "s"))
    }

    @Test("appendPoint appends to the in-progress stroke")
    func appendsToCurrent() {
        let e = makeEditor()
        _ = e.startStroke(color: RGBA(r: 0, g: 0, b: 0, a: 1), width: 1, pointerType: .mouse)
        e.appendPoint(StrokePoint(x: 0, y: 0))
        e.appendPoint(StrokePoint(x: 5, y: 5))
        #expect(e.doc.strokes["s-1"]?.points.count == 2)
    }

    @Test("appendPoint is a no-op when no stroke is in progress")
    func appendNoOp() {
        let e = makeEditor()
        e.appendPoint(StrokePoint(x: 0, y: 0))
        #expect(e.doc.strokes.isEmpty)
    }

    @Test("endStroke clears currentStrokeId; doc retains the stroke")
    func endStrokeFreezes() {
        let e = makeEditor()
        _ = e.startStroke(color: RGBA(r: 0, g: 0, b: 0, a: 1), width: 1, pointerType: .mouse)
        e.appendPoint(StrokePoint(x: 1, y: 1))
        e.endStroke()
        #expect(e.currentStrokeId == nil)
        #expect(e.doc.strokes["s-1"]?.points.count == 1)
    }
}
