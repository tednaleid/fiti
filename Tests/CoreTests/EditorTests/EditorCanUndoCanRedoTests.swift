// ABOUTME: Tests for Editor.canUndo / canRedo — the menubar reads these to
// ABOUTME: decide whether to enable the Undo / Redo menu items.

import Testing

@Suite("Editor canUndo / canRedo")
@MainActor
struct EditorCanUndoCanRedoTests {
    private func makeEditor() -> Editor {
        Editor(clock: VirtualClock(), ids: SeededIdGenerator(prefix: "s"))
    }

    @Test("empty editor has no undo or redo")
    func empty() {
        let editor = makeEditor()
        #expect(editor.canUndo == false)
        #expect(editor.canRedo == false)
    }

    @Test("canUndo is true after a completed stroke")
    func afterStroke() {
        let editor = makeEditor()
        _ = editor.startStroke(color: RGBA(r: 0, g: 0, b: 0, a: 1), width: 1, pointerType: .mouse)
        editor.endStroke()
        #expect(editor.canUndo == true)
        #expect(editor.canRedo == false)
    }

    @Test("canRedo is true after undo")
    func afterUndo() {
        let editor = makeEditor()
        _ = editor.startStroke(color: RGBA(r: 0, g: 0, b: 0, a: 1), width: 1, pointerType: .mouse)
        editor.endStroke()
        _ = editor.undo()
        #expect(editor.canUndo == false)
        #expect(editor.canRedo == true)
    }
}
