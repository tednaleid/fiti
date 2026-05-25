// ABOUTME: NSPanel subclass for the fiti toolbar — nonactivating so clicks
// ABOUTME: don't steal focus from the underlying app being presented to.

import AppKit

public final class ToolbarPanel: NSPanel {
    public init() {
        let initialRect = NSRect(x: 24, y: 24, width: 56, height: 560)
        super.init(contentRect: initialRect,
                   styleMask: [.titled, .nonactivatingPanel, .utilityWindow],
                   backing: .buffered,
                   defer: false)
        self.level = .floating
        self.hidesOnDeactivate = false
        self.isFloatingPanel = true
        self.title = "fiti"
        self.setFrameAutosaveName("fiti.toolbar.v2")
        self.standardWindowButton(.closeButton)?.isHidden = true
        self.standardWindowButton(.miniaturizeButton)?.isHidden = true
        self.standardWindowButton(.zoomButton)?.isHidden = true
    }
}
