// ABOUTME: Dev HTTP route for the per-tool outline toggles: POST /outline {tool, enabled}.
// ABOUTME: Lives in its own extension to keep DevHTTPServer under the type-body limit.

#if DEBUG
import Foundation

extension DevHTTPServer {
    func installOutlineRoute() {
        router.add("POST", "/outline") { [weak self] req, _ in
            guard let self else { return .notFound() }
            guard let json = try? JSONSerialization.jsonObject(with: req.body) as? [String: Any],
                  let tool = json["tool"] as? String,
                  let enabled = json["enabled"] as? Bool else {
                return .badRequest("expected {tool: \"text\"|\"arrow\"|\"pen\", enabled: Bool} body")
            }
            guard self.surface.setOutline(tool: tool, enabled: enabled) else {
                return .badRequest("unknown tool \(tool)")
            }
            return .ok()
        }
    }
}
#endif
