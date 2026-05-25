// ABOUTME: Tests resolveOutline: nil when disabled, white/black halo by luminance,
// ABOUTME: alpha preserved, width = sizeBasis * widthFactor, threshold boundary.

import Testing

@Suite("resolveOutline")
struct OutlineStyleTests {
    @Test("disabled returns nil")
    func disabledNil() {
        #expect(resolveOutline(enabled: false, color: RGBA(r: 0.5, g: 0.1, b: 0.1, a: 1),
                               sizeBasis: 40, widthFactor: 0.5) == nil)
    }

    @Test("dark color yields a white halo")
    func darkToWhite() {
        let o = resolveOutline(enabled: true, color: RGBA(r: 0.1, g: 0.1, b: 0.1, a: 1),
                               sizeBasis: 40, widthFactor: 0.5)
        #expect(o?.haloColor == RGBA(r: 1, g: 1, b: 1, a: 1))
    }

    @Test("light color yields a black halo")
    func lightToBlack() {
        let o = resolveOutline(enabled: true, color: RGBA(r: 0.95, g: 0.95, b: 0.95, a: 1),
                               sizeBasis: 40, widthFactor: 0.5)
        #expect(o?.haloColor == RGBA(r: 0, g: 0, b: 0, a: 1))
    }

    @Test("halo alpha equals the mark alpha")
    func alphaPreserved() {
        let o = resolveOutline(enabled: true, color: RGBA(r: 0.1, g: 0.1, b: 0.1, a: 0.5),
                               sizeBasis: 40, widthFactor: 0.5)
        #expect(o?.haloColor.a == 0.5)
    }

    @Test("halo width is sizeBasis * widthFactor")
    func widthMath() {
        let o = resolveOutline(enabled: true, color: RGBA(r: 0.1, g: 0.1, b: 0.1, a: 1),
                               sizeBasis: 40, widthFactor: 0.5)
        #expect(o?.haloWidth == 20)
    }

    @Test("luminance threshold splits white vs black in both directions")
    func thresholdBoundary() {
        let justDark = resolveOutline(enabled: true, color: RGBA(r: 0.49, g: 0.49, b: 0.49, a: 1),
                                      sizeBasis: 1, widthFactor: 1)
        let justLight = resolveOutline(enabled: true, color: RGBA(r: 0.51, g: 0.51, b: 0.51, a: 1),
                                       sizeBasis: 1, widthFactor: 1)
        #expect(justDark?.haloColor == RGBA(r: 1, g: 1, b: 1, a: 1))
        #expect(justLight?.haloColor == RGBA(r: 0, g: 0, b: 0, a: 1))
    }
}
