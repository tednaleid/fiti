// ABOUTME: contentTag hashes a CanvasItem's appearance-affecting fields so the bake
// ABOUTME: signature invalidates on style change. Split out to keep CanvasView under budget.

import Foundation

/// Hashes the appearance-affecting fields of an item so the bake signature
/// invalidates when style (not just transform) changes. Pure; no `self`.
func contentTag(for item: CanvasItem) -> Int {
    switch item {
    case .stroke(let s):
        var hasher = Hasher()
        hasher.combine(s.color.r)
        hasher.combine(s.color.g)
        hasher.combine(s.color.b)
        hasher.combine(s.color.a)
        hasher.combine(s.width)
        return hasher.finalize()
    case .text(let t):
        var hasher = Hasher()
        hasher.combine(t.string)
        hasher.combine(t.fontName)
        hasher.combine(t.fontSize)
        hasher.combine(t.color.r)
        hasher.combine(t.color.g)
        hasher.combine(t.color.b)
        hasher.combine(t.color.a)
        return hasher.finalize()
    case .arrow(let a):
        var hasher = Hasher()
        hasher.combine(a.color.r)
        hasher.combine(a.color.g)
        hasher.combine(a.color.b)
        hasher.combine(a.color.a)
        hasher.combine(a.width)
        hasher.combine(a.tail.x)
        hasher.combine(a.tail.y)
        hasher.combine(a.head.x)
        hasher.combine(a.head.y)
        return hasher.finalize()
    }
}
