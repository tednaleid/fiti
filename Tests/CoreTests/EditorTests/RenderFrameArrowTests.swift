// ABOUTME: RenderFrame.from surfaces the in-progress item: a pen stroke as .stroke,
// ABOUTME: an Editor transient arrow as .arrow; the transient is not in the committed set.

import Foundation
import Testing

@Suite("RenderFrame arrow")
struct RenderFrameArrowTests {
    @MainActor private func makeEditor() -> Editor {
        Editor(clock: VirtualClock(), ids: SeededIdGenerator(prefix: "s"))
    }

    @MainActor @Test("surfaces an in-progress arrow")
    func surfacesInProgressArrow() {
        let e = makeEditor()
        _ = e.beginArrow(color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 8, tail: Point(x: 0, y: 0))
        e.updateArrowHead(to: Point(x: 40, y: 0))
        let frame = RenderFrame.from(editor: e, canvasSize: Size(width: 100, height: 100))
        guard case .arrow(let a)? = frame.inProgress else {
            Issue.record("expected an in-progress arrow"); return
        }
        #expect(a.head == Point(x: 40, y: 0))
        #expect(frame.items.isEmpty)
    }
}
