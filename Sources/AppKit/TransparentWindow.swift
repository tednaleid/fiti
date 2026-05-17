// ABOUTME: Borderless transparent always-on-top NSWindow covering the main screen.
// ABOUTME: Conforms to WindowControl — click-through toggle and focus.

import AppKit

public final class TransparentWindow: NSWindow, WindowControl {
    /// The application that was frontmost when `focus()` was last called.
    /// Captured before fiti steals focus so `releaseFocus()` can hand it
    /// back on deactivate. Nil between deactivate and the next activate.
    private var previousApp: NSRunningApplication?

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
        // Capture BEFORE we activate ourselves; otherwise frontmostApplication
        // would already be fiti. Skip self-capture (happens if the user invokes
        // activate from our menubar, which makes fiti frontmost first).
        let ownBundle = Bundle.main.bundleIdentifier
        if let current = NSWorkspace.shared.frontmostApplication,
           current.bundleIdentifier != ownBundle {
            previousApp = current
        }
        self.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    public func releaseFocus() {
        defer { previousApp = nil }
        guard let app = previousApp, !app.isTerminated else { return }
        app.activate(options: [])
    }
}
