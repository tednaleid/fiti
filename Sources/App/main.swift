// ABOUTME: fiti entry point — argv → wiring → NSApplication.run().
// ABOUTME: Sole place where AppKit + DevHTTP + Core concretes are stitched together.

import AppKit
import Foundation

let args = Args.parse(CommandLine.arguments)

final class FitiAppDelegate: NSObject, NSApplicationDelegate {
    let args: Args
    var window: TransparentWindow!
    var canvas: CanvasView!
    var inputView: CanvasInputView!
    var input: NSEventInputSource!
    var controller: AppController!
    var editor: Editor!
    var devServer: DevHTTPServer?
    var subscription: Cancellable?
    var menubar: MenubarController!
    var toolbar: ToolbarController!

    init(args: Args) { self.args = args }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // AXIsProcessTrustedWithOptions(prompt: true) is a one-time prompt per
        // bundle identity — the OS suppresses repeat dialogs on its own, so we
        // can call this on every launch without becoming annoying.
        if !AccessibilityCheck.isTrusted(prompt: true) {
            NSLog("fiti: accessibility permission not granted; Ctrl+F global hotkey will not work until granted in System Settings → Privacy & Security → Accessibility.")
        }

        editor = Editor(clock: SystemClock(), ids: UUIDStrokeIds())
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
        menubar = MenubarController(controller: controller, editor: editor)
        toolbar = ToolbarController(controller: controller)
        composeControllerCallbacks()

        input = NSEventInputSource(view: inputView)
        input.onPointerDown   = { [weak self] in self?.controller.pointerDown($0) }
        input.onPointerMoved  = { [weak self] in self?.controller.pointerMoved($0) }
        input.onPointerUp     = { [weak self] in self?.controller.pointerUp() }
        input.onToggle        = { [weak self] in self?.controller.toggle() }
        input.onDeactivate    = { [weak self] in self?.controller.deactivate() }
        input.onClear         = { [weak self] in self?.controller.clear() }
        input.onUndo          = { [weak self] in _ = self?.editor.undo() }
        input.onRedo          = { [weak self] in _ = self?.editor.redo() }

        subscription = editor.subscribe { [weak self] _ in
            guard let self else { return }
            self.canvas.render(RenderFrame.from(editor: self.editor, canvasSize: self.canvasSize))
        }

        if args.dev {
            let surface = FitiDevHTTPSurface(controller: controller,
                                             canvasSize: { [weak self] in self?.canvasSize ?? Size(width: 0, height: 0) })
            do {
                let server = try DevHTTPServer(surface: surface, port: args.port)
                try server.start()
                devServer = server
                NSLog("fiti dev HTTP listening on localhost:\(args.port)")
            } catch {
                NSLog("fiti dev HTTP failed to start: \(error)")
            }
        }

        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private var canvasSize: Size {
        Size(width: Double(canvas.frame.width), height: Double(canvas.frame.height))
    }

    @MainActor
    private func composeControllerCallbacks() {
        // Compose onModeChanged: menubar (icon) + toolbar (panel visibility).
        let menubarModeHandler = controller.onModeChanged
        controller.onModeChanged = { [weak self] mode in
            menubarModeHandler?(mode)
            self?.toolbar.updateVisibility(for: mode)
        }

        // Compose onDrawingsVisibilityChanged: toolbar (eye glyph) + canvas
        // (suppress drawing). The toolbar set this in its init; we wrap.
        let toolbarVisibilityHandler = controller.onDrawingsVisibilityChanged
        controller.onDrawingsVisibilityChanged = { [weak self] visible in
            toolbarVisibilityHandler?(visible)
            self?.canvas.drawingsVisible = visible
        }
    }
}

let app = NSApplication.shared
let delegate = FitiAppDelegate(args: args)
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
