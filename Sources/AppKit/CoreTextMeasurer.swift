// ABOUTME: CoreText-backed implementation of the TextMeasuring port.
// ABOUTME: Measures string layout by splitting on newlines and querying CTLine.

import AppKit
import CoreText

public struct CoreTextMeasurer: TextMeasuring {
    public init() {}

    public func measure(string: String, fontName: String, fontSize: Double) -> Size {
        let font = NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        let lh = Double(lineHeight(for: font))
        let lines = string.components(separatedBy: "\n")
        let maxWidth = lines.map { lineWidth(for: $0, font: font) }.max() ?? 0
        let totalHeight = Double(lines.count) * lh
        return Size(width: max(maxWidth, 1), height: max(totalHeight, 1))
    }

    public func caretIndex(at localPoint: Point, string: String,
                           fontName: String, fontSize: Double) -> Int {
        let font = NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        let lh = Double(lineHeight(for: font))
        let lines = string.components(separatedBy: "\n")
        let lineIndex = max(0, min(Int(localPoint.y / lh), lines.count - 1))

        // Sum of character offsets before this line (including newlines).
        let priorCount = lines[..<lineIndex].reduce(0) { $0 + $1.count + 1 }

        let lineString = lines[lineIndex]
        let ctLine = buildCTLine(for: lineString, font: font)
        let column = CTLineGetStringIndexForPosition(ctLine, CGPoint(x: localPoint.x, y: 0))
        let clampedColumn = max(0, min(column, lineString.count))

        return max(0, min(priorCount + clampedColumn, string.count))
    }

    // MARK: - Helpers

    private func lineWidth(for string: String, font: NSFont) -> Double {
        let line = buildCTLine(for: string, font: font)
        return CTLineGetTypographicBounds(line, nil, nil, nil)
    }

    private func buildCTLine(for string: String, font: NSFont) -> CTLine {
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let attributed = NSAttributedString(string: string, attributes: attrs)
        return CTLineCreateWithAttributedString(attributed)
    }
}
