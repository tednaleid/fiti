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

    @Test("translate commits to editor BEFORE clearing inFlightTransforms so the [:] callback reads new transforms")
    func translateCommitsBeforeClearingOverlay() {
        let (c, editor, ids) = setup()
        var seenAtCallback: [StrokeId: Transform] = [:]
        c.onInFlightTransformsChanged = { overrides in
            if overrides.isEmpty {
                // Capture the editor's transform at the moment the overlay clears.
                // If commit happened first, this is the post-drag value.
                seenAtCallback[ids[0]] = editor.doc.strokes[ids[0]]?.transform
            }
        }
        c.pointerDown(StrokePoint(x: 20, y: 10))
        c.pointerMoved(StrokePoint(x: 30, y: 20))
        c.pointerUp()
        #expect(seenAtCallback[ids[0]] == Transform(x: 10, y: 10, scale: 1, rotate: 0))
    }

    // MARK: region-first multi-select

    @Test("clicking a member of a multi-selection keeps the whole selection and translates it")
    func clickMemberKeepsMultiSelection() {
        let (c, editor, ids) = setup()
        c.selectedStrokeIds = ids                      // both selected
        c.pointerDown(StrokePoint(x: 20, y: 10))       // on stroke 0, which is inside the box
        c.pointerMoved(StrokePoint(x: 30, y: 10))      // drag +10 x
        c.pointerUp()
        #expect(Set(c.selectedStrokeIds) == Set(ids))  // still both
        #expect(editor.doc.strokes[ids[0]]?.transform.x == 10)
        #expect(editor.doc.strokes[ids[1]]?.transform.x == 10)  // moved together
    }

    @Test("clicking empty interior of the selection box translates the group")
    func clickEmptyInteriorTranslates() {
        let (c, editor, ids) = setup()
        c.selectedStrokeIds = ids
        let box = c.selectionBox!
        c.pointerDown(StrokePoint(x: box.center.x, y: box.center.y))  // empty interior
        c.pointerMoved(StrokePoint(x: box.center.x + 5, y: box.center.y))
        c.pointerUp()
        #expect(Set(c.selectedStrokeIds) == Set(ids))
        #expect(editor.doc.strokes[ids[0]]?.transform.x == 5)
    }

    @Test("Space+Cmd marquee toggles each intersected stroke")
    func cmdMarqueeToggles() {
        let (c, _, ids) = setup()
        c.selectedStrokeIds = [ids[0]]                 // stroke 0 already selected
        // Marquee over BOTH strokes with Cmd: stroke 0 removed, stroke 1 added.
        c.pointerDown(StrokePoint(x: 0, y: 0), modifiers: PointerModifiers(command: true))
        c.pointerMoved(StrokePoint(x: 200, y: 200), modifiers: PointerModifiers(command: true))
        c.pointerUp(modifiers: PointerModifiers(command: true))
        #expect(c.selectedStrokeIds == [ids[1]])
    }

    // MARK: resize + rotate

    @Test("dragging a corner scales the selection and commits one undoable op")
    func cornerResize() {
        let (c, editor, ids) = setup()
        c.selectedStrokeIds = [ids[0]]
        let box = c.selectionBox!
        let br = box.corners()[2]   // bottomRight
        let tl = box.corners()[0]   // anchor
        c.pointerDown(StrokePoint(x: br.x, y: br.y))
        // double the distance from the anchor along the diagonal
        c.pointerMoved(StrokePoint(x: tl.x + (br.x - tl.x) * 2, y: tl.y + (br.y - tl.y) * 2))
        c.pointerUp()
        #expect(editor.doc.strokes[ids[0]]!.transform.scale == 2)
        editor.undo()
        #expect(editor.doc.strokes[ids[0]]!.transform.scale == 1)
    }

    @Test("dragging the rotate node rotates the group as a rigid unit, one undoable op")
    func rotateGesture() {
        let (c, editor, ids) = setup()
        c.selectedStrokeIds = ids
        let box = c.selectionBox!
        let node = box.rotateNode(offset: AppController.rotateNodeOffset)
        c.pointerDown(StrokePoint(x: node.x, y: node.y))
        // move the pointer 90° around the center
        let center = box.center
        c.pointerMoved(StrokePoint(x: center.x, y: center.y + 50))
        c.pointerUp()
        // both strokes gained the same rotation delta (rigid)
        let r0 = editor.doc.strokes[ids[0]]!.transform.rotate
        let r1 = editor.doc.strokes[ids[1]]!.transform.rotate
        #expect(abs(r0 - r1) < 1e-6)
        #expect(abs(r0) > 1)   // actually rotated
        editor.undo()
        #expect(abs(editor.doc.strokes[ids[0]]!.transform.rotate) < 1e-6)
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
