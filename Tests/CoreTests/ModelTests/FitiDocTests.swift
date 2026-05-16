// ABOUTME: Tests for FitiDoc — the keyed-map + ordered-list document shape.

import Testing

@Suite("FitiDoc")
struct FitiDocTests {
    @Test("empty has no strokes")
    func empty() {
        let doc = FitiDoc.empty
        #expect(doc.strokes.isEmpty)
        #expect(doc.strokeOrder.isEmpty)
    }

    @Test("ordering is independent of map iteration")
    func order() {
        var doc = FitiDoc.empty
        let s1 = Stroke(id: "a", color: RGBA(r: 0, g: 0, b: 0, a: 1), width: 1, transform: .identity, points: [], pointerType: .mouse, pressureEnabled: false, createdAt: 0)
        let s2 = Stroke(id: "b", color: RGBA(r: 0, g: 0, b: 0, a: 1), width: 1, transform: .identity, points: [], pointerType: .mouse, pressureEnabled: false, createdAt: 0)
        doc.strokes["a"] = s1
        doc.strokes["b"] = s2
        doc.strokeOrder = ["b", "a"]
        #expect(doc.strokeOrder == ["b", "a"])
    }
}
