// ABOUTME: Tests for transient selection lifetime (clear on Space release with
// ABOUTME: mid-gesture deferral) and tool-gated Delete.

import Testing

@Suite("Selection lifetime")
@MainActor
struct SelectionLifetimeTests {
    // swiftlint:disable:next large_tuple
    private func setup() -> (AppController, Editor, [StrokeId]) {
        let clock = VirtualClock()
        let editor = Editor(clock: clock, ids: SeededIdGenerator(prefix: "s"))
        let c = AppController(editor: editor, window: RecordingWindow(),
                              detector: RecordingStationaryDetector(), clock: clock,
                              ticker: RecordingFadeTicker())
        c.activate()
        c.pointerDown(StrokePoint(x: 10, y: 10)); c.pointerMoved(StrokePoint(x: 30, y: 20)); c.pointerUp()
        c.currentTool = .selection
        return (c, editor, editor.doc.itemOrder)
    }

    @Test("releasing Space (tool → pen) clears the selection")
    func releaseClears() {
        let (c, _, ids) = setup()
        c.selectedStrokeIds = [ids[0]]
        c.currentTool = .pen
        #expect(c.selectedStrokeIds == [])
        #expect(c.selectionBox == nil)
    }

    @Test("releasing Space mid-gesture defers the clear until pointerUp")
    func deferredClear() {
        let (c, editor, ids) = setup()
        c.selectedStrokeIds = ids
        c.pointerDown(StrokePoint(x: 20, y: 10))     // grab the group (inside box)
        c.pointerMoved(StrokePoint(x: 25, y: 10))
        c.currentTool = .pen                          // Space released mid-drag
        #expect(c.selectedStrokeIds == ids)           // NOT cleared yet
        c.pointerUp()                                 // gesture ends → deferred clear applies
        #expect(c.selectedStrokeIds == [])
        #expect(editor.doc.items[ids[0]]?.transform.x == 5)  // the drag still committed
    }

    @Test("Delete in selection mode with no selection is a no-op")
    func deleteNoSelectionNoOp() {
        let (c, editor, _) = setup()
        let before = editor.doc.items.count
        c.run(.clear)
        #expect(editor.doc.items.count == before)   // nothing cleared
    }

    @Test("Delete in pen mode clears everything")
    func deletePenClearsAll() {
        let (c, editor, _) = setup()
        c.currentTool = .pen
        c.run(.clear)
        #expect(editor.doc.items.isEmpty)
    }
}
