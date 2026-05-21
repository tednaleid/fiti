// ABOUTME: Tests for AppController.run(_ command: KeyCommand) — exhaustive over
// ABOUTME: every KeyCommand case including clamps, mid-stroke behavior, and the
// ABOUTME: clear-finalizes-in-progress-stroke invariant.

import Testing

@Suite("AppController.run(_:)")
@MainActor
struct RunCommandTests {
    // swiftlint:disable:next large_tuple
    private func make() -> (AppController, Editor, VirtualClock) {
        let clock = VirtualClock()
        let editor = Editor(clock: clock, ids: SeededIdGenerator(prefix: "s"))
        let controller = AppController(
            editor: editor,
            window: RecordingWindow(),
            detector: RecordingStationaryDetector(),
            clock: clock,
            ticker: RecordingFadeTicker()
        )
        return (controller, editor, clock)
    }

    @Test("pickColor sets RGB from the palette and preserves alpha")
    func pickColorPreservesAlpha() {
        let (c, _, _) = make()
        c.currentColor = RGBA(r: 0, g: 0, b: 0, a: 0.5)
        c.run(.pickColor(2))  // Red
        #expect(abs(c.currentColor.r - 224.0/255.0) < 0.0001)
        #expect(abs(c.currentColor.g - 49.0/255.0) < 0.0001)
        #expect(abs(c.currentColor.b - 49.0/255.0) < 0.0001)
        #expect(c.currentColor.a == 0.5)
    }

    @Test("pickColor with out-of-range index is a no-op")
    func pickColorOutOfRange() {
        let (c, _, _) = make()
        let before = c.currentColor
        c.run(.pickColor(99))
        c.run(.pickColor(-1))
        #expect(c.currentColor == before)
    }

    @Test("bumpSize(.up) multiplies width by 1.1")
    func bumpSizeUp() {
        let (c, _, _) = make()
        c.currentWidth = 10
        c.run(.bumpSize(.up))
        #expect(abs(c.currentWidth - 11.0) < 0.0001)
    }

    @Test("bumpSize(.down) divides width by 1.1")
    func bumpSizeDown() {
        let (c, _, _) = make()
        c.currentWidth = 11
        c.run(.bumpSize(.down))
        #expect(abs(c.currentWidth - 10.0) < 0.0001)
    }

    @Test("bumpSize(.up) clamps at 40")
    func bumpSizeUpClamp() {
        let (c, _, _) = make()
        c.currentWidth = 40
        c.run(.bumpSize(.up))
        #expect(c.currentWidth == 40)
    }

    @Test("bumpSize(.down) clamps at 1")
    func bumpSizeDownClamp() {
        let (c, _, _) = make()
        c.currentWidth = 1
        c.run(.bumpSize(.down))
        #expect(c.currentWidth == 1)
    }

    @Test("bumpOpacity(.up) adds 0.1 to alpha")
    func bumpOpacityUp() {
        let (c, _, _) = make()
        c.currentColor = RGBA(r: 0.2, g: 0.3, b: 0.4, a: 0.5)
        c.run(.bumpOpacity(.up))
        #expect(abs(c.currentColor.a - 0.6) < 0.0001)
        #expect(c.currentColor.r == 0.2)  // RGB unchanged
        #expect(c.currentColor.g == 0.3)
        #expect(c.currentColor.b == 0.4)
    }

    @Test("bumpOpacity(.down) subtracts 0.1 from alpha")
    func bumpOpacityDown() {
        let (c, _, _) = make()
        c.currentColor = RGBA(r: 0.2, g: 0.3, b: 0.4, a: 0.5)
        c.run(.bumpOpacity(.down))
        #expect(abs(c.currentColor.a - 0.4) < 0.0001)
    }

    @Test("bumpOpacity(.up) clamps at 1.0")
    func bumpOpacityUpClamp() {
        let (c, _, _) = make()
        c.currentColor = RGBA(r: 0, g: 0, b: 0, a: 1.0)
        c.run(.bumpOpacity(.up))
        #expect(c.currentColor.a == 1.0)
    }

