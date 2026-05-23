// ABOUTME: DevHTTPServer extension — routes and handlers for POST /tool and POST /text.
// ABOUTME: Compiled into Debug builds only — never present in shipped binaries.

#if DEBUG
import Foundation

extension DevHTTPServer {
    func installTextRoutes() {
        router.add("POST", "/tool") { [weak self] req, _ in
            guard let self else { return .notFound() }
            return self.handleSetTool(req)
        }

        router.add("POST", "/text") { [weak self] req, _ in
            guard let self else { return .notFound() }
            return self.handleTextAction(req)
        }
    }

    @MainActor
    func handleSetTool(_ req: HTTPRequest) -> HTTPResponse {
        guard let json = try? JSONSerialization.jsonObject(with: req.body) as? [String: Any],
              let toolName = json["tool"] as? String else {
            return .badRequest("expected {tool: \"pen\"|\"selection\"|\"text\"} body")
        }
        let tool: Tool
        switch toolName {
        case "pen": tool = .pen
        case "selection": tool = .selection
        case "text": tool = .text
        default: return .badRequest("unknown tool \(toolName)")
        }
        surface.setTool(tool)
        return .ok()
    }

    @MainActor
    func handleTextAction(_ req: HTTPRequest) -> HTTPResponse {
        guard let json = try? JSONSerialization.jsonObject(with: req.body) as? [String: Any],
              let action = json["action"] as? String else {
            return .badRequest("expected {action: String} body")
        }
        switch action {
        case "type":
            return handleTextType(json)
        case "newline": surface.textNewline()
        case "backspace": surface.textBackspace()
        case "commit": surface.textCommit()
        case "escape": surface.textEscape()
        case "caret":
            return handleTextCaret(json)
        default:
            return .badRequest("unknown action \(action)")
        }
        return .ok()
    }

    @MainActor
    func handleTextType(_ json: [String: Any]) -> HTTPResponse {
        guard let text = json["text"] as? String else {
            return .badRequest("\"type\" action requires \"text\" field")
        }
        surface.typeText(text)
        return .ok()
    }

    @MainActor
    func handleTextCaret(_ json: [String: Any]) -> HTTPResponse {
        guard let dirName = json["direction"] as? String else {
            return .badRequest("\"caret\" action requires \"direction\" field")
        }
        guard let direction = caretMove(from: dirName) else {
            return .badRequest("unknown direction \(dirName)")
        }
        surface.moveTextCaret(direction)
        return .ok()
    }
}

private func caretMove(from name: String) -> TextEditSession.CaretMove? {
    switch name {
    case "left": return .left
    case "right": return .right
    case "up": return .up
    case "down": return .down
    case "lineStart": return .lineStart
    case "lineEnd": return .lineEnd
    default: return nil
    }
}
#endif
