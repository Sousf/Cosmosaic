import Foundation

public struct ConfigError: Error, Equatable, CustomStringConvertible {
    public let line: Int
    public let message: String
    public var description: String { "line \(line): \(message)" }

    public init(line: Int, message: String) {
        self.line = line
        self.message = message
    }
}

extension ConfigParser {
    static func parseBind(fields: [String], line: Int) throws -> Keybind {
        guard fields.count >= 3 else {
            throw ConfigError(line: line, message: "bind needs MODS, KEY, DISPATCHER")
        }
        let mods = try parseMods(fields[0], line: line)
        let key = fields[1].uppercased()
        let dispatcher = try parseDispatcher(name: fields[2],
                                             args: Array(fields.dropFirst(3)),
                                             line: line)
        return Keybind(mods: mods, key: key, dispatcher: dispatcher)
    }

    static func parseMods(_ text: String, line: Int) throws -> Set<Modifier> {
        var mods: Set<Modifier> = []
        for word in text.split(separator: " ") {
            guard let mod = Modifier(rawValue: word.uppercased()) else {
                throw ConfigError(line: line, message: "unknown modifier '\(word)'")
            }
            mods.insert(mod)
        }
        return mods
    }

    static func parseDispatcher(name: String, args: [String], line: Int) throws -> Dispatcher {
        let arg = args.joined(separator: ",")
        switch name {
        case "exec":
            return .exec(arg)
        case "killactive":
            return .killactive
        case "movefocus":
            return .movefocus(try parseDirection(arg, line: line))
        case "movewindow":
            return .movewindow(try parseDirection(arg, line: line))
        case "workspace":
            return .workspace(try parseWorkspaceNumber(arg, line: line))
        case "movetoworkspace":
            return .movetoworkspace(try parseWorkspaceNumber(arg, line: line))
        case "togglefloating":
            return .togglefloating
        case "fullscreen":
            return .fullscreen
        case "resizeactive":
            let parts = arg.split(separator: " ").compactMap { Int($0) }
            guard parts.count == 2 else {
                throw ConfigError(line: line, message: "resizeactive needs 'dx dy', got '\(arg)'")
            }
            return .resizeactive(dx: parts[0], dy: parts[1])
        case "reload":
            return .reload
        default:
            throw ConfigError(line: line, message: "unknown dispatcher '\(name)'")
        }
    }

    static func parseDirection(_ text: String, line: Int) throws -> Direction {
        guard let direction = Direction(rawValue: text.lowercased()) else {
            throw ConfigError(line: line, message: "expected direction l/r/u/d, got '\(text)'")
        }
        return direction
    }

    static func parseWorkspaceNumber(_ text: String, line: Int) throws -> Int {
        guard let number = Int(text), (1...9).contains(number) else {
            throw ConfigError(line: line, message: "workspace must be 1-9, got '\(text)'")
        }
        return number
    }

    static func parseConfig(_ text: String) throws -> Config {
        var config = Config()
        var variables: [String: String] = [:]
        var openBlock: (name: String, line: Int)? = nil

        for (index, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let lineNumber = index + 1
            var line = String(rawLine)
            if let hash = line.firstIndex(of: "#") {
                line = String(line[..<hash])
            }
            line = line.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            // Substitute longest variable names first so $mode isn't clobbered by $mod.
            for (name, value) in variables.sorted(by: { $0.key.count > $1.key.count }) {
                line = line.replacingOccurrences(of: "$\(name)", with: value)
            }

            if line == "}" {
                guard openBlock != nil else {
                    throw ConfigError(line: lineNumber, message: "'}' with no open block")
                }
                openBlock = nil
                continue
            }
            if line.hasSuffix("{") {
                guard openBlock == nil else {
                    throw ConfigError(line: lineNumber, message: "nested blocks are not supported")
                }
                let name = line.dropLast().trimmingCharacters(in: .whitespaces)
                guard name == "general" else {
                    throw ConfigError(line: lineNumber, message: "unknown block '\(name)'")
                }
                openBlock = (name, lineNumber)
                continue
            }

            guard let eq = line.firstIndex(of: "=") else {
                throw ConfigError(line: lineNumber, message: "expected 'key = value'")
            }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)

            if openBlock?.name == "general" {
                try setGeneralOption(&config.general, key: key, value: value, line: lineNumber)
                continue
            }

            if key.hasPrefix("$") {
                variables[String(key.dropFirst())] = value
                continue
            }

            let fields = value.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }

