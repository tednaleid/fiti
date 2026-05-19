// ABOUTME: Floating toolbar that appears when fiti activates. Owns color /
// ABOUTME: width / opacity / hide controls; writes through to AppController.

import AppKit

@MainActor
public final class ToolbarController: NSObject {
    private let controller: AppController
    private let defaults: UserDefaults
    internal let panel: ToolbarPanel

    private let colorWell: NSColorWell
    private let widthSlider: NSSlider
    private let opacitySlider: NSSlider
    private let hideButton: NSButton
    private let autoFadeButton = NSButton(title: "", target: nil, action: nil)
    private var quickPickButtons: [NSButton] = []

    // swiftlint:disable large_tuple comma
    /// 8 quick-pick colors from `../scratch/scratch/packages/web/src/ui/Toolbar.tsx`.
    /// RGB only — alpha is taken from the user's current opacity at click time.
    private static let quickPickRGB: [(r: Double, g: Double, b: Double)] = [
        (0.0, 0.0, 0.0),
        (134.0 / 255.0, 142.0 / 255.0, 150.0 / 255.0),
        (224.0 / 255.0,  49.0 / 255.0,  49.0 / 255.0),
        (247.0 / 255.0, 103.0 / 255.0,   7.0 / 255.0),
        (245.0 / 255.0, 159.0 / 255.0,   0.0),
        ( 47.0 / 255.0, 158.0 / 255.0,  68.0 / 255.0),
        ( 25.0 / 255.0, 113.0 / 255.0, 194.0 / 255.0),
        (156.0 / 255.0,  54.0 / 255.0, 181.0 / 255.0)
    ]
    // swiftlint:enable large_tuple comma

