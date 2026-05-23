// ABOUTME: Semantic cursor the AppKit adapter renders into an NSCursor. Core
// ABOUTME: expresses intent (.brush for pen, .system for selection); the
// ABOUTME: adapter maps it to a platform cursor.

import Foundation

public enum SystemCursor: Equatable, Sendable {
    case arrow, openHand, closedHand, iBeam
    case resize(angle: Double)   // screen-space angle in {0,45,90,135}; adapter picks the platform cursor
    case rotate
}

public enum CursorSpec: Equatable, Sendable {
    case brush(color: RGBA, diameter: Double)
    case system(SystemCursor)

    /// Outline color contrasting with a brush fill (BT.601 luminance on RGB).
    public static func outlineColor(for fill: RGBA) -> RGBA {
        let luminance = 0.299 * fill.r + 0.587 * fill.g + 0.114 * fill.b
        return luminance > 0.5
            ? RGBA(r: 0, g: 0, b: 0, a: 0.5)
            : RGBA(r: 1, g: 1, b: 1, a: 0.5)
    }
}
