// ABOUTME: Tests for AppController.currentTool — defaults, publisher, and
// ABOUTME: cursor behavior (selection tool returns the system arrow).

import Testing

@Suite("AppController.currentTool")
@MainActor
struct ToolStateTests {
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

    @Test("currentTool defaults to .pen")
    func defaultsToPen() {
        let c = make()
        #expect(c.currentTool == .pen)
    }

    @Test("onCurrentToolChanged publisher fires on transition")
    func publisherFires() {
        let c = make()
        var values: [Tool] = []
        c.onCurrentToolChanged = { values.append($0) }
        c.currentTool = .selection
        c.currentTool = .pen
        #expect(values == [.selection, .pen])
    }

    @Test("setting currentTool to its current value does not fire publisher")
    func idempotent() {
        let c = make()
        var count = 0
        c.onCurrentToolChanged = { _ in count += 1 }
        c.currentTool = .pen
        #expect(count == 0)
    }

    @Test("cursor is .system(.arrow) while currentTool is .selection in an active mode")
    func cursorUnderSelection() {
        let c = make()
        c.activate()
        #expect(c.currentCursor != nil)
        c.currentTool = .selection
        #expect(c.currentCursor == .system(.arrow))
        c.currentTool = .pen
        #expect(c.currentCursor != nil)
    }
}
