// ABOUTME: Minimal HTTP/1.1 response composer. Serializes status, headers, and body.
// ABOUTME: Header names are canonicalized to Title-Case on serialize (e.g. content-type -> Content-Type).

import Foundation

public struct HTTPResponse: Sendable {
    public let status: Int
    public let reason: String
    public let headers: [String: String]
    public let body: Data

    public init(status: Int, reason: String, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status
        self.reason = reason
        var h = headers
        h["content-length"] = String(body.count)
        if h["content-type"] == nil { h["content-type"] = "text/plain; charset=utf-8" }
        h["connection"] = "close"
        self.headers = h
        self.body = body
    }

    /// Canonicalizes a lowercase header name to Title-Case (e.g. "content-type" -> "Content-Type").
    private static func canonicalize(_ name: String) -> String {
        name.split(separator: "-", omittingEmptySubsequences: false)
            .map { segment -> String in
                guard let first = segment.first else { return String(segment) }
                return first.uppercased() + segment.dropFirst()
            }
            .joined(separator: "-")
    }

    public func serialize() -> Data {
        var lines = ["HTTP/1.1 \(status) \(reason)"]
        for (k, v) in headers {
            lines.append("\(HTTPResponse.canonicalize(k)): \(v)")
        }
        lines.append("")
        lines.append("")
        var data = Data(lines.joined(separator: "\r\n").utf8)
        data.append(body)
        return data
    }

    public static func ok(_ body: String = "OK") -> HTTPResponse {
        HTTPResponse(status: 200, reason: "OK", body: Data(body.utf8))
    }

    public static func json(_ value: Any) -> HTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])) ?? Data("{}".utf8)
        return HTTPResponse(status: 200, reason: "OK",
                            headers: ["content-type": "application/json"], body: data)
    }

    public static func json<T: Encodable>(encode value: T) -> HTTPResponse {
        let data = (try? JSONEncoder().encode(value)) ?? Data("{}".utf8)
        return HTTPResponse(status: 200, reason: "OK",
                            headers: ["content-type": "application/json"], body: data)
    }

    public static func notFound(_ body: String = "Not Found") -> HTTPResponse {
        HTTPResponse(status: 404, reason: "Not Found", body: Data(body.utf8))
    }

    public static func badRequest(_ body: String) -> HTTPResponse {
        HTTPResponse(status: 400, reason: "Bad Request", body: Data(body.utf8))
    }

    public static func png(_ data: Data) -> HTTPResponse {
        HTTPResponse(status: 200, reason: "OK",
                     headers: ["content-type": "image/png"], body: data)
    }
}
