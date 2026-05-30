// ABOUTME: 60x140 live mark preview rendered through SnapshotRenderer — the same image
// ABOUTME: shown in the toolbar and inside each PresetPopover cell. No interaction.

import AppKit

@MainActor
final class MarkPreview: NSView {
    static let canvasSize = Size(width: 60, height: 140)
    private static let markLength: Double = 66

    var color: RGBA = RGBA(r: 0, g: 0, b: 0, a: 1) { didSet { refresh() } }
    var width: Double = 6 { didSet { refresh() } }
    var outlineOn: Bool = false { didSet { refresh() } }
    /// The active tool. `.selection` is a meta tool; the preview keeps the
    /// drawing tool that was set before it.
    var currentTool: Tool = .pen {
        didSet { if currentTool != .selection { previewTool = currentTool; refresh() } }
    }
    private(set) var previewTool: Tool = .pen
    private let imageView = NSImageView()
    /// Overlay drawn over the hovered half (size = top, opacity = bottom) as a
    /// brighter-accent ring, matching the buttons' mouseover affordance.
    private let hoverOverlay = NSView()
    private var hoverArea: NSTrackingArea?
    private var hoveredAxis: PresetAxis?

    /// Fired when the user clicks the preview: top half → `.size`, bottom half → `.opacity`.
    var onHalfClick: ((PresetAxis) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
        refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    // The preview is one click target split in half; keep the image view from
    // swallowing the click, and fire on the first mouse so it works while the
    // app is inactive (same as the toolbar's FirstMouseButtons).
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let y = convert(event.locationInWindow, from: nil).y
        onHalfClick?(Self.axis(forY: y, height: bounds.height))
    }

    override func mouseMoved(with event: NSEvent) {
        let y = convert(event.locationInWindow, from: nil).y
        setHoveredAxis(Self.axis(forY: y, height: bounds.height))
    }
    override func mouseExited(with event: NSEvent) { setHoveredAxis(nil) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = hoverArea { removeTrackingArea(area) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    private func setHoveredAxis(_ axis: PresetAxis?) {
        guard axis != hoveredAxis else { return }
        hoveredAxis = axis
        guard let axis else { hoverOverlay.isHidden = true; return }
        // Non-flipped: the top half (size) is the upper y range.
        let half = bounds.height / 2
        hoverOverlay.frame = NSRect(x: 0, y: axis == .size ? half : 0,
                                    width: bounds.width, height: half).insetBy(dx: 1, dy: 1)
        hoverOverlay.isHidden = false
    }

    /// Which axis a click at `y` (view coords, non-flipped) targets: the top half
    /// (y at or above the midpoint) is size, the bottom half is opacity.
    static func axis(forY y: CGFloat, height: CGFloat) -> PresetAxis {
        y >= height / 2 ? .size : .opacity
    }

    private func build() {
        imageView.imageScaling = .scaleNone   // the renderer already produces real-sized pixels
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            widthAnchor.constraint(equalToConstant: CGFloat(Self.canvasSize.width)),
            heightAnchor.constraint(equalToConstant: CGFloat(Self.canvasSize.height))
        ])

        // Hover ring overlay, on top of the image, hidden until a half is hovered.
        hoverOverlay.wantsLayer = true
        hoverOverlay.layer?.cornerRadius = 4
        hoverOverlay.layer?.borderWidth = 1.5
        hoverOverlay.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.9).cgColor
        hoverOverlay.isHidden = true
        addSubview(hoverOverlay)   // added after imageView → draws on top
    }

    private func refresh() {
        imageView.image = Self.render(tool: previewTool, color: color, width: width,
                                      outlineOn: outlineOn)
    }

    /// Build a `SnapshotRenderer` image for the given parameters at the standard preview
    /// canvas size. Internal so `PresetPopover` cells reuse the exact same pipeline.
    static func render(tool: Tool, color: RGBA, width: Double, outlineOn: Bool) -> NSImage? {
        let flags = OutlineFlags(text: tool == .text && outlineOn,
                                 arrow: tool == .arrow && outlineOn,
                                 pen: tool == .pen && outlineOn)
        let frame = RenderFrame(items: [previewItem(tool: tool, color: color, width: width)],
                                inProgress: nil, canvasSize: canvasSize)
        return SnapshotRenderer.image(from: frame, scale: 2, outline: flags)
    }

    private static func previewItem(tool: Tool, color: RGBA, width: Double) -> CanvasItem {
        let w = canvasSize.width, h = canvasSize.height
        let cx = w / 2, midY = h / 2, half = markLength / 2
        switch tool {
        case .arrow:
            return .arrow(ArrowItem(id: "preview", color: color, width: width, transform: .identity,
                                    tail: Point(x: cx, y: midY + half),
                                    head: Point(x: cx, y: midY - half),
                                    createdAt: 0))
        case .text:
            let fs = width * 4
            let font = NSFont(name: "Helvetica", size: CGFloat(fs)) ?? .systemFont(ofSize: CGFloat(fs))
            let glyph = ("A" as NSString).size(withAttributes: [.font: font])
            return .text(TextItem(id: "preview", string: "A", fontName: "Helvetica", fontSize: fs,
                                  color: color,
                                  transform: Transform(x: (w - Double(glyph.width)) / 2,
                                                       y: (h - Double(glyph.height)) / 2,
                                                       scale: 1, rotate: 0),
                                  bounds: Size(width: Double(glyph.width), height: Double(glyph.height)),
                                  createdAt: 0))
        case .pen, .selection:
            let pts = [(cx, midY - half), (cx - 6, midY - half * 0.25),
                       (cx + 5, midY + half * 0.35), (cx - 2, midY + half)]
                .map { StrokePoint(x: $0.0, y: $0.1) }
            return .stroke(Stroke(id: "preview", color: color, width: width, transform: .identity,
                                  points: pts, pointerType: .mouse, pressureEnabled: false,
                                  createdAt: 0))
        }
    }

    // MARK: Test hooks

    // swiftlint:disable identifier_name
    var testOnly_hasPreviewImage: Bool { imageView.image != nil }
    var testOnly_previewTool: Tool { previewTool }
    func testOnly_click(atY y: CGFloat) { onHalfClick?(Self.axis(forY: y, height: bounds.height)) }
    // swiftlint:enable identifier_name
}
