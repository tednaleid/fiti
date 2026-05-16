// ABOUTME: Tests for clear — empties the doc but is undo-able.
// ABOUTME: Exercises the multi-stroke restoreStrokes path in applyInverse.

import Testing

@Suite("Editor.clear")
struct EditorClearTests {
    private func makeEditor() -> Editor {
        Editor(clock: VirtualClock(now: 0), ids: SeededIdGenerator(prefix: "s"))
    }

    @Test("empties doc")
    func empties() {
        let e = makeEditor()
        _ = e.startStroke(color: RGBA(r: 0, g: 0, b: 0, a: 1), width: 1, pointerType: .mouse)
        e.endStroke()
        _ = e.startStroke(color: RGBA(r: 0, g: 0, b: 0, a: 1), width: 1, pointerType: .mouse)
        e.endStroke()
        e.clear()
        #expect(e.doc.strokes.isEmpty)
        #expect(e.doc.strokeOrder.isEmpty)
    }

    @Test("undo restores all strokes at their original strokeOrder positions")
    func undoRestoresAll() {
        let e = makeEditor()
        _ = e.startStroke(color: RGBA(r: 0, g: 0, b: 0, a: 1), width: 1, pointerType: .mouse)
        e.endStroke()
        _ = e.startStroke(color: RGBA(r: 0, g: 0, b: 0, a: 1), width: 1, pointerType: .mouse)
        e.endStroke()
        let before = e.doc
        e.clear()
        _ = e.undo()
        #expect(e.doc == before)
    }

    @Test("clear on an empty doc is a no-op (doesn't push undo)")
    func clearEmpty() {
        let e = makeEditor()
        e.clear()
        #expect(e.undoStack.isEmpty)
    }
}
