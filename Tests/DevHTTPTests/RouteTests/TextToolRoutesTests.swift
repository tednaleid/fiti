// ABOUTME: Tests for POST /tool and POST /text routes.
// ABOUTME: Uses FakeSurface and ephemeral-port DevHTTPServer; real URLSession.

import Foundation
import Testing

@Suite("Text tool routes")
@MainActor
struct TextToolRoutesTests {
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

    // MARK: - POST /tool

    @Test("POST /tool sets currentTool on surface")
    func setToolText() async throws {
        let surface = FakeSurface()
        let server = try DevHTTPServer(surface: surface, port: 0); try server.start(); defer { server.stop() }
        let status = try await postStatus(server, "/tool", body: "{\"tool\":\"text\"}")
        #expect(status == 200)
        #expect(surface.currentTool == .text)
    }

    @Test("POST /tool pen sets pen tool")
    func setToolPen() async throws {
        let surface = FakeSurface()
        surface.currentTool = .text
        let server = try DevHTTPServer(surface: surface, port: 0); try server.start(); defer { server.stop() }
        let status = try await postStatus(server, "/tool", body: "{\"tool\":\"pen\"}")
        #expect(status == 200)
        #expect(surface.currentTool == .pen)
    }

    @Test("POST /tool selection sets selection tool")
    func setToolSelection() async throws {
        let surface = FakeSurface()
        let server = try DevHTTPServer(surface: surface, port: 0); try server.start(); defer { server.stop() }
        let status = try await postStatus(server, "/tool", body: "{\"tool\":\"selection\"}")
        #expect(status == 200)
        #expect(surface.currentTool == .selection)
    }

    @Test("POST /tool with unknown tool returns 400")
    func setToolUnknown() async throws {
        let surface = FakeSurface()
        let server = try DevHTTPServer(surface: surface, port: 0); try server.start(); defer { server.stop() }
        #expect(try await postStatus(server, "/tool", body: "{\"tool\":\"eraser\"}") == 400)
    }

    @Test("POST /tool with missing body returns 400")
    func setToolMissingBody() async throws {
        let surface = FakeSurface()
        let server = try DevHTTPServer(surface: surface, port: 0); try server.start(); defer { server.stop() }
        #expect(try await postStatus(server, "/tool", body: "{}") == 400)
    }

    // MARK: - POST /text type

    @Test("POST /text type forwards text to surface")
    func textType() async throws {
        let surface = FakeSurface()
        let server = try DevHTTPServer(surface: surface, port: 0); try server.start(); defer { server.stop() }
        let status = try await postStatus(server, "/text", body: "{\"action\":\"type\",\"text\":\"hi\"}")
        #expect(status == 200)
        #expect(surface.lastTypedText == "hi")
        #expect(surface.textActions.contains("type:hi"))
    }

    @Test("POST /text type missing text field returns 400")
    func textTypeMissingText() async throws {
        let surface = FakeSurface()
        let server = try DevHTTPServer(surface: surface, port: 0); try server.start(); defer { server.stop() }
        #expect(try await postStatus(server, "/text", body: "{\"action\":\"type\"}") == 400)
    }

    // MARK: - POST /text control actions

    @Test("POST /text newline calls textNewline")
    func textNewline() async throws {
        let surface = FakeSurface()
        let server = try DevHTTPServer(surface: surface, port: 0); try server.start(); defer { server.stop() }
        #expect(try await postStatus(server, "/text", body: "{\"action\":\"newline\"}") == 200)
        #expect(surface.textActions.contains("newline"))
    }

    @Test("POST /text backspace calls textBackspace")
    func textBackspace() async throws {
        let surface = FakeSurface()
        let server = try DevHTTPServer(surface: surface, port: 0); try server.start(); defer { server.stop() }
        #expect(try await postStatus(server, "/text", body: "{\"action\":\"backspace\"}") == 200)
        #expect(surface.textActions.contains("backspace"))
    }

