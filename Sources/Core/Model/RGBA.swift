// ABOUTME: sRGB color with linear-floating-point components in 0...1.
// ABOUTME: Stored on every Stroke; serialized in HTTP /doc responses.

import Foundation

public struct RGBA: Equatable, Hashable, Codable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double
    public var a: Double

    public init(r: Double, g: Double, b: Double, a: Double) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }
}

public extension RGBA {
    /// Returns a copy with `a` replaced. Used by AppController.run(.bumpOpacity:)
    /// to avoid spelling out all four fields.
    func with(a newAlpha: Double) -> RGBA {
        RGBA(r: r, g: g, b: b, a: newAlpha)
    }
}
