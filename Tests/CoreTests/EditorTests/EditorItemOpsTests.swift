// ABOUTME: Tests for the item-generic Editor surface — addItem, replaceItem,
// ABOUTME: and replaceItems undo round-trips, alongside the existing stroke path.

import Testing

@MainActor
@Suite("Editor item ops")
struct EditorItemOpsTests {
    private func makeEditor() -> Editor {
        Editor(clock: VirtualClock(), ids: SeededIdGenerator(prefix: "i"))
    }
    private func text(_ id: ItemId, _ s: String) -> CanvasItem {
        .text(TextItem(id: id, string: s, fontName: "Helvetica", fontSize: 24,
                       color: RGBA(r: 0, g: 0, b: 0, a: 1), transform: .identity,
                       bounds: Size(width: 24, height: 24), createdAt: 0))
    }

    @Test("addItem inserts and undo deletes")
    func addUndo() {
        let e = makeEditor()
        e.addItem(text("t1", "hi"))
        #expect(e.doc.itemOrder == ["t1"])
        e.undo()
        #expect(e.doc.items["t1"] == nil)
        #expect(e.doc.itemOrder.isEmpty)
    }

    @Test("replaceItem swaps content in place; undo restores prior value")
    func replaceUndo() {
        let e = makeEditor()
        e.addItem(text("t1", "hi"))
        e.replaceItem(text("t1", "hello"))
        if case .text(let t)? = e.doc.items["t1"] { #expect(t.string == "hello") } else { Issue.record("missing") }
        e.undo()
        if case .text(let t)? = e.doc.items["t1"] { #expect(t.string == "hi") } else { Issue.record("missing") }
        #expect(e.doc.itemOrder == ["t1"])  // order preserved
    }

    @Test("replaceItems swaps many in one undo step; undo restores all priors")
    func replaceItemsUndo() {
        let e = makeEditor()
        e.addItem(text("t1", "a"))
        e.addItem(text("t2", "b"))
        e.replaceItems([text("t1", "A"), text("t2", "B")])
        if case .text(let t)? = e.doc.items["t1"] { #expect(t.string == "A") } else { Issue.record("missing") }
        if case .text(let t)? = e.doc.items["t2"] { #expect(t.string == "B") } else { Issue.record("missing") }
        e.undo()  // a single step restores both
        if case .text(let t)? = e.doc.items["t1"] { #expect(t.string == "a") } else { Issue.record("missing") }
        if case .text(let t)? = e.doc.items["t2"] { #expect(t.string == "b") } else { Issue.record("missing") }
    }

    @Test("replaceItems skips unknown ids and returns false when none match")
    func replaceItemsUnknown() {
        let e = makeEditor()
        e.addItem(text("t1", "a"))
        #expect(e.replaceItems([text("ghost", "x")]) == false)
        #expect(e.doc.items["ghost"] == nil)
    }
}
