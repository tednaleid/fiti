// ABOUTME: Tests for InverseOp + ItemRestoreEntry — the data records
// ABOUTME: that describe how to reverse a doc mutation.

import Testing

@Suite("InverseOp")
struct InverseOpTests {
    @Test("ItemRestoreEntry is equatable")
    func restoreEquatable() {
        let s = Stroke(id: "a", color: RGBA(r: 0, g: 0, b: 0, a: 1), width: 1, transform: .identity, points: [], pointerType: .mouse, pressureEnabled: false, createdAt: 0)
        let item = CanvasItem.stroke(s)
        #expect(ItemRestoreEntry(snapshot: item, atIndex: 0) == ItemRestoreEntry(snapshot: item, atIndex: 0))
        #expect(ItemRestoreEntry(snapshot: item, atIndex: 0) != ItemRestoreEntry(snapshot: item, atIndex: 1))
    }

    @Test("deleteItem / restoreItem / deleteItems / restoreItems are equatable")
    func opEquatable() {
        let s = Stroke(id: "a", color: RGBA(r: 0, g: 0, b: 0, a: 1), width: 1, transform: .identity, points: [], pointerType: .mouse, pressureEnabled: false, createdAt: 0)
        let item = CanvasItem.stroke(s)
        #expect(InverseOp.deleteItem("a") == .deleteItem("a"))
        #expect(InverseOp.restoreItem(snapshot: item, atIndex: 0) == .restoreItem(snapshot: item, atIndex: 0))
        #expect(InverseOp.deleteItems(["a"]) == .deleteItems(["a"]))
        let entry = ItemRestoreEntry(snapshot: item, atIndex: 0)
        #expect(InverseOp.restoreItems(entries: [entry]) == .restoreItems(entries: [entry]))
    }
}
