// ABOUTME: Integration tests for FitiDevHTTPSurface — the production bridge
// ABOUTME: between the HTTP server and AppController + Editor + SnapshotRenderer.

import Foundation
import Testing

@Suite("FitiDevHTTPSurface")
@MainActor
struct FitiDevHTTPSurfaceTests {
    private struct Rig {
        let bridge: FitiDevHTTPSurface
        let controller: AppController
        let window: RecordingWindow
    }

    private func makeBridge() -> Rig {
        let window = RecordingWindow()
        let editor = Editor(clock: VirtualClock(), ids: SeededIdGenerator(prefix: "s"))
        let controller = AppController(
            editor: editor,
            window: window,
            detector: RecordingStationaryDetector(),
            clock: VirtualClock(),
            ticker: RecordingFadeTicker(),
            textMeasurer: CoreTextMeasurer()
        )
        let bridge = FitiDevHTTPSurface(controller: controller,
                                        canvasSize: { Size(width: 100, height: 100) })
        return Rig(bridge: bridge, controller: controller, window: window)
    }

    @Test("pointerDown while inactive auto-activates and starts a stroke")
    func autoActivateOnDown() {
        let rig = makeBridge()
        rig.bridge.pointerDown(StrokePoint(x: 10, y: 20))
        #expect(rig.controller.mode == .activeDrawing)
        #expect(rig.window.clickThroughHistory.last == false)
        #expect(rig.controller.editor.currentStrokeId == "s-1")
    }

    @Test("pointerMoved without prior down still starts a stroke")
    func moveWithoutDownStarts() {
        let rig = makeBridge()
        rig.bridge.pointerMoved(StrokePoint(x: 10, y: 20))
        #expect(rig.controller.mode == .activeDrawing)
        #expect(rig.controller.editor.currentStrokeId == "s-1")
    }

    @Test("snapshotPNG produces a PNG with the right magic bytes")
    func snapshot() throws {
        let rig = makeBridge()
        let data = try #require(rig.bridge.snapshotPNG())
        #expect(data.prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
    }

    @Test("clear empties the editor doc")
    func clear() {
        let rig = makeBridge()
        rig.bridge.pointerDown(StrokePoint(x: 0, y: 0))
        rig.bridge.pointerUp()
        #expect(rig.controller.editor.doc.itemOrder.count == 1)
        rig.bridge.clear()
        #expect(rig.controller.editor.doc.itemOrder.isEmpty)
    }
}
