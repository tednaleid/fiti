// ABOUTME: Tests for GET /snapshot.png — returns PNG bytes from the surface.
// ABOUTME: Uses FakeSurface and ephemeral-port DevHTTPServer; real URLSession.

import Foundation
import Testing

@Suite("/snapshot.png")
struct SnapshotTests {
    @Test("returns the surface's PNG bytes with image/png content type")
    func returnsPNG() async throws {
        let surface = FakeSurface()
        surface.snapshotPNGReturn = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])  // real PNG magic
        let server = try DevHTTPServer(surface: surface, port: 0); try server.start(); defer { server.stop() }
        let port = try #require(server.boundPort)
        let url = try #require(URL(string: "http://localhost:\(port)/snapshot.png"))
        let (data, response) = try await URLSession.shared.data(from: url)
        let http = try #require(response as? HTTPURLResponse)
        #expect(http.statusCode == 200)
        #expect(http.value(forHTTPHeaderField: "Content-Type") == "image/png")
        #expect(data.prefix(8) == surface.snapshotPNGReturn)
    }

    @Test("returns 500 when surface returns nil")
    func nilReturnsError() async throws {
        let surface = FakeSurface()
        surface.snapshotPNGReturn = nil
        let server = try DevHTTPServer(surface: surface, port: 0); try server.start(); defer { server.stop() }
        let port = try #require(server.boundPort)
        let url = try #require(URL(string: "http://localhost:\(port)/snapshot.png"))
        let (_, response) = try await URLSession.shared.data(from: url)
        let http = try #require(response as? HTTPURLResponse)
        #expect(http.statusCode == 500)
    }
}
