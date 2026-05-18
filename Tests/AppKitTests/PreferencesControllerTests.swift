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
        #expect(PreferencesWindow.autosaveName == "fiti.preferences")
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

@Suite("PreferencesController launch-at-login switch")
@MainActor
struct PreferencesControllerSwitchTests {
    @Test("switch starts off when launchAtLogin.status is disabled")
    func switchOffWhenDisabled() {
        let lal = RecordingLaunchAtLogin()
        let controller = PreferencesController(launchAtLogin: lal)
        #expect(controller.testOnly_switch.state == .off)
    }

    @Test("switch starts on when launchAtLogin.status is enabled")
    func switchOnWhenEnabled() throws {
        let lal = RecordingLaunchAtLogin()
        try lal.setEnabled(true)
        let controller = PreferencesController(launchAtLogin: lal)
        #expect(controller.testOnly_switch.state == .on)
    }

    @Test("switch starts on when launchAtLogin.status is requiresApproval")
    func switchOnWhenRequiresApproval() throws {
        let lal = RecordingLaunchAtLogin()
        lal.simulateApprovalRequired = true
        try lal.setEnabled(true)
        let controller = PreferencesController(launchAtLogin: lal)
        #expect(controller.testOnly_switch.state == .on)
    }

    @Test("flipping switch on calls setEnabled(true)")
    func flipOnCallsSetEnabled() {
        let lal = RecordingLaunchAtLogin()
        let controller = PreferencesController(launchAtLogin: lal)
        controller.testOnly_toggleSwitch(to: .on)
        #expect(lal.status == .enabled)
    }

    @Test("flipping switch off calls setEnabled(false)")
    func flipOffCallsSetEnabled() throws {
        let lal = RecordingLaunchAtLogin()
        try lal.setEnabled(true)
        let controller = PreferencesController(launchAtLogin: lal)
        controller.testOnly_toggleSwitch(to: .off)
        #expect(lal.status == .disabled)
    }

    @Test("switch reverts when setEnabled throws")
    func switchRevertsOnError() {
        let lal = RecordingLaunchAtLogin()
        lal.errorToThrow = RecordingLaunchAtLoginError.synthetic
        let controller = PreferencesController(launchAtLogin: lal)
        controller.testOnly_toggleSwitch(to: .on)
        #expect(controller.testOnly_switch.state == .off)
        #expect(lal.status == .disabled)
    }

    @Test("switch reverts to on when on-to-off attempt throws")
    func switchRevertsToOnWhenOffAttemptThrows() throws {
        let lal = RecordingLaunchAtLogin()
        try lal.setEnabled(true)
        let controller = PreferencesController(launchAtLogin: lal)
        lal.errorToThrow = RecordingLaunchAtLoginError.synthetic
        controller.testOnly_toggleSwitch(to: .off)
        #expect(controller.testOnly_switch.state == .on)
        #expect(lal.status == .enabled)
    }
}

@Suite("PreferencesController status text")
@MainActor
struct PreferencesControllerStatusTextTests {
    @Test("status field is hidden when launch-at-login is disabled")
    func hiddenWhenDisabled() {
        let lal = RecordingLaunchAtLogin()
        let controller = PreferencesController(launchAtLogin: lal)
        #expect(controller.testOnly_statusField.isHidden == true)
    }

    @Test("status field is hidden when launch-at-login is enabled")
    func hiddenWhenEnabled() throws {
        let lal = RecordingLaunchAtLogin()
        try lal.setEnabled(true)
        let controller = PreferencesController(launchAtLogin: lal)
        #expect(controller.testOnly_statusField.isHidden == true)
    }

    @Test("status field shows the approval hint when requiresApproval")
    func hintWhenRequiresApproval() throws {
        let lal = RecordingLaunchAtLogin()
        lal.simulateApprovalRequired = true
        try lal.setEnabled(true)
        let controller = PreferencesController(launchAtLogin: lal)
        #expect(controller.testOnly_statusField.isHidden == false)
        #expect(controller.testOnly_statusField.stringValue.contains("Login Items"))
    }

    @Test("status field shows the error message when setEnabled throws")
    func errorMessage() {
        struct NamedError: LocalizedError {
            var errorDescription: String? { "Login Items registration failed" }
        }
        let lal = RecordingLaunchAtLogin()
        lal.errorToThrow = NamedError()
        let controller = PreferencesController(launchAtLogin: lal)
        controller.testOnly_toggleSwitch(to: .on)
        #expect(controller.testOnly_statusField.isHidden == false)
        #expect(controller.testOnly_statusField.stringValue == "Login Items registration failed")
    }

    @Test("status field clears when a subsequent toggle succeeds")
    func clearsOnSuccess() {
        let lal = RecordingLaunchAtLogin()
        lal.errorToThrow = RecordingLaunchAtLoginError.synthetic
        let controller = PreferencesController(launchAtLogin: lal)
        controller.testOnly_toggleSwitch(to: .on) // fails, field shows error
        lal.errorToThrow = nil
        controller.testOnly_toggleSwitch(to: .on) // succeeds
        #expect(controller.testOnly_statusField.isHidden == true)
    }
}
