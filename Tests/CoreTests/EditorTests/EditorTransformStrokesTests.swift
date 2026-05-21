// ABOUTME: Tests for Editor.transformStrokes — batched transform op that
// ABOUTME: captures pre-call transforms as a single undo entry.

import Testing

@Suite("Editor.transformStrokes")
@MainActor
struct EditorTransformStrokesTests {
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

    @Test("applies a transform to each listed stroke")
    func appliesTransforms() {
        let (editor, ids) = makeEditorWith(strokes: 2)
        let t1 = Transform(x: 10, y: 0, scale: 1, rotate: 0)
        let t2 = Transform(x: 0, y: 20, scale: 2, rotate: 0)
        let ok = editor.transformStrokes([(ids[0], t1), (ids[1], t2)])
        #expect(ok == true)
        #expect(editor.doc.strokes[ids[0]]?.transform == t1)
        #expect(editor.doc.strokes[ids[1]]?.transform == t2)
    }

    @Test("transformStrokes is one undo entry — single undo restores all")
    func singleUndoEntry() {
        let (editor, ids) = makeEditorWith(strokes: 2)
        let t1 = Transform(x: 10, y: 0, scale: 1, rotate: 0)
        let t2 = Transform(x: 0, y: 20, scale: 2, rotate: 0)
        editor.transformStrokes([(ids[0], t1), (ids[1], t2)])
        #expect(editor.undo() == true)
        #expect(editor.doc.strokes[ids[0]]?.transform == .identity)
        #expect(editor.doc.strokes[ids[1]]?.transform == .identity)
    }

    @Test("redo re-applies all transforms")
    func redoReapplies() {
        let (editor, ids) = makeEditorWith(strokes: 2)
        let t1 = Transform(x: 10, y: 0, scale: 1, rotate: 0)
        editor.transformStrokes([(ids[0], t1), (ids[1], .identity)])
        editor.undo()
        #expect(editor.redo() == true)
        #expect(editor.doc.strokes[ids[0]]?.transform == t1)
    }

    @Test("transformStrokes with unknown id is skipped, known id still applied")
    func unknownIdSkipped() {
        let (editor, ids) = makeEditorWith(strokes: 1)
        let t = Transform(x: 5, y: 5, scale: 1, rotate: 0)
        let ok = editor.transformStrokes([(ids[0], t), ("missing", t)])
        #expect(ok == true)
        #expect(editor.doc.strokes[ids[0]]?.transform == t)
    }

    @Test("transformStrokes with no known ids returns false and does not push undo")
    func allUnknownReturnsFalse() {
        let (editor, _) = makeEditorWith(strokes: 1)
        let before = editor.canUndo
        let ok = editor.transformStrokes([("missing", .identity)])
        #expect(ok == false)
        #expect(editor.canUndo == before)
    }
}
