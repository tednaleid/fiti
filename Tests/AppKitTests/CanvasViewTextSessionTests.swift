// ABOUTME: Smoke tests for CanvasView's text-session setter.
// ABOUTME: Verifies storage, clearing, and idempotent behavior without a real screen.

import AppKit
import Testing

@Suite("CanvasView text session")
@MainActor
struct CanvasViewTextSessionTests {
    private func makeCanvas() -> CanvasView {
        CanvasView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    }

    private func makeSnapshot() -> TextSessionSnapshot {
        TextSessionSnapshot(
            string: "hello",
            caret: 3,
            transform: Transform(x: 10, y: 20, scale: 1, rotate: 0),
            color: RGBA(r: 1, g: 0, b: 0, a: 1),
            fontName: "Helvetica",
            fontSize: 18
        )
    }

    @Test("textSession defaults to nil")
    func defaultsNil() {
        #expect(makeCanvas().textSession == nil)
    }

    @Test("setTextSession stores the snapshot")
    func storesSnapshot() {
        let canvas = makeCanvas()
        let snap = makeSnapshot()
        canvas.setTextSession(snap)
        #expect(canvas.textSession == snap)
    }

    @Test("setTextSession(nil) clears the session")
    func clearsSession() {
        let canvas = makeCanvas()
        canvas.setTextSession(makeSnapshot())
        canvas.setTextSession(nil)
        #expect(canvas.textSession == nil)
    }

    @Test("idempotent setTextSession does not redraw")
    func idempotentSet() {
        let canvas = makeCanvas()
        let snap = makeSnapshot()
        canvas.setTextSession(snap)
        canvas.needsDisplay = false
        canvas.setTextSession(snap)
        #expect(canvas.needsDisplay == false)
    }

    @Test("render with active session does not crash")
    func renderWithSessionNoCrash() {
        let canvas = makeCanvas()
        canvas.testOnly_overrideBackingScale = 1
        canvas.setTextSession(makeSnapshot())
        let frame = RenderFrame(items: [], liveItems: [], inProgress: nil,
                                canvasSize: Size(width: 400, height: 300))
        canvas.render(frame)
        // No crash is the assertion; needsDisplay is unreliable in headless tests.
        #expect(canvas.textSession != nil)
    }

    @Test("render after clearSession does not crash")
    func renderAfterClearNoCrash() {
        let canvas = makeCanvas()
        canvas.testOnly_overrideBackingScale = 1
        canvas.setTextSession(makeSnapshot())
        canvas.setTextSession(nil)
        let frame = RenderFrame(items: [], liveItems: [], inProgress: nil,
                                canvasSize: Size(width: 400, height: 300))
        canvas.render(frame)
        #expect(canvas.textSession == nil)
    }
}
