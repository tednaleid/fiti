// ABOUTME: Adapter-side value carrying the live text-edit state the canvas needs to render.
// ABOUTME: Maps from the Core TextEditSession so AppKit details stay out of Core.

import Foundation

/// Carries the live text-session state used by CanvasView to draw the
/// in-progress string and cursor caret. Constructed from a Core
/// `TextEditSession` at the App-layer wiring site.
public struct TextSessionSnapshot: Equatable, Sendable {
    public let string: String
    public let caret: Int
    public let transform: Transform
    public let color: RGBA
    public let fontName: String
    public let fontSize: Double

    public init(
        string: String,
        caret: Int,
        transform: Transform,
        color: RGBA,
        fontName: String,
        fontSize: Double
    ) {
        self.string = string
        self.caret = caret
        self.transform = transform
        self.color = color
        self.fontName = fontName
        self.fontSize = fontSize
    }

    /// Convenience init that lifts a Core `TextEditSession` into this snapshot.
    public init(_ session: TextEditSession) {
        self.init(
            string: session.string,
            caret: session.caret,
            transform: session.transform,
            color: session.color,
            fontName: session.fontName,
            fontSize: session.fontSize
        )
    }
}
