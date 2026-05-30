// ABOUTME: Tests MarkPreview — 60x140 mark snapshot view, used by the toolbar and
// ABOUTME: re-used (via static render) by each PresetPopover cell.

import AppKit
import Testing

@Suite("MarkPreview")
@MainActor
struct MarkPreviewTests {
    @Test("renders a snapshot image for each drawing tool with outline on and off")
    func rendersForEachTool() {
        let mp = MarkPreview()
        mp.color = RGBA(r: 1, g: 0, b: 0, a: 1)
        mp.width = 30
        for tool in [Tool.pen, .arrow, .text] {
            for on in [false, true] {
                mp.currentTool = tool
                mp.outlineOn = on
                #expect(mp.testOnly_hasPreviewImage)
            }
        }
    }

    @Test("setting currentTool = .selection keeps the previously-set previewTool")
    func selectionKeepsPriorTool() {
        let mp = MarkPreview()
        mp.currentTool = .text
        #expect(mp.testOnly_previewTool == .text)
        mp.currentTool = .selection
        #expect(mp.testOnly_previewTool == .text)
        mp.currentTool = .arrow
        #expect(mp.testOnly_previewTool == .arrow)
    }

    @Test("static render returns a non-nil image for the standard preview inputs")
    func staticRenderProducesImage() {
        let img = MarkPreview.render(tool: .pen,
                                     color: RGBA(r: 0.5, g: 0.5, b: 0.5, a: 1),
                                     width: 14,
                                     outlineOn: false)
        #expect(img != nil)
    }

    @Test("canvasSize is 60x140 logical points")
    func canvasSize() {
        #expect(MarkPreview.canvasSize.width == 60)
        #expect(MarkPreview.canvasSize.height == 140)
    }

    @Test("axis(forY:) maps the top half to size and the bottom half to opacity")
    func axisByHalf() {
        // Non-flipped view: y grows upward, so the visual top is the larger y.
        #expect(MarkPreview.axis(forY: 139, height: 140) == .size)     // top
        #expect(MarkPreview.axis(forY: 71, height: 140) == .size)      // just above midpoint
        #expect(MarkPreview.axis(forY: 70, height: 140) == .size)      // midpoint counts as top
        #expect(MarkPreview.axis(forY: 69, height: 140) == .opacity)   // just below midpoint
        #expect(MarkPreview.axis(forY: 1, height: 140) == .opacity)    // bottom
    }

    @Test("clicking the top half fires onHalfClick(.size), bottom half (.opacity)")
    func halfClickFires() {
        let mp = MarkPreview()
        mp.frame = NSRect(x: 0, y: 0, width: 60, height: 140)
        var picks: [PresetAxis] = []
        mp.onHalfClick = { picks.append($0) }
        mp.testOnly_click(atY: 130)  // top
        mp.testOnly_click(atY: 10)   // bottom
        #expect(picks == [.size, .opacity])
    }
}
