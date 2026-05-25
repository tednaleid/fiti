// ABOUTME: Pixel tests for the outline halo on strokes, arrows, and text: a contrast
// ABOUTME: halo appears around the mark with outline on, and is absent with it off.

import AppKit
import CoreGraphics
import Testing

@MainActor
@Suite("Outline halo rendering")
struct OutlineRenderingTests {
    private func makeContext(_ w: Int, _ h: Int) -> CGContext {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        return CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                         bytesPerRow: 0, space: cs,
                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }
    private func whiteCount(_ ctx: CGContext, xs: StrideThrough<Int>, ys: StrideThrough<Int>) -> Int {
        let bpr = ctx.bytesPerRow
        let p = ctx.data!.bindMemory(to: UInt8.self, capacity: bpr * ctx.height)
        var n = 0
        for y in ys { for x in xs {
            let i = y * bpr + x * 4
            if p[i + 3] > 120 && p[i] > 180 && p[i + 1] > 180 && p[i + 2] > 180 { n += 1 }
        } }
        return n
    }
    private func redCount(_ ctx: CGContext, xs: StrideThrough<Int>, ys: StrideThrough<Int>) -> Int {
        let bpr = ctx.bytesPerRow
        let p = ctx.data!.bindMemory(to: UInt8.self, capacity: bpr * ctx.height)
        var n = 0
        for y in ys { for x in xs {
            let i = y * bpr + x * 4
            if p[i + 3] > 120 && p[i] > 100 && p[i + 1] < 90 && p[i + 2] < 90 { n += 1 }
        } }
        return n
    }
    private func darkRed() -> RGBA { RGBA(r: 0.5, g: 0.1, b: 0.1, a: 1) }

    @Test("stroke gets a white halo with outline on, none with it off")
    func strokeHalo() {
        func render(_ outline: Bool) -> CGContext {
            let s = Stroke(id: "a", color: darkRed(), width: 40, transform: .identity,
                           points: [StrokePoint(x: 20, y: 80), StrokePoint(x: 180, y: 80)],
                           pointerType: .mouse, pressureEnabled: false, createdAt: 0)
            let ctx = makeContext(200, 160)
            drawStroke(s, in: ctx, isInProgress: false, outline: outline)
            return ctx
        }
        // The only white pixels in the frame are the halo; scan the whole image so the
        // assertion is robust to the halo's exact width (which is a tunable factor).
        let on = whiteCount(render(true), xs: stride(from: 0, through: 199, by: 1),
                            ys: stride(from: 0, through: 159, by: 1))
        let off = whiteCount(render(false), xs: stride(from: 0, through: 199, by: 1),
                             ys: stride(from: 0, through: 159, by: 1))
        #expect(on > 20)
        #expect(off == 0)
    }

    @Test("arrow gets a white halo with outline on, none with it off")
    func arrowHalo() {
        func render(_ outline: Bool) -> CGContext {
            let a = ArrowItem(id: "a", color: darkRed(), width: 40, transform: .identity,
                              tail: Point(x: 100, y: 30), head: Point(x: 100, y: 150),
                              createdAt: 0)
            let ctx = makeContext(200, 200)
            drawArrow(a, in: ctx, isInProgress: false, outline: outline)
            return ctx
        }
        let on = whiteCount(render(true), xs: stride(from: 70, through: 86, by: 1),
                            ys: stride(from: 60, through: 120, by: 1))
        let off = whiteCount(render(false), xs: stride(from: 70, through: 86, by: 1),
                             ys: stride(from: 60, through: 120, by: 1))
        #expect(on > 5)
        #expect(off == 0)
    }

    // Average green/red over the red-dominant interior pixels. Scale-invariant, so it
    // is comparable across opacities: pure mark stays low; halo bleed-through raises it.
    private func interiorGreenOverRed(_ ctx: CGContext) -> Double {
        let bpr = ctx.bytesPerRow
        let p = ctx.data!.bindMemory(to: UInt8.self, capacity: bpr * ctx.height)
        var n = 0
        var sum = 0.0
        for y in 0..<ctx.height { for x in 0..<ctx.width {
            let i = y * bpr + x * 4
            if Int(p[i + 3]) < 40 { continue }
            let r = Double(p[i]), g = Double(p[i + 1]), b = Double(p[i + 2])
            guard r > g, r > b, r > 40 else { continue }
            n += 1
            sum += g / r
        } }
        return sum / Double(max(n, 1))
    }

    @Test("translucent outlined text keeps a clean interior (no halo bleed)")
    func textOutlineTranslucentNoBleed() {
        func render(_ alpha: Double) -> CGContext {
            let t = TextItem(id: "a", string: "H", fontName: "Helvetica-Bold", fontSize: 60,
                             color: RGBA(r: 0.88, g: 0.19, b: 0.19, a: alpha), transform: .identity,
                             bounds: Size(width: 60, height: 70), createdAt: 0)
            let ctx = makeContext(120, 100)
            drawText(t, in: ctx, outline: true)   // the live path: direct draw, no compositeGroups
            return ctx
        }
        // As the mark goes translucent, the halo must not bleed into the interior: the
        // interior's green/red character stays the same as the opaque mark's. Without
        // isolation the translucent fill can't cover the halo and this ratio jumps.
        let opaque = interiorGreenOverRed(render(1.0))
        let translucent = interiorGreenOverRed(render(0.5))
        #expect(abs(translucent - opaque) < 0.05)
    }

    @Test("text keeps a full mark-color interior with the halo behind it")
    func textHalo() {
        func render(_ outline: Bool) -> CGContext {
            let t = TextItem(id: "a", string: "H", fontName: "Helvetica-Bold", fontSize: 60,
                             color: darkRed(), transform: .identity,
                             bounds: Size(width: 60, height: 70), createdAt: 0)
            let ctx = makeContext(120, 100)
            drawText(t, in: ctx, outline: outline)
            return ctx
        }
        let allX = stride(from: 0, through: 119, by: 1)
        let allY = stride(from: 0, through: 99, by: 1)
        let onCtx = render(true)
        let haloOn = whiteCount(onCtx, xs: allX, ys: allY)
        let redOn = redCount(onCtx, xs: allX, ys: allY)
        let haloOff = whiteCount(render(false), xs: allX, ys: allY)
        #expect(haloOn > 5)        // halo present around the glyphs
        #expect(redOn > 300)       // a substantial mark-color interior remains (halo behind, not eating it)
        #expect(haloOff == 0)      // no halo without outline
    }
}
