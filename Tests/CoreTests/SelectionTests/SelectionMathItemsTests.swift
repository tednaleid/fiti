// ABOUTME: SelectionMath over a mixed stroke+text document — hit-test, marquee,
// ABOUTME: and selection bounds use each item's box (points vs frozen text bounds).

import Testing

@Suite("SelectionMath over items")
struct SelectionMathItemsTests {
    private func textItem(_ id: ItemId, at p: Point, size: Size) -> CanvasItem {
        .text(TextItem(id: id, string: "x", fontName: "Helvetica", fontSize: 24,
                       color: RGBA(r: 0, g: 0, b: 0, a: 1),
                       transform: Transform(x: p.x, y: p.y, scale: 1, rotate: 0),
                       bounds: size, createdAt: 0))
    }

    @Test("hit-test lands inside a text item's box")
    func hitText() {
        let item = textItem("t1", at: Point(x: 100, y: 100), size: Size(width: 60, height: 24))
        let order = ["t1"]
        let items: [ItemId: CanvasItem] = ["t1": item]
        #expect(SelectionMath.hitTestItem(at: Point(x: 110, y: 108), items: items, order: order, tolerance: 2) == "t1")
        #expect(SelectionMath.hitTestItem(at: Point(x: 500, y: 500), items: items, order: order, tolerance: 2) == nil)
    }

    @Test("marquee selects an intersecting text item")
    func marqueeText() {
        let item = textItem("t1", at: Point(x: 100, y: 100), size: Size(width: 60, height: 24))
        let hits = SelectionMath.marqueeHitItems(
            rect: Rect(x: 90, y: 90, width: 40, height: 40),
            items: ["t1": item], order: ["t1"])
        #expect(hits == ["t1"])
    }
}
