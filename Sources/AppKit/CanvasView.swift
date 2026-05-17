// ABOUTME: NSView that renders a RenderFrame via Core Graphics.
// ABOUTME: Two-canvas split: committed strokes baked to a CGImage and
// ABOUTME: redrawn only when strokeOrder changes; in-progress drawn live.

import AppKit
import CoreGraphics

public final class CanvasView: NSView, Renderer {
    private var lastFrame: RenderFrame?
    private var committedImage: CGImage?
    internal private(set) var committedSignature: [StrokeId] = []

    private var backingScale: CGFloat = 1

    // swiftlint:disable identifier_name
    /// Test-only override for `window?.backingScaleFactor`. When set, replaces
    /// the live window lookup in `render(_:)` so unit tests can simulate a
    /// retina display without needing a real screen attached.
    internal var testOnly_overrideBackingScale: CGFloat?

    internal var testOnly_committedImage: CGImage? { committedImage }
    // swiftlint:enable identifier_name

    public var drawingsVisible: Bool = true {
        didSet {
            if oldValue != drawingsVisible { needsDisplay = true }
        }
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    public override var isFlipped: Bool { true }

    // MARK: - Renderer

    public func render(_ frame: RenderFrame) {
        let inProgressId = frame.inProgress?.id
        let signature = frame.strokes.map(\.id).filter { $0 != inProgressId }
        let resolvedScale = testOnly_overrideBackingScale ?? window?.backingScaleFactor ?? 1
        if signature != committedSignature || resolvedScale != backingScale {
            backingScale = resolvedScale
            committedImage = bakeCommitted(frame, exclude: inProgressId)
            committedSignature = signature
        }
        lastFrame = frame
        needsDisplay = true
    }

    public override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext, let frame = lastFrame else { return }
        guard drawingsVisible else { return }
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        if let image = committedImage {
            let rect = CGRect(x: 0, y: 0, width: frame.canvasSize.width, height: frame.canvasSize.height)
            // CGContext.draw(image:in:) is not isFlipped-aware: it always lays the
            // image's bottom-left at rect.origin in CG-coords. In a flipped NSView
            // that puts the image upside down. Locally undo the view's flip so the
            // blit places the bake's top-origin pixels at the view's top.
            ctx.saveGState()
            ctx.translateBy(x: 0, y: rect.height)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(image, in: rect)
            ctx.restoreGState()
        }
        if let live = frame.inProgress, !live.points.isEmpty {
            drawStroke(live, in: ctx)
        }
    }

    private func bakeCommitted(_ frame: RenderFrame, exclude: StrokeId?) -> CGImage? {
        let pointWidth = Int(frame.canvasSize.width)
        let pointHeight = Int(frame.canvasSize.height)
        guard pointWidth > 0, pointHeight > 0 else { return nil }
        let pixelWidth = Int((CGFloat(pointWidth) * backingScale).rounded())
        let pixelHeight = Int((CGFloat(pointHeight) * backingScale).rounded())
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        // Order matters: flip first (in pixel space — the CGContext is sized in
        // pixels), then apply the scale CTM so drawStroke can keep using point
        // coordinates as if the context were point-sized.
        ctx.translateBy(x: 0, y: CGFloat(pixelHeight))
        ctx.scaleBy(x: 1, y: -1)
        ctx.scaleBy(x: backingScale, y: backingScale)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        for stroke in frame.strokes where stroke.id != exclude {
            drawStroke(stroke, in: ctx)
        }
        return ctx.makeImage()
    }
}
