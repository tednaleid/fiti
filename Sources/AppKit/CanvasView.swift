// ABOUTME: NSView that renders a RenderFrame via Core Graphics.
// ABOUTME: Two-canvas split: committed strokes baked to a CGImage; in-flight (dragged)
// ABOUTME: and in-progress strokes drawn live so selection drags skip re-baking.

import AppKit
import CoreGraphics

struct BakeSignatureEntry: Equatable {
    let id: StrokeId
    let transform: Transform
}

public final class CanvasView: NSView, Renderer {
    private var lastFrame: RenderFrame?
    private var committedImage: CGImage?
    private var committedSignature: [BakeSignatureEntry] = []

    /// Exposed for tests only — do not use in production code.
    internal var bakeSignatureForTesting: [BakeSignatureEntry] { committedSignature }

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

    public private(set) var globalOpacity: Double = 1.0

    public func setGlobalOpacity(_ opacity: Double) {
        guard globalOpacity != opacity else { return }
        globalOpacity = opacity
        needsDisplay = true
    }

    public private(set) var selectionBounds: Rect?
    public private(set) var marqueeRect: Rect?

    public func setSelectionBounds(_ rect: Rect?) {
        guard selectionBounds != rect else { return }
        selectionBounds = rect
        needsDisplay = true
    }

    public func setMarquee(_ rect: Rect?) {
        guard marqueeRect != rect else { return }
        marqueeRect = rect
        needsDisplay = true
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
        // Signature covers only committed strokes — live strokes are excluded by
        // construction (they're in frame.liveStrokes, not frame.strokes).
        let signature = frame.strokes
            .filter { $0.id != inProgressId }
            .map { BakeSignatureEntry(id: $0.id, transform: $0.transform) }
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
        ctx.setAlpha(CGFloat(globalOpacity))
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
        for live in frame.liveStrokes {
            drawStroke(live, in: ctx, isInProgress: false)
        }
        if let live = frame.inProgress, !live.points.isEmpty {
            drawStroke(live, in: ctx, isInProgress: true)
        }
        // Reset alpha for selection/marquee overlays — they manage their own alpha.
        ctx.setAlpha(1.0)
        if let sel = selectionBounds {
            drawSelectionBox(sel, in: ctx)
        }
        if let marq = marqueeRect {
            drawMarquee(marq, in: ctx)
        }
    }

    private func drawSelectionBox(_ rect: Rect, in ctx: CGContext) {
        let cgRect = CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
        let accentColor = NSColor.controlAccentColor

        // Outline
        ctx.saveGState()
        accentColor.setStroke()
        ctx.setLineWidth(1)
        ctx.stroke(cgRect)

        // Corner handles: 6x6pt squares centered on each corner
        let handleSize: CGFloat = 6
        let offset: CGFloat = handleSize / 2
        let corners: [CGPoint] = [
            CGPoint(x: cgRect.minX, y: cgRect.minY),
            CGPoint(x: cgRect.maxX, y: cgRect.minY),
            CGPoint(x: cgRect.minX, y: cgRect.maxY),
            CGPoint(x: cgRect.maxX, y: cgRect.maxY)
        ]
        accentColor.setFill()
        for corner in corners {
            let handle = CGRect(x: corner.x - offset, y: corner.y - offset,
                                width: handleSize, height: handleSize)
            ctx.fill(handle)
        }

        // Rotation handle: circle 20pt above top midpoint, with a connecting line
        let topMidX = cgRect.midX
        let topY = cgRect.minY
        let rotHandleRadius: CGFloat = 6
        let rotHandleCenterY = topY - 20
        ctx.setLineWidth(1)
        ctx.strokeEllipse(in: CGRect(x: topMidX - rotHandleRadius,
                                     y: rotHandleCenterY - rotHandleRadius,
                                     width: rotHandleRadius * 2,
                                     height: rotHandleRadius * 2))
        ctx.move(to: CGPoint(x: topMidX, y: topY))
        ctx.addLine(to: CGPoint(x: topMidX, y: rotHandleCenterY + rotHandleRadius))
        ctx.strokePath()
        ctx.restoreGState()
    }

    private func drawMarquee(_ rect: Rect, in ctx: CGContext) {
        let cgRect = CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
        let accentColor = NSColor.controlAccentColor

        ctx.saveGState()
        // Faint fill
        accentColor.withAlphaComponent(0.15).setFill()
        ctx.fill(cgRect)

        // Dashed outline
        accentColor.setStroke()
        ctx.setLineWidth(1)
        ctx.setLineDash(phase: 0, lengths: [4, 4])
        ctx.stroke(cgRect)
        ctx.restoreGState()
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
            drawStroke(stroke, in: ctx, isInProgress: false)
        }
        return ctx.makeImage()
    }
}
