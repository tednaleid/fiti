// ABOUTME: NSView that renders a RenderFrame via Core Graphics.
// ABOUTME: Conforms to Renderer; called from the wiring layer on every editor change.

import AppKit
import CoreGraphics

public final class CanvasView: NSView, Renderer {
    private var currentFrame: RenderFrame?

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    // MARK: - Renderer

    public func render(_ frame: RenderFrame) {
        currentFrame = frame
        self.needsDisplay = true
    }

    public override var isFlipped: Bool { true }

    public override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext, let frame = currentFrame else { return }

        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        for stroke in frame.strokes {
            drawStroke(stroke, in: ctx)
        }
        if let inProgress = frame.inProgress, !inProgress.points.isEmpty {
            drawStroke(inProgress, in: ctx)
        }
    }
}
