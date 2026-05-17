// ABOUTME: Tests for the in-memory adapters used by AppController tests.

import Testing

@MainActor
@Suite("Port doubles")
struct PortDoublesTests {
    @Test("RecordingRenderer captures every frame")
    func recordingRenderer() {
        let r = RecordingRenderer()
        let frame = RenderFrame(strokes: [], inProgress: nil, canvasSize: Size(width: 100, height: 100))
        r.render(frame)
        r.render(frame)
        #expect(r.frames.count == 2)
    }

    @Test("RecordingWindow records click-through and focus calls")
    func recordingWindow() {
        let w = RecordingWindow()
        w.setClickThrough(true)
        w.setClickThrough(false)
        w.focus()
        #expect(w.clickThroughHistory == [true, false])
        #expect(w.focusCount == 1)
    }
}
