// ABOUTME: Pixel-level tests for drawArrow against a CGBitmapContext.
// ABOUTME: Proves the shaft fills red and the shaft/head seam does not darken.

import CoreGraphics
import Foundation
import Testing

@Suite("drawArrow")
struct ArrowDrawingTests {
    private func makeContext(width: Int, height: Int) -> CGContext {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx
    }

    private struct RGBA8 { let r: UInt8; let g: UInt8; let b: UInt8; let a: UInt8 }

    private func pixel(_ ctx: CGContext, x: Int, y: Int) -> RGBA8 {
        // swiftlint:disable:next force_unwrapping
        let data = ctx.data!.bindMemory(to: UInt8.self, capacity: ctx.bytesPerRow * ctx.height)
        let offset = y * ctx.bytesPerRow + x * 4
        return RGBA8(r: data[offset], g: data[offset + 1], b: data[offset + 2], a: data[offset + 3])
    }

    @Test("fills the shaft red and the seam matches the shaft without darkening")
    func mergedFillNoSeamDarkening() {
        let ctx = makeContext(width: 140, height: 60)
        let arrow = ArrowItem(id: "arrow-1", color: RGBA(r: 1, g: 0, b: 0, a: 1),
                              width: 10, transform: .identity,
                              tail: Point(x: 10, y: 30), head: Point(x: 130, y: 30),
                              createdAt: 0)
        drawArrow(arrow, in: ctx, isInProgress: false)

        // CGContext uses a bottom-left origin; the arrow lives at y=30 so the bitmap
        // row is height - 30 = 30. Both sample points share that row.
        let shaft = pixel(ctx, x: 40, y: 30)
        #expect(shaft.r > 200, "shaft should be red-dominant")
        #expect(shaft.g < 50)
        #expect(shaft.b < 50)
        #expect(shaft.a > 250, "shaft should be fully opaque")

        // The shaft/head seam sits ahead of the join; sampling on-axis there must
        // be the SAME red and alpha as the shaft. A doubled/overlapped path would
        // darken or change alpha here, so equality (within tolerance) proves a
        // single merged filled outline.
        let seam = pixel(ctx, x: 95, y: 30)
        let tol: Int = 6
        #expect(abs(Int(seam.r) - Int(shaft.r)) <= tol, "seam red must match shaft red (no darkening)")
        #expect(abs(Int(seam.g) - Int(shaft.g)) <= tol)
        #expect(abs(Int(seam.b) - Int(shaft.b)) <= tol)
        #expect(abs(Int(seam.a) - Int(shaft.a)) <= tol, "seam alpha must match shaft alpha")
    }
}
