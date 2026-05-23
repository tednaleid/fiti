// ABOUTME: Tests for KeyMonitor's pure NSEvent → dispatch path. Synthesizes
// ABOUTME: NSEvent.keyDown via NSEvent.keyEvent(with:...) and asserts that
// ABOUTME: handle() either dispatches and swallows or passes the event through.

import AppKit
import Testing

@Suite("KeyMonitor")
@MainActor
struct KeyMonitorTests {
    // swiftlint:disable:next large_tuple
    private func make() -> (KeyMonitor, AppController, Editor) {
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
        let monitor = KeyMonitor(controller: controller)
        return (monitor, controller, editor)
    }

    private func keyEvent(_ chars: String, shift: Bool = false, command: Bool = false, isARepeat: Bool = false) -> NSEvent {
        var flags: NSEvent.ModifierFlags = []
        if shift { flags.insert(.shift) }
        if command { flags.insert(.command) }
        return NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: chars,
            charactersIgnoringModifiers: chars,
            isARepeat: isARepeat,
            keyCode: 0
        )!
    }

    private func keyUpEvent(_ chars: String) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyUp,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: chars,
            charactersIgnoringModifiers: chars,
            isARepeat: false,
            keyCode: 0
        )!
    }

    @Test("bound key dispatches and is swallowed")
    func boundKeyDispatched() {
        let (monitor, controller, _) = make()
        let before = controller.currentColor
        let result = monitor.handle(keyEvent("1"))  // Black — distinct from the Red default
        #expect(result == nil, "bound key should be swallowed (nil return)")
        #expect(controller.currentColor != before)
    }

    @Test("shifted bound key dispatches the shifted variant")
    func shiftedKeyDispatched() {
        let (monitor, controller, _) = make()
        controller.currentWidth = 10
        _ = monitor.handle(keyEvent("s", shift: true))  // bumpSize(.down)
        #expect(controller.currentWidth < 10)
    }

    @Test("OS-shape Shift+S (chars='S', shift flag set) dispatches bumpSize(.down)")
    func shiftedKeyDispatchedOSShape() {
        // charactersIgnoringModifiers ignores everything except shift, so Shift+S
        // arrives as "S" not "s". This test mimics the real NSEvent shape that
        // macOS delivers — the original shiftedKeyDispatched used "s" for both
        // chars and charactersIgnoringModifiers, which masked the bug where the
        // registry lookup missed because of the case mismatch.
        let (monitor, controller, _) = make()
        controller.currentWidth = 10
        _ = monitor.handle(keyEvent("S", shift: true))
        #expect(controller.currentWidth < 10, "Shift+S should dispatch bumpSize(.down) even when chars is uppercase")
    }

    @Test("OS-shape Shift+O (chars='O', shift flag set) dispatches bumpOpacity(.down)")
    func shiftedOpacityDispatchedOSShape() {
        let (monitor, controller, _) = make()
        controller.currentColor = RGBA(r: 0.5, g: 0.5, b: 0.5, a: 0.9)
        _ = monitor.handle(keyEvent("O", shift: true))
        #expect(controller.currentColor.a < 0.9, "Shift+O should dispatch bumpOpacity(.down) even when chars is uppercase")
    }

    @Test("unbound key is passed through unchanged")
    func unboundKeyPassesThrough() {
        let (monitor, controller, _) = make()
        let before = controller.currentColor
        let event = keyEvent("x")
        let result = monitor.handle(event)
        #expect(result === event, "unbound key should return the original event")
        #expect(controller.currentColor == before)
    }

    @Test("Cmd-modified bound key passes through (menubar's job, not ours)")
    func commandModifierPassesThrough() {
        let (monitor, controller, _) = make()
        let before = controller.currentWidth
        let event = keyEvent("s", command: true)
        let result = monitor.handle(event)
        #expect(result === event)
        #expect(controller.currentWidth == before)
    }

    @Test("multi-character chars (dead-key composition) pass through")
    func multiCharPassesThrough() {
        let (monitor, controller, _) = make()
        let before = controller.currentColor
        let event = keyEvent("´e")  // accent composition
        let result = monitor.handle(event)
        #expect(result === event)
        #expect(controller.currentColor == before)
    }

    @Test("delete key dispatches run(.clear)")
    func deleteClearDispatches() {
        let (monitor, controller, editor) = make()
        controller.activate()
        controller.pointerDown(StrokePoint(x: 0, y: 0))
        controller.pointerUp()
        #expect(editor.doc.items.isEmpty == false)
        _ = monitor.handle(keyEvent("\u{7F}"))  // NSDeleteCharacter
        #expect(editor.doc.items.isEmpty == true)
    }

    @Test("'c' is no longer bound; passes through")
    func cIsUnbound() {
        let (monitor, controller, editor) = make()
        controller.activate()
        controller.pointerDown(StrokePoint(x: 0, y: 0))
        controller.pointerUp()
        let event = keyEvent("c")
        let result = monitor.handle(event)
        #expect(result === event, "'c' should pass through unchanged now that delete is the clear binding")
        #expect(editor.doc.items.isEmpty == false)
    }

    @Test("Space keyDown sets currentTool to .selection")
    func spaceKeyDownEntersSelection() {
        let (monitor, controller, _) = make()
        #expect(controller.currentTool == .pen)
        _ = monitor.handle(keyEvent(" "))
        #expect(controller.currentTool == .selection)
    }

    @Test("Space keyUp reverts currentTool to .pen")
    func spaceKeyUpExitsSelection() {
        let (monitor, controller, _) = make()
        _ = monitor.handle(keyEvent(" "))
        #expect(controller.currentTool == .selection)
        _ = monitor.handle(keyUpEvent(" "))
        #expect(controller.currentTool == .pen)
    }

    @Test("Space autorepeat (isARepeat=true) does not re-fire the tool transition")
    func spaceRepeatIgnored() {
        let (monitor, controller, _) = make()
        var fireCount = 0
        controller.onCurrentToolChanged = { _ in fireCount += 1 }
        _ = monitor.handle(keyEvent(" "))
        _ = monitor.handle(keyEvent(" ", isARepeat: true))
        _ = monitor.handle(keyEvent(" ", isARepeat: true))
        #expect(fireCount == 1)
    }
}
