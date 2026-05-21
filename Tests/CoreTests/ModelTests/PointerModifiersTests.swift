// ABOUTME: Tests for the PointerModifiers value type — the Core abstraction
// ABOUTME: that lets AppKit modifier flags cross into Core without leaking NSEvent.

import Testing

@Suite("PointerModifiers")
struct PointerModifiersTests {
    @Test("default factory has no modifiers set")
    func defaultEmpty() {
        let m = PointerModifiers()
        #expect(m.command == false)
        #expect(m.shift == false)
    }

    @Test(".none equals default")
    func noneEqualsDefault() {
        #expect(PointerModifiers.none == PointerModifiers())
    }

    @Test("equality compares both flags")
    func equality() {
        #expect(PointerModifiers(command: true) != PointerModifiers())
        #expect(PointerModifiers(shift: true) != PointerModifiers())
        #expect(PointerModifiers(command: true, shift: true) == PointerModifiers(command: true, shift: true))
    }
}
