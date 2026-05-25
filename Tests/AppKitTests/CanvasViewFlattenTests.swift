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
        view.render(RenderFrame(items: [.stroke(committed)], inProgress: .stroke(live),
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
        liveView.render(RenderFrame(items: [.stroke(h)], inProgress: .stroke(v),
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

    @Test("WYSIWYG: a committed mark above the live group's color stays on top while drawing")
    func liveZOrderMatchesCommitted() throws {
        let red = RGBA(r: 1, g: 0, b: 0, a: 0.5)
        let blue = RGBA(r: 0, g: 0, b: 1, a: 1)   // opaque so on-top is unambiguous
        func vbar(_ id: String, x: Double, _ y0: Double, _ y1: Double, _ c: RGBA) -> Stroke {
            Stroke(id: id, color: c, width: 16, transform: .identity,
                   points: [StrokePoint(x: x, y: y0), StrokePoint(x: x, y: y1)],
                   pointerType: .mouse, pressureEnabled: false, createdAt: 0)
        }
        func hbar(_ id: String, y: Double, _ c: RGBA) -> Stroke {
            Stroke(id: id, color: c, width: 16, transform: .identity,
                   points: [StrokePoint(x: 10, y: y), StrokePoint(x: 90, y: y)],
                   pointerType: .mouse, pressureEnabled: false, createdAt: 0)
        }
        let r1 = vbar("r1", x: 30, 10, 90, red)
        let b  = hbar("b", y: 50, blue)
        let r2 = vbar("r2", x: 70, 10, 40, red)   // away from blue (y=50)

        func crossingBlueComponent(committed: [CanvasItem], inProgress: CanvasItem?) throws -> CGFloat {
            let view = CanvasView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
            view.testOnly_overrideBackingScale = 1
            view.render(RenderFrame(items: committed, inProgress: inProgress,
                                    canvasSize: Size(width: 100, height: 100)))
            let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: rep)
            return try #require(rep.colorAt(x: 30, y: 50)).blueComponent
        }
        // live: r1 + blue committed, r2 in progress (r2 joins the red group below blue)
        let liveBlue = try crossingBlueComponent(committed: [.stroke(r1), .stroke(b)], inProgress: .stroke(r2))
        // committed: all three
        let comBlue = try crossingBlueComponent(committed: [.stroke(r1), .stroke(b), .stroke(r2)], inProgress: nil)
        #expect(comBlue > 0.5, "committed: blue is on top at the crossing")
        #expect(liveBlue > 0.5, "while drawing: blue must also stay on top at the crossing")
        #expect(abs(liveBlue - comBlue) < 0.15, "live z-order matches committed")
    }
}
