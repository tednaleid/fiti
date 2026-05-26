// ABOUTME: NSButton that accepts the first mouse click, so toolbar controls fire
// ABOUTME: immediately in the non-activating floating panel (no dead first click).

import AppKit

final class FirstMouseButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
