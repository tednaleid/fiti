// ABOUTME: Per-tool style memory — pen/text/arrow each remember their own color,
// ABOUTME: opacity, and width across tool switches; selection passes through.

import Testing

@Suite("AppController per-tool style")
@MainActor
struct ToolStyleTests {
    private func make() -> AppController {
        let clock = VirtualClock()
        return AppController(
            editor: Editor(clock: clock, ids: SeededIdGenerator(prefix: "t")),
            window: RecordingWindow(),
            detector: RecordingStationaryDetector(),
            clock: clock,
            ticker: RecordingFadeTicker(),
            textMeasurer: FakeTextMeasurer()
        )
    }

    private let red = RGBA(r: 1, g: 0, b: 0, a: 0.9)
    private let blue = RGBA(r: 0, g: 0, b: 1, a: 0.4)

    @Test("each drawing tool remembers its own color and width across switches")
    func remembersPerTool() {
        let c = make()
        c.currentTool = .pen
        c.currentColor = red
        c.currentWidth = 10

        c.currentTool = .text
        c.currentColor = blue
        c.currentWidth = 30

        c.currentTool = .pen
        #expect(c.currentColor == red)
        #expect(c.currentWidth == 10)

        c.currentTool = .text
        #expect(c.currentColor == blue)
        #expect(c.currentWidth == 30)

        c.currentTool = .arrow                       // never customized -> default
        #expect(c.currentColor == ToolStyle.default.color)
        #expect(c.currentWidth == ToolStyle.default.width)
    }

    @Test("switching to selection keeps the last drawing tool's active style")
    func selectionKeepsActiveStyle() {
        let c = make()
        c.currentTool = .pen
        c.currentColor = red
        c.currentWidth = 10

        c.currentTool = .selection
        #expect(c.currentColor == red)
        #expect(c.currentWidth == 10)
    }

    @Test("editing style in selection mode with no selection updates the last drawing tool")
    func selectionNoSelectionEditsLastDrawingTool() {
        let c = make()
        c.currentTool = .pen
        c.currentTool = .selection      // no selection
        c.run(.bumpOpacity(.up))        // falls through to the drawing default
        c.currentColor = blue           // direct edit (e.g. toolbar swatch) in selection

        c.currentTool = .pen
        #expect(c.currentColor == blue) // the selection-mode edit landed in pen's slot
    }

    @Test("style(for:) and loadStyles round-trip per-tool styles")
    func loadStylesAppliesCurrentTool() {
        let c = make()
        c.loadStyles([.pen: ToolStyle(color: red, width: 10),
                      .text: ToolStyle(color: blue, width: 30),
                      .arrow: .default])
        #expect(c.style(for: .text) == ToolStyle(color: blue, width: 30))
        // current tool is .pen at construction, so its style is live now
        #expect(c.currentColor == red)
        #expect(c.currentWidth == 10)
    }
}
