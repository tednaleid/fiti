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

    @Test("in-progress stroke flattens live with a committed same-color mark")
    func liveStrokeFlattensWithCommitted() throws {
        let view = CanvasView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        view.testOnly_overrideBackingScale = 1
        let red = RGBA(r: 1, g: 0, b: 0, a: 0.5)
        let committed = Stroke(id: "h", color: red, width: 16, transform: .identity,
                               points: [StrokePoint(x: 10, y: 50), StrokePoint(x: 90, y: 50)],
                               pointerType: .mouse, pressureEnabled: false, createdAt: 0)
        let live = Stroke(id: "v", color: red, width: 16, transform: .identity,
                          points: [StrokePoint(x: 50, y: 10), StrokePoint(x: 50, y: 90)],
                          pointerType: .mouse, pressureEnabled: false, createdAt: 1)
        view.render(RenderFrame(items: [.stroke(committed)], inProgress: live,
                                canvasSize: Size(width: 100, height: 100)))
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let arm = try #require(rep.colorAt(x: 20, y: 50)).alphaComponent
        let center = try #require(rep.colorAt(x: 50, y: 50)).alphaComponent
        #expect(arm > 0.3)
        #expect(center < 0.65)
        #expect(abs(center - arm) < 0.15)
    }

    @Test("WYSIWYG: live crossing matches the same two marks committed")
    func liveMatchesCommitted() throws {
        let red = RGBA(r: 1, g: 0, b: 0, a: 0.5)
        let h = Stroke(id: "h", color: red, width: 16, transform: .identity,
                       points: [StrokePoint(x: 10, y: 50), StrokePoint(x: 90, y: 50)],
                       pointerType: .mouse, pressureEnabled: false, createdAt: 0)
        let v = Stroke(id: "v", color: red, width: 16, transform: .identity,
                       points: [StrokePoint(x: 50, y: 10), StrokePoint(x: 50, y: 90)],
                       pointerType: .mouse, pressureEnabled: false, createdAt: 1)
        let liveView = CanvasView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        liveView.testOnly_overrideBackingScale = 1
        liveView.render(RenderFrame(items: [.stroke(h)], inProgress: v,
                                    canvasSize: Size(width: 100, height: 100)))
        let liveRep = try #require(liveView.bitmapImageRepForCachingDisplay(in: liveView.bounds))
        liveView.cacheDisplay(in: liveView.bounds, to: liveRep)
        let comView = CanvasView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        comView.testOnly_overrideBackingScale = 1
        comView.render(RenderFrame(items: [.stroke(h), .stroke(v)], inProgress: nil,
                                   canvasSize: Size(width: 100, height: 100)))
        let comRep = try #require(comView.bitmapImageRepForCachingDisplay(in: comView.bounds))
        comView.cacheDisplay(in: comView.bounds, to: comRep)
        let liveCenter = try #require(liveRep.colorAt(x: 50, y: 50)).alphaComponent
        let comCenter = try #require(comRep.colorAt(x: 50, y: 50)).alphaComponent
        #expect(abs(liveCenter - comCenter) < 0.08)
    }
}
