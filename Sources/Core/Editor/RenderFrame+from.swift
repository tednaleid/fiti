// ABOUTME: Convenience builder: assemble a RenderFrame from current Editor state.
// ABOUTME: Used by the App-layer wiring on every editor change notification.

import Foundation

public extension RenderFrame {
    @MainActor
    static func from(editor: Editor, canvasSize: Size) -> RenderFrame {
        from(editor: editor, canvasSize: canvasSize, overrides: [:], editingItemId: nil)
    }

    @MainActor
    static func from(editor: Editor, canvasSize: Size, overrides: [ItemId: Transform]) -> RenderFrame {
        from(editor: editor, canvasSize: canvasSize, overrides: overrides, editingItemId: nil)
    }

    @MainActor
    static func from(editor: Editor, canvasSize: Size,
                     overrides: [ItemId: Transform], editingItemId: ItemId?) -> RenderFrame {
        var committed: [CanvasItem] = []
        var live: [CanvasItem] = []
        for id in editor.doc.itemOrder {
            guard id != editingItemId, var item = editor.doc.items[id] else { continue }
            if let override = overrides[id] {
                item.transform = override
                live.append(item)
            } else {
                committed.append(item)
            }
        }
        let inProgress: CanvasItem? = {
            if let id = editor.currentStrokeId, case .stroke(let s)? = editor.doc.items[id] {
                return .stroke(s)
            }
            if let a = editor.currentArrow { return .arrow(a) }
            return nil
        }()
        return RenderFrame(items: committed, liveItems: live,
                           inProgress: inProgress, canvasSize: canvasSize)
    }
}
