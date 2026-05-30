// ABOUTME: End-to-end test: server starts on an ephemeral port, URLSession hits it.
// ABOUTME: Uses Swift Testing; no @testable import needed — all types are public.

import Foundation
import Testing

@Suite("DevHTTPServer")
struct DevHTTPServerTests {
    @Test("responds to GET / with 200")
    @MainActor
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

    @Test("POST /popover triggers the surface and reports the resulting state")
    @MainActor
    func triggerPopover() async throws {
        let surface = FakeSurface()
        let server = try DevHTTPServer(surface: surface, port: 0)
        defer { server.stop() }
        try server.start()
        let port = server.boundPort!

        let (data, response) = try await post("http://localhost:\(port)/popover",
                                              body: #"{"axis":"size"}"#)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["open"] as? Bool == true)
        #expect(json["axis"] as? String == "size")
        #expect(surface.popoverTriggers == [.size])
        #expect(surface.popoverOpen == true)
    }

    @Test("POST /popover with an unknown axis is a 400")
    @MainActor
    func triggerPopoverBadAxis() async throws {
        let surface = FakeSurface()
        let server = try DevHTTPServer(surface: surface, port: 0)
        defer { server.stop() }
        try server.start()
        let port = server.boundPort!

        let (_, response) = try await post("http://localhost:\(port)/popover", body: #"{"axis":"bogus"}"#)
        #expect((response as? HTTPURLResponse)?.statusCode == 400)
        #expect(surface.popoverTriggers.isEmpty)
    }

    @Test("GET /popover.png returns the PNG when open and 409 when closed")
    @MainActor
    func popoverPNG() async throws {
        let surface = FakeSurface()
        let server = try DevHTTPServer(surface: surface, port: 0)
        defer { server.stop() }
        try server.start()
        let port = server.boundPort!

        // Closed → 409.
        let (_, closedResp) = try await URLSession.shared.data(from: URL(string: "http://localhost:\(port)/popover.png")!)
        #expect((closedResp as? HTTPURLResponse)?.statusCode == 409)

        // Open it, then the PNG is served.
        surface.popoverOpen = true
        surface.popoverAxis = .size
        let (data, openResp) = try await URLSession.shared.data(from: URL(string: "http://localhost:\(port)/popover.png")!)
        let http = try #require(openResp as? HTTPURLResponse)
        #expect(http.statusCode == 200)
        #expect(http.value(forHTTPHeaderField: "Content-Type") == "image/png")
        #expect(Array(data.prefix(4)) == [0x89, 0x50, 0x4E, 0x47])
    }

    @MainActor
    private func post(_ url: String, body: String) async throws -> (Data, URLResponse) {
        var req = URLRequest(url: URL(string: url)!)
        req.httpMethod = "POST"
        req.httpBody = Data(body.utf8)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await URLSession.shared.data(for: req)
    }
}
