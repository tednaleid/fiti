// ABOUTME: Floating toolbar that appears when fiti activates. Owns color /
// ABOUTME: width / opacity / hide controls; writes through to AppController.

import AppKit

@MainActor
// swiftlint:disable:next type_body_length
public final class ToolbarController: NSObject {
    private let controller: AppController
    private let defaults: UserDefaults
    internal let panel: ToolbarPanel

    private let penButton = NSButton(title: "", target: nil, action: nil)
    private let textButton = NSButton(title: "", target: nil, action: nil)
    private let arrowButton = NSButton(title: "", target: nil, action: nil)
    private let colorWell: NSColorWell
    private let sizePicker = ValuePickerControl(kind: .size, presets: ValuePresets.sizes, value: 6)
    private let opacityPicker = ValuePickerControl(kind: .opacity, presets: ValuePresets.opacities, value: 0.8)
    private let hideButton: NSButton
    private let autoFadeButton = NSButton(title: "", target: nil, action: nil)
    private var quickPickButtons: [NSButton] = []

    private let widthLabel = NSTextField(labelWithString: "size")
    private let opacityLabel = NSTextField(labelWithString: "opacity")
    private(set) var activeSwatchIndex: Int?

    public init(controller: AppController, defaults: UserDefaults = .standard) {
        self.controller = controller
        self.defaults = defaults
        self.panel = ToolbarPanel()
        self.colorWell = NSColorWell()
        self.hideButton = NSButton(title: "", target: nil, action: nil)
        super.init()

        loadPersistedState()
        buildContent()
        updateVisibility(for: controller.mode)

        sizePicker.setValue(controller.currentWidth)
        sizePicker.color = controller.currentColor
        sizePicker.currentTool = controller.currentTool
        sizePicker.toolTipText = "Size — s / S"
        sizePicker.onPick = { [weak self] v in self?.controller.currentWidth = v }

        opacityPicker.setValue(controller.currentColor.a)
        opacityPicker.color = controller.currentColor
        opacityPicker.toolTipText = "Opacity — o / O"
        opacityPicker.onPick = { [weak self] v in
            guard let self else { return }
            let c = self.controller.currentColor
            self.controller.currentColor = RGBA(r: c.r, g: c.g, b: c.b, a: v)
        }

        // React to external writes (HTTP, other adapters) — keep widgets in sync and persist.
        controller.onCurrentColorChanged = { [weak self] color in
            self?.syncColorWidgets(with: color)
            self?.sizePicker.color = color
            self?.opacityPicker.color = color
            self?.opacityPicker.setValue(color.a)
            self?.persistColor()
        }
        controller.onCurrentWidthChanged = { [weak self] width in
            self?.sizePicker.setValue(width)
            self?.defaults.set(width, forKey: "fiti.width")
        }
        controller.onDrawingsVisibilityChanged = { [weak self] visible in
            self?.updateHideButtonGlyph(visible: visible)
        }
        controller.onAutoFadeEnabledChanged = { [weak self] enabled in
            self?.updateAutoFadeGlyph(enabled: enabled)
        }
        controller.onCurrentToolChanged = { [weak self] tool in
            self?.updateToolHighlights()
            self?.sizePicker.currentTool = tool
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
        colorWell.color = NSColor(red: CGFloat(color.r), green: CGFloat(color.g),
                                  blue: CGFloat(color.b), alpha: CGFloat(color.a))
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

        colorWell.target = self
        colorWell.action = #selector(customColorChanged(_:))
        colorWell.color = NSColor(red: CGFloat(controller.currentColor.r),
                                  green: CGFloat(controller.currentColor.g),
                                  blue: CGFloat(controller.currentColor.b),
                                  alpha: CGFloat(controller.currentColor.a))
        colorWell.toolTip = "Custom color"
        stack.addArrangedSubview(colorWell)

        styleSliderLabel(widthLabel)
        stack.addArrangedSubview(widthLabel)
        stack.addArrangedSubview(sizePicker)

        styleSliderLabel(opacityLabel)
        stack.addArrangedSubview(opacityLabel)
        stack.addArrangedSubview(opacityPicker)

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

    private func styleSliderLabel(_ field: NSTextField) {
        field.font = .systemFont(ofSize: 10)
        field.alignment = .center
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

    @objc private func customColorChanged(_ sender: NSColorWell) {
        let c = sender.color
        let a = controller.currentColor.a
        controller.currentColor = RGBA(r: Double(c.redComponent), g: Double(c.greenComponent), b: Double(c.blueComponent), a: a)
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
        sizePicker.setValue(value)
        controller.currentWidth = value
    }

    internal func testOnly_setOpacity(_ value: Double) {
        opacityPicker.setValue(value)
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

    func testOnly_pickSizePreset(at index: Int) { sizePicker.testOnly_selectPreset(at: index) }
    func testOnly_pickOpacityPreset(at index: Int) { opacityPicker.testOnly_selectPreset(at: index) }

    // swiftlint:disable identifier_name
    internal var testOnly_colorWellColor: NSColor { colorWell.color }
    internal var testOnly_widthSliderValue: Double { sizePicker.value }
    internal var testOnly_hideButtonGlyphName: String { currentHideGlyphName }
    internal var testOnly_autoFadeGlyphName: String { currentAutoFadeGlyphName }
    internal var testOnly_colorWellTooltip: String? { colorWell.toolTip }
    internal var testOnly_widthSliderTooltip: String? { sizePicker.toolTipText }
    internal var testOnly_opacitySliderTooltip: String? { opacityPicker.toolTipText }
    internal var testOnly_hideButtonTooltip: String? { hideButton.toolTip }
    internal var testOnly_autoFadeTooltip: String? { autoFadeButton.toolTip }
    internal var testOnly_widthLabelText: String { widthLabel.stringValue }
    internal var testOnly_opacityLabelText: String { opacityLabel.stringValue }
    internal var testOnly_activeSwatchIndex: Int? { activeSwatchIndex }
    internal var testOnly_penTooltip: String? { penButton.toolTip }
    internal var testOnly_textTooltip: String? { textButton.toolTip }
    internal var testOnly_arrowTooltip: String? { arrowButton.toolTip }
    internal var testOnly_penActiveBackground: Bool { hasActiveBackground(penButton) }
    internal var testOnly_textActiveBackground: Bool { hasActiveBackground(textButton) }
    internal var testOnly_arrowActiveBackground: Bool { hasActiveBackground(arrowButton) }
    internal var testOnly_hideButtonActiveBackground: Bool { hasActiveBackground(hideButton) }
    internal var testOnly_autoFadeActiveBackground: Bool { hasActiveBackground(autoFadeButton) }
    internal var testOnly_sizePickerTool: Tool { sizePicker.currentTool }
    // swiftlint:enable identifier_name

    private func hasActiveBackground(_ button: NSButton) -> Bool {
        guard let cg = button.layer?.backgroundColor else { return false }
        return cg.alpha > 0
    }
}

internal enum TestOnlyError: Error { case outOfRange }
