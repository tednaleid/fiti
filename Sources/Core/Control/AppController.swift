// ABOUTME: Activation state machine. Bridges raw pointer input to Editor
// ABOUTME: calls; owns click-through toggling via WindowControl.

import Foundation

public final class AppController {
    public enum Mode: Equatable, Sendable {
        case inactive
        case activeIdle
        case activeDrawing
    }

    public private(set) var mode: Mode = .inactive
    public let editor: Editor
    private let window: WindowControl

    // Drawing parameters used while in POC. Hardcoded here; the toolbar that
    // mutates these lands in a later phase.
    public var currentColor: RGBA = RGBA(r: 0.20, g: 0.80, b: 0.94, a: 1.0)
    public var currentWidth: Double = 6

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
}
