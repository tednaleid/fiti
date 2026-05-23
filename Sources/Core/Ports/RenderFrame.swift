// ABOUTME: Immutable snapshot the renderer draws. Committed items are baked;
// ABOUTME: live items (in-flight transforms) and the in-progress pen draw live.

import Foundation

public struct RenderFrame: Equatable, Sendable {
    public var items: [CanvasItem]          // committed, baked
    public var liveItems: [CanvasItem]      // in-flight transform overrides, drawn live
    public var inProgress: Stroke?          // pen stroke being actively drawn, drawn live
    public var canvasSize: Size             // logical points

    public init(items: [CanvasItem], liveItems: [CanvasItem] = [],
                inProgress: Stroke?, canvasSize: Size) {
        self.items = items
        self.liveItems = liveItems
        self.inProgress = inProgress
        self.canvasSize = canvasSize
    }
}
