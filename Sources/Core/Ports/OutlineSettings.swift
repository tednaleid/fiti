// ABOUTME: Port for the per-tool outline/halo render-mode toggles. AppKit backs it with
// ABOUTME: UserDefaults; tests and default wiring use the in-memory DefaultOutlineSettings.

/// Whether marks render with a contrasting halo, independently per tool. Read live
/// by the renderer; a global, non-destructive render mode (the document is unchanged).
@MainActor
public protocol OutlineSettings: AnyObject {
    var textOutline: Bool { get set }
    var arrowOutline: Bool { get set }
    var penOutline: Bool { get set }
}

public extension OutlineSettings {
    /// The flags as a value the renderer can resolve per item type.
    var flags: OutlineFlags {
        OutlineFlags(text: textOutline, arrow: arrowOutline, pen: penOutline)
    }
}

/// In-memory `OutlineSettings`. Production injects a persistent adapter; tests
/// inject this with explicit values. Defaults match the product default:
/// text and arrows outlined, pen not.
@MainActor
public final class DefaultOutlineSettings: OutlineSettings {
    public var textOutline: Bool
    public var arrowOutline: Bool
    public var penOutline: Bool
    public init(textOutline: Bool = true, arrowOutline: Bool = true, penOutline: Bool = false) {
        self.textOutline = textOutline
        self.arrowOutline = arrowOutline
        self.penOutline = penOutline
    }
}
