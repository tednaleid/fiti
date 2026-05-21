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
        let strokes = editor.doc.strokeOrder.compactMap { id -> Stroke? in
            guard var s = editor.doc.strokes[id] else { return nil }
            if let override = overrides[id] { s.transform = override }
            return s
        }
        let inProgress = editor.currentStrokeId.flatMap { editor.doc.strokes[$0] }
        return RenderFrame(strokes: strokes, inProgress: inProgress, canvasSize: canvasSize)
    }
}
