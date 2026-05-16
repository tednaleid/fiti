// ABOUTME: Regression test for the mid-emit listener-mutation bug.
// ABOUTME: A listener that cancels itself during emit must not crash.

import Testing

@Suite("Editor.subscribe cancel-during-emit")
struct EditorSubscribeCancelDuringEmitTests {
    @Test("a listener that unsubscribes itself does not crash emit")
    func cancelDuringEmit() {
        let editor = Editor(clock: VirtualClock(), ids: SeededIdGenerator(prefix: "s"))
        var cancellable: Cancellable?
        var fired = 0
        cancellable = editor.subscribe { _ in
            fired += 1
            cancellable?()
        }
        _ = editor.startStroke(color: RGBA(r: 0, g: 0, b: 0, a: 1), width: 1, pointerType: .mouse)
        editor.endStroke()
        // First emit (from startStroke) fires the callback and cancels.
        // Second emit (from endStroke) should NOT call the cancelled listener.
        #expect(fired == 1)
    }
}
