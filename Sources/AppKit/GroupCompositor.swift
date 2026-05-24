// ABOUTME: Paints a LayerPlan into a CGContext. Each group flattens in a
// ABOUTME: transparency layer, items drawn opaque, composited at the group's alpha.

import AppKit
import CoreGraphics

/// Composite `groups` (bottom-to-top) into `ctx`. Each group's items are drawn
/// opaque (alpha 1) inside a transparency layer, which is then composited at the
/// group's alpha. Same-color overlaps union flat; cross-group z-order is source-over.
func compositeGroups(_ groups: [FlattenLayer], in ctx: CGContext) {
    for group in groups {
        guard let groupAlpha = group.items.first?.color.a else { continue }
        ctx.saveGState()
        ctx.setAlpha(CGFloat(groupAlpha))
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        for item in group.items {
            drawItem(item.withAlpha(1), in: ctx, isInProgress: false)
        }
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }
}
