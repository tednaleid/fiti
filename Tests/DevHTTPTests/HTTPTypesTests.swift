// ABOUTME: Tests for HTTPRequest / HTTPResponse value types and their parsing.
// ABOUTME: Uses Swift Testing; compiled directly into fiti-unit (no @testable import needed).

import Foundation
import Testing

@Suite("HTTP types")
struct HTTPTypesTests {
    @Test("parses GET request line and headers")
    func parseGet() throws {
        let raw = "GET /state HTTP/1.1\r\nHost: localhost\r\nUser-Agent: curl\r\n\r\n"
        let req = try HTTPRequest.parse(Data(raw.utf8))
        #expect(req.method == "GET")
        #expect(req.path == "/state")
        #expect(req.headers["host"] == "localhost")
        #expect(req.body.isEmpty)
    }

    @Test("parses POST request with JSON body")
    func parsePost() throws {
        let body = "{\"event\":\"down\",\"x\":10,\"y\":20}"
        let raw = "POST /pointer HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        let req = try HTTPRequest.parse(Data(raw.utf8))
        #expect(req.method == "POST")
        #expect(req.path == "/pointer")
        #expect(req.headers["content-type"] == "application/json")
        #expect(String(data: req.body, encoding: .utf8) == body)
    }

    @Test("HTTPResponse.json serializes correctly")
    func responseJSON() throws {
        let resp = HTTPResponse.json(["ok": true])
        let data = resp.serialize()
        let text = String(data: data, encoding: .utf8)!
        #expect(text.hasPrefix("HTTP/1.1 200"))
        #expect(text.contains("Content-Type: application/json"))
        #expect(text.contains("\"ok\":true") || text.contains("\"ok\": true"))
    }

    @Test("parse throws on missing header terminator")
    func parseMalformed() {
        let raw = "GET /state HTTP/1.1\r\nHost: localhost\r\n"  // no \r\n\r\n
        #expect(throws: HTTPRequest.ParseError.malformed) {
            _ = try HTTPRequest.parse(Data(raw.utf8))
        }
    }

    @Test("HTTPResponse status codes serialize correctly")
    func responseStatus() {
        let resp = HTTPResponse.notFound("nope")
        let text = String(data: resp.serialize(), encoding: .utf8)!
        #expect(text.hasPrefix("HTTP/1.1 404"))
    }
}
