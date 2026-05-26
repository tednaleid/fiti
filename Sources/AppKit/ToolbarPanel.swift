// ABOUTME: NSPanel subclass for the fiti toolbar. A non-activating panel one level
// ABOUTME: above the canvas, so its controls take clicks without the app foreground.

import AppKit

public final class ToolbarPanel: NSPanel {
    public init() {
        // opt-f can't bring an accessory app foreground on current macOS
        // (cooperative activation blocks a background self-activation), so the
        // toolbar must work while the app is inactive. A `.nonactivatingPanel`
        // delivers clicks straight to its controls without trying to activate.
        // It must also sit one level *above* the full-screen canvas window
        // (also `.floating`); otherwise the canvas, ordered front on activation,
        // covers the panel and the canvas swallows the clicks as toolbar-region
        // pointer events.
        let initialRect = NSRect(x: 24, y: 24, width: 80, height: 600)
        super.init(contentRect: initialRect,
                   styleMask: [.titled, .utilityWindow, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        self.hidesOnDeactivate = false
        self.isFloatingPanel = true
        self.becomesKeyOnlyIfNeeded = true
        self.title = "fiti"
        self.setFrameAutosaveName("fiti.toolbar.v3")
        self.standardWindowButton(.closeButton)?.isHidden = true
        self.standardWindowButton(.miniaturizeButton)?.isHidden = true
        self.standardWindowButton(.zoomButton)?.isHidden = true
        // Set level last: isFloatingPanel and other config can reset it. Must be
        // above the canvas window (.floating) so the panel receives its clicks.
        self.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
    }
}
