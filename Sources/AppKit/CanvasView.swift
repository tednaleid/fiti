// ABOUTME: NSView that renders a RenderFrame via Core Graphics.
// ABOUTME: Two-canvas split: committed items baked to a CGImage; in-flight (dragged)
// ABOUTME: and in-progress strokes drawn live so selection drags skip re-baking.

import AppKit
import CoreGraphics

struct BakeSignatureEntry: Equatable {
    let id: ItemId
    let transform: Transform
    let contentTag: Int   // strokes: stable (0); text: hash(string, fontName, fontSize, color)
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

    public private(set) var selectionBox: OrientedBox?
    public private(set) var marqueeRect: Rect?

    public func setSelectionBox(_ box: OrientedBox?) {
        guard selectionBox != box else { return }
        selectionBox = box
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
        // Signature covers only committed items — live items are excluded by
        // construction (they're in frame.liveItems, not frame.items).
        let signature = frame.items
            .filter { $0.id != inProgressId }
            .map { BakeSignatureEntry(id: $0.id, transform: $0.transform, contentTag: contentTag(for: $0)) }
        let resolvedScale = testOnly_overrideBackingScale ?? window?.backingScaleFactor ?? 1
        if signature != committedSignature || resolvedScale != backingScale {
            backingScale = resolvedScale
            committedImage = bakeCommitted(frame, exclude: inProgressId)
            committedSignature = signature
        }
        lastFrame = frame
        needsDisplay = true
    }

    private func contentTag(for item: CanvasItem) -> Int {
        switch item {
        case .stroke:
            return 0
        case .text(let t):
            var hasher = Hasher()
            hasher.combine(t.string)
            hasher.combine(t.fontName)
            hasher.combine(t.fontSize)
            hasher.combine(t.color.r)
            hasher.combine(t.color.g)
            hasher.combine(t.color.b)
            hasher.combine(t.color.a)
            return hasher.finalize()
        }
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
        for live in frame.liveItems {
            drawItem(live, in: ctx, isInProgress: false)
        }
        if let live = frame.inProgress, !live.points.isEmpty {
            drawStroke(live, in: ctx, isInProgress: true)
        }
        // Reset alpha for selection/marquee overlays — they manage their own alpha.
        ctx.setAlpha(1.0)
        if let box = selectionBox {
            drawSelectionBox(box, in: ctx)
        }
        if let marq = marqueeRect {
            drawMarquee(marq, in: ctx)
        }
    }

    private func drawSelectionBox(_ box: OrientedBox, in ctx: CGContext) {
        let corners = box.corners().map { CGPoint(x: $0.x, y: $0.y) }
        ctx.saveGState()
        ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
        ctx.setLineWidth(1)
        ctx.setLineDash(phase: 0, lengths: [5, 4])
        ctx.beginPath()
        ctx.move(to: corners[0])
        for c in corners.dropFirst() { ctx.addLine(to: c) }
        ctx.closePath()
        ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [])

        // corner handles (6×6pt, filled accent, white outline)
        let h: CGFloat = 6
        for c in corners {
            let r = CGRect(x: c.x - h / 2, y: c.y - h / 2, width: h, height: h)
            ctx.setFillColor(NSColor.controlAccentColor.cgColor)
            ctx.fill(r)
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(1)
            ctx.stroke(r)
        }

        // rotate node + connecting line from the top-edge midpoint. The offset
        // is shared with hit-testing so the node is drawn where it's grabbed.
        let node = box.rotateNode(offset: SelectionMetrics.rotateNodeOffset)
        let topMid = CGPoint(x: (corners[0].x + corners[1].x) / 2, y: (corners[0].y + corners[1].y) / 2)
        ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
        ctx.setLineWidth(1)
        ctx.beginPath(); ctx.move(to: topMid); ctx.addLine(to: CGPoint(x: node.x, y: node.y)); ctx.strokePath()
        let nodeRect = CGRect(x: node.x - 6, y: node.y - 6, width: 12, height: 12)
        ctx.setFillColor(NSColor.black.cgColor); ctx.fillEllipse(in: nodeRect)
        ctx.strokeEllipse(in: nodeRect)
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

    private func bakeCommitted(_ frame: RenderFrame, exclude: ItemId?) -> CGImage? {
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
        // pixels), then apply the scale CTM so drawing functions can use point
        // coordinates as if the context were point-sized.
        ctx.translateBy(x: 0, y: CGFloat(pixelHeight))
        ctx.scaleBy(x: 1, y: -1)
        ctx.scaleBy(x: backingScale, y: backingScale)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        for item in frame.items where item.id != exclude {
            drawItem(item, in: ctx, isInProgress: false)
        }
        return ctx.makeImage()
    }
}
