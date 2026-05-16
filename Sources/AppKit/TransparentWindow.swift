// ABOUTME: Borderless transparent always-on-top NSWindow covering the main screen.
// ABOUTME: Conforms to WindowControl — click-through toggle and focus.

import AppKit

public final class TransparentWindow: NSWindow, WindowControl {
    public init() {
        let frame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        super.init(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .floating
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.ignoresMouseEvents = true   // start in click-through state
        self.acceptsMouseMovedEvents = true
        self.setFrame(frame, display: true)
    }

    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { true }

    // MARK: - WindowControl

    public func setClickThrough(_ enabled: Bool) {
        self.ignoresMouseEvents = enabled
    }

    public func focus() {
        self.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
