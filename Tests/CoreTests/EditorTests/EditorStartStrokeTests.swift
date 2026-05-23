// ABOUTME: Tests for Editor.startStroke — creates an in-progress stroke
// ABOUTME: with the supplied color/width/pointerType and an empty points array.

import Testing

@Suite("Editor.startStroke")
@MainActor
struct EditorStartStrokeTests {
    private struct Rig {
        let editor: Editor
        let ids: SeededIdGenerator
        let clock: VirtualClock
    }

    private func makeEditor(clockNow: Double = 100) -> Rig {
        let clock = VirtualClock(now: clockNow)
        let ids = SeededIdGenerator(prefix: "s")
        let editor = Editor(clock: clock, ids: ids)
        return Rig(editor: editor, ids: ids, clock: clock)
    }

    @Test("creates a new stroke with the supplied parameters")
    func basics() {
        let rig = makeEditor()
        let editor = rig.editor
        let id = editor.startStroke(color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 4, pointerType: .mouse)
        #expect(id == "s-1")
        #expect(editor.currentStrokeId == "s-1")
        guard case .stroke(let stroke)? = editor.doc.items["s-1"] else {
            Issue.record("expected a stroke item")
            return
        }
        #expect(stroke.color.r == 1)
        #expect(stroke.width == 4)
        #expect(stroke.transform == .identity)
        #expect(stroke.points.isEmpty == true)
        #expect(stroke.pointerType == .mouse)
        #expect(stroke.pressureEnabled == false)
        #expect(stroke.createdAt == 100)
    }

    @Test("appends id to itemOrder")
    func appendsToOrder() {
        let editor = makeEditor().editor
        _ = editor.startStroke(color: RGBA(r: 0, g: 0, b: 0, a: 1), width: 1, pointerType: .mouse)
        #expect(editor.doc.itemOrder == ["s-1"])
    }

    @Test("pushes a deleteItem onto the undo stack")
    func pushesUndo() {
        let editor = makeEditor().editor
        _ = editor.startStroke(color: RGBA(r: 0, g: 0, b: 0, a: 1), width: 1, pointerType: .mouse)
        #expect(editor.undoStack == [.deleteItem("s-1")])
        #expect(editor.redoStack.isEmpty)
    }
}
