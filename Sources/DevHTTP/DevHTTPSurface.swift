// ABOUTME: Protocol the dev HTTP server talks to. Production wires AppController + Editor;
// ABOUTME: tests wire FakeSurface for deterministic assertions.

#if DEBUG
import Foundation

@MainActor
public protocol DevHTTPSurface: AnyObject {
    var doc: FitiDoc { get }
    var mode: AppController.Mode { get }
    var clickThrough: Bool { get }
    var canvasSize: Size { get }
    var undoDepth: Int { get }
    var redoDepth: Int { get }
    var currentStrokeId: ItemId? { get }
    var currentColor: RGBA { get }
    var currentWidth: Double { get }
    var drawingsVisible: Bool { get }
    var currentTool: Tool { get }
    var isEditingText: Bool { get }
    var editingText: String? { get }

    func activate()
    func deactivate()
    func setTool(_ tool: Tool)
    func typeText(_ text: String)
    func textNewline()
    func textBackspace()
    func textCommit()
    func textEscape()
    func moveTextCaret(_ direction: TextEditSession.CaretMove)
    func pointerDown(_ point: StrokePoint)
    func pointerMoved(_ point: StrokePoint)
    func pointerUp()
    func clear()
    func undo() -> Bool
    func redo() -> Bool
    func eraseStroke(_ id: ItemId) -> Bool
    func snapshotPNG() -> Data?
    func setColor(_ color: RGBA)
    func setWidth(_ width: Double)
    func setDrawingsVisible(_ visible: Bool)
}
#endif
