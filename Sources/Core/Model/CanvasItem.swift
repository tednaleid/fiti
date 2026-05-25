// ABOUTME: Sum type over everything the document can hold. Shared identity and
// ABOUTME: transform live here so selection/undo/render stay item-generic.

import Foundation

public enum CanvasItem: Equatable, Codable, Sendable {
    case stroke(Stroke)
    case text(TextItem)
    case arrow(ArrowItem)

    public var id: ItemId {
        switch self {
        case .stroke(let s): return s.id
        case .text(let t): return t.id
        case .arrow(let a): return a.id
        }
    }

    public var createdAt: Double {
        switch self {
        case .stroke(let s): return s.createdAt
        case .text(let t): return t.createdAt
        case .arrow(let a): return a.createdAt
        }
    }

    public var color: RGBA {
        switch self {
        case .stroke(let s): return s.color
        case .text(let t): return t.color
        case .arrow(let a): return a.color
        }
    }

    public var transform: Transform {
        get {
            switch self {
            case .stroke(let s): return s.transform
            case .text(let t): return t.transform
            case .arrow(let a): return a.transform
            }
        }
        set {
            switch self {
            case .stroke(var s): s.transform = newValue; self = .stroke(s)
            case .text(var t): t.transform = newValue; self = .text(t)
            case .arrow(var a): a.transform = newValue; self = .arrow(a)
            }
        }
    }

    /// Returns a copy with `color` replaced. Used when style shortcuts retarget
    /// the selection (see AppController.run).
    public func withColor(_ newColor: RGBA) -> CanvasItem {
        switch self {
        case .stroke(var s): s.color = newColor; return .stroke(s)
        case .text(var t): t.color = newColor; return .text(t)
        case .arrow(var a): a.color = newColor; return .arrow(a)
        }
    }

    /// Returns a copy with `color`'s RGB replaced but the item's own alpha kept.
    public func withColorPreservingAlpha(r: Double, g: Double, b: Double) -> CanvasItem {
        withColor(RGBA(r: r, g: g, b: b, a: color.a))
    }

    /// Returns a copy with `color`'s alpha replaced.
    public func withAlpha(_ newAlpha: Double) -> CanvasItem {
        withColor(color.with(a: newAlpha))
    }
}
