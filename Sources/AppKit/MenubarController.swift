// ABOUTME: Menu-bar status item for fiti. Two-state SF Symbol icon,
// ABOUTME: menu wired to AppController actions, NSMenuDelegate for enabled state.

import AppKit

@MainActor
public final class MenubarController: NSObject {
    private let controller: AppController
    private let editor: Editor
    private let onOpenPreferences: @MainActor () -> Void
    private let statusItem: NSStatusItem
    internal let menu: NSMenu
    internal private(set) var currentSymbolName: String = ""

    private let activateItem: NSMenuItem
    private let deactivateItem: NSMenuItem
    private let preferencesItem: NSMenuItem
    private let undoItem: NSMenuItem
    private let redoItem: NSMenuItem

    public init(
        controller: AppController,
        editor: Editor,
        onOpenPreferences: @escaping @MainActor () -> Void
    ) {
        self.controller = controller
        self.editor = editor
        self.onOpenPreferences = onOpenPreferences
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.menu = NSMenu()

        self.activateItem = NSMenuItem(title: "Activate", action: #selector(activate), keyEquivalent: "f")
        self.deactivateItem = NSMenuItem(title: "Deactivate", action: #selector(deactivate), keyEquivalent: "\u{1b}")
        self.preferencesItem = NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ",")
        let clearItem = NSMenuItem(title: "Clear", action: #selector(clearAll), keyEquivalent: "k")
        self.undoItem = NSMenuItem(title: "Undo", action: #selector(undo), keyEquivalent: "z")
        self.redoItem = NSMenuItem(title: "Redo", action: #selector(redo), keyEquivalent: "z")
        let quitItem = NSMenuItem(title: "Quit fiti", action: #selector(quit), keyEquivalent: "q")

        super.init()

        activateItem.keyEquivalentModifierMask = [.option]
        deactivateItem.keyEquivalentModifierMask = []
        preferencesItem.keyEquivalentModifierMask = [.command]
        clearItem.keyEquivalentModifierMask = [.command]
        undoItem.keyEquivalentModifierMask = [.command]
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        quitItem.keyEquivalentModifierMask = [.command]

        for item in [activateItem, deactivateItem, preferencesItem, undoItem, redoItem, clearItem, quitItem] {
            item.target = self
        }

        menu.addItem(activateItem)
        menu.addItem(deactivateItem)
        menu.addItem(.separator())
        menu.addItem(preferencesItem)
        menu.addItem(.separator())
        menu.addItem(clearItem)
        menu.addItem(undoItem)
        menu.addItem(redoItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)

        menu.delegate = self
        statusItem.menu = menu

        updateIcon(for: controller.mode)
        controller.onModeChanged = { [weak self] mode in self?.updateIcon(for: mode) }
    }

    isolated deinit {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func updateIcon(for mode: AppController.Mode) {
        let name = mode == .inactive ? "theatermask.and.paintbrush"
                                     : "theatermask.and.paintbrush.fill"
        currentSymbolName = name
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "fiti")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    @objc private func activate() { controller.activate() }
    @objc private func deactivate() { controller.deactivate() }
    @objc private func openPreferences() { onOpenPreferences() }
    @objc private func clearAll() { controller.clear() }
    @objc private func undo() { _ = editor.undo() }
    @objc private func redo() { _ = editor.redo() }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
}

extension MenubarController: NSMenuDelegate {
    public func menuNeedsUpdate(_ menu: NSMenu) {
        let active = controller.mode != .inactive
        activateItem.isEnabled = !active
        deactivateItem.isEnabled = active
        undoItem.isEnabled = editor.canUndo
        redoItem.isEnabled = editor.canRedo
    }
}
