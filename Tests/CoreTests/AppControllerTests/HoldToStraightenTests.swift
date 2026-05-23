// ABOUTME: Tests for the hold-to-straighten gesture wiring on AppController.
// ABOUTME: Covers stationary detector arming, dead-zone, rubber-band state, snap logic.

import Testing

@Suite("hold-to-straighten")
@MainActor
struct HoldToStraightenTests {
    @Test("RecordingStationaryDetector arms, fires, and reports last-armed state")
    func detectorDouble() {
        let det = RecordingStationaryDetector()
        var fired = 0
        det.onStationary = { fired += 1 }
        #expect(det.isArmed == false)
        det.arm()
        #expect(det.isArmed)
        det.fire()
        #expect(fired == 1)
        #expect(det.isArmed == false)
        det.arm()
        det.disarm()
        #expect(det.isArmed == false)
        det.fire()
        #expect(fired == 1) // no fire when disarmed
    }

    private func make() -> (AppController, RecordingStationaryDetector) {
        let window = RecordingWindow()
        let editor = Editor(clock: VirtualClock(), ids: SeededIdGenerator(prefix: "s"))
        let detector = RecordingStationaryDetector()
        let controller = AppController(
            editor: editor,
            window: window,
            detector: detector,
            clock: VirtualClock(),
            ticker: RecordingFadeTicker()
        )
        return (controller, detector)
    }

    @Test("pointerDown arms the detector")
    func pointerDownArms() {
        let (c, det) = make()
        c.activate()
        c.pointerDown(StrokePoint(x: 0, y: 0))
        #expect(det.isArmed)
    }

    @Test("pointerMoved past the dead-zone re-arms the detector")
    func pointerMovedReArms() {
        let (c, det) = make()
        c.activate()
        c.pointerDown(StrokePoint(x: 0, y: 0))
        det.disarm()  // clear initial arm
        c.pointerMoved(StrokePoint(x: 10, y: 0))  // well past dead-zone
        #expect(det.isArmed)
    }

    @Test("tiny jitter within the dead-zone does not re-arm")
    func jitterDoesNotReArm() {
        let (c, det) = make()
        c.activate()
        c.pointerDown(StrokePoint(x: 0, y: 0))
        det.disarm()
        c.pointerMoved(StrokePoint(x: 0.5, y: 0.5))  // within 2.0 dead-zone
        #expect(det.isArmed == false)
    }

    @Test("pointerUp disarms")
    func pointerUpDisarms() {
        let (c, det) = make()
        c.activate()
        c.pointerDown(StrokePoint(x: 0, y: 0))
        #expect(det.isArmed)
        c.pointerUp()
        #expect(det.isArmed == false)
    }

    @Test("stationary fire on a straight stroke enters rubber-band and snaps the stroke")
    func snapStraightStroke() {
        let (c, det) = make()
        c.activate()
        c.pointerDown(StrokePoint(x: 0, y: 0))
        c.pointerMoved(StrokePoint(x: 5, y: 0.5))
        c.pointerMoved(StrokePoint(x: 10, y: -0.5))
        c.pointerMoved(StrokePoint(x: 15, y: 0))
        #expect(c.isRubberBanding == false)
        det.fire()
        #expect(c.isRubberBanding == true)
        let id = c.editor.currentStrokeId!
        guard case .stroke(let s)? = c.editor.doc.items[id] else { Issue.record("missing"); return }
        let pts = s.points
        #expect(pts.count == 2)
        #expect(pts.first == StrokePoint(x: 0, y: 0))
        #expect(pts.last == StrokePoint(x: 15, y: 0))
    }

    @Test("stationary fire on a non-straight stroke does NOT snap")
    func dontSnapBox() {
        let (c, det) = make()
        c.activate()
        c.pointerDown(StrokePoint(x: 0, y: 0))
        c.pointerMoved(StrokePoint(x: 10, y: 0))
        c.pointerMoved(StrokePoint(x: 10, y: 10))
        c.pointerMoved(StrokePoint(x: 0, y: 10))
        det.fire()
        #expect(c.isRubberBanding == false)
        let id = c.editor.currentStrokeId!
        guard case .stroke(let s)? = c.editor.doc.items[id] else { Issue.record("missing"); return }
        #expect(s.points.count == 4)
    }

    @Test("during rubber-band, pointerMoved updates the endpoint instead of appending")
    func rubberBandMovesEndpoint() {
        let (c, det) = make()
        c.activate()
        c.pointerDown(StrokePoint(x: 0, y: 0))
        c.pointerMoved(StrokePoint(x: 50, y: 0))
        det.fire()  // snap → rubber-band
        c.pointerMoved(StrokePoint(x: 100, y: 50))  // should update endpoint
        let id = c.editor.currentStrokeId!
        guard case .stroke(let s)? = c.editor.doc.items[id] else { Issue.record("missing"); return }
        let pts = s.points
        #expect(pts.count == 2)
        #expect(pts.last == StrokePoint(x: 100, y: 50))
    }

    @Test("during rubber-band, the stationary detector stays disarmed")
    func rubberBandKeepsDetectorDisarmed() {
        let (c, det) = make()
        c.activate()
        c.pointerDown(StrokePoint(x: 0, y: 0))
        c.pointerMoved(StrokePoint(x: 50, y: 0))
        det.fire()
        c.pointerMoved(StrokePoint(x: 75, y: 0))
        c.pointerMoved(StrokePoint(x: 100, y: 25))
        #expect(det.isArmed == false)
    }

    @Test("pointerUp from rubber-band commits the line and resets state")
    func rubberBandCommit() {
        let (c, det) = make()
        c.activate()
        c.pointerDown(StrokePoint(x: 0, y: 0))
        c.pointerMoved(StrokePoint(x: 50, y: 0))
        det.fire()
        c.pointerMoved(StrokePoint(x: 100, y: 25))
        c.pointerUp()
        #expect(c.isRubberBanding == false)
        #expect(c.mode == .activeIdle)
        #expect(c.editor.currentStrokeId == nil)
    }

    @Test("deactivate while rubber-banding resets state")
    func deactivateWhileRubberBanding() {
        let (c, det) = make()
        c.activate()
        c.pointerDown(StrokePoint(x: 0, y: 0))
        c.pointerMoved(StrokePoint(x: 50, y: 0))
        det.fire()  // enter rubber-band
        #expect(c.isRubberBanding == true)
        c.deactivate()
        #expect(c.isRubberBanding == false)
        #expect(c.mode == .inactive)
        #expect(det.isArmed == false)
    }
}
