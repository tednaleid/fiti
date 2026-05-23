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

    ctx.saveGState()
    let t = stroke.transform
    if t != .identity {
        if t.x != 0 || t.y != 0 {
            ctx.translateBy(x: CGFloat(t.x), y: CGFloat(t.y))
        }
        if t.rotate != 0 {
            ctx.rotate(by: CGFloat(t.rotate * .pi / 180.0))
        }
        if t.scale != 1 {
            ctx.scaleBy(x: CGFloat(t.scale), y: CGFloat(t.scale))
        }
    }

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
    ctx.restoreGState()
}

public func drawItem(_ item: CanvasItem, in ctx: CGContext, isInProgress: Bool) {
    switch item {
    case .stroke(let s): drawStroke(s, in: ctx, isInProgress: isInProgress)
    case .text(let t): drawText(t, in: ctx)
    }
}

public func drawText(_ text: TextItem, in ctx: CGContext) {
    ctx.saveGState()
    let t = text.transform
    if t != .identity {
        if t.x != 0 || t.y != 0 {
            ctx.translateBy(x: CGFloat(t.x), y: CGFloat(t.y))
        }
        if t.rotate != 0 {
            ctx.rotate(by: CGFloat(t.rotate * .pi / 180.0))
        }
        if t.scale != 1 {
            ctx.scaleBy(x: CGFloat(t.scale), y: CGFloat(t.scale))
        }
    }

    let font = NSFont(name: text.fontName, size: CGFloat(text.fontSize))
        ?? NSFont.systemFont(ofSize: CGFloat(text.fontSize))
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(
            calibratedRed: CGFloat(text.color.r),
            green: CGFloat(text.color.g),
            blue: CGFloat(text.color.b),
            alpha: CGFloat(text.color.a)
        )
    ]
    // CanvasView is isFlipped and the bake context applies its own y-flip, so the
    // local drawing space has y increasing downward. CoreText ignores the context
    // flip and would render glyphs mirrored vertically, so apply the corrective
    // text matrix to draw glyphs upright.
    ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)

    let lineHeight = CGFloat(text.fontSize) * 1.2
    let ascent = font.ascender
    let lines = text.string.components(separatedBy: "\n")
    for (index, line) in lines.enumerated() {
        let attrStr = NSAttributedString(string: line, attributes: attrs)
        let ctLine = CTLineCreateWithAttributedString(attrStr)
        // y is downward in this space: line 0 sits at the top of the local box
        // (0,0)-(bounds.w, lines*lineHeight) and subsequent lines descend. With the
        // flipped text matrix the glyph rises from its baseline, so place the baseline
        // at the line's top plus the font ascent.
        let yOffset = CGFloat(index) * lineHeight + ascent
        ctx.textPosition = CGPoint(x: 0, y: yOffset)
        CTLineDraw(ctLine, ctx)
    }
    ctx.restoreGState()
}
