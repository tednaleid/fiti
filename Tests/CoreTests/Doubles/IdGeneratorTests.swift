// ABOUTME: Tests for the SeededIdGenerator test double.

import Testing

@Suite("SeededIdGenerator")
struct IdGeneratorTests {
    @Test("produces deterministic monotonic ids")
    func deterministic() {
        let gen = SeededIdGenerator(prefix: "s")
        #expect(gen.newStrokeId() == "s-1")
        #expect(gen.newStrokeId() == "s-2")
        #expect(gen.newStrokeId() == "s-3")
    }

    @Test("two generators with same prefix produce same sequence")
    func reproducible() {
        let a = SeededIdGenerator(prefix: "s")
        let b = SeededIdGenerator(prefix: "s")
        #expect(a.newStrokeId() == b.newStrokeId())
        #expect(a.newStrokeId() == b.newStrokeId())
    }
}
