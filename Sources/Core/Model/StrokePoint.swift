// ABOUTME: One sample on a freehand stroke — (x, y, pressure) in logical points.
// ABOUTME: Pressure defaults to 0.5 for mouse input; real values come from pen later.

import Foundation

public struct StrokePoint: Equatable, Codable, Sendable {
    public var x: Double
    public var y: Double
    public var pressure: Double

    public init(x: Double, y: Double, pressure: Double = 0.5) {
        self.x = x
        self.y = y
        self.pressure = pressure
    }
}
