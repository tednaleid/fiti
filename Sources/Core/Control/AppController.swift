// ABOUTME: Activation state machine. Bridges raw pointer input to Editor
// ABOUTME: calls; owns click-through toggling via WindowControl.

import Foundation

@MainActor
public final class AppController {
    public enum Mode: Equatable, Sendable {
        case inactive
        case activeIdle
        case activeDrawing
    }

    public var onModeChanged: ((Mode) -> Void)?

    public private(set) var mode: Mode = .inactive {
        didSet {
            if oldValue != mode { onModeChanged?(mode) }
        }
    }

    public var onDrawingsVisibilityChanged: ((Bool) -> Void)?

    public var drawingsVisible: Bool = true {
        didSet {
            if oldValue != drawingsVisible { onDrawingsVisibilityChanged?(drawingsVisible) }
        }
    }

    public let editor: Editor
    private let window: WindowControl

    // Drawing parameters. Each has a didSet publisher so HTTP writes and
    // toolbar-widget writes both notify other adapters that need to react
    // (toolbar widgets, snapshot consumers, etc.).
    public var onCurrentColorChanged: ((RGBA) -> Void)?
    public var onCurrentWidthChanged: ((Double) -> Void)?

    // Default: red #e03131 from the toolbar's quick-pick palette, at 0.8
    // opacity so the slider is immediately discoverable. UserDefaults
    // overrides this when the toolbar reads persisted state at launch.
    public var currentColor: RGBA = RGBA(r: 224.0 / 255.0, g: 49.0 / 255.0, b: 49.0 / 255.0, a: 0.8) {
        didSet {
            if oldValue != currentColor { onCurrentColorChanged?(currentColor) }
        }
    }
    public var currentWidth: Double = 6 {
        didSet {
            if oldValue != currentWidth { onCurrentWidthChanged?(currentWidth) }
        }
    }

    public init(editor: Editor, window: WindowControl) {
        self.editor = editor
        self.window = window
    }

    public func activate() {
        guard mode == .inactive else { return }
        mode = .activeIdle
        window.setClickThrough(false)
        window.focus()
    }

    public func deactivate() {
        guard mode != .inactive else { return }
        if mode == .activeDrawing { editor.endStroke() }
        mode = .inactive
        window.setClickThrough(true)
    }

    public func toggle() {
        if mode == .inactive { activate() } else { deactivate() }
    }

    public func pointerDown(_ point: StrokePoint) {
        guard mode == .activeIdle else { return }
        _ = editor.startStroke(color: currentColor, width: currentWidth, pointerType: .mouse)
        editor.appendPoint(point)
        mode = .activeDrawing
    }

    public func pointerMoved(_ point: StrokePoint) {
        guard mode == .activeDrawing else { return }
        editor.appendPoint(point)
    }

    public func pointerUp() {
        guard mode == .activeDrawing else { return }
        editor.endStroke()
        mode = .activeIdle
    }

    public func clear() {
        // If a stroke is in progress, end it first so its points are committed
        // before they're cleared (matches the eraseStroke / undo invariant that
        // a snapshot of the doc is consistent after every public method returns).
        if mode == .activeDrawing {
            editor.endStroke()
            mode = .activeIdle
        }
        editor.clear()
    }
}
