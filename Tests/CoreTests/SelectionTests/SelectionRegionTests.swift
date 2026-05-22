// ABOUTME: Tests for SelectionMath.region — classifies a point against an
// ABOUTME: oriented box into rotateHandle / corner / body / outside.

import Testing

@Suite("SelectionMath.region")
struct SelectionRegionTests {
    private let box = OrientedBox(center: Point(x: 100, y: 100),
                                  size: Size(width: 40, height: 20), rotation: 0)

    @Test("nil box is always outside")
    func nilBox() {
        #expect(SelectionMath.region(at: Point(x: 100, y: 100), box: nil,
                                     handleRadius: 8, rotateNodeOffset: 20) == .outside)
    }

    @Test("point on the rotate node classifies as rotateHandle")
    func node() {
        let r = SelectionMath.region(at: Point(x: 100, y: 70), box: box,
                                     handleRadius: 8, rotateNodeOffset: 20)
        #expect(r == .rotateHandle)
    }

    @Test("points on each corner classify as that corner")
    func corners() {
        let hr = 8.0
        #expect(SelectionMath.region(at: Point(x: 80, y: 90), box: box, handleRadius: hr, rotateNodeOffset: 20) == .corner(.topLeft))
        #expect(SelectionMath.region(at: Point(x: 120, y: 90), box: box, handleRadius: hr, rotateNodeOffset: 20) == .corner(.topRight))
        #expect(SelectionMath.region(at: Point(x: 120, y: 110), box: box, handleRadius: hr, rotateNodeOffset: 20) == .corner(.bottomRight))
        #expect(SelectionMath.region(at: Point(x: 80, y: 110), box: box, handleRadius: hr, rotateNodeOffset: 20) == .corner(.bottomLeft))
    }

    @Test("interior is body, far away is outside")
    func bodyAndOutside() {
        #expect(SelectionMath.region(at: Point(x: 100, y: 100), box: box, handleRadius: 8, rotateNodeOffset: 20) == .body)
        #expect(SelectionMath.region(at: Point(x: 500, y: 500), box: box, handleRadius: 8, rotateNodeOffset: 20) == .outside)
    }

    @Test("on a rotated box, the rotated top-left corner still classifies as topLeft")
    func rotatedCorner() {
        let rbox = OrientedBox(center: Point(x: 0, y: 0), size: Size(width: 20, height: 20), rotation: 90)
        // local topLeft (-10,-10) at rotation 90 (y-down) → world (10,-10).
        let r = SelectionMath.region(at: Point(x: 10, y: -10), box: rbox, handleRadius: 8, rotateNodeOffset: 20)
        #expect(r == .corner(.topLeft))
    }
}
