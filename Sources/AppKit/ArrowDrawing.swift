// ABOUTME: Fills an ArrowItem's merged outline as one CGPath with rounded joins.
// ABOUTME: Shares the opaque/alpha behavior of drawStroke so it slots into drawItem.

import AppKit
import CoreGraphics
import Foundation

public func drawArrow(_ arrow: ArrowItem, in ctx: CGContext, isInProgress: Bool) {
    let outline = ArrowGeometry.outline(tail: arrow.tail, head: arrow.head, width: arrow.width)
    guard outline.count >= 3 else { return }

    withItemTransform(arrow.transform, in: ctx) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: outline[0].x, y: outline[0].y))
        for p in outline.dropFirst() {
            path.addLine(to: CGPoint(x: p.x, y: p.y))
        }
        path.closeSubpath()
        ctx.setFillColor(red: CGFloat(arrow.color.r), green: CGFloat(arrow.color.g),
                         blue: CGFloat(arrow.color.b), alpha: CGFloat(arrow.color.a))
        ctx.setStrokeColor(red: CGFloat(arrow.color.r), green: CGFloat(arrow.color.g),
                           blue: CGFloat(arrow.color.b), alpha: CGFloat(arrow.color.a))
        // Round the outer corners: stroke the same path in the same color with round
        // joins. Cosmetic, small; a local fraction of the width (do NOT reach into
        // Core's internal ArrowGeometry constants, which are not visible cross-module).
        let cornerRoundWidth = arrow.width * 0.3
        ctx.setLineWidth(cornerRoundWidth)
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
        ctx.addPath(path)
        ctx.drawPath(using: .fillStroke)
    }
}
