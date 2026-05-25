// ABOUTME: Tests for POST /outline {tool, enabled} route and the outline.{text,arrow,pen}
// ABOUTME: object in GET /state. Uses FakeSurface and ephemeral-port DevHTTPServer.

import Foundation
import Testing

@Suite("Outline routes")
@MainActor
struct OutlineRouteTests {
    private func post(_ server: DevHTTPServer, _ path: String, body: String) async throws -> (Int, Data) {
        let port = try #require(server.boundPort)
        var req = URLRequest(url: try #require(URL(string: "http://localhost:\(port)\(path)")))
        req.httpMethod = "POST"
        req.httpBody = Data(body.utf8)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.data(for: req)
        let http = try #require(response as? HTTPURLResponse)
        return (http.statusCode, data)
    }

    private func postStatus(_ server: DevHTTPServer, _ path: String, body: String) async throws -> Int {
        let (status, _) = try await post(server, path, body: body)
        return status
    }

    private func get(_ server: DevHTTPServer, _ path: String) async throws -> (Int, [String: Any]) {
        let port = try #require(server.boundPort)
        let url = try #require(URL(string: "http://localhost:\(port)\(path)"))
        let (data, response) = try await URLSession.shared.data(from: url)
        let http = try #require(response as? HTTPURLResponse)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return (http.statusCode, json)
    }

    @Test("POST /outline sets the named tool on the surface")
    func outlineEnable() async throws {
        let surface = FakeSurface()
        surface.penOutline = false
        let server = try DevHTTPServer(surface: surface, port: 0); try server.start(); defer { server.stop() }
        let status = try await postStatus(server, "/outline", body: #"{"tool":"pen","enabled":true}"#)
        #expect(status == 200)
        #expect(surface.penOutline == true)
        #expect(surface.textOutline == true)   // other tools untouched
    }

    @Test("POST /outline can clear a tool")
    func outlineDisable() async throws {
        let surface = FakeSurface()
        let server = try DevHTTPServer(surface: surface, port: 0); try server.start(); defer { server.stop() }
        let status = try await postStatus(server, "/outline", body: #"{"tool":"text","enabled":false}"#)
        #expect(status == 200)
        #expect(surface.textOutline == false)
    }

    @Test("POST /outline with missing fields returns 400")
    func outlineMissingBody() async throws {
        let surface = FakeSurface()
        let server = try DevHTTPServer(surface: surface, port: 0); try server.start(); defer { server.stop() }
        #expect(try await postStatus(server, "/outline", body: "{}") == 400)
    }

    @Test("POST /outline with an unknown tool returns 400")
    func outlineUnknownTool() async throws {
        let surface = FakeSurface()
        let server = try DevHTTPServer(surface: surface, port: 0); try server.start(); defer { server.stop() }
        #expect(try await postStatus(server, "/outline", body: #"{"tool":"laser","enabled":true}"#) == 400)
    }

    @Test("GET /state reports the per-tool outline flags")
    func stateIncludesOutline() async throws {
        let surface = FakeSurface()
        surface.textOutline = true
        surface.arrowOutline = false
        surface.penOutline = true
        let server = try DevHTTPServer(surface: surface, port: 0); try server.start(); defer { server.stop() }
        let (status, json) = try await get(server, "/state")
        #expect(status == 200)
        let outline = try #require(json["outline"] as? [String: Any])
        #expect(outline["text"] as? Bool == true)
        #expect(outline["arrow"] as? Bool == false)
        #expect(outline["pen"] as? Bool == true)
    }
}
