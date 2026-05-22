// ABOUTME: AppKit InputSource — wraps an NSView's mouse callbacks and a local
// ABOUTME: NSEvent monitor for Esc / Cmd+K / Cmd+Z / Cmd+Shift+Z. The system-wide
// ABOUTME: activation hotkey is handled by KeyboardShortcutsHotkeys, not here.

import AppKit

public final class NSEventInputSource: InputSource {
    public var onPointerDown: ((StrokePoint, PointerModifiers) -> Void)?
    public var onPointerMoved: ((StrokePoint, PointerModifiers) -> Void)?
    public var onPointerUp: ((PointerModifiers) -> Void)?
    public var onPointerHover: ((StrokePoint, PointerModifiers) -> Void)?
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
    public func canvasInput(_ view: CanvasInputView, mouseDownAt point: CGPoint, modifiers: PointerModifiers) {
        onPointerDown?(StrokePoint(x: Double(point.x), y: Double(point.y)), modifiers)
    }
    public func canvasInput(_ view: CanvasInputView, mouseDraggedAt point: CGPoint, modifiers: PointerModifiers) {
        onPointerMoved?(StrokePoint(x: Double(point.x), y: Double(point.y)), modifiers)
    }
    public func canvasInput(_ view: CanvasInputView, mouseUpAt point: CGPoint, modifiers: PointerModifiers) {
        onPointerUp?(modifiers)
    }
    public func canvasInput(_ view: CanvasInputView, mouseMovedAt point: CGPoint, modifiers: PointerModifiers) {
        onPointerHover?(StrokePoint(x: Double(point.x), y: Double(point.y)), modifiers)
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
    func canvasInput(_ view: CanvasInputView, mouseDownAt point: CGPoint, modifiers: PointerModifiers)
    func canvasInput(_ view: CanvasInputView, mouseDraggedAt point: CGPoint, modifiers: PointerModifiers)
    func canvasInput(_ view: CanvasInputView, mouseUpAt point: CGPoint, modifiers: PointerModifiers)
    func canvasInput(_ view: CanvasInputView, mouseMovedAt point: CGPoint, modifiers: PointerModifiers)
}

public final class CanvasInputView: NSView {
    public weak var delegate: CanvasInputDelegate?
    private var fitiCursor: NSCursor?
    private var cursorTrackingArea: NSTrackingArea?

    public override var isFlipped: Bool { true }
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    public override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let m = PointerModifiers(
            command: event.modifierFlags.contains(.command),
            shift: event.modifierFlags.contains(.shift)
        )
        delegate?.canvasInput(self, mouseDownAt: p, modifiers: m)
    }
    public override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let m = PointerModifiers(
            command: event.modifierFlags.contains(.command),
            shift: event.modifierFlags.contains(.shift)
        )
        delegate?.canvasInput(self, mouseDraggedAt: p, modifiers: m)
    }
    public override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let m = PointerModifiers(
            command: event.modifierFlags.contains(.command),
            shift: event.modifierFlags.contains(.shift)
        )
        delegate?.canvasInput(self, mouseUpAt: p, modifiers: m)
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = cursorTrackingArea { removeTrackingArea(existing) }
        // Explicit bounds rect + .mouseMoved + .cursorUpdate so we re-apply
        // the cursor on every move WITHIN the area, not just on enter/exit.
        // Without .mouseMoved, any external set() (toolbar interaction, window
        // activation reset, NSColorPanel close) can leave us stuck on arrow
        // until the mouse exits and re-enters.
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .cursorUpdate, .mouseMoved, .mouseEnteredAndExited],
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

    public override func mouseMoved(with event: NSEvent) {
        // Reapply on every move so external set()s (toolbar, color panel,
        // activation reset) can't strand us on arrow once the mouse re-enters
        // or moves within the canvas.
        if let cursor = fitiCursor { cursor.set() }
        let p = convert(event.locationInWindow, from: nil)
        let m = PointerModifiers(command: event.modifierFlags.contains(.command),
                                 shift: event.modifierFlags.contains(.shift))
        delegate?.canvasInput(self, mouseMovedAt: p, modifiers: m)
    }

    /// Set the cursor that should appear over this view, or nil to revert to
    /// the system default.
    public func updateCursor(_ cursor: NSCursor?) {
        fitiCursor = cursor
        if let cursor {
            cursor.set()
        } else {
            NSCursor.arrow.set()
        }
        // Force AppKit to re-resolve the cursor on the next runloop pass so a
        // keyboard-triggered change (color/size/opacity) sticks even when the
        // mouse is stationary. Without this, AppKit's cursor cache reverts to
        // the system arrow because no mouse motion fired cursorUpdate(with:).
        window?.invalidateCursorRects(for: self)
    }
}
