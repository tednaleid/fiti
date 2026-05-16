// ABOUTME: Protocol the dev HTTP server talks to. Production wires AppController + Editor;
// ABOUTME: tests wire FakeSurface for deterministic assertions.

import Foundation

public protocol DevHTTPSurface: AnyObject {
    var doc: FitiDoc { get }
    var mode: AppController.Mode { get }
    var clickThrough: Bool { get }
    var canvasSize: Size { get }
    var undoDepth: Int { get }
    var redoDepth: Int { get }
    var currentStrokeId: StrokeId? { get }

    func activate()
    func deactivate()
    func pointerDown(_ point: StrokePoint)
    func pointerMoved(_ point: StrokePoint)
    func pointerUp()
    func clear()
    func undo() -> Bool
    func redo() -> Bool
    func eraseStroke(_ id: StrokeId) -> Bool
    func snapshotPNG() -> Data?
}
