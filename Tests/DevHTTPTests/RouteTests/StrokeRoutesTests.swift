// ABOUTME: Tests for GET /strokes/{id} and POST /strokes/{id}/erase.
// ABOUTME: Uses FakeSurface and ephemeral-port DevHTTPServer; real URLSession.

import Foundation
import Testing

@Suite("/strokes/:id routes")
struct StrokeRoutesTests {
    @Test("GET /strokes/{id} returns the stroke")
    func getStroke() async throws {
        let surface = FakeSurface()
        let s = Stroke(id: "abc", color: RGBA(r: 0, g: 1, b: 0, a: 1), width: 3, transform: .identity,
                       points: [StrokePoint(x: 5, y: 5)], pointerType: .mouse, pressureEnabled: false, createdAt: 0)
        surface.doc = FitiDoc(strokes: ["abc": s], strokeOrder: ["abc"])
        let server = try DevHTTPServer(surface: surface, port: 0); try server.start(); defer { server.stop() }
        let port = try #require(server.boundPort)
        let url = try #require(URL(string: "http://localhost:\(port)/strokes/abc"))
        let (data, response) = try await URLSession.shared.data(from: url)
        let http = try #require(response as? HTTPURLResponse)
        #expect(http.statusCode == 200)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect((json["id"] as? String) == "abc")
    }

    @Test("GET /strokes/{id} returns 404 for unknown id")
    func get404() async throws {
        let surface = FakeSurface()
        let server = try DevHTTPServer(surface: surface, port: 0); try server.start(); defer { server.stop() }
        let port = try #require(server.boundPort)
        let url = try #require(URL(string: "http://localhost:\(port)/strokes/nope"))
        let (_, response) = try await URLSession.shared.data(from: url)
        let http = try #require(response as? HTTPURLResponse)
        #expect(http.statusCode == 404)
    }

    @Test("POST /strokes/{id}/erase calls eraseStroke on the surface")
    func postErase() async throws {
        let surface = FakeSurface()
        let server = try DevHTTPServer(surface: surface, port: 0); try server.start(); defer { server.stop() }
        let port = try #require(server.boundPort)
        let url = try #require(URL(string: "http://localhost:\(port)/strokes/abc/erase"))
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        let (_, response) = try await URLSession.shared.data(for: req)
        let http = try #require(response as? HTTPURLResponse)
        #expect(http.statusCode == 200)
        #expect(surface.erasedIds == ["abc"])
    }
}
