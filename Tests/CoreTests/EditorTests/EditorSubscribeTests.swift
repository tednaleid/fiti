// ABOUTME: Tests for the subscribe/unsubscribe lifecycle on Editor.
// ABOUTME: Verifies that listeners fire on mutation and stop after cancellation.

import Testing

@Suite("Editor.subscribe")
@MainActor
struct EditorSubscribeTests {
    @Test("notifies on local change")
    func notifies() {
        let e = Editor(clock: VirtualClock(), ids: SeededIdGenerator(prefix: "s"))
        var count = 0
        let unsubscribe = e.subscribe { kind in
            #expect(kind == .local)
            count += 1
        }
        _ = e.startStroke(color: RGBA(r: 0, g: 0, b: 0, a: 1), width: 1, pointerType: .mouse)
        e.endStroke()
        #expect(count == 2)
        unsubscribe()
    }

    @Test("unsubscribe stops notifications")
    func unsubscribe() {
        let e = Editor(clock: VirtualClock(), ids: SeededIdGenerator(prefix: "s"))
        var count = 0
        let cancel = e.subscribe { _ in count += 1 }
        _ = e.startStroke(color: RGBA(r: 0, g: 0, b: 0, a: 1), width: 1, pointerType: .mouse)
        cancel()
        e.endStroke()
        #expect(count == 1)
    }
}
