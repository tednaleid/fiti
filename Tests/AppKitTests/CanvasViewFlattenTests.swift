// ABOUTME: End-to-end flattening through the committed bake: a same-color +
// ABOUTME: drawn at 50% must be uniform, not darker at the intersection.

import AppKit
import Testing

@MainActor
@Suite("CanvasView flattening")
struct CanvasViewFlattenTests {
    func hBar(_ id: String, y: Double, _ c: RGBA) -> CanvasItem {
        .stroke(Stroke(id: id, color: c, width: 16, transform: .identity,
                       points: [StrokePoint(x: 10, y: y), StrokePoint(x: 90, y: y)],
                       pointerType: .mouse, pressureEnabled: false, createdAt: 0))
    }
    func vBar(_ id: String, x: Double, _ c: RGBA) -> CanvasItem {
        .stroke(Stroke(id: id, color: c, width: 16, transform: .identity,
                       points: [StrokePoint(x: x, y: 10), StrokePoint(x: x, y: 90)],
                       pointerType: .mouse, pressureEnabled: false, createdAt: 0))
    }

    @Test("a same-color 50% + is flat across the intersection in the committed bake")
    func committedPlusIsFlat() throws {
        let view = CanvasView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        view.testOnly_overrideBackingScale = 1
        let red = RGBA(r: 1, g: 0, b: 0, a: 0.5)
        view.render(RenderFrame(items: [hBar("h", y: 50, red), vBar("v", x: 50, red)],
                                inProgress: nil, canvasSize: Size(width: 100, height: 100)))
        let rep = NSBitmapImageRep(cgImage: try #require(view.testOnly_committedImage))
        let arm = try #require(rep.colorAt(x: 20, y: 50)).alphaComponent
        let center = try #require(rep.colorAt(x: 50, y: 50)).alphaComponent
        #expect(arm > 0.3)
        #expect(abs(center - arm) < 0.12)
        #expect(center < 0.65)
    }
}
