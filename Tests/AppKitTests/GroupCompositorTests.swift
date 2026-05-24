// ABOUTME: Pixel tests for GroupCompositor: same-color overlap is flat at the
// ABOUTME: group alpha, and cross-color groups preserve z-order.

import AppKit
import CoreGraphics
import Testing

@Suite("GroupCompositor")
@MainActor
struct GroupCompositorTests {
    private let size = 60

    private func context() -> CGContext {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                            bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setLineCap(.round); ctx.setLineJoin(.round)
        return ctx
    }
    private func hBar(_ id: String, y: Double, _ c: RGBA) -> CanvasItem {
        .stroke(Stroke(id: id, color: c, width: 16, transform: .identity,
                       points: [StrokePoint(x: 6, y: y), StrokePoint(x: 54, y: y)],
                       pointerType: .mouse, pressureEnabled: false, createdAt: 0))
    }
    private func vBar(_ id: String, x: Double, _ c: RGBA) -> CanvasItem {
        .stroke(Stroke(id: id, color: c, width: 16, transform: .identity,
                       points: [StrokePoint(x: x, y: 6), StrokePoint(x: x, y: 54)],
                       pointerType: .mouse, pressureEnabled: false, createdAt: 0))
    }
    private func alpha(_ ctx: CGContext, _ x: Int, _ y: Int) -> CGFloat {
        NSBitmapImageRep(cgImage: ctx.makeImage()!).colorAt(x: x, y: y)?.alphaComponent ?? 0
    }

    @Test("same-color 50% + is flat: intersection equals the arms")
    func sameColorPlusFlat() {
        let ctx = context()
        let red = RGBA(r: 1, g: 0, b: 0, a: 0.5)
        compositeGroups([FlattenLayer(items: [hBar("h", y: 30, red), vBar("v", x: 30, red)])], in: ctx)
        let arm = alpha(ctx, 12, 30)
        let center = alpha(ctx, 30, 30)
        #expect(arm > 0.3)
        #expect(abs(center - arm) < 0.12)
        #expect(center < 0.65)
    }

    @Test("different-color groups preserve z-order: later group on top")
    func crossColorOrder() {
        let ctx = context()
        compositeGroups([
            FlattenLayer(items: [hBar("r", y: 30, RGBA(r: 1, g: 0, b: 0, a: 1))]),
            FlattenLayer(items: [vBar("b", x: 30, RGBA(r: 0, g: 0, b: 1, a: 1))])
        ], in: ctx)
        let c = NSBitmapImageRep(cgImage: ctx.makeImage()!).colorAt(x: 30, y: 30)!
        #expect(c.blueComponent > 0.5 && c.redComponent < 0.3)
    }
}
