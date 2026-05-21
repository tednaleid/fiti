// ABOUTME: Tests for SelectionMath pure functions — hit-test, marquee-hit,
// ABOUTME: and selectionBounds. No state, no AppKit.

import Testing

@Suite("SelectionMath")
struct SelectionMathTests {
    private func makeStroke(id: String, points: [StrokePoint], width: Double = 4,
                            transform: Transform = .identity) -> Stroke {
        Stroke(id: id, color: RGBA(r: 0, g: 0, b: 0, a: 1), width: width,
               transform: transform, points: points,
               pointerType: .mouse, pressureEnabled: false, createdAt: 0)
    }

    // MARK: hitTest

    @Test("hitTest returns the stroke when the query is on its polyline")
    func hitTestOnPoint() {
        let s = makeStroke(id: "a", points: [StrokePoint(x: 0, y: 0), StrokePoint(x: 100, y: 0)])
        let hit = SelectionMath.hitTest(point: StrokePoint(x: 50, y: 0), strokes: [s], tolerance: 1)
        #expect(hit == "a")
    }

    @Test("hitTest returns the stroke when the query is within width/2 + tolerance")
    func hitTestWithinHalfWidth() {
        let s = makeStroke(id: "a", points: [StrokePoint(x: 0, y: 0), StrokePoint(x: 100, y: 0)], width: 10)
        let hit = SelectionMath.hitTest(point: StrokePoint(x: 50, y: 4), strokes: [s], tolerance: 1)
        #expect(hit == "a")
    }

    @Test("hitTest returns nil when the query is too far from any stroke")
    func hitTestFar() {
        let s = makeStroke(id: "a", points: [StrokePoint(x: 0, y: 0), StrokePoint(x: 100, y: 0)], width: 10)
        let hit = SelectionMath.hitTest(point: StrokePoint(x: 50, y: 50), strokes: [s], tolerance: 1)
        #expect(hit == nil)
    }

    @Test("hitTest with overlapping strokes returns the topmost (last in array)")
    func hitTestTopmost() {
        let s1 = makeStroke(id: "bottom", points: [StrokePoint(x: 0, y: 0), StrokePoint(x: 100, y: 0)])
        let s2 = makeStroke(id: "top", points: [StrokePoint(x: 0, y: 0), StrokePoint(x: 100, y: 0)])
        let hit = SelectionMath.hitTest(point: StrokePoint(x: 50, y: 0), strokes: [s1, s2], tolerance: 1)
        #expect(hit == "top")
    }

    @Test("hitTest with empty stroke array returns nil")
    func hitTestEmpty() {
        let hit = SelectionMath.hitTest(point: StrokePoint(x: 0, y: 0), strokes: [], tolerance: 1)
        #expect(hit == nil)
    }

    // MARK: marqueeHit

    @Test("marqueeHit returns strokes whose AABB intersects the marquee")
    func marqueeIntersect() {
        let s1 = makeStroke(id: "in", points: [StrokePoint(x: 10, y: 10), StrokePoint(x: 20, y: 20)])
        let s2 = makeStroke(id: "out", points: [StrokePoint(x: 100, y: 100), StrokePoint(x: 110, y: 110)])
        let ids = SelectionMath.marqueeHit(rect: Rect(x: 0, y: 0, width: 30, height: 30),
                                           strokes: [s1, s2])
        #expect(ids == ["in"])
    }

    @Test("marqueeHit returns all intersecting strokes in z-order")
    func marqueeMultiple() {
        let s1 = makeStroke(id: "a", points: [StrokePoint(x: 5, y: 5), StrokePoint(x: 15, y: 15)])
        let s2 = makeStroke(id: "b", points: [StrokePoint(x: 20, y: 20), StrokePoint(x: 25, y: 25)])
        let ids = SelectionMath.marqueeHit(rect: Rect(x: 0, y: 0, width: 30, height: 30),
                                           strokes: [s1, s2])
        #expect(ids == ["a", "b"])
    }

    @Test("marqueeHit with no overlap returns empty")
    func marqueeEmpty() {
        let s = makeStroke(id: "a", points: [StrokePoint(x: 100, y: 100), StrokePoint(x: 110, y: 110)])
        let ids = SelectionMath.marqueeHit(rect: Rect(x: 0, y: 0, width: 30, height: 30),
                                           strokes: [s])
        #expect(ids.isEmpty)
    }

    @Test("marqueeHit skips strokes with zero points")
    func marqueeHitSkipsEmptyStrokes() {
        let s = makeStroke(id: "empty", points: [])
        let ids = SelectionMath.marqueeHit(rect: Rect(x: -1000, y: -1000, width: 2000, height: 2000),
                                           strokes: [s])
        #expect(ids.isEmpty)
    }

    @Test("hitTest applies transform — translated stroke is hit at its new location")
    func hitTestAfterTranslate() {
        let s = makeStroke(id: "a",
                           points: [StrokePoint(x: 0, y: 0), StrokePoint(x: 5, y: 0)],
                           transform: Transform(x: 10, y: 0, scale: 1, rotate: 0))
        let hit = SelectionMath.hitTest(point: StrokePoint(x: 15, y: 0), strokes: [s], tolerance: 1)
        #expect(hit == "a")
    }

    // MARK: selectionBounds

    @Test("selectionBounds returns the AABB enclosing all selected strokes")
    func boundsUnion() {
        let s1 = makeStroke(id: "a", points: [StrokePoint(x: 0, y: 0), StrokePoint(x: 10, y: 10)])
        let s2 = makeStroke(id: "b", points: [StrokePoint(x: 20, y: 20), StrokePoint(x: 30, y: 40)])
        let bounds = SelectionMath.selectionBounds(strokeIds: ["a", "b"],
                                                   strokes: ["a": s1, "b": s2])
        #expect(bounds == Rect(x: 0, y: 0, width: 30, height: 40))
    }

    @Test("selectionBounds with empty id list returns nil")
    func boundsEmpty() {
        let bounds = SelectionMath.selectionBounds(strokeIds: [],
                                                   strokes: [String: Stroke]())
        #expect(bounds == nil)
    }

    @Test("selectionBounds with unknown id is skipped")
    func boundsUnknownId() {
        let s = makeStroke(id: "a", points: [StrokePoint(x: 5, y: 5), StrokePoint(x: 15, y: 15)])
        let bounds = SelectionMath.selectionBounds(strokeIds: ["a", "missing"],
                                                   strokes: ["a": s])
        #expect(bounds == Rect(x: 5, y: 5, width: 10, height: 10))
    }
}
