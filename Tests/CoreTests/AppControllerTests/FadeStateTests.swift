// ABOUTME: Tests for AppController fade properties — toggle on/off, ticker
// ABOUTME: start/stop bookkeeping, opacity reset behavior. Tick state machine
// ABOUTME: behavior lives in FadeTickTests.

import Testing

@Suite("AppController fade state")
@MainActor
struct FadeStateTests {
    // swiftlint:disable:next large_tuple
    private func make() -> (AppController, VirtualClock, RecordingFadeTicker, OpacityRecorder) {
        let clock = VirtualClock()
        let ticker = RecordingFadeTicker()
        let window = RecordingWindow()
        let editor = Editor(clock: clock, ids: SeededIdGenerator(prefix: "s"))
        let controller = AppController(
            editor: editor,
            window: window,
            detector: RecordingStationaryDetector(),
            clock: clock,
            ticker: ticker
        )
        let rec = OpacityRecorder()
        controller.onFadeOpacityChanged = { rec.opacities.append($0) }
        return (controller, clock, ticker, rec)
    }

    private final class OpacityRecorder {
        var opacities: [Double] = []
    }

    @Test("initial state: autoFade off, opacity 1.0, ticker stopped")
    func initialState() {
        let (c, _, ticker, _) = make()
        #expect(c.autoFadeEnabled == false)
        #expect(c.fadeOpacity == 1.0)
        #expect(ticker.isRunning == false)
    }

    @Test("toggling autoFadeEnabled on starts the ticker")
    func toggleOnStartsTicker() {
        let (c, _, ticker, _) = make()
        c.autoFadeEnabled = true
        #expect(ticker.isRunning == true)
    }

    @Test("toggling autoFadeEnabled off stops the ticker and resets opacity to 1.0")
    func toggleOffStopsAndResets() {
        let (c, _, ticker, _) = make()
        c.autoFadeEnabled = true
        c.fadeOpacity = 0.5
        c.autoFadeEnabled = false
        #expect(ticker.isRunning == false)
        #expect(c.fadeOpacity == 1.0)
    }

    @Test("onAutoFadeEnabledChanged fires on each value change")
    func autoFadeChangePublisher() {
        let (c, _, _, _) = make()
        var values: [Bool] = []
        c.onAutoFadeEnabledChanged = { values.append($0) }
        c.autoFadeEnabled = true
        c.autoFadeEnabled = false
        #expect(values == [true, false])
    }

    @Test("idempotent autoFade set does not re-fire the publisher")
    func idempotentAutoFadeSet() {
        let (c, _, _, _) = make()
        var count = 0
        c.onAutoFadeEnabledChanged = { _ in count += 1 }
        c.autoFadeEnabled = true
        c.autoFadeEnabled = true
        #expect(count == 1)
    }

    @Test("onFadeOpacityChanged fires when opacity changes")
    func opacityPublisher() {
        let (c, _, _, rec) = make()
        c.fadeOpacity = 0.75
        #expect(rec.opacities.last == 0.75)
    }
}
