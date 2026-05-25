// ABOUTME: Tests the size/opacity preset lists and next/previous/closest helpers
// ABOUTME: that back the toolbar pickers and the keyboard size/opacity shortcuts.

import Testing

@Suite("ValuePresets")
struct ValuePresetsTests {
    @Test("preset lists are the agreed values")
    func lists() {
        #expect(ValuePresets.sizes == [2, 4, 6, 9, 14, 20, 30, 45, 70, 100])
        #expect(ValuePresets.opacities == [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0])
    }

    @Test("nextPreset returns the first preset strictly greater than the value")
    func nextStepsUp() {
        #expect(nextPreset(after: 6, in: ValuePresets.sizes) == 9)   // on-preset
        #expect(nextPreset(after: 7, in: ValuePresets.sizes) == 9)   // off-preset
        #expect(nextPreset(after: 100, in: ValuePresets.sizes) == 100) // clamps at max
    }

    @Test("previousPreset returns the last preset strictly less than the value")
    func previousStepsDown() {
        #expect(previousPreset(before: 9, in: ValuePresets.sizes) == 6)  // on-preset
        #expect(previousPreset(before: 7, in: ValuePresets.sizes) == 6)  // off-preset
        #expect(previousPreset(before: 2, in: ValuePresets.sizes) == 2)  // clamps at min
    }

    @Test("opacity stepping lands on exact 10% increments")
    func opacityExactSteps() {
        #expect(nextPreset(after: 0.5, in: ValuePresets.opacities) == 0.6)
        #expect(previousPreset(before: 0.5, in: ValuePresets.opacities) == 0.4)
        #expect(nextPreset(after: 1.0, in: ValuePresets.opacities) == 1.0)
        #expect(previousPreset(before: 0.1, in: ValuePresets.opacities) == 0.1)
    }

    @Test("closestPresetIndex picks the nearest cell, ties to the lower index")
    func closest() {
        #expect(closestPresetIndex(to: 6, in: ValuePresets.sizes) == 2)
        #expect(closestPresetIndex(to: 7, in: ValuePresets.sizes) == 2)   // 7 closer to 6 than 9
        #expect(closestPresetIndex(to: 8, in: ValuePresets.sizes) == 3)   // 8 closer to 9
        #expect(closestPresetIndex(to: 0, in: []) == nil)
    }
}
