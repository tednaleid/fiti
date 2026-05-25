// ABOUTME: Fills an ArrowItem's merged outline as one CGPath with rounded joins.
// ABOUTME: Shares the opaque/alpha behavior of drawStroke so it slots into drawItem.

import AppKit
import CoreGraphics
import Foundation

public func drawArrow(_ arrow: ArrowItem, in ctx: CGContext, isInProgress: Bool, outline: Bool = false) {
    let poly = ArrowGeometry.outline(tail: arrow.tail, head: arrow.head, width: arrow.width)
    guard poly.count >= 3 else { return }

    withItemTransform(arrow.transform, in: ctx) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: poly[0].x, y: poly[0].y))
        for p in poly.dropFirst() {
            path.addLine(to: CGPoint(x: p.x, y: p.y))
        }
        path.closeSubpath()
        if let halo = resolveOutline(enabled: outline, color: arrow.color, sizeBasis: arrow.width,
                                     widthFactor: OutlineTuning.arrowWidthFactor,
                                     minWidth: OutlineTuning.arrowMinHaloWidth) {
            strokeHalo(path, halo, in: ctx)
        }
        ctx.setFillColor(red: CGFloat(arrow.color.r), green: CGFloat(arrow.color.g),
                         blue: CGFloat(arrow.color.b), alpha: CGFloat(arrow.color.a))
        ctx.setStrokeColor(red: CGFloat(arrow.color.r), green: CGFloat(arrow.color.g),
                           blue: CGFloat(arrow.color.b), alpha: CGFloat(arrow.color.a))
        // Round the outer corners: stroke the same path in the same color with round
        // joins. Cosmetic, small; a local fraction of the width (do NOT reach into
        // Core's internal ArrowGeometry constants, which are not visible cross-module).
        let cornerRoundWidth = arrow.width * 0.17
        ctx.setLineWidth(cornerRoundWidth)
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
        ctx.addPath(path)
        ctx.drawPath(using: .fillStroke)
    }
}
