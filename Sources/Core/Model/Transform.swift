// ABOUTME: Per-stroke affine transform applied on top of frozen point geometry.
// ABOUTME: POC always uses .identity; drag/resize/rotate edits land later.

import Foundation

public struct Transform: Equatable, Codable, Sendable {
    public var x: Double
    public var y: Double
    public var scale: Double
    public var rotate: Double  // degrees

    public init(x: Double, y: Double, scale: Double, rotate: Double) {
        self.x = x
        self.y = y
        self.scale = scale
        self.rotate = rotate
    }

    public static let identity = Transform(x: 0, y: 0, scale: 1, rotate: 0)
}
