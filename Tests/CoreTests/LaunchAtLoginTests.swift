// ABOUTME: Tests for the RecordingLaunchAtLogin double — covers the initial
// ABOUTME: state, status transitions on setEnabled, throwing path, and approval simulation.

import Testing

@Suite("RecordingLaunchAtLogin")
@MainActor
struct LaunchAtLoginTests {
    @Test("initial state is disabled and available")
    func initialState() {
        let lal = RecordingLaunchAtLogin()
        #expect(lal.isAvailable == true)
        #expect(lal.status == .disabled)
    }

    @Test("setEnabled(true) moves status to enabled")
    func enableMovesToEnabled() throws {
        let lal = RecordingLaunchAtLogin()
        try lal.setEnabled(true)
        #expect(lal.status == .enabled)
    }

    @Test("setEnabled(false) moves status back to disabled")
    func disableMovesToDisabled() throws {
        let lal = RecordingLaunchAtLogin()
        try lal.setEnabled(true)
        try lal.setEnabled(false)
        #expect(lal.status == .disabled)
    }

    @Test("simulateApprovalRequired makes setEnabled(true) land in requiresApproval")
    func approvalRequired() throws {
        let lal = RecordingLaunchAtLogin()
        lal.simulateApprovalRequired = true
        try lal.setEnabled(true)
        #expect(lal.status == .requiresApproval)
    }

    @Test("errorToThrow makes setEnabled throw and leaves status unchanged")
    func errorPath() {
        let lal = RecordingLaunchAtLogin()
        lal.errorToThrow = RecordingLaunchAtLoginError.synthetic
        #expect(throws: RecordingLaunchAtLoginError.synthetic) {
            try lal.setEnabled(true)
        }
        #expect(lal.status == .disabled)
    }

    @Test("isAvailable can be overridden to false")
    func unavailable() {
        let lal = RecordingLaunchAtLogin()
        lal.isAvailable = false
        #expect(lal.isAvailable == false)
    }
}
