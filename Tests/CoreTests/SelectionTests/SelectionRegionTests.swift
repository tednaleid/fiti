// ABOUTME: Tests for SelectionMath.region — classifies a point against an
// ABOUTME: oriented box into rotateHandle / corner / body / outside.

import Testing

@Suite("SelectionMath.region")
struct SelectionRegionTests {
    private let box = OrientedBox(center: Point(x: 100, y: 100),
                                  size: Size(width: 40, height: 20), rotation: 0)

    private func region(at p: Point, box: OrientedBox?, handleRadius: Double = 8) -> SelectionRegion {
        SelectionMath.region(at: p, box: box, handleRadius: handleRadius,
                             rotateNodeOffset: 20, rotateNodeRadius: 10)
    }

    @Test("nil box is always outside")
    func nilBox() {
        #expect(region(at: Point(x: 100, y: 100), box: nil) == .outside)
    }

    @Test("point on the rotate node classifies as rotateHandle")
    func node() {
        #expect(region(at: Point(x: 100, y: 70), box: box) == .rotateHandle)
    }

    @Test("rotate node uses a larger grab radius than corners")
    func nodeRadiusExceedsCornerRadius() {
        // 9pt from the node (y=70) is beyond the 8pt corner radius but within
        // the 10pt rotate-node radius, so it still grabs the node.
        #expect(region(at: Point(x: 109, y: 70), box: box) == .rotateHandle)
    }

    @Test("points on each corner classify as that corner")
    func corners() {
        #expect(region(at: Point(x: 80, y: 90), box: box) == .corner(.topLeft))
        #expect(region(at: Point(x: 120, y: 90), box: box) == .corner(.topRight))
        #expect(region(at: Point(x: 120, y: 110), box: box) == .corner(.bottomRight))
        #expect(region(at: Point(x: 80, y: 110), box: box) == .corner(.bottomLeft))
    }

    @Test("interior is body, far away is outside")
    func bodyAndOutside() {
        #expect(region(at: Point(x: 100, y: 100), box: box) == .body)
        #expect(region(at: Point(x: 500, y: 500), box: box) == .outside)
    }

    @Test("on a rotated box, the rotated top-left corner still classifies as topLeft")
    func rotatedCorner() {
        let rbox = OrientedBox(center: Point(x: 0, y: 0), size: Size(width: 20, height: 20), rotation: 90)
        // local topLeft (-10,-10) at rotation 90 (y-down) → world (10,-10).
        #expect(region(at: Point(x: 10, y: -10), box: rbox) == .corner(.topLeft))
    }
}
