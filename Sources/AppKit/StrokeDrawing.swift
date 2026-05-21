// ABOUTME: Shared stroke-rendering function used by CanvasView and
// ABOUTME: SnapshotRenderer. Fills a perfect-freehand polygon outline.

import CoreGraphics
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
