// ABOUTME: Tests for MenubarController — verifies icon swaps with mode and
// ABOUTME: that the controller installs/removes its NSStatusItem cleanly.

import AppKit
import Testing

@Suite("MenubarController")
@MainActor
struct MenubarControllerTests {
    // swiftlint:disable:next large_tuple
    private func make() -> (MenubarController, AppController, RecordingWindow, Editor, PreferencesCounter) {
        let counter = PreferencesCounter()
        let window = RecordingWindow()
        let editor = Editor(clock: VirtualClock(), ids: SeededIdGenerator(prefix: "s"))
        let controller = AppController(
            editor: editor,
            window: window,
            detector: RecordingStationaryDetector(),
            clock: VirtualClock(),
            ticker: RecordingFadeTicker(),
            textMeasurer: CoreTextMeasurer()
        )
        let menubar = MenubarController(
            controller: controller,
            editor: editor,
            onOpenPreferences: { counter.count += 1 }
        )
        return (menubar, controller, window, editor, counter)
    }

    private final class PreferencesCounter {
        var count = 0
    }

    @Test("initial icon is the outlined symbol")
    func initialIcon() {
        let (menubar, _, _, _, _) = make()
        #expect(menubar.currentSymbolName == "theatermask.and.paintbrush")
    }

    @Test("icon swaps to the filled symbol when controller becomes active")
    func activateSwapsIcon() {
        let (menubar, controller, _, _, _) = make()
        controller.activate()
        #expect(menubar.currentSymbolName == "theatermask.and.paintbrush.fill")
    }

    @Test("icon returns to outlined when controller becomes inactive")
    func deactivateRestoresIcon() {
        let (menubar, controller, _, _, _) = make()
        controller.activate()
        controller.deactivate()
        #expect(menubar.currentSymbolName == "theatermask.and.paintbrush")
    }

    @Test("activeDrawing stays on the filled icon")
    func drawingKeepsFilled() {
        let (menubar, controller, _, _, _) = make()
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
        let (menubar, _, _, _, _) = make()
        let titles = menubar.menu.items.map(\.title)
        #expect(titles == ["Activate", "Deactivate", "",
                           "Preferences...", "",
                           "Drawing",
                           "Clear", "Undo", "Redo", "",
                           "Quit fiti"])
    }

    @Test("Activate item key equivalent is Opt+F")
    func activateShortcut() throws {
        let (menubar, _, _, _, _) = make()
        let item = try #require(menubar.menu.items.first { $0.title == "Activate" })
        #expect(item.keyEquivalent == "f")
        #expect(item.keyEquivalentModifierMask == [.option])
    }

    @Test("Preferences item has Cmd+, key equivalent")
    func preferencesShortcut() throws {
        let (menubar, _, _, _, _) = make()
        let item = try #require(menubar.menu.items.first { $0.title == "Preferences..." })
        #expect(item.keyEquivalent == ",")
        #expect(item.keyEquivalentModifierMask == [.command])
    }

    @Test("Preferences menu action fires onOpenPreferences")
    func preferencesAction() throws {
        let (menubar, _, _, _, counter) = make()
        try fire("Preferences...", in: menubar)
        #expect(counter.count == 1)
    }

    @Test("Undo item key equivalent is Cmd+Z; Redo is Cmd+Shift+Z")
    func undoRedoShortcuts() throws {
        let (menubar, _, _, _, _) = make()
        let undo = try #require(menubar.menu.items.first { $0.title == "Undo" })
        let redo = try #require(menubar.menu.items.first { $0.title == "Redo" })
        #expect(undo.keyEquivalent == "z" && undo.keyEquivalentModifierMask == [.command])
        #expect(redo.keyEquivalent == "z" && redo.keyEquivalentModifierMask == [.command, .shift])
    }

    @Test("menuNeedsUpdate enables Activate when inactive, disables Deactivate")
    func enabledStateInactive() {
        let (menubar, _, _, _, _) = make()
        menubar.menuNeedsUpdate(menubar.menu)
        let activate = menubar.menu.items.first { $0.title == "Activate" }!
        let deactivate = menubar.menu.items.first { $0.title == "Deactivate" }!
        #expect(activate.isEnabled == true)
        #expect(deactivate.isEnabled == false)
    }

    @Test("menuNeedsUpdate enables Deactivate when active")
    func enabledStateActive() {
        let (menubar, controller, _, _, _) = make()
        controller.activate()
        menubar.menuNeedsUpdate(menubar.menu)
        let activate = menubar.menu.items.first { $0.title == "Activate" }!
        let deactivate = menubar.menu.items.first { $0.title == "Deactivate" }!
        #expect(activate.isEnabled == false)
        #expect(deactivate.isEnabled == true)
    }

    @Test("menuNeedsUpdate ties Undo / Redo to Editor.canUndo / canRedo")
    func enabledStateUndoRedo() {
        let (menubar, _, _, editor, _) = make()
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
        let (menubar, controller, _, _, _) = make()
        try fire("Activate", in: menubar)
        #expect(controller.mode == .activeIdle)
    }

    @Test("Clear menu action calls controller.clear()")
    func clearAction() throws {
        let (menubar, _, _, editor, _) = make()
        _ = editor.startStroke(color: RGBA(r: 0, g: 0, b: 0, a: 1), width: 1, pointerType: .mouse)
        editor.endStroke()
        try fire("Clear", in: menubar)
        #expect(editor.doc.itemOrder.isEmpty)
    }

    @Test("Undo menu action calls editor.undo()")
    func undoAction() throws {
        let (menubar, _, _, editor, _) = make()
        _ = editor.startStroke(color: RGBA(r: 0, g: 0, b: 0, a: 1), width: 1, pointerType: .mouse)
        editor.endStroke()
        try fire("Undo", in: menubar)
        #expect(editor.doc.itemOrder.isEmpty)
        #expect(editor.canRedo == true)
    }
}

