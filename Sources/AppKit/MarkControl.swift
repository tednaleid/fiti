// ABOUTME: Combined toolbar control — "− size +" and "− opacity +" stepper rows around
// ABOUTME: a live preview of the current mark, rendered through fiti's real pipeline.

import AppKit

@MainActor
final class MarkControl: NSView {
    var onWidth: ((Double) -> Void)?
    var onOpacity: ((Double) -> Void)?

    var color: RGBA = RGBA(r: 0, g: 0, b: 0, a: 1) { didSet { refresh() } }
    var width: Double = 6 { didSet { refresh() } }
    var outlineOn: Bool = false { didSet { refresh() } }
    /// The active tool. `.selection` is ignored (a meta tool), so the preview keeps
    /// showing the drawing tool "behind" it.
    var currentTool: Tool = .pen {
        didSet { if currentTool != .selection { previewTool = currentTool; refresh() } }
    }
    private var previewTool: Tool = .pen

    private let previewCanvas = Size(width: 60, height: 140)
    /// Fixed pen/arrow length, centered in the (taller) preview so the mark's
    /// ends show with margin; thickness/size still varies with `width`.
    private let markLength: Double = 66
    private let preview = NSImageView()
    private let sizeLabel = NSTextField(labelWithString: "size")
    private let opacityLabel = NSTextField(labelWithString: "opacity")
    private let sizeMinus = MarkControl.stepper("−")
    private let sizePlus = MarkControl.stepper("+")
    private let opacityMinus = MarkControl.stepper("−")
    private let opacityPlus = MarkControl.stepper("+")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
        refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    private static func stepper(_ title: String) -> NSButton {
        let b = NSButton(title: title, target: nil, action: nil)
        b.isBordered = false
        b.font = .systemFont(ofSize: 15, weight: .medium)
        return b
    }

    private func build() {
        sizeMinus.target = self; sizeMinus.action = #selector(sizeDown)
        sizePlus.target = self; sizePlus.action = #selector(sizeUp)
        opacityMinus.target = self; opacityMinus.action = #selector(opacityDown)
        opacityPlus.target = self; opacityPlus.action = #selector(opacityUp)
        sizeLabel.toolTip = "Size — s / S"
        opacityLabel.toolTip = "Opacity — o / O"

        preview.imageScaling = .scaleNone   // draw at real size; the render already clips

        let stack = NSStackView(views: [row(sizeMinus, sizeLabel, sizePlus),
                                        preview,
                                        row(opacityMinus, opacityLabel, opacityPlus)])
        stack.orientation = .vertical
        stack.spacing = 3
        stack.alignment = .centerX
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            preview.widthAnchor.constraint(equalToConstant: CGFloat(previewCanvas.width)),
            preview.heightAnchor.constraint(equalToConstant: CGFloat(previewCanvas.height))
        ])
    }

    private func row(_ minus: NSButton, _ label: NSTextField, _ plus: NSButton) -> NSStackView {
        label.font = .systemFont(ofSize: 11)
        label.alignment = .center
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [minus, label, plus])
        row.orientation = .horizontal
        row.spacing = 2
        row.distribution = .fill
        row.widthAnchor.constraint(equalToConstant: CGFloat(previewCanvas.width)).isActive = true
        return row
    }

    @objc private func sizeUp() { onWidth?(nextPreset(after: width, in: ValuePresets.sizes)) }
    @objc private func sizeDown() { onWidth?(previousPreset(before: width, in: ValuePresets.sizes)) }
    @objc private func opacityUp() { onOpacity?(nextPreset(after: color.a, in: ValuePresets.opacities)) }
    @objc private func opacityDown() { onOpacity?(previousPreset(before: color.a, in: ValuePresets.opacities)) }

    private func refresh() {
        preview.image = renderPreview()
        sizeMinus.isEnabled = previousPreset(before: width, in: ValuePresets.sizes) < width
        sizePlus.isEnabled = nextPreset(after: width, in: ValuePresets.sizes) > width
        opacityMinus.isEnabled = previousPreset(before: color.a, in: ValuePresets.opacities) < color.a
        opacityPlus.isEnabled = nextPreset(after: color.a, in: ValuePresets.opacities) > color.a
    }

    private func renderPreview() -> NSImage? {
        let flags = OutlineFlags(text: previewTool == .text && outlineOn,
                                 arrow: previewTool == .arrow && outlineOn,
                                 pen: previewTool == .pen && outlineOn)
        let frame = RenderFrame(items: [previewItem()], inProgress: nil, canvasSize: previewCanvas)
        return SnapshotRenderer.image(from: frame, scale: 2, outline: flags)
    }

    private func previewItem() -> CanvasItem {
        let w = previewCanvas.width, h = previewCanvas.height
        let cx = w / 2, midY = h / 2, half = markLength / 2
        switch previewTool {
        case .arrow:
            return .arrow(ArrowItem(id: "preview", color: color, width: width, transform: .identity,
                                    tail: Point(x: cx, y: midY + half), head: Point(x: cx, y: midY - half),
                                    createdAt: 0))
        case .text:
            let fs = width * 4
            // Center a single "A" using its measured glyph box; large sizes clip
            // symmetrically (negative offsets) so the A stays centered.
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
            // Vertical freehand wave of fixed length, centered.
            let pts = [(cx, midY - half), (cx - 6, midY - half * 0.25),
                       (cx + 5, midY + half * 0.35), (cx - 2, midY + half)]
                .map { StrokePoint(x: $0.0, y: $0.1) }
            return .stroke(Stroke(id: "preview", color: color, width: width, transform: .identity,
                                  points: pts, pointerType: .mouse, pressureEnabled: false, createdAt: 0))
        }
    }

    // MARK: Test hooks

    // swiftlint:disable identifier_name
    func testOnly_tapSizeUp() { sizeUp() }
    func testOnly_tapSizeDown() { sizeDown() }
    func testOnly_tapOpacityUp() { opacityUp() }
    func testOnly_tapOpacityDown() { opacityDown() }
    var testOnly_sizeMinusEnabled: Bool { sizeMinus.isEnabled }
    var testOnly_sizePlusEnabled: Bool { sizePlus.isEnabled }
    var testOnly_opacityMinusEnabled: Bool { opacityMinus.isEnabled }
    var testOnly_opacityPlusEnabled: Bool { opacityPlus.isEnabled }
    var testOnly_previewTool: Tool { previewTool }
    var testOnly_color: RGBA { color }
    var testOnly_hasPreviewImage: Bool { preview.image != nil }
    var testOnly_sizeLabelText: String { sizeLabel.stringValue }
    var testOnly_opacityLabelText: String { opacityLabel.stringValue }
    var testOnly_sizeTooltip: String? { sizeLabel.toolTip }
    var testOnly_opacityTooltip: String? { opacityLabel.toolTip }
    // swiftlint:enable identifier_name
}
