// ABOUTME: Tests the over-toolbar cursor/input policy: an arrow cursor when the
// ABOUTME: hover point is inside toolbarRegion, and no drawing started there.

import Testing

@Suite("AppController toolbar region")
@MainActor
struct ToolbarRegionTests {
    private func make() -> (AppController, Editor) {
        let clock = VirtualClock()
        let editor = Editor(clock: clock, ids: SeededIdGenerator(prefix: "s"))
        let c = AppController(editor: editor, window: RecordingWindow(),
                              detector: RecordingStationaryDetector(), clock: clock,
                              ticker: RecordingFadeTicker(), textMeasurer: FakeTextMeasurer())
        return (c, editor)
    }

    @Test("hovering inside the toolbar region shows the arrow cursor")
    func arrowOverToolbar() {
        let (c, _) = make()
        c.activate()                                   // pen tool, activeIdle
        c.toolbarRegion = Rect(x: 0, y: 0, width: 60, height: 320)
        c.pointerHover(StrokePoint(x: 10, y: 10), modifiers: .none)
        #expect(c.currentCursor == .system(.arrow))
    }

    @Test("hovering outside the toolbar region shows the tool cursor")
    func brushOutsideToolbar() {
        let (c, _) = make()
        c.activate()
        c.toolbarRegion = Rect(x: 0, y: 0, width: 60, height: 320)
        c.pointerHover(StrokePoint(x: 400, y: 400), modifiers: .none)
        #expect(c.currentCursor == .brush(color: c.currentColor, diameter: c.currentWidth))
    }

    @Test("pointerDown inside the toolbar region starts no stroke")
    func noDrawUnderToolbar() {
        let (c, editor) = make()
        c.activate()
        c.toolbarRegion = Rect(x: 0, y: 0, width: 60, height: 320)
        c.pointerDown(StrokePoint(x: 10, y: 10))
        #expect(editor.doc.items.isEmpty)
        #expect(c.mode == .activeIdle)
    }

    @Test("pointerDown just outside the toolbar region starts a stroke")
    func drawOutsideToolbar() {
        let (c, editor) = make()
        c.activate()
        c.toolbarRegion = Rect(x: 0, y: 0, width: 60, height: 320)
        c.pointerDown(StrokePoint(x: 400, y: 400))
        #expect(c.mode == .activeDrawing)
        #expect(!editor.doc.items.isEmpty)
    }
}
