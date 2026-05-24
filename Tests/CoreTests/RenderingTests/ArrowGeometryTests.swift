// ABOUTME: ArrowGeometry.outline tests: vertex layout, width scaling, taper, degeneracy.
// ABOUTME: Pure Core; verifies the merged shaft+head polygon for a known arrow.

import Foundation
import Testing

@Suite("ArrowGeometry")
struct ArrowGeometryTests {
    @Test("horizontal arrow vertex layout")
    func horizontalArrowVertices() {
        let pts = ArrowGeometry.outline(tail: Point(x: 0, y: 0), head: Point(x: 100, y: 0), width: 10)
        #expect(pts.count == 7)
        #expect(pts[3] == Point(x: 100, y: 0))                              // tip is the head
        #expect(abs(pts[2].x - 55) < 1e-9 && abs(pts[2].y - 26) < 1e-9)     // left barb tip
        #expect(abs(pts[4].x - 55) < 1e-9 && abs(pts[4].y + 26) < 1e-9)     // right barb tip
        #expect(abs(pts[0].y - 2.75) < 1e-9)                                // tail edge half-width
        #expect(abs(pts[6].y + 2.75) < 1e-9)
    }

    @Test("head scales with width")
    func headScalesWithWidth() {
        let small = ArrowGeometry.outline(tail: Point(x: 0, y: 0), head: Point(x: 200, y: 0), width: 10)
        let big = ArrowGeometry.outline(tail: Point(x: 0, y: 0), head: Point(x: 200, y: 0), width: 20)
        #expect(abs(big[2].y - small[2].y * 2) < 1e-9)
    }

    @Test("tail narrower than barb span (taper)")
    func tailNarrowerThanBarbSpan() {
        let pts = ArrowGeometry.outline(tail: Point(x: 0, y: 0), head: Point(x: 100, y: 0), width: 10)
        #expect(abs(pts[0].y) < abs(pts[2].y))
    }

    @Test("degenerate inputs return empty")
    func degenerateIsEmpty() {
        #expect(ArrowGeometry.outline(tail: Point(x: 5, y: 5), head: Point(x: 5, y: 5), width: 10).isEmpty)
        #expect(ArrowGeometry.outline(tail: Point(x: 0, y: 0), head: Point(x: 10, y: 0), width: 0).isEmpty)
    }
}
