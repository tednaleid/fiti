// ABOUTME: NSButton that accepts the first mouse click, so toolbar controls fire
// ABOUTME: immediately in the non-activating floating panel (no dead first click).

import AppKit

/// fiti is an accessory app and the toolbar is a non-activating panel, so right
/// after activation it isn't the foreground app. A plain NSButton swallows the
/// first click (using it to focus). Accepting first mouse makes the control fire
/// on that first click — matching CanvasInputView, which already does this.
final class FirstMouseButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
