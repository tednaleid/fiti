// ABOUTME: Tests for KeyMonitor's text-capture branch. While a text session is
// ABOUTME: active, keystrokes route to the session rather than shortcut registry.

import AppKit
import Testing

@Suite("KeyMonitor text-capture")
@MainActor
struct KeyMonitorTextTests {
    private func make() -> (KeyMonitor, AppController) {
        let clock = VirtualClock()
        let editor = Editor(clock: clock, ids: SeededIdGenerator(prefix: "t"))
        let controller = AppController(
            editor: editor,
            window: RecordingWindow(),
            detector: RecordingStationaryDetector(),
            clock: clock,
            ticker: RecordingFadeTicker(),
            textMeasurer: FakeTextMeasurer()
        )
        let monitor = KeyMonitor(controller: controller)
        return (monitor, controller)
    }

    /// Starts a text editing session by simulating a text-tool pointer down.
    private func beginTextSession(controller: AppController) {
        controller.activate()
        controller.currentTool = .text
        controller.pointerDown(StrokePoint(x: 100, y: 100))
        // After pointerDown with .text, a session should exist.
    }

    private func keyDown(
        _ chars: String,
        keyCode: UInt16 = 0,
        shift: Bool = false,
        command: Bool = false
    ) -> NSEvent {
        var flags: NSEvent.ModifierFlags = []
        if shift { flags.insert(.shift) }
        if command { flags.insert(.command) }
        // charactersIgnoringModifiers ignores modifiers except Shift.
        let charsIgnoring = shift ? chars.uppercased() : chars
        return NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: chars,
            charactersIgnoringModifiers: charsIgnoring,
            isARepeat: false,
            keyCode: keyCode
        )!
    }

    @Test("printable char inserts into session and event is swallowed")
    func printableCharInserts() {
        let (monitor, controller) = make()
        beginTextSession(controller: controller)
        #expect(controller.isEditingText)

        let result = monitor.handle(keyDown("a", keyCode: 0))
        #expect(result == nil, "printable key should be swallowed")
        #expect(controller.textSession?.string == "a")
    }

    @Test("Return commits the session (session ends)")
    func returnCommitsSession() {
        let (monitor, controller) = make()
        beginTextSession(controller: controller)
        _ = monitor.handle(keyDown("a", keyCode: 0))
        #expect(controller.textSession?.string == "a")

        let result = monitor.handle(keyDown("\r", keyCode: 36))
        #expect(result == nil, "Return should be swallowed")
        #expect(controller.textSession == nil, "session should be committed/cleared")
    }

    @Test("Shift+Return inserts newline into session")
    func shiftReturnInsertsNewline() {
        let (monitor, controller) = make()
        beginTextSession(controller: controller)
        _ = monitor.handle(keyDown("a", keyCode: 0))

        let result = monitor.handle(keyDown("\r", keyCode: 36, shift: true))
        #expect(result == nil, "Shift+Return should be swallowed")
        #expect(controller.textSession?.string == "a\n", "session should have newline appended")
        #expect(controller.isEditingText, "session should still be active after Shift+Return")
    }

    @Test("Escape ends the session and returns tool to .pen")
    func escapeEndsSessionAndRestoresPen() {
        let (monitor, controller) = make()
        beginTextSession(controller: controller)
        #expect(controller.currentTool == .text)

        let result = monitor.handle(keyDown("\u{1B}", keyCode: 53))
        #expect(result == nil, "Escape should be swallowed")
        #expect(controller.textSession == nil, "session should be nil after Escape")
        #expect(controller.currentTool == .pen, "tool should revert to .pen after Escape")
    }

    @Test("while editing, 's' does not change currentWidth (shortcut suspended)")
    func widthShortcutSuspendedWhileEditing() {
        let (monitor, controller) = make()
        beginTextSession(controller: controller)
        let widthBefore = controller.currentWidth

        _ = monitor.handle(keyDown("s", keyCode: 1))
        #expect(controller.currentWidth == widthBefore, "'s' should not fire width shortcut while editing")
        #expect(controller.textSession?.string == "s", "'s' should be inserted as text")
    }

    @Test("Cmd-combo passes through to menubar while editing")
    func cmdComboPassesThroughWhileEditing() {
        let (monitor, controller) = make()
        beginTextSession(controller: controller)

        let event = keyDown("z", keyCode: 6, command: true)
        let result = monitor.handle(event)
        #expect(result === event, "Cmd+Z should pass through to menubar")
        // session string should remain empty (not have "z" inserted)
        #expect(controller.textSession?.string == "", "Cmd+Z should not insert into session")
    }
}
