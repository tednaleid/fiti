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

    private func renderToBitmap(width: Int, height: Int, draw: (CGContext) -> Void) -> CGContext {
        let ctx = makeContext(width: width, height: height)
        draw(ctx)
        return ctx
    }

    // Returns the red component (0–255) at the given pixel.  The bitmap is
    // premultiplied RGBA so for a fully-opaque red stroke r ≈ 255, g ≈ 0.
    // For absence-of-stroke detection we rely on the background remaining white.
    private func redComponent(_ ctx: CGContext, x: Int, y: Int) -> UInt8 {
        pixel(ctx, x: x, y: y).r
    }

    @Test("drawStroke applies stroke.transform via CTM")
    func drawStrokeAppliesTransform() {
        // Stroke points at y=50. CGContext uses bottom-left origin, so bitmap row
        // for y=50 in a 200-tall bitmap is 200-50=150 from the top.
        // With a y+80 translate, stroke moves to y=130 → bitmap row 200-130=70.
        let baseStroke = Stroke(id: "a",
                                color: RGBA(r: 1, g: 0, b: 0, a: 1),
                                width: 10,
                                transform: .identity,
                                points: [StrokePoint(x: 50, y: 50),
                                         StrokePoint(x: 100, y: 50),
                                         StrokePoint(x: 150, y: 50)],
                                pointerType: .mouse,
                                pressureEnabled: false,
                                createdAt: 0)

        let untransformed = renderToBitmap(width: 200, height: 200) { ctx in
            drawStroke(baseStroke, in: ctx, isInProgress: false)
        }
        let translatedStroke = Stroke(id: "a",
                                      color: RGBA(r: 1, g: 0, b: 0, a: 1),
                                      width: 10,
                                      transform: Transform(x: 0, y: 80, scale: 1, rotate: 0),
                                      points: [StrokePoint(x: 50, y: 50),
                                               StrokePoint(x: 100, y: 50),
                                               StrokePoint(x: 150, y: 50)],
                                      pointerType: .mouse,
                                      pressureEnabled: false,
                                      createdAt: 0)
        let translated = renderToBitmap(width: 200, height: 200) { ctx in
            drawStroke(translatedStroke, in: ctx, isInProgress: false)
        }

        // Without transform, stroke center at CG y=50 → bitmap row 150.
        let untransformedOnLine = pixel(untransformed, x: 100, y: 150)
        #expect(untransformedOnLine.r > 200, "untransformed stroke should be present at bitmap row 150 (CG y=50)")
        #expect(untransformedOnLine.g < 50)

        // Bitmap row 70 (CG y=130) should be untouched white background without translation.
        let untransformedOffLine = pixel(untransformed, x: 100, y: 70)
        #expect(untransformedOffLine.r == 255 && untransformedOffLine.g == 255 && untransformedOffLine.b == 255,
                "untransformed stroke should not reach bitmap row 70 (CG y=130)")

        // With y+80 translate, original row 150 (CG y=50) should now be white background.
        let translatedOldPos = pixel(translated, x: 100, y: 150)
        #expect(translatedOldPos.r == 255 && translatedOldPos.g == 255 && translatedOldPos.b == 255,
                "translated stroke should not be present at original bitmap row 150 (CG y=50)")

        // With y+80 translate, stroke moves to CG y=130 → bitmap row 70 — should be red-dominant.
        let translatedNewPos = pixel(translated, x: 100, y: 70)
        #expect(translatedNewPos.r > 200, "translated stroke should be present at bitmap row 70 (CG y=130)")
        #expect(translatedNewPos.g < 50)
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
