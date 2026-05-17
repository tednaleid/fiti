// ABOUTME: Synthesizes NSEvents and asserts dispatchKey invokes the right
// ABOUTME: callbacks. Tests the pure dispatch helper, not the monitor wiring.

import AppKit
import Foundation
import Testing

@Suite("dispatchKey")
struct NSEventInputSourceTests {
    @Test("Ctrl+G triggers onToggle")
    func ctrlG() throws {
        var toggled = false
        let event = try #require(makeKeyDown(chars: "g", flags: [.control]))
        let consumed = dispatchKey(event,
                                   onToggle: { toggled = true },
                                   onClear: nil,
                                   onDeactivate: nil,
                                   onUndo: nil,
                                   onRedo: nil)
        #expect(toggled)
        #expect(consumed)
    }

    @Test("Esc triggers onDeactivate")
    func esc() throws {
        var deactivated = false
        let event = try #require(makeKeyDown(chars: "", flags: [], keyCode: 53))
        let consumed = dispatchKey(event,
                                   onToggle: nil,
                                   onClear: nil,
                                   onDeactivate: { deactivated = true },
                                   onUndo: nil,
                                   onRedo: nil)
        #expect(deactivated)
        #expect(consumed)
    }

    @Test("Cmd+K triggers onClear")
    func cmdK() throws {
        var cleared = false
        let event = try #require(makeKeyDown(chars: "k", flags: [.command]))
        let consumed = dispatchKey(event,
                                   onToggle: nil,
                                   onClear: { cleared = true },
                                   onDeactivate: nil,
                                   onUndo: nil,
                                   onRedo: nil)
        #expect(cleared)
        #expect(consumed)
    }

    @Test("Cmd+Z triggers onUndo")
    func cmdZ() throws {
        var undone = false
        let event = try #require(makeKeyDown(chars: "z", flags: [.command]))
        let consumed = dispatchKey(event,
                                   onToggle: nil,
                                   onClear: nil,
                                   onDeactivate: nil,
                                   onUndo: { undone = true },
                                   onRedo: nil)
        #expect(undone)
        #expect(consumed)
    }

    @Test("Cmd+Shift+Z triggers onRedo (not onUndo)")
    func cmdShiftZ() throws {
        var undone = false
        var redone = false
        // Real Shift+Z events arrive with charactersIgnoringModifiers = "Z",
        // not "z" — Shift affects the character even though Cmd/Option don't.
        let event = try #require(makeKeyDown(chars: "Z", flags: [.command, .shift]))
        let consumed = dispatchKey(event,
                                   onToggle: nil,
                                   onClear: nil,
                                   onDeactivate: nil,
                                   onUndo: { undone = true },
                                   onRedo: { redone = true })
        #expect(redone)
        #expect(undone == false)
        #expect(consumed)
    }

    @Test("bare G passes through (no Ctrl)")
    func bareG() throws {
        var toggled = false
        let event = try #require(makeKeyDown(chars: "g", flags: []))
        let consumed = dispatchKey(event,
                                   onToggle: { toggled = true },
                                   onClear: nil,
                                   onDeactivate: nil,
                                   onUndo: nil,
                                   onRedo: nil)
        #expect(toggled == false)
        #expect(consumed == false)
    }

    @Test("unrelated key passes through")
    func passthrough() throws {
        let event = try #require(makeKeyDown(chars: "a", flags: []))
        let consumed = dispatchKey(event,
                                   onToggle: nil,
                                   onClear: nil,
                                   onDeactivate: nil,
                                   onUndo: nil,
                                   onRedo: nil)
        #expect(consumed == false)
    }

    private func makeKeyDown(chars: String, flags: NSEvent.ModifierFlags, keyCode: UInt16 = 0) -> NSEvent? {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                         timestamp: 0, windowNumber: 0, context: nil,
                         characters: chars, charactersIgnoringModifiers: chars,
                         isARepeat: false, keyCode: keyCode)
    }
}
