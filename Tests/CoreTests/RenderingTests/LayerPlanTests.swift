// ABOUTME: Tests the pure overlap-aware grouping keyed on (hue, alpha).
// ABOUTME: Boxes are injected so cases are exact and independent of geometry.

import Testing

@Suite("LayerPlan.compute")
struct LayerPlanTests {
    private let red = RGBA(r: 1, g: 0, b: 0, a: 0.5)
    private let blue = RGBA(r: 0, g: 0, b: 1, a: 0.5)

    private func mark(_ id: String, _ color: RGBA) -> CanvasItem {
        .stroke(Stroke(id: id, color: color, width: 1, transform: .identity,
                       points: [], pointerType: .mouse, pressureEnabled: false, createdAt: 0))
    }
    private func layerIds(_ items: [CanvasItem], _ boxes: [ItemId: Rect]) -> [[ItemId]] {
        LayerPlan.compute(items: items, aabb: { boxes[$0.id] }).map { $0.items.map(\.id) }
    }

    @Test("same key marks merge into one layer")
    func sameKeyMerge() {
        let items = [mark("r1", red), mark("r2", red)]
        let boxes: [ItemId: Rect] = ["r1": Rect(x: 0, y: 0, width: 10, height: 10),
                                     "r2": Rect(x: 5, y: 5, width: 10, height: 10)]
        #expect(layerIds(items, boxes) == [["r1", "r2"]])
    }

    @Test("same key split by a NON-overlapping other key still merges")
    func splitByNonOverlappingMerges() {
        let items = [mark("r1", red), mark("b", blue), mark("r3", red)]
        let boxes: [ItemId: Rect] = [
            "r1": Rect(x: 0, y: 0, width: 20, height: 20),
            "b": Rect(x: 100, y: 0, width: 10, height: 20),
            "r3": Rect(x: 5, y: 5, width: 20, height: 20)
        ]
        let layers = layerIds(items, boxes)
        #expect(layers.first { $0.contains("r1") } == ["r1", "r3"])
        #expect(layers.contains(["b"]))
        #expect(layers.count == 2)
    }

    @Test("a different key overlapping both same-key marks forces a split")
    func genuineConflictSplits() {
        let items = [mark("r1", red), mark("b", blue), mark("r2", red)]
        let box = Rect(x: 0, y: 0, width: 30, height: 30)
        let boxes: [ItemId: Rect] = ["r1": box, "b": box, "r2": box]
        #expect(layerIds(items, boxes) == [["r1"], ["b"], ["r2"]])
    }

    @Test("same hue but different alpha are different keys: overlapping splits")
    func differentAlphaSameHueSplits() {
        let r70 = RGBA(r: 1, g: 0, b: 0, a: 0.7)
        let r30 = RGBA(r: 1, g: 0, b: 0, a: 0.3)
        let items = [mark("a", r70), mark("b", r30)]
        let box = Rect(x: 0, y: 0, width: 10, height: 10)
        #expect(layerIds(items, ["a": box, "b": box]) == [["a"], ["b"]])
    }

    @Test("same hue but different alpha, non-overlapping: each its own layer, order kept")
    func differentAlphaSameHueNonOverlapping() {
        let r70 = RGBA(r: 1, g: 0, b: 0, a: 0.7)
        let r30 = RGBA(r: 1, g: 0, b: 0, a: 0.3)
        let items = [mark("a", r70), mark("b", r30)]
        let boxes: [ItemId: Rect] = ["a": Rect(x: 0, y: 0, width: 10, height: 10),
                                     "b": Rect(x: 50, y: 0, width: 10, height: 10)]
        #expect(layerIds(items, boxes) == [["a"], ["b"]])
    }

    @Test("nil AABB never constrains and same-key can merge")
    func nilBoxNeverConstrains() {
        let items = [mark("r1", red), mark("b", blue), mark("r2", red)]
        #expect(layerIds(items, [:]) == [["r1", "r2"], ["b"]])
    }

    @Test("a single mark yields one layer of one item")
    func singleItem() {
        #expect(layerIds([mark("only", red)], ["only": Rect(x: 0, y: 0, width: 5, height: 5)]) == [["only"]])
    }
}
