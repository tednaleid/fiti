// ABOUTME: Active-app keyboard shortcut adapter. Installs an NSEvent local
// ABOUTME: monitor while mode != .inactive; translates each keyDown into a
// ABOUTME: KeyCommand via KeyCommandRegistry and dispatches AppController.run(_:).

import AppKit

@MainActor
public final class KeyMonitor {
    private let controller: AppController
    private var monitor: Any?
    // Separate storage so the nonisolated deinit can remove the monitor without
    // crossing an actor boundary. NSEvent.removeMonitor(_:) is thread-safe.
    nonisolated(unsafe) private var monitorForDeinit: Any?

    public init(controller: AppController) {
        self.controller = controller
    }

    deinit {
        if let m = monitorForDeinit {
            NSEvent.removeMonitor(m)
        }
    }

    /// Called from main.swift's onModeChanged composition. Installs the local
    /// monitor while fiti is active so we never intercept keys when inactive.
    public func syncRegistration(for mode: AppController.Mode) {
        if mode == .inactive {
            uninstall()
        } else {
            install()
        }
    }

    private func install() {
        guard monitor == nil else { return }
        let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event) ?? event
        }
        monitor = m
        monitorForDeinit = m
    }

    private func uninstall() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
            monitorForDeinit = nil
        }
    }

    /// Pure translation, exposed for unit tests. Returns nil to swallow the
    /// event (bound key dispatched); returns the original event to pass it
    /// through (unbound, Cmd-modified, or multi-character composition).
    internal func handle(_ event: NSEvent) -> NSEvent? {
        // charactersIgnoringModifiers ignores everything *except* shift, so
        // Shift+S arrives as "S". Lowercase before building the binding —
        // the registry uses lowercase + an explicit shift flag.
        guard let chars = event.charactersIgnoringModifiers,
              chars.count == 1,
              let ch = chars.lowercased().first else {
            return event
        }
        // Cmd combos belong to the menubar (Cmd+Z, Cmd+K, Cmd+S, ...).
        if event.modifierFlags.contains(.command) { return event }
        let binding = KeyBinding(character: ch, shift: event.modifierFlags.contains(.shift))
        guard let command = KeyCommandRegistry.command(for: binding) else { return event }
        controller.run(command)
        return nil
    }
}
