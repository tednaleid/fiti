// ABOUTME: Pure-Core axis-aligned bounding rectangle. Used by SelectionMath
// ABOUTME: and the AppKit renderer for selection box / marquee geometry.

import Foundation

public struct Rect: Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var maxX: Double { x + width }
    public var maxY: Double { y + height }

    public func intersects(_ other: Rect) -> Bool {
        x <= other.maxX && other.x <= maxX && y <= other.maxY && other.y <= maxY
    }

    public func contains(_ p: StrokePoint) -> Bool {
        p.x >= x && p.x <= maxX && p.y >= y && p.y <= maxY
    }
}
