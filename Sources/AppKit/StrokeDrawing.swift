// ABOUTME: Shared item-rendering functions used by CanvasView and SnapshotRenderer.
// ABOUTME: drawItem dispatches on CanvasItem case; drawStroke fills a freehand polygon.

import AppKit
import CoreGraphics
import CoreText
import Foundation
import PerfectFreehand

public func drawStroke(_ stroke: Stroke, in ctx: CGContext, isInProgress: Bool) {
    guard !stroke.points.isEmpty else { return }
    let opts = FitiStrokeOptions.make(width: stroke.width, last: !isInProgress || stroke.snappedToLine)
    let polygon = getStroke(points: stroke.points.perfectFreehandInputs, options: opts)
    guard polygon.count >= 3 else { return }

    withItemTransform(stroke.transform, in: ctx) {
        ctx.setFillColor(red: CGFloat(stroke.color.r),
                         green: CGFloat(stroke.color.g),
                         blue: CGFloat(stroke.color.b),
                         alpha: CGFloat(stroke.color.a))
        let path = CGMutablePath()
        path.move(to: CGPoint(x: polygon[0].x, y: polygon[0].y))
        for v in polygon.dropFirst() {
            path.addLine(to: CGPoint(x: v.x, y: v.y))
        }
        path.closeSubpath()
        ctx.addPath(path)
        ctx.fillPath()
    }
}

public func drawItem(_ item: CanvasItem, in ctx: CGContext, isInProgress: Bool) {
    switch item {
    case .stroke(let s): drawStroke(s, in: ctx, isInProgress: isInProgress)
    case .text(let t): drawText(t, in: ctx)
    }
}

public func drawText(_ text: TextItem, in ctx: CGContext) {
    withItemTransform(text.transform, in: ctx) {
        drawTextString(text.string, fontName: text.fontName, fontSize: text.fontSize,
                       color: text.color, in: ctx)
    }
}

/// Draws a (possibly multi-line) string at the local origin in the current CTM.
/// Shared by `drawText` (committed items) and `drawLiveText` (the in-progress
/// edit session) so the glyph stacking and line height stay identical. The caller
/// is responsible for applying the item transform around this call.
func drawTextString(_ string: String, fontName: String, fontSize: Double,
                    color: RGBA, in ctx: CGContext) {
    let font = NSFont(name: fontName, size: CGFloat(fontSize))
        ?? NSFont.systemFont(ofSize: CGFloat(fontSize))
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(
            calibratedRed: CGFloat(color.r),
            green: CGFloat(color.g),
            blue: CGFloat(color.b),
            alpha: CGFloat(color.a)
        )
    ]
    // CanvasView is isFlipped and the bake context applies its own y-flip, so the
    // local drawing space has y increasing downward. CoreText ignores the context
    // flip and would render glyphs mirrored vertically, so apply the corrective
    // text matrix to draw glyphs upright.
    ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)

    let lh = lineHeight(for: font)
    let ascent = font.ascender
    let lines = string.components(separatedBy: "\n")
    for (index, line) in lines.enumerated() {
        let attrStr = NSAttributedString(string: line, attributes: attrs)
        let ctLine = CTLineCreateWithAttributedString(attrStr)
        // y is downward in this space: line 0 sits at the top of the local box
        // (0,0)-(bounds.w, lines*lineHeight) and subsequent lines descend. With the
        // flipped text matrix the glyph rises from its baseline, so place the baseline
        // at the line's top plus the font ascent.
        let yOffset = CGFloat(index) * lh + ascent
        ctx.textPosition = CGPoint(x: 0, y: yOffset)
        CTLineDraw(ctLine, ctx)
    }
}
