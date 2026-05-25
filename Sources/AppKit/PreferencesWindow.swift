// ABOUTME: NSWindow subclass for fiti Preferences. Titled, non-resizable, has
// ABOUTME: a close button only; window survives close (isReleasedWhenClosed = false).

import AppKit

public final class PreferencesWindow: NSWindow {
    public static let autosaveName: NSWindow.FrameAutosaveName = "fiti.preferences"

    public init() {
        let initialRect = NSRect(x: 0, y: 0, width: 360, height: 180)
        super.init(contentRect: initialRect,
                   styleMask: [.titled, .closable],
                   backing: .buffered,
                   defer: false)
        self.title = "fiti Preferences"
        self.isReleasedWhenClosed = false
        self.setFrameAutosaveName(Self.autosaveName)
        self.standardWindowButton(.miniaturizeButton)?.isHidden = true
        self.standardWindowButton(.zoomButton)?.isHidden = true
    }
}
