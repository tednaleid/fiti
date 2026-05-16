// ABOUTME: Sole mutation surface for FitiDoc. Owns undo/redo via InverseOp.
// ABOUTME: All edits go through methods on this class; no doc mutation elsewhere.

import Foundation

public enum ChangeKind: Sendable {
    case local, remote
}

public typealias Cancellable = () -> Void

public final class Editor {
    public private(set) var doc: FitiDoc = .empty
    public private(set) var undoStack: [InverseOp] = []
    public private(set) var redoStack: [InverseOp] = []
    public private(set) var currentStrokeId: StrokeId?

    private let clock: Clock
    private let ids: IdGenerator
    private var listeners: [UUID: (ChangeKind) -> Void] = [:]

    public init(clock: Clock, ids: IdGenerator) {
        self.clock = clock
        self.ids = ids
    }

    // MARK: - Drawing

    @discardableResult
    public func startStroke(color: RGBA, width: Double, pointerType: PointerType) -> StrokeId {
        precondition(currentStrokeId == nil, "stroke already in progress; call endStroke first")
        let id = ids.newStrokeId()
        let stroke = Stroke(
            id: id,
            color: color,
            width: width,
            transform: .identity,
            points: [],
            pointerType: pointerType,
            pressureEnabled: false,
            createdAt: clock.now()
        )
        doc.strokes[id] = stroke
        doc.strokeOrder.append(id)
        currentStrokeId = id
        pushUndo(.deleteStroke(id))
        emit(.local)
        return id
    }

    // MARK: - Undo plumbing

    private func pushUndo(_ op: InverseOp) {
        undoStack.append(op)
        redoStack.removeAll()
    }

    // MARK: - Listeners

    @discardableResult
    public func subscribe(_ listener: @escaping (ChangeKind) -> Void) -> Cancellable {
        let token = UUID()
        listeners[token] = listener
        return { [weak self] in self?.listeners.removeValue(forKey: token) }
    }

    private func emit(_ kind: ChangeKind) {
        for listener in listeners.values { listener(kind) }
    }
}
