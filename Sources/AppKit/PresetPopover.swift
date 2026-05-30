// ABOUTME: Borderless panel showing 10 preset cells for the size or opacity axis.
// ABOUTME: Owns its dismissal monitors and lifecycle; idempotent open / close.

import AppKit

@MainActor
final class PresetPopover {
    private let panel: NSPanel

    private(set) var currentAxis: PresetAxis?
    var isOpen: Bool { currentAxis != nil }

    init() {
        let rect = NSRect(x: 0, y: 0, width: 100, height: 140)
        panel = NSPanel(contentRect: rect,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = NSColor.clear
        panel.hasShadow = true
        // Above the toolbar (.floating + 1) so the popover sits on top of it.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
        panel.hidesOnDeactivate = false

        let container = NSView(frame: rect)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(white: 0.16, alpha: 0.96).cgColor
        container.layer?.cornerRadius = 8
        panel.contentView = container
    }

    // swiftlint:disable function_parameter_count
    /// Show the popover for `axis`, anchored to `anchor` (screen coords) on the chosen `edge`.
    /// `onPick(value)` fires when the user clicks a cell; the popover then closes.
    func open(axis: PresetAxis,
              currentValue: Double,
              color: RGBA,
              width: Double,
              tool: Tool,
              outlineOn: Bool,
              anchor: NSRect,
              edge: PopoverEdge,
              onPick: @escaping (Double) -> Void) {
        // swiftlint:enable function_parameter_count
        guard !isOpen else { return }
        currentAxis = axis
        // Position the panel flush with the anchor's top/bottom; horizontal placement
        // depends on the edge. Concrete cell building lands in Task 6.
        let panelWidth = panel.frame.width
        let gap: CGFloat = 6
        let originY = anchor.minY
        let originX: CGFloat
        switch edge {
        case .maxX: originX = anchor.maxX + gap
        case .minX: originX = anchor.minX - gap - panelWidth
        }
        panel.setFrame(NSRect(x: originX, y: originY, width: panelWidth, height: anchor.height),
                       display: true)
        panel.orderFront(nil)
    }

    func close() {
        guard isOpen else { return }
        currentAxis = nil
        panel.orderOut(nil)
    }
}
