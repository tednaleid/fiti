// ABOUTME: Borderless transparent always-on-top NSWindow covering the main screen.
// ABOUTME: Conforms to WindowControl — click-through toggle and focus.

import AppKit

public final class TransparentWindow: NSWindow, WindowControl {
    /// The most-recent non-fiti application to be frontmost. Maintained by a
    /// `NSWorkspace.didActivateApplicationNotification` observer so it's always
    /// current regardless of how fiti was activated (hotkey, menubar, or HTTP).
    /// `releaseFocus()` restores to this on deactivate.
    private var previousApp: NSRunningApplication?
    private var activationObserver: NSObjectProtocol?

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

        // Continuously track the most-recent non-fiti frontmost app. Whoever
        // was on top right before fiti's hotkey or menubar fires is what
        // releaseFocus() returns to.
        let ownBundle = Bundle.main.bundleIdentifier
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            if app.bundleIdentifier != ownBundle {
                self.previousApp = app
            }
        }
    }

    isolated deinit {
        if let token = activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
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

    public func releaseFocus() {
        defer { previousApp = nil }
        guard let app = previousApp, !app.isTerminated else { return }
        app.activate(options: [])
    }
}
