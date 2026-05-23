// ABOUTME: Tests for undo/redo of completed strokes — the round-trip.
// ABOUTME: Verifies stack semantics and that doc state is restored byte-identically.

import Testing

@Suite("Editor undo / redo")
@MainActor
struct EditorUndoRedoTests {
    private func makeEditor() -> Editor {
        Editor(clock: VirtualClock(now: 0), ids: SeededIdGenerator(prefix: "s"))
    }

    private func drawOne(_ e: Editor) {
        _ = e.startStroke(color: RGBA(r: 0, g: 0, b: 0, a: 1), width: 1, pointerType: .mouse)
        e.appendPoint(StrokePoint(x: 1, y: 1))
        e.endStroke()
    }

    @Test("undo removes the last completed stroke")
    func undoRemoves() {
        let e = makeEditor()
        drawOne(e)
        #expect(e.doc.items.count == 1)
        let did = e.undo()
        #expect(did)
        #expect(e.doc.items.isEmpty)
        #expect(e.doc.itemOrder.isEmpty)
    }

    @Test("redo restores the undone stroke byte-identically")
    func redoRestores() {
        let e = makeEditor()
        drawOne(e)
        let before = e.doc
        _ = e.undo()
        _ = e.redo()
        #expect(e.doc == before)
    }

    @Test("undo with empty stack returns false")
    func undoEmpty() {
        let e = makeEditor()
        #expect(e.undo() == false)
    }

    @Test("a new stroke after undo clears the redo stack")
    func newStrokeClearsRedo() {
        let e = makeEditor()
        drawOne(e)
        _ = e.undo()
        #expect(e.redoStack.isEmpty == false)
        drawOne(e)
        #expect(e.redoStack.isEmpty)
    }
}
