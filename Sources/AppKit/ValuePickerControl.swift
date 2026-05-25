// ABOUTME: Toolbar size/opacity control. − / + edge zones step presets, center opens
// ABOUTME: a vertical preset menu; size shows a proportional, clipped, outline-aware glyph.

import AppKit

@MainActor
final class ValuePickerControl: NSView, NSPopoverDelegate {
    enum Kind { case size, opacity }
    enum Zone: Equatable { case decrement, increment, menu }

    private let kind: Kind
    private let presets: [Double]
    private(set) var value: Double
    var onPick: ((Double) -> Void)?

    var currentTool: Tool = .pen { didSet { needsDisplay = true } }
    var color: RGBA = RGBA(r: 0, g: 0, b: 0, a: 1) { didSet { needsDisplay = true } }
    /// Whether the current tool's outline is enabled. When true the size glyph is
    /// drawn with a contrast outline, matching how the mark will actually render.
    var outlineOn: Bool = false { didSet { needsDisplay = true } }
    var toolTipText: String? { didSet { toolTip = toolTipText } }

    // ── Visual tuning knobs (adjust freely; they only affect the preview) ──
    /// Tap width of each − / + zone at the control edges.
    private let edgeZone: CGFloat = 15
    /// Bottom strip height reserved for the value number.
    private let numberStrip: CGFloat = 12
    /// Pixels-per-unit for each tool's size glyph; large values clip at the edges.
    private let penScale: CGFloat = 1.0     // circle diameter ≈ value
    private let textScale: CGFloat = 2.0    // "T" point size ≈ value × 2
    private let arrowScale: CGFloat = 0.5   // arrow line width ≈ value × 0.5
    /// Preset cell size in the popover menu.
    private let cellSize: CGFloat = 26

    init(kind: Kind, presets: [Double], value: Double) {
        self.kind = kind
        self.presets = presets
        self.value = value
        super.init(frame: NSRect(x: 0, y: 0, width: 64, height: 36))
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 36) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func setValue(_ v: Double) { value = v; needsDisplay = true }

    var displayString: String {
        switch kind {
        case .size: return "\(Int(value.rounded()))"
        case .opacity: return "\(Int((value * 100).rounded()))%"
        }
    }

    // MARK: Interaction

    func zone(forX x: CGFloat) -> Zone {
        if x < edgeZone { return .decrement }
        if x > bounds.width - edgeZone { return .increment }
        return .menu
    }

    override func mouseDown(with event: NSEvent) {
        let x = convert(event.locationInWindow, from: nil).x
        switch zone(forX: x) {
        case .decrement: step(to: previousPreset(before: value, in: presets))
        case .increment: step(to: nextPreset(after: value, in: presets))
        case .menu: presentMenu()
        }
    }

    private func step(to v: Double) {
        setValue(v)
        onPick?(v)
    }

    // MARK: Vertical preset menu

    private var activePopover: NSPopover?

