// ABOUTME: Tests for CanvasView.globalOpacity — verifies the setter, idempotence,
// ABOUTME: and that rendering with reduced opacity dims stroke alpha.

import AppKit
import Testing

@Suite("CanvasView globalOpacity")
@MainActor
struct CanvasViewGlobalOpacityTests {
    @Test("initial globalOpacity is 1.0")
    func initialOpacity() {
        let canvas = CanvasView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        #expect(canvas.globalOpacity == 1.0)
    }

    @Test("setGlobalOpacity stores the new value")
    func setStoresValue() {
        let canvas = CanvasView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        canvas.setGlobalOpacity(0.5)
        #expect(canvas.globalOpacity == 0.5)
    }

    @Test("setGlobalOpacity is idempotent: value stays the same on repeated calls")
    func idempotentValueIsUnchanged() {
        let canvas = CanvasView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        canvas.setGlobalOpacity(0.5)
        canvas.setGlobalOpacity(0.5)
        #expect(canvas.globalOpacity == 0.5)
    }

    @Test("setGlobalOpacity stores each new distinct value")
    func setMultipleDistinctValues() {
        let canvas = CanvasView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        canvas.setGlobalOpacity(0.25)
        #expect(canvas.globalOpacity == 0.25)
        canvas.setGlobalOpacity(0.75)
        #expect(canvas.globalOpacity == 0.75)
    }

    @Test("rendering at opacity 0.5 produces a half-alpha pixel")
    func renderAtHalfOpacity() throws {
        let view = CanvasView(frame: NSRect(x: 0, y: 0, width: 50, height: 50))
        let stroke = Stroke(id: "a", color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 4,
                            transform: .identity,
                            points: [StrokePoint(x: 10, y: 5), StrokePoint(x: 40, y: 5)],
                            pointerType: .mouse, pressureEnabled: false, createdAt: 0)
        view.render(RenderFrame(strokes: [stroke], inProgress: nil,
                                canvasSize: Size(width: 50, height: 50)))
        view.setGlobalOpacity(0.5)
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let pixel = try #require(rep.colorAt(x: 25, y: 5))
        // Stroke is opaque red; at opacity 0.5 it should sample to alpha ~0.5.
        #expect(abs(pixel.alphaComponent - 0.5) < 0.1)
    }
}
