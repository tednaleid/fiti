// ABOUTME: Tests for CanvasView's selection setters — selection bounds and
// ABOUTME: marquee rect storage and idempotent set behavior.

import AppKit
import Testing

@Suite("CanvasView selection")
@MainActor
struct CanvasViewSelectionTests {
    private func makeCanvas() -> CanvasView {
        CanvasView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
    }

    @Test("selectionBounds defaults to nil")
    func selectionDefaultsNil() {
        #expect(makeCanvas().selectionBounds == nil)
    }

    @Test("setSelectionBounds stores the value")
    func setStoresSelection() {
        let canvas = makeCanvas()
        let rect = Rect(x: 10, y: 10, width: 50, height: 50)
        canvas.setSelectionBounds(rect)
        #expect(canvas.selectionBounds == rect)
    }

    @Test("idempotent setSelectionBounds does not redraw")
    func idempotentSelectionSet() {
        let canvas = makeCanvas()
        let rect = Rect(x: 10, y: 10, width: 50, height: 50)
        canvas.setSelectionBounds(rect)
        canvas.needsDisplay = false
        canvas.setSelectionBounds(rect)
        #expect(canvas.needsDisplay == false)
    }

    @Test("setMarquee stores the value")
    func marqueeSet() {
        let canvas = makeCanvas()
        canvas.setMarquee(Rect(x: 0, y: 0, width: 30, height: 30))
        #expect(canvas.marqueeRect == Rect(x: 0, y: 0, width: 30, height: 30))
    }

    @Test("setMarquee(nil) clears the rectangle")
    func marqueeClears() {
        let canvas = makeCanvas()
        canvas.setMarquee(Rect(x: 0, y: 0, width: 30, height: 30))
        canvas.setMarquee(nil)
        #expect(canvas.marqueeRect == nil)
    }
}
