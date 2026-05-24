// ABOUTME: One drawn arrow: frozen tail/head endpoints, style, and transform.
// ABOUTME: A first-class CanvasItem case; head is rendered at `head`, the lift point.

import Foundation

public struct ArrowItem: Equatable, Codable, Sendable {
    public let id: ItemId
    public var color: RGBA
    public var width: Double
    public var transform: Transform
    public var tail: Point        // local coords, frozen at commit
    public var head: Point        // local coords, frozen at commit
    public let createdAt: Double  // seconds since epoch

    public init(id: ItemId, color: RGBA, width: Double, transform: Transform,
                tail: Point, head: Point, createdAt: Double) {
        self.id = id
        self.color = color
        self.width = width
        self.transform = transform
        self.tail = tail
        self.head = head
        self.createdAt = createdAt
    }
}
