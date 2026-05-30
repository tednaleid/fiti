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
    var textOutline: Bool { get }
    var arrowOutline: Bool { get }
    var penOutline: Bool { get }
    var popoverOpen: Bool { get }
    var popoverAxis: PresetAxis? { get }

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
    /// Set one tool's outline ("text" | "arrow" | "pen"). Returns false if unknown.
    func setOutline(tool: String, enabled: Bool) -> Bool
    /// Open or toggle the size/opacity popover (re-triggering the same axis closes it).
    func triggerPopover(axis: PresetAxis)
    /// PNG of the open popover panel, or nil when closed.
    func popoverPNG() -> Data?
    /// PNG of the whole toolbar panel (always available while the toolbar is up).
    func toolbarPNG() -> Data?
}
#endif
