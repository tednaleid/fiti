// ABOUTME: Tests the in-memory DefaultOutlineSettings: defaults off, round-trips.

import Testing

@Suite("OutlineSettings")
@MainActor
struct OutlineSettingsTests {
    @Test("defaults to off")
    func defaultsOff() {
        #expect(DefaultOutlineSettings().outlineEnabled == false)
    }

    @Test("holds an injected value and round-trips a write")
    func roundTrips() {
        let s = DefaultOutlineSettings(outlineEnabled: true)
        #expect(s.outlineEnabled == true)
        s.outlineEnabled = false
        #expect(s.outlineEnabled == false)
    }
}
