// ABOUTME: Floating toolbar that appears when fiti activates. Owns color /
// ABOUTME: width / opacity / hide controls; writes through to AppController.

import AppKit

// swiftlint:disable file_length
// ^ The toolbar controller is the single hub for all toolbar chrome + wiring.
// A follow-up could split the test hooks / icon builders into extensions;
// artificial fragmentation just to hit the line count isn't worth it now.

@MainActor
// swiftlint:disable:next type_body_length
public final class ToolbarController: NSObject {
    private let controller: AppController
    private let defaults: UserDefaults
    private let outlineSettings: OutlineSettings
    internal let panel: ToolbarPanel

    private let penButton = NSButton(title: "", target: nil, action: nil)
    private let textButton = NSButton(title: "", target: nil, action: nil)
    private let arrowButton = NSButton(title: "", target: nil, action: nil)
    private let customColorButton = NSButton(title: "", target: nil, action: nil)
    private let markControl = MarkControl()
    private let hideButton: NSButton
    private let autoFadeButton = NSButton(title: "", target: nil, action: nil)
    private var quickPickButtons: [NSButton] = []

    private(set) var activeSwatchIndex: Int?

    public init(controller: AppController, defaults: UserDefaults = .standard,
                outlineSettings: OutlineSettings = DefaultOutlineSettings()) {
        self.controller = controller
        self.defaults = defaults
        self.outlineSettings = outlineSettings
        self.panel = ToolbarPanel()
        self.hideButton = NSButton(title: "", target: nil, action: nil)
        super.init()

        loadPersistedState()
        buildContent()
        updateVisibility(for: controller.mode)

        markControl.width = controller.currentWidth
        markControl.color = controller.currentColor
        markControl.currentTool = controller.currentTool
        markControl.outlineOn = outlineOn(for: controller.currentTool)
        markControl.onWidth = { [weak self] v in self?.controller.currentWidth = v }
        markControl.onOpacity = { [weak self] v in
            guard let self else { return }
            let c = self.controller.currentColor
            self.controller.currentColor = RGBA(r: c.r, g: c.g, b: c.b, a: v)
        }

        // React to external writes (HTTP, other adapters) — keep widgets in sync and persist.
        controller.onCurrentColorChanged = { [weak self] color in
            self?.syncColorWidgets(with: color)
            self?.markControl.color = color
            self?.persistColor()
        }
        controller.onCurrentWidthChanged = { [weak self] width in
            self?.markControl.width = width
            self?.defaults.set(width, forKey: "fiti.width")
        }
        controller.onDrawingsVisibilityChanged = { [weak self] visible in
            self?.updateHideButtonGlyph(visible: visible)
        }
        controller.onAutoFadeEnabledChanged = { [weak self] enabled in
            self?.updateAutoFadeGlyph(enabled: enabled)
        }
        controller.onCurrentToolChanged = { [weak self] tool in
            guard let self else { return }
            self.updateToolHighlights()
            if tool != .selection {
                self.markControl.currentTool = tool
                self.markControl.outlineOn = self.outlineOn(for: tool)
            }
        }
    }

    /// Whether the size-glyph preview should show an outline: the live per-tool
    /// outline setting. Selection has no mark of its own, so no outline.
    private func outlineOn(for tool: Tool) -> Bool {
        switch tool {
        case .pen: return outlineSettings.penOutline
        case .text: return outlineSettings.textOutline
        case .arrow: return outlineSettings.arrowOutline
        case .selection: return false
        }
    }

    public func updateVisibility(for mode: AppController.Mode) {
        if mode == .inactive {
            panel.orderOut(nil)
        } else {
            panel.orderFront(nil)
        }
    }

    private func syncColorWidgets(with color: RGBA) {
        updateSwatchHighlights()
    }

    // swiftlint:disable:next function_body_length
    private func buildContent() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false

