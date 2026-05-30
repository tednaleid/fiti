// ABOUTME: Text-tool pointer routing and commit. Click blank starts a new text;
// ABOUTME: click on existing text edits it at the reverse-mapped caret.

import Foundation

extension AppController {
    public func escapePressed() {
        if isEditingText {
            commitText()   // stay in the text tool, ready for the next text
        } else {
            deactivate()
        }
    }

    func textPointerDown(_ point: StrokePoint) {
        revealDrawingsForNewMark()
        if isEditingText { commitText() }
        let p = Point(x: point.x, y: point.y)
        if let hitId = SelectionMath.hitTestItem(at: p, items: editor.doc.items,
                                                 order: editor.doc.itemOrder,
                                                 tolerance: SelectionMetrics.handleHitRadius),
           case .text(let t)? = editor.doc.items[hitId] {
            beginEditing(t, at: p)
        } else {
            beginNewText(at: p)
        }
        refreshCursor()
    }

    private func beginNewText(at p: Point) {
        textSession = TextEditSession(
            itemId: nil, string: "", caret: 0,
            transform: Transform(x: p.x, y: p.y, scale: 1, rotate: 0),
            color: currentColor, fontName: "Helvetica", fontSize: textFontSize(forWidth: currentWidth))
    }

    private func beginEditing(_ t: TextItem, at p: Point) {
        // Map the world click into the item's local space (translate only for v1).
        let local = Point(x: p.x - t.transform.x, y: p.y - t.transform.y)
        let caret = textMeasurer.caretIndex(at: local, string: t.string,
                                            fontName: t.fontName, fontSize: t.fontSize)
        textSession = TextEditSession(itemId: t.id, string: t.string, caret: caret,
                                      transform: t.transform, color: t.color,
                                      fontName: t.fontName, fontSize: t.fontSize)
    }

    public func insertText(_ s: String) { textSession?.insert(s); fireSession() }
    public func deleteBackward() { textSession?.deleteBackward(); fireSession() }
    public func insertNewline() { textSession?.insertNewline(); fireSession() }
    public func moveCaret(_ d: TextEditSession.CaretMove) { textSession?.moveCaret(d); fireSession() }

    private func fireSession() { onTextSessionChanged?(textSession) }

    public func commitText() {
        guard let s = textSession else { return }
        let text = s.string
        let measured = textMeasurer.measure(string: text, fontName: s.fontName, fontSize: s.fontSize)
        if let id = s.itemId {
            if text.isEmpty { _ = editor.eraseItems(ids: [id]) } else {
                let item = TextItem(id: id, string: text, fontName: s.fontName, fontSize: s.fontSize,
                                    color: s.color, transform: s.transform, bounds: measured,
                                    createdAt: clock.now())
                _ = editor.replaceItem(.text(item))
            }
        } else if !text.isEmpty {
            let id = editor.newItemId()
            let item = TextItem(id: id, string: text, fontName: s.fontName, fontSize: s.fontSize,
                                color: s.color, transform: s.transform, bounds: measured,
                                createdAt: clock.now())
            editor.addItem(.text(item))
        }
        // Clear the session last: its didSet fires onTextSessionChanged?(nil) as the
        // sole notification, by which point the committed item is already in the doc.
        textSession = nil
        refreshCursor()
    }
}