    private func presentMenu() {
        guard activePopover == nil else { return }
        let strip = NSStackView()
        strip.orientation = .vertical
        strip.spacing = 4
        strip.edgeInsets = NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        for (i, preset) in presets.enumerated() {
            let btn = NSButton(title: "", target: self, action: #selector(presetClicked(_:)))
            btn.tag = i
            btn.bezelStyle = .regularSquare
            btn.imagePosition = .imageOnly
            btn.image = cellImage(for: preset)
            strip.addArrangedSubview(btn)
        }
        let vc = NSViewController()
        vc.view = strip
        let pop = NSPopover()
        pop.contentViewController = vc
        pop.behavior = .transient
        pop.contentSize = strip.fittingSize
        pop.delegate = self
        activePopover = pop
        pop.show(relativeTo: bounds, of: self, preferredEdge: .maxX)
    }

    func popoverDidClose(_ notification: Notification) { activePopover = nil }

    @objc private func presetClicked(_ sender: NSButton) {
        let v = presets[sender.tag]
        setValue(v)
        onPick?(v)
        activePopover?.close()
        activePopover = nil
    }

    private func cellImage(for preset: Double) -> NSImage {
        let img = NSImage(size: NSSize(width: cellSize, height: cellSize))
        img.lockFocus()
        let region = NSRect(x: 0, y: 0, width: cellSize, height: cellSize)
        switch kind {
        case .opacity: drawOpacityLozenge(in: region.insetBy(dx: 2, dy: 7), alpha: preset)
        case .size: drawSizeGlyph(in: region, value: preset)
        }
        img.unlockFocus()
        return img
    }

    // MARK: Drawing

    /// The center region (between the − / + zones, above the number strip) that
    /// holds the glyph or lozenge.
    private var glyphRegion: NSRect {
        NSRect(x: edgeZone, y: numberStrip,
               width: max(1, bounds.width - 2 * edgeZone), height: max(1, bounds.height - numberStrip))
    }

    override func draw(_ dirtyRect: NSRect) {
        drawEdges()
        switch kind {
        case .opacity: drawOpacityLozenge(in: glyphRegion.insetBy(dx: 2, dy: 5), alpha: value)
        case .size: drawSizeGlyph(in: glyphRegion, value: value)
        }
        drawNumber()
    }

    private func drawEdges() {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let midY = glyphRegion.midY
        let minus = "−" as NSString
        let plus = "+" as NSString
        let mh = minus.size(withAttributes: attrs).height
        minus.draw(at: NSPoint(x: 3, y: midY - mh / 2), withAttributes: attrs)
        let psz = plus.size(withAttributes: attrs)
        plus.draw(at: NSPoint(x: bounds.width - psz.width - 3, y: midY - psz.height / 2),
                  withAttributes: attrs)
    }

    private func drawNumber() {
        let text = displayString as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9),
            .foregroundColor: NSColor.labelColor
        ]
        let sz = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: (bounds.width - sz.width) / 2, y: 1), withAttributes: attrs)
    }

    /// Draws the tool glyph at a size proportional to `value`, clipped to `region`
    /// so large values show only the part that fits. Outlined when `outlineOn`.
    private func drawSizeGlyph(in region: NSRect, value: Double) {
        guard let ctx = NSGraphicsContext.current else { return }
        ctx.saveGraphicsState()
        NSBezierPath(rect: region).addClip()
        defer { ctx.restoreGraphicsState() }

        let cx = region.midX, cy = region.midY
        let fill = NSColor(srgbRed: color.r, green: color.g, blue: color.b, alpha: 1)
        let o = CursorSpec.outlineColor(for: color)
        let outline = NSColor(srgbRed: o.r, green: o.g, blue: o.b, alpha: 1)

        switch currentTool {
        case .pen, .selection:
            let d = max(2, CGFloat(value) * penScale)
            let rect = NSRect(x: cx - d / 2, y: cy - d / 2, width: d, height: d)
            if outlineOn {
                outline.setStroke()
                let ring = NSBezierPath(ovalIn: rect)
                ring.lineWidth = 3
                ring.stroke()
            }
            fill.setFill()
            NSBezierPath(ovalIn: rect).fill()

        case .arrow:
            let lw = max(1, CGFloat(value) * arrowScale)
            let half = region.width / 2 - 2
            let line = NSBezierPath()
            line.move(to: NSPoint(x: cx - half, y: cy))
            line.line(to: NSPoint(x: cx + half, y: cy))
            line.lineCapStyle = .round
            if outlineOn {
                outline.setStroke()
                line.lineWidth = lw + 3
                line.stroke()
            }
            fill.setStroke()
            line.lineWidth = lw
            line.stroke()

        case .text:
            let pt = max(8, CGFloat(value) * textScale)
            var attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: pt),
                .foregroundColor: fill
            ]
            if outlineOn {
                attrs[.strokeColor] = outline
                attrs[.strokeWidth] = -8.0   // negative = fill + stroke (outlined glyph)
            }
            let s = "T" as NSString
            let sz = s.size(withAttributes: attrs)
            s.draw(at: NSPoint(x: cx - sz.width / 2, y: cy - sz.height / 2), withAttributes: attrs)
        }
    }

    private func drawOpacityLozenge(in rect: NSRect, alpha: Double) {
        guard let ctx = NSGraphicsContext.current else { return }
        let path = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        ctx.saveGraphicsState()
        path.addClip()
        NSColor.white.setFill(); rect.fill()
        NSColor(white: 0.8, alpha: 1).setFill()
        let w = rect.width / 2, h = rect.height / 2
        NSRect(x: rect.minX, y: rect.minY, width: w, height: h).fill()
        NSRect(x: rect.midX, y: rect.midY, width: w, height: h).fill()
        NSColor(srgbRed: color.r, green: color.g, blue: color.b, alpha: CGFloat(alpha)).setFill()
        rect.fill()
        ctx.restoreGraphicsState()
    }

    // MARK: Test hooks

    // swiftlint:disable identifier_name
    var testOnly_displayString: String { displayString }
    func testOnly_zone(forX x: CGFloat) -> Zone { zone(forX: x) }
    func testOnly_acceptsFirstMouse() -> Bool { acceptsFirstMouse(for: nil) }
    func testOnly_step(_ zone: Zone) {
        switch zone {
        case .decrement: step(to: previousPreset(before: value, in: presets))
        case .increment: step(to: nextPreset(after: value, in: presets))
        case .menu: break
        }
    }
    func testOnly_selectPreset(at index: Int) {
        let v = presets[index]
        setValue(v)
        onPick?(v)
    }
    // swiftlint:enable identifier_name
}
