// ABOUTME: UserDefaults-backed load/save of the per-tool styles (color + width).
// ABOUTME: Seeds any unpersisted tool from the legacy global keys so upgrades carry over.

import AppKit

@MainActor
struct UserDefaultsToolStyles {
    let defaults: UserDefaults

    /// Per-tool styles. A tool with no persisted style yet inherits the legacy global
    /// color/width (so existing users keep their setting on upgrade), or the product
    /// default when nothing was ever saved.
    func load() -> [Tool: ToolStyle] {
        let fallback = legacyGlobalStyle() ?? .default
        var styles: [Tool: ToolStyle] = [:]
        for tool in Tool.drawingTools {
            styles[tool] = persistedStyle(for: tool) ?? fallback
        }
        return styles
    }

    func save(_ style: ToolStyle, for tool: Tool) {
        defaults.set(style.color.r, forKey: key(tool, "color.r"))
        defaults.set(style.color.g, forKey: key(tool, "color.g"))
        defaults.set(style.color.b, forKey: key(tool, "color.b"))
        defaults.set(style.color.a, forKey: key(tool, "color.a"))
        defaults.set(style.width, forKey: key(tool, "width"))
    }

    private func persistedStyle(for tool: Tool) -> ToolStyle? {
        guard let r = defaults.object(forKey: key(tool, "color.r")) as? Double,
              let g = defaults.object(forKey: key(tool, "color.g")) as? Double,
              let b = defaults.object(forKey: key(tool, "color.b")) as? Double,
              let a = defaults.object(forKey: key(tool, "color.a")) as? Double,
              let w = defaults.object(forKey: key(tool, "width")) as? Double else { return nil }
        return ToolStyle(color: RGBA(r: r, g: g, b: b, a: a), width: w)
    }

    /// The pre-per-tool global color/width, used once to seed tools on upgrade.
    private func legacyGlobalStyle() -> ToolStyle? {
        guard let r = defaults.object(forKey: "fiti.color.r") as? Double,
              let g = defaults.object(forKey: "fiti.color.g") as? Double,
              let b = defaults.object(forKey: "fiti.color.b") as? Double,
              let a = defaults.object(forKey: "fiti.color.a") as? Double else { return nil }
        let w = defaults.object(forKey: "fiti.width") as? Double ?? ToolStyle.default.width
        return ToolStyle(color: RGBA(r: r, g: g, b: b, a: a), width: w)
    }

    private func key(_ tool: Tool, _ suffix: String) -> String {
        "fiti.style.\(name(tool)).\(suffix)"
    }

    private func name(_ tool: Tool) -> String {
        switch tool {
        case .pen: return "pen"
        case .text: return "text"
        case .arrow: return "arrow"
        case .selection: return "selection"
        }
    }
}
