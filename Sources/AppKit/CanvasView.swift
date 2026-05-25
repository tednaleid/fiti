// ABOUTME: NSView that renders a RenderFrame via Core Graphics.
// ABOUTME: Two-canvas split: committed items baked to a CGImage; in-flight (dragged)
// ABOUTME: and the in-progress item (stroke or arrow) drawn live so selection drags skip re-baking.

import AppKit
import CoreGraphics
import CoreText

struct BakeSignatureEntry: Equatable {
    let id: ItemId
    let transform: Transform
    let contentTag: Int   // strokes: hash(color, width); text: hash(string, fontName, fontSize, color); arrows: hash(color, width, tail, head)
}

public final class CanvasView: NSView, Renderer {
    private var lastFrame: RenderFrame?
    /// The static bake of the groups BELOW the active group (the full bake when
    /// not drawing). `testOnly_committedImage` returns this.
    private var committedImage: CGImage?
    /// The static bake of the groups ABOVE the active group; nil when not drawing.
    private var aboveImage: CGImage?
    private var committedSignature: [BakeSignatureEntry] = []
    private var activeGroupCommitted: [CanvasItem] = []
    private var activeGroupUnion: CGImage?

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
    public private(set) var textSession: TextSessionSnapshot?

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

    public func setTextSession(_ session: TextSessionSnapshot?) {
        guard textSession != session else { return }
        textSession = session
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

    private struct RenderSplit {
        let below: [CanvasItem]
        let above: [CanvasItem]
        let lifted: [CanvasItem]   // active group's committed members
    }

    /// Plan over committed + the in-progress item; split the other groups into
    /// those below vs above the active group (the one the in-progress item joins).
    private func renderSplit(for frame: RenderFrame, inProgressId: ItemId?) -> RenderSplit {
        let committed = frame.items.filter { $0.id != inProgressId }
        // Only lift the active layer when the in-progress item is actually drawable.
        // A just-started item with no geometry yet (e.g. an arrow at pointer-down,
        // tail == head) is not drawn by drawLiveGroup, so lifting its layer here would
        // pull those committed items out of the static bake and leave them unpainted
        // until the first move.
        guard let live = frame.inProgress, isLiveDrawable(live) else {
            return RenderSplit(below: committed, above: [], lifted: [])
        }
        let plan = LayerPlan.compute(items: committed + [live],
                                     aabb: { SelectionMath.worldAABB(of: $0) })
        guard let activeIdx = plan.firstIndex(where: { $0.items.contains { $0.id == live.id } }) else {
            return RenderSplit(below: committed, above: [], lifted: [])
        }
        let lifted = plan[activeIdx].items.filter { $0.id != live.id }
        let below = plan[..<activeIdx].flatMap { $0.items }
        let above = plan[(activeIdx + 1)...].flatMap { $0.items }
        return RenderSplit(below: below, above: above, lifted: lifted)
    }

    public func render(_ frame: RenderFrame) {
        let inProgressId = frame.inProgress?.id
        #if DEBUG
        let split = PerfLog.shared.measure("render.split") { renderSplit(for: frame, inProgressId: inProgressId) }
        #else
        let split = renderSplit(for: frame, inProgressId: inProgressId)
        #endif

        // Signature covers everything baked (below + above) in order, plus the
        // lifted membership, so live drawing rebuilds only when the split changes.
        let bakedItems = split.below + split.above
        let signature = bakedItems
            .map { BakeSignatureEntry(id: $0.id, transform: $0.transform, contentTag: contentTag(for: $0)) }
        let resolvedScale = testOnly_overrideBackingScale ?? window?.backingScaleFactor ?? 1
        let liftedChanged = split.lifted.map(\.id) != activeGroupCommitted.map(\.id)
        if signature != committedSignature || resolvedScale != backingScale || liftedChanged {
            backingScale = resolvedScale
            #if DEBUG
            PerfLog.shared.measure("render.bake") { rebuildBakes(frame: frame, split: split) }
            #else
            rebuildBakes(frame: frame, split: split)
            #endif
            committedSignature = signature
        }
        lastFrame = frame
        needsDisplay = true
    }

    /// Rebuild the below/above static bakes plus the lifted opaque union. Kept
    /// as one call so the four cache assignments stay together.
    private func rebuildBakes(frame: RenderFrame, split: RenderSplit) {
        committedImage = bakeCommitted(frame, baked: split.below)
        aboveImage = split.above.isEmpty ? nil : bakeCommitted(frame, baked: split.above)
        activeGroupCommitted = split.lifted
        activeGroupUnion = split.lifted.isEmpty ? nil : bakeOpaqueUnion(frame, members: split.lifted)
    }

    public override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext, let frame = lastFrame else { return }
        guard drawingsVisible else { return }
        #if DEBUG
        let drawStart = ContinuousClock.now
        defer { PerfLog.shared.record("draw.total", duration: ContinuousClock.now - drawStart) }
        PerfLog.shared.set(gauge: "canvas.deviceW", frame.canvasSize.width * backingScale)
        PerfLog.shared.set(gauge: "canvas.deviceH", frame.canvasSize.height * backingScale)
        #endif
        ctx.setAlpha(CGFloat(globalOpacity))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        if let image = committedImage { blitBake(image, frame, in: ctx) }
        for live in frame.liveItems {
            drawItem(live, in: ctx, isInProgress: false)
        }
        if let live = frame.inProgress, isLiveDrawable(live) {
            #if DEBUG
            PerfLog.shared.measure("draw.liveGroup") { drawLiveGroup(live, frame: frame, in: ctx) }
            #else
            drawLiveGroup(live, frame: frame, in: ctx)
            #endif
        }
        if let above = aboveImage { blitBake(above, frame, in: ctx) }
        // Reset alpha for selection/marquee overlays — they manage their own alpha.
        ctx.setAlpha(1.0)
        if let box = selectionBox {
            drawSelectionBox(box, in: ctx)
        }
        if let marq = marqueeRect {
            drawMarquee(marq, in: ctx)
        }
        if let session = textSession {
            drawLiveText(session, in: ctx)
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

    private func drawLiveText(_ session: TextSessionSnapshot, in ctx: CGContext) {
        withItemTransform(session.transform, in: ctx) {
            drawTextString(session.string, fontName: session.fontName,
                           fontSize: session.fontSize, color: session.color, in: ctx)
        }
        drawLiveCaret(session, in: ctx)
    }

    private func drawLiveCaret(_ session: TextSessionSnapshot, in ctx: CGContext) {
        let font = NSFont(name: session.fontName, size: CGFloat(session.fontSize))
            ?? NSFont.systemFont(ofSize: CGFloat(session.fontSize))
        let lh = lineHeight(for: font)

        // Find which line the caret is on and the column within that line.
        let lines = session.string.components(separatedBy: "\n")
        var remaining = session.caret
        var caretLine = 0
        var caretCol = 0
        for (i, line) in lines.enumerated() {
            if remaining <= line.count {
                caretLine = i
                caretCol = remaining
                break
            }
            remaining -= line.count + 1
            if i == lines.count - 1 {
                caretLine = i
                caretCol = line.count
            }
        }

        // Measure the x offset of the caret within its line.
        let linePrefix = String(lines[caretLine].prefix(caretCol))
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let attributed = NSAttributedString(string: linePrefix, attributes: attrs)
        let ctLine = CTLineCreateWithAttributedString(attributed)
        let caretX = CTLineGetTypographicBounds(ctLine, nil, nil, nil)

        // y offset: line index * lineHeight (top of the line cell). The caret bar
        // spans the full line height down from there, matching drawText's stacking.
        let caretY = CGFloat(caretLine) * lh

        withItemTransform(session.transform, in: ctx) {
            // Draw a 1.5pt wide vertical caret rule spanning the full line height.
            ctx.setFillColor(NSColor.controlAccentColor.cgColor)
            let caretRect = CGRect(x: CGFloat(caretX), y: caretY, width: 1.5, height: lh)
            ctx.fill(caretRect)
        }
    }

    /// Composite the active group (cached committed union + the in-progress
    /// item) flattened at the group alpha, under globalOpacity. Matches the
    /// committed bake, so live drawing equals the committed result.
    private func drawLiveGroup(_ live: CanvasItem, frame: RenderFrame, in ctx: CGContext) {
        let groupAlpha = live.color.a
        ctx.saveGState()
        ctx.setAlpha(CGFloat(globalOpacity * groupAlpha))
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        if let union = activeGroupUnion { blitBake(union, frame, in: ctx) }
        drawItem(live.withAlpha(1), in: ctx, isInProgress: true)
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    /// True when an in-progress item has visible geometry worth live-drawing.
    private func isLiveDrawable(_ item: CanvasItem) -> Bool {
        switch item {
        case .stroke(let s): return !s.points.isEmpty
        case .arrow(let a): return a.tail != a.head
        case .text: return false
        }
    }

}

// MARK: - Baking
// Bake helpers live in an extension so the main class body stays within the
// type-body-length budget; they are pure aside from reading `backingScale`.
extension CanvasView {
    /// Builds the canvas-sized pixel context shared by `bakeCommitted` and
    /// `bakeOpaqueUnion`: flip-then-scale CTM so callers draw in point space,
    /// round line cap/join. The two bakes differ only in what they composite.
    func makeBakeContext(_ frame: RenderFrame) -> CGContext? {
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
        return ctx
    }

    /// Blit a canvas-sized bake image, locally undoing the view's flip.
    /// CGContext.draw(image:in:) is not isFlipped-aware: it always lays the
    /// image's bottom-left at rect.origin in CG-coords. In a flipped NSView that
    /// puts the image upside down, so undo the flip to place the bake's
    /// top-origin pixels at the view's top.
    func blitBake(_ image: CGImage, _ frame: RenderFrame, in ctx: CGContext) {
        let rect = CGRect(x: 0, y: 0, width: frame.canvasSize.width, height: frame.canvasSize.height)
        ctx.saveGState()
        ctx.translateBy(x: 0, y: rect.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: rect)
        ctx.restoreGState()
    }

    func bakeCommitted(_ frame: RenderFrame, baked: [CanvasItem]) -> CGImage? {
        guard let ctx = makeBakeContext(frame) else { return nil }
        let groups = LayerPlan.compute(items: baked, aabb: { SelectionMath.worldAABB(of: $0) })
        compositeGroups(groups, in: ctx)
        return ctx.makeImage()
    }

    /// The lifted group's committed members drawn opaque (alpha 1), source-over,
    /// into a canvas-sized image. The group alpha is applied later in draw(_:),
    /// when this union is composited with the live stroke.
    func bakeOpaqueUnion(_ frame: RenderFrame, members: [CanvasItem]) -> CGImage? {
        guard let ctx = makeBakeContext(frame) else { return nil }
        for member in members { drawItem(member.withAlpha(1), in: ctx, isInProgress: false) }
        return ctx.makeImage()
    }
}
