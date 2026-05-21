// ABOUTME: Tests for the Tool enum — covers the two cases shipped in v1
// ABOUTME: (.pen default, .selection) and their equality.

import Testing

@Suite("Tool")
struct ToolTests {
    @Test(".pen and .selection are distinct cases")
    func distinctCases() {
        #expect(Tool.pen != Tool.selection)
        #expect(Tool.pen == Tool.pen)
        #expect(Tool.selection == Tool.selection)
    }
}
