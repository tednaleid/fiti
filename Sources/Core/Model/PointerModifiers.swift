// ABOUTME: Modifier-key state carried alongside a pointer event so Core sees
// ABOUTME: Cmd / Shift without importing AppKit. AppKit's NSEventInputSource
// ABOUTME: extracts event.modifierFlags into one of these on every dispatch.

import Foundation

public struct PointerModifiers: Equatable, Hashable, Sendable {
    public var command: Bool
    public var shift: Bool

    public init(command: Bool = false, shift: Bool = false) {
        self.command = command
        self.shift = shift
    }

    public static let none = PointerModifiers()
}
