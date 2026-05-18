// ABOUTME: Tests that AppController emits CursorSpec changes when mode,
// ABOUTME: currentColor, or currentWidth shift, and dedupes no-op transitions.

import Testing

@Suite("AppController cursor emission")
@MainActor
struct CursorEmissionTests {
    // Reference type so the closure mutates a shared list rather than the
    // local-capture copy that a struct or value-typed array would produce.
    private final class Recorder {
        var emissions: [CursorSpec?] = []
    }

    private func makeWithRecorder() -> (AppController, Recorder) {
        let window = RecordingWindow()
        let editor = Editor(clock: VirtualClock(), ids: SeededIdGenerator(prefix: "s"))
        let controller = AppController(
            editor: editor,
            window: window,
            detector: RecordingStationaryDetector(),
            clock: VirtualClock(),
            ticker: RecordingFadeTicker()
        )
        let rec = Recorder()
        controller.onCursorChanged = { rec.emissions.append($0) }
        return (controller, rec)
    }

    @Test("no emission until something changes")
    func noInitialEmission() {
        let (_, rec) = makeWithRecorder()
        #expect(rec.emissions.isEmpty)
    }

    @Test("activate emits a non-nil spec matching currentColor and currentWidth")
    func activateEmits() {
        let (c, rec) = makeWithRecorder()
        c.activate()
        #expect(rec.emissions.count == 1)
        #expect(rec.emissions[0] == CursorSpec(color: c.currentColor, diameter: c.currentWidth))
    }

    @Test("deactivate emits nil")
    func deactivateEmitsNil() {
        let (c, rec) = makeWithRecorder()
        c.activate()
        c.deactivate()
        #expect(rec.emissions.last == .some(nil))
    }

    @Test("color change while active emits new spec")
    func colorChangeWhileActive() {
        let (c, rec) = makeWithRecorder()
        c.activate()
        let blue = RGBA(r: 0, g: 0, b: 1, a: 1)
        c.currentColor = blue
        #expect(rec.emissions.last == .some(CursorSpec(color: blue, diameter: c.currentWidth)))
    }

    @Test("width change while active emits new spec")
    func widthChangeWhileActive() {
        let (c, rec) = makeWithRecorder()
        c.activate()
        c.currentWidth = 18
        #expect(rec.emissions.last == .some(CursorSpec(color: c.currentColor, diameter: 18)))
    }

    @Test("color change while inactive does not emit (still nil)")
    func colorChangeWhileInactiveNoEmit() {
        let (c, rec) = makeWithRecorder()
        c.currentColor = RGBA(r: 0, g: 1, b: 0, a: 1)
        #expect(rec.emissions.isEmpty)
    }

    @Test("width change while inactive does not emit")
    func widthChangeWhileInactiveNoEmit() {
        let (c, rec) = makeWithRecorder()
        c.currentWidth = 12
        #expect(rec.emissions.isEmpty)
    }

    @Test("idempotent color set does not refire")
    func idempotentColor() {
        let (c, rec) = makeWithRecorder()
        c.activate()
        let before = rec.emissions.count
        let snapshot = c.currentColor
        c.currentColor = snapshot
        #expect(rec.emissions.count == before)
    }

    @Test("idempotent width set does not refire")
    func idempotentWidth() {
        let (c, rec) = makeWithRecorder()
        c.activate()
        let before = rec.emissions.count
        let snapshot = c.currentWidth
        c.currentWidth = snapshot
        #expect(rec.emissions.count == before)
    }

    @Test("activeIdle → activeDrawing does not refire (spec unchanged)")
    func drawingTransitionDoesNotRefire() {
        let (c, rec) = makeWithRecorder()
        c.activate()
        let before = rec.emissions.count
        c.pointerDown(StrokePoint(x: 10, y: 10))
        #expect(c.mode == .activeDrawing)
        #expect(rec.emissions.count == before)
    }

    @Test("currentCursor property tracks state directly")
    func currentCursorProperty() {
        let (c, _) = makeWithRecorder()
        #expect(c.currentCursor == nil)
        c.activate()
        #expect(c.currentCursor == CursorSpec(color: c.currentColor, diameter: c.currentWidth))
        c.deactivate()
        #expect(c.currentCursor == nil)
    }
}