    @Test("POST /text commit calls textCommit")
    func textCommit() async throws {
        let surface = FakeSurface()
        let server = try DevHTTPServer(surface: surface, port: 0); try server.start(); defer { server.stop() }
        #expect(try await postStatus(server, "/text", body: "{\"action\":\"commit\"}") == 200)
        #expect(surface.textActions.contains("commit"))
    }

    @Test("POST /text escape calls textEscape")
    func textEscape() async throws {
        let surface = FakeSurface()
        let server = try DevHTTPServer(surface: surface, port: 0); try server.start(); defer { server.stop() }
        #expect(try await postStatus(server, "/text", body: "{\"action\":\"escape\"}") == 200)
        #expect(surface.textActions.contains("escape"))
    }

    // MARK: - POST /text caret

    @Test("POST /text caret left forwards .left to surface")
    func textCaretLeft() async throws {
        let surface = FakeSurface()
        let server = try DevHTTPServer(surface: surface, port: 0); try server.start(); defer { server.stop() }
        #expect(try await postStatus(server, "/text", body: "{\"action\":\"caret\",\"direction\":\"left\"}") == 200)
        #expect(surface.lastCaretMove == .left)
    }

    @Test("POST /text caret lineEnd forwards .lineEnd to surface")
    func textCaretLineEnd() async throws {
        let surface = FakeSurface()
        let server = try DevHTTPServer(surface: surface, port: 0); try server.start(); defer { server.stop() }
        #expect(try await postStatus(server, "/text", body: "{\"action\":\"caret\",\"direction\":\"lineEnd\"}") == 200)
        #expect(surface.lastCaretMove == .lineEnd)
    }

    @Test("POST /text caret unknown direction returns 400")
    func textCaretUnknownDirection() async throws {
        let surface = FakeSurface()
        let server = try DevHTTPServer(surface: surface, port: 0); try server.start(); defer { server.stop() }
        #expect(try await postStatus(server, "/text", body: "{\"action\":\"caret\",\"direction\":\"diagonal\"}") == 400)
    }

    @Test("POST /text caret missing direction returns 400")
    func textCaretMissingDirection() async throws {
        let surface = FakeSurface()
        let server = try DevHTTPServer(surface: surface, port: 0); try server.start(); defer { server.stop() }
        #expect(try await postStatus(server, "/text", body: "{\"action\":\"caret\"}") == 400)
    }

    @Test("POST /text unknown action returns 400")
    func textUnknownAction() async throws {
        let surface = FakeSurface()
        let server = try DevHTTPServer(surface: surface, port: 0); try server.start(); defer { server.stop() }
        #expect(try await postStatus(server, "/text", body: "{\"action\":\"zap\"}") == 400)
    }

    // MARK: - GET /state includes text tool fields

    @Test("GET /state includes currentTool, isEditingText, editingText")
    func stateIncludesTextFields() async throws {
        let surface = FakeSurface()
        surface.currentTool = .text
        surface.isEditingText = true
        surface.editingText = "hello"
        let server = try DevHTTPServer(surface: surface, port: 0); try server.start(); defer { server.stop() }
        let (status, json) = try await get(server, "/state")
        #expect(status == 200)
        #expect((json["currentTool"] as? String) == "text")
        #expect((json["isEditingText"] as? Bool) == true)
        #expect((json["editingText"] as? String) == "hello")
    }

    @Test("GET /state editingText is nil when not editing")
    func stateEditingTextNilWhenIdle() async throws {
        let surface = FakeSurface()
        let server = try DevHTTPServer(surface: surface, port: 0); try server.start(); defer { server.stop() }
        let (_, json) = try await get(server, "/state")
        #expect((json["currentTool"] as? String) == "pen")
        #expect((json["isEditingText"] as? Bool) == false)
        // editingText key is present but value is NSNull when nil
        #expect(json["editingText"] is NSNull || json["editingText"] == nil)
    }
}
