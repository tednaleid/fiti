// ABOUTME: Toolbar size/opacity composite — two SF-Symbol PresetButtons sandwiching
// ABOUTME: a live MarkPreview. Click on a button opens the matching popover via callback.

import AppKit

@MainActor
final class MarkControl: NSView {
    /// Fired when the user clicks one of the trigger buttons. The rect is the
    /// MarkPreview's bounds converted to the receiver's window's screen coords
    /// (or the preview's bounds when there is no window — used in tests).
    var onOpenPopover: ((PresetAxis, NSRect) -> Void)?

    var color: RGBA = RGBA(r: 0, g: 0, b: 0, a: 1) { didSet { preview.color = color } }
    var width: Double = 6 { didSet { preview.width = width } }
    var outlineOn: Bool = false { didSet { preview.outlineOn = outlineOn } }
    var currentTool: Tool = .pen { didSet { preview.currentTool = currentTool } }

    private let preview = MarkPreview()
    private let sizeButton = PresetButton.make(symbol: "lineweight",
                                               accessibility: "Size",
                                               tooltip: "Size — s / S")
    private let opacityButton = PresetButton.make(symbol: "drop",
                                                  accessibility: "Opacity",
                                                  tooltip: "Opacity — o / O")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    /// The two trigger buttons, exposed so ToolbarController can normalize their
    /// size against the color swatches (the widest toolbar buttons).
    var triggerButtons: [NSButton] { [sizeButton, opacityButton] }

    private func build() {
        sizeButton.target = self
        sizeButton.action = #selector(sizeClicked)
        opacityButton.target = self
        opacityButton.action = #selector(opacityClicked)

        // Top/bottom half of the rendered stroke opens size/opacity, and hovering a
        // half lights that axis's button — signaling which a click would open.
        preview.onHalfClick = { [weak self] axis in self?.triggerOpen(axis) }
        preview.onHalfHover = { [weak self] axis in
            self?.sizeButton.setHoverHighlight(axis == .size)
            self?.opacityButton.setHoverHighlight(axis == .opacity)
        }

        let stack = NSStackView(views: [sizeButton, preview, opacityButton])
        stack.orientation = .vertical
        stack.spacing = 3
        stack.alignment = .centerX
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    @objc private func sizeClicked() { triggerOpen(.size) }
    @objc private func opacityClicked() { triggerOpen(.opacity) }

    /// Open (or toggle) the popover for `axis`, exactly as a trigger-button click does.
    /// Shared by the buttons and the dev HTTP `/popover` route.
    func triggerOpen(_ axis: PresetAxis) {
        onOpenPopover?(axis, previewScreenRect())
    }

    private func previewScreenRect() -> NSRect {
        // When attached to a window, convert preview.bounds to screen coords for the
        // popover anchor. Otherwise (tests without a window), resolve the preview's
        // fixed-size constraints and return its local bounds — a caller that needs a
        // real screen rect must add the view to a window.
        guard let window = preview.window else {
            preview.layoutSubtreeIfNeeded()
            return preview.bounds
        }
        let inWindow = preview.convert(preview.bounds, to: nil)
        return window.convertToScreen(inWindow)
    }

    // MARK: Trigger highlight (driven by ToolbarController as popover open/close cycles)

    func setSizeButtonActive(_ active: Bool) { setActiveBackground(sizeButton, active: active) }
    func setOpacityButtonActive(_ active: Bool) { setActiveBackground(opacityButton, active: active) }

    private func setActiveBackground(_ button: NSButton, active: Bool) {
        button.wantsLayer = true
        button.layer?.cornerRadius = 4
        button.layer?.backgroundColor = active
            ? NSColor.controlAccentColor.withAlphaComponent(0.25).cgColor
            : NSColor.clear.cgColor
    }

    // MARK: Test hooks

    // swiftlint:disable identifier_name
    func testOnly_clickSizeButton() { sizeClicked() }
    func testOnly_clickOpacityButton() { opacityClicked() }
    var testOnly_previewTool: Tool { preview.testOnly_previewTool }
    var testOnly_hasPreviewImage: Bool { preview.testOnly_hasPreviewImage }
    var testOnly_color: RGBA { color }
    var testOnly_sizeButtonTooltip: String? { sizeButton.toolTip }
    var testOnly_opacityButtonTooltip: String? { opacityButton.toolTip }
    var testOnly_sizeButtonActive: Bool { hasActive(sizeButton) }
    var testOnly_opacityButtonActive: Bool { hasActive(opacityButton) }
    // swiftlint:enable identifier_name

    private func hasActive(_ button: NSButton) -> Bool {
        guard let cg = button.layer?.backgroundColor else { return false }
        return cg.alpha > 0
    }
}
