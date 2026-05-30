// ABOUTME: ToolbarController's size/opacity popover policy — open/toggle/swap,
// ABOUTME: commit-pick write-through, edge selection, and trigger-highlight sync.

import AppKit

extension ToolbarController {
    func handleOpenPopover(axis: PresetAxis, anchor: NSRect) {
        if popover.isOpen, popover.currentAxis == axis {
            popover.close()
            updateTriggerHighlights()
            return
        }
        if popover.isOpen { popover.close() }

        let edge = pickEdge()
        let currentValue: Double
        switch axis {
        case .size: currentValue = controller.currentWidth
        case .opacity: currentValue = controller.currentColor.a
        }
        // markControl.currentTool already reflects the last drawing tool, because
        // controller.onCurrentToolChanged skips updating it when tool == .selection.
        let tool: Tool = markControl.currentTool
        popover.open(axis: axis,
                     currentValue: currentValue,
                     color: controller.currentColor,
                     width: controller.currentWidth,
                     tool: tool,
                     outlineOn: outlineOn(for: tool),
                     anchor: anchor,
                     edge: edge,
                     onPick: { [weak self] value in
                         self?.commitPick(axis: axis, value: value)
                     })
        updateTriggerHighlights()
    }

    func commitPick(axis: PresetAxis, value: Double) {
        switch axis {
        case .size:
            controller.currentWidth = value
        case .opacity:
            let c = controller.currentColor
            controller.currentColor = RGBA(r: c.r, g: c.g, b: c.b, a: value)
        }
        updateTriggerHighlights()
    }

    func pickEdge() -> PopoverEdge {
        guard let screen = panel.screen else { return .maxX }
        return PopoverEdgePicker.pick(toolbarMidX: Double(panel.frame.midX),
                                      screenMidX: Double(screen.frame.midX))
    }

    func updateTriggerHighlights() {
        markControl.setSizeButtonActive(popover.currentAxis == .size)
        markControl.setOpacityButtonActive(popover.currentAxis == .opacity)
    }
}
