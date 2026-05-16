// ABOUTME: Tests for the RenderFrame.from(editor:canvasSize:) helper.
// ABOUTME: Verifies stroke ordering and in-progress stroke extraction.

import Testing

@Suite("RenderFrame.from(editor:)")
struct RenderFrameFromTests {
    @Test("orders strokes by strokeOrder, exposes in-progress separately")
    func ordersStrokes() {
        let e = Editor(clock: VirtualClock(), ids: SeededIdGenerator(prefix: "s"))
        _ = e.startStroke(color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 1, pointerType: .mouse)
        e.endStroke()
        _ = e.startStroke(color: RGBA(r: 0, g: 1, b: 0, a: 1), width: 1, pointerType: .mouse)
        e.endStroke()
        _ = e.startStroke(color: RGBA(r: 0, g: 0, b: 1, a: 1), width: 1, pointerType: .mouse) // in progress

        let frame = RenderFrame.from(editor: e, canvasSize: Size(width: 800, height: 600))
        #expect(frame.strokes.map { $0.id } == ["s-1", "s-2", "s-3"])
        #expect(frame.inProgress?.id == "s-3")
        #expect(frame.canvasSize == Size(width: 800, height: 600))
    }

    @Test("no in-progress when no current stroke")
    func noInProgress() {
        let e = Editor(clock: VirtualClock(), ids: SeededIdGenerator(prefix: "s"))
        _ = e.startStroke(color: RGBA(r: 0, g: 0, b: 0, a: 1), width: 1, pointerType: .mouse)
        e.endStroke()
        let frame = RenderFrame.from(editor: e, canvasSize: Size(width: 100, height: 100))
        #expect(frame.inProgress == nil)
    }
}
