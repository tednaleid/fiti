// ABOUTME: Arrows flatten through the (hue, alpha) opacity grouping exactly like
// ABOUTME: strokes, and a live in-progress arrow is pixel-identical to its committed form.

import AppKit
import Testing

@MainActor
@Suite("Arrow flattening")
struct ArrowFlattenTests {
    func hArrow(_ id: String, y: Double, _ c: RGBA) -> ArrowItem {
        ArrowItem(id: id, color: c, width: 14, transform: .identity,
                  tail: Point(x: 10, y: y), head: Point(x: 90, y: y), createdAt: 0)
    }
    func vArrow(_ id: String, x: Double, _ c: RGBA) -> ArrowItem {
        ArrowItem(id: id, color: c, width: 14, transform: .identity,
                  tail: Point(x: x, y: 10), head: Point(x: x, y: 90), createdAt: 1)
    }
    func hStroke(_ id: String, y: Double, _ c: RGBA) -> Stroke {
        Stroke(id: id, color: c, width: 14, transform: .identity,
               points: [StrokePoint(x: 10, y: y), StrokePoint(x: 90, y: y)],
               pointerType: .mouse, pressureEnabled: false, createdAt: 0)
    }

    // Sample on the shaft, away from endpoints/heads, so both points are pure shaft.
    private let armX = 25, armY = 50, centerX = 50, centerY = 50

    @Test("two overlapping same-color 50% arrows are flat across the overlap")
    func overlappingArrowsAreFlat() throws {
        let view = CanvasView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        view.testOnly_overrideBackingScale = 1
        let red = RGBA(r: 1, g: 0, b: 0, a: 0.5)
        view.render(RenderFrame(items: [.arrow(hArrow("h", y: 50, red)),
                                        .arrow(vArrow("v", x: 50, red))],
                                inProgress: nil, canvasSize: Size(width: 100, height: 100)))
        let rep = NSBitmapImageRep(cgImage: try #require(view.testOnly_committedImage))
        let arm = try #require(rep.colorAt(x: armX, y: armY)).alphaComponent
        let center = try #require(rep.colorAt(x: centerX, y: centerY)).alphaComponent
        #expect(arm > 0.3)
        #expect(center < 0.65, "overlap must not accumulate to a darker alpha")
        #expect(abs(center - arm) < 0.12, "overlap matches a single arm (flat)")
    }

    @Test("a same-color arrow crossing a same-color stroke is flat (cross-type grouping)")
    func arrowCrossingStrokeIsFlat() throws {
        let view = CanvasView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        view.testOnly_overrideBackingScale = 1
        let red = RGBA(r: 1, g: 0, b: 0, a: 0.5)
        view.render(RenderFrame(items: [.stroke(hStroke("h", y: 50, red)),
                                        .arrow(vArrow("v", x: 50, red))],
                                inProgress: nil, canvasSize: Size(width: 100, height: 100)))
        let rep = NSBitmapImageRep(cgImage: try #require(view.testOnly_committedImage))
        let arm = try #require(rep.colorAt(x: armX, y: armY)).alphaComponent
        let center = try #require(rep.colorAt(x: centerX, y: centerY)).alphaComponent
        #expect(arm > 0.3)
        #expect(center < 0.65, "arrow+stroke overlap must not accumulate")
        #expect(abs(center - arm) < 0.12, "arrow and stroke flatten together")
    }

    @Test("a different-color mark above the arrow shows on top at the crossing (z-order)")
    func zOrderPreservedOverArrow() throws {
        let view = CanvasView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        view.testOnly_overrideBackingScale = 1
        let red = RGBA(r: 1, g: 0, b: 0, a: 0.5)
        let blue = RGBA(r: 0, g: 0, b: 1, a: 1)   // opaque so on-top is unambiguous
        // red arrow below, blue stroke above (later in z-order).
        view.render(RenderFrame(items: [.arrow(vArrow("a", x: 50, red)),
                                        .stroke(hStroke("b", y: 50, blue))],
                                inProgress: nil, canvasSize: Size(width: 100, height: 100)))
        let rep = NSBitmapImageRep(cgImage: try #require(view.testOnly_committedImage))
        let blueAtCross = try #require(rep.colorAt(x: centerX, y: centerY)).blueComponent
        #expect(blueAtCross > 0.5, "blue stroke stays on top of the arrow at the crossing")
    }

    @Test("WYSIWYG: a live crossing arrow matches the same two marks committed")
    func liveArrowMatchesCommitted() throws {
        let red = RGBA(r: 1, g: 0, b: 0, a: 0.5)
        let committed = hStroke("h", y: 50, red)
        let arrow = vArrow("v", x: 50, red)

        let liveView = CanvasView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        liveView.testOnly_overrideBackingScale = 1
        liveView.render(RenderFrame(items: [.stroke(committed)], inProgress: .arrow(arrow),
                                    canvasSize: Size(width: 100, height: 100)))
        let liveRep = try #require(liveView.bitmapImageRepForCachingDisplay(in: liveView.bounds))
        liveView.cacheDisplay(in: liveView.bounds, to: liveRep)

        let comView = CanvasView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        comView.testOnly_overrideBackingScale = 1
        comView.render(RenderFrame(items: [.stroke(committed), .arrow(arrow)], inProgress: nil,
                                   canvasSize: Size(width: 100, height: 100)))
        let comRep = try #require(comView.bitmapImageRepForCachingDisplay(in: comView.bounds))
        comView.cacheDisplay(in: comView.bounds, to: comRep)

        let liveCenter = try #require(liveRep.colorAt(x: centerX, y: centerY)).alphaComponent
        let comCenter = try #require(comRep.colorAt(x: centerX, y: centerY)).alphaComponent
        #expect(abs(liveCenter - comCenter) < 0.08, "live arrow is pixel-identical to committed")
    }

    @Test("a just-started zero-length arrow does not hide committed marks")
    func degenerateArrowKeepsCommittedVisible() throws {
        let view = CanvasView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        view.testOnly_overrideBackingScale = 1
        let red = RGBA(r: 1, g: 0, b: 0, a: 1)
        // An in-progress arrow at pointer-down has tail == head (no geometry). It shares
        // the committed mark's hue, so it would join that layer. Lifting the layer for a
        // non-drawable live item once pulled the committed mark out of the static bake
        // and left it unpainted until the first move.
        let degenerate = ArrowItem(id: "live", color: red, width: 14, transform: .identity,
                                   tail: Point(x: 50, y: 50), head: Point(x: 50, y: 50), createdAt: 2)
        view.render(RenderFrame(items: [.arrow(hArrow("committed", y: 50, red))],
                                inProgress: .arrow(degenerate),
                                canvasSize: Size(width: 100, height: 100)))
        let rep = NSBitmapImageRep(cgImage: try #require(view.testOnly_committedImage))
        let onShaft = try #require(rep.colorAt(x: armX, y: armY)).alphaComponent
        #expect(onShaft > 0.5, "committed mark stays painted while a zero-length arrow is in progress")
    }
}
