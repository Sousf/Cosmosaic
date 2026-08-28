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

    /// Set `key = value` inside `block { }`, replacing just the value token in
    /// place (indent and comments untouched), inserting the key into an
    /// existing block, or appending a whole new block when absent.
    public static func setOption(in text: String, block: String,
                                 key: String, value: String) -> String {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        var inBlock = false

        for index in lines.indices {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if !inBlock {
                if trimmed == "\(block) {" { inBlock = true }
                continue
            }
            if trimmed == "}" {
                // Key wasn't in the block: insert it just before the brace.
                lines.insert("    \(key) = \(value)", at: index)
                return lines.joined(separator: "\n")
            }
            if let replaced = replacingValue(inLine: lines[index], key: key, value: value) {
                lines[index] = replaced
                return lines.joined(separator: "\n")
            }
        }

        var result = text
        if !result.isEmpty && !result.hasSuffix("\n") { result += "\n" }
        return result + "\n\(block) {\n    \(key) = \(value)\n}\n"
    }

    /// If `line` assigns `key`, replace only the value token, preserving
    /// indentation, spacing, and any trailing comment. Returns nil otherwise.
    private static func replacingValue(inLine line: String, key: String,
                                       value: String) -> String? {
        let code: Substring
        let suffix: Substring
        if let hash = line.firstIndex(of: "#") {
            code = line[..<hash]
            suffix = line[hash...]
        } else {
            code = line[...]
            suffix = ""
        }
        guard let eq = code.firstIndex(of: "="),
              code[..<eq].trimmingCharacters(in: .whitespaces) == key else { return nil }

        let valueRegion = code[code.index(after: eq)...]
        guard let valueStart = valueRegion.firstIndex(where: { $0 != " " }) else {
            // `key =` with no value yet: append one.
            return String(code) + " \(value)" + suffix
        }
        var valueEnd = valueRegion.endIndex
        while valueEnd > valueStart, valueRegion[valueRegion.index(before: valueEnd)] == " " {
            valueEnd = valueRegion.index(before: valueEnd)
        }
        return String(code[..<valueStart]) + value + String(valueRegion[valueEnd...]) + suffix
    }

    public static func deleteBind(in text: String, provenance: BindProvenance) -> String {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        guard (1...lines.count).contains(provenance.line) else { return text }
        lines.remove(at: provenance.line - 1)
        return lines.joined(separator: "\n")
    }
}
