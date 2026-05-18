// ABOUTME: Tests for AppController.onCurrentColorChanged / onCurrentWidthChanged
// ABOUTME: — fire when the drawing parameters change so adapters (toolbar widgets,
// ABOUTME: HTTP clients) can react to writes from any source.

import Testing

@Suite("AppController color/width didSet publication")
@MainActor
struct OnCurrentColorWidthChangedTests {
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

    @Test("assigning a new currentColor publishes via onCurrentColorChanged")
    func colorPublishes() {
        let c = make()
        var received: [RGBA] = []
        c.onCurrentColorChanged = { received.append($0) }
        c.currentColor = RGBA(r: 0.5, g: 0.5, b: 0.5, a: 0.5)
        #expect(received == [RGBA(r: 0.5, g: 0.5, b: 0.5, a: 0.5)])
    }

    @Test("assigning the same currentColor does not publish")
    func colorNoOp() {
        let c = make()
        let original = c.currentColor
        var received: [RGBA] = []
        c.onCurrentColorChanged = { received.append($0) }
        c.currentColor = original
        #expect(received == [])
    }

    @Test("assigning a new currentWidth publishes via onCurrentWidthChanged")
    func widthPublishes() {
        let c = make()
        var received: [Double] = []
        c.onCurrentWidthChanged = { received.append($0) }
        c.currentWidth = 12
        #expect(received == [12])
    }

    @Test("assigning the same currentWidth does not publish")
    func widthNoOp() {
        let c = make()
        let original = c.currentWidth
        var received: [Double] = []
        c.onCurrentWidthChanged = { received.append($0) }
        c.currentWidth = original
        #expect(received == [])
    }
}
