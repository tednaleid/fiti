// ABOUTME: t and p key commands switch the active tool.
// ABOUTME: Verifies both direct command dispatch and KeyCommandRegistry bindings.

import Testing

@MainActor
@Suite("Tool switch commands")
struct ToolSwitchTests {
    private func controller() -> AppController {
        let c = AppController(editor: Editor(clock: VirtualClock(), ids: SeededIdGenerator(prefix: "i")),
                              window: RecordingWindow(), detector: RecordingStationaryDetector(),
                              clock: VirtualClock(), ticker: RecordingFadeTicker())
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

    @Test("t and p are registered bindings")
    func bindings() {
        #expect(KeyCommandRegistry.command(for: KeyBinding(character: "t")) == .selectTool(.text))
        #expect(KeyCommandRegistry.command(for: KeyBinding(character: "p")) == .selectTool(.pen))
    }
}
