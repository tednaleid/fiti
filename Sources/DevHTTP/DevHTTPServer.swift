// ABOUTME: NWListener-based HTTP/1.1 server. Single-threaded async — fine for
// ABOUTME: a dev introspection API that handles a few requests per minute.

import Foundation
import Network

public final class DevHTTPServer {
    private let surface: DevHTTPSurface
    private var router: Router
    private let listener: NWListener
    private let queue = DispatchQueue(label: "fiti.devhttp")
    public private(set) var boundPort: Int?

    public init(surface: DevHTTPSurface, port: UInt16) throws {
        self.surface = surface
        self.router = Router()
        let params = NWParameters.tcp
        let endpoint: NWEndpoint.Port = port == 0 ? .any : (NWEndpoint.Port(rawValue: port) ?? .any)
        self.listener = try NWListener(using: params, on: endpoint)
        installRoutes()
    }

    public func start() throws {
        listener.stateUpdateHandler = { [weak self] state in
            if case .ready = state, let port = self?.listener.port {
                self?.boundPort = Int(port.rawValue)
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)
        let deadline = Date().addingTimeInterval(2)
        while boundPort == nil && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
    }

    public func stop() {
        listener.cancel()
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        readRequest(on: connection, buffer: Data())
    }

    private static let maxRequestBytes = 1024 * 1024  // 1 MB — generous for a dev API.

    private func readRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buf = buffer
            if let d = data { buf.append(d) }
            if let req = try? HTTPRequest.parse(buf) {
                let response = self.router.handle(req).serialize()
                connection.send(content: response, completion: .contentProcessed { _ in
                    connection.cancel()
                })
                return
            }
            if buf.count > Self.maxRequestBytes {
                // Defensive: cap how long we'll keep accumulating an unparseable request.
                connection.cancel()
                return
            }
            if isComplete || error != nil {
                connection.cancel()
                return
            }
            self.readRequest(on: connection, buffer: buf)
        }
    }

    private func installRoutes() {
        router.add("GET", "/") { _, _ in
            HTTPResponse(status: 200, reason: "OK", body: Data("fiti dev API\n".utf8))
        }
    }
}
