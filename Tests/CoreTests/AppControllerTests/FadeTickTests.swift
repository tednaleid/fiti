// ABOUTME: Tests for AppController fade state machine — handleTick branches
// ABOUTME: (solid / ramp / expiration / re-arm) and pointer-event reset triggers.

import Testing

@Suite("AppController fade tick state machine")
@MainActor
struct FadeTickTests {
    // The state-machine tests below expect a ramp starting at age 8 and clearing at
    // age 10; with the ramp (2s) now running on top of the hold, an 8s hold yields
    // exactly that. The product default is exercised separately below.
    // swiftlint:disable:next large_tuple
    private func make(secondsBeforeFade: Double = 8) -> (AppController, VirtualClock, RecordingFadeTicker, Editor) {
        let clock = VirtualClock()
        let ticker = RecordingFadeTicker()
        let window = RecordingWindow()
        let editor = Editor(clock: clock, ids: SeededIdGenerator(prefix: "s"))
        let controller = AppController(
            editor: editor,
            window: window,
            detector: RecordingStationaryDetector(),
            clock: clock,
            ticker: ticker,
            textMeasurer: FakeTextMeasurer(),
            fadeSettings: DefaultFadeSettings(secondsBeforeFade: secondsBeforeFade)
        )
        return (controller, clock, ticker, editor)
    }

    /// Activate, draw a one-point stroke, end it. Leaves lastInputAt = clock.now()
    /// from the pointerUp; mode = .activeIdle.
    private func drawOneStroke(_ controller: AppController) {
        controller.activate()
        controller.pointerDown(StrokePoint(x: 0, y: 0))
        controller.pointerUp()
    }

    @Test("tick when autoFade is off is a no-op")
    func tickOffNoOps() {
        let (c, clock, ticker, editor) = make()
        drawOneStroke(c)
        ticker.start()  // verify the autoFade guard catches even an externally-started ticker
        clock.advance(by: 1000)
        ticker.tick(at: clock.now())
        #expect(editor.doc.items.isEmpty == false)
        #expect(c.fadeOpacity == 1.0)
    }

    @Test("tick at age 7 keeps opacity 1.0")
    func tickInSolidPhase() {
        let (c, clock, ticker, _) = make()
        drawOneStroke(c)         // pointerUp at t=0; lastInputAt = 0
        c.autoFadeEnabled = true // re-arms lastInputAt to clock.now() = 0; ticker starts
        clock.advance(by: 7)
        ticker.tick(at: clock.now())
        #expect(c.fadeOpacity == 1.0)
    }

    @Test("tick at age 8.5 sets opacity to 0.75 (within ramp)")
    func tickInRamp() {
        let (c, clock, ticker, _) = make()
        drawOneStroke(c)
        c.autoFadeEnabled = true
        clock.advance(by: 8.5)
        ticker.tick(at: clock.now())
        #expect(abs(c.fadeOpacity - 0.75) < 0.0001)
    }

    @Test("tick at age 10 clears strokes and resets state")
    func tickExpires() {
        let (c, clock, ticker, editor) = make()
        drawOneStroke(c)
        c.autoFadeEnabled = true
        clock.advance(by: 10)
        ticker.tick(at: clock.now())
        #expect(editor.doc.items.isEmpty == true)
        #expect(c.fadeOpacity == 1.0)
    }

    @Test("tick at age 10 also clears selectedItemIds so the selection box disappears with the strokes")
    func tickExpiresClearsSelection() {
        let (c, clock, ticker, editor) = make()
        drawOneStroke(c)
        c.selectedItemIds = editor.doc.itemOrder
        #expect(!c.selectedItemIds.isEmpty)
        c.autoFadeEnabled = true
        clock.advance(by: 10)
        ticker.tick(at: clock.now())
        #expect(c.selectedItemIds == [])
    }

    @Test("tick on empty doc stays at opacity 1.0")
    func tickEmptyDoc() {
        let (c, clock, ticker, _) = make()
        c.autoFadeEnabled = true
        clock.advance(by: 100)
        ticker.tick(at: clock.now())
        #expect(c.fadeOpacity == 1.0)
    }

    @Test("tick re-arms when lastInputAt is nil but strokes exist (post-undo)")
    func tickReArmsAfterUndo() {
        let (c, clock, ticker, editor) = make()
        drawOneStroke(c)
        c.autoFadeEnabled = true
        clock.advance(by: 10)
        ticker.tick(at: clock.now())
        #expect(editor.doc.items.isEmpty == true)
        _ = editor.undo()
        clock.advance(by: 0.05)
        ticker.tick(at: clock.now())  // re-arms lastInputAt to now
        #expect(c.fadeOpacity == 1.0)
        clock.advance(by: 1.0)         // 1s past the re-arm — still solid phase
        ticker.tick(at: clock.now())
        #expect(c.fadeOpacity == 1.0)
    }

    @Test("mid-stroke (activeDrawing) tick does NOT expire")
    func midStrokeGuard() {
        let (c, clock, ticker, editor) = make()
        c.autoFadeEnabled = true
        c.activate()
        c.pointerDown(StrokePoint(x: 0, y: 0))  // mode = .activeDrawing
        clock.advance(by: 15)
        ticker.tick(at: clock.now())
        #expect(editor.doc.items.isEmpty == false)
    }

