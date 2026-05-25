// ABOUTME: Toolbar control showing a tool-aware example + number (size) or a color
// ABOUTME: swatch + percent (opacity), opening a horizontal preset popover on click.

import AppKit

@MainActor
final class ValuePickerControl: NSView, NSPopoverDelegate {
    enum Kind { case size, opacity }

    private let kind: Kind
    private let presets: [Double]
    private(set) var value: Double
    var onPick: ((Double) -> Void)?

    /// Drives the size preview glyph and color. Updating either repaints.
    var currentTool: Tool = .pen { didSet { needsDisplay = true } }
    var color: RGBA = RGBA(r: 0, g: 0, b: 0, a: 1) { didSet { needsDisplay = true } }

    var toolTipText: String? {
        didSet { toolTip = toolTipText }
    }

    private let cellSize: CGFloat = 22

    init(kind: Kind, presets: [Double], value: Double) {
        self.kind = kind
        self.presets = presets
        self.value = value
        super.init(frame: NSRect(x: 0, y: 0, width: 44, height: 24))
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    func setValue(_ v: Double) {
        value = v
        needsDisplay = true
    }

    // MARK: Display

    var displayString: String {
        switch kind {
        case .size: return "\(Int(value.rounded()))"
        case .opacity: return "\(Int((value * 100).rounded()))%"
        }
    }

    /// The collapsed-state example glyph at the current value, scaled to fit `maxSide`.
    func previewImage(maxSide: CGFloat) -> NSImage {
        switch kind {
        case .opacity:
            return swatchImage(alpha: value, side: maxSide)
        case .size:
            switch currentTool {
            case .pen, .selection:
                return scaledToFit(fitiBrushDabImage(color: color, diameter: value, outlineWidth: 1),
                                   maxSide: maxSide)
            case .arrow:
                return scaledToFit(arrowGlyphImage(color: color, width: value), maxSide: maxSide)
            case .text:
                return letterTImage(color: color, fontSize: value * 4, maxSide: maxSide)
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let img = previewImage(maxSide: bounds.height - 2)
        let imgRect = NSRect(x: 2, y: (bounds.height - img.size.height) / 2,
                             width: img.size.width, height: img.size.height)
        img.draw(in: imgRect)
        let text = displayString as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.labelColor
        ]
        let tsize = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: bounds.width - tsize.width - 2,
                              y: (bounds.height - tsize.height) / 2), withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) {
        presentPopover()
    }

    // MARK: Popover

    private var activePopover: NSPopover?

    private func presentPopover() {
        guard activePopover == nil else { return }
        let strip = NSStackView()
        strip.orientation = .horizontal
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
        pop.show(relativeTo: bounds, of: self, preferredEdge: .maxY)
    }

    func popoverDidClose(_ notification: Notification) {
        activePopover = nil
    }

    private func cellImage(for preset: Double) -> NSImage {
        switch kind {
        case .opacity: return swatchImage(alpha: preset, side: cellSize)
        case .size:
            switch currentTool {
            case .pen, .selection:
                return scaledToFit(fitiBrushDabImage(color: color, diameter: preset, outlineWidth: 1), maxSide: cellSize)
            case .arrow:
                return scaledToFit(arrowGlyphImage(color: color, width: preset), maxSide: cellSize)
            case .text:
                return letterTImage(color: color, fontSize: preset * 4, maxSide: cellSize)
            }
        }
    }

    @objc private func presetClicked(_ sender: NSButton) {
        let v = presets[sender.tag]
        setValue(v)
        onPick?(v)
        activePopover?.close()
        activePopover = nil
    }

    // MARK: Glyph drawing

    private func swatchImage(alpha: Double, side: CGFloat) -> NSImage {
        let fill = color
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.white.setFill(); rect.fill()
            NSColor(white: 0.8, alpha: 1).setFill()
            let h = rect.height / 2, w = rect.width / 2
            NSRect(x: 0, y: 0, width: w, height: h).fill()
            NSRect(x: w, y: h, width: w, height: h).fill()
            NSColor(srgbRed: fill.r, green: fill.g, blue: fill.b, alpha: CGFloat(alpha)).setFill()
            rect.fill()
            return true
        }
    }

    private func arrowGlyphImage(color: RGBA, width: Double) -> NSImage {
        let side: CGFloat = 24
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            let p = NSBezierPath()
            p.move(to: NSPoint(x: 3, y: side / 2))
            p.line(to: NSPoint(x: side - 6, y: side / 2))
            p.lineWidth = max(1, CGFloat(width) / 2)
            p.lineCapStyle = .round
            NSColor(srgbRed: color.r, green: color.g, blue: color.b, alpha: color.a).setStroke()
            p.stroke()
            let head = NSBezierPath()
            head.move(to: NSPoint(x: side - 3, y: side / 2))
            head.line(to: NSPoint(x: side - 10, y: side / 2 + 6))
            head.line(to: NSPoint(x: side - 10, y: side / 2 - 6))
            head.close()
            NSColor(srgbRed: color.r, green: color.g, blue: color.b, alpha: color.a).setFill()
            head.fill()
            return true
        }
    }

    private func letterTImage(color: RGBA, fontSize: Double, maxSide: CGFloat) -> NSImage {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: CGFloat(fontSize)),
            .foregroundColor: NSColor(srgbRed: color.r, green: color.g, blue: color.b, alpha: color.a)
        ]
        let s = "T" as NSString
        let natural = s.size(withAttributes: attrs)
        let safe = NSSize(width: max(1, natural.width), height: max(1, natural.height))
        let img = NSImage(size: safe, flipped: false) { _ in
            s.draw(at: .zero, withAttributes: attrs); return true
        }
        return scaledToFit(img, maxSide: maxSide)
    }

    private func scaledToFit(_ image: NSImage, maxSide: CGFloat) -> NSImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxSide, longest > 0 else { return image }
        let scale = maxSide / longest
        let target = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        return NSImage(size: target, flipped: false) { rect in
            image.draw(in: rect); return true
        }
    }

    // MARK: Test hooks

    // swiftlint:disable identifier_name
    var testOnly_displayString: String { displayString }
    func testOnly_selectPreset(at index: Int) {
        let v = presets[index]
        setValue(v)
        onPick?(v)
    }
    func testOnly_previewImage() -> NSImage { previewImage(maxSide: 22) }
    // swiftlint:enable identifier_name
}
