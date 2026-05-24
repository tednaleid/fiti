// ABOUTME: Pure overlap-aware grouping of canvas items into flattened layers,
// ABOUTME: keyed on (hue, alpha). Same-key marks merge unless a different key overlaps between them.

import Foundation

/// One flattened layer: marks of a single (hue, alpha) key, composited as a group.
/// Emitted bottom-to-top in final composite order.
public struct FlattenLayer: Equatable, Sendable {
    public let items: [CanvasItem]
    public init(items: [CanvasItem]) { self.items = items }
}

public enum LayerPlan {
    /// Group `items` (z-order, bottom first) into flattened layers in composite
    /// order. `aabb` returns an item's world-space bounds, or nil if it has none.
    public static func compute(items: [CanvasItem], aabb: (CanvasItem) -> Rect?) -> [FlattenLayer] {
        guard !items.isEmpty else { return [] }
        let boxes = items.map(aabb)
        let before = constraints(items: items, boxes: boxes)
        let order = clusteredOrder(items: items, before: before)
        return groupRuns(items: items, order: order)
    }

    /// before[j] = indices i < j that must composite before j (different key,
    /// overlapping). Edges only go low->high, so the graph is acyclic.
    private static func constraints(items: [CanvasItem], boxes: [Rect?]) -> [Set<Int>] {
        let n = items.count
        var before = Array(repeating: Set<Int>(), count: n)
        guard n > 1 else { return before }
        for j in 1..<n {
            for i in 0..<j {
                guard let bi = boxes[i], let bj = boxes[j] else { continue }
                if !sameKey(items[i].color, items[j].color), bi.intersects(bj) {
                    before[j].insert(i)
                }
            }
        }
        return before
    }

    /// Emit a constraint-respecting order that greedily clusters same-key items.
    private static func clusteredOrder(items: [CanvasItem], before: [Set<Int>]) -> [Int] {
        let n = items.count
        var emitted = Array(repeating: false, count: n)
        var order: [Int] = []
        order.reserveCapacity(n)
        var lastKey: RGBA?
        for _ in 0..<n {
            let chosen = nextIndex(items: items, before: before, emitted: emitted, lastKey: lastKey)
            emitted[chosen] = true
            order.append(chosen)
            lastKey = items[chosen].color
        }
        return order
    }

    /// Among items whose predecessors are all emitted, prefer one whose key
    /// matches `lastKey`, else the earliest eligible. The smallest un-emitted
    /// index is always eligible, so a value always exists.
    private static func nextIndex(items: [CanvasItem], before: [Set<Int>],
                                  emitted: [Bool], lastKey: RGBA?) -> Int {
        var fallback: Int?
        for k in 0..<items.count where !emitted[k] {
            guard before[k].allSatisfy({ emitted[$0] }) else { continue }
            if fallback == nil { fallback = k }
            if let lk = lastKey, sameKey(items[k].color, lk) { return k }
        }
        return fallback ?? 0
    }

    /// Group consecutive same-key items in `order` into layers.
    private static func groupRuns(items: [CanvasItem], order: [Int]) -> [FlattenLayer] {
        var layers: [FlattenLayer] = []
        var current: [CanvasItem] = []
        for idx in order {
            let item = items[idx]
            if let first = current.first, !sameKey(first.color, item.color) {
                layers.append(FlattenLayer(items: current))
                current = []
            }
            current.append(item)
        }
        if !current.isEmpty { layers.append(FlattenLayer(items: current)) }
        return layers
    }

    private static func sameKey(_ a: RGBA, _ b: RGBA) -> Bool {
        a.r == b.r && a.g == b.g && a.b == b.b && a.a == b.a
    }
}
