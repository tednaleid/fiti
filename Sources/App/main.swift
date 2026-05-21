// ABOUTME: fiti entry point — argv → wiring → NSApplication.run().
// ABOUTME: Sole place where AppKit + DevHTTP + Core concretes are stitched together.

import AppKit
import Foundation

let args = Args.parse(CommandLine.arguments)

@MainActor
final class FitiAppDelegate: NSObject, NSApplicationDelegate {
    let args: Args
    var window: TransparentWindow!
    var canvas: CanvasView!
    var inputView: CanvasInputView!
    var input: NSEventInputSource!
    var controller: AppController!
    var editor: Editor!
    #if DEBUG
    var devServer: DevHTTPServer?
    #endif
    var subscription: Cancellable?
    var menubar: MenubarController!
    var preferences: PreferencesController!
    var toolbar: ToolbarController!
    var hotkeys: KeyboardShortcutsHotkeys!
    var cursorRenderer: CursorRenderer!
    private var keyMonitor: KeyMonitor!
    private var toolbarScreenObserver: NSObjectProtocol?

    init(args: Args) { self.args = args }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let clock = SystemClock()
        editor = Editor(clock: clock, ids: UUIDStrokeIds())
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

        let ticker = TimerFadeTicker(clock: clock)
        controller = AppController(
            editor: editor,
            window: window,
            detector: TaskStationaryDetector(),
            clock: clock,
            ticker: ticker
        )
        preferences = PreferencesController(launchAtLogin: SMAppServiceLaunchAtLogin())
        menubar = MenubarController(
            controller: controller,
            editor: editor,
            onOpenPreferences: { [weak self] in self?.preferences.show() }
        )
        toolbar = ToolbarController(controller: controller)
        keyMonitor = KeyMonitor(controller: controller)
        composeControllerCallbacks()
        followToolbarToScreen(clearStrokes: false)  // initial sync — autosaved toolbar position may be on a non-main screen
        observeToolbarScreenChanges()

        input = NSEventInputSource(view: inputView)
        input.onPointerDown   = { [weak self] in self?.controller.pointerDown($0, modifiers: $1) }
        input.onPointerMoved  = { [weak self] in self?.controller.pointerMoved($0, modifiers: $1) }
        input.onPointerUp     = { [weak self] in self?.controller.pointerUp(modifiers: $0) }
        input.onDeactivate    = { [weak self] in self?.controller.deactivate() }
        input.onClear         = { [weak self] in self?.controller.clear() }
        input.onUndo          = { [weak self] in _ = self?.editor.undo() }
        input.onRedo          = { [weak self] in _ = self?.editor.redo() }

        hotkeys = KeyboardShortcutsHotkeys()
        hotkeys.onActivation { [weak self] in self?.controller.toggle() }

        cursorRenderer = CursorRenderer(view: inputView)
        controller.onCursorChanged = { [weak self] spec in self?.cursorRenderer.setSpec(spec) }

        subscription = editor.subscribe { [weak self] _ in
            guard let self else { return }
            self.canvas.render(RenderFrame.from(editor: self.editor, canvasSize: self.canvasSize))
        }

        maybeStartDevServer()

        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @MainActor
    private func maybeStartDevServer() {
        guard args.dev else { return }
        #if DEBUG
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
        #else
        NSLog("fiti: --dev is a no-op in Release builds (DevHTTP surface is compiled out)")
        #endif
    }

    private var canvasSize: Size {
        Size(width: Double(canvas.frame.width), height: Double(canvas.frame.height))
    }

    @MainActor
    private func composeControllerCallbacks() {
        // Compose onModeChanged: menubar (icon) + toolbar (panel visibility)
        // + keyMonitor (install/uninstall local NSEvent monitor).
        let menubarModeHandler = controller.onModeChanged
        controller.onModeChanged = { [weak self] mode in
            menubarModeHandler?(mode)
            self?.toolbar.updateVisibility(for: mode)
            self?.keyMonitor.syncRegistration(for: mode)
        }

        // Compose onDrawingsVisibilityChanged: toolbar (eye glyph) + canvas
        // (suppress drawing). The toolbar set this in its init; we wrap.
        let toolbarVisibilityHandler = controller.onDrawingsVisibilityChanged
        controller.onDrawingsVisibilityChanged = { [weak self] visible in
            toolbarVisibilityHandler?(visible)
            self?.canvas.drawingsVisible = visible
        }

        controller.onFadeOpacityChanged = { [weak self] opacity in
            self?.canvas.setGlobalOpacity(opacity)
        }
    }

    /// Keep the full-screen drawing canvas on whichever monitor hosts the
    /// floating toolbar. Fires when the user drags the toolbar between
    /// monitors (didChangeScreenNotification) and once at startup so the
    /// canvas follows the toolbar's autosaved frame.
    @MainActor
    private func observeToolbarScreenChanges() {
        toolbarScreenObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeScreenNotification,
            object: toolbar.panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.followToolbarToScreen(clearStrokes: true)
            }
        }
    }

    @MainActor
    private func followToolbarToScreen(clearStrokes: Bool) {
        guard let target = toolbar.panel.screen else { return }
        guard window.screen != target else { return }
        if clearStrokes { controller.clear() }
        window.setFrame(target.frame, display: true)
    }
}

let app = NSApplication.shared
let delegate = FitiAppDelegate(args: args)
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
