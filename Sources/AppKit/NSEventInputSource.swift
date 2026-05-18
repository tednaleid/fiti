// ABOUTME: AppKit InputSource — wraps an NSView's mouse callbacks and a local
// ABOUTME: NSEvent monitor for Esc / Cmd+K / Cmd+Z / Cmd+Shift+Z. The system-wide
// ABOUTME: activation hotkey is handled by KeyboardShortcutsHotkeys, not here.

import AppKit

public final class NSEventInputSource: InputSource {
    public var onPointerDown: ((StrokePoint) -> Void)?
    public var onPointerMoved: ((StrokePoint) -> Void)?
    public var onPointerUp: (() -> Void)?
    public var onDeactivate: (() -> Void)?
    public var onClear: (() -> Void)?
    public var onUndo: (() -> Void)?
    public var onRedo: (() -> Void)?

    private let view: CanvasInputView
    private var keyMonitor: Any?

    public init(view: CanvasInputView) {
        self.view = view
        view.delegate = self
        installKeyMonitor()
    }

    deinit {
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
    }

    /// Returns true if the event was consumed (caller should drop it).
    public func handleKeyDown(_ event: NSEvent) -> Bool {
        dispatchKey(event,
                    onClear: onClear, onDeactivate: onDeactivate,
                    onUndo: onUndo, onRedo: onRedo)
    }

    private func installKeyMonitor() {
        // Local monitor only — fires when fiti is the focused app. The global
        // activation hotkey is owned by HotkeyRegistry (KeyboardShortcuts), which
        // intercepts the keystroke system-wide and does not need Accessibility
        // permission.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyDown(event) ? nil : event
        }
    }
}

extension NSEventInputSource: CanvasInputDelegate {
    public func canvasInput(_ view: CanvasInputView, mouseDownAt point: CGPoint) {
        onPointerDown?(StrokePoint(x: Double(point.x), y: Double(point.y)))
    }
    public func canvasInput(_ view: CanvasInputView, mouseDraggedAt point: CGPoint) {
        onPointerMoved?(StrokePoint(x: Double(point.x), y: Double(point.y)))
    }
    public func canvasInput(_ view: CanvasInputView, mouseUpAt point: CGPoint) {
        onPointerUp?()
    }
}

// MARK: - Pure key dispatch (testable without installing NSEvent monitors)

/// Inspect a `keyDown` event and invoke whichever callback matches; returns
/// `true` if the event was consumed. Pure logic — no AppKit side effects beyond
/// reading the event. Lifted out of `NSEventInputSource` so tests can exercise
/// dispatch without instantiating the class (which would install a real
/// `NSEvent` monitor as a side effect).
public func dispatchKey(_ event: NSEvent,
                        onClear: (() -> Void)?,
                        onDeactivate: (() -> Void)?,
                        onUndo: (() -> Void)?,
                        onRedo: (() -> Void)?) -> Bool {
    // charactersIgnoringModifiers preserves Shift, so Cmd+Shift+Z arrives with
    // chars == "Z". Lowercase before matching so Shift-bearing combos still hit.
    let chars = event.charactersIgnoringModifiers?.lowercased()
    let cmd = event.modifierFlags.contains(.command)
    let opt = event.modifierFlags.contains(.option)
    let shift = event.modifierFlags.contains(.shift)
    if chars == "z" && cmd && !opt && shift {
        onRedo?()
        return true
    }
    if chars == "z" && cmd && !opt && !shift {
        onUndo?()
        return true
    }
    if chars == "k" && cmd && !opt {
        onClear?()
        return true
    }
    if event.keyCode == 53 {
        onDeactivate?()
        return true
    }
    return false
}

// MARK: - Companion view

public protocol CanvasInputDelegate: AnyObject {
    func canvasInput(_ view: CanvasInputView, mouseDownAt point: CGPoint)
    func canvasInput(_ view: CanvasInputView, mouseDraggedAt point: CGPoint)
    func canvasInput(_ view: CanvasInputView, mouseUpAt point: CGPoint)
}

public final class CanvasInputView: NSView {
    public weak var delegate: CanvasInputDelegate?
    private var fitiCursor: NSCursor?
    private var cursorTrackingArea: NSTrackingArea?

    public override var isFlipped: Bool { true }
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    public override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        delegate?.canvasInput(self, mouseDownAt: p)
    }
    public override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        delegate?.canvasInput(self, mouseDraggedAt: p)
    }
    public override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        delegate?.canvasInput(self, mouseUpAt: p)
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = cursorTrackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .inVisibleRect, .cursorUpdate, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        cursorTrackingArea = area
    }

    public override func cursorUpdate(with event: NSEvent) {
        if let cursor = fitiCursor {
            cursor.set()
        } else {
            super.cursorUpdate(with: event)
        }
    }

    public override func mouseEntered(with event: NSEvent) {
        if let cursor = fitiCursor { cursor.set() }
    }

    /// Set the cursor that should appear over this view, or nil to revert to
    /// the system default. If the mouse is currently over the view, apply
    /// immediately so slider drags update the cursor live without requiring
    /// the user to wiggle the mouse.
    public func updateCursor(_ cursor: NSCursor?) {
        fitiCursor = cursor
        if let cursor, mouseIsInside {
            cursor.set()
        } else if cursor == nil {
            NSCursor.arrow.set()
        }
    }

    private var mouseIsInside: Bool {
        guard let window, window.isVisible else { return false }
        let mouseInWindow = window.mouseLocationOutsideOfEventStream
        let mouseInView = convert(mouseInWindow, from: nil)
        return bounds.contains(mouseInView)
    }
}
