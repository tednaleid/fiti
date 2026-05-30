// ABOUTME: Tests PresetPopover — borderless panel that shows preset cells for the size
// ABOUTME: or opacity axis. Covers lifecycle, cell building, selection, and dismissal.

import AppKit
import Testing

@Suite("PresetPopover")
@MainActor
struct PresetPopoverTests {
    private func anchor() -> NSRect {
        // A point in screen space that is on a real screen — using NSScreen.main's frame
        // origin avoids screen-edge clamping concerns. Size matches MarkPreview.
        let origin = NSScreen.main?.frame.origin ?? .zero
        return NSRect(x: origin.x + 100, y: origin.y + 100, width: 60, height: 140)
    }

    @Test("isOpen is false before open")
    func notOpenInitially() {
        let pop = PresetPopover()
        #expect(pop.isOpen == false)
        #expect(pop.currentAxis == nil)
    }

    @Test("open(size, ...) sets isOpen and currentAxis = .size")
    func openSetsAxis() {
        let pop = PresetPopover()
        pop.open(axis: .size, currentValue: 6,
                 color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 6, tool: .pen, outlineOn: false,
                 anchor: anchor(), edge: .maxX, onPick: { _ in })
        #expect(pop.isOpen == true)
        #expect(pop.currentAxis == .size)
        pop.close()
    }

    @Test("close clears isOpen and currentAxis")
    func closeClears() {
        let pop = PresetPopover()
        pop.open(axis: .opacity, currentValue: 0.7,
                 color: RGBA(r: 0, g: 1, b: 0, a: 0.7), width: 14, tool: .pen, outlineOn: true,
                 anchor: anchor(), edge: .maxX, onPick: { _ in })
        pop.close()
        #expect(pop.isOpen == false)
        #expect(pop.currentAxis == nil)
    }

    @Test("close is idempotent — calling twice does not crash")
    func closeIdempotent() {
        let pop = PresetPopover()
        pop.close()
        pop.close()
        #expect(pop.isOpen == false)
    }
}
