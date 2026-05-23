// ABOUTME: Data records describing how to reverse a mutation.
// ABOUTME: Editor.applyInverse consumes one and produces the paired inverse.

import Foundation

public struct ItemRestoreEntry: Equatable, Sendable {
    public let snapshot: CanvasItem
    public let atIndex: Int
    public init(snapshot: CanvasItem, atIndex: Int) {
        self.snapshot = snapshot
        self.atIndex = atIndex
    }
}

public struct TransformEntry: Equatable, Sendable {
    public let itemId: ItemId
    public let transform: Transform
    public init(itemId: ItemId, transform: Transform) {
        self.itemId = itemId
        self.transform = transform
    }
}

public enum InverseOp: Equatable, Sendable {
    case deleteItem(ItemId)
    case restoreItem(snapshot: CanvasItem, atIndex: Int)
    case deleteItems([ItemId])
    case restoreItems(entries: [ItemRestoreEntry])
    case setTransforms(entries: [TransformEntry])
    case replaceItems(entries: [CanvasItem])   // restore prior full values
}
