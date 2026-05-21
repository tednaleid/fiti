// ABOUTME: Tests for Editor.eraseStrokes — batched erase op that uses the
// ABOUTME: existing restoreStrokes inverse primitive so one undo brings
// ABOUTME: everything back at original z-order.

import Testing

@Suite("Editor.eraseStrokes")
@MainActor
struct EditorEraseStrokesTests {
    private func makeEditorWith(strokes count: Int) -> (Editor, [StrokeId]) {
        let editor = Editor(clock: VirtualClock(), ids: SeededIdGenerator(prefix: "s"))
        var ids: [StrokeId] = []
        for _ in 0..<count {
            let id = editor.startStroke(color: RGBA(r: 0, g: 0, b: 0, a: 1), width: 2, pointerType: .mouse)
            editor.appendPoint(StrokePoint(x: 0, y: 0))
            editor.endStroke()
            ids.append(id)
        }
        return (editor, ids)
    }

    @Test("eraseStrokes removes all listed strokes")
    func erasesAll() {
        let (editor, ids) = makeEditorWith(strokes: 3)
        let ok = editor.eraseStrokes(ids: [ids[0], ids[2]])
        #expect(ok == true)
        #expect(editor.doc.strokes[ids[0]] == nil)
        #expect(editor.doc.strokes[ids[1]] != nil)
        #expect(editor.doc.strokes[ids[2]] == nil)
    }

    @Test("eraseStrokes is one undoable op")
    func singleUndo() {
        let (editor, ids) = makeEditorWith(strokes: 3)
        editor.eraseStrokes(ids: [ids[0], ids[2]])
        editor.undo()
        #expect(editor.doc.strokes.count == 3)
        #expect(editor.doc.strokeOrder == ids)
    }

    @Test("eraseStrokes with empty list returns false and no-ops")
    func emptyListNoOp() {
        let (editor, _) = makeEditorWith(strokes: 2)
        let before = editor.canUndo
        let ok = editor.eraseStrokes(ids: [])
        #expect(ok == false)
        #expect(editor.canUndo == before)
        #expect(editor.doc.strokes.count == 2)
    }

    @Test("eraseStrokes with unknown ids does nothing and returns false")
    func unknownIdsReturnsFalse() {
        let (editor, _) = makeEditorWith(strokes: 1)
        let ok = editor.eraseStrokes(ids: ["missing"])
        #expect(ok == false)
    }
}
