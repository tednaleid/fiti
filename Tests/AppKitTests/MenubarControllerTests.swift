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

    /// Invoke the menu item's action through the ObjC runtime, the way
    /// AppKit would when the user clicks it. Avoids NSMenu.performActionForItem
    /// so we don't depend on autoenablesItems / validation behaviour.
    private func fire(_ title: String, in menubar: MenubarController) throws {
        let item = try #require(menubar.menu.items.first { $0.title == title })
        let target = try #require(item.target as? NSObject)
        let action = try #require(item.action)
        _ = target.perform(action, with: nil)
    }

    @Test("menu has the expected items in order")
    func menuStructure() {
        let (menubar, _, _, _) = make()
        let titles = menubar.menu.items.map(\.title)
        #expect(titles == ["Activate", "Deactivate", "",
                           "Clear", "Undo", "Redo", "",
                           "Quit fiti"])
    }

    @Test("Activate item key equivalent is Cmd+Opt+Z")
    func activateShortcut() throws {
        let (menubar, _, _, _) = make()
        let item = try #require(menubar.menu.items.first { $0.title == "Activate" })
        #expect(item.keyEquivalent == "z")
        #expect(item.keyEquivalentModifierMask == [.command, .option])
    }

    @Test("Undo item key equivalent is Cmd+Z; Redo is Cmd+Shift+Z")
    func undoRedoShortcuts() throws {
        let (menubar, _, _, _) = make()
        let undo = try #require(menubar.menu.items.first { $0.title == "Undo" })
        let redo = try #require(menubar.menu.items.first { $0.title == "Redo" })
        #expect(undo.keyEquivalent == "z" && undo.keyEquivalentModifierMask == [.command])
        #expect(redo.keyEquivalent == "z" && redo.keyEquivalentModifierMask == [.command, .shift])
    }

    @Test("menuNeedsUpdate enables Activate when inactive, disables Deactivate")
    func enabledStateInactive() {
        let (menubar, _, _, _) = make()
        menubar.menuNeedsUpdate(menubar.menu)
        let activate = menubar.menu.items.first { $0.title == "Activate" }!
        let deactivate = menubar.menu.items.first { $0.title == "Deactivate" }!
        #expect(activate.isEnabled == true)
        #expect(deactivate.isEnabled == false)
    }

    @Test("menuNeedsUpdate enables Deactivate when active")
    func enabledStateActive() {
        let (menubar, controller, _, _) = make()
        controller.activate()
        menubar.menuNeedsUpdate(menubar.menu)
        let activate = menubar.menu.items.first { $0.title == "Activate" }!
        let deactivate = menubar.menu.items.first { $0.title == "Deactivate" }!
        #expect(activate.isEnabled == false)
        #expect(deactivate.isEnabled == true)
    }

    @Test("menuNeedsUpdate ties Undo / Redo to Editor.canUndo / canRedo")
    func enabledStateUndoRedo() {
        let (menubar, _, _, editor) = make()
        menubar.menuNeedsUpdate(menubar.menu)
        let undo = menubar.menu.items.first { $0.title == "Undo" }!
        let redo = menubar.menu.items.first { $0.title == "Redo" }!
        #expect(undo.isEnabled == false)
        #expect(redo.isEnabled == false)

        _ = editor.startStroke(color: RGBA(r: 0, g: 0, b: 0, a: 1), width: 1, pointerType: .mouse)
        editor.endStroke()
        menubar.menuNeedsUpdate(menubar.menu)
        #expect(undo.isEnabled == true)
        #expect(redo.isEnabled == false)

        _ = editor.undo()
        menubar.menuNeedsUpdate(menubar.menu)
        #expect(undo.isEnabled == false)
        #expect(redo.isEnabled == true)
    }

    @Test("Activate menu action calls controller.activate()")
    func activateAction() throws {
        let (menubar, controller, _, _) = make()
        try fire("Activate", in: menubar)
        #expect(controller.mode == .activeIdle)
    }

    @Test("Clear menu action calls controller.clear()")
    func clearAction() throws {
        let (menubar, _, _, editor) = make()
        _ = editor.startStroke(color: RGBA(r: 0, g: 0, b: 0, a: 1), width: 1, pointerType: .mouse)
        editor.endStroke()
        try fire("Clear", in: menubar)
        #expect(editor.doc.strokeOrder.isEmpty)
    }

    @Test("Undo menu action calls editor.undo()")
    func undoAction() throws {
        let (menubar, _, _, editor) = make()
        _ = editor.startStroke(color: RGBA(r: 0, g: 0, b: 0, a: 1), width: 1, pointerType: .mouse)
        editor.endStroke()
        try fire("Undo", in: menubar)
        #expect(editor.doc.strokeOrder.isEmpty)
        #expect(editor.canRedo == true)
    }
}
