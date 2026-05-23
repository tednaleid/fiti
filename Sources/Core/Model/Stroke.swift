// ABOUTME: One drawn stroke — frozen geometry + per-stroke metadata.
// ABOUTME: Points freeze at endStroke; later edits target `transform`.

import Foundation

public struct Stroke: Equatable, Codable, Sendable {
    public let id: StrokeId
    public var color: RGBA
    public var width: Double
    public var transform: Transform
    public var points: [StrokePoint]
    public let pointerType: PointerType
    public let pressureEnabled: Bool
    public let createdAt: Double  // seconds since epoch
    // Marks strokes whose geometry is final and only the endpoint moves
    // (e.g. hold-to-straighten rubber-banding). Drives `last: true` at render
    // time so perfect-freehand does not trim the polygon end.
    public var snappedToLine: Bool

    public init(
        id: StrokeId,
        color: RGBA,
        width: Double,
        transform: Transform,
        points: [StrokePoint],
        pointerType: PointerType,
        pressureEnabled: Bool,
        createdAt: Double,
        snappedToLine: Bool = false
    ) {
        self.id = id
        self.color = color
        self.width = width
        self.transform = transform
        self.points = points
        self.pointerType = pointerType
        self.pressureEnabled = pressureEnabled
        self.createdAt = createdAt
        self.snappedToLine = snappedToLine
    }
}