@Suite("MenubarController Drawing submenu")
@MainActor
struct MenubarControllerDrawingSubmenuTests {
    // swiftlint:disable:next large_tuple
    private func make() -> (MenubarController, AppController, Editor) {
        let clock = VirtualClock()
        let editor = Editor(clock: clock, ids: SeededIdGenerator(prefix: "s"))
        let controller = AppController(
            editor: editor,
            window: RecordingWindow(),
            detector: RecordingStationaryDetector(),
            clock: clock,
            ticker: RecordingFadeTicker(),
            textMeasurer: CoreTextMeasurer()
        )
        let mb = MenubarController(controller: controller, editor: editor, onOpenPreferences: {})
        return (mb, controller, editor)
    }

    private func drawingSubmenu(_ mb: MenubarController) -> NSMenu? {
        mb.menu.item(withTitle: "Drawing")?.submenu
    }

    @Test("Drawing submenu exists")
    func submenuExists() {
        let (mb, _, _) = make()
        #expect(drawingSubmenu(mb) != nil)
    }

    @Test("Drawing submenu has 8 color items with keyEquivalents 1..8")
    func colorItems() {
        let (mb, _, _) = make()
        let sub = drawingSubmenu(mb)!
        let colors = QuickPickPalette.colors
        for i in 0..<8 {
            let item = sub.item(withTitle: colors[i].name)
            #expect(item != nil, "expected menu item titled \(colors[i].name)")
            #expect(item?.keyEquivalent == "\(i + 1)")
            #expect(item?.keyEquivalentModifierMask == [])
        }
    }

    @Test("Larger stroke item has keyEquivalent 's' with no modifier")
    func largerStrokeKey() {
        let (mb, _, _) = make()
        let item = drawingSubmenu(mb)!.item(withTitle: "Larger stroke")
        #expect(item?.keyEquivalent == "s")
        #expect(item?.keyEquivalentModifierMask == [])
    }

    @Test("Smaller stroke item has keyEquivalent 's' with shift")
    func smallerStrokeKey() {
        let (mb, _, _) = make()
        let item = drawingSubmenu(mb)!.item(withTitle: "Smaller stroke")
        #expect(item?.keyEquivalent == "s")
        #expect(item?.keyEquivalentModifierMask == [.shift])
    }

    @Test("More opaque item has keyEquivalent 'o' with no modifier")
    func moreOpaqueKey() {
        let (mb, _, _) = make()
        let item = drawingSubmenu(mb)!.item(withTitle: "More opaque")
        #expect(item?.keyEquivalent == "o")
        #expect(item?.keyEquivalentModifierMask == [])
    }

    @Test("Less opaque item has keyEquivalent 'o' with shift")
    func lessOpaqueKey() {
        let (mb, _, _) = make()
        let item = drawingSubmenu(mb)!.item(withTitle: "Less opaque")
        #expect(item?.keyEquivalent == "o")
        #expect(item?.keyEquivalentModifierMask == [.shift])
    }

    @Test("Hide drawings item shows checkmark when drawingsVisible is false")
    func hideStateCheckmark() {
        let (mb, controller, _) = make()
        let item = drawingSubmenu(mb)!.item(withTitle: "Hide drawings")!
        // Initial: drawingsVisible == true → item.state == .off
        mb.menu.delegate?.menuNeedsUpdate?(mb.menu)
        #expect(item.state == .off)
        controller.drawingsVisible = false
        mb.menu.delegate?.menuNeedsUpdate?(mb.menu)
        #expect(item.state == .on)
    }

    @Test("Auto-fade item shows checkmark when autoFadeEnabled is true")
    func autoFadeStateCheckmark() {
        let (mb, controller, _) = make()
        let item = drawingSubmenu(mb)!.item(withTitle: "Auto-fade")!
        mb.menu.delegate?.menuNeedsUpdate?(mb.menu)
        #expect(item.state == .off)
        controller.autoFadeEnabled = true
        mb.menu.delegate?.menuNeedsUpdate?(mb.menu)
        #expect(item.state == .on)
    }

    @Test("clicking a color submenu item dispatches the matching pickColor")
    func clickColorDispatches() {
        let (mb, controller, _) = make()
        let red = drawingSubmenu(mb)!.item(withTitle: "Red")!
        // Synthesize a click by invoking the action selector directly.
        _ = red.target?.perform(red.action, with: red)
        #expect(abs(controller.currentColor.r - 224.0/255.0) < 0.0001)
    }

    @Test("clicking Larger stroke dispatches bumpSize(.up)")
    func clickLargerStrokeDispatches() {
        let (mb, controller, _) = make()
        controller.currentWidth = 10
        let item = drawingSubmenu(mb)!.item(withTitle: "Larger stroke")!
        _ = item.target?.perform(item.action, with: item)
        #expect(controller.currentWidth > 10)
    }
}
