import Foundation

/// Surgical, comment-preserving edits to config file text. Each operation
/// touches only the target bind's line; the file remains the single source
/// of truth and is re-parsed afterwards.
public enum ConfigEditor {

    private static let canonicalModOrder: [Modifier] = [.super, .ctrl, .alt, .shift]

    static func modsText(_ mods: Set<Modifier>) -> String {
        canonicalModOrder.filter(mods.contains).map(\.rawValue).joined(separator: " ")
    }

    static func dispatcherText(_ dispatcher: Dispatcher) -> String {
        switch dispatcher {
        case .exec(let command): return "exec, \(command)"
        case .killactive: return "killactive"
        case .movefocus(let d): return "movefocus, \(d.rawValue)"
        case .movewindow(let d): return "movewindow, \(d.rawValue)"
        case .workspace(let n): return "workspace, \(n)"
        case .movetoworkspace(let n): return "movetoworkspace, \(n)"
        case .togglefloating: return "togglefloating"
        case .fullscreen: return "fullscreen"
        case .resizeactive(let dx, let dy): return "resizeactive, \(dx) \(dy)"
        case .reload: return "reload"
        }
    }

    public static func serialize(_ bind: Keybind,
                                 modsText modsOverride: String? = nil,
                                 comment: String? = nil) -> String {
        var line = "bind = \(modsOverride ?? modsText(bind.mods)), \(bind.key), \(dispatcherText(bind.dispatcher))"
        if let comment {
            line += "  \(comment)"
        }
        return line
    }

    public static func updateBind(in text: String, provenance: BindProvenance,
                                  oldBind: Keybind, newBind: Keybind) -> String {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        guard (1...lines.count).contains(provenance.line) else { return text }
        // Unchanged mods keep their original spelling ($mod stays $mod).
        let mods = newBind.mods == oldBind.mods ? provenance.rawMods : nil
        lines[provenance.line - 1] = serialize(newBind, modsText: mods,
                                               comment: provenance.comment)
        return lines.joined(separator: "\n")
    }

    public static func addBind(to text: String, _ bind: Keybind, afterLine: Int?) -> String {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        if let afterLine, (1...lines.count).contains(afterLine) {
            lines.insert(serialize(bind), at: afterLine)
            return lines.joined(separator: "\n")
        }
        var result = text
        if !result.isEmpty && !result.hasSuffix("\n") {
            result += "\n"
        }
        return result + serialize(bind) + "\n"
    }

    public static func deleteBind(in text: String, provenance: BindProvenance) -> String {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        guard (1...lines.count).contains(provenance.line) else { return text }
        lines.remove(at: provenance.line - 1)
        return lines.joined(separator: "\n")
    }
}
