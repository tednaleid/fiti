// ABOUTME: Tests for the VirtualClock test double used to drive deterministic
// ABOUTME: createdAt timestamps in Editor tests.

import Testing

@Suite("VirtualClock")
struct ClockTests {
    @Test("returns set time")
    func setTime() {
        let clock = VirtualClock(now: 42)
        #expect(clock.now() == 42)
    }

    @Test("advance moves the clock forward")
    func advance() {
        let clock = VirtualClock(now: 0)
        clock.advance(by: 5)
        #expect(clock.now() == 5)
        clock.advance(by: 2.5)
        #expect(clock.now() == 7.5)
    }
}
