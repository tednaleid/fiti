// ABOUTME: Port for the global outline/halo render-mode toggle. AppKit backs it with
// ABOUTME: UserDefaults; tests and default wiring use the in-memory DefaultOutlineSettings.

/// Whether marks render with a contrasting halo. Read live by the renderer; a
/// global, non-destructive render mode (the document model is unchanged).
@MainActor
public protocol OutlineSettings: AnyObject {
    var outlineEnabled: Bool { get set }
}

/// In-memory `OutlineSettings`. Production injects a persistent adapter; tests
/// inject this with an explicit value.
@MainActor
public final class DefaultOutlineSettings: OutlineSettings {
    public var outlineEnabled: Bool
    public init(outlineEnabled: Bool = false) {
        self.outlineEnabled = outlineEnabled
    }
}
