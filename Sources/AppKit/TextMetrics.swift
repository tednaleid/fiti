// ABOUTME: Shared AppKit-layer text/render metrics used across drawing and measuring.
// ABOUTME: One line-height formula and one CTM transform helper so render, hit box, and caret agree.

import AppKit
import CoreGraphics

/// The single source of truth for a font's line height. Used by glyph rendering
/// (`drawText`), the live caret, and `CoreTextMeasurer` (the frozen hit box and
/// `caretIndex(at:)` line-picking) so multi-line text stays aligned across all three.
func lineHeight(for font: NSFont) -> CGFloat {
    font.ascender - font.descender + font.leading
}

/// Applies a `Transform` as a CTM (translate, rotate, scale) inside a saved
/// graphics state, runs `body`, then restores. The single definition for the
/// stroke, text, and live-text draw paths so their transform handling can't drift.
func withItemTransform(_ t: Transform, in ctx: CGContext, _ body: () -> Void) {
    ctx.saveGState()
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
    body()
    ctx.restoreGState()
}
