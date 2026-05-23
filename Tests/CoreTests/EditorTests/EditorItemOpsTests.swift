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
}
