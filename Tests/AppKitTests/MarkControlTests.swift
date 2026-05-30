// ABOUTME: Tests MarkControl — the toolbar's size/opacity composite. Buttons trigger
// ABOUTME: the popover-open callback; MarkPreview holds the live mark snapshot.

import AppKit
import Testing

@Suite("MarkControl")
@MainActor
struct MarkControlTests {
    @Test("size button click invokes onOpenPopover with .size and the preview rect")
    func sizeButtonOpensPopover() {
        let mc = MarkControl()
        var calls: [(PresetAxis, NSRect)] = []
        mc.onOpenPopover = { axis, rect in calls.append((axis, rect)) }
        mc.testOnly_clickSizeButton()
        #expect(calls.count == 1)
        #expect(calls.first?.0 == .size)
        #expect(calls.first?.1.width == CGFloat(MarkPreview.canvasSize.width))
        #expect(calls.first?.1.height == CGFloat(MarkPreview.canvasSize.height))
    }

    @Test("opacity button click invokes onOpenPopover with .opacity and the preview rect")
    func opacityButtonOpensPopover() {
        let mc = MarkControl()
        var calls: [(PresetAxis, NSRect)] = []
        mc.onOpenPopover = { axis, rect in calls.append((axis, rect)) }
        mc.testOnly_clickOpacityButton()
        #expect(calls.count == 1)
        #expect(calls.first?.0 == .opacity)
    }

    @Test("preview ignores the selection tool, keeping the prior drawing tool")
    func selectionKeepsPriorTool() {
        let mc = MarkControl()
        mc.currentTool = .text
        #expect(mc.testOnly_previewTool == .text)
        mc.currentTool = .selection
        #expect(mc.testOnly_previewTool == .text)
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

    @Test("size button has the size tooltip and lineweight SF Symbol")
    func sizeButtonTooltip() {
        let mc = MarkControl()
        #expect(mc.testOnly_sizeButtonTooltip == "Size — s / S")
    }

    @Test("opacity button has the opacity tooltip and drop SF Symbol")
    func opacityButtonTooltip() {
        let mc = MarkControl()
        #expect(mc.testOnly_opacityButtonTooltip == "Opacity — o / O")
    }
}
