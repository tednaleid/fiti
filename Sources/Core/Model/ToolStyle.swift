// ABOUTME: A drawing tool's remembered style — color (opacity in the alpha) and the
// ABOUTME: stroke/font width. Pen, text, and arrow each keep their own across switches.

import Foundation

public struct ToolStyle: Equatable, Sendable {
    public var color: RGBA
    public var width: Double

    public init(color: RGBA, width: Double) {
        self.color = color
        self.width = width
    }

    /// The product default applied to every tool on first run: red #e03131 at 0.8
    /// opacity, width 6. Matches the historical global default.
    public static let `default` = ToolStyle(
        color: RGBA(r: 224.0 / 255.0, g: 49.0 / 255.0, b: 49.0 / 255.0, a: 0.8),
        width: 6)
}
