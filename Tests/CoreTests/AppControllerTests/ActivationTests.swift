// ABOUTME: Tests for AppController mode transitions on activate/deactivate.
// ABOUTME: Covers initial state, activate, and deactivate paths.

import Testing

@Suite("AppController activation")
@MainActor
struct ActivationTests {
    private func make() -> (AppController, RecordingWindow) {
        let window = RecordingWindow()
        let editor = Editor(clock: VirtualClock(), ids: SeededIdGenerator(prefix: "s"))
        let controller = AppController(editor: editor, window: window)
        return (controller, window)
    }

    @Test("initial mode is inactive")
    func initial() {
        let (c, _) = make()
        #expect(c.mode == .inactive)
    }

    @Test("activate flips to activeIdle and disables click-through")
    func activate() {
        let (c, w) = make()
        c.activate()
        #expect(c.mode == .activeIdle)
        #expect(w.clickThroughHistory.last == false)
        #expect(w.focusCount == 1)
    }

    @Test("deactivate flips back to inactive and enables click-through")
    func deactivate() {
        let (c, w) = make()
        c.activate()
        c.deactivate()
        #expect(c.mode == .inactive)
        #expect(w.clickThroughHistory.last == true)
    }

    @Test("double-activate is idempotent")
    func doubleActivate() {
        let (c, w) = make()
        c.activate()
        c.activate()
        #expect(c.mode == .activeIdle)
        #expect(w.focusCount == 1)
        #expect(w.clickThroughHistory == [false])
    }

    @Test("deactivate while already inactive is a no-op")
    func doubleDeactivate() {
        let (c, w) = make()
        c.deactivate()
        #expect(c.mode == .inactive)
        #expect(w.clickThroughHistory.isEmpty)
    }
}
