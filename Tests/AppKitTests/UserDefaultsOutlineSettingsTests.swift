// ABOUTME: Tests the UserDefaults-backed OutlineSettings adapter: default off
// ABOUTME: when unset, and round-trip persistence.

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

    @Test("unset reads as off")
    func unsetIsOff() {
        #expect(UserDefaultsOutlineSettings(defaults: freshDefaults()).outlineEnabled == false)
    }

    @Test("a set value round-trips and persists across adapters")
    func roundTrips() {
        let d = freshDefaults()
        let s = UserDefaultsOutlineSettings(defaults: d)
        s.outlineEnabled = true
        #expect(s.outlineEnabled == true)
        #expect(UserDefaultsOutlineSettings(defaults: d).outlineEnabled == true)
    }
}
