// ABOUTME: Tests MarkControl — preset stepping via the buttons, edge-disabling,
// ABOUTME: preview ignores the selection tool, and crash-free real-pipeline rendering.

import AppKit
import Testing

@Suite("MarkControl")
@MainActor
struct MarkControlTests {
    @Test("size steppers fire onWidth with the next/previous preset")
    func sizeStepping() {
        let mc = MarkControl()
        var picked: [Double] = []
        mc.onWidth = { picked.append($0) }
        mc.width = 14
        mc.testOnly_tapSizeUp()    // 14 -> 20
        mc.testOnly_tapSizeDown()  // 14 -> 9 (still reads width 14; controller would update it)
        #expect(picked == [20, 9])
    }

    @Test("opacity steppers fire onOpacity with the next/previous preset")
    func opacityStepping() {
        let mc = MarkControl()
        var picked: [Double] = []
        mc.onOpacity = { picked.append($0) }
        mc.color = RGBA(r: 1, g: 0, b: 0, a: 0.5)
        mc.testOnly_tapOpacityUp()    // 0.5 -> 0.6
        mc.testOnly_tapOpacityDown()  // 0.5 -> 0.4
        #expect(picked.count == 2)
        #expect(abs(picked[0] - 0.6) < 0.0001)
        #expect(abs(picked[1] - 0.4) < 0.0001)
    }

    @Test("minus disables at the smallest preset, plus at the largest")
    func edgeDisabling() {
        let mc = MarkControl()
        mc.width = 2            // smallest size preset
        #expect(mc.testOnly_sizeMinusEnabled == false)
        #expect(mc.testOnly_sizePlusEnabled == true)
        mc.width = 100          // largest
        #expect(mc.testOnly_sizePlusEnabled == false)
        #expect(mc.testOnly_sizeMinusEnabled == true)
        mc.color = RGBA(r: 1, g: 0, b: 0, a: 0.1)   // smallest opacity
        #expect(mc.testOnly_opacityMinusEnabled == false)
        mc.color = RGBA(r: 1, g: 0, b: 0, a: 1.0)   // largest
        #expect(mc.testOnly_opacityPlusEnabled == false)
    }

    @Test("preview ignores the selection tool, keeping the prior drawing tool")
    func selectionKeepsPriorTool() {
        let mc = MarkControl()
        mc.currentTool = .text
        #expect(mc.testOnly_previewTool == .text)
        mc.currentTool = .selection
        #expect(mc.testOnly_previewTool == .text)   // unchanged
        mc.currentTool = .arrow
        #expect(mc.testOnly_previewTool == .arrow)
    }

    @Test("renders a preview image for each drawing tool and outline state")
    func rendersPreview() {
        let mc = MarkControl()
        mc.color = RGBA(r: 1, g: 0, b: 0, a: 1)
        mc.width = 30
        for tool in [Tool.pen, .arrow, .text] {
            for on in [false, true] {
                mc.currentTool = tool
                mc.outlineOn = on
                #expect(mc.testOnly_hasPreviewImage)
            }
        }
    }

    @Test("labels read 'size' and 'opacity' with the keyboard-hint tooltips")
    func labels() {
        let mc = MarkControl()
        #expect(mc.testOnly_sizeLabelText == "size")
        #expect(mc.testOnly_opacityLabelText == "opacity")
        #expect(mc.testOnly_sizeTooltip == "Size — s / S")
        #expect(mc.testOnly_opacityTooltip == "Opacity — o / O")
    }
}
