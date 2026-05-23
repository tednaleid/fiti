// ABOUTME: Tests for AppController.selectionBox recompute on selection change
// ABOUTME: and pointerHover driving the region-appropriate cursor.

import Testing

@Suite("AppController selection box + hover")
@MainActor
struct SelectionBoxHoverTests {
    private func setup() -> (AppController, [StrokeId]) {
        let clock = VirtualClock()
        let editor = Editor(clock: clock, ids: SeededIdGenerator(prefix: "s"))
        let c = AppController(editor: editor, window: RecordingWindow(),
                              detector: RecordingStationaryDetector(), clock: clock,
                              ticker: RecordingFadeTicker())
        c.activate()
        c.pointerDown(StrokePoint(x: 10, y: 10)); c.pointerMoved(StrokePoint(x: 30, y: 20)); c.pointerUp()
        c.currentTool = .selection
        return (c, editor.doc.itemOrder)
    }

    @Test("setting selectedStrokeIds computes a selection box at rotation 0")
    func boxRecompute() {
        let (c, ids) = setup()
        c.selectedStrokeIds = [ids[0]]
        #expect(c.selectionBox != nil)
        #expect(c.selectionBox?.rotation == 0)
    }

    @Test("clearing the selection clears the box")
    func boxClear() {
        let (c, ids) = setup()
        c.selectedStrokeIds = [ids[0]]
        c.selectedStrokeIds = []
        #expect(c.selectionBox == nil)
    }

    @Test("hovering the body emits an open-hand cursor")
    func hoverBody() {
        let (c, ids) = setup()
        c.selectedStrokeIds = [ids[0]]
        let box = c.selectionBox!
        c.pointerHover(StrokePoint(x: box.center.x, y: box.center.y), modifiers: .none)
        #expect(c.currentCursor == .system(.openHand))
    }

    @Test("hovering outside the box emits the arrow")
    func hoverOutside() {
        let (c, ids) = setup()
        c.selectedStrokeIds = [ids[0]]
        c.pointerHover(StrokePoint(x: 1000, y: 1000), modifiers: .none)
        #expect(c.currentCursor == .system(.arrow))
    }
}
