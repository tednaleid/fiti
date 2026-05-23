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
    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    public private(set) var currentStrokeId: ItemId?

    private let clock: Clock
    private let ids: IdGenerator
    private var listeners: [UUID: (ChangeKind) -> Void] = [:]

    public init(clock: Clock, ids: IdGenerator) {
        self.clock = clock
        self.ids = ids
    }

    // MARK: - Drawing

    @discardableResult
    public func startStroke(color: RGBA, width: Double, pointerType: PointerType) -> ItemId {
        precondition(currentStrokeId == nil, "stroke already in progress; call endStroke first")
        let id = ids.newItemId()
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
        doc.items[id] = .stroke(stroke)
        doc.itemOrder.append(id)
        currentStrokeId = id
        pushUndo(.deleteItem(id))
        emit(.local)
        return id
    }

    public func appendPoint(_ point: StrokePoint) {
        guard let id = currentStrokeId, case .stroke(var s)? = doc.items[id] else { return }
        s.points.append(point)
        doc.items[id] = .stroke(s)
        emit(.local)
    }

    public func straightenCurrentStroke() {
        guard let id = currentStrokeId, case .stroke(var s)? = doc.items[id],
              s.points.count >= 2 else { return }
        s.points = [s.points.first!, s.points.last!]
        s.snappedToLine = true
        doc.items[id] = .stroke(s)
        emit(.local)
    }

    public func moveCurrentStrokeEndpoint(to point: StrokePoint) {
        guard let id = currentStrokeId, case .stroke(var s)? = doc.items[id],
              !s.points.isEmpty else { return }
        s.points[s.points.count - 1] = point
        doc.items[id] = .stroke(s)
        emit(.local)
    }

    public func endStroke() {
        guard currentStrokeId != nil else { return }
        currentStrokeId = nil
        emit(.local)
    }

    @discardableResult
    public func eraseStroke(_ id: ItemId) -> Bool {
        guard let item = doc.items[id] else { return false }
        let atIndex = doc.itemOrder.firstIndex(of: id) ?? doc.itemOrder.count
        doc.items.removeValue(forKey: id)
        doc.itemOrder.removeAll { $0 == id }
        pushUndo(.restoreItem(snapshot: item, atIndex: atIndex))
        emit(.local)
        return true
    }

    @discardableResult
    public func eraseItems(ids: [ItemId]) -> Bool {
        let presentIds = ids.filter { doc.items[$0] != nil }
        guard !presentIds.isEmpty else { return false }
        let entries: [ItemRestoreEntry] = presentIds.compactMap { id in
            guard let item = doc.items[id] else { return nil }
            let idx = doc.itemOrder.firstIndex(of: id) ?? doc.itemOrder.count
            return ItemRestoreEntry(snapshot: item, atIndex: idx)
        }
        for id in presentIds {
            doc.items.removeValue(forKey: id)
            doc.itemOrder.removeAll { $0 == id }
        }
        pushUndo(.restoreItems(entries: entries))
        emit(.local)
        return true
    }

    @discardableResult
    public func transformItems(_ updates: [(id: ItemId, transform: Transform)]) -> Bool {
        let known = updates.filter { doc.items[$0.id] != nil }
        guard !known.isEmpty else { return false }
        let oldEntries: [TransformEntry] = known.compactMap { update in
            guard let item = doc.items[update.id] else { return nil }
            return TransformEntry(itemId: update.id, transform: item.transform)
        }
        for update in known {
            doc.items[update.id]?.transform = update.transform
        }
        pushUndo(.setTransforms(entries: oldEntries))
        emit(.local)
        return true
    }

    public func clear() {
        guard !doc.itemOrder.isEmpty else { return }
        let entries: [ItemRestoreEntry] = doc.itemOrder.enumerated().compactMap { idx, id in
            guard let item = doc.items[id] else { return nil }
            return ItemRestoreEntry(snapshot: item, atIndex: idx)
        }
        doc.items.removeAll()
        doc.itemOrder.removeAll()
        if currentStrokeId != nil { currentStrokeId = nil }
        pushUndo(.restoreItems(entries: entries))
        emit(.local)
    }

    // MARK: - Item-generic mutations

    public func addItem(_ item: CanvasItem) {
        doc.items[item.id] = item
        doc.itemOrder.append(item.id)
        pushUndo(.deleteItem(item.id))
        emit(.local)
    }

    @discardableResult
    public func replaceItem(_ item: CanvasItem) -> Bool {
        replaceItems([item])
    }

    /// Replaces several existing items in one undoable step. Unknown ids are
    /// skipped; returns false when none of the ids are present.
    @discardableResult
    public func replaceItems(_ items: [CanvasItem]) -> Bool {
        let priors: [CanvasItem] = items.compactMap { doc.items[$0.id] }
        guard !priors.isEmpty else { return false }
        for item in items where doc.items[item.id] != nil {
            doc.items[item.id] = item
        }
        pushUndo(.replaceItems(entries: priors))
        emit(.local)
        return true
    }

    public func newItemId() -> ItemId { ids.newItemId() }

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
        case .deleteItem(let id):              return applyDeleteItem(id)
        case .restoreItem(let s, let i):       return applyRestoreItem(snapshot: s, atIndex: i)
        case .deleteItems(let ids):            return applyDeleteItems(ids)
        case .restoreItems(let entries):       return applyRestoreItems(entries)
        case .setTransforms(let entries):      return applySetTransforms(entries)
        case .replaceItems(let entries):       return applyReplaceItems(entries)
        }
    }

    private func applyDeleteItem(_ id: ItemId) -> InverseOp? {
        guard let item = doc.items[id] else { return nil }
        let atIndex = doc.itemOrder.firstIndex(of: id) ?? doc.itemOrder.count
        doc.items.removeValue(forKey: id)
        doc.itemOrder.removeAll { $0 == id }
        return .restoreItem(snapshot: item, atIndex: atIndex)
    }

    private func applyRestoreItem(snapshot: CanvasItem, atIndex: Int) -> InverseOp? {
        doc.items[snapshot.id] = snapshot
        let insertAt = max(0, min(atIndex, doc.itemOrder.count))
        doc.itemOrder.insert(snapshot.id, at: insertAt)
        return .deleteItem(snapshot.id)
    }

    private func applyDeleteItems(_ ids: [ItemId]) -> InverseOp? {
        var entries: [ItemRestoreEntry] = []
        for id in ids {
            guard let item = doc.items[id] else { continue }
            let idx = doc.itemOrder.firstIndex(of: id) ?? doc.itemOrder.count
            entries.append(ItemRestoreEntry(snapshot: item, atIndex: idx))
        }
        for id in ids {
            doc.items.removeValue(forKey: id)
            doc.itemOrder.removeAll { $0 == id }
        }
        return .restoreItems(entries: entries)
    }

    private func applyRestoreItems(_ entries: [ItemRestoreEntry]) -> InverseOp? {
        // Insert in ascending atIndex order so earlier inserts don't shift later ones.
        let sorted = entries.sorted { $0.atIndex < $1.atIndex }
        for entry in sorted {
            doc.items[entry.snapshot.id] = entry.snapshot
            let insertAt = max(0, min(entry.atIndex, doc.itemOrder.count))
            doc.itemOrder.insert(entry.snapshot.id, at: insertAt)
        }
        return .deleteItems(entries.map { $0.snapshot.id })
    }

    private func applySetTransforms(_ entries: [TransformEntry]) -> InverseOp? {
        var currentEntries: [TransformEntry] = []
        for entry in entries {
            guard let item = doc.items[entry.itemId] else { continue }
            currentEntries.append(TransformEntry(itemId: entry.itemId, transform: item.transform))
            doc.items[entry.itemId]?.transform = entry.transform
        }
        return .setTransforms(entries: currentEntries)
    }

    private func applyReplaceItems(_ entries: [CanvasItem]) -> InverseOp? {
        var current: [CanvasItem] = []
        for item in entries {
            if let now = doc.items[item.id] { current.append(now) }
            doc.items[item.id] = item
        }
        return .replaceItems(entries: current)
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
