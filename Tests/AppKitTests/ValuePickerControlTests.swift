// ABOUTME: Tests ValuePickerControl — first-mouse, edge-zone hit-testing, preset
// ABOUTME: stepping, display strings, and crash-free rendering across tools/outline.

import AppKit
import Testing

@Suite("ValuePickerControl")
@MainActor
struct ValuePickerControlTests {
    @Test("accepts first mouse so clicks land in the floating panel")
    func firstMouse() {
        let pc = ValuePickerControl(kind: .size, presets: ValuePresets.sizes, value: 6)
        #expect(pc.testOnly_acceptsFirstMouse() == true)
    }

    @Test("x position maps to decrement / menu / increment zones")
    func zones() {
        let pc = ValuePickerControl(kind: .size, presets: ValuePresets.sizes, value: 6)
        // init frame is 64 wide, edge zones 15pt each side.
        #expect(pc.testOnly_zone(forX: 5) == .decrement)
        #expect(pc.testOnly_zone(forX: 32) == .menu)
        #expect(pc.testOnly_zone(forX: 60) == .increment)
    }

    @Test("decrement / increment step to adjacent presets and fire onPick")
    func stepping() {
        let pc = ValuePickerControl(kind: .size, presets: ValuePresets.sizes, value: 14)
        var picked: [Double] = []
        pc.onPick = { picked.append($0) }
        pc.testOnly_step(.increment)   // 14 -> 20
        #expect(pc.value == 20)
        pc.testOnly_step(.decrement)   // 20 -> 14
        #expect(pc.value == 14)
        #expect(picked == [20, 14])
    }

    @Test("display strings: integer for size, percent for opacity")
    func display() {
        #expect(ValuePickerControl(kind: .size, presets: ValuePresets.sizes, value: 6)
                    .testOnly_displayString == "6")
        #expect(ValuePickerControl(kind: .opacity, presets: ValuePresets.opacities, value: 0.5)
                    .testOnly_displayString == "50%")
    }

    @Test("selecting a preset cell fires onPick with that value")
    func pick() {
        let pc = ValuePickerControl(kind: .size, presets: ValuePresets.sizes, value: 6)
        var picked: Double?
        pc.onPick = { picked = $0 }
        pc.testOnly_selectPreset(at: 4)   // ValuePresets.sizes[4] == 14
        #expect(picked == 14)
    }

    @Test("renders for every tool and outline state without crashing")
    func renderSmoke() {
        let pc = ValuePickerControl(kind: .size, presets: ValuePresets.sizes, value: 70)
        pc.color = RGBA(r: 1, g: 0, b: 0, a: 1)
        for tool in [Tool.pen, .arrow, .text, .selection] {
            for on in [false, true] {
                pc.currentTool = tool
                pc.outlineOn = on
                if let rep = pc.bitmapImageRepForCachingDisplay(in: pc.bounds) {
                    pc.cacheDisplay(in: pc.bounds, to: rep)
                    #expect(rep.pixelsWide > 0)
                } else {
                    Issue.record("no bitmap rep for \(tool) outline=\(on)")
                }
            }
        }
        let op = ValuePickerControl(kind: .opacity, presets: ValuePresets.opacities, value: 0.4)
        op.color = RGBA(r: 0, g: 0.4, b: 1, a: 1)
        if let rep = op.bitmapImageRepForCachingDisplay(in: op.bounds) {
            op.cacheDisplay(in: op.bounds, to: rep)
            #expect(rep.pixelsWide > 0)
        }
    }
}
