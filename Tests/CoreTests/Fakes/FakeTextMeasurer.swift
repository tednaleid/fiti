// ABOUTME: Deterministic monospace fake implementing TextMeasuring for tests.
// ABOUTME: Formula: charWidth = fontSize/2; multiline uses 1.5x line spacing.

import Foundation

public struct FakeTextMeasurer: TextMeasuring {
    public init() {}

    public func measure(string: String, fontName: String, fontSize: Double) -> Size {
        let charWidth = fontSize / 2
        let lines = string.components(separatedBy: "\n")
        let newlineCount = lines.count - 1
        let maxLineLength = lines.map(\.count).max() ?? 0
        let width = Double(maxLineLength) * charWidth
        let height = fontSize + Double(newlineCount) * fontSize * 1.5
        return Size(width: width, height: height)
    }

    public func caretIndex(at localPoint: Point, string: String,
                           fontName: String, fontSize: Double) -> Int {
        let charWidth = fontSize / 2
        let lineHeight = fontSize * 1.5
        let lines = string.components(separatedBy: "\n")
        let rawLineIndex = Int(localPoint.y / lineHeight)
        let lineIndex = max(0, min(rawLineIndex, lines.count - 1))
        let line = lines[lineIndex]
        let col = min(Int(localPoint.x / charWidth), line.count)
        let priorOffset = lines[..<lineIndex].reduce(0) { $0 + $1.count + 1 }
        return priorOffset + col
    }
}
