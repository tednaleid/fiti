// ABOUTME: In-progress text edit state: the string being typed, caret position, and
// ABOUTME: pure mutation operations (insert, delete, newline, caret motion).

import Foundation

public struct TextEditSession: Equatable, Sendable {
    public var itemId: ItemId?
    public var string: String
    public var caret: Int
    public var transform: Transform
    public var color: RGBA
    public var fontName: String
    public var fontSize: Double

    public init(
        itemId: ItemId?,
        string: String,
        caret: Int,
        transform: Transform,
        color: RGBA,
        fontName: String,
        fontSize: Double
    ) {
        self.itemId = itemId
        self.string = string
        self.caret = caret
        self.transform = transform
        self.color = color
        self.fontName = fontName
        self.fontSize = fontSize
    }

    public enum CaretMove {
        case left, right, up, down, lineStart, lineEnd
    }

    /// Inserts `s` at the current caret position and advances the caret by `s.count`.
    public mutating func insert(_ s: String) {
        let idx = string.index(string.startIndex, offsetBy: caret)
        string.insert(contentsOf: s, at: idx)
        caret += s.count
    }

    /// Removes the character immediately before the caret. No-op when caret == 0.
    public mutating func deleteBackward() {
        guard caret > 0 else { return }
        let endIdx = string.index(string.startIndex, offsetBy: caret)
        let startIdx = string.index(before: endIdx)
        string.remove(at: startIdx)
        caret -= 1
    }

    /// Inserts a newline at the caret and advances the caret by 1.
    public mutating func insertNewline() {
        insert("\n")
    }

    /// Moves the caret in the given direction, clamped to valid positions.
    public mutating func moveCaret(_ dir: CaretMove) {
        switch dir {
        case .left:
            caret = max(0, caret - 1)
        case .right:
            caret = min(string.count, caret + 1)
        case .up:
            let (lineIndex, col) = lineAndColumn()
            guard lineIndex > 0 else { return }
            let lines = string.components(separatedBy: "\n")
            let targetLine = lines[lineIndex - 1]
            let clampedCol = min(col, targetLine.count)
            caret = absoluteIndex(line: lineIndex - 1, col: clampedCol, lines: lines)
        case .down:
            let (lineIndex, col) = lineAndColumn()
            let lines = string.components(separatedBy: "\n")
            guard lineIndex < lines.count - 1 else { return }
            let targetLine = lines[lineIndex + 1]
            let clampedCol = min(col, targetLine.count)
            caret = absoluteIndex(line: lineIndex + 1, col: clampedCol, lines: lines)
        case .lineStart:
            let (lineIndex, _) = lineAndColumn()
            let lines = string.components(separatedBy: "\n")
            caret = absoluteIndex(line: lineIndex, col: 0, lines: lines)
        case .lineEnd:
            let (lineIndex, _) = lineAndColumn()
            let lines = string.components(separatedBy: "\n")
            caret = absoluteIndex(line: lineIndex, col: lines[lineIndex].count, lines: lines)
        }
    }

    // MARK: - Private helpers

    /// Returns the (lineIndex, column) for the current caret position.
    private func lineAndColumn() -> (Int, Int) {
        let lines = string.components(separatedBy: "\n")
        var remaining = caret
        for (i, line) in lines.enumerated() {
            let lineLen = line.count
            if remaining <= lineLen {
                return (i, remaining)
            }
            remaining -= lineLen + 1  // +1 for the '\n'
        }
        // Fallback: last line end
        return (lines.count - 1, lines.last?.count ?? 0)
    }

    /// Computes the absolute character index for a given line and column.
    private func absoluteIndex(line: Int, col: Int, lines: [String]) -> Int {
        var index = 0
        for i in 0 ..< line {
            index += lines[i].count + 1  // +1 for the '\n'
        }
        return index + col
    }
}
