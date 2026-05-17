// ABOUTME: Menu-bar status item for fiti. Two-state SF Symbol icon,
// ABOUTME: menu wired to AppController actions, NSMenuDelegate for enabled state.

import AppKit

@MainActor
public final class MenubarController {
    private let controller: AppController
    private let editor: Editor
    private let statusItem: NSStatusItem
    internal private(set) var currentSymbolName: String = ""

    public init(controller: AppController, editor: Editor) {
        self.controller = controller
        self.editor = editor
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
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
}
