// ABOUTME: Synthesizes NSEvents and asserts dispatchKey invokes the right
// ABOUTME: callbacks. Tests the pure dispatch helper, not the monitor wiring.

import AppKit
import Foundation
import Testing

@Suite("dispatchKey")
struct NSEventInputSourceTests {
    @Test("Cmd+Opt+Z triggers onActivate")
    func cmdOptZ() throws {
        var activated = false
        let event = try #require(makeKeyDown(chars: "z", flags: [.command, .option]))
        let consumed = dispatchKey(event,
                                   onActivate: { activated = true },
                                   onClear: nil,
                                   onDeactivate: nil)
        #expect(activated)
        #expect(consumed)
    }

    @Test("Esc triggers onDeactivate")
    func esc() throws {
        var deactivated = false
        let event = try #require(makeKeyDown(chars: "", flags: [], keyCode: 53))
        let consumed = dispatchKey(event,
                                   onActivate: nil,
                                   onClear: nil,
                                   onDeactivate: { deactivated = true })
        #expect(deactivated)
        #expect(consumed)
    }

    @Test("Cmd+K triggers onClear")
    func cmdK() throws {
        var cleared = false
        let event = try #require(makeKeyDown(chars: "k", flags: [.command]))
        let consumed = dispatchKey(event,
                                   onActivate: nil,
                                   onClear: { cleared = true },
                                   onDeactivate: nil)
        #expect(cleared)
        #expect(consumed)
    }

    @Test("unrelated key passes through")
    func passthrough() throws {
        let event = try #require(makeKeyDown(chars: "a", flags: []))
        let consumed = dispatchKey(event,
                                   onActivate: nil,
                                   onClear: nil,
                                   onDeactivate: nil)
        #expect(consumed == false)
    }

    private func makeKeyDown(chars: String, flags: NSEvent.ModifierFlags, keyCode: UInt16 = 0) -> NSEvent? {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                         timestamp: 0, windowNumber: 0, context: nil,
                         characters: chars, charactersIgnoringModifiers: chars,
                         isARepeat: false, keyCode: keyCode)
    }
}
