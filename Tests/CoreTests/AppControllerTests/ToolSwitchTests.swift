// ABOUTME: t and p key commands switch the active tool.
// ABOUTME: Verifies both direct command dispatch and KeyCommandRegistry bindings.

import Testing

@MainActor
@Suite("Tool switch commands")
struct ToolSwitchTests {
    private func controller() -> AppController {
        let c = AppController(editor: Editor(clock: VirtualClock(), ids: SeededIdGenerator(prefix: "i")),
                              window: RecordingWindow(), detector: RecordingStationaryDetector(),
                              clock: VirtualClock(), ticker: RecordingFadeTicker(),
                              textMeasurer: FakeTextMeasurer())
        c.activate(); return c
    }

    @Test("t selects text, p selects pen")
    func toolKeys() {
        let c = controller()
        c.run(.selectTool(.text))
        #expect(c.currentTool == .text)
        c.run(.selectTool(.pen))
        #expect(c.currentTool == .pen)
    }

    @Test("t and d are registered bindings")
    func bindings() {
        #expect(KeyCommandRegistry.command(for: KeyBinding(character: "t")) == .selectTool(.text))
        #expect(KeyCommandRegistry.command(for: KeyBinding(character: "d")) == .selectTool(.pen))
    }
}
