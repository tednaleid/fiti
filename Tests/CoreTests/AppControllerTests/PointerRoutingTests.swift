// ABOUTME: Tests for AppController.pointerDown/Moved/Up — translates raw
// ABOUTME: pointer events into Editor stroke calls based on current mode.

import Testing

@Suite("AppController pointer routing")
@MainActor
struct PointerRoutingTests {
    private func make() -> AppController {
        let window = RecordingWindow()
        let editor = Editor(clock: VirtualClock(), ids: SeededIdGenerator(prefix: "s"))
        return AppController(
            editor: editor,
            window: window,
            detector: RecordingStationaryDetector(),
            clock: VirtualClock(),
            ticker: RecordingFadeTicker(),
            textMeasurer: FakeTextMeasurer()
        )
    }

    @Test("pointerDown in activeIdle starts a stroke and seeds the first point")
    func downStartsStroke() {
        let c = make()
        c.activate()
        c.pointerDown(StrokePoint(x: 10, y: 20))
        #expect(c.mode == .activeDrawing)
        #expect(c.editor.currentStrokeId == "s-1")
        guard case .stroke(let s)? = c.editor.doc.items["s-1"] else { Issue.record("missing"); return }
        #expect(s.points.first?.x == 10)
    }

    @Test("pointerMoved in activeDrawing appends a point")
    func moveAppends() {
        let c = make()
        c.activate()
        c.pointerDown(StrokePoint(x: 0, y: 0))
        c.pointerMoved(StrokePoint(x: 1, y: 1))
        c.pointerMoved(StrokePoint(x: 2, y: 2))
        guard case .stroke(let s)? = c.editor.doc.items["s-1"] else { Issue.record("missing"); return }
        #expect(s.points.count == 3)
    }

    @Test("pointerUp in activeDrawing ends the stroke and returns to activeIdle")
    func upEnds() {
        let c = make()
        c.activate()
        c.pointerDown(StrokePoint(x: 0, y: 0))
        c.pointerUp()
        #expect(c.mode == .activeIdle)
        #expect(c.editor.currentStrokeId == nil)
    }

    @Test("pointer events in inactive mode are ignored")
    func ignoredWhenInactive() {
        let c = make()
        c.pointerDown(StrokePoint(x: 0, y: 0))
        #expect(c.mode == .inactive)
        #expect(c.editor.doc.items.isEmpty)
    }

    @Test("deactivate mid-draw ends the in-progress stroke")
    func deactivateMidDraw() {
        let c = make()
        c.activate()
        c.pointerDown(StrokePoint(x: 0, y: 0))
        c.pointerMoved(StrokePoint(x: 1, y: 1))
        c.deactivate()
        #expect(c.mode == .inactive)
        #expect(c.editor.currentStrokeId == nil)
        guard case .stroke(let s)? = c.editor.doc.items["s-1"] else { Issue.record("missing"); return }
        #expect(s.points.count == 2)
    }

    @Test("clear() empties the editor doc")
    func clearPassesThrough() {
        let c = make()
        c.activate()
        c.pointerDown(StrokePoint(x: 0, y: 0))
        c.pointerUp()
        #expect(c.editor.doc.itemOrder.count == 1)
        c.clear()
        #expect(c.editor.doc.itemOrder.isEmpty)
    }

    @Test("clear() while drawing ends the in-progress stroke first")
    func clearWhileDrawing() {
        let c = make()
        c.activate()
        c.pointerDown(StrokePoint(x: 0, y: 0))
        c.clear()
        #expect(c.editor.currentStrokeId == nil)
        #expect(c.editor.doc.itemOrder.isEmpty)
        #expect(c.mode == .activeIdle)
    }
}
