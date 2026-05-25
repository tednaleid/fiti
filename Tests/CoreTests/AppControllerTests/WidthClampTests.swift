// ABOUTME: Verifies the stroke-width cap is 100px for the size-bump command
// ABOUTME: and that the cap is exposed as AppController.maxStrokeWidth.

import Testing

@Suite("Stroke width clamp")
@MainActor
struct WidthClampTests {
    @Test("maxStrokeWidth is 100")
    func maxIs100() {
        #expect(AppController.maxStrokeWidth == 100)
    }

    @Test("bumpSize up clamps at 100, not 40")
    func bumpClampsAt100() {
        let clock = VirtualClock()
        let editor = Editor(clock: clock, ids: SeededIdGenerator(prefix: "s"))
        let c = AppController(editor: editor, window: RecordingWindow(),
                              detector: RecordingStationaryDetector(), clock: clock,
                              ticker: RecordingFadeTicker(), textMeasurer: FakeTextMeasurer())
        c.currentWidth = 95
        c.run(.bumpSize(.up))   // 95 * 1.1 = 104.5 -> clamps to 100
        #expect(c.currentWidth == 100)
    }
}
