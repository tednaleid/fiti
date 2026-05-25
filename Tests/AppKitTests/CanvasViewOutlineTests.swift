// ABOUTME: CanvasView honors the OutlineSettings toggle: the committed bake gains a
// ABOUTME: contrast halo and re-bakes when the toggle flips.

import AppKit
import Testing

@MainActor
@Suite("CanvasView outline mode")
struct CanvasViewOutlineTests {
    private func fatStroke() -> Stroke {
        Stroke(id: "a", color: RGBA(r: 0.5, g: 0.1, b: 0.1, a: 1), width: 40,
               transform: .identity,
               points: [StrokePoint(x: 20, y: 80), StrokePoint(x: 180, y: 80)],
               pointerType: .mouse, pressureEnabled: false, createdAt: 0)
    }
    private func frame() -> RenderFrame {
        RenderFrame(items: [.stroke(fatStroke())], inProgress: nil,
                    canvasSize: Size(width: 200, height: 160))
    }
    private func whiteCountInBake(_ view: CanvasView) throws -> Int {
        let image = try #require(view.testOnly_committedImage)
        let ctx = try #require(CGContext(data: nil, width: image.width, height: image.height,
                                         bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bpr = ctx.bytesPerRow
        let data = try #require(ctx.data)
        let p = data.bindMemory(to: UInt8.self, capacity: bpr * image.height)
        var n = 0
        for y in 0..<image.height { for x in 0..<image.width {
            let i = y * bpr + x * 4
            if p[i + 3] > 120 && p[i] > 180 && p[i + 1] > 180 && p[i + 2] > 180 { n += 1 }
        } }
        return n
    }

    @Test("outline on adds white halo pixels to the bake")
    func haloInBake() throws {
        let view = CanvasView(frame: NSRect(x: 0, y: 0, width: 200, height: 160))
        view.outlineSettings = DefaultOutlineSettings(penOutline: true)
        view.render(frame())
        #expect(try whiteCountInBake(view) > 20)
    }

    @Test("flipping the toggle re-bakes (halo appears, then is gone)")
    func toggleRebakes() throws {
        let settings = DefaultOutlineSettings(penOutline: false)
        let view = CanvasView(frame: NSRect(x: 0, y: 0, width: 200, height: 160))
        view.outlineSettings = settings
        view.render(frame())
        #expect(try whiteCountInBake(view) == 0)
        settings.penOutline = true
        view.refresh()
        #expect(try whiteCountInBake(view) > 20)
    }
}
