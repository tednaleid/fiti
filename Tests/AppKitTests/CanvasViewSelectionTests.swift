// ABOUTME: Tests for CanvasView's selection setters — selection box and
// ABOUTME: marquee rect storage and idempotent set behavior.

import AppKit
import Testing

@Suite("CanvasView selection")
@MainActor
struct CanvasViewSelectionTests {
    private func makeCanvas() -> CanvasView {
        CanvasView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
    }

    @Test("selectionBox defaults to nil")
    func selectionDefaultsNil() {
        #expect(makeCanvas().selectionBox == nil)
    }

    @Test("setSelectionBox stores the box")
    func setBoxStores() {
        let canvas = CanvasView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        let box = OrientedBox(center: Point(x: 100, y: 100), size: Size(width: 40, height: 20), rotation: 30)
        canvas.setSelectionBox(box)
        #expect(canvas.selectionBox == box)
    }

    @Test("setSelectionBox(nil) clears the chrome")
    func clearBox() {
        let canvas = CanvasView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        canvas.setSelectionBox(OrientedBox(center: Point(x: 10, y: 10), size: Size(width: 5, height: 5), rotation: 0))
        canvas.setSelectionBox(nil)
        #expect(canvas.selectionBox == nil)
    }

    @Test("idempotent setSelectionBox does not redraw")
    func idempotentSelectionSet() {
        let canvas = makeCanvas()
        let box = OrientedBox(center: Point(x: 50, y: 50), size: Size(width: 20, height: 10), rotation: 0)
        canvas.setSelectionBox(box)
        canvas.needsDisplay = false
        canvas.setSelectionBox(box)
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
