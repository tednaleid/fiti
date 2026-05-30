// ABOUTME: NWListener-based HTTP/1.1 server. Single-threaded async — fine for
// ABOUTME: a dev introspection API that handles a few requests per minute.
// ABOUTME: Compiled into Debug builds only — never present in shipped binaries.

#if DEBUG
import Foundation
import Network

// `@unchecked Sendable` because the mutable state (`router`, `boundPort`) is
// only touched from the dev-HTTP DispatchQueue or via short-lived reads from
// the start() busy-wait. A POC concession; a proper fix would actor-isolate
// the class or replace the busy-wait with a semaphore signaled from the
// NWListener state handler.
public final class DevHTTPServer: @unchecked Sendable {
    let surface: DevHTTPSurface
    var router: Router
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
                    // Handlers touch AppController/Editor/AppKit, all of which are
                    // main-thread-only. Hop to main to dispatch, then come back.
                    let router = self.router
                    DispatchQueue.main.async {
                        let response = MainActor.assumeIsolated { router.handle(req).serialize() }
                        connection.send(content: response, completion: .contentProcessed { _ in
                            connection.cancel()
                        })
                    }
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
            return self.handleState()
        }

        router.add("GET", "/doc") { [weak self] _, _ in
            guard let self else { return .notFound() }
            return .json(encode: self.surface.doc)
        }

        router.add("GET", "/strokes/:id") { [weak self] _, params in
            guard let self, let id = params["id"],
                  case .stroke(let stroke)? = self.surface.doc.items[id] else { return .notFound() }
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

        router.add("GET", "/perf") { _, _ in
            DevHTTPServer.handlePerf()
        }

        router.add("POST", "/perf/reset") { _, _ in
            PerfLog.shared.reset()
            return .ok()
        }

        installToolbarRoutes()
        installTextRoutes()
        installHistoryRoutes()
        installSnapshotRoute()
        installOutlineRoute()
        installPopoverRoutes()
    }

    private func installToolbarRoutes() {
        router.add("POST", "/color") { [weak self] req, _ in
            guard let self else { return .notFound() }
            return self.handleSetColor(req)
        }

        router.add("POST", "/width") { [weak self] req, _ in
            guard let self else { return .notFound() }
            return self.handleSetWidth(req)
        }

        router.add("POST", "/drawings/show") { [weak self] _, _ in
            self?.surface.setDrawingsVisible(true)
            return .ok()
        }

        router.add("POST", "/drawings/hide") { [weak self] _, _ in
            self?.surface.setDrawingsVisible(false)
            return .ok()
        }
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

    @MainActor
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

    @MainActor
    private func handleSetColor(_ req: HTTPRequest) -> HTTPResponse {
        guard let json = try? JSONSerialization.jsonObject(with: req.body) as? [String: Any],
              let r = (json["r"] as? Double) ?? (json["r"] as? Int).map(Double.init),
              let g = (json["g"] as? Double) ?? (json["g"] as? Int).map(Double.init),
              let b = (json["b"] as? Double) ?? (json["b"] as? Int).map(Double.init),
              let a = (json["a"] as? Double) ?? (json["a"] as? Int).map(Double.init) else {
            return .badRequest("expected {r, g, b, a} body, each in 0..1")
        }
        surface.setColor(RGBA(r: r, g: g, b: b, a: a))
        return .ok()
    }

    @MainActor
    private func handleSetWidth(_ req: HTTPRequest) -> HTTPResponse {
        guard let json = try? JSONSerialization.jsonObject(with: req.body) as? [String: Any],
              let w = (json["width"] as? Double) ?? (json["width"] as? Int).map(Double.init) else {
            return .badRequest("expected {width: Double} body")
        }
        surface.setWidth(w)
        return .ok()
    }

    @MainActor
    private static func handlePerf() -> HTTPResponse {
        let snap = PerfLog.shared.snapshot()
        var stats: [String: Any] = [:]
        for (label, stat) in snap.stats {
            // count is >= 1 for any stat present in the map (record() increments it).
            let mean = stat.totalSeconds / Double(stat.count)
            stats[label] = [
                "count": stat.count,
                "totalMs": stat.totalSeconds * 1000,
                "meanMs": mean * 1000,
                "maxMs": stat.maxSeconds * 1000,
                "lastMs": stat.lastSeconds * 1000
            ]
        }
        return .json(["stats": stats, "gauges": snap.gauges])
    }

    @MainActor
    private func handleState() -> HTTPResponse {
        let payload: [String: Any] = [
            "mode": String(describing: surface.mode),
            "clickThrough": surface.clickThrough,
            "canvasSize": ["width": surface.canvasSize.width, "height": surface.canvasSize.height],
            "undoDepth": surface.undoDepth,
            "redoDepth": surface.redoDepth,
            "currentStrokeId": surface.currentStrokeId as Any,
            "color": ["r": surface.currentColor.r, "g": surface.currentColor.g,
                      "b": surface.currentColor.b, "a": surface.currentColor.a],
            "width": surface.currentWidth,
            "drawingsVisible": surface.drawingsVisible,
            "outline": ["text": surface.textOutline, "arrow": surface.arrowOutline,
                        "pen": surface.penOutline],
            "currentTool": String(describing: surface.currentTool),
            "isEditingText": surface.isEditingText,
            "editingText": surface.editingText as Any,
            "popoverOpen": surface.popoverOpen,
            "popoverAxis": surface.popoverAxis?.name as Any
        ]
        return .json(payload)
    }

}
#endif
