// ABOUTME: Sum type over everything the document can hold. Shared identity and
// ABOUTME: transform live here so selection/undo/render stay item-generic.

import Foundation

public enum CanvasItem: Equatable, Codable, Sendable {
    case stroke(Stroke)
    case text(TextItem)

    public var id: ItemId {
        switch self {
        case .stroke(let s): return s.id
        case .text(let t): return t.id
        }
    }

    public var createdAt: Double {
        switch self {
        case .stroke(let s): return s.createdAt
        case .text(let t): return t.createdAt
        }
    }

    public var color: RGBA {
        switch self {
        case .stroke(let s): return s.color
        case .text(let t): return t.color
        }
    }

    public var transform: Transform {
        get {
            switch self {
            case .stroke(let s): return s.transform
            case .text(let t): return t.transform
            }
        }
        set {
            switch self {
            case .stroke(var s): s.transform = newValue; self = .stroke(s)
            case .text(var t): t.transform = newValue; self = .text(t)
            }
        }
    }
}
