// ABOUTME: Tests for Editor.straightenCurrentStroke and moveCurrentStrokeEndpoint.
// ABOUTME: In-place mutations on the in-progress stroke; whole stroke is one undo unit.

import Testing

@Suite("Editor straighten & move endpoint")
@MainActor
struct EditorStraightenTests {
    private func make() -> Editor {
        Editor(clock: VirtualClock(), ids: SeededIdGenerator(prefix: "s"))
    }

    @Test("straightenCurrentStroke replaces points with [first, last]")
    func straighten() {
        let e = make()
        let red = RGBA(r: 1, g: 0, b: 0, a: 1)
        let id = e.startStroke(color: red, width: 4, pointerType: .mouse)
        e.appendPoint(StrokePoint(x: 0, y: 0))
        e.appendPoint(StrokePoint(x: 3, y: 1))
        e.appendPoint(StrokePoint(x: 6, y: -1))
        e.appendPoint(StrokePoint(x: 10, y: 0))
        e.straightenCurrentStroke()
        let pts = e.doc.strokes[id]!.points
        #expect(pts.count == 2)
        #expect(pts.first == StrokePoint(x: 0, y: 0))
        #expect(pts.last == StrokePoint(x: 10, y: 0))
    }

    @Test("straightenCurrentStroke is a no-op when no stroke in progress")
    func straightenNoStroke() {
        let e = make()
        e.straightenCurrentStroke()  // does not crash
    }

    @Test("straightenCurrentStroke with fewer than 2 points is a no-op")
    func straightenTooFew() {
        let e = make()
        _ = e.startStroke(color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 4, pointerType: .mouse)
        e.appendPoint(StrokePoint(x: 0, y: 0))
        e.straightenCurrentStroke()
        #expect(e.doc.strokes[e.currentStrokeId!]!.points.count == 1)
    }

    @Test("moveCurrentStrokeEndpoint replaces the last point in place")
    func moveEndpoint() {
        let e = make()
        let id = e.startStroke(color: RGBA(r: 0, g: 1, b: 0, a: 1), width: 4, pointerType: .mouse)
        e.appendPoint(StrokePoint(x: 0, y: 0))
        e.appendPoint(StrokePoint(x: 10, y: 10))
        e.moveCurrentStrokeEndpoint(to: StrokePoint(x: 20, y: 5))
        let pts = e.doc.strokes[id]!.points
        #expect(pts.count == 2)
        #expect(pts.last == StrokePoint(x: 20, y: 5))
    }

    @Test("moveCurrentStrokeEndpoint is a no-op when no stroke in progress")
    func moveEndpointNoStroke() {
        let e = make()
        e.moveCurrentStrokeEndpoint(to: StrokePoint(x: 1, y: 1))  // does not crash
    }

    @Test("undo after straightenCurrentStroke + endStroke removes the whole stroke")
    func undoAfterStraighten() {
        let e = make()
        let id = e.startStroke(color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 4, pointerType: .mouse)
        e.appendPoint(StrokePoint(x: 0, y: 0))
        e.appendPoint(StrokePoint(x: 5, y: 1))
        e.appendPoint(StrokePoint(x: 10, y: 0))
        e.straightenCurrentStroke()
        e.moveCurrentStrokeEndpoint(to: StrokePoint(x: 15, y: 0))
        e.endStroke()
        #expect(e.doc.strokes[id] != nil)
        #expect(e.undo())
        #expect(e.doc.strokes[id] == nil)
    }
}
