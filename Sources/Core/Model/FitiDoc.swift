// ABOUTME: The drawing document — keyed map of items plus an ordered id list.
// ABOUTME: Map for identity, list for z-order. CRDT-friendly.

import Foundation

public struct FitiDoc: Equatable, Codable, Sendable {
    public var items: [ItemId: CanvasItem]
    public var itemOrder: [ItemId]

    public init(items: [ItemId: CanvasItem] = [:], itemOrder: [ItemId] = []) {
        self.items = items
        self.itemOrder = itemOrder
    }

    public static let empty = FitiDoc()
}
