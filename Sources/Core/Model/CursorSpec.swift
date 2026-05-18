// ABOUTME: Cursor data the AppKit cursor adapter renders into an NSCursor.
// ABOUTME: Today: filled circle for the pen tool. Future tool variants split this into an enum.

import Foundation

public struct CursorSpec: Equatable, Sendable {
    public let color: RGBA
    public let diameter: Double

    public init(color: RGBA, diameter: Double) {
        self.color = color
        self.diameter = diameter
    }

    /// Picks an outline color that contrasts with the fill so the cursor stays
    /// visible against backgrounds of similar color. Uses BT.601 relative
    /// luminance on the RGB components only — alpha is ignored so a low-opacity
    /// stroke color still picks an outline based on its color identity, not its
    /// transparency. The outline alpha is 0.5 so the ring stays subtle and
    /// doesn't compete with the fill color for the eye's attention.
    public static func outlineColor(for fill: RGBA) -> RGBA {
        let luminance = 0.299 * fill.r + 0.587 * fill.g + 0.114 * fill.b
        return luminance > 0.5
            ? RGBA(r: 0, g: 0, b: 0, a: 0.5)
            : RGBA(r: 1, g: 1, b: 1, a: 0.5)
    }
}