    public init(controller: AppController, defaults: UserDefaults = .standard) {
        self.controller = controller
        self.defaults = defaults
        self.panel = ToolbarPanel()
        self.colorWell = NSColorWell()
        self.widthSlider = NSSlider(value: controller.currentWidth, minValue: 1, maxValue: 40, target: nil, action: nil)
        self.opacitySlider = NSSlider(value: controller.currentColor.a, minValue: 0, maxValue: 1, target: nil, action: nil)
        self.hideButton = NSButton(title: "", target: nil, action: nil)
        super.init()

        loadPersistedState()
        buildContent()
        updateVisibility(for: controller.mode)

        // React to external writes (HTTP, other adapters) — keep widgets in sync.
        controller.onCurrentColorChanged = { [weak self] color in
            self?.syncColorWidgets(with: color)
        }
        controller.onCurrentWidthChanged = { [weak self] width in
            self?.widthSlider.doubleValue = width
        }
        controller.onDrawingsVisibilityChanged = { [weak self] visible in
            self?.updateHideButtonGlyph(visible: visible)
        }
        controller.onAutoFadeEnabledChanged = { [weak self] enabled in
            self?.updateAutoFadeGlyph(enabled: enabled)
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
        opacitySlider.doubleValue = color.a
    }

    // swiftlint:disable:next function_body_length
    private func buildContent() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let pen = NSButton(title: "", target: nil, action: nil)
        pen.image = NSImage(systemSymbolName: "pencil.tip", accessibilityDescription: "Pen")
        pen.imagePosition = .imageOnly
        pen.bezelStyle = .regularSquare
        pen.state = .on
        pen.isEnabled = false
        stack.addArrangedSubview(pen)

        for rowStart in stride(from: 0, to: Self.quickPickRGB.count, by: 2) {
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 4
            for offset in 0..<2 where rowStart + offset < Self.quickPickRGB.count {
                let i = rowStart + offset
                let rgb = Self.quickPickRGB[i]
                let btn = NSButton(title: "", target: self, action: #selector(colorClicked(_:)))
                btn.tag = i
                btn.bezelStyle = .regularSquare
                btn.image = makeSwatchImage(r: rgb.r, g: rgb.g, b: rgb.b)
                btn.imagePosition = .imageOnly
                quickPickButtons.append(btn)
                row.addArrangedSubview(btn)
            }
            stack.addArrangedSubview(row)
        }

        colorWell.target = self
        colorWell.action = #selector(customColorChanged(_:))
        colorWell.color = NSColor(red: CGFloat(controller.currentColor.r),
                                  green: CGFloat(controller.currentColor.g),
                                  blue: CGFloat(controller.currentColor.b),
                                  alpha: CGFloat(controller.currentColor.a))
        stack.addArrangedSubview(colorWell)

        widthSlider.target = self
        widthSlider.action = #selector(widthChanged(_:))
        widthSlider.doubleValue = controller.currentWidth
        stack.addArrangedSubview(label("w"))
        stack.addArrangedSubview(widthSlider)

        opacitySlider.target = self
        opacitySlider.action = #selector(opacityChanged(_:))
        opacitySlider.doubleValue = controller.currentColor.a
        stack.addArrangedSubview(label("o"))
        stack.addArrangedSubview(opacitySlider)

        hideButton.target = self
        hideButton.action = #selector(toggleHide(_:))
        hideButton.bezelStyle = .regularSquare
        hideButton.imagePosition = .imageOnly
        hideButton.wantsLayer = true
        hideButton.layer?.cornerRadius = 4
        updateHideButtonGlyph(visible: controller.drawingsVisible)
        stack.addArrangedSubview(hideButton)

        autoFadeButton.target = self
        autoFadeButton.action = #selector(autoFadeClicked(_:))
        autoFadeButton.bezelStyle = .regularSquare
        autoFadeButton.imagePosition = .imageOnly
        autoFadeButton.wantsLayer = true
        autoFadeButton.layer?.cornerRadius = 4
        updateAutoFadeGlyph(enabled: controller.autoFadeEnabled)
        stack.addArrangedSubview(autoFadeButton)
        autoFadeButton.widthAnchor.constraint(equalTo: hideButton.widthAnchor).isActive = true

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])
        panel.contentView = container
    }

    private func label(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: 10)
        l.alignment = .center
        return l
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

    private static let activeBackground = NSColor.systemGreen.withAlphaComponent(0.25).cgColor

    private func updateHideButtonGlyph(visible: Bool) {
        let name = visible ? "eye" : "eye.slash"
        currentHideGlyphName = name
        let image = NSImage(systemSymbolName: name, accessibilityDescription: visible ? "Hide" : "Show")
        image?.isTemplate = true
        hideButton.image = image
        let active = !visible  // hiding is the engaged action
        hideButton.layer?.backgroundColor = active ? Self.activeBackground : nil
        hideButton.contentTintColor = active ? .systemGreen : nil
    }

    private func updateAutoFadeGlyph(enabled: Bool) {
        let name = enabled ? "timer.fill" : "timer"
        currentAutoFadeGlyphName = name
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Auto-fade drawings")
        image?.isTemplate = true
        autoFadeButton.image = image
        autoFadeButton.layer?.backgroundColor = enabled ? Self.activeBackground : nil
        autoFadeButton.contentTintColor = enabled ? .systemGreen : nil
    }

    // MARK: - Actions

    @objc private func colorClicked(_ sender: NSButton) {
        let rgb = Self.quickPickRGB[sender.tag]
        let a = controller.currentColor.a
        controller.currentColor = RGBA(r: rgb.r, g: rgb.g, b: rgb.b, a: a)
        persistColor()
    }

    @objc private func customColorChanged(_ sender: NSColorWell) {
        let c = sender.color
        let a = controller.currentColor.a
        controller.currentColor = RGBA(r: Double(c.redComponent), g: Double(c.greenComponent), b: Double(c.blueComponent), a: a)
        persistColor()
    }

    @objc private func widthChanged(_ sender: NSSlider) {
        controller.currentWidth = sender.doubleValue
        defaults.set(controller.currentWidth, forKey: "fiti.width")
    }

    @objc private func opacityChanged(_ sender: NSSlider) {
        let c = controller.currentColor
        controller.currentColor = RGBA(r: c.r, g: c.g, b: c.b, a: sender.doubleValue)
        persistColor()
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

    internal func testOnly_setWidth(_ value: Double) {
        widthSlider.doubleValue = value
        widthChanged(widthSlider)
    }

    internal func testOnly_setOpacity(_ value: Double) {
        opacitySlider.doubleValue = value
        opacityChanged(opacitySlider)
    }

    internal func testOnly_toggleHide() {
        toggleHide(hideButton)
    }

    internal func testOnly_clickAutoFade() {
        autoFadeClicked(autoFadeButton)
    }

    // swiftlint:disable identifier_name
    internal var testOnly_colorWellColor: NSColor { colorWell.color }
    internal var testOnly_widthSliderValue: Double { widthSlider.doubleValue }
    internal var testOnly_hideButtonGlyphName: String { currentHideGlyphName }
    internal var testOnly_autoFadeGlyphName: String { currentAutoFadeGlyphName }
    // swiftlint:enable identifier_name
}

internal enum TestOnlyError: Error { case outOfRange }
