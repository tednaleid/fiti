// ABOUTME: Tests for the SeededIdGenerator test double.

import Testing

@Suite("SeededIdGenerator")
struct IdGeneratorTests {
    @Test("produces deterministic monotonic ids")
    func deterministic() {
        let gen = SeededIdGenerator(prefix: "s")
        #expect(gen.newItemId() == "s-1")
        #expect(gen.newItemId() == "s-2")
        #expect(gen.newItemId() == "s-3")
    }

    @Test("two generators with same prefix produce same sequence")
    func reproducible() {
        let a = SeededIdGenerator(prefix: "s")
        let b = SeededIdGenerator(prefix: "s")
        #expect(a.newItemId() == b.newItemId())
        #expect(a.newItemId() == b.newItemId())
    }
}
