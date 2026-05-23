// ABOUTME: Tests for the RenderFrame.from(editor:canvasSize:) helper.
// ABOUTME: Verifies item ordering, in-progress extraction, committed/live split, and editingItemId exclusion.

import Testing

@Suite("RenderFrame.from(editor:)")
struct RenderFrameFromTests {
    @Test("orders strokes by itemOrder, exposes in-progress separately")
    @MainActor
    func ordersStrokes() {
        let e = Editor(clock: VirtualClock(), ids: SeededIdGenerator(prefix: "s"))
        _ = e.startStroke(color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 1, pointerType: .mouse)
        e.endStroke()
        _ = e.startStroke(color: RGBA(r: 0, g: 1, b: 0, a: 1), width: 1, pointerType: .mouse)
        e.endStroke()
        _ = e.startStroke(color: RGBA(r: 0, g: 0, b: 1, a: 1), width: 1, pointerType: .mouse) // in progress

        let frame = RenderFrame.from(editor: e, canvasSize: Size(width: 800, height: 600))
        #expect(frame.items.map { $0.id } == ["s-1", "s-2", "s-3"])
        #expect(frame.inProgress?.id == "s-3")
        #expect(frame.canvasSize == Size(width: 800, height: 600))
    }

    @Test("no in-progress when no current stroke")
    @MainActor
    func noInProgress() {
        let e = Editor(clock: VirtualClock(), ids: SeededIdGenerator(prefix: "s"))
        _ = e.startStroke(color: RGBA(r: 0, g: 0, b: 0, a: 1), width: 1, pointerType: .mouse)
        e.endStroke()
        let frame = RenderFrame.from(editor: e, canvasSize: Size(width: 100, height: 100))
        #expect(frame.inProgress == nil)
    }

    @Test("from(overrides:) routes overridden strokes to liveItems with the override applied")
    @MainActor
    func overridesGoLive() {
        let e = Editor(clock: VirtualClock(), ids: SeededIdGenerator(prefix: "s"))
        _ = e.startStroke(color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 1, pointerType: .mouse)
        e.endStroke()
        _ = e.startStroke(color: RGBA(r: 0, g: 1, b: 0, a: 1), width: 1, pointerType: .mouse)
        e.endStroke()

        let override = Transform(x: 20, y: 30, scale: 1, rotate: 0)
        let frame = RenderFrame.from(editor: e, canvasSize: Size(width: 100, height: 100),
                                     overrides: ["s-2": override])

        // s-1 stays committed (no override)
        #expect(frame.items.map { $0.id } == ["s-1"])
        // s-2 goes live with the override transform applied
        #expect(frame.liveItems.map { $0.id } == ["s-2"])
        #expect(frame.liveItems.first?.transform == override)
        // no cross-contamination
        #expect(frame.items.first?.id != "s-2")
        #expect(frame.liveItems.first?.id != "s-1")
    }

    @Test("from with empty overrides puts everything in items and nothing in liveItems")
    @MainActor
    func noOverridesAllCommitted() {
        let e = Editor(clock: VirtualClock(), ids: SeededIdGenerator(prefix: "s"))
        _ = e.startStroke(color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 1, pointerType: .mouse)
        e.endStroke()
        _ = e.startStroke(color: RGBA(r: 0, g: 1, b: 0, a: 1), width: 1, pointerType: .mouse)
        e.endStroke()

        let frame = RenderFrame.from(editor: e, canvasSize: Size(width: 100, height: 100))
        #expect(frame.items.map { $0.id } == ["s-1", "s-2"])
        #expect(frame.liveItems.isEmpty)
    }

    @Test("editingItemId is excluded from committed items")
    @MainActor
    func excludesEditing() {
        let e = Editor(clock: VirtualClock(), ids: SeededIdGenerator(prefix: "i"))
        e.addItem(.text(TextItem(id: "t1", string: "hi", fontName: "Helvetica", fontSize: 24,
                                 color: RGBA(r: 0, g: 0, b: 0, a: 1), transform: .identity,
                                 bounds: Size(width: 24, height: 24), createdAt: 0)))
        let frame = RenderFrame.from(editor: e, canvasSize: Size(width: 100, height: 100),
                                     overrides: [:], editingItemId: "t1")
        #expect(frame.items.contains { $0.id == "t1" } == false)
    }
}
