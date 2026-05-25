// ABOUTME: Tests the in-memory DefaultOutlineSettings and the OutlineFlags it derives:
// ABOUTME: product defaults (text/arrow on, pen off) and per-tool round-trips.

import Testing

@Suite("OutlineSettings")
@MainActor
struct OutlineSettingsTests {
    @Test("defaults: text and arrows on, pen off")
    func defaults() {
        let s = DefaultOutlineSettings()
        #expect(s.textOutline == true)
        #expect(s.arrowOutline == true)
        #expect(s.penOutline == false)
    }

    @Test("each tool round-trips a write")
    func roundTrips() {
        let s = DefaultOutlineSettings(textOutline: false, arrowOutline: false, penOutline: true)
        #expect(s.flags == OutlineFlags(text: false, arrow: false, pen: true))
        s.textOutline = true
        s.penOutline = false
        #expect(s.flags == OutlineFlags(text: true, arrow: false, pen: false))
    }
}
