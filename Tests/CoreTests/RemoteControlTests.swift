import Testing
@testable import Core

@MainActor
@Suite("RemoteControl parsing")
struct RemoteControlTests {
    @Test("parse startStroke message")
    func parseStartStroke() {
        let json: [String: Any] = [
            "type": "startStroke",
            "strokeId": "abc123",
            "tool": "pen",
            "color": "#FF00FF",
            "width": 3.0,
            "point": ["x": 0.1, "y": 0.9, "pressure": 0.7, "t": 123.456]
        ]
        let data = try! JSONSerialization.data(withJSONObject: json, options: [])
        let action = try! parseRemoteAction(from: data)
        switch action {
        case .startStroke(let s):
            #expect(s.strokeId == "abc123")
            #expect(s.tool == .pen)
            #expect(s.color == "#FF00FF")
            #expect(s.width == 3.0)
            #expect(s.point.x == 0.1)
            #expect(s.point.y == 0.9)
            #expect(s.point.pressure == 0.7)
        default:
            #expect(false)
        }
    }

    @Test("parse appendPoints message")
    func parseAppendPoints() {
        let json: [String: Any] = [
            "type": "appendPoints",
            "strokeId": "s1",
            "points": [["x": 0.2, "y": 0.3, "pressure": 0.5], ["x": 0.25, "y": 0.35]]
        ]
        let data = try! JSONSerialization.data(withJSONObject: json, options: [])
        let action = try! parseRemoteAction(from: data)
        switch action {
        case .appendPoints(let a):
            #expect(a.strokeId == "s1")
            #expect(a.points.count == 2)
            #expect(a.points[0].pressure == 0.5)
            #expect(a.points[1].pressure == nil)
        default:
            #expect(false)
        }
    }

    @Test("parse endStroke message")
    func parseEndStroke() {
        let json: [String: Any] = ["type": "endStroke", "strokeId": "s1"]
        let data = try! JSONSerialization.data(withJSONObject: json, options: [])
        let action = try! parseRemoteAction(from: data)
        switch action {
        case .endStroke(let id):
            #expect(id == "s1")
        default:
            #expect(false)
        }
    }

    @Test("parse undo/redo")
    func parseUndoRedo() {
        let a = try! parseRemoteAction(from: try! JSONSerialization.data(withJSONObject: ["type":"undo"], options: []))
        let b = try! parseRemoteAction(from: try! JSONSerialization.data(withJSONObject: ["type":"redo"], options: []))
        switch (a,b) {
        case (.undo, .redo):
            #expect(true)
        default:
            #expect(false)
        }
    }

    @Test("invalid messages produce errors")
    func parseInvalid() {
        let data = "notjson".data(using: .utf8)!
        do {
            _ = try parseRemoteAction(from: data)
            #expect(false)
        } catch {
            #expect(true)
        }
    }
}
