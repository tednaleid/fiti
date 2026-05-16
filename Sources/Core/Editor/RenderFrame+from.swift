// ABOUTME: Convenience builder: assemble a RenderFrame from current Editor state.
// ABOUTME: Used by the App-layer wiring on every editor change notification.

import Foundation

public extension RenderFrame {
    static func from(editor: Editor, canvasSize: Size) -> RenderFrame {
        let strokes = editor.doc.strokeOrder.compactMap { editor.doc.strokes[$0] }
        let inProgress = editor.currentStrokeId.flatMap { editor.doc.strokes[$0] }
        return RenderFrame(strokes: strokes, inProgress: inProgress, canvasSize: canvasSize)
    }
}
