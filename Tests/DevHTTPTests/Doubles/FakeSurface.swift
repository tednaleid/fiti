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
    public var currentStrokeId: StrokeId?

    public var activateCalls = 0
    public var deactivateCalls = 0
    public var clearCalls = 0
    public var undoCalls = 0
    public var redoCalls = 0
    public var erasedIds: [StrokeId] = []
    public var pointerEvents: [(String, StrokePoint?)] = []
    public var snapshotPNGReturn: Data? = Data([0x89, 0x50, 0x4E, 0x47])

    public init() {}

    public func activate() { activateCalls += 1 }
    public func deactivate() { deactivateCalls += 1 }
    public func pointerDown(_ p: StrokePoint) { pointerEvents.append(("down", p)) }
    public func pointerMoved(_ p: StrokePoint) { pointerEvents.append(("move", p)) }
    public func pointerUp() { pointerEvents.append(("up", nil)) }
    public func clear() { clearCalls += 1 }
    public func undo() -> Bool { undoCalls += 1; return true }
    public func redo() -> Bool { redoCalls += 1; return true }
    public func eraseStroke(_ id: StrokeId) -> Bool { erasedIds.append(id); return true }
    public func snapshotPNG() -> Data? { snapshotPNGReturn }
}
