// ABOUTME: In-memory Renderer for tests. Captures every frame for assertion.

import Foundation

public final class RecordingRenderer: Renderer {
    public private(set) var frames: [RenderFrame] = []
    public init() {}
    public func render(_ frame: RenderFrame) { frames.append(frame) }
}
