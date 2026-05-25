// ABOUTME: Paints a LayerPlan into a CGContext. Each group flattens in a
// ABOUTME: transparency layer, items drawn opaque, composited at the group's alpha.

import AppKit
import CoreGraphics

/// Composite `groups` (bottom-to-top) into `ctx`. Each group's items are drawn
/// opaque (alpha 1) inside a transparency layer, which is then composited at the
/// group's alpha. Same-color overlaps union flat; cross-group z-order is source-over.
func compositeGroups(_ groups: [FlattenLayer], in ctx: CGContext, outline: Bool = false) {
    for group in groups {
        guard let groupAlpha = group.items.first?.color.a else { continue }
        ctx.saveGState()
        ctx.setAlpha(CGFloat(groupAlpha))
        if let clip = groupClip(group.items) {
            ctx.clip(to: clip)
        }
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        for item in group.items {
            drawItem(item.withAlpha(1), in: ctx, isInProgress: false, outline: outline)
        }
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }
}

/// Union of the items' world AABBs, each padded by its rendered ink extent so the
/// clip never shaves a stroke's width. Returns nil if no item has bounds (then the
/// caller does not clip).
private func groupClip(_ items: [CanvasItem]) -> CGRect? {
    var minX = Double.greatestFiniteMagnitude, minY = Double.greatestFiniteMagnitude
    var maxX = -Double.greatestFiniteMagnitude, maxY = -Double.greatestFiniteMagnitude
    var found = false
    for item in items {
        guard let box = SelectionMath.worldAABB(of: item) else { continue }
        let pad = inkPad(item)
        minX = min(minX, box.x - pad);             minY = min(minY, box.y - pad)
        maxX = max(maxX, box.x + box.width + pad); maxY = max(maxY, box.y + box.height + pad)
        found = true
    }
    guard found else { return nil }
    return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
}

/// World-space margin to add around an item's centerline AABB so its rendered
/// ink (stroke width + round caps + AA) is never clipped. Generous on purpose.
private func inkPad(_ item: CanvasItem) -> Double {
    switch item {
    case .stroke(let s):
        return s.width * linearScale(s.transform) + 1
    case .text:
        return 2
    case .arrow(let a):
        return a.width * linearScale(a.transform) + 1
    }
}

/// Conservative linear scale factor for a transform. Transform uses uniform
/// scale, so this is just the scale field. Returns 1 for identity.
private func linearScale(_ t: Transform) -> Double {
    t.scale
}
