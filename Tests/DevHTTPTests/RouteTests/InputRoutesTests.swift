// ABOUTME: Tests for POST /pointer, /activate, /deactivate.
// ABOUTME: Uses FakeSurface and ephemeral-port DevHTTPServer; real URLSession.

import Foundation
import Testing

@Suite("Input routes")
@MainActor
struct InputRoutesTests {
    private func post(_ server: DevHTTPServer, _ path: String, body: String? = nil) async throws -> Int {
        let port = try #require(server.boundPort)
        var req = URLRequest(url: try #require(URL(string: "http://localhost:\(port)\(path)")))
        req.httpMethod = "POST"
        if let body {
            req.httpBody = Data(body.utf8)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (_, response) = try await URLSession.shared.data(for: req)
        let http = try #require(response as? HTTPURLResponse)
        return http.statusCode
    }

    @Test("POST /activate / /deactivate route to the surface")
    func activation() async throws {
        let surface = FakeSurface()
        let server = try DevHTTPServer(surface: surface, port: 0); try server.start(); defer { server.stop() }
        #expect(try await post(server, "/activate") == 200)
        #expect(try await post(server, "/deactivate") == 200)
        #expect(surface.activateCalls == 1)
        #expect(surface.deactivateCalls == 1)
    }

    @Test("POST /pointer with down event")
    func pointerDown() async throws {
        let surface = FakeSurface()
        let server = try DevHTTPServer(surface: surface, port: 0); try server.start(); defer { server.stop() }
        #expect(try await post(server, "/pointer", body: "{\"event\":\"down\",\"x\":10,\"y\":20}") == 200)
        #expect(surface.pointerEvents.count == 1)
        #expect(surface.pointerEvents[0].0 == "down")
        #expect(surface.pointerEvents[0].1?.x == 10)
        #expect(surface.pointerEvents[0].1?.y == 20)
    }

    @Test("POST /pointer with malformed body returns 400")
    func pointerBadRequest() async throws {
        let surface = FakeSurface()
        let server = try DevHTTPServer(surface: surface, port: 0); try server.start(); defer { server.stop() }
        #expect(try await post(server, "/pointer", body: "{}") == 400)
    }
}
