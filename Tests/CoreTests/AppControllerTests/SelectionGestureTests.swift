// ABOUTME: Tests for AppController's selection gesture state machine —
// ABOUTME: click-to-select, Cmd-click toggle, marquee, and drag-translate.

import Testing

@Suite("AppController selection gestures")
@MainActor
struct SelectionGestureTests {
    // swiftlint:disable:next large_tuple
    private func setup() -> (AppController, Editor, [StrokeId]) {
        let clock = VirtualClock()
        let editor = Editor(clock: clock, ids: SeededIdGenerator(prefix: "s"))
        let controller = AppController(
            editor: editor,
            window: RecordingWindow(),
            detector: RecordingStationaryDetector(),
            clock: clock,
            ticker: RecordingFadeTicker()
        )
        // Draw two strokes at known locations so hit-tests are deterministic.
        controller.activate()
        controller.pointerDown(StrokePoint(x: 10, y: 10))
        controller.pointerMoved(StrokePoint(x: 30, y: 10))
        controller.pointerUp()
        controller.pointerDown(StrokePoint(x: 100, y: 100))
        controller.pointerMoved(StrokePoint(x: 120, y: 100))
        controller.pointerUp()
        controller.currentTool = .selection
        return (controller, editor, editor.doc.strokeOrder)
    }

    // MARK: click-to-select

    @Test("click on a stroke replaces selection with that stroke")
    func clickReplacesSelection() {
        let (c, _, ids) = setup()
        c.pointerDown(StrokePoint(x: 20, y: 10))
        c.pointerUp()
        #expect(c.selectedStrokeIds == [ids[0]])
    }

    @Test("clicking a second stroke replaces (not adds)")
    func clickReplacesEvenWithExisting() {
        let (c, _, ids) = setup()
        c.pointerDown(StrokePoint(x: 20, y: 10))
        c.pointerUp()
        c.pointerDown(StrokePoint(x: 110, y: 100))
        c.pointerUp()
        #expect(c.selectedStrokeIds == [ids[1]])
    }

    @Test("Cmd-click toggles a stroke into / out of selection")
    func cmdClickToggles() {
        let (c, _, ids) = setup()
        c.pointerDown(StrokePoint(x: 20, y: 10), modifiers: PointerModifiers(command: true))
        c.pointerUp()
        #expect(c.selectedStrokeIds == [ids[0]])
        c.pointerDown(StrokePoint(x: 110, y: 100), modifiers: PointerModifiers(command: true))
        c.pointerUp()
        #expect(Set(c.selectedStrokeIds) == Set(ids))
        c.pointerDown(StrokePoint(x: 20, y: 10), modifiers: PointerModifiers(command: true))
        c.pointerUp()
        #expect(c.selectedStrokeIds == [ids[1]])
    }

    // MARK: marquee

    @Test("drag from empty area marquees over intersecting strokes")
    func marqueeSelectsIntersecting() {
        let (c, _, ids) = setup()
        c.pointerDown(StrokePoint(x: 0, y: 0))
        c.pointerMoved(StrokePoint(x: 50, y: 50))
        c.pointerUp()
        #expect(c.selectedStrokeIds == [ids[0]])
    }

    @Test("a marquee that includes both strokes selects both")
    func marqueeBoth() {
        let (c, _, ids) = setup()
        c.pointerDown(StrokePoint(x: 0, y: 0))
        c.pointerMoved(StrokePoint(x: 200, y: 200))
        c.pointerUp()
        #expect(Set(c.selectedStrokeIds) == Set(ids))
    }

    @Test("marquee starting in empty space clears prior selection on commit")
    func marqueeClearsPriorSelection() {
        let (c, _, ids) = setup()
        c.selectedStrokeIds = [ids[0], ids[1]]
        c.pointerDown(StrokePoint(x: 500, y: 500))
        c.pointerMoved(StrokePoint(x: 550, y: 550))
        c.pointerUp()
        #expect(c.selectedStrokeIds == [])
    }

    // MARK: drag-translate

    @Test("drag on a stroke translates it; one undoable op")
    func dragTranslate() {
        let (c, editor, ids) = setup()
        c.pointerDown(StrokePoint(x: 20, y: 10))
        c.pointerMoved(StrokePoint(x: 25, y: 15))
        c.pointerMoved(StrokePoint(x: 30, y: 20))
        c.pointerUp()
        #expect(editor.doc.strokes[ids[0]]?.transform.x == 10)
        #expect(editor.doc.strokes[ids[0]]?.transform.y == 10)
        editor.undo()
        #expect(editor.doc.strokes[ids[0]]?.transform == .identity)
    }

    // MARK: pen mode bypasses selection

    @Test("pointerDown while currentTool == .pen draws a stroke")
    func penIgnoresSelection() {
        let (c, editor, _) = setup()
        c.currentTool = .pen
        let before = editor.doc.strokes.count
        c.pointerDown(StrokePoint(x: 300, y: 300))
        c.pointerUp()
        #expect(editor.doc.strokes.count == before + 1)
    }

    // MARK: drawing new stroke clears selection

    @Test("drawing a new stroke while having a selection clears the selection")
    func drawClearsSelection() {
        let (c, _, ids) = setup()
        c.selectedStrokeIds = [ids[0]]
        c.currentTool = .pen
        c.pointerDown(StrokePoint(x: 300, y: 300))
        c.pointerUp()
        #expect(c.selectedStrokeIds == [])
    }
}
