// ABOUTME: Tests for eraseStroke — delete-by-id with undo support.
// ABOUTME: Covers removal from doc, itemOrder, and undo restoration at original index.

import Testing

@Suite("Editor.eraseStroke")
@MainActor
struct EditorEraseTests {
    private func makeEditor() -> Editor {
        Editor(clock: VirtualClock(now: 0), ids: SeededIdGenerator(prefix: "s"))
    }

    @Test("erases an existing stroke and removes from itemOrder")
    func erases() {
        let e = makeEditor()
        _ = e.startStroke(color: RGBA(r: 0, g: 0, b: 0, a: 1), width: 1, pointerType: .mouse)
        e.endStroke()
        let did = e.eraseStroke("s-1")
        #expect(did)
        #expect(e.doc.items.isEmpty)
        #expect(e.doc.itemOrder.isEmpty)
    }

    @Test("returns false for unknown stroke")
    func unknown() {
        let e = makeEditor()
        #expect(e.eraseStroke("nope") == false)
    }

    @Test("undo of erase restores the stroke at its original index")
    func undoRestoresAtIndex() {
        let e = makeEditor()
        _ = e.startStroke(color: RGBA(r: 0, g: 0, b: 0, a: 1), width: 1, pointerType: .mouse)
        e.endStroke()
        _ = e.startStroke(color: RGBA(r: 0, g: 0, b: 0, a: 1), width: 1, pointerType: .mouse)
        e.endStroke()
        #expect(e.doc.itemOrder == ["s-1", "s-2"])
        _ = e.eraseStroke("s-1")
        #expect(e.doc.itemOrder == ["s-2"])
        _ = e.undo()
        #expect(e.doc.itemOrder == ["s-1", "s-2"])
    }
}
