// ABOUTME: Tests for color/size/opacity shortcuts retargeting the selection —
// ABOUTME: when currentTool == .selection with a live selection, run(_:) mutates
// ABOUTME: the selected items (re-measuring text bounds) instead of the brush.

import Testing

@Suite("AppController.run(_:) selection retargeting")
@MainActor
struct SelectionStyleCommandTests {
    // swiftlint:disable:next large_tuple
    private func make() -> (AppController, Editor, VirtualClock) {
        let clock = VirtualClock()
        let editor = Editor(clock: clock, ids: SeededIdGenerator(prefix: "s"))
        let controller = AppController(
            editor: editor,
            window: RecordingWindow(),
            detector: RecordingStationaryDetector(),
            clock: clock,
            ticker: RecordingFadeTicker(),
            textMeasurer: FakeTextMeasurer()
        )
        return (controller, editor, clock)
    }

    /// Lays down two strokes and a text item; returns their ids in order.
    private func seedThreeItems(_ c: AppController, _ editor: Editor) -> [ItemId] {
        c.activate()
        c.pointerDown(StrokePoint(x: 0, y: 0)); c.pointerUp()
        c.pointerDown(StrokePoint(x: 10, y: 10)); c.pointerUp()
        let textId = editor.newItemId()
        editor.addItem(.text(TextItem(id: textId, string: "ab", fontName: "Helvetica",
                                      fontSize: 24, color: RGBA(r: 0, g: 0, b: 0, a: 0.5),
                                      transform: .identity, bounds: Size(width: 24, height: 24),
                                      createdAt: 0)))
        return editor.doc.itemOrder
    }

    @Test("pickColor in selection mode recolors selected items (preserving each alpha), not the brush")
    func pickColorRetargetsSelection() {
        let (c, editor, _) = make()
        let ids = seedThreeItems(c, editor)
        let brushBefore = c.currentColor
        c.currentTool = .selection
        c.selectedStrokeIds = ids
        c.run(.pickColor(5))  // Green
        let green = QuickPickPalette.colors[5]
        for id in ids {
            let color = editor.doc.items[id]!.color
            #expect(abs(color.r - green.r) < 0.0001)
            #expect(abs(color.g - green.g) < 0.0001)
            #expect(abs(color.b - green.b) < 0.0001)
        }
        #expect(editor.doc.items[ids[2]]!.color.a == 0.5)  // text kept its own alpha
        #expect(c.currentColor == brushBefore)             // brush default untouched
    }

    @Test("bumpOpacity in selection mode shifts each selected item's alpha")
    func bumpOpacityRetargetsSelection() {
        let (c, editor, _) = make()
        let ids = seedThreeItems(c, editor)
        c.currentTool = .selection
        c.selectedStrokeIds = [ids[2]]  // the text item at a=0.5
        c.run(.bumpOpacity(.down))
        #expect(abs(editor.doc.items[ids[2]]!.color.a - 0.4) < 0.0001)
    }

    @Test("bumpSize in selection mode scales stroke width and re-measures text bounds")
    func bumpSizeRetargetsSelection() {
        let (c, editor, _) = make()
        let ids = seedThreeItems(c, editor)
        guard case .stroke(let strokeBefore)? = editor.doc.items[ids[0]] else {
            Issue.record("expected a stroke"); return
        }
        c.currentTool = .selection
        c.selectedStrokeIds = ids
        c.run(.bumpSize(.up))
        guard case .stroke(let strokeAfter)? = editor.doc.items[ids[0]] else {
            Issue.record("expected a stroke"); return
        }
        #expect(abs(strokeAfter.width - strokeBefore.width * 1.1) < 0.0001)
        guard case .text(let textAfter)? = editor.doc.items[ids[2]] else {
            Issue.record("expected text"); return
        }
        // fontSize 24 -> 26.4; FakeTextMeasurer bounds = (chars * size/2, size)
        #expect(abs(textAfter.fontSize - 26.4) < 0.0001)
        #expect(abs(textAfter.bounds.width - 26.4) < 0.0001)   // "ab" = 2 * (26.4/2)
        #expect(abs(textAfter.bounds.height - 26.4) < 0.0001)
    }

    @Test("style shortcut in selection mode is one undo step")
    func styleShortcutSingleUndo() {
        let (c, editor, _) = make()
        let ids = seedThreeItems(c, editor)
        c.currentTool = .selection
        c.selectedStrokeIds = ids
        c.run(.pickColor(5))  // all three -> green
        _ = editor.undo()     // single step reverts all three
        guard case .stroke(let s)? = editor.doc.items[ids[0]] else {
            Issue.record("expected a stroke"); return
        }
        #expect(abs(s.color.r - 224.0/255.0) < 0.0001)  // back to default red
    }

    @Test("style shortcut with empty selection falls through to brush defaults")
    func styleShortcutEmptySelectionFallsThrough() {
        let (c, _, _) = make()
        c.currentColor = RGBA(r: 0, g: 0, b: 0, a: 1)
        c.currentTool = .selection
        c.selectedStrokeIds = []  // nothing selected
        c.run(.pickColor(5))      // Green
        let green = QuickPickPalette.colors[5]
        #expect(abs(c.currentColor.r - green.r) < 0.0001)  // brush changed (default path)
    }
}
