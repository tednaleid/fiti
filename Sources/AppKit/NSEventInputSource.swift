// ABOUTME: AppKit InputSource — wraps an NSView's mouse callbacks and a local
// ABOUTME: NSEvent key monitor (Cmd+Opt+Z to activate, Esc to deactivate).

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

    public init(view: CanvasInputView) {
        self.view = view
        view.delegate = self
        installKeyMonitor()
    }

    deinit {
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let chars = event.charactersIgnoringModifiers
            let cmd = event.modifierFlags.contains(.command)
            let opt = event.modifierFlags.contains(.option)
            if chars == "z" && cmd && opt {
                self.onActivate?()
                return nil
            }
            if chars == "k" && cmd && !opt {
                self.onClear?()
                return nil
            }
            if event.keyCode == 53 {
                self.onDeactivate?()
                return nil
            }
            return event
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
