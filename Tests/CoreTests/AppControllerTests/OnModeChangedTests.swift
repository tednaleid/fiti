// ABOUTME: Tests for AppController.onModeChanged — fires whenever `mode`
// ABOUTME: transitions, via a didSet observer. Single subscriber for now.

import Testing

@Suite("AppController onModeChanged")
@MainActor
struct OnModeChangedTests {
    private func make() -> (AppController, RecordingWindow) {
        let window = RecordingWindow()
        let editor = Editor(clock: VirtualClock(), ids: SeededIdGenerator(prefix: "s"))
        let controller = AppController(
            editor: editor,
            window: window,
            detector: RecordingStationaryDetector(),
            clock: VirtualClock(),
            ticker: RecordingFadeTicker()
        )
        return (controller, window)
    }

    @Test("activate publishes .activeIdle")
    func activate() {
        let (c, _) = make()
        var received: [AppController.Mode] = []
        c.onModeChanged = { received.append($0) }
        c.activate()
        #expect(received == [.activeIdle])
    }

    @Test("deactivate publishes .inactive")
    func deactivate() {
        let (c, _) = make()
        c.activate()
        var received: [AppController.Mode] = []
        c.onModeChanged = { received.append($0) }
        c.deactivate()
        #expect(received == [.inactive])
    }

    @Test("pointerDown publishes .activeDrawing")
    func pointerDown() {
        let (c, _) = make()
        c.activate()
        var received: [AppController.Mode] = []
        c.onModeChanged = { received.append($0) }
        c.pointerDown(StrokePoint(x: 0, y: 0))
        #expect(received == [.activeDrawing])
    }

    @Test("pointerUp returns mode to .activeIdle")
    func pointerUp() {
        let (c, _) = make()
        c.activate()
        c.pointerDown(StrokePoint(x: 0, y: 0))
        var received: [AppController.Mode] = []
        c.onModeChanged = { received.append($0) }
        c.pointerUp()
        #expect(received == [.activeIdle])
    }

    @Test("clear mid-stroke publishes .activeIdle")
    func clearMidStroke() {
        let (c, _) = make()
        c.activate()
        c.pointerDown(StrokePoint(x: 0, y: 0))
        var received: [AppController.Mode] = []
        c.onModeChanged = { received.append($0) }
        c.clear()
        #expect(received == [.activeIdle])
    }

    @Test("no callback fires when mode does not actually change")
    func noOpTransitions() {
        let (c, _) = make()
        c.activate()
        var received: [AppController.Mode] = []
        c.onModeChanged = { received.append($0) }
        c.activate()  // already activeIdle; guard returns early
        c.deactivate()
        c.deactivate()  // already inactive
        #expect(received == [.inactive])
    }
}
