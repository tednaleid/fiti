// ABOUTME: Port for measuring text geometry. The AppKit adapter implements it
// ABOUTME: with CoreText; tests use a deterministic monospace fake.

import Foundation

public protocol TextMeasuring: Sendable {
    func measure(string: String, fontName: String, fontSize: Double) -> Size
    func caretIndex(at localPoint: Point, string: String,
                    fontName: String, fontSize: Double) -> Int
}
