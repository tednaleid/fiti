// ABOUTME: Tests for POST /clear, /undo, /redo routes.
// ABOUTME: Uses FakeSurface and ephemeral-port DevHTTPServer; real URLSession.

import Foundation
import Testing

@Suite("History routes")
struct HistoryRoutesTests {
    @Test("clear / undo / redo route to surface")
    func all() async throws {
        let surface = FakeSurface()
        let server = try DevHTTPServer(surface: surface, port: 0); try server.start(); defer { server.stop() }
        let port = try #require(server.boundPort)

        func post(_ path: String) async throws -> Int {
            let url = try #require(URL(string: "http://localhost:\(port)\(path)"))
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            let (_, response) = try await URLSession.shared.data(for: req)
            let http = try #require(response as? HTTPURLResponse)
            return http.statusCode
        }

        #expect(try await post("/clear") == 200)
        #expect(try await post("/undo") == 200)
        #expect(try await post("/redo") == 200)
        #expect(surface.clearCalls == 1)
        #expect(surface.undoCalls == 1)
        #expect(surface.redoCalls == 1)
    }
}
