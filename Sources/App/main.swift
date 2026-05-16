// ABOUTME: Phase 3 smoke wiring. Phase 5 will replace this with argv parsing
// ABOUTME: and dev HTTP wiring; for now it just shows that the AppKit shell works.

import AppKit
import Foundation

final class SmokeClock: Clock { func now() -> Double { Date().timeIntervalSince1970 } }
final class SmokeIds: IdGenerator {
    private var counter = 0
    func newStrokeId() -> StrokeId { counter += 1; return "stroke-\(counter)" }
}

final class SmokeAppDelegate: NSObject, NSApplicationDelegate {
    var window: TransparentWindow!
    var canvas: CanvasView!
    var input: NSEventInputSource!
    var controller: AppController!
    var editor: Editor!
    var inputView: CanvasInputView!
    var subscription: Cancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        editor = Editor(clock: SmokeClock(), ids: SmokeIds())
        window = TransparentWindow()
        let frame = window.contentLayoutRect

        let container = NSView(frame: frame)
        canvas = CanvasView(frame: frame)
        inputView = CanvasInputView(frame: frame)
        canvas.autoresizingMask = [.width, .height]
        inputView.autoresizingMask = [.width, .height]
        container.addSubview(canvas)
        container.addSubview(inputView)
        window.contentView = container

        controller = AppController(editor: editor, window: window)
        input = NSEventInputSource(view: inputView)
        input.onPointerDown   = { [weak self] in self?.controller.pointerDown($0) }
        input.onPointerMoved  = { [weak self] in self?.controller.pointerMoved($0) }
        input.onPointerUp     = { [weak self] in self?.controller.pointerUp() }
        input.onActivate      = { [weak self] in self?.controller.activate() }
        input.onDeactivate    = { [weak self] in self?.controller.deactivate() }
        input.onClear         = { [weak self] in self?.controller.clear() }

        subscription = editor.subscribe { [weak self] _ in
            guard let self else { return }
            self.canvas.render(RenderFrame.from(editor: self.editor,
                canvasSize: Size(width: Double(self.canvas.frame.width),
                                 height: Double(self.canvas.frame.height))))
        }

        // The local NSEvent key monitor only fires when this app is active.
        // With .accessory policy and no Dock icon, the app won't activate on
        // its own — so do it explicitly here. Phase 5 will replace this with
        // proper argv-driven startup.
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

let app = NSApplication.shared
let delegate = SmokeAppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
