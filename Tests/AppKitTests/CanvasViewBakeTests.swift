// ABOUTME: Verifies CanvasView caches the committed bake and invalidates when
// ABOUTME: itemOrder, transforms, or text content changes.

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
        let frame = RenderFrame(items: [.stroke(stroke)], inProgress: nil,
                                canvasSize: Size(width: 100, height: 100))
        view.render(frame)
        #expect(view.bakeSignatureForTesting.map(\.id) == ["a"])
    }

    @Test("adding a stroke invalidates the bake signature")
    func newStrokeInvalidates() {
        let view = CanvasView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let s1 = Stroke(id: "a", color: RGBA(r: 0, g: 0, b: 0, a: 1), width: 1,
                        transform: .identity, points: [], pointerType: .mouse,
                        pressureEnabled: false, createdAt: 0)
        view.render(RenderFrame(items: [.stroke(s1)], inProgress: nil,
                                canvasSize: Size(width: 100, height: 100)))
        let s2 = Stroke(id: "b", color: RGBA(r: 0, g: 0, b: 0, a: 1), width: 1,
                        transform: .identity, points: [], pointerType: .mouse,
                        pressureEnabled: false, createdAt: 0)
        view.render(RenderFrame(items: [.stroke(s1), .stroke(s2)], inProgress: nil,
                                canvasSize: Size(width: 100, height: 100)))
        #expect(view.bakeSignatureForTesting.map(\.id) == ["a", "b"])
    }

    @Test("a committed stroke near the top renders near the top of the view")
    func committedStrokeOrientation() throws {
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
        view.render(RenderFrame(items: [.stroke(committed), .stroke(live)], inProgress: live,
                                canvasSize: Size(width: 100, height: 100)))
        #expect(view.bakeSignatureForTesting.map(\.id) == ["a"])
    }

    @Test("bake CGImage dimensions match canvas points × backingScale (default 1)")
    func bakeDimensionsDefaultScale() throws {
        let view = CanvasView(frame: NSRect(x: 0, y: 0, width: 50, height: 50))
        let stroke = Stroke(id: "a", color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 4,
                            transform: .identity,
                            points: [StrokePoint(x: 10, y: 25), StrokePoint(x: 40, y: 25)],
                            pointerType: .mouse, pressureEnabled: false, createdAt: 0)
        view.render(RenderFrame(items: [.stroke(stroke)], inProgress: nil,
                                canvasSize: Size(width: 50, height: 50)))
        let image = try #require(view.testOnly_committedImage)
        #expect(image.width == 50)
        #expect(image.height == 50)
    }

    @Test("bake CGImage dimensions scale with backingScale = 2")
    func bakeDimensionsRetina() throws {
        let view = CanvasView(frame: NSRect(x: 0, y: 0, width: 50, height: 50))
        view.testOnly_overrideBackingScale = 2
        let stroke = Stroke(id: "a", color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 4,
                            transform: .identity,
                            points: [StrokePoint(x: 10, y: 25), StrokePoint(x: 40, y: 25)],
                            pointerType: .mouse, pressureEnabled: false, createdAt: 0)
        view.render(RenderFrame(items: [.stroke(stroke)], inProgress: nil,
                                canvasSize: Size(width: 50, height: 50)))
        let image = try #require(view.testOnly_committedImage)
        #expect(image.width == 100)
        #expect(image.height == 100)
    }

    @Test("same stroke ID with changed transform invalidates the bake")
    func transformChangeInvalidatesBake() throws {
        let view = CanvasView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let stroke1 = Stroke(id: "a", color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 2,
                             transform: .identity,
                             points: [StrokePoint(x: 0, y: 0), StrokePoint(x: 10, y: 10)],
                             pointerType: .mouse, pressureEnabled: false, createdAt: 0)
        let frame1 = RenderFrame(items: [.stroke(stroke1)], inProgress: nil,
                                 canvasSize: Size(width: 100, height: 100))
        view.render(frame1)
        let firstImage = try #require(view.testOnly_committedImage)

        let stroke2 = Stroke(id: "a", color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 2,
                             transform: Transform(x: 50, y: 0, scale: 1, rotate: 0),
                             points: [StrokePoint(x: 0, y: 0), StrokePoint(x: 10, y: 10)],
                             pointerType: .mouse, pressureEnabled: false, createdAt: 0)
        let frame2 = RenderFrame(items: [.stroke(stroke2)], inProgress: nil,
                                 canvasSize: Size(width: 100, height: 100))
        view.render(frame2)
        let secondImage = try #require(view.testOnly_committedImage)

        // The bake must have been re-issued — a different CGImage pointer proves it.
        #expect(firstImage !== secondImage)
    }

    @Test("changing backingScale invalidates the bake and re-bakes at new resolution")
    func bakeRespondsToScaleChange() throws {
        let view = CanvasView(frame: NSRect(x: 0, y: 0, width: 50, height: 50))
        let stroke = Stroke(id: "a", color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 4,
                            transform: .identity,
                            points: [StrokePoint(x: 10, y: 25), StrokePoint(x: 40, y: 25)],
                            pointerType: .mouse, pressureEnabled: false, createdAt: 0)
        let frame = RenderFrame(items: [.stroke(stroke)], inProgress: nil,
                                canvasSize: Size(width: 50, height: 50))

        view.testOnly_overrideBackingScale = 1
        view.render(frame)
        let firstImage = try #require(view.testOnly_committedImage)
        #expect(firstImage.width == 50)

        view.testOnly_overrideBackingScale = 2
        view.render(frame)
        let secondImage = try #require(view.testOnly_committedImage)
        #expect(secondImage.width == 100)
    }

    @Test("live items are not included in the bake signature")
    func liveStrokesNotBaked() {
        let view = CanvasView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let committed = Stroke(id: "a", color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 2,
                               transform: .identity, points: [],
                               pointerType: .mouse, pressureEnabled: false, createdAt: 0)
        let dragged = Stroke(id: "b", color: RGBA(r: 0, g: 1, b: 0, a: 1), width: 2,
                             transform: Transform(x: 10, y: 0, scale: 1, rotate: 0),
                             points: [], pointerType: .mouse, pressureEnabled: false, createdAt: 0)
        let frame = RenderFrame(items: [.stroke(committed)], liveItems: [.stroke(dragged)], inProgress: nil,
                                canvasSize: Size(width: 100, height: 100))
        view.render(frame)
        #expect(view.bakeSignatureForTesting.map(\.id) == ["a"])
        #expect(!view.bakeSignatureForTesting.map(\.id).contains("b"))
    }

    @Test("bake stays stable when only a live stroke moves")
    func bakeStableAcrossLiveStrokeMove() throws {
        let view = CanvasView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let committed = Stroke(id: "a", color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 2,
                               transform: .identity,
                               points: [StrokePoint(x: 0, y: 0), StrokePoint(x: 10, y: 10)],
                               pointerType: .mouse, pressureEnabled: false, createdAt: 0)
        let dragged = Stroke(id: "b", color: RGBA(r: 0, g: 1, b: 0, a: 1), width: 2,
                             transform: .identity,
                             points: [StrokePoint(x: 20, y: 20), StrokePoint(x: 30, y: 30)],
                             pointerType: .mouse, pressureEnabled: false, createdAt: 0)

        // Frame A: committed=[a], live=[b @ T1]
        let draggedT1 = Stroke(id: "b", color: dragged.color, width: dragged.width,
                               transform: Transform(x: 5, y: 5, scale: 1, rotate: 0),
                               points: dragged.points, pointerType: dragged.pointerType,
                               pressureEnabled: dragged.pressureEnabled, createdAt: dragged.createdAt)
        let frameA = RenderFrame(items: [.stroke(committed)], liveItems: [.stroke(draggedT1)], inProgress: nil,
                                 canvasSize: Size(width: 100, height: 100))
        view.render(frameA)
        let imageAfterA = try #require(view.testOnly_committedImage)
        let sigAfterA = view.bakeSignatureForTesting

        // Frame B: committed=[a] (unchanged), live=[b @ T2] — only live stroke moved
        let draggedT2 = Stroke(id: "b", color: dragged.color, width: dragged.width,
                               transform: Transform(x: 25, y: 25, scale: 1, rotate: 0),
                               points: dragged.points, pointerType: dragged.pointerType,
                               pressureEnabled: dragged.pressureEnabled, createdAt: dragged.createdAt)
        let frameB = RenderFrame(items: [.stroke(committed)], liveItems: [.stroke(draggedT2)], inProgress: nil,
                                 canvasSize: Size(width: 100, height: 100))
        view.render(frameB)
        let imageAfterB = try #require(view.testOnly_committedImage)
        let sigAfterB = view.bakeSignatureForTesting

        // Signature and CGImage pointer must be unchanged — no re-bake occurred.
        #expect(sigAfterA == sigAfterB)
        #expect(imageAfterA === imageAfterB)
    }

    @Test("a text item whose string changes produces a different bake signature")
    func textContentChangeYieldsDifferentSignature() {
        let view = CanvasView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))

        func frameWithText(_ string: String) -> RenderFrame {
            let text = TextItem(id: "t1", string: string, fontName: "Helvetica", fontSize: 16,
                                color: RGBA(r: 0, g: 0, b: 0, a: 1), transform: .identity,
                                bounds: Size(width: 50, height: 20), createdAt: 0)
            return RenderFrame(items: [.text(text)], inProgress: nil,
                               canvasSize: Size(width: 100, height: 100))
        }

        view.render(frameWithText("hello"))
        let sig1 = view.bakeSignatureForTesting

        view.render(frameWithText("world"))
        let sig2 = view.bakeSignatureForTesting

        #expect(sig1 != sig2, "different string should produce a different bake signature")
    }

    @Test("a live stroke renders at its transformed position")
    func liveStrokeRendersAtTransformedPosition() throws {
        // Canvas 200×200. Stroke points at y=50. With a y+80 translate the stroke
        // moves to y=130. CGContext uses bottom-left origin, so:
        //   CG y=50  → bitmap row 200-50  = 150 (original position, should be empty)
        //   CG y=130 → bitmap row 200-130 = 70  (translated position, should be ink)
        let view = CanvasView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        view.testOnly_overrideBackingScale = 1
        let stroke = Stroke(id: "live", color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 10,
                            transform: Transform(x: 0, y: 80, scale: 1, rotate: 0),
                            points: [StrokePoint(x: 50, y: 50),
                                     StrokePoint(x: 100, y: 50),
                                     StrokePoint(x: 150, y: 50)],
                            pointerType: .mouse, pressureEnabled: false, createdAt: 0)
        let frame = RenderFrame(items: [], liveItems: [.stroke(stroke)], inProgress: nil,
                                canvasSize: Size(width: 200, height: 200))
        view.render(frame)

        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)

        // Translated position (y=130 in flipped view coords = row 130 from top): should have ink.
        let atTranslated = try #require(rep.colorAt(x: 100, y: 130))
        #expect(atTranslated.redComponent > 0.5,
                "live stroke should render at translated position (view y=130)")

        // Original position (view y=50): should be background (no stroke was committed there).
        let atOriginal = try #require(rep.colorAt(x: 100, y: 50))
        #expect(atOriginal.redComponent < 0.1,
                "no ink should appear at original un-translated position (view y=50)")
    }
}
