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
