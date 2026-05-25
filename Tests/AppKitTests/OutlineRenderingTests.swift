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
        let on = whiteCount(render(true), xs: stride(from: 95, through: 105, by: 1),
                            ys: stride(from: 101, through: 116, by: 1))
        let off = whiteCount(render(false), xs: stride(from: 95, through: 105, by: 1),
                             ys: stride(from: 101, through: 116, by: 1))
        #expect(on > 5)
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

    @Test("text gets white halo pixels on the glyphs with outline on, none with it off")
    func textHalo() {
        func render(_ outline: Bool) -> CGContext {
            let t = TextItem(id: "a", string: "H", fontName: "Helvetica-Bold", fontSize: 60,
                             color: darkRed(), transform: .identity,
                             bounds: Size(width: 60, height: 70), createdAt: 0)
            let ctx = makeContext(120, 100)
            drawText(t, in: ctx, outline: outline)
            return ctx
        }
        let on = whiteCount(render(true), xs: stride(from: 0, through: 119, by: 1),
                            ys: stride(from: 0, through: 99, by: 1))
        let off = whiteCount(render(false), xs: stride(from: 0, through: 119, by: 1),
                             ys: stride(from: 0, through: 99, by: 1))
        #expect(on > 5)
        #expect(off == 0)
    }
}
