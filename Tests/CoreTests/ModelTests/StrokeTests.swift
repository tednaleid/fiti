// ABOUTME: Tests for the Stroke value type.

import Testing

@Suite("Stroke")
struct StrokeTests {
    @Test("constructs with all fields")
    func construct() {
        let s = Stroke(
            id: "stroke-1",
            color: RGBA(r: 1, g: 0, b: 0, a: 1),
            width: 4,
            transform: .identity,
            points: [StrokePoint(x: 0, y: 0)],
            pointerType: .mouse,
            pressureEnabled: false,
            createdAt: 100
        )
        #expect(s.id == "stroke-1")
        #expect(s.color.r == 1)
        #expect(s.width == 4)
        #expect(s.transform == .identity)
        #expect(s.points.count == 1)
        #expect(s.pointerType == .mouse)
        #expect(s.pressureEnabled == false)
        #expect(s.createdAt == 100)
    }

    @Test("appending points produces a new value (struct semantics)")
    func valueSemantics() {
        var a = Stroke(id: "s", color: RGBA(r: 0, g: 0, b: 0, a: 1), width: 1, transform: .identity, points: [], pointerType: .mouse, pressureEnabled: false, createdAt: 0)
        let b = a
        a.points.append(StrokePoint(x: 1, y: 1))
        #expect(a.points.count == 1)
        #expect(b.points.isEmpty)
    }
}
