// ABOUTME: Editor transient arrow lifecycle: begin/update/commit/cancel.
// ABOUTME: Commit adds exactly one undoable item; cancel leaves the doc untouched.

import Foundation
import Testing

@Suite("Editor arrow")
struct EditorArrowTests {
    @MainActor private func makeEditor() -> Editor {
        Editor(clock: VirtualClock(now: 100), ids: SeededIdGenerator(prefix: "a"))
    }

    @MainActor @Test("begin, update, commit adds one undoable arrow")
    func beginUpdateCommit() {
        let e = makeEditor()
        _ = e.beginArrow(color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 8, tail: Point(x: 0, y: 0))
        #expect(e.currentArrow != nil)
        e.updateArrowHead(to: Point(x: 50, y: 0))
        #expect(e.currentArrow?.head == Point(x: 50, y: 0))
        let id = e.commitArrow()
        #expect(id != nil)
        #expect(e.currentArrow == nil)
        #expect(e.doc.itemOrder.count == 1)
        #expect(e.canUndo)
        _ = e.undo()
        #expect(e.doc.itemOrder.isEmpty)
    }

    @MainActor @Test("cancel discards without committing")
    func cancelDiscards() {
        let e = makeEditor()
        _ = e.beginArrow(color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 8, tail: Point(x: 0, y: 0))
        e.updateArrowHead(to: Point(x: 50, y: 0))
        e.cancelArrow()
        #expect(e.currentArrow == nil)
        #expect(e.doc.itemOrder.isEmpty)
        #expect(!e.canUndo)
    }
}
