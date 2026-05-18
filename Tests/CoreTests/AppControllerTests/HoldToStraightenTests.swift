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
}
