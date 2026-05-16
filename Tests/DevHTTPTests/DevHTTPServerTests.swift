// ABOUTME: End-to-end test: server starts on an ephemeral port, URLSession hits it.
// ABOUTME: Uses Swift Testing; no @testable import needed — all types are public.

import Foundation
import Testing

@Suite("DevHTTPServer")
struct DevHTTPServerTests {
    @Test("responds to GET / with 200")
    func smoke() async throws {
        let surface = FakeSurface()
        let server = try DevHTTPServer(surface: surface, port: 0)
        defer { server.stop() }
        try server.start()
        let port = server.boundPort!

        let (data, response) = try await URLSession.shared.data(from: URL(string: "http://localhost:\(port)/")!)
        let http = try #require(response as? HTTPURLResponse)
        #expect(http.statusCode == 200)
        #expect(String(data: data, encoding: .utf8) == "fiti dev API\n")
    }
}
