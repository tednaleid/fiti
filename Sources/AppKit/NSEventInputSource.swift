// ABOUTME: AppKit InputSource — wraps an NSView's mouse callbacks and local/global
// ABOUTME: NSEvent key monitors (Cmd+Opt+Z global to activate, Esc local to deactivate).

import AppKit

public final class NSEventInputSource: InputSource {
    public var onPointerDown: ((StrokePoint) -> Void)?
    public var onPointerMoved: ((StrokePoint) -> Void)?
    public var onPointerUp: (() -> Void)?
    public var onActivate: (() -> Void)?
    public var onDeactivate: (() -> Void)?
    public var onClear: (() -> Void)?

    private let view: CanvasInputView
    private var keyMonitor: Any?
    private var globalMonitor: Any?

    public init(view: CanvasInputView) {
        self.view = view
        view.delegate = self
        installKeyMonitor()
    }

    deinit {
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
    }

    /// Returns true if the event was consumed (caller should drop it).
    public func handleKeyDown(_ event: NSEvent) -> Bool {
        dispatchKey(event, onActivate: onActivate, onClear: onClear, onDeactivate: onDeactivate)
    }

    private func installKeyMonitor() {
        // Local monitor handles all three shortcuts when fiti is focused.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyDown(event) ? nil : event
        }
        // Global monitor handles Cmd+Opt+Z only — Esc and Cmd+K stay local
        // because they only make sense while fiti is the focused app.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            let chars = event.charactersIgnoringModifiers
            let cmd = event.modifierFlags.contains(.command)
            let opt = event.modifierFlags.contains(.option)
            if chars == "z" && cmd && opt {
                self.onActivate?()
            }
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
/// dispatch without instantiating the class (which would install real
/// `NSEvent` monitors as a side effect).
public func dispatchKey(_ event: NSEvent,
                        onActivate: (() -> Void)?,
                        onClear: (() -> Void)?,
                        onDeactivate: (() -> Void)?) -> Bool {
    let chars = event.charactersIgnoringModifiers
    let cmd = event.modifierFlags.contains(.command)
    let opt = event.modifierFlags.contains(.option)
    if chars == "z" && cmd && opt {
        onActivate?()
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
}
