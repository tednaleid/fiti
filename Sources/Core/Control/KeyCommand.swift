// ABOUTME: Pure-Core key dispatch vocabulary. KeyCommand is the verb;
// ABOUTME: KeyBinding is the (character, shift) tuple; KeyCommandRegistry maps
// ABOUTME: between them and is the single source of truth for active-app shortcuts.

import Foundation

public enum KeyCommand: Equatable, Hashable, Sendable {
    case pickColor(Int)
    case bumpSize(Direction)
    case bumpOpacity(Direction)
    case toggleHide
    case toggleAutoFade
    case clear
    case selectTool(Tool)

    public enum Direction: Equatable, Hashable, Sendable {
        case up
        case down
    }
}

public struct KeyBinding: Hashable, Sendable {
    public let character: Character
    public let shift: Bool

    public init(character: Character, shift: Bool = false) {
        self.character = character
        self.shift = shift
    }
}

public enum KeyCommandRegistry {
    public static let bindings: [KeyBinding: KeyCommand] = [
        KeyBinding(character: "1"): .pickColor(0),
        KeyBinding(character: "2"): .pickColor(1),
        KeyBinding(character: "3"): .pickColor(2),
        KeyBinding(character: "4"): .pickColor(3),
        KeyBinding(character: "5"): .pickColor(4),
        KeyBinding(character: "6"): .pickColor(5),
        KeyBinding(character: "7"): .pickColor(6),
        KeyBinding(character: "8"): .pickColor(7),
        KeyBinding(character: "s"): .bumpSize(.up),
        KeyBinding(character: "s", shift: true): .bumpSize(.down),
        KeyBinding(character: "o"): .bumpOpacity(.up),
        KeyBinding(character: "o", shift: true): .bumpOpacity(.down),
        KeyBinding(character: "h"): .toggleHide,
        KeyBinding(character: "f"): .toggleAutoFade,
        // "\u{7F}" is NSDeleteCharacter — what NSEvent delivers when the user
        // presses the big delete key (top-right of QWERTY). The forward-delete
        // key (fn+Delete) is U+F728 and is intentionally unbound for now.
        KeyBinding(character: "\u{7F}"): .clear,
        KeyBinding(character: "t"): .selectTool(.text),
        // The pen tool is labeled "Drawing" in the UI; `d` is its home-row shortcut.
        KeyBinding(character: "d"): .selectTool(.pen),
        KeyBinding(character: "a"): .selectTool(.arrow)
    ]

    public static func command(for binding: KeyBinding) -> KeyCommand? {
        bindings[binding]
    }
}