    @Test("pointerDown sets lastInputAt — subsequent expiration honors it")
    func pointerDownResets() {
        let (c, clock, ticker, editor) = make()
        drawOneStroke(c)         // initial stroke ended at t=0
        c.autoFadeEnabled = true
        clock.advance(by: 5)
        c.activate()
        c.pointerDown(StrokePoint(x: 1, y: 1))  // lastInputAt = 5; mode now activeDrawing
        clock.advance(by: 7)                     // total elapsed 12 from t=0; mid-stroke guard active
        ticker.tick(at: clock.now())
        #expect(editor.doc.items.isEmpty == false)  // guard prevents expire
        #expect(c.mode == .activeDrawing)
    }

    @Test("pointerMoved keeps the timer fresh through a long stroke")
    func pointerMovedResets() {
        let (c, clock, ticker, editor) = make()
        c.autoFadeEnabled = true
        c.activate()
        c.pointerDown(StrokePoint(x: 0, y: 0))
        clock.advance(by: 9)
        c.pointerMoved(StrokePoint(x: 1, y: 1))  // updates lastInputAt to 9
        c.pointerUp()                            // updates lastInputAt to 9; mode .activeIdle
        clock.advance(by: 5)                     // 5s past pointerUp — still solid (age 5)
        ticker.tick(at: clock.now())
        #expect(c.fadeOpacity == 1.0)
        #expect(editor.doc.items.isEmpty == false)
    }

    @Test("pointerUp sets lastInputAt and the window starts fresh from there")
    func pointerUpResets() {
        let (c, clock, ticker, editor) = make()
        c.autoFadeEnabled = true
        c.activate()
        c.pointerDown(StrokePoint(x: 0, y: 0))
        clock.advance(by: 20)
        c.pointerUp()                            // lastInputAt = 20; mode .activeIdle
        clock.advance(by: 5)                     // 5s past pointerUp
        ticker.tick(at: clock.now())
        #expect(c.fadeOpacity == 1.0)            // age = 5s, still solid
        #expect(editor.doc.items.isEmpty == false)
    }

    @Test("default hold is 5s: solid before 5, ramping at 6, cleared at 7")
    func defaultHoldIsFive() {
        // Build without injecting fadeSettings so the product default (5s hold) applies.
        let clock = VirtualClock()
        let ticker = RecordingFadeTicker()
        let editor = Editor(clock: clock, ids: SeededIdGenerator(prefix: "s"))
        let c = AppController(editor: editor, window: RecordingWindow(),
                              detector: RecordingStationaryDetector(), clock: clock,
                              ticker: ticker, textMeasurer: FakeTextMeasurer())
        c.activate(); c.pointerDown(StrokePoint(x: 0, y: 0)); c.pointerUp()
        c.autoFadeEnabled = true                 // re-arms lastInputAt to 0

        clock.advance(by: 4.9)                   // still within the 5s hold
        ticker.tick(at: clock.now())
        #expect(c.fadeOpacity == 1.0)

        clock.advance(by: 1.1)                   // age 6.0 -> halfway through the 2s ramp
        ticker.tick(at: clock.now())
        #expect(abs(c.fadeOpacity - 0.5) < 0.0001)

        clock.advance(by: 1.0)                   // age 7.0 (hold 5 + ramp 2) -> cleared
        ticker.tick(at: clock.now())
        #expect(editor.doc.items.isEmpty == true)
        #expect(c.fadeOpacity == 1.0)
    }

    @Test("a zero hold fades immediately over the ramp")
    func zeroHoldFadesImmediately() {
        let (c, clock, ticker, editor) = make(secondsBeforeFade: 0)
        drawOneStroke(c)
        c.autoFadeEnabled = true
        clock.advance(by: 1)                     // age 1 -> halfway through the 2s ramp
        ticker.tick(at: clock.now())
        #expect(abs(c.fadeOpacity - 0.5) < 0.0001)
        clock.advance(by: 1.1)                    // age 2.1 -> past the ramp
        ticker.tick(at: clock.now())
        #expect(editor.doc.items.isEmpty == true)
    }

    @Test("drawing mid-fade restores full opacity immediately, before release")
    func drawingMidFadeRestoresOpacity() {
        let (c, clock, ticker, _) = make(secondsBeforeFade: 8)
        drawOneStroke(c)
        c.autoFadeEnabled = true
        clock.advance(by: 9)                     // age 9 -> mid ramp (hold 8, ramp 8..10)
        ticker.tick(at: clock.now())
        #expect(c.fadeOpacity < 1.0)             // confirm we are visibly faded
        c.pointerDown(StrokePoint(x: 5, y: 5))   // start a new mark
        #expect(c.fadeOpacity == 1.0)            // solid at once, not stuck until pointerUp
        c.pointerMoved(StrokePoint(x: 6, y: 6))
        #expect(c.fadeOpacity == 1.0)
    }
}
