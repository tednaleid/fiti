// ABOUTME: Tests for AppController mode transitions on activate/deactivate.
// ABOUTME: Covers initial state, activate, and deactivate paths.

import Testing

@Suite("AppController activation")
@MainActor
struct ActivationTests {
    private func make() -> (AppController, RecordingWindow) {
        let window = RecordingWindow()
        let editor = Editor(clock: VirtualClock(), ids: SeededIdGenerator(prefix: "s"))
        let controller = AppController(editor: editor, window: window, detector: RecordingStationaryDetector())
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

    @Test("toggle from inactive activates")
    func toggleFromInactive() {
        let (c, w) = make()
        c.toggle()
        #expect(c.mode == .activeIdle)
        #expect(w.clickThroughHistory.last == false)
    }

    @Test("toggle from activeIdle deactivates")
    func toggleFromActiveIdle() {
        let (c, w) = make()
        c.activate()
        c.toggle()
        #expect(c.mode == .inactive)
        #expect(w.clickThroughHistory.last == true)
    }

    @Test("toggle from activeDrawing ends the stroke and deactivates")
    func toggleFromActiveDrawing() {
        let (c, _) = make()
        c.activate()
        c.pointerDown(StrokePoint(x: 0, y: 0))
        #expect(c.mode == .activeDrawing)
        c.toggle()
        #expect(c.mode == .inactive)
    }

    @Test("deactivate releases focus back to the previously-frontmost app")
    func deactivateReleasesFocus() {
        let (c, w) = make()
        c.activate()
        #expect(w.releaseFocusCount == 0)
        c.deactivate()
        #expect(w.releaseFocusCount == 1)
    }

    @Test("deactivate while already inactive does not call releaseFocus")
    func inactiveDeactivateSkipsReleaseFocus() {
        let (c, w) = make()
        c.deactivate()
        #expect(w.releaseFocusCount == 0)
    }

    @Test("RecordingHotkeyRegistry fires the registered handler")
    func registryFiresHandler() {
        let registry = RecordingHotkeyRegistry()
        var fired = 0
        registry.onActivation { fired += 1 }
        registry.fireActivation()
        registry.fireActivation()
        #expect(fired == 2)
    }

    @Test("RecordingHotkeyRegistry without a handler is a no-op when fired")
    func registryWithoutHandlerNoOps() {
        let registry = RecordingHotkeyRegistry()
        registry.fireActivation()
        // Reaching here without crashing is the assertion.
    }

    @Test("activation hotkey toggles the controller between inactive and activeIdle")
    func activationHotkeyTogglesController() {
        let (c, _) = make()
        let registry = RecordingHotkeyRegistry()
        registry.onActivation { c.toggle() }
        #expect(c.mode == .inactive)
        registry.fireActivation()
        #expect(c.mode == .activeIdle)
        registry.fireActivation()
        #expect(c.mode == .inactive)
    }
}
