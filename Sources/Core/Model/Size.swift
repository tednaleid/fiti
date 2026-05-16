// ABOUTME: Logical-point size for canvas dimensions.
// ABOUTME: Avoids importing CoreGraphics in Sources/Core.

import Foundation

public struct Size: Equatable, Codable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}
