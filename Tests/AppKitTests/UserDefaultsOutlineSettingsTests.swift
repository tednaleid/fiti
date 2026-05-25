// ABOUTME: Tests the UserDefaults-backed OutlineSettings adapter: product defaults
// ABOUTME: when unset (text/arrow on, pen off) and per-tool round-trip persistence.

import AppKit
import Testing

@Suite("UserDefaultsOutlineSettings")
@MainActor
struct UserDefaultsOutlineSettingsTests {
    private func freshDefaults() -> UserDefaults {
        let suite = "fiti.tests.outline.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    @Test("unset reads product defaults: text/arrow on, pen off")
    func unsetDefaults() {
        let s = UserDefaultsOutlineSettings(defaults: freshDefaults())
        #expect(s.textOutline == true)
        #expect(s.arrowOutline == true)
        #expect(s.penOutline == false)
    }

    @Test("each tool round-trips and persists across adapters")
    func roundTrips() {
        let d = freshDefaults()
        let s = UserDefaultsOutlineSettings(defaults: d)
        s.textOutline = false
        s.penOutline = true
        #expect(s.textOutline == false)
        #expect(s.penOutline == true)
        let reloaded = UserDefaultsOutlineSettings(defaults: d)
        #expect(reloaded.textOutline == false)
        #expect(reloaded.arrowOutline == true)   // untouched, still its default
        #expect(reloaded.penOutline == true)
    }
}
