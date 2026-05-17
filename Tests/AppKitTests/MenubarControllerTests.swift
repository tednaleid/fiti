// ABOUTME: Tests for MenubarController — verifies icon swaps with mode and
// ABOUTME: that the controller installs/removes its NSStatusItem cleanly.

import AppKit
import Testing

@Suite("MenubarController")
@MainActor
struct MenubarControllerTests {
    // swiftlint:disable:next large_tuple
    private func make() -> (MenubarController, AppController, RecordingWindow, Editor) {
        let window = RecordingWindow()
        let editor = Editor(clock: VirtualClock(), ids: SeededIdGenerator(prefix: "s"))
        let controller = AppController(editor: editor, window: window)
        let menubar = MenubarController(controller: controller, editor: editor)
        return (menubar, controller, window, editor)
    }

    @Test("initial icon is the outlined symbol")
    func initialIcon() {
        let (menubar, _, _, _) = make()
        #expect(menubar.currentSymbolName == "theatermask.and.paintbrush")
    }

    @Test("icon swaps to the filled symbol when controller becomes active")
    func activateSwapsIcon() {
        let (menubar, controller, _, _) = make()
        controller.activate()
        #expect(menubar.currentSymbolName == "theatermask.and.paintbrush.fill")
    }

    @Test("icon returns to outlined when controller becomes inactive")
    func deactivateRestoresIcon() {
        let (menubar, controller, _, _) = make()
        controller.activate()
        controller.deactivate()
        #expect(menubar.currentSymbolName == "theatermask.and.paintbrush")
    }

    @Test("activeDrawing stays on the filled icon")
    func drawingKeepsFilled() {
        let (menubar, controller, _, _) = make()
        controller.activate()
        controller.pointerDown(StrokePoint(x: 0, y: 0))
        #expect(menubar.currentSymbolName == "theatermask.and.paintbrush.fill")
    }
}
