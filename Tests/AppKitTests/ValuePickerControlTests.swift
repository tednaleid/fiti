// ABOUTME: Tests ValuePickerControl — display string, tool-aware size preview,
// ABOUTME: and that selecting a preset cell fires onPick with that value.

import AppKit
import Testing

@Suite("ValuePickerControl")
@MainActor
struct ValuePickerControlTests {
    @Test("size control shows the integer width")
    func sizeDisplay() {
        let pc = ValuePickerControl(kind: .size, presets: ValuePresets.sizes, value: 6)
        #expect(pc.testOnly_displayString == "6")
    }

    @Test("opacity control shows the percent")
    func opacityDisplay() {
        let pc = ValuePickerControl(kind: .opacity, presets: ValuePresets.opacities, value: 0.5)
        #expect(pc.testOnly_displayString == "50%")
    }

    @Test("selecting a preset cell fires onPick with that preset value")
    func pickFires() {
        let pc = ValuePickerControl(kind: .size, presets: ValuePresets.sizes, value: 6)
        var picked: Double?
        pc.onPick = { picked = $0 }
        pc.testOnly_selectPreset(at: 4)   // ValuePresets.sizes[4] == 14
        #expect(picked == 14)
    }

    @Test("the size preview renders for each tool without crashing")
    func toolAwarePreview() {
        let pc = ValuePickerControl(kind: .size, presets: ValuePresets.sizes, value: 20)
        pc.color = RGBA(r: 1, g: 0, b: 0, a: 1)
        for tool in [Tool.pen, .arrow, .text, .selection] {
            pc.currentTool = tool
            #expect(pc.testOnly_previewImage().size.width > 0)
        }
    }
}
