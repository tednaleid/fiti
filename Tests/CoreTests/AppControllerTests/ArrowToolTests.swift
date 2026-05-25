// ABOUTME: Arrow tool: the `a` key resolves to selectTool(.arrow), and the pointer
// ABOUTME: gesture commits exactly one arrow (discarding a sub-minimum-length drag).

import Testing

@Suite("Arrow tool")
struct ArrowToolTests {
    @MainActor
    private func make() -> AppController {
        let c = AppController(editor: Editor(clock: VirtualClock(), ids: SeededIdGenerator(prefix: "i")),
                              window: RecordingWindow(), detector: RecordingStationaryDetector(),
                              clock: VirtualClock(), ticker: RecordingFadeTicker(),
                              textMeasurer: FakeTextMeasurer())
        c.activate(); c.currentTool = .arrow; return c
    }

    @Test("a key selects the arrow tool")
    func keyBindingResolves() {
        #expect(KeyCommandRegistry.command(for: KeyBinding(character: "a")) == .selectTool(.arrow))
    }

    @MainActor @Test("drag commits exactly one arrow")
    func dragCommitsOneArrow() {
        let app = make()
        app.pointerDown(StrokePoint(x: 0, y: 0, pressure: 0))
        app.pointerMoved(StrokePoint(x: 120, y: 0, pressure: 0))
        app.pointerUp()
        let items = app.editor.doc.itemOrder.compactMap { app.editor.doc.items[$0] }
        #expect(items.count == 1)
        guard case .arrow(let a) = items.first else { Issue.record("expected an arrow"); return }
        #expect(a.tail == Point(x: 0, y: 0))
        #expect(a.head == Point(x: 120, y: 0))
    }

    @MainActor @Test("sub-minimum drag commits nothing")
    func subMinimumDragDiscards() {
        let app = make()
        app.pointerDown(StrokePoint(x: 0, y: 0, pressure: 0))
        app.pointerMoved(StrokePoint(x: 1, y: 0, pressure: 0))
        app.pointerUp()
        #expect(app.editor.doc.itemOrder.isEmpty)
    }
}
