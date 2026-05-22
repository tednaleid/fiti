// ABOUTME: A selection box that can be rotated — center, local size, and a
// ABOUTME: rotation in degrees. Pure geometry; the renderer and hit-testing
// ABOUTME: read its corners / rotate node / world↔local transform.

import Foundation

public struct OrientedBox: Equatable, Sendable {
    public var center: Point
    public var size: Size
    public var rotation: Double  // degrees

    public init(center: Point, size: Size, rotation: Double) {
        self.center = center
        self.size = size
        self.rotation = rotation
    }

    private var halfW: Double { size.width / 2 }
    private var halfH: Double { size.height / 2 }

    /// World-space corners, ordered topLeft, topRight, bottomRight, bottomLeft
    /// (in a y-down screen coordinate system: top = smaller y).
    public func corners() -> [Point] {
        [Point(x: -halfW, y: -halfH),
         Point(x: halfW, y: -halfH),
         Point(x: halfW, y: halfH),
         Point(x: -halfW, y: halfH)].map(worldFromLocal)
    }

    /// World-space center of the rotate node, `offset` above the top-edge midpoint.
    public func rotateNode(offset: Double) -> Point {
        worldFromLocal(Point(x: 0, y: -halfH - offset))
    }

    /// Maps a world point into the box's local (unrotated, center-origin) frame.
    public func toLocal(_ p: Point) -> Point {
        let dx = p.x - center.x
        let dy = p.y - center.y
        let a = -rotation * .pi / 180
        let c = cos(a), s = sin(a)
        return Point(x: dx * c - dy * s, y: dx * s + dy * c)
    }

    private func worldFromLocal(_ p: Point) -> Point {
        let a = rotation * .pi / 180
        let c = cos(a), s = sin(a)
        return Point(x: center.x + p.x * c - p.y * s,
                     y: center.y + p.x * s + p.y * c)
    }
}
