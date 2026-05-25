// ABOUTME: Tests Rect.contains(Point) — the overload currentCursor uses to test
// ABOUTME: the toolbar region against the (Point-typed) hover location.

import Testing

@Suite("Rect.contains(Point)")
struct RectContainsPointTests {
    @Test("inside, on the edge, and outside")
    func contains() {
        let r = Rect(x: 0, y: 0, width: 10, height: 20)
        #expect(r.contains(Point(x: 5, y: 5)) == true)
        #expect(r.contains(Point(x: 0, y: 0)) == true)   // edge is inside
        #expect(r.contains(Point(x: 10, y: 20)) == true) // far edge inside
        #expect(r.contains(Point(x: 11, y: 5)) == false)
        #expect(r.contains(Point(x: 5, y: -1)) == false)
    }
}
