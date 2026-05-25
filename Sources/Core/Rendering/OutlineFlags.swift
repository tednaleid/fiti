// ABOUTME: Per-tool outline on/off flags threaded through the renderer; resolves
// ABOUTME: whether a given item's type should draw its contrast halo.

public struct OutlineFlags: Equatable, Sendable {
    public var text: Bool
    public var arrow: Bool
    public var pen: Bool

    public init(text: Bool, arrow: Bool, pen: Bool) {
        self.text = text
        self.arrow = arrow
        self.pen = pen
    }

    /// All tools off — the default for callers that don't opt in.
    public static let none = OutlineFlags(text: false, arrow: false, pen: false)

    /// Whether the outline is enabled for this item's tool type.
    public func enabled(for item: CanvasItem) -> Bool {
        switch item {
        case .text: return text
        case .arrow: return arrow
        case .stroke: return pen
        }
    }
}