        configureToolButton(penButton, symbol: "pencil.tip", accessibility: "Pen",
                            tooltip: "Pen — p", action: #selector(penClicked(_:)))
        configureToolButton(textButton, symbol: "textformat", accessibility: "Text",
                            tooltip: "Text — t", action: #selector(textClicked(_:)))
        configureToolButton(arrowButton, symbol: "line.diagonal.arrow", accessibility: "Arrow",
                            tooltip: "Arrow — a", action: #selector(arrowClicked(_:)))
        stack.addArrangedSubview(penButton)
        stack.addArrangedSubview(textButton)
        stack.addArrangedSubview(arrowButton)

        for (i, color) in QuickPickPalette.colors.enumerated() {
            let btn = NSButton(title: "", target: self, action: #selector(colorClicked(_:)))
            btn.tag = i
            btn.bezelStyle = .regularSquare
            btn.image = makeSwatchImage(r: color.r, g: color.g, b: color.b)
            btn.imagePosition = .imageOnly
            btn.toolTip = "\(color.name) — \(i + 1)"
            quickPickButtons.append(btn)
            stack.addArrangedSubview(btn)
        }

        // Custom-color picker: a color-wheel button (clearly "pick any color"),
        // grouped with the swatches. Opens the macOS color panel on click.
        customColorButton.image = makeColorWheelImage(diameter: 22)
        customColorButton.imagePosition = .imageOnly
        customColorButton.bezelStyle = .regularSquare
        customColorButton.target = self
        customColorButton.action = #selector(openColorPanel)
        customColorButton.toolTip = "Custom color"
        stack.addArrangedSubview(customColorButton)

        stack.addArrangedSubview(markControl)

        hideButton.target = self
        hideButton.action = #selector(toggleHide(_:))
        hideButton.bezelStyle = .regularSquare
        hideButton.imagePosition = .imageOnly
        updateHideButtonGlyph(visible: controller.drawingsVisible)
        stack.addArrangedSubview(hideButton)

        autoFadeButton.target = self
        autoFadeButton.action = #selector(autoFadeClicked(_:))
        autoFadeButton.bezelStyle = .regularSquare
        autoFadeButton.imagePosition = .imageOnly
        updateAutoFadeGlyph(enabled: controller.autoFadeEnabled)
        stack.addArrangedSubview(autoFadeButton)
        autoFadeButton.widthAnchor.constraint(equalTo: hideButton.widthAnchor).isActive = true

        let container = ToolbarContainerView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])
        panel.contentView = container
        updateSwatchHighlights()
        updateToolHighlights()
    }

    /// Refresh the "active" highlight on the swatch matching `controller.currentColor`.
    /// Called whenever the controller's color changes (via toolbar click, picker,
    /// keyboard shortcut, or HTTP write). Compares on RGB only — alpha comes from
    /// the opacity picker and doesn't disqualify a swatch match.
    private func updateSwatchHighlights() {
        let match = matchingSwatchIndex(for: controller.currentColor)
        activeSwatchIndex = match
        for (i, btn) in quickPickButtons.enumerated() {
            setActiveBackground(btn, active: i == match)
        }
        // The custom-color wheel is "active" when the color isn't one of the
        // palette swatches (i.e. it came from the color panel).
        setActiveBackground(customColorButton, active: match == nil)
    }

    private func matchingSwatchIndex(for color: RGBA) -> Int? {
        QuickPickPalette.colors.firstIndex { c in
            abs(c.r - color.r) < 0.001 && abs(c.g - color.g) < 0.001 && abs(c.b - color.b) < 0.001
        }
    }

    private func configureToolButton(_ button: NSButton, symbol: String, accessibility: String,
                                     tooltip: String, action: Selector) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: accessibility)
        button.imagePosition = .imageOnly
        button.bezelStyle = .regularSquare
        button.target = self
        button.action = action
        button.toolTip = tooltip
    }

    /// Highlights whichever tool button matches `controller.currentTool`. While
    /// Space-to-select is held, currentTool is .selection and neither lights up.
    private func updateToolHighlights() {
        setActiveBackground(penButton, active: controller.currentTool == .pen)
        setActiveBackground(textButton, active: controller.currentTool == .text)
        setActiveBackground(arrowButton, active: controller.currentTool == .arrow)
    }

    private func setActiveBackground(_ button: NSButton, active: Bool) {
        button.wantsLayer = true
        button.layer?.cornerRadius = 4
        button.layer?.backgroundColor = active
            ? NSColor.controlAccentColor.withAlphaComponent(0.25).cgColor
            : NSColor.clear.cgColor
    }

    private func makeSwatchImage(r: Double, g: Double, b: Double) -> NSImage {
        let size = NSSize(width: 22, height: 22)
        let img = NSImage(size: size)
        img.lockFocus()
        NSColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 3, yRadius: 3).fill()
        img.unlockFocus()
        return img
    }

    internal private(set) var currentHideGlyphName: String = "eye"
    internal private(set) var currentAutoFadeGlyphName: String = "timer"

    /// Builds an SF Symbol image. When `withRedX` is true, palette rendering
    /// colors the secondary layer (the slash on `eye.slash` or the X badge on
    /// `clock.badge.xmark`) red while the base symbol keeps the label color.
    private func icon(named name: String, withRedX: Bool, accessibilityDescription: String?) -> NSImage? {
        if withRedX {
            let config = NSImage.SymbolConfiguration(paletteColors: [.labelColor, .systemRed])
            return NSImage(systemSymbolName: name, accessibilityDescription: accessibilityDescription)?
                .withSymbolConfiguration(config)
        }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: accessibilityDescription)
        image?.isTemplate = true
        return image
    }

    private func updateHideButtonGlyph(visible: Bool) {
        let name = visible ? "eye" : "eye.slash"
        currentHideGlyphName = name
        hideButton.image = icon(named: name, withRedX: !visible,
                                accessibilityDescription: visible ? "Hide" : "Show")
        hideButton.toolTip = visible ? "Hide drawings — h" : "Show drawings — h"
        // Active = hiding is engaged (drawings not visible).
        setActiveBackground(hideButton, active: !visible)
    }

    private func updateAutoFadeGlyph(enabled: Bool) {
        let name = enabled ? "clock" : "clock.badge.xmark"
        currentAutoFadeGlyphName = name
        autoFadeButton.image = icon(named: name, withRedX: !enabled,
                                    accessibilityDescription: "Auto-fade drawings")
        autoFadeButton.toolTip = enabled ? "Auto-fade on — f" : "Auto-fade off — f"
        // Active = auto-fade timer is running.
        setActiveBackground(autoFadeButton, active: enabled)
    }

    // MARK: - Actions

    @objc private func penClicked(_ sender: NSButton) {
        controller.currentTool = .pen
    }

    @objc private func textClicked(_ sender: NSButton) {
        controller.currentTool = .text
    }

    @objc private func arrowClicked(_ sender: NSButton) {
        controller.currentTool = .arrow
    }

    @objc private func colorClicked(_ sender: NSButton) {
        let c = QuickPickPalette.colors[sender.tag]
        let a = controller.currentColor.a
        controller.currentColor = RGBA(r: c.r, g: c.g, b: c.b, a: a)
    }

    @objc private func openColorPanel() {
        let panel = NSColorPanel.shared
        let cur = controller.currentColor
        panel.color = NSColor(srgbRed: CGFloat(cur.r), green: CGFloat(cur.g),
                              blue: CGFloat(cur.b), alpha: 1)
        panel.setTarget(self)
        panel.setAction(#selector(colorPanelChanged(_:)))
        panel.isContinuous = true
        panel.orderFront(nil)
    }

    @objc private func colorPanelChanged(_ sender: NSColorPanel) {
        // Convert to sRGB so component access is well-defined; keep the user's
        // current alpha (opacity is the opacity control's job, not the wheel's).
        guard let c = sender.color.usingColorSpace(.sRGB) else { return }
        let a = controller.currentColor.a
        controller.currentColor = RGBA(r: Double(c.redComponent), g: Double(c.greenComponent),
                                       b: Double(c.blueComponent), a: a)
    }

    /// A 12-wedge rainbow wheel image for the custom-color button.
    private func makeColorWheelImage(diameter: CGFloat) -> NSImage {
        let img = NSImage(size: NSSize(width: diameter, height: diameter))
        img.lockFocus()
        let center = NSPoint(x: diameter / 2, y: diameter / 2)
        let wedges = 12
        for i in 0..<wedges {
            let path = NSBezierPath()
            path.move(to: center)
            path.appendArc(withCenter: center, radius: diameter / 2,
                           startAngle: CGFloat(i) / CGFloat(wedges) * 360,
                           endAngle: CGFloat(i + 1) / CGFloat(wedges) * 360)
            path.close()
            NSColor(hue: CGFloat(i) / CGFloat(wedges), saturation: 0.85, brightness: 0.95, alpha: 1).setFill()
            path.fill()
        }
        img.unlockFocus()
        return img
    }

    @objc private func toggleHide(_ sender: NSButton) {
        controller.drawingsVisible.toggle()
    }

    @objc private func autoFadeClicked(_ sender: NSButton) {
        controller.autoFadeEnabled.toggle()
        defaults.set(controller.autoFadeEnabled, forKey: "fiti.autoFade")
    }

    // MARK: - Persistence

    private func loadPersistedState() {
        if let r = defaults.object(forKey: "fiti.color.r") as? Double,
           let g = defaults.object(forKey: "fiti.color.g") as? Double,
           let b = defaults.object(forKey: "fiti.color.b") as? Double,
           let a = defaults.object(forKey: "fiti.color.a") as? Double {
            controller.currentColor = RGBA(r: r, g: g, b: b, a: a)
        }
        if let w = defaults.object(forKey: "fiti.width") as? Double {
            controller.currentWidth = w
        }
        if defaults.bool(forKey: "fiti.autoFade") {
            controller.autoFadeEnabled = true
        }
    }

    private func persistColor() {
        let c = controller.currentColor
        defaults.set(c.r, forKey: "fiti.color.r")
        defaults.set(c.g, forKey: "fiti.color.g")
        defaults.set(c.b, forKey: "fiti.color.b")
        defaults.set(c.a, forKey: "fiti.color.a")
    }

    // MARK: - Test hooks

    internal func testOnly_clickQuickPick(at index: Int) throws {
        guard index < quickPickButtons.count else { throw TestOnlyError.outOfRange }
        colorClicked(quickPickButtons[index])
    }

    internal func testOnly_swatchTooltip(at index: Int) -> String? {
        guard index < quickPickButtons.count else { return nil }
        return quickPickButtons[index].toolTip
    }

    internal func testOnly_setWidth(_ value: Double) {
        markControl.width = value
        controller.currentWidth = value
    }

    internal func testOnly_setOpacity(_ value: Double) {
        let c = controller.currentColor
        controller.currentColor = RGBA(r: c.r, g: c.g, b: c.b, a: value)
    }

    internal func testOnly_toggleHide() { toggleHide(hideButton) }

    internal func testOnly_clickPen() { penClicked(penButton) }

    internal func testOnly_clickText() { textClicked(textButton) }

    internal func testOnly_clickArrow() { arrowClicked(arrowButton) }

    internal func testOnly_clickAutoFade() {
        autoFadeClicked(autoFadeButton)
    }

    func testOnly_tapSizeUp() { markControl.testOnly_tapSizeUp() }
    func testOnly_tapOpacityUp() { markControl.testOnly_tapOpacityUp() }

    // swiftlint:disable identifier_name
    internal var testOnly_markColor: RGBA { markControl.testOnly_color }
    internal var testOnly_widthSliderValue: Double { markControl.width }
    internal var testOnly_hideButtonGlyphName: String { currentHideGlyphName }
    internal var testOnly_autoFadeGlyphName: String { currentAutoFadeGlyphName }
    internal var testOnly_customColorTooltip: String? { customColorButton.toolTip }
    internal var testOnly_widthSliderTooltip: String? { markControl.testOnly_sizeTooltip }
    internal var testOnly_opacitySliderTooltip: String? { markControl.testOnly_opacityTooltip }
    internal var testOnly_hideButtonTooltip: String? { hideButton.toolTip }
    internal var testOnly_autoFadeTooltip: String? { autoFadeButton.toolTip }
    internal var testOnly_widthLabelText: String { markControl.testOnly_sizeLabelText }
    internal var testOnly_opacityLabelText: String { markControl.testOnly_opacityLabelText }
    internal var testOnly_activeSwatchIndex: Int? { activeSwatchIndex }
    internal var testOnly_customColorActiveBackground: Bool { hasActiveBackground(customColorButton) }
    internal var testOnly_penTooltip: String? { penButton.toolTip }
    internal var testOnly_textTooltip: String? { textButton.toolTip }
    internal var testOnly_arrowTooltip: String? { arrowButton.toolTip }
    internal var testOnly_penActiveBackground: Bool { hasActiveBackground(penButton) }
    internal var testOnly_textActiveBackground: Bool { hasActiveBackground(textButton) }
    internal var testOnly_arrowActiveBackground: Bool { hasActiveBackground(arrowButton) }
    internal var testOnly_hideButtonActiveBackground: Bool { hasActiveBackground(hideButton) }
    internal var testOnly_autoFadeActiveBackground: Bool { hasActiveBackground(autoFadeButton) }
    internal var testOnly_sizePickerTool: Tool { markControl.testOnly_previewTool }
    internal var testOnly_sizePickerOutlineOn: Bool { markControl.outlineOn }
    // swiftlint:enable identifier_name

    private func hasActiveBackground(_ button: NSButton) -> Bool {
        guard let cg = button.layer?.backgroundColor else { return false }
        return cg.alpha > 0
    }
}

internal enum TestOnlyError: Error { case outOfRange }
