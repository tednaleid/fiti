// ABOUTME: Tests for KeyCommandRegistry — exhaustive lookup table for every
// ABOUTME: bound key plus reserved-slot assertions for future tools.

import Testing

@Suite("KeyCommandRegistry")
struct KeyCommandRegistryTests {
    private func lookup(_ ch: Character, shift: Bool = false) -> KeyCommand? {
        KeyCommandRegistry.command(for: KeyBinding(character: ch, shift: shift))
    }

    @Test("digits 1..8 resolve to pickColor 0..7")
    func digitsPickColor() {
        for i in 0..<8 {
            let ch = Character("\(i + 1)")
            #expect(lookup(ch) == .pickColor(i))
        }
    }

    @Test("'s' resolves to bumpSize(.up); shift+'s' resolves to bumpSize(.down)")
    func sizeBindings() {
        #expect(lookup("s") == .bumpSize(.up))
        #expect(lookup("s", shift: true) == .bumpSize(.down))
    }

    @Test("'o' resolves to bumpOpacity(.up); shift+'o' resolves to bumpOpacity(.down)")
    func opacityBindings() {
        #expect(lookup("o") == .bumpOpacity(.up))
        #expect(lookup("o", shift: true) == .bumpOpacity(.down))
    }

    @Test("'h' toggles hide; 'f' toggles auto-fade; 'c' clears")
    func toggleAndClearBindings() {
        #expect(lookup("h") == .toggleHide)
        #expect(lookup("f") == .toggleAutoFade)
        #expect(lookup("c") == .clear)
    }

    @Test("reserved slots (Space, 'e', 'p') resolve to nil")
    func reservedSlotsAreUnbound() {
        #expect(lookup(" ") == nil)
        #expect(lookup("e") == nil)
        #expect(lookup("p") == nil)
    }

    @Test("uppercase variants without shift are not silently mapped")
    func uppercaseRequiresShift() {
        // The registry uses lowercase + shift convention. Looking up a literal
        // uppercase character returns nil — callers should normalize via
        // charactersIgnoringModifiers first.
        #expect(lookup("S") == nil)
        #expect(lookup("O") == nil)
    }

    @Test("registry has exactly the documented number of bindings")
    func bindingCount() {
        // 8 colors + 4 size/opacity (s/S/o/O) + 3 toggles (h/f/c) = 15
        #expect(KeyCommandRegistry.bindings.count == 15)
    }
}
