// ABOUTME: Plain 2D point in logical canvas coordinates. Distinct from
// ABOUTME: StrokePoint (which carries pressure); used by selection geometry.

import Foundation

public struct Point: Equatable, Hashable, Codable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}
