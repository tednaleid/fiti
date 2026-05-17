// ABOUTME: Confirms the perfect-freehand renderer path produces non-zero
// ABOUTME: polygon-fill pixels along a stroke's path and transparent pixels
// ABOUTME: far from it. End-to-end through CanvasView's bake.

import AppKit
import Testing

@Suite("CanvasView perfect-freehand rendering")
@MainActor
struct CanvasViewPerfectFreehandTests {
    @Test("a horizontal stroke fills pixels along its path")
    func horizontalStrokeFills() throws {
        let view = CanvasView(frame: NSRect(x: 0, y: 0, width: 100, height: 30))
        let stroke = Stroke(id: "a", color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 10,
                            transform: .identity,
                            points: [StrokePoint(x: 10, y: 15),
                                     StrokePoint(x: 50, y: 15),
                                     StrokePoint(x: 90, y: 15)],
                            pointerType: .mouse, pressureEnabled: false, createdAt: 0)
        view.render(RenderFrame(strokes: [stroke], inProgress: nil,
                                canvasSize: Size(width: 100, height: 30)))
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        // A pixel right on the stroke's centerline should be filled red.
        let center = try #require(rep.colorAt(x: 50, y: 15))
        #expect(center.redComponent > 0.5)
        #expect(center.alphaComponent > 0.5)
        // A pixel far above the stroke should be transparent.
        let above = try #require(rep.colorAt(x: 50, y: 2))
        #expect(above.alphaComponent < 0.01)
    }
}
