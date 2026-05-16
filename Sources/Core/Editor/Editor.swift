// ABOUTME: Sole mutation surface for FitiDoc. Owns undo/redo via InverseOp.
// ABOUTME: All edits go through methods on this class; no doc mutation elsewhere.

import Foundation

public enum ChangeKind: Sendable {
    case local, remote
}

public typealias Cancellable = () -> Void

@MainActor
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

    public func appendPoint(_ point: StrokePoint) {
        guard let id = currentStrokeId else { return }
        doc.strokes[id]?.points.append(point)
        emit(.local)
    }

    public func endStroke() {
        guard currentStrokeId != nil else { return }
        currentStrokeId = nil
        emit(.local)
    }

    @discardableResult
    public func eraseStroke(_ id: StrokeId) -> Bool {
        guard let stroke = doc.strokes[id] else { return false }
        let atIndex = doc.strokeOrder.firstIndex(of: id) ?? doc.strokeOrder.count
        doc.strokes.removeValue(forKey: id)
        doc.strokeOrder.removeAll { $0 == id }
        pushUndo(.restoreStroke(snapshot: stroke, atIndex: atIndex))
        emit(.local)
        return true
    }

    public func clear() {
        guard !doc.strokeOrder.isEmpty else { return }
        let entries: [StrokeRestoreEntry] = doc.strokeOrder.enumerated().compactMap { idx, id in
            guard let s = doc.strokes[id] else { return nil }
            return StrokeRestoreEntry(snapshot: s, atIndex: idx)
        }
        doc.strokes.removeAll()
        doc.strokeOrder.removeAll()
        if currentStrokeId != nil { currentStrokeId = nil }
        pushUndo(.restoreStrokes(entries: entries))
        emit(.local)
    }

    // MARK: - Undo / redo

    @discardableResult
    public func undo() -> Bool {
        guard let op = undoStack.popLast() else { return false }
        if let inverse = applyInverse(op) {
            redoStack.append(inverse)
        }
        emit(.local)
        return true
    }

    @discardableResult
    public func redo() -> Bool {
        guard let op = redoStack.popLast() else { return false }
        if let inverse = applyInverse(op) {
            undoStack.append(inverse)
        }
        emit(.local)
        return true
    }

    private func applyInverse(_ op: InverseOp) -> InverseOp? {
        switch op {
        case .deleteStroke(let id):
            guard let stroke = doc.strokes[id] else { return nil }
            let atIndex = doc.strokeOrder.firstIndex(of: id) ?? doc.strokeOrder.count
            doc.strokes.removeValue(forKey: id)
            doc.strokeOrder.removeAll { $0 == id }
            return .restoreStroke(snapshot: stroke, atIndex: atIndex)

        case .restoreStroke(let snapshot, let atIndex):
            doc.strokes[snapshot.id] = snapshot
            let insertAt = max(0, min(atIndex, doc.strokeOrder.count))
            doc.strokeOrder.insert(snapshot.id, at: insertAt)
            return .deleteStroke(snapshot.id)

        case .deleteStrokes(let ids):
            var entries: [StrokeRestoreEntry] = []
            for id in ids {
                guard let stroke = doc.strokes[id] else { continue }
                let idx = doc.strokeOrder.firstIndex(of: id) ?? doc.strokeOrder.count
                entries.append(StrokeRestoreEntry(snapshot: stroke, atIndex: idx))
            }
            for id in ids {
                doc.strokes.removeValue(forKey: id)
                doc.strokeOrder.removeAll { $0 == id }
            }
            return .restoreStrokes(entries: entries)

        case .restoreStrokes(let entries):
            // Insert in ascending atIndex order so earlier inserts don't shift later ones.
            let sorted = entries.sorted { $0.atIndex < $1.atIndex }
            for entry in sorted {
                doc.strokes[entry.snapshot.id] = entry.snapshot
                let insertAt = max(0, min(entry.atIndex, doc.strokeOrder.count))
                doc.strokeOrder.insert(entry.snapshot.id, at: insertAt)
            }
            return .deleteStrokes(entries.map { $0.snapshot.id })
        }
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
        for listener in Array(listeners.values) { listener(kind) }
    }
}
