// ABOUTME: Tests for POST /outline route and outlineEnabled field in GET /state.
// ABOUTME: Uses FakeSurface and ephemeral-port DevHTTPServer; real URLSession.

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

    @Test("POST /outline {enabled: true} sets outlineEnabled on surface")
    func outlineEnable() async throws {
        let surface = FakeSurface()
        let server = try DevHTTPServer(surface: surface, port: 0); try server.start(); defer { server.stop() }
        let status = try await postStatus(server, "/outline", body: #"{"enabled":true}"#)
        #expect(status == 200)
        #expect(surface.outlineEnabled == true)
    }

    @Test("POST /outline {enabled: false} clears outlineEnabled on surface")
    func outlineDisable() async throws {
        let surface = FakeSurface()
        surface.outlineEnabled = true
        let server = try DevHTTPServer(surface: surface, port: 0); try server.start(); defer { server.stop() }
        let status = try await postStatus(server, "/outline", body: #"{"enabled":false}"#)
        #expect(status == 200)
        #expect(surface.outlineEnabled == false)
    }

    @Test("POST /outline with missing body returns 400")
    func outlineMissingBody() async throws {
        let surface = FakeSurface()
        let server = try DevHTTPServer(surface: surface, port: 0); try server.start(); defer { server.stop() }
        #expect(try await postStatus(server, "/outline", body: "{}") == 400)
    }

    @Test("POST /outline toggles the surface and /state reports it")
    func outlineRoute() async throws {
        let surface = FakeSurface()
        let server = try DevHTTPServer(surface: surface, port: 0); try server.start(); defer { server.stop() }
        let status = try await postStatus(server, "/outline", body: #"{"enabled":true}"#)
        #expect(status == 200)
        #expect(surface.outlineEnabled == true)
        let (stateStatus, json) = try await get(server, "/state")
        #expect(stateStatus == 200)
        #expect(json["outlineEnabled"] as? Bool == true)
    }

    @Test("GET /state includes outlineEnabled field")
    func stateIncludesOutlineEnabled() async throws {
        let surface = FakeSurface()
        surface.outlineEnabled = true
        let server = try DevHTTPServer(surface: surface, port: 0); try server.start(); defer { server.stop() }
        let (status, json) = try await get(server, "/state")
        #expect(status == 200)
        #expect(json["outlineEnabled"] as? Bool == true)
    }

    @Test("GET /state outlineEnabled defaults to false")
    func stateOutlineEnabledDefault() async throws {
        let surface = FakeSurface()
        let server = try DevHTTPServer(surface: surface, port: 0); try server.start(); defer { server.stop() }
        let (_, json) = try await get(server, "/state")
        #expect(json["outlineEnabled"] as? Bool == false)
    }
}
