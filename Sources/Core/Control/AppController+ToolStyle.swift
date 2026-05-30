// ABOUTME: Per-tool style memory — pen/text/arrow each keep their own color/opacity/
// ABOUTME: width. currentTool swaps the active style; loadStyles seeds from persistence.

import Foundation

extension AppController {
    /// Which tool slot the active style maps to: the current tool when drawing, else
    /// the last drawing tool while in selection.
    public var styleTool: Tool { currentTool.isDrawingTool ? currentTool : lastDrawingTool }

    /// The remembered style for `tool` (the product default for a non-drawing tool).
    public func style(for tool: Tool) -> ToolStyle { toolStyles[tool] ?? .default }

    /// Replace all per-tool styles (e.g. loaded from persistence at launch) and make
    /// the current tool's style live. Drawing tools only; others are ignored.
    public func loadStyles(_ styles: [Tool: ToolStyle]) {
        for (tool, style) in styles where tool.isDrawingTool { toolStyles[tool] = style }
        applyStyle(of: styleTool)
    }

    /// Load `tool`'s remembered style into the live `currentColor`/`currentWidth`.
    func applyStyle(of tool: Tool) {
        let style = self.style(for: tool)
        currentColor = style.color
        currentWidth = style.width
    }
}
