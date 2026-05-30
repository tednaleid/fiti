// ABOUTME: DevHTTPServer extension — routes for the size/opacity popover: POST /popover
// ABOUTME: to open/toggle it and GET /popover.png to capture the open panel.

#if DEBUG
import Foundation

extension DevHTTPServer {
    func installPopoverRoutes() {
        router.add("POST", "/popover") { [weak self] req, _ in
            guard let self else { return .notFound() }
            return self.handleTriggerPopover(req)
        }

        router.add("GET", "/popover.png") { [weak self] _, _ in
            guard let data = self?.surface.popoverPNG() else {
                return HTTPResponse(status: 409, reason: "Conflict",
                                    body: Data("popover not open".utf8))
            }
            return .png(data)
        }
    }

    @MainActor
    func handleTriggerPopover(_ req: HTTPRequest) -> HTTPResponse {
        guard let json = try? JSONSerialization.jsonObject(with: req.body) as? [String: Any],
              let axisName = json["axis"] as? String else {
            return .badRequest("expected {axis: \"size\"|\"opacity\"} body")
        }
        guard let axis = PresetAxis(name: axisName) else {
            return .badRequest("unknown axis \(axisName)")
        }
        surface.triggerPopover(axis: axis)
        return .json(["open": surface.popoverOpen,
                      "axis": surface.popoverAxis?.name as Any])
    }
}
#endif
