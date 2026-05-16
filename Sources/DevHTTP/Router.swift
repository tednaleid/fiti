// ABOUTME: Maps (method, path) to a route handler. Path params resolved by simple
// ABOUTME: pattern match — no regex DSL; we only have a handful of routes.

import Foundation

public struct Router: Sendable {
    public typealias Handler = @MainActor (HTTPRequest, [String: String]) -> HTTPResponse

    private struct Route {
        let method: String
        let pattern: [String]
        let handler: Handler
    }

    private var routes: [Route] = []

    public init() {}

    public mutating func add(_ method: String, _ pattern: String, handler: @escaping Handler) {
        let parts = pattern.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        routes.append(Route(method: method, pattern: parts, handler: handler))
    }

    @MainActor
    public func handle(_ req: HTTPRequest) -> HTTPResponse {
        let parts = req.path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        for route in routes where route.method == req.method && route.pattern.count == parts.count {
            var params: [String: String] = [:]
            var matched = true
            for (a, b) in zip(route.pattern, parts) {
                if a.hasPrefix(":") {
                    params[String(a.dropFirst())] = b
                } else if a != b {
                    matched = false
                    break
                }
            }
            if matched { return route.handler(req, params) }
        }
        return .notFound()
    }
}
