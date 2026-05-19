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
    private var drawingItems: [KeyCommand: NSMenuItem] = [:]

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

        let drawingMenu = NSMenu(title: "Drawing")
        buildDrawingSubmenu(drawingMenu)
        let drawingItem = NSMenuItem(title: "Drawing", action: nil, keyEquivalent: "")
        drawingItem.submenu = drawingMenu

        menu.addItem(activateItem)
        menu.addItem(deactivateItem)
        menu.addItem(.separator())
        menu.addItem(preferencesItem)
        menu.addItem(.separator())
        menu.addItem(drawingItem)
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

    private func buildDrawingSubmenu(_ menu: NSMenu) {
        for (i, color) in QuickPickPalette.colors.enumerated() {
            let item = makeDrawingItem(
                title: color.name,
                key: "\(i + 1)",
                modifiers: [],
                command: .pickColor(i)
            )
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(makeDrawingItem(title: "Larger stroke", key: "s", modifiers: [], command: .bumpSize(.up)))
        menu.addItem(makeDrawingItem(title: "Smaller stroke", key: "s", modifiers: [.shift], command: .bumpSize(.down)))
        menu.addItem(.separator())
        menu.addItem(makeDrawingItem(title: "More opaque", key: "o", modifiers: [], command: .bumpOpacity(.up)))
        menu.addItem(makeDrawingItem(title: "Less opaque", key: "o", modifiers: [.shift], command: .bumpOpacity(.down)))
        menu.addItem(.separator())
        menu.addItem(makeDrawingItem(title: "Hide drawings", key: "h", modifiers: [], command: .toggleHide))
        menu.addItem(makeDrawingItem(title: "Auto-fade", key: "f", modifiers: [], command: .toggleAutoFade))
    }

    private func makeDrawingItem(title: String, key: String, modifiers: NSEvent.ModifierFlags,
                                 command: KeyCommand) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(runDrawingCommand(_:)), keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = self
        item.representedObject = CommandBox(command: command)
        drawingItems[command] = item
        return item
    }

    @objc private func runDrawingCommand(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? CommandBox else { return }
        controller.run(box.command)
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
        drawingItems[.toggleHide]?.state = controller.drawingsVisible ? .off : .on
        drawingItems[.toggleAutoFade]?.state = controller.autoFadeEnabled ? .on : .off
    }
}

private final class CommandBox: NSObject {
    let command: KeyCommand
    init(command: KeyCommand) { self.command = command }
}
