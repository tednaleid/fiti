// ABOUTME: In-memory DevHTTPSurface for route tests. Records every method call.
// ABOUTME: All properties start in a sensible default state for deterministic assertions.

import Foundation

public final class FakeSurface: DevHTTPSurface {
    public var doc: FitiDoc = .empty
    public var mode: AppController.Mode = .inactive
    public var clickThrough: Bool = true
    public var canvasSize: Size = Size(width: 1440, height: 900)
    public var undoDepth: Int = 0
    public var redoDepth: Int = 0
    public var currentStrokeId: ItemId?
    public var currentColor: RGBA = RGBA(r: 1, g: 0, b: 0, a: 1)
    public var currentWidth: Double = 6
    public var drawingsVisible: Bool = true
    public var currentTool: Tool = .pen
    public var isEditingText: Bool = false
    public var editingText: String?
    public var outlineEnabled: Bool = false

    public var activateCalls = 0
    public var deactivateCalls = 0
    public var clearCalls = 0
    public var undoCalls = 0
    public var redoCalls = 0
    public var erasedIds: [ItemId] = []
    public var pointerEvents: [(String, StrokePoint?)] = []
    public var snapshotPNGReturn: Data? = Data([0x89, 0x50, 0x4E, 0x47])
    public var lastTypedText: String?
    public var textActions: [String] = []
    public var lastCaretMove: TextEditSession.CaretMove?

    public init() {}

    public func activate() { activateCalls += 1 }
    public func deactivate() { deactivateCalls += 1 }
    public func pointerDown(_ p: StrokePoint) { pointerEvents.append(("down", p)) }
    public func pointerMoved(_ p: StrokePoint) { pointerEvents.append(("move", p)) }
    public func pointerUp() { pointerEvents.append(("up", nil)) }
    public func clear() { clearCalls += 1 }
    public func undo() -> Bool { undoCalls += 1; return true }
    public func redo() -> Bool { redoCalls += 1; return true }
    public func eraseStroke(_ id: ItemId) -> Bool { erasedIds.append(id); return true }
    public func snapshotPNG() -> Data? { snapshotPNGReturn }
    public func setColor(_ color: RGBA) { currentColor = color }
    public func setWidth(_ width: Double) { currentWidth = width }
    public func setDrawingsVisible(_ visible: Bool) { drawingsVisible = visible }
    public func setOutline(_ enabled: Bool) { outlineEnabled = enabled }

    public func setTool(_ tool: Tool) {
        currentTool = tool
        if tool == .text { isEditingText = true }
    }

    public func typeText(_ text: String) {
        lastTypedText = text
        textActions.append("type:\(text)")
        editingText = (editingText ?? "") + text
    }

    public func textNewline() { textActions.append("newline") }
    public func textBackspace() { textActions.append("backspace") }

    public func textCommit() {
        textActions.append("commit")
        isEditingText = false
    }

    public func textEscape() {
        textActions.append("escape")
        isEditingText = false
    }

    public func moveTextCaret(_ direction: TextEditSession.CaretMove) {
        lastCaretMove = direction
        textActions.append("caret:\(direction)")
    }
}
