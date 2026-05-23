// ABOUTME: Tests for GET /state and GET /doc routes.
// ABOUTME: Uses a FakeSurface and an ephemeral-port DevHTTPServer; real URLSession.

import Foundation
import Testing

@Suite("/state and /doc")
@MainActor
struct StateAndDocTests {
    private func startServer(_ surface: FakeSurface) throws -> DevHTTPServer {
        let server = try DevHTTPServer(surface: surface, port: 0)
        try server.start()
        return server
    }

    private func get(_ server: DevHTTPServer, _ path: String) async throws -> (Int, [String: Any]) {
        let port = try #require(server.boundPort)
        let url = try #require(URL(string: "http://localhost:\(port)\(path)"))
        let (data, response) = try await URLSession.shared.data(from: url)
        let http = try #require(response as? HTTPURLResponse)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return (http.statusCode, json)
    }

    @Test("/state returns mode, clickThrough, canvasSize, undo/redo depth")
    func state() async throws {
        let surface = FakeSurface()
        surface.mode = .activeIdle
        surface.clickThrough = false
        surface.undoDepth = 3
        surface.redoDepth = 1
        surface.currentColor = RGBA(r: 0.25, g: 0.5, b: 0.75, a: 1)
        surface.currentWidth = 4
        surface.drawingsVisible = true
        let server = try startServer(surface); defer { server.stop() }
        let (status, json) = try await get(server, "/state")
        #expect(status == 200)
        #expect((json["mode"] as? String) == "activeIdle")
        #expect((json["clickThrough"] as? Bool) == false)
        #expect((json["undoDepth"] as? Int) == 3)
        #expect((json["redoDepth"] as? Int) == 1)
        let color = try #require(json["color"] as? [String: Any])
        #expect(color["r"] as? Double == 0.25)
        #expect(color["g"] as? Double == 0.5)
        #expect(color["b"] as? Double == 0.75)
        #expect(color["a"] as? Double == 1)
        #expect(json["width"] as? Double == 4)
        #expect(json["drawingsVisible"] as? Bool == true)
    }

    @Test("/doc returns FitiDoc JSON")
    func doc() async throws {
        let surface = FakeSurface()
        let s = Stroke(id: "a", color: RGBA(r: 1, g: 0, b: 0, a: 1), width: 2, transform: .identity,
                       points: [StrokePoint(x: 1, y: 2)], pointerType: .mouse, pressureEnabled: false, createdAt: 0)
        surface.doc = FitiDoc(items: ["a": .stroke(s)], itemOrder: ["a"])
        let server = try startServer(surface); defer { server.stop() }
        let (status, json) = try await get(server, "/doc")
        #expect(status == 200)
        #expect((json["itemOrder"] as? [String]) == ["a"])
    }
}
