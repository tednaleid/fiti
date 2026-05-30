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

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
        refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

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
    // swiftlint:enable identifier_name
}
