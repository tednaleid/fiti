// ABOUTME: Snapshot a Renderer needs to draw the current state.
// ABOUTME: Built from Editor state by the wiring layer.

import Foundation

public struct RenderFrame: Equatable, Sendable {
    public var strokes: [Stroke]            // committed strokes to bake (excludes in-flight overrides)
    public var liveStrokes: [Stroke]        // in-flight (dragged) strokes, drawn live with override transforms
    public var inProgress: Stroke?          // pen stroke being actively drawn, drawn live
    public var canvasSize: Size             // logical points

    public init(strokes: [Stroke], liveStrokes: [Stroke] = [], inProgress: Stroke?, canvasSize: Size) {
        self.strokes = strokes
        self.liveStrokes = liveStrokes
        self.inProgress = inProgress
        self.canvasSize = canvasSize
    }
}
