// ABOUTME: Tests that starting a new mark while drawings are hidden reveals them
// ABOUTME: (pen/arrow/text), while selection-tool interaction leaves hide alone.

import Testing

@Suite("AppController reveal-on-draw")
@MainActor
struct RevealOnDrawTests {
    private func make() -> (AppController, Editor) {
        let clock = VirtualClock()
        let editor = Editor(clock: clock, ids: SeededIdGenerator(prefix: "s"))
        let c = AppController(editor: editor, window: RecordingWindow(),
                              detector: RecordingStationaryDetector(), clock: clock,
                              ticker: RecordingFadeTicker(), textMeasurer: FakeTextMeasurer())
        return (c, editor)
    }

    @Test("pen down while hidden reveals drawings")
    func penRevealsHidden() {
        let (c, _) = make()
        c.activate()
        c.drawingsVisible = false
        c.pointerDown(StrokePoint(x: 10, y: 10))
        #expect(c.drawingsVisible == true)
        #expect(c.mode == .activeDrawing)
    }

    @Test("arrow down while hidden reveals drawings")
    func arrowRevealsHidden() {
        let (c, _) = make()
        c.activate()
        c.currentTool = .arrow
        c.drawingsVisible = false
        c.pointerDown(StrokePoint(x: 10, y: 10))
        #expect(c.drawingsVisible == true)
    }

    @Test("text down while hidden reveals drawings")
    func textRevealsHidden() {
        let (c, _) = make()
        c.activate()
        c.currentTool = .text
        c.drawingsVisible = false
        c.pointerDown(StrokePoint(x: 10, y: 10))
        #expect(c.drawingsVisible == true)
    }

    @Test("selection click while hidden leaves drawings hidden")
    func selectionLeavesHidden() {
        let (c, _) = make()
        c.activate()
        c.currentTool = .selection
        c.drawingsVisible = false
        c.pointerDown(StrokePoint(x: 10, y: 10))
        #expect(c.drawingsVisible == false)
    }
}
