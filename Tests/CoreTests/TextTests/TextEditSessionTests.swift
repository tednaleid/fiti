// ABOUTME: Pure edit-buffer behavior — insert, delete, newline, caret motion
// ABOUTME: including up/down across hard-break lines, with clamping.

import Testing

@Suite("TextEditSession")
struct TextEditSessionTests {
    private func session(_ s: String, caret: Int) -> TextEditSession {
        TextEditSession(itemId: nil, string: s, caret: caret, transform: .identity,
                        color: RGBA(r: 0, g: 0, b: 0, a: 1), fontName: "Helvetica", fontSize: 24)
    }

    @Test("insert places text at the caret and advances it")
    func insert() {
        var s = session("ac", caret: 1)
        s.insert("b")
        #expect(s.string == "abc"); #expect(s.caret == 2)
    }

    @Test("deleteBackward removes the char before the caret")
    func deleteBackward() {
        var s = session("abc", caret: 2)
        s.deleteBackward()
        #expect(s.string == "ac"); #expect(s.caret == 1)
    }

    @Test("deleteBackward at index 0 is a no-op")
    func deleteAtStart() {
        var s = session("abc", caret: 0)
        s.deleteBackward()
        #expect(s.string == "abc"); #expect(s.caret == 0)
    }

    @Test("insertNewline inserts \\n")
    func newline() {
        var s = session("ab", caret: 1)
        s.insertNewline()
        #expect(s.string == "a\nb"); #expect(s.caret == 2)
    }

    @Test("moveCaret down keeps the column across lines")
    func caretDown() {
        var s = session("abcd\nef", caret: 3)   // line 0, col 3
        s.moveCaret(.down)                       // line 1 has only 2 chars -> clamp to col 2
        #expect(s.caret == 7)                    // index of end of "ef"
    }

    @Test("moveCaret left/right clamps at ends")
    func caretEnds() {
        var s = session("ab", caret: 0)
        s.moveCaret(.left); #expect(s.caret == 0)
        s.moveCaret(.right); s.moveCaret(.right); s.moveCaret(.right); #expect(s.caret == 2)
    }
}
