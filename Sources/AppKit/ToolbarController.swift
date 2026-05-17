// ABOUTME: Floating toolbar that appears when fiti activates. Owns color /
// ABOUTME: width / opacity / hide controls; writes through to AppController.

import AppKit

@MainActor
public final class ToolbarController: NSObject {
    private let controller: AppController
    private let defaults: UserDefaults
    internal let panel: ToolbarPanel

    public init(controller: AppController, defaults: UserDefaults = .standard) {
        self.controller = controller
        self.defaults = defaults
        self.panel = ToolbarPanel()
        super.init()
        updateVisibility(for: controller.mode)
    }

    public func updateVisibility(for mode: AppController.Mode) {
        if mode == .inactive {
            panel.orderOut(nil)
        } else {
            panel.orderFront(nil)
        }
    }
}
