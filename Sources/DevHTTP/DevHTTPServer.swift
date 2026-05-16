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
            if self.isComplete(buf) {
                if let req = try? HTTPRequest.parse(buf) {
                    let response = self.router.handle(req).serialize()
                    connection.send(content: response, completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                    return
                }
                connection.cancel()
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

    /// Returns true when the buffer contains a complete HTTP/1.1 request: headers
    /// terminated by \r\n\r\n and at least Content-Length bytes of body (if declared).
    private func isComplete(_ buf: Data) -> Bool {
        guard let headerEnd = buf.range(of: Data("\r\n\r\n".utf8)) else { return false }
        guard let headerText = String(data: Data(buf[..<headerEnd.lowerBound]), encoding: .utf8) else { return false }
        let bodyStart = headerEnd.upperBound
        if let contentLengthLine = headerText.components(separatedBy: "\r\n").first(where: {
            $0.lowercased().hasPrefix("content-length:")
        }) {
            let value = contentLengthLine.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
            if let length = Int(value) {
                return buf.count >= bodyStart + length
            }
        }
        return true
    }

    private func installRoutes() {
        router.add("GET", "/") { _, _ in
            HTTPResponse(status: 200, reason: "OK", body: Data("fiti dev API\n".utf8))
        }

        router.add("GET", "/state") { [weak self] _, _ in
            guard let self else { return .notFound() }
            let payload: [String: Any] = [
                "mode": String(describing: self.surface.mode),
                "clickThrough": self.surface.clickThrough,
                "canvasSize": ["width": self.surface.canvasSize.width, "height": self.surface.canvasSize.height],
                "undoDepth": self.surface.undoDepth,
                "redoDepth": self.surface.redoDepth,
                "currentStrokeId": self.surface.currentStrokeId as Any
            ]
            return .json(payload)
        }

        router.add("GET", "/doc") { [weak self] _, _ in
            guard let self else { return .notFound() }
            return .json(encode: self.surface.doc)
        }

        router.add("GET", "/strokes/:id") { [weak self] _, params in
            guard let self, let id = params["id"], let stroke = self.surface.doc.strokes[id] else { return .notFound() }
            return .json(encode: stroke)
        }

        router.add("POST", "/strokes/:id/erase") { [weak self] _, params in
            guard let self, let id = params["id"] else { return .badRequest("missing id") }
            let ok = self.surface.eraseStroke(id)
            return .json(["erased": ok])
        }

        router.add("POST", "/activate") { [weak self] _, _ in
            self?.surface.activate()
            return .ok()
        }

        router.add("POST", "/deactivate") { [weak self] _, _ in
            self?.surface.deactivate()
            return .ok()
        }

        router.add("POST", "/pointer") { [weak self] req, _ in
            guard let self else { return .notFound() }
            return self.handlePointer(req)
        }

        installHistoryRoutes()
    }

    private func installHistoryRoutes() {
        router.add("POST", "/clear") { [weak self] _, _ in
            self?.surface.clear()
            return .ok()
        }

        router.add("POST", "/undo") { [weak self] _, _ in
            let did = self?.surface.undo() ?? false
            return .json(["undid": did])
        }

        router.add("POST", "/redo") { [weak self] _, _ in
            let did = self?.surface.redo() ?? false
            return .json(["redid": did])
        }
    }

    private func handlePointer(_ req: HTTPRequest) -> HTTPResponse {
        guard let json = try? JSONSerialization.jsonObject(with: req.body) as? [String: Any],
              let event = json["event"] as? String else {
            return .badRequest("expected {event, x, y} body")
        }
        if event == "up" {
            surface.pointerUp()
            return .ok()
        }
        guard let x = (json["x"] as? Double) ?? (json["x"] as? Int).map(Double.init),
              let y = (json["y"] as? Double) ?? (json["y"] as? Int).map(Double.init) else {
            return .badRequest("missing x/y")
        }
        let pressure = (json["pressure"] as? Double) ?? 0.5
        let point = StrokePoint(x: x, y: y, pressure: pressure)
        switch event {
        case "down": surface.pointerDown(point)
        case "move": surface.pointerMoved(point)
        default: return .badRequest("unknown event \(event)")
        }
        return .ok()
    }
}
