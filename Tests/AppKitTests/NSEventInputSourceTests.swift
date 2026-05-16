// ABOUTME: Synthesizes NSEvents and asserts handleKeyDown invokes the right
// ABOUTME: callbacks (Cmd+Opt+Z → activate, Esc → deactivate, Cmd+K → clear).

import AppKit
import Foundation
import Testing

@Suite("NSEventInputSource key handling")
struct NSEventInputSourceTests {
    @Test("Cmd+Opt+Z triggers onActivate")
    func cmdOptZ() throws {
        let view = CanvasInputView(frame: .zero)
        let input = NSEventInputSource(view: view)
        var activated = false
        input.onActivate = { activated = true }
        let event = try #require(makeKeyDown(chars: "z", flags: [.command, .option]))
        let consumed = input.handleKeyDown(event)
        #expect(activated)
        #expect(consumed)
    }

    @Test("Esc triggers onDeactivate")
    func esc() throws {
        let view = CanvasInputView(frame: .zero)
        let input = NSEventInputSource(view: view)
        var deactivated = false
        input.onDeactivate = { deactivated = true }
        let event = try #require(makeKeyDown(chars: "", flags: [], keyCode: 53))
        let consumed = input.handleKeyDown(event)
        #expect(deactivated)
        #expect(consumed)
    }

    @Test("Cmd+K triggers onClear")
    func cmdK() throws {
        let view = CanvasInputView(frame: .zero)
        let input = NSEventInputSource(view: view)
        var cleared = false
        input.onClear = { cleared = true }
        let event = try #require(makeKeyDown(chars: "k", flags: [.command]))
        let consumed = input.handleKeyDown(event)
        #expect(cleared)
        #expect(consumed)
    }

    @Test("unrelated key passes through")
    func passthrough() throws {
        let view = CanvasInputView(frame: .zero)
        let input = NSEventInputSource(view: view)
        let event = try #require(makeKeyDown(chars: "a", flags: []))
        let consumed = input.handleKeyDown(event)
        #expect(consumed == false)
    }

    private func makeKeyDown(chars: String, flags: NSEvent.ModifierFlags, keyCode: UInt16 = 0) -> NSEvent? {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                         timestamp: 0, windowNumber: 0, context: nil,
                         characters: chars, charactersIgnoringModifiers: chars,
                         isARepeat: false, keyCode: keyCode)
    }
}
