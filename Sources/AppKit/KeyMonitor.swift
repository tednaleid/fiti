// ABOUTME: Active-app keyboard shortcut adapter. Installs an NSEvent local
// ABOUTME: monitor while mode != .inactive; translates keyDown/keyUp into text
// ABOUTME: input (while editing), tool switches (Space), or KeyCommands.

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
        let m = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
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
    /// event (bound key dispatched or Space tool switch); returns the original
    /// event to pass it through (unbound, Cmd-modified, or multi-character).
    internal func handle(_ event: NSEvent) -> NSEvent? {
        // Text-capture branch: while a session is active, route all keyDown
        // events to the text input handler, bypassing shortcuts entirely.
        if controller.isEditingText, event.type == .keyDown {
            return handleTextKey(event)
        }

        // charactersIgnoringModifiers ignores everything *except* shift, so
        // Shift+S arrives as "S". Lowercase before building the binding —
        // the registry uses lowercase + an explicit shift flag.
        guard let chars = event.charactersIgnoringModifiers,
              chars.count == 1,
              let ch = chars.lowercased().first else {
            return event
        }
        // Space press-and-hold: keyDown → selection (pen only), keyUp → pen.
        if ch == " " { return handleSpace(event) }
        // Only dispatch registry commands for keyDown; pass keyUp through.
        guard event.type == .keyDown else { return event }
        // Cmd combos belong to the menubar (Cmd+Z, Cmd+K, Cmd+S, ...).
        if event.modifierFlags.contains(.command) { return event }
        let binding = KeyBinding(character: ch, shift: event.modifierFlags.contains(.shift))
        guard let command = KeyCommandRegistry.command(for: binding) else { return event }
        controller.run(command)
        return nil
    }

    /// Handles Space press-and-hold: keyDown → selection tool (from pen), keyUp → pen.
    /// Guards ensure Space in other tool modes is a no-op rather than a forced switch.
    private func handleSpace(_ event: NSEvent) -> NSEvent? {
        if event.type == .keyDown {
            if event.isARepeat { return nil }
            if controller.currentTool == .pen {
                controller.currentTool = .selection
            }
            return nil
        }
        if event.type == .keyUp {
            if controller.currentTool == .selection {
                controller.currentTool = .pen
            }
            return nil
        }
        return event
    }

    private func handleTextKey(_ event: NSEvent) -> NSEvent? {
        // Cmd-combos pass through to the menubar (Cmd+Z, Cmd+K, etc.).
        if event.modifierFlags.contains(.command) { return event }

        switch event.keyCode {
        case 53:  // Escape — pass through to the app-command key path
            // (CanvasInputView.keyDown -> onDeactivate), which owns Esc and
            // routes it through the layered escapePressed(). Acting here too
            // would double-handle it (commit-then-deactivate).
            return event
        case 36:  // Return / Enter
            if event.modifierFlags.contains(.shift) {
                controller.insertNewline()
            } else {
                controller.commitText()
            }
        case 51:  // Delete / Backspace
            controller.deleteBackward()
        case 123, 124, 126, 125:  // Arrow keys
            handleArrow(keyCode: event.keyCode)
        default:
            if let chars = event.characters, !chars.isEmpty,
               chars.unicodeScalars.allSatisfy({ $0.value >= 0x20 }) {
                controller.insertText(chars)
            }
        }
        return nil
    }

    private func handleArrow(keyCode: UInt16) {
        switch keyCode {
        case 123: controller.moveCaret(.left)
        case 124: controller.moveCaret(.right)
        case 126: controller.moveCaret(.up)
        case 125: controller.moveCaret(.down)
        default: break
        }
    }
}
