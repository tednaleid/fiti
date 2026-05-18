// ABOUTME: Tests for AppController.onDrawingsVisibilityChanged — fires when
// ABOUTME: drawingsVisible toggles, via a didSet observer. Mirror of onModeChanged.

import Testing

@Suite("AppController onDrawingsVisibilityChanged")
@MainActor
struct OnDrawingsVisibilityChangedTests {
    private func make() -> AppController {
        let window = RecordingWindow()
        let editor = Editor(clock: VirtualClock(), ids: SeededIdGenerator(prefix: "s"))
        return AppController(
            editor: editor,
            window: window,
            detector: RecordingStationaryDetector(),
            clock: VirtualClock(),
            ticker: RecordingFadeTicker()
        )
    }

    @Test("drawingsVisible defaults to true")
    func defaultIsVisible() {
        let c = make()
        #expect(c.drawingsVisible == true)
    }

    @Test("toggling drawingsVisible publishes the new value")
    func togglePublishes() {
        let c = make()
        var received: [Bool] = []
        c.onDrawingsVisibilityChanged = { received.append($0) }
        c.drawingsVisible = false
        c.drawingsVisible = true
        #expect(received == [false, true])
    }

    @Test("setting the same value does not publish")
    func noOpTransition() {
        let c = make()
        c.drawingsVisible = true
        var received: [Bool] = []
        c.onDrawingsVisibilityChanged = { received.append($0) }
        c.drawingsVisible = true
        #expect(received == [])
    }

    @Test("default color is the red from the toolbar palette at 0.8 opacity")
    func defaultColor() {
        let c = make()
        #expect(c.currentColor.r == 224.0 / 255.0)
        #expect(c.currentColor.g == 49.0 / 255.0)
        #expect(c.currentColor.b == 49.0 / 255.0)
        #expect(c.currentColor.a == 0.8)
    }
}
