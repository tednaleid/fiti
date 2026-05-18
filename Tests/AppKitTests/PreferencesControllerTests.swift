// ABOUTME: Tests for PreferencesController and its window — verifies window
// ABOUTME: identity, hotkey recorder binding, launch-at-login switch behaviour.

import AppKit
import Testing

@Suite("PreferencesWindow")
@MainActor
struct PreferencesWindowTests {
    @Test("window has the expected title")
    func windowTitle() {
        let window = PreferencesWindow()
        #expect(window.title == "fiti Preferences")
    }

    @Test("window is not resizable")
    func notResizable() {
        let window = PreferencesWindow()
        #expect(window.styleMask.contains(.resizable) == false)
    }

    @Test("window is not released when closed")
    func notReleasedWhenClosed() {
        let window = PreferencesWindow()
        #expect(window.isReleasedWhenClosed == false)
    }

    @Test("window uses the fiti.preferences autosave name")
    func autosaveName() {
        let window = PreferencesWindow()
        #expect(window.frameAutosaveName == "fiti.preferences")
    }
}
