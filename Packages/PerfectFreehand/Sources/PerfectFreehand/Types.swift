// ABOUTME: Ported from perfect-freehand@1.2.3/types.ts (MIT, Steve Ruiz).
// ABOUTME: Public types — StrokeOptions, TaperOptions, Point2D, StrokeInputPoint.

import Foundation

public struct Point2D: Sendable, Equatable, Codable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public protocol StrokeInputPoint {
    var x: Double { get }
    var y: Double { get }
    var pressure: Double? { get }
}

public struct StrokeOptions: Sendable {
    public var size: Double = 8
    public init() {}
}
