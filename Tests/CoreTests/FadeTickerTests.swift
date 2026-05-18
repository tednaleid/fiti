// ABOUTME: Tests for the RecordingFadeTicker double — covers start/stop bookkeeping
// ABOUTME: and the tick(at:) helper that drives AppController fade state in unit tests.

import Testing

@Suite("RecordingFadeTicker")
@MainActor
struct FadeTickerTests {
    @Test("initial state is stopped")
    func initialState() {
        let ticker = RecordingFadeTicker()
        #expect(ticker.isRunning == false)
    }

    @Test("start() flips isRunning to true")
    func startRuns() {
        let ticker = RecordingFadeTicker()
        ticker.start()
        #expect(ticker.isRunning == true)
    }

    @Test("stop() flips isRunning back to false")
    func stopStops() {
        let ticker = RecordingFadeTicker()
        ticker.start()
        ticker.stop()
        #expect(ticker.isRunning == false)
    }

    @Test("tick(at:) calls onTick when running")
    func tickFiresWhenRunning() {
        let ticker = RecordingFadeTicker()
        var received: Double?
        ticker.onTick = { received = $0 }
        ticker.start()
        ticker.tick(at: 42.5)
        #expect(received == 42.5)
    }

    @Test("tick(at:) is a no-op when stopped")
    func tickNoOpsWhenStopped() {
        let ticker = RecordingFadeTicker()
        var fireCount = 0
        ticker.onTick = { _ in fireCount += 1 }
        ticker.tick(at: 1)
        #expect(fireCount == 0)
    }
}
