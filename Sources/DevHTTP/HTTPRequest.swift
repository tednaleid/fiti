// ABOUTME: Minimal HTTP/1.1 request parser. Only what the dev API needs.
// ABOUTME: Parses method, path, headers (lowercased keys), and body from raw Data.

#if DEBUG
import Foundation

public struct HTTPRequest: Sendable {
    public let method: String
    public let path: String
    public let headers: [String: String]
    public let body: Data

    public enum ParseError: Error { case malformed }

    /// Parse a complete HTTP/1.1 request from `data`. Assumes the caller has already
    /// buffered the full message (request line, headers, and `Content-Length` worth
    /// of body). The dev server (Task 4.2+) is responsible for that buffering before
    /// calling this. Returns `.malformed` only on missing/garbled headers — body
    /// length is not validated.
    public static func parse(_ data: Data) throws -> HTTPRequest {
        guard let split = data.range(of: Data("\r\n\r\n".utf8)) else { throw ParseError.malformed }
        let headerData = data[..<split.lowerBound]
        let body = data[split.upperBound...]
        guard let headerText = String(data: Data(headerData), encoding: .utf8) else { throw ParseError.malformed }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { throw ParseError.malformed }
        let parts = requestLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2 else { throw ParseError.malformed }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        return HTTPRequest(method: parts[0], path: parts[1], headers: headers, body: Data(body))
    }
}
#endif