    @Test("bumpOpacity(.down) clamps at 0.0")
    func bumpOpacityDownClamp() {
        let (c, _, _) = make()
        c.currentColor = RGBA(r: 0, g: 0, b: 0, a: 0.0)
        c.run(.bumpOpacity(.down))
        #expect(c.currentColor.a == 0.0)
    }

    @Test("toggleHide flips drawingsVisible")
    func toggleHideFlips() {
        let (c, _, _) = make()
        #expect(c.drawingsVisible == true)
        c.run(.toggleHide)
        #expect(c.drawingsVisible == false)
        c.run(.toggleHide)
        #expect(c.drawingsVisible == true)
    }

    @Test("toggleAutoFade flips autoFadeEnabled")
    func toggleAutoFadeFlips() {
        let (c, _, _) = make()
        #expect(c.autoFadeEnabled == false)
        c.run(.toggleAutoFade)
        #expect(c.autoFadeEnabled == true)
        c.run(.toggleAutoFade)
        #expect(c.autoFadeEnabled == false)
    }

    @Test("clear with in-progress stroke finalizes then empties the doc")
    func clearFinalizesInProgressStroke() {
        let (c, editor, _) = make()
        c.activate()
        c.pointerDown(StrokePoint(x: 0, y: 0))
        c.pointerMoved(StrokePoint(x: 5, y: 5))
        // Mid-stroke clear:
        c.run(.clear)
        #expect(editor.doc.strokes.isEmpty == true)
        #expect(c.mode == .activeIdle)
        // One undo brings the just-finalized stroke back.
        _ = editor.undo()
        #expect(editor.doc.strokes.isEmpty == false)
    }

    @Test("pickColor mid-stroke leaves the in-progress stroke unchanged")
    func pickColorMidStrokeDoesNotRetro() {
        let (c, editor, _) = make()
        c.currentColor = RGBA(r: 1, g: 0, b: 0, a: 1)  // Red
        c.activate()
        c.pointerDown(StrokePoint(x: 0, y: 0))
        guard let id = editor.currentStrokeId, let strokeBefore = editor.doc.strokes[id] else {
            Issue.record("expected an in-progress stroke")
            return
        }
        c.run(.pickColor(5))  // Green
        let strokeAfter = editor.doc.strokes[id]
        #expect(strokeAfter?.color == strokeBefore.color)  // unchanged
        #expect(c.currentColor != strokeBefore.color)      // controller moved
    }

    @Test("bumpSize mid-stroke leaves the in-progress stroke width unchanged")
    func bumpSizeMidStrokeDoesNotRetro() {
        let (c, editor, _) = make()
        c.currentWidth = 10
        c.activate()
        c.pointerDown(StrokePoint(x: 0, y: 0))
        guard let id = editor.currentStrokeId, let strokeBefore = editor.doc.strokes[id] else {
            Issue.record("expected an in-progress stroke")
            return
        }
        c.run(.bumpSize(.up))
        let strokeAfter = editor.doc.strokes[id]
        #expect(strokeAfter?.width == strokeBefore.width)  // unchanged
        #expect(c.currentWidth > strokeBefore.width)        // controller moved
    }

    @Test("run(.clear) with non-empty selectedStrokeIds erases only those strokes")
    func clearWithSelectionErasesSelected() {
        let (c, editor, _) = make()
        c.activate()
        c.pointerDown(StrokePoint(x: 0, y: 0))
        c.pointerUp()
        c.pointerDown(StrokePoint(x: 10, y: 10))
        c.pointerUp()
        let allIds = editor.doc.strokeOrder
        #expect(allIds.count == 2)
        c.selectedStrokeIds = [allIds[0]]
        c.run(.clear)
        #expect(editor.doc.strokes[allIds[0]] == nil)
        #expect(editor.doc.strokes[allIds[1]] != nil)
        #expect(c.selectedStrokeIds == [])
    }

    @Test("run(.clear) with empty selection clears everything (existing behavior)")
    func clearWithoutSelectionClearsAll() {
        let (c, editor, _) = make()
        c.activate()
        c.pointerDown(StrokePoint(x: 0, y: 0))
        c.pointerUp()
        #expect(editor.doc.strokeOrder.count == 1)
        c.run(.clear)
        #expect(editor.doc.strokeOrder.isEmpty)
    }
}
