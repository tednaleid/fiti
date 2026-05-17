// ABOUTME: Verifies CanvasView caches the committed bake and invalidates
// ABOUTME: when strokeOrder changes.

import AppKit
import Testing

@MainActor
@Suite("CanvasView bake invariant")
struct CanvasViewBakeTests {
    @Test("first render bakes the committed signature")
    func firstBake() {
        let view = CanvasView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let stroke = Stroke(id: "a", color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 2,
                            transform: .identity,
                            points: [StrokePoint(x: 0, y: 0), StrokePoint(x: 50, y: 50)],
                            pointerType: .mouse, pressureEnabled: false, createdAt: 0)
        let frame = RenderFrame(strokes: [stroke], inProgress: nil,
                                canvasSize: Size(width: 100, height: 100))
        view.render(frame)
        #expect(view.committedSignature == ["a"])
    }

    @Test("adding a stroke invalidates the bake signature")
    func newStrokeInvalidates() {
        let view = CanvasView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let s1 = Stroke(id: "a", color: RGBA(r: 0, g: 0, b: 0, a: 1), width: 1,
                        transform: .identity, points: [], pointerType: .mouse,
                        pressureEnabled: false, createdAt: 0)
        view.render(RenderFrame(strokes: [s1], inProgress: nil,
                                canvasSize: Size(width: 100, height: 100)))
        let s2 = Stroke(id: "b", color: RGBA(r: 0, g: 0, b: 0, a: 1), width: 1,
                        transform: .identity, points: [], pointerType: .mouse,
                        pressureEnabled: false, createdAt: 0)
        view.render(RenderFrame(strokes: [s1, s2], inProgress: nil,
                                canvasSize: Size(width: 100, height: 100)))
        #expect(view.committedSignature == ["a", "b"])
    }

    @Test("a committed stroke near the top renders near the top of the view")
    func committedStrokeOrientation() throws {
        let view = CanvasView(frame: NSRect(x: 0, y: 0, width: 50, height: 50))
        let stroke = Stroke(id: "a", color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 4,
                            transform: .identity,
                            points: [StrokePoint(x: 10, y: 5), StrokePoint(x: 40, y: 5)],
                            pointerType: .mouse, pressureEnabled: false, createdAt: 0)
        view.render(RenderFrame(strokes: [stroke], inProgress: nil,
                                canvasSize: Size(width: 50, height: 50)))
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let top = try #require(rep.colorAt(x: 25, y: 5))
        let bottom = try #require(rep.colorAt(x: 25, y: 45))
        #expect(top.redComponent > 0.5, "stroke should be near the top of the view")
        #expect(bottom.redComponent < 0.1, "no stroke should appear near the bottom")
    }

    @Test("in-progress stroke is excluded from the committed signature")
    func inProgressExcluded() {
        let view = CanvasView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let committed = Stroke(id: "a", color: RGBA(r: 0, g: 0, b: 0, a: 1), width: 1,
                               transform: .identity, points: [], pointerType: .mouse,
                               pressureEnabled: false, createdAt: 0)
        let live = Stroke(id: "b", color: RGBA(r: 0, g: 0, b: 0, a: 1), width: 1,
                          transform: .identity, points: [], pointerType: .mouse,
                          pressureEnabled: false, createdAt: 0)
        view.render(RenderFrame(strokes: [committed, live], inProgress: live,
                                canvasSize: Size(width: 100, height: 100)))
        #expect(view.committedSignature == ["a"])
    }
}
