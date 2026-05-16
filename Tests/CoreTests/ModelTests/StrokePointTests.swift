// ABOUTME: Tests for the StrokePoint — (x, y, pressure) triple.

import Testing

@Suite("StrokePoint")
struct StrokePointTests {
    @Test("constructs with x, y, pressure")
    func construct() {
        let p = StrokePoint(x: 10, y: 20, pressure: 0.5)
        #expect(p.x == 10)
        #expect(p.y == 20)
        #expect(p.pressure == 0.5)
    }

    @Test("default pressure is 0.5 (mouse default)")
    func defaultPressure() {
        let p = StrokePoint(x: 0, y: 0)
        #expect(p.pressure == 0.5)
    }
}
