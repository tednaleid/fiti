// ABOUTME: Shared item-rendering functions used by CanvasView and SnapshotRenderer.
// ABOUTME: drawItem dispatches on CanvasItem case; drawStroke fills a freehand polygon.

import AppKit
import CoreGraphics
import CoreText
import Foundation
import PerfectFreehand

/// Stroke `path` with the resolved contrast halo behind the fill, if outline is on.
/// Shared by drawStroke and drawArrow (both use the stroke/arrow width factor).
func strokeHaloIfNeeded(_ path: CGPath, color: RGBA, sizeBasis: Double,
                        outline: Bool, in ctx: CGContext) {
    guard let halo = resolveOutline(enabled: outline, color: color, sizeBasis: sizeBasis,
                                    widthFactor: OutlineTuning.strokeWidthFactor) else { return }
    ctx.setStrokeColor(red: CGFloat(halo.haloColor.r), green: CGFloat(halo.haloColor.g),
                       blue: CGFloat(halo.haloColor.b), alpha: CGFloat(halo.haloColor.a))
    ctx.setLineWidth(CGFloat(halo.haloWidth))
    ctx.setLineJoin(.round)
    ctx.setLineCap(.round)
    ctx.addPath(path)
    ctx.strokePath()
}

public func drawItem(_ item: CanvasItem, in ctx: CGContext, isInProgress: Bool, outline: Bool = false) {
    switch item {
    case .stroke(let s): drawStroke(s, in: ctx, isInProgress: isInProgress, outline: outline)
    case .text(let t): drawText(t, in: ctx, outline: outline)
    case .arrow(let a): drawArrow(a, in: ctx, isInProgress: isInProgress, outline: outline)
    }
}

public func drawStroke(_ stroke: Stroke, in ctx: CGContext, isInProgress: Bool, outline: Bool = false) {
    guard !stroke.points.isEmpty else { return }
    let opts = FitiStrokeOptions.make(width: stroke.width, last: !isInProgress || stroke.snappedToLine)
    let polygon = getStroke(points: stroke.points.perfectFreehandInputs, options: opts)
    guard polygon.count >= 3 else { return }

    withItemTransform(stroke.transform, in: ctx) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: polygon[0].x, y: polygon[0].y))
        for v in polygon.dropFirst() {
            path.addLine(to: CGPoint(x: v.x, y: v.y))
        }
        path.closeSubpath()
        strokeHaloIfNeeded(path, color: stroke.color, sizeBasis: stroke.width, outline: outline, in: ctx)
        ctx.setFillColor(red: CGFloat(stroke.color.r), green: CGFloat(stroke.color.g),
                         blue: CGFloat(stroke.color.b), alpha: CGFloat(stroke.color.a))
        ctx.addPath(path)
        ctx.fillPath()
    }
}

public func drawText(_ text: TextItem, in ctx: CGContext, outline: Bool = false) {
    withItemTransform(text.transform, in: ctx) {
        drawTextString(text.string, fontName: text.fontName, fontSize: text.fontSize,
                       color: text.color, in: ctx, outline: outline)
    }
}

/// Draws a (possibly multi-line) string at the local origin in the current CTM.
/// Shared by `drawText` (committed items) and `drawLiveText` (the in-progress
/// edit session) so the glyph stacking and line height stay identical. The caller
/// is responsible for applying the item transform around this call.
func drawTextString(_ string: String, fontName: String, fontSize: Double,
                    color: RGBA, in ctx: CGContext, outline: Bool = false) {
    let font = NSFont(name: fontName, size: CGFloat(fontSize))
        ?? NSFont.systemFont(ofSize: CGFloat(fontSize))
    // The two-pass halo-behind technique relies on the opaque fill covering the inner
    // half of the halo stroke. A translucent fill cannot, so the halo bleeds into the
    // glyph interior. When the mark is translucent and outlined, draw both passes
    // opaque inside a transparency layer and composite that layer at the mark's alpha
    // (mirrors compositeGroups / drawLiveGroup, so live text equals committed text).
    let isolateForOutline = outline && color.a < 1
    let drawColor = isolateForOutline ? color.with(a: 1) : color
    let fillColor = NSColor(
        calibratedRed: CGFloat(drawColor.r),
        green: CGFloat(drawColor.g),
        blue: CGFloat(drawColor.b),
        alpha: CGFloat(drawColor.a)
    )
    // CanvasView is isFlipped and the bake context applies its own y-flip, so the
    // local drawing space has y increasing downward. CoreText ignores the context
    // flip and would render glyphs mirrored vertically, so apply the corrective
    // text matrix to draw glyphs upright.
    ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)

    let lh = lineHeight(for: font)
    let ascent = font.ascender
    let lines = string.components(separatedBy: "\n")

    // Draw every line with `attrs` at the stacked baseline positions. y is downward
    // here: line 0 sits at the top of the local box and subsequent lines descend; with
    // the flipped text matrix the glyph rises from its baseline, so place the baseline
    // at the line's top plus the font ascent.
    func drawLines(_ attrs: [NSAttributedString.Key: Any]) {
        for (index, line) in lines.enumerated() {
            let attrStr = NSAttributedString(string: line, attributes: attrs)
            let ctLine = CTLineCreateWithAttributedString(attrStr)
            let yOffset = CGFloat(index) * lh + ascent
            ctx.textPosition = CGPoint(x: 0, y: yOffset)
            CTLineDraw(ctLine, ctx)
        }
    }

    if isolateForOutline {
        ctx.saveGState()
        ctx.setAlpha(CGFloat(color.a))
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    }
    // Halo behind the fill: first stroke the glyph contours thickly in the contrast
    // color (positive strokeWidth = stroke only, no fill), then fill the glyphs in the
    // mark color on top. The fill covers the inner half of the halo stroke, so the
    // interior stays the full mark color and only the outer halo shows. (A single-pass
    // negative strokeWidth would paint the stroke over the fill, eating thin glyph stems.)
    if let halo = resolveOutline(enabled: outline, color: drawColor,
                                 width: textHaloWidth(forFontSize: fontSize)) {
        let haloColor = NSColor(calibratedRed: CGFloat(halo.haloColor.r),
                                green: CGFloat(halo.haloColor.g),
                                blue: CGFloat(halo.haloColor.b),
                                alpha: CGFloat(halo.haloColor.a))
        drawLines([
            .font: font,
            .foregroundColor: haloColor,
            .strokeColor: haloColor,
            .strokeWidth: 100.0 * halo.haloWidth / fontSize
        ])
    }
    drawLines([.font: font, .foregroundColor: fillColor])
    if isolateForOutline {
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }
}
