// ABOUTME: Tests for OrientedBox geometry — corners, rotate node, and the
// ABOUTME: world↔local round-trip at rotation 0 and non-zero.

import Testing

@Suite("OrientedBox")
struct OrientedBoxTests {
    private func approx(_ a: Double, _ b: Double, _ eps: Double = 1e-9) -> Bool { abs(a - b) <= eps }

    @Test("corners at rotation 0 are center ± half-size, ordered TL/TR/BR/BL")
    func cornersUnrotated() {
        let box = OrientedBox(center: Point(x: 100, y: 100), size: Size(width: 40, height: 20), rotation: 0)
        let c = box.corners()
        #expect(approx(c[0].x, 80) && approx(c[0].y, 90))   // topLeft
        #expect(approx(c[1].x, 120) && approx(c[1].y, 90))  // topRight
        #expect(approx(c[2].x, 120) && approx(c[2].y, 110)) // bottomRight
        #expect(approx(c[3].x, 80) && approx(c[3].y, 110))  // bottomLeft
    }

    @Test("rotateNode at rotation 0 sits above the top-edge midpoint")
    func rotateNodeUnrotated() {
        let box = OrientedBox(center: Point(x: 100, y: 100), size: Size(width: 40, height: 20), rotation: 0)
        let n = box.rotateNode(offset: 20)
        #expect(approx(n.x, 100) && approx(n.y, 70))  // top edge y=90, minus 20
    }

    @Test("toLocal is the inverse of the world placement (round-trip)")
    func toLocalRoundTrip() {
        let box = OrientedBox(center: Point(x: 50, y: 50), size: Size(width: 30, height: 30), rotation: 30)
        // A world corner maps back to its local position (±halfW, ±halfH).
        let worldTL = box.corners()[0]
        let local = box.toLocal(worldTL)
        #expect(approx(local.x, -15) && approx(local.y, -15))
    }

    @Test("90° rotation sends the local top edge to the right side")
    func rotated90() {
        let box = OrientedBox(center: Point(x: 0, y: 0), size: Size(width: 20, height: 20), rotation: 90)
        // local topLeft (-10,-10) rotates +90 (y-down screen) → (10,-10).
        let c = box.corners()[0]
        #expect(approx(c.x, 10) && approx(c.y, -10))
    }
}
