// ABOUTME: Tests for CanvasView.drawingsVisible — short-circuits draw(_:) when
// ABOUTME: false so hide/show on the toolbar produces a transparent overlay
// ABOUTME: without disturbing the underlying document.

import AppKit
import Testing

@Suite("CanvasView drawingsVisible")
@MainActor
struct CanvasViewVisibilityTests {
    @Test("strokes render normally when drawingsVisible is true")
    func renderWhenVisible() throws {
        let view = CanvasView(frame: NSRect(x: 0, y: 0, width: 50, height: 50))
        let stroke = Stroke(id: "a", color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 4,
                            transform: .identity,
                            points: [StrokePoint(x: 10, y: 5), StrokePoint(x: 40, y: 5)],
                            pointerType: .mouse, pressureEnabled: false, createdAt: 0)
        view.render(RenderFrame(items: [.stroke(stroke)], inProgress: nil,
                                canvasSize: Size(width: 50, height: 50)))
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let top = try #require(rep.colorAt(x: 25, y: 5))
        #expect(top.redComponent > 0.5)
    }

    @Test("draw produces a transparent overlay when drawingsVisible is false")
    func hiddenWhenInvisible() throws {
        let view = CanvasView(frame: NSRect(x: 0, y: 0, width: 50, height: 50))
        let stroke = Stroke(id: "a", color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 4,
                            transform: .identity,
                            points: [StrokePoint(x: 10, y: 5), StrokePoint(x: 40, y: 5)],
                            pointerType: .mouse, pressureEnabled: false, createdAt: 0)
        view.render(RenderFrame(items: [.stroke(stroke)], inProgress: nil,
                                canvasSize: Size(width: 50, height: 50)))
        view.drawingsVisible = false
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let pixel = try #require(rep.colorAt(x: 25, y: 5))
        #expect(pixel.alphaComponent < 0.01, "pixel should be transparent when hidden")
    }
}
