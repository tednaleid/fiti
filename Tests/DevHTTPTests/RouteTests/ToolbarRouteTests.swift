// ABOUTME: HTTP route tests for the toolbar surface — POST /color, /width,
// ABOUTME: /drawings/show, /drawings/hide. Mirror what the toolbar widgets do.

import Foundation
import Testing

@Suite("Toolbar routes")
@MainActor
struct ToolbarRouteTests {
    private func startServer(surface: FakeSurface) async throws -> DevHTTPServer {
        let server = try DevHTTPServer(surface: surface, port: 0)
        try server.start()
        return server
    }

    private func postJSON(path: String, body: Data, port: Int) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: try #require(URL(string: "http://localhost:\(port)\(path)")))
        req.httpMethod = "POST"
        if !body.isEmpty {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        let http = try #require(response as? HTTPURLResponse)
        return (data, http)
    }

    private func get(path: String, port: Int) async throws -> (Data, HTTPURLResponse) {
        let url = try #require(URL(string: "http://localhost:\(port)\(path)"))
        let (data, response) = try await URLSession.shared.data(from: url)
        let http = try #require(response as? HTTPURLResponse)
        return (data, http)
    }

    @Test("POST /color sets the surface's currentColor")
    func postColor() async throws {
        let surface = FakeSurface()
        let server = try await startServer(surface: surface)
        defer { server.stop() }
        let body = Data(#"{"r":0.1,"g":0.2,"b":0.3,"a":0.4}"#.utf8)
        let (_, response) = try await postJSON(path: "/color", body: body, port: server.boundPort ?? 0)
        #expect(response.statusCode == 200)
        #expect(surface.currentColor == RGBA(r: 0.1, g: 0.2, b: 0.3, a: 0.4))
    }

    @Test("POST /width sets the surface's currentWidth")
    func postWidth() async throws {
        let surface = FakeSurface()
        let server = try await startServer(surface: surface)
        defer { server.stop() }
        let body = Data(#"{"width":11}"#.utf8)
        let (_, response) = try await postJSON(path: "/width", body: body, port: server.boundPort ?? 0)
        #expect(response.statusCode == 200)
        #expect(surface.currentWidth == 11)
    }

    @Test("POST /drawings/hide sets drawingsVisible to false")
    func postHide() async throws {
        let surface = FakeSurface()
        let server = try await startServer(surface: surface)
        defer { server.stop() }
        let (_, response) = try await postJSON(path: "/drawings/hide", body: Data(), port: server.boundPort ?? 0)
        #expect(response.statusCode == 200)
        #expect(surface.drawingsVisible == false)
    }

    @Test("POST /drawings/show sets drawingsVisible to true")
    func postShow() async throws {
        let surface = FakeSurface()
        surface.drawingsVisible = false
        let server = try await startServer(surface: surface)
        defer { server.stop() }
        let (_, response) = try await postJSON(path: "/drawings/show", body: Data(), port: server.boundPort ?? 0)
        #expect(response.statusCode == 200)
        #expect(surface.drawingsVisible == true)
    }

    @Test("GET /state includes color, width, drawingsVisible")
    func stateIncludesToolbarFields() async throws {
        let surface = FakeSurface()
        surface.currentColor = RGBA(r: 0.5, g: 0.5, b: 0.5, a: 1)
        surface.currentWidth = 7
        surface.drawingsVisible = false
        let server = try await startServer(surface: surface)
        defer { server.stop() }
        let (data, response) = try await get(path: "/state", port: server.boundPort ?? 0)
        #expect(response.statusCode == 200)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let color = try #require(json["color"] as? [String: Any])
        #expect(color["r"] as? Double == 0.5)
        #expect(json["width"] as? Double == 7)
        #expect(json["drawingsVisible"] as? Bool == false)
    }
}
