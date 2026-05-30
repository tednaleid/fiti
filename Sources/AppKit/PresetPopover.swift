// ABOUTME: Borderless panel showing 10 preset cells for the size or opacity axis.
// ABOUTME: Owns its dismissal monitors and lifecycle; idempotent open / close.

import AppKit

@MainActor
final class PresetPopover {
    private let panel: NSPanel
    private let stack: NSStackView
    private var cells: [NSButton] = []
    private var onPick: ((Double) -> Void)?
    private var localKeyMonitor: Any?
    private var globalMouseMonitor: Any?
    private var deactivationObserver: NSObjectProtocol?
    private let escKeyCode: UInt16 = 0x35

    private(set) var currentAxis: PresetAxis?
    var isOpen: Bool { currentAxis != nil }

    private let cellSpacing: CGFloat = 6
    private let edgePadding: CGFloat = 6

    init() {
        let rect = NSRect(x: 0, y: 0, width: 100, height: 140)
        panel = NSPanel(contentRect: rect,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = NSColor.clear
        panel.hasShadow = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
        panel.hidesOnDeactivate = false

        stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = cellSpacing
        stack.edgeInsets = NSEdgeInsets(top: edgePadding, left: edgePadding,
                                        bottom: edgePadding, right: edgePadding)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: rect)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor(white: 0.16, alpha: 0.96).cgColor
        container.layer?.cornerRadius = 8
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])
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
        self.onPick = onPick

        buildCells(axis: axis, currentValue: currentValue,
                   color: color, width: width, tool: tool, outlineOn: outlineOn)
        positionPanel(anchor: anchor, edge: edge)
        panel.orderFront(nil)
        installLocalKeyMonitor()
        installDeactivationObserver()
        installGlobalMouseMonitor()
    }

    func close() {
        guard isOpen else { return }
        currentAxis = nil
        onPick = nil
        for cell in cells { cell.removeFromSuperview() }
        cells.removeAll()
        panel.orderOut(nil)
        removeLocalKeyMonitor()
        removeDeactivationObserver()
        removeGlobalMouseMonitor()
    }

    /// Rebuild the open popover's cells for a new style/value — e.g. the user changed
    /// color or width while it stays open. Keeps the current axis; no-op when closed.
    func refresh(currentValue: Double, color: RGBA, width: Double, tool: Tool, outlineOn: Bool) {
        guard isOpen, let axis = currentAxis else { return }
        for cell in cells { cell.removeFromSuperview() }
        cells.removeAll()
        buildCells(axis: axis, currentValue: currentValue,
                   color: color, width: width, tool: tool, outlineOn: outlineOn)
    }

    /// Render the open popover panel's view hierarchy to PNG, for the dev HTTP
    /// `/popover.png` introspection endpoint. Returns nil when the popover is closed.
    func snapshotPNG() -> Data? {
        guard isOpen else { return nil }
        return panel.contentView?.snapshotPNG()
    }

    private func installLocalKeyMonitor() {
        if localKeyMonitor != nil { return }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleLocalKey(event) ? nil : event
        }
    }

    private func removeLocalKeyMonitor() {
        if let token = localKeyMonitor {
            NSEvent.removeMonitor(token)
            localKeyMonitor = nil
        }
    }

    private func installGlobalMouseMonitor() {
        if globalMouseMonitor != nil { return }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
    }

    private func removeGlobalMouseMonitor() {
        if let token = globalMouseMonitor {
            NSEvent.removeMonitor(token)
            globalMouseMonitor = nil
        }
    }

    private func installDeactivationObserver() {
        if deactivationObserver != nil { return }
        deactivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    private func removeDeactivationObserver() {
        if let observer = deactivationObserver {
            NotificationCenter.default.removeObserver(observer)
            deactivationObserver = nil
        }
    }

    /// Returns true if the event was consumed (ESC, popover closes); false otherwise.
    private func handleLocalKey(_ event: NSEvent) -> Bool {
        guard isOpen, event.keyCode == escKeyCode else { return false }
        close()
        return true
    }

    // swiftlint:disable function_parameter_count
    private func buildCells(axis: PresetAxis, currentValue: Double, color: RGBA, width: Double,
                            tool: Tool, outlineOn: Bool) {
        // swiftlint:enable function_parameter_count
        let selected = axis.selectedIndex(for: currentValue)
        let resolvedTool: Tool = (tool == .selection) ? .pen : tool
        for (index, preset) in axis.values.enumerated() {
            let cell = makeCell(index: index, axis: axis, preset: preset,
                                color: color, width: width, tool: resolvedTool, outlineOn: outlineOn)
            setActiveBackground(cell, active: index == selected)
            stack.addArrangedSubview(cell)
            cells.append(cell)
        }
    }

    // swiftlint:disable function_parameter_count
    private func makeCell(index: Int, axis: PresetAxis, preset: Double,
                          color: RGBA, width: Double, tool: Tool, outlineOn: Bool) -> NSButton {
        // swiftlint:enable function_parameter_count
        let cell = FirstMouseButton(title: "", target: nil, action: nil)
        cell.tag = index
        cell.target = self
        cell.action = #selector(cellClicked(_:))
        cell.bezelStyle = .regularSquare
        cell.isBordered = false
        cell.imagePosition = .imageOnly
        cell.wantsLayer = true
        cell.layer?.cornerRadius = 4

        let image: NSImage?
        switch axis {
        case .size:
            image = MarkPreview.render(tool: tool, color: color, width: preset, outlineOn: outlineOn)
        case .opacity:
            let withAlpha = RGBA(r: color.r, g: color.g, b: color.b, a: preset)
            image = MarkPreview.render(tool: tool, color: withAlpha, width: width, outlineOn: outlineOn)
        }
        cell.image = image

        cell.widthAnchor.constraint(equalToConstant: CGFloat(MarkPreview.canvasSize.width)).isActive = true
        cell.heightAnchor.constraint(equalToConstant: CGFloat(MarkPreview.canvasSize.height)).isActive = true
        return cell
    }

    @objc private func cellClicked(_ sender: NSButton) {
        guard let axis = currentAxis else { return }
        let value = axis.values[sender.tag]
        let pick = onPick
        close()
        pick?(value)
    }

    private func setActiveBackground(_ button: NSButton, active: Bool) {
        button.layer?.backgroundColor = active
            ? NSColor.controlAccentColor.withAlphaComponent(0.25).cgColor
            : NSColor.clear.cgColor
    }

    private func positionPanel(anchor: NSRect, edge: PopoverEdge) {
        // Width: 10 cells + 9 inter-cell gaps + 2 edge paddings.
        let cellW = CGFloat(MarkPreview.canvasSize.width)
        let cellCount: CGFloat = 10
        let panelWidth = cellW * cellCount + cellSpacing * (cellCount - 1) + edgePadding * 2
        let originY = anchor.minY
        let originX: CGFloat
        switch edge {
        case .maxX: originX = anchor.maxX + cellSpacing
        case .minX: originX = anchor.minX - cellSpacing - panelWidth
        }
        panel.setFrame(NSRect(x: originX, y: originY, width: panelWidth, height: anchor.height),
                       display: true)
    }

    // MARK: Test hooks

    // swiftlint:disable identifier_name
    var testOnly_cellCount: Int { cells.count }
    var testOnly_selectedCellIndex: Int? {
        cells.firstIndex { ($0.layer?.backgroundColor?.alpha ?? 0) > 0 }
    }
    func testOnly_clickCell(at index: Int) {
        cellClicked(cells[index])
    }
    func testOnly_handleKey(_ event: NSEvent) -> Bool { handleLocalKey(event) }
    var testOnly_monitorCount: Int {
        var count = 0
        if localKeyMonitor != nil { count += 1 }
        if globalMouseMonitor != nil { count += 1 }
        if deactivationObserver != nil { count += 1 }
        return count
    }
    // swiftlint:enable identifier_name
}
