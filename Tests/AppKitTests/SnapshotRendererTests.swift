// ABOUTME: SnapshotRenderer tests — decode the PNG output and check that
// ABOUTME: it has the right dimensions and that strokes appear where expected.

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import Testing

@Suite("SnapshotRenderer")
struct SnapshotRendererTests {
    private func decode(_ data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    private struct RGBA8 { let r: UInt8; let g: UInt8; let b: UInt8; let a: UInt8 }

    private func pixel(_ image: CGImage, x: Int, y: Int) -> RGBA8 {
        // swiftlint:disable:next force_unwrapping
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        var bytes = [UInt8](repeating: 0, count: 4)
        // swiftlint:disable:next force_unwrapping
        let ctx = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8,
                            bytesPerRow: 4, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return RGBA8(r: bytes[0], g: bytes[1], b: bytes[2], a: bytes[3])
    }

    @Test("image(from:) returns an NSImage sized in logical points")
    func nsImageOutput() throws {
        let stroke = Stroke(id: "a", color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 6, transform: .identity,
                            points: [StrokePoint(x: 10, y: 25), StrokePoint(x: 90, y: 25)],
                            pointerType: .mouse, pressureEnabled: false, createdAt: 0)
        let frame = RenderFrame(items: [.stroke(stroke)], inProgress: nil,
                                canvasSize: Size(width: 100, height: 50))
        let image = try #require(SnapshotRenderer.image(from: frame, scale: 2.0))
        #expect(image.size.width == 100)   // points, not pixels
        #expect(image.size.height == 50)
    }

    @Test("empty frame produces a transparent PNG at the expected dimensions")
    func emptyFrame() throws {
        let frame = RenderFrame(items: [], inProgress: nil,
                                canvasSize: Size(width: 100, height: 50))
        let data = try #require(SnapshotRenderer.png(from: frame, scale: 1.0))
        #expect(data.prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
        let image = try #require(decode(data))
        #expect(image.width == 100)
        #expect(image.height == 50)
        let center = pixel(image, x: 50, y: 25)
        #expect(center.a == 0)
    }

    @Test("a single horizontal stroke renders red pixels along its path")
    func singleStroke() throws {
        let stroke = Stroke(id: "a", color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 4,
                            transform: .identity,
                            points: [StrokePoint(x: 10, y: 25), StrokePoint(x: 90, y: 25)],
                            pointerType: .mouse, pressureEnabled: false, createdAt: 0)
        let frame = RenderFrame(items: [.stroke(stroke)], inProgress: nil,
                                canvasSize: Size(width: 100, height: 50))
        let data = try #require(SnapshotRenderer.png(from: frame, scale: 1.0))
        let image = try #require(decode(data))
        let onLine = pixel(image, x: 50, y: 25)
        #expect(onLine.r > 200 && onLine.g < 50 && onLine.b < 50)
        let offLine = pixel(image, x: 50, y: 5)
        #expect(offLine.a == 0)
    }

    @Test("two same-color 50% strokes crossing in a + flatten so the intersection is not brighter than the arm")
    func snapshotPlusIsFlat() throws {
        let horiz = Stroke(id: "h", color: RGBA(r: 1, g: 0, b: 0, a: 0.5), width: 16,
                           transform: .identity,
                           points: [StrokePoint(x: 20, y: 50), StrokePoint(x: 80, y: 50)],
                           pointerType: .mouse, pressureEnabled: false, createdAt: 0)
        let vert = Stroke(id: "v", color: RGBA(r: 1, g: 0, b: 0, a: 0.5), width: 16,
                          transform: .identity,
                          points: [StrokePoint(x: 50, y: 20), StrokePoint(x: 50, y: 80)],
                          pointerType: .mouse, pressureEnabled: false, createdAt: 0)
        let frame = RenderFrame(items: [.stroke(horiz), .stroke(vert)], inProgress: nil,
                                canvasSize: Size(width: 100, height: 100))
        let data = try #require(SnapshotRenderer.png(from: frame, scale: 1.0))
        let image = try #require(decode(data))
        let arm = pixel(image, x: 25, y: 50)
        let intersection = pixel(image, x: 50, y: 50)
        // Both alpha values on 0-255 scale. Intersection must be within ~12% (~31/255)
        // of the arm and must stay below 0.65 (~166/255).
        #expect(abs(Int(intersection.a) - Int(arm.a)) < 31)
        #expect(intersection.a < 166)
    }

    @Test("strokes render in strokeOrder (last stroke on top)")
    func ordering() throws {
        let red = Stroke(id: "r", color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 8,
                         transform: .identity,
                         points: [StrokePoint(x: 0, y: 25), StrokePoint(x: 100, y: 25)],
                         pointerType: .mouse, pressureEnabled: false, createdAt: 0)
        let blue = Stroke(id: "b", color: RGBA(r: 0, g: 0, b: 1, a: 1), width: 8,
                          transform: .identity,
                          points: [StrokePoint(x: 0, y: 25), StrokePoint(x: 100, y: 25)],
                          pointerType: .mouse, pressureEnabled: false, createdAt: 0)
        let frame = RenderFrame(items: [.stroke(red), .stroke(blue)], inProgress: nil,
                                canvasSize: Size(width: 100, height: 50))
        let data = try #require(SnapshotRenderer.png(from: frame, scale: 1.0))
        let image = try #require(decode(data))
        let center = pixel(image, x: 50, y: 25)
        #expect(center.b > 200 && center.r < 50)
    }
}
