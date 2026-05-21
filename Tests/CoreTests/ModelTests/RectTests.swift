// ABOUTME: Tests for the Core Rect value — origin + size, intersection,
// ABOUTME: contains-point. Doesn't import CoreGraphics.

import Testing

@Suite("Rect")
struct RectTests {
    @Test("rect stores x/y/width/height")
    func basicShape() {
        let r = Rect(x: 1, y: 2, width: 3, height: 4)
        #expect(r.x == 1)
        #expect(r.y == 2)
        #expect(r.width == 3)
        #expect(r.height == 4)
    }

    @Test("intersects returns true when rects overlap")
    func intersectsOverlap() {
        let a = Rect(x: 0, y: 0, width: 10, height: 10)
        let b = Rect(x: 5, y: 5, width: 10, height: 10)
        #expect(a.intersects(b))
        #expect(b.intersects(a))
    }

    @Test("intersects returns false when rects are disjoint")
    func intersectsDisjoint() {
        let a = Rect(x: 0, y: 0, width: 5, height: 5)
        let b = Rect(x: 10, y: 10, width: 5, height: 5)
        #expect(!a.intersects(b))
    }

    @Test("intersects returns true when one rect contains the other")
    func intersectsContained() {
        let outer = Rect(x: 0, y: 0, width: 100, height: 100)
        let inner = Rect(x: 10, y: 10, width: 5, height: 5)
        #expect(outer.intersects(inner))
        #expect(inner.intersects(outer))
    }

    @Test("intersects is closed — touching edges count as intersection")
    func intersectsTouchingEdges() {
        let a = Rect(x: 0, y: 0, width: 10, height: 10)
        let b = Rect(x: 10, y: 0, width: 10, height: 10)
        #expect(a.intersects(b))
        #expect(b.intersects(a))
    }
}
