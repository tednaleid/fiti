// ABOUTME: Tests for AppController.selectedStrokeIds and inFlightTransforms
// ABOUTME: — pure state + publishers. Gesture-driven population is in
// ABOUTME: SelectionGestureTests once the state machine lands.

import Testing

@Suite("AppController selection state")
@MainActor
struct SelectionStateTests {
    private func make() -> AppController {
        let clock = VirtualClock()
        let editor = Editor(clock: clock, ids: SeededIdGenerator(prefix: "s"))
        return AppController(
            editor: editor,
            window: RecordingWindow(),
            detector: RecordingStationaryDetector(),
            clock: clock,
            ticker: RecordingFadeTicker(),
            textMeasurer: FakeTextMeasurer()
        )
    }

    @Test("selectedStrokeIds defaults to empty")
    func selectedDefaultsEmpty() {
        let c = make()
        #expect(c.selectedStrokeIds == [])
    }

    @Test("onSelectionChanged fires on change")
    func selectionPublisher() {
        let c = make()
        var values: [[StrokeId]] = []
        c.onSelectionChanged = { values.append($0) }
        c.selectedStrokeIds = ["a", "b"]
        c.selectedStrokeIds = []
        #expect(values == [["a", "b"], []])
    }

    @Test("idempotent assignment does not fire publisher")
    func selectionIdempotent() {
        let c = make()
        var count = 0
        c.onSelectionChanged = { _ in count += 1 }
        c.selectedStrokeIds = []
        #expect(count == 0)
    }

    @Test("inFlightTransforms defaults to empty")
    func inFlightDefaultsEmpty() {
        let c = make()
        #expect(c.inFlightTransforms.isEmpty)
    }

    @Test("onInFlightTransformsChanged fires on change")
    func inFlightPublisher() {
        let c = make()
        var fireCount = 0
        c.onInFlightTransformsChanged = { _ in fireCount += 1 }
        c.inFlightTransforms = ["a": Transform(x: 1, y: 0, scale: 1, rotate: 0)]
        #expect(fireCount == 1)
        c.inFlightTransforms = [:]
        #expect(fireCount == 2)
    }
}
