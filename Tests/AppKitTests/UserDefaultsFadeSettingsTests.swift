// ABOUTME: Tests the UserDefaults-backed FadeSettings adapter: default when unset,
// ABOUTME: round-trip persistence, and clamping to the whole-second range.

import AppKit
import Testing

@Suite("UserDefaultsFadeSettings")
@MainActor
struct UserDefaultsFadeSettingsTests {
    private func freshDefaults() -> UserDefaults {
        let suite = "fiti.tests.fade.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("unset reads the Core product default")
    func unsetIsDefault() {
        let store = UserDefaultsFadeSettings(defaults: freshDefaults())
        #expect(store.secondsBeforeFade == DefaultFadeSettings.defaultSecondsBeforeFade)
    }

    @Test("a set value round-trips")
    func roundTrips() {
        let defaults = freshDefaults()
        let store = UserDefaultsFadeSettings(defaults: defaults)
        store.secondsBeforeFade = 8
        #expect(store.secondsBeforeFade == 8)
        // A fresh adapter over the same defaults reads the persisted value.
        #expect(UserDefaultsFadeSettings(defaults: defaults).secondsBeforeFade == 8)
    }

    @Test("values are clamped to the whole-second range")
    func clamps() {
        let store = UserDefaultsFadeSettings(defaults: freshDefaults())
        store.secondsBeforeFade = 0
        #expect(store.secondsBeforeFade == UserDefaultsFadeSettings.minSeconds)
        store.secondsBeforeFade = 999
        #expect(store.secondsBeforeFade == UserDefaultsFadeSettings.maxSeconds)
        store.secondsBeforeFade = 5.7
        #expect(store.secondsBeforeFade == 6)   // rounded to whole seconds
    }
}
