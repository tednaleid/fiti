// ABOUTME: Tests for ToolbarController — verifies the floating panel shows on
// ABOUTME: activation, hides on deactivation, and (later) widgets write through
// ABOUTME: to AppController state.

import AppKit
import Testing

@Suite("ToolbarController")
@MainActor
struct ToolbarControllerTests {
    // swiftlint:disable:next large_tuple
    private func make() -> (ToolbarController, AppController, Editor) {
        let window = RecordingWindow()
        let editor = Editor(clock: VirtualClock(), ids: SeededIdGenerator(prefix: "s"))
        let controller = AppController(editor: editor, window: window)
        let toolbar = ToolbarController(controller: controller,
                                        defaults: UserDefaults(suiteName: UUID().uuidString)!)
        return (toolbar, controller, editor)
    }

    @Test("panel is hidden on init")
    func hiddenOnInit() {
        let (toolbar, _, _) = make()
        #expect(toolbar.panel.isVisible == false)
    }

    @Test("updateVisibility shows the panel when mode is not .inactive")
    func showsWhenActive() {
        let (toolbar, _, _) = make()
        toolbar.updateVisibility(for: .activeIdle)
        #expect(toolbar.panel.isVisible == true)
    }

    @Test("updateVisibility hides the panel when mode is .inactive")
    func hidesWhenInactive() {
        let (toolbar, _, _) = make()
        toolbar.updateVisibility(for: .activeIdle)
        toolbar.updateVisibility(for: .inactive)
        #expect(toolbar.panel.isVisible == false)
    }
}
