// ABOUTME: ArrowGeometry.outline tests: head layout, getStroke-derived shaft, tail cap.
// ABOUTME: Pure Core; verifies the merged shaft+head polygon for a known arrow.

import Foundation
import Testing

@Suite("ArrowGeometry")
struct ArrowGeometryTests {
    @Test("solid swept head: tip and barbs")
    func headLayout() {
        let w = 10.0
        let pts = ArrowGeometry.outline(tail: Point(x: 0, y: 0), head: Point(x: 100, y: 0), width: w)
        // 7 base vertices + the rounded tail-cap arc (tailCapSegments - 1 interior points).
        #expect(pts.count == 7 + ArrowGeometry.tailCapSegments - 1)
        let headLen = ArrowGeometry.headLengthFactor * w
        let barb = ArrowGeometry.barbSpanFactor * w
        #expect(pts[3] == Point(x: 100, y: 0))                  // tip is the head
        #expect(abs(pts[2].x - (100 - headLen)) < 1e-9)         // barbs sit at the head base
        #expect(abs(pts[2].y - barb) < 1e-9)                    // left barb
        #expect(abs(pts[4].y + barb) < 1e-9)                    // right barb
    }

    @Test("shaft half-width comes from the getStroke pipeline")
    func shaftMatchesGetStroke() {
        let w = 10.0
        let pts = ArrowGeometry.outline(tail: Point(x: 0, y: 0), head: Point(x: 100, y: 0), width: w)
        let half = ArrowGeometry.shaftHalfWidth(width: w)
        #expect(half > 0)
        #expect(abs(pts[0].y - half) < 1e-9)   // tail edge
        #expect(abs(pts[6].y + half) < 1e-9)
        #expect(abs(pts[1].y - half) < 1e-9)   // join edge -- uniform, no taper
    }

    @Test("notch sits forward of the base for a solid head")
    func notchNearBase() {
        let w = 10.0
        let pts = ArrowGeometry.outline(tail: Point(x: 0, y: 0), head: Point(x: 100, y: 0), width: w)
        let base = 100 - ArrowGeometry.headLengthFactor * w
        // join (notch) vertices pts[1]/pts[5] sit forward of the barb base, not at the
        // tip -- a shallow concave back, i.e. a solid swept head (not an open chevron).
        #expect(pts[1].x > base && pts[1].x < 100)
        #expect(abs(pts[1].x - pts[5].x) < 1e-9)
    }

    @Test("head scales with width")
    func headScalesWithWidth() {
        let small = ArrowGeometry.outline(tail: Point(x: 0, y: 0), head: Point(x: 200, y: 0), width: 10)
        let big = ArrowGeometry.outline(tail: Point(x: 0, y: 0), head: Point(x: 200, y: 0), width: 20)
        #expect(abs(big[2].y - small[2].y * 2) < 1e-9)
    }

    @Test("shaft narrower than the barb span")
    func shaftNarrowerThanBarb() {
        let pts = ArrowGeometry.outline(tail: Point(x: 0, y: 0), head: Point(x: 100, y: 0), width: 10)
        #expect(abs(pts[0].y) < abs(pts[2].y))
    }

    @Test("rounded tail cap bulges away from the head")
    func roundedTailCap() {
        let w = 10.0
        let pts = ArrowGeometry.outline(tail: Point(x: 0, y: 0), head: Point(x: 100, y: 0), width: w)
        let half = ArrowGeometry.shaftHalfWidth(width: w)
        let cap = pts[7...]   // interior cap points, after the 7 base vertices
        #expect(!cap.isEmpty)
        for p in cap {
            #expect(p.x <= 1e-9)                                           // behind the tail
            #expect(abs((p.x * p.x + p.y * p.y).squareRoot() - half) < 1e-6) // on the cap radius
        }
    }

    @Test("degenerate inputs return empty")
    func degenerateIsEmpty() {
        #expect(ArrowGeometry.outline(tail: Point(x: 5, y: 5), head: Point(x: 5, y: 5), width: 10).isEmpty)
        #expect(ArrowGeometry.outline(tail: Point(x: 0, y: 0), head: Point(x: 10, y: 0), width: 0).isEmpty)
    }
}
