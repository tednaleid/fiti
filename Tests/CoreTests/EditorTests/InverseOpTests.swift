// ABOUTME: Tests for InverseOp + StrokeRestoreEntry — the data records
// ABOUTME: that describe how to reverse a doc mutation.

import Testing

@Suite("InverseOp")
struct InverseOpTests {
    @Test("StrokeRestoreEntry is equatable")
    func restoreEquatable() {
        let s = Stroke(id: "a", color: RGBA(r: 0, g: 0, b: 0, a: 1), width: 1, transform: .identity, points: [], pointerType: .mouse, pressureEnabled: false, createdAt: 0)
        #expect(StrokeRestoreEntry(snapshot: s, atIndex: 0) == StrokeRestoreEntry(snapshot: s, atIndex: 0))
        #expect(StrokeRestoreEntry(snapshot: s, atIndex: 0) != StrokeRestoreEntry(snapshot: s, atIndex: 1))
    }

    @Test("deleteStroke / restoreStroke / deleteStrokes / restoreStrokes are equatable")
    func opEquatable() {
        let s = Stroke(id: "a", color: RGBA(r: 0, g: 0, b: 0, a: 1), width: 1, transform: .identity, points: [], pointerType: .mouse, pressureEnabled: false, createdAt: 0)
        #expect(InverseOp.deleteStroke("a") == .deleteStroke("a"))
        #expect(InverseOp.restoreStroke(snapshot: s, atIndex: 0) == .restoreStroke(snapshot: s, atIndex: 0))
        #expect(InverseOp.deleteStrokes(["a"]) == .deleteStrokes(["a"]))
        let entry = StrokeRestoreEntry(snapshot: s, atIndex: 0)
        #expect(InverseOp.restoreStrokes(entries: [entry]) == .restoreStrokes(entries: [entry]))
    }
}
