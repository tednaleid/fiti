// ABOUTME: Tests for PreferencesController and its window — verifies window
// ABOUTME: identity, hotkey recorder binding, launch-at-login switch behaviour.

import AppKit
import KeyboardShortcuts
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

@Suite("PreferencesController hotkey recorder")
@MainActor
struct PreferencesControllerHotkeyTests {
    @Test("controller has a recorder bound to .toggleActivation")
    func recorderBinding() {
        let lal = RecordingLaunchAtLogin()
        let controller = PreferencesController(launchAtLogin: lal)
        #expect(controller.testOnly_recorder.shortcutName == .toggleActivation)
    }

    @Test("show() makes the window visible")
    func showOrdersFront() {
        let lal = RecordingLaunchAtLogin()
        let controller = PreferencesController(launchAtLogin: lal)
        controller.show()
        #expect(controller.testOnly_window.isVisible == true)
    }

    @Test("show() is idempotent — calling twice leaves window visible")
    func showIdempotent() {
        let lal = RecordingLaunchAtLogin()
        let controller = PreferencesController(launchAtLogin: lal)
        controller.show()
        controller.show()
        #expect(controller.testOnly_window.isVisible == true)
    }
}