            switch key {
            case "bind":
                config.binds.append(try parseBind(fields: fields, line: lineNumber))
            case "windowrule":
                config.windowRules.append(try parseWindowRule(fields: fields, line: lineNumber))
            default:
                throw ConfigError(line: lineNumber, message: "unknown option '\(key)'")
            }
        }

        if let block = openBlock {
            throw ConfigError(line: block.line, message: "unclosed block '\(block.name)'")
        }
        return config
    }

    static func setGeneralOption(_ general: inout GeneralConfig,
                                 key: String, value: String, line: Int) throws {
        func integer() throws -> Int {
            guard let n = Int(value), n >= 0 else {
                throw ConfigError(line: line, message: "'\(key)' expects a non-negative integer, got '\(value)'")
            }
            return n
        }
        switch key {
        case "gaps_in": general.gapsIn = try integer()
        case "gaps_out": general.gapsOut = try integer()
        case "border_size": general.borderSize = try integer()
        case "col.active_border": general.activeBorderColor = try parseColor(value, line: line)
        case "col.inactive_border": general.inactiveBorderColor = try parseColor(value, line: line)
        default:
            throw ConfigError(line: line, message: "unknown general option '\(key)'")
        }
    }

    static func parseColor(_ text: String, line: Int) throws -> ConfigColor {
        let hex: Substring
        var alpha: UInt8 = 0xff
        if text.hasPrefix("rgba(") && text.hasSuffix(")") {
            let digits = text.dropFirst(5).dropLast()
            guard digits.count == 8 else {
                throw ConfigError(line: line, message: "rgba() expects RRGGBBAA, got '\(text)'")
            }
            hex = digits.prefix(6)
            guard let a = UInt8(digits.suffix(2), radix: 16) else {
                throw ConfigError(line: line, message: "invalid alpha in '\(text)'")
            }
            alpha = a
        } else if text.hasPrefix("rgb(") && text.hasSuffix(")") {
            hex = text.dropFirst(4).dropLast()
            guard hex.count == 6 else {
                throw ConfigError(line: line, message: "rgb() expects RRGGBB, got '\(text)'")
            }
        } else {
            throw ConfigError(line: line, message: "expected rgb(RRGGBB) or rgba(RRGGBBAA), got '\(text)'")
        }
        guard let r = UInt8(hex.prefix(2), radix: 16),
              let g = UInt8(hex.dropFirst(2).prefix(2), radix: 16),
              let b = UInt8(hex.suffix(2), radix: 16) else {
            throw ConfigError(line: line, message: "invalid hex color '\(text)'")
        }
        return ConfigColor(r: r, g: g, b: b, a: alpha)
    }

    static func parseWindowRule(fields: [String], line: Int) throws -> WindowRule {
        guard fields.count == 2 else {
            throw ConfigError(line: line, message: "windowrule needs 'EFFECT, PATTERN'")
        }
        guard let effect = WindowRule.Effect(rawValue: fields[0]) else {
            throw ConfigError(line: line, message: "unknown windowrule effect '\(fields[0])'")
        }
        do {
            _ = try NSRegularExpression(pattern: fields[1])
        } catch {
            throw ConfigError(line: line, message: "invalid regex '\(fields[1])'")
        }
        return WindowRule(effect: effect, appPattern: fields[1])
    }
}
