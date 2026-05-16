// ABOUTME: Tests for the RGBA color model — sRGB, 0...1 components.
// ABOUTME: Phase 2.1 of the POC plan.

import Testing

@Suite("RGBA")
struct RGBATests {
    @Test("constructs with rgba components")
    func construct() {
        let c = RGBA(r: 1, g: 0.5, b: 0, a: 1)
        #expect(c.r == 1)
        #expect(c.g == 0.5)
        #expect(c.b == 0)
        #expect(c.a == 1)
    }

    @Test("is equatable")
    func equatable() {
        #expect(RGBA(r: 1, g: 0, b: 0, a: 1) == RGBA(r: 1, g: 0, b: 0, a: 1))
        #expect(RGBA(r: 1, g: 0, b: 0, a: 1) != RGBA(r: 0, g: 1, b: 0, a: 1))
    }
}
