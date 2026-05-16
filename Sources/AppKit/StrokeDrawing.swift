// ABOUTME: Shared stroke-rendering function used by CanvasView and
// ABOUTME: SnapshotRenderer. Top-origin coords; uniform-width CGPath.

import CoreGraphics
import Foundation

public func drawStroke(_ stroke: Stroke, in ctx: CGContext) {
    guard !stroke.points.isEmpty else { return }
    ctx.setLineWidth(CGFloat(stroke.width))
    ctx.setStrokeColor(red: CGFloat(stroke.color.r),
                       green: CGFloat(stroke.color.g),
                       blue: CGFloat(stroke.color.b),
                       alpha: CGFloat(stroke.color.a))
    let path = CGMutablePath()
    let first = stroke.points[0]
    path.move(to: CGPoint(x: first.x, y: first.y))
    for point in stroke.points.dropFirst() {
        path.addLine(to: CGPoint(x: point.x, y: point.y))
    }
    ctx.addPath(path)
    ctx.strokePath()
}
