// ABOUTME: Pure popover-edge enum and picker. Determines whether the size/opacity
// ABOUTME: popover extends right (.maxX) or left (.minX) of its anchor.

import Foundation

public enum PopoverEdge: Equatable, Sendable {
    /// Popover extends to the right of the anchor.
    case maxX
    /// Popover extends to the left of the anchor.
    case minX
}

public enum PopoverEdgePicker {
    /// Returns `.maxX` when the toolbar's horizontal center is strictly left of
    /// the screen's midpoint (popover extends right); `.minX` otherwise.
    public static func pick(toolbarMidX: Double, screenMidX: Double) -> PopoverEdge {
        toolbarMidX < screenMidX ? .maxX : .minX
    }
}
