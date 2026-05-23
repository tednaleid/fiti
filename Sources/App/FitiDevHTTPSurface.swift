// ABOUTME: Production DevHTTPSurface — bridges AppController + Editor to the
// ABOUTME: dev HTTP server. Lives in Sources/App because it imports both
// ABOUTME: Core (AppController) and AppKit (SnapshotRenderer).

#if DEBUG
import Foundation

public final class FitiDevHTTPSurface: DevHTTPSurface {
    private let controller: AppController
    private let canvasSizeProvider: () -> Size

    public init(controller: AppController, canvasSize: @escaping () -> Size) {
        self.controller = controller
        self.canvasSizeProvider = canvasSize
    }

    public var doc: FitiDoc { controller.editor.doc }
    public var mode: AppController.Mode { controller.mode }
    public var clickThrough: Bool { mode == .inactive }
    public var canvasSize: Size { canvasSizeProvider() }
    public var undoDepth: Int { controller.editor.undoStack.count }
    public var redoDepth: Int { controller.editor.redoStack.count }
    public var currentStrokeId: StrokeId? { controller.editor.currentStrokeId }
    public var currentColor: RGBA { controller.currentColor }
    public var currentWidth: Double { controller.currentWidth }
    public var drawingsVisible: Bool { controller.drawingsVisible }
    public var currentTool: Tool { controller.currentTool }
    public var isEditingText: Bool { controller.isEditingText }
    public var editingText: String? { controller.textSession?.string }

    public func activate() { controller.activate() }
    public func deactivate() { controller.deactivate() }

    // Auto-activate so the dev client can switch tools without first POSTing /activate.
    public func setTool(_ tool: Tool) {
        if controller.mode == .inactive { controller.activate() }
        controller.currentTool = tool
    }

    public func typeText(_ text: String) { controller.insertText(text) }
    public func textNewline() { controller.insertNewline() }
    public func textBackspace() { controller.deleteBackward() }
    public func textCommit() { controller.commitText() }
    public func textEscape() { controller.escapePressed() }
    public func moveTextCaret(_ direction: TextEditSession.CaretMove) { controller.moveCaret(direction) }

    public func setColor(_ color: RGBA) { controller.currentColor = color }
    public func setWidth(_ width: Double) { controller.currentWidth = width }
    public func setDrawingsVisible(_ visible: Bool) { controller.drawingsVisible = visible }

    // HTTP routes bypass the activation gate. Auto-activate so the dev client
    // can drive drawing without first POSTing /activate.
    public func pointerDown(_ p: StrokePoint) {
        if controller.mode == .inactive { controller.activate() }
        controller.pointerDown(p)
    }

    public func pointerMoved(_ p: StrokePoint) {
        if controller.mode == .inactive { controller.activate() }
        if controller.mode == .activeIdle {
            controller.pointerDown(p)
        } else {
            controller.pointerMoved(p)
        }
    }

    public func pointerUp() {
        if controller.mode == .activeDrawing { controller.pointerUp() }
    }

    public func clear() { controller.editor.clear() }
    public func undo() -> Bool { controller.editor.undo() }
    public func redo() -> Bool { controller.editor.redo() }
    public func eraseStroke(_ id: StrokeId) -> Bool { controller.editor.eraseStroke(id) }

    public func snapshotPNG() -> Data? {
        let frame = RenderFrame.from(editor: controller.editor, canvasSize: canvasSize)
        return SnapshotRenderer.png(from: frame)
    }
}
#endif
