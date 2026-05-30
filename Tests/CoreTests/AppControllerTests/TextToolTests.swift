// ABOUTME: AppController text-tool routing with a FakeTextMeasurer — create,
// ABOUTME: edit-at-caret, commit/keep, Esc layering, empty/erase, size/color.

import Testing

@MainActor
@Suite("Text tool routing")
struct TextToolTests {
    private func make() -> AppController {
        let c = AppController(editor: Editor(clock: VirtualClock(), ids: SeededIdGenerator(prefix: "i")),
                              window: RecordingWindow(), detector: RecordingStationaryDetector(),
                              clock: VirtualClock(), ticker: RecordingFadeTicker(),
                              textMeasurer: FakeTextMeasurer())
        c.activate(); c.currentTool = .text; return c
    }

    @Test("click on blank starts a new empty session at the click")
    func clickBlankStarts() {
        let c = make()
        c.pointerDown(StrokePoint(x: 40, y: 50))
        #expect(c.isEditingText)
        #expect(c.textSession?.itemId == nil)
        #expect(c.textSession?.transform.x == 40)
    }

    @Test("typing then Return commits a text item and stays in text mode")
    func commitKeepsMode() {
        let c = make()
        c.pointerDown(StrokePoint(x: 0, y: 0))
        c.insertText("hi")
        c.commitText()
        #expect(c.currentTool == .text)
        #expect(c.isEditingText == false)
        #expect(c.editor.doc.itemOrder.count == 1)
        if case .text(let t)? = c.editor.doc.items[c.editor.doc.itemOrder[0]] {
            #expect(t.string == "hi")
            #expect(t.bounds == Size(width: 24, height: 24))   // fake: 2 chars * 12
            #expect(t.fontSize == textFontSize(forWidth: c.currentWidth))
            #expect(t.color == c.currentColor)
        } else { Issue.record("expected text item") }
    }

    @Test("empty new text on commit is discarded")
    func emptyDiscarded() {
        let c = make()
        c.pointerDown(StrokePoint(x: 0, y: 0))
        c.commitText()
        #expect(c.editor.doc.itemOrder.isEmpty)
    }

    @Test("clicking an existing text edits it at the reverse-mapped caret")
    func clickEdits() {
        let c = make()
        c.pointerDown(StrokePoint(x: 0, y: 0)); c.insertText("abc"); c.commitText()
        let id = c.editor.doc.itemOrder[0]
        // text origin at (0,0); click near x=30 -> fake caretIndex 2
        c.pointerDown(StrokePoint(x: 30, y: 5))
        #expect(c.textSession?.itemId == id)
        #expect(c.textSession?.caret == 2)
    }

    @Test("Esc while typing commits and stays in the text tool")
    func escWhileTyping() {
        let c = make()
        c.pointerDown(StrokePoint(x: 0, y: 0)); c.insertText("hi")
        c.escapePressed()
        #expect(c.currentTool == .text)
        #expect(c.isEditingText == false)
        #expect(c.editor.doc.itemOrder.count == 1)
    }

    @Test("Esc when idle deactivates fiti")
    func escIdleDeactivates() {
        let c = make()
        c.escapePressed()
        #expect(c.mode == .inactive)
    }

    @Test("editing an existing text to empty erases it on commit")
    func emptiedErases() {
        let c = make()
        c.pointerDown(StrokePoint(x: 0, y: 0)); c.insertText("hi"); c.commitText()
        let id = c.editor.doc.itemOrder[0]
        c.pointerDown(StrokePoint(x: 0, y: 0))   // re-edit (caret 0)
        c.textSession?.string = ""               // simulate deleting all
        c.commitText()
        #expect(c.editor.doc.items[id] == nil)
    }
}
