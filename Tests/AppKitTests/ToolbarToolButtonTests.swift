// ABOUTME: Tests for the toolbar's pen/text/arrow tool buttons — selecting a tool and
// ABOUTME: keeping the active-state highlight in sync with controller.currentTool.

import AppKit
import Testing

@Suite("ToolbarController tool buttons")
@MainActor
struct ToolbarToolButtonTests {
    private func make() -> (ToolbarController, AppController) {
        let clock = VirtualClock()
        let editor = Editor(clock: clock, ids: SeededIdGenerator(prefix: "s"))
        let controller = AppController(
            editor: editor,
            window: RecordingWindow(),
            detector: RecordingStationaryDetector(),
            clock: clock,
            ticker: RecordingFadeTicker(),
            textMeasurer: CoreTextMeasurer()
        )
        let toolbar = ToolbarController(controller: controller,
                                        defaults: UserDefaults(suiteName: UUID().uuidString)!)
        return (toolbar, controller)
    }

    @Test("pen tool button is active on init (default tool is pen)")
    func penToolActiveOnInit() {
        let (toolbar, _) = make()
        #expect(toolbar.testOnly_penActiveBackground == true)
        #expect(toolbar.testOnly_textActiveBackground == false)
        #expect(toolbar.testOnly_arrowActiveBackground == false)
    }

    @Test("clicking the arrow button selects the arrow tool and moves the highlight")
    func clickArrowSelectsArrowTool() {
        let (toolbar, controller) = make()
        toolbar.testOnly_clickArrow()
        #expect(controller.currentTool == .arrow)
        #expect(toolbar.testOnly_arrowActiveBackground == true)
        #expect(toolbar.testOnly_penActiveBackground == false)
        #expect(toolbar.testOnly_textActiveBackground == false)
    }

    @Test("external arrow tool change updates the tool-button highlight")
    func externalArrowToolChangeUpdatesHighlight() {
        let (toolbar, controller) = make()
        controller.currentTool = .arrow  // e.g. via the `a` keyboard shortcut
        #expect(toolbar.testOnly_arrowActiveBackground == true)
        #expect(toolbar.testOnly_penActiveBackground == false)
    }

    @Test("clicking the text button selects the text tool and moves the highlight")
    func clickTextSelectsTextTool() {
        let (toolbar, controller) = make()
        toolbar.testOnly_clickText()
        #expect(controller.currentTool == .text)
        #expect(toolbar.testOnly_textActiveBackground == true)
        #expect(toolbar.testOnly_penActiveBackground == false)
    }

    @Test("clicking the pen button selects the pen tool and moves the highlight")
    func clickPenSelectsPenTool() {
        let (toolbar, controller) = make()
        controller.currentTool = .text
        toolbar.testOnly_clickPen()
        #expect(controller.currentTool == .pen)
        #expect(toolbar.testOnly_penActiveBackground == true)
        #expect(toolbar.testOnly_textActiveBackground == false)
    }

    @Test("external tool change updates the tool-button highlight")
    func externalToolChangeUpdatesHighlight() {
        let (toolbar, controller) = make()
        controller.currentTool = .text  // e.g. via the `t` keyboard shortcut
        #expect(toolbar.testOnly_textActiveBackground == true)
        #expect(toolbar.testOnly_penActiveBackground == false)
    }

    @Test("tool buttons have shortcut tooltips")
    func toolButtonTooltips() {
        let (toolbar, _) = make()
        #expect(toolbar.testOnly_penTooltip == "Pen — p")
        #expect(toolbar.testOnly_textTooltip == "Text — t")
        #expect(toolbar.testOnly_arrowTooltip == "Arrow — a")
    }
}
