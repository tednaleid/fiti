// ABOUTME: Active tool in the selection / drawing surface. Lives parallel to
// ABOUTME: AppController.Mode — orthogonal: any active mode can host any tool.

import Foundation

public enum Tool: Equatable, Hashable, Sendable {
    case pen
    case selection
    case text
    case arrow

    /// The tools that draw a mark and therefore carry their own remembered style.
    /// `.selection` is a meta tool with no mark of its own.
    public static let drawingTools: [Tool] = [.pen, .text, .arrow]

    public var isDrawingTool: Bool { Self.drawingTools.contains(self) }
}
