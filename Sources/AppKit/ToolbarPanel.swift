// ABOUTME: NSPanel subclass for the fiti toolbar. Activating (not a non-activating
// ABOUTME: panel) so a first click activates the accessory app and fires the control.

import AppKit

public final class ToolbarPanel: NSPanel {
    public init() {
        // The toolbar only shows while fiti is active (and capturing), so the
        // panel being activating is fine — and it's necessary: an accessory app
        // can't reliably self-activate from a global hotkey on current macOS, so
        // the user's click on the panel is what brings fiti foreground. A
        // non-activating panel swallowed that first click until a canvas draw
        // activated the app.
        let initialRect = NSRect(x: 24, y: 24, width: 80, height: 600)
        super.init(contentRect: initialRect,
                   styleMask: [.titled, .utilityWindow],
                   backing: .buffered,
                   defer: false)
        self.level = .floating
        self.hidesOnDeactivate = false
        self.isFloatingPanel = true
        self.title = "fiti"
        self.setFrameAutosaveName("fiti.toolbar.v3")
        self.standardWindowButton(.closeButton)?.isHidden = true
        self.standardWindowButton(.miniaturizeButton)?.isHidden = true
        self.standardWindowButton(.zoomButton)?.isHidden = true
    }
}
