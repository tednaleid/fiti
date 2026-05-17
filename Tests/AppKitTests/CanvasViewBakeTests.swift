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
