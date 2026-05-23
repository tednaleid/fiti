// ABOUTME: A placed text mark — string + font + frozen layout bounds. Bounds are
// ABOUTME: measured by the AppKit/CoreText adapter at commit (see architecture.md, B4).

import Foundation

public struct TextItem: Equatable, Codable, Sendable {
    public let id: ItemId
    public var string: String          // may contain "\n"
    public var fontName: String
    public var fontSize: Double
    public var color: RGBA
    public var transform: Transform
    public var bounds: Size            // local-space layout size, frozen at commit
    public let createdAt: Double

    public init(id: ItemId, string: String, fontName: String, fontSize: Double,
                color: RGBA, transform: Transform, bounds: Size, createdAt: Double) {
        self.id = id
        self.string = string
        self.fontName = fontName
        self.fontSize = fontSize
        self.color = color
        self.transform = transform
        self.bounds = bounds
        self.createdAt = createdAt
    }
}
