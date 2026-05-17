// ABOUTME: Pixel-level tests for drawStroke against a CGBitmapContext.
// ABOUTME: With perfect-freehand polygon-fill rendering, asserts fill presence
// ABOUTME: along the stroke path and absence far from it (shape-agnostic).

import CoreGraphics
import Foundation
import Testing

@Suite("drawStroke")
struct StrokeDrawingTests {
    private func makeContext(width: Int, height: Int) -> CGContext {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: width, height: height,
                            bitsPerComponent: 8, bytesPerRow: 0, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx
    }

    private struct RGB { let r: UInt8; let g: UInt8; let b: UInt8 }

    private func pixel(_ ctx: CGContext, x: Int, y: Int) -> RGB {
        // swiftlint:disable:next force_unwrapping
        let data = ctx.data!.bindMemory(to: UInt8.self, capacity: ctx.bytesPerRow * ctx.height)
        let offset = y * ctx.bytesPerRow + x * 4
        return RGB(r: data[offset], g: data[offset + 1], b: data[offset + 2])
    }

    @Test("draws nothing for an empty stroke")
    func emptyStroke() {
        let ctx = makeContext(width: 10, height: 10)
        let stroke = Stroke(id: "a", color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 1,
                            transform: .identity, points: [], pointerType: .mouse,
                            pressureEnabled: false, createdAt: 0)
        drawStroke(stroke, in: ctx, isInProgress: false)
        let px = pixel(ctx, x: 5, y: 5)
        #expect(px.r == 255 && px.g == 255 && px.b == 255)
    }

    @Test("draws red pixels along a horizontal stroke")
    func horizontalLine() {
        let ctx = makeContext(width: 100, height: 30)
        // Use enough points and a generous width so the perfect-freehand
        // polygon definitively covers the centerline at x = 50.
        let stroke = Stroke(id: "a", color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 10,
                            transform: .identity,
                            points: [StrokePoint(x: 10, y: 15),
                                     StrokePoint(x: 50, y: 15),
                                     StrokePoint(x: 90, y: 15)],
                            pointerType: .mouse, pressureEnabled: false, createdAt: 0)
        drawStroke(stroke, in: ctx, isInProgress: false)
        // Somewhere along the stroke's middle should be red-dominant.
        let onLine = pixel(ctx, x: 50, y: 15)
        #expect(onLine.r > 200)
        #expect(onLine.g < 50)
        #expect(onLine.b < 50)
        // Far above the stroke should remain white (untouched).
        let offLine = pixel(ctx, x: 50, y: 0)
        #expect(offLine.r == 255 && offLine.g == 255 && offLine.b == 255)
    }
}
