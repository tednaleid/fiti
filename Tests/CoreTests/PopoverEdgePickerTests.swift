// ABOUTME: Tests PopoverEdgePicker — chooses .maxX or .minX from toolbar/screen midpoints.
// ABOUTME: Pure helper so we can verify edge-mirroring without a real window.

import Testing

@Suite("PopoverEdgePicker")
struct PopoverEdgePickerTests {
    @Test("toolbar in the left half returns .maxX (popover extends right)")
    func leftHalfReturnsMaxX() {
        // Screen midX 720, toolbar midX 100 (left side).
        #expect(PopoverEdgePicker.pick(toolbarMidX: 100, screenMidX: 720) == .maxX)
    }

    @Test("toolbar in the right half returns .minX (popover extends left)")
    func rightHalfReturnsMinX() {
        // Screen midX 720, toolbar midX 1400 (right side).
        #expect(PopoverEdgePicker.pick(toolbarMidX: 1400, screenMidX: 720) == .minX)
    }

    @Test("toolbar exactly at screen midpoint returns .minX (boundary picks right-edge layout)")
    func boundaryReturnsMinX() {
        #expect(PopoverEdgePicker.pick(toolbarMidX: 720, screenMidX: 720) == .minX)
    }
}
