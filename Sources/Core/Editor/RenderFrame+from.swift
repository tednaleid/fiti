// ABOUTME: Convenience builder: assemble a RenderFrame from current Editor state.
// ABOUTME: Used by the App-layer wiring on every editor change notification.

import Foundation

public extension RenderFrame {
    @MainActor
    static func from(editor: Editor, canvasSize: Size) -> RenderFrame {
        from(editor: editor, canvasSize: canvasSize, overrides: [:])
    }

    @MainActor
    static func from(editor: Editor, canvasSize: Size, overrides: [StrokeId: Transform]) -> RenderFrame {
        var committed: [Stroke] = []
        var live: [Stroke] = []
        for id in editor.doc.itemOrder {
            guard case .stroke(let s) = editor.doc.items[id] else { continue }
            if let override = overrides[id] {
                var moved = s
                moved.transform = override
                live.append(moved)
            } else {
                committed.append(s)
            }
        }
        let inProgress: Stroke? = editor.currentStrokeId.flatMap {
            guard case .stroke(let s) = editor.doc.items[$0] else { return nil }
            return s
        }
        return RenderFrame(strokes: committed, liveStrokes: live,
                           inProgress: inProgress, canvasSize: canvasSize)
    }
}
