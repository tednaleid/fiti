// ABOUTME: Tests PresetAxis — the preset list, display formatting, and exact-match index.
// ABOUTME: Pure data + pure functions; no AppKit dependency.

import Testing

@Suite("PresetAxis")
struct PresetAxisTests {
    @Test("size axis exposes the ten ValuePresets.sizes values")
    func sizeValues() {
        #expect(PresetAxis.size.values == ValuePresets.sizes)
        #expect(PresetAxis.size.values.count == 10)
    }

    @Test("opacity axis exposes the ten ValuePresets.opacities values")
    func opacityValues() {
        #expect(PresetAxis.opacity.values == ValuePresets.opacities)
        #expect(PresetAxis.opacity.values.count == 10)
    }

    @Test("size displayString rounds to an integer (e.g. 14)")
    func sizeDisplayString() {
        #expect(PresetAxis.size.displayString(for: 14) == "14")
        #expect(PresetAxis.size.displayString(for: 6) == "6")
        #expect(PresetAxis.size.displayString(for: 100) == "100")
    }

    @Test("opacity displayString is a percent (e.g. 70%)")
    func opacityDisplayString() {
        #expect(PresetAxis.opacity.displayString(for: 0.7) == "70%")
        #expect(PresetAxis.opacity.displayString(for: 0.1) == "10%")
        #expect(PresetAxis.opacity.displayString(for: 1.0) == "100%")
    }

    @Test("selectedIndex returns the index for an exact preset match")
    func selectedIndexExact() {
        #expect(PresetAxis.size.selectedIndex(for: 2) == 0)
        #expect(PresetAxis.size.selectedIndex(for: 14) == 4)
        #expect(PresetAxis.size.selectedIndex(for: 100) == 9)
        #expect(PresetAxis.opacity.selectedIndex(for: 0.1) == 0)
        #expect(PresetAxis.opacity.selectedIndex(for: 0.7) == 6)
        #expect(PresetAxis.opacity.selectedIndex(for: 1.0) == 9)
    }

    @Test("selectedIndex returns nil for off-preset values")
    func selectedIndexOffPreset() {
        #expect(PresetAxis.size.selectedIndex(for: 7) == nil)
        #expect(PresetAxis.size.selectedIndex(for: 50) == nil)
        #expect(PresetAxis.opacity.selectedIndex(for: 0.75) == nil)
        #expect(PresetAxis.opacity.selectedIndex(for: 0.05) == nil)
    }
}
