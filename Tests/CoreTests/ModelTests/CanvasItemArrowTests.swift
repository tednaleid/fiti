// ABOUTME: CanvasItem.arrow case: shared accessors, restyle, and SelectionMath
// ABOUTME: world AABB plus point-in-polygon hit-test for arrows.

import Foundation
import Testing

@Suite("CanvasItem arrow")
struct CanvasItemArrowTests {
    private func arrowItem() -> ArrowItem {
        ArrowItem(id: "arrow-1", color: RGBA(r: 0, g: 0, b: 1, a: 0.5), width: 10,
                  transform: .identity, tail: Point(x: 0, y: 0), head: Point(x: 100, y: 0),
                  createdAt: 1)
    }

    @Test("shared accessors and restyle")
    func sharedAccessors() {
        let item = CanvasItem.arrow(arrowItem())
        #expect(item.color == RGBA(r: 0, g: 0, b: 1, a: 0.5))
        #expect(item.transform == .identity)
        let recolored = item.withColor(RGBA(r: 1, g: 0, b: 0, a: 1))
        #expect(recolored.color == RGBA(r: 1, g: 0, b: 0, a: 1))
    }

    @Test("world AABB covers the head")
    func worldAABBCoversHead() {
        let box = SelectionMath.worldAABB(of: .arrow(arrowItem()))
        #expect(box != nil)
        // The barbs are the widest part of the head; the AABB spans +/- the barb half-span.
        let barb = ArrowGeometry.barbSpanFactor * 10
        #expect(abs(box!.y + barb) < 1e-6)
        #expect(abs(box!.height - 2 * barb) < 1e-6)
    }

    @Test("hit-test inside and outside")
    func hitTestInsideAndOutside() {
        let id = "arrow-1"
        let items: [ItemId: CanvasItem] = [id: .arrow(arrowItem())]
        #expect(SelectionMath.hitTestItem(at: Point(x: 30, y: 0), items: items, order: [id], tolerance: 0) == id)
        #expect(SelectionMath.hitTestItem(at: Point(x: 30, y: 40), items: items, order: [id], tolerance: 0) == nil)
    }
}
