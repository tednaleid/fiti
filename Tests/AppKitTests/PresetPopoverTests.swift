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

    @Test("open builds 10 cells for the size axis")
    func tenCellsForSize() {
        let pop = PresetPopover()
        pop.open(axis: .size, currentValue: 14,
                 color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 14, tool: .pen, outlineOn: false,
                 anchor: anchor(), edge: .maxX, onPick: { _ in })
        #expect(pop.testOnly_cellCount == 10)
        pop.close()
    }

    @Test("open builds 10 cells for the opacity axis")
    func tenCellsForOpacity() {
        let pop = PresetPopover()
        pop.open(axis: .opacity, currentValue: 0.7,
                 color: RGBA(r: 0, g: 0, b: 1, a: 0.7), width: 14, tool: .pen, outlineOn: false,
                 anchor: anchor(), edge: .maxX, onPick: { _ in })
        #expect(pop.testOnly_cellCount == 10)
        pop.close()
    }

    @Test("the cell at the matching preset index has the active background")
    func matchingCellHighlighted() {
        let pop = PresetPopover()
        // Size 14 → preset index 4 (ValuePresets.sizes is [2,4,6,9,14,...]).
        pop.open(axis: .size, currentValue: 14,
                 color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 14, tool: .pen, outlineOn: false,
                 anchor: anchor(), edge: .maxX, onPick: { _ in })
        #expect(pop.testOnly_selectedCellIndex == 4)
        pop.close()
    }

    @Test("off-preset currentValue leaves no cell highlighted")
    func offPresetNoHighlight() {
        let pop = PresetPopover()
        pop.open(axis: .size, currentValue: 7,  // not in ValuePresets.sizes
                 color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 7, tool: .pen, outlineOn: false,
                 anchor: anchor(), edge: .maxX, onPick: { _ in })
        #expect(pop.testOnly_selectedCellIndex == nil)
        pop.close()
    }

    @Test("clicking cell N fires onPick with axis.values[N] and closes the popover")
    func cellClickPicksAndCloses() {
        let pop = PresetPopover()
        var picked: [Double] = []
        pop.open(axis: .size, currentValue: 14,
                 color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 14, tool: .pen, outlineOn: false,
                 anchor: anchor(), edge: .maxX, onPick: { picked.append($0) })
        pop.testOnly_clickCell(at: 6)  // ValuePresets.sizes[6] == 30
        #expect(picked == [30])
        #expect(pop.isOpen == false)
    }

    @Test("clicking an opacity cell fires onPick with the matching opacity preset")
    func opacityCellClick() {
        let pop = PresetPopover()
        var picked: [Double] = []
        pop.open(axis: .opacity, currentValue: 0.5,
                 color: RGBA(r: 1, g: 0, b: 0, a: 0.5), width: 14, tool: .pen, outlineOn: false,
                 anchor: anchor(), edge: .maxX, onPick: { picked.append($0) })
        pop.testOnly_clickCell(at: 9)  // 1.0
        #expect(picked.count == 1)
        #expect(abs(picked[0] - 1.0) < 1e-6)
    }

    @Test("delivering an ESC keyDown to the local monitor closes the popover")
    func escClosesPopover() {
        let pop = PresetPopover()
        pop.open(axis: .size, currentValue: 14,
                 color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 14, tool: .pen, outlineOn: false,
                 anchor: anchor(), edge: .maxX, onPick: { _ in })
        let escEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                        timestamp: 0, windowNumber: 0, context: nil,
                                        characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}",
                                        isARepeat: false, keyCode: 0x35)!
        let consumed = pop.testOnly_handleKey(escEvent)
        #expect(consumed)
        #expect(pop.isOpen == false)
    }

    @Test("a non-ESC keyDown is not swallowed and does not close the popover")
    func nonEscIgnored() {
        let pop = PresetPopover()
        pop.open(axis: .size, currentValue: 14,
                 color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 14, tool: .pen, outlineOn: false,
                 anchor: anchor(), edge: .maxX, onPick: { _ in })
        let aEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                      timestamp: 0, windowNumber: 0, context: nil,
                                      characters: "a", charactersIgnoringModifiers: "a",
                                      isARepeat: false, keyCode: 0x00)!
        let consumed = pop.testOnly_handleKey(aEvent)
        #expect(consumed == false)
        #expect(pop.isOpen == true)
        pop.close()
    }

    @Test("NSApplication.didResignActiveNotification closes the popover")
    func resignActiveClosesPopover() {
        let pop = PresetPopover()
        pop.open(axis: .opacity, currentValue: 0.7,
                 color: RGBA(r: 0, g: 0, b: 1, a: 0.7), width: 14, tool: .pen, outlineOn: false,
                 anchor: anchor(), edge: .maxX, onPick: { _ in })
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification,
                                        object: NSApp)
        #expect(pop.isOpen == false)
    }

    @Test("opening installs three monitors/observers; closing removes them")
    func monitorsClean() {
        let pop = PresetPopover()
        #expect(pop.testOnly_monitorCount == 0)
        pop.open(axis: .size, currentValue: 14,
                 color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 14, tool: .pen, outlineOn: false,
                 anchor: anchor(), edge: .maxX, onPick: { _ in })
        #expect(pop.testOnly_monitorCount == 3)
        pop.close()
        #expect(pop.testOnly_monitorCount == 0)
    }

    @Test("open/close cycles do not accumulate monitors")
    func monitorsNoLeakAcrossCycles() {
        let pop = PresetPopover()
        for _ in 0..<5 {
            pop.open(axis: .size, currentValue: 14,
                     color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 14, tool: .pen, outlineOn: false,
                     anchor: anchor(), edge: .maxX, onPick: { _ in })
            pop.close()
        }
        #expect(pop.testOnly_monitorCount == 0)
    }

    @Test("refresh rebuilds cells with new style and moves the selection")
    func refreshUpdatesCells() {
        let pop = PresetPopover()
        pop.open(axis: .size, currentValue: 14,
                 color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 14, tool: .pen, outlineOn: false,
                 anchor: anchor(), edge: .maxX, onPick: { _ in })
        #expect(pop.testOnly_selectedCellIndex == 4)
        let redSnapshot = pop.snapshotPNG()

        // Same axis still open: change color to blue and move the value to 30 (index 6).
        pop.refresh(currentValue: 30, color: RGBA(r: 0, g: 0, b: 1, a: 1),
                    width: 30, tool: .pen, outlineOn: false)
        #expect(pop.isOpen)                        // refresh does not close
        #expect(pop.testOnly_cellCount == 10)
        #expect(pop.testOnly_selectedCellIndex == 6)   // highlight followed the new value
        #expect(pop.snapshotPNG() != redSnapshot)      // cells re-rendered in the new color

        pop.close()
    }

    @Test("refresh is a no-op when the popover is closed")
    func refreshClosedIsNoop() {
        let pop = PresetPopover()
        pop.refresh(currentValue: 30, color: RGBA(r: 0, g: 0, b: 1, a: 1),
                    width: 30, tool: .pen, outlineOn: false)
        #expect(pop.isOpen == false)
        #expect(pop.testOnly_cellCount == 0)
    }

    @Test("snapshotPNG returns nil when closed, PNG data when open")
    func snapshotPNG() {
        let pop = PresetPopover()
        #expect(pop.snapshotPNG() == nil)
        pop.open(axis: .size, currentValue: 14,
                 color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 14, tool: .pen, outlineOn: false,
                 anchor: anchor(), edge: .maxX, onPick: { _ in })
        let data = pop.snapshotPNG()
        #expect(data != nil)
        // PNG magic number: 89 50 4E 47.
        #expect(Array(data!.prefix(4)) == [0x89, 0x50, 0x4E, 0x47])
        pop.close()
        #expect(pop.snapshotPNG() == nil)
    }
}
