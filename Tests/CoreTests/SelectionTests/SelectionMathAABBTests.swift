// ABOUTME: Verifies SelectionMath.worldAABB is public and bounds strokes.
// ABOUTME: The opacity LayerPlan passes this as its AABB function.

import Testing

@Suite("SelectionMath.worldAABB")
struct SelectionMathAABBTests {
    @Test("stroke world AABB encloses its transformed points")
    func strokeBounds() {
        let s = Stroke(id: "a", color: RGBA(r: 0, g: 0, b: 0, a: 1), width: 2,
                       transform: .identity,
                       points: [StrokePoint(x: 0, y: 0), StrokePoint(x: 10, y: 4)],
                       pointerType: .mouse, pressureEnabled: false, createdAt: 0)
        #expect(SelectionMath.worldAABB(of: .stroke(s)) == Rect(x: 0, y: 0, width: 10, height: 4))
    }
}
