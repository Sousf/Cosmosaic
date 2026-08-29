import Foundation

/// A modifier key in a keybind. `super` is the Command key, `alt` is Option.
public enum Modifier: String, Sendable, Hashable, CaseIterable {
    case `super` = "SUPER"
    case alt = "ALT"
    case ctrl = "CTRL"
    case shift = "SHIFT"
}

public enum Direction: String, Sendable, Equatable {
    case left = "l"
    case right = "r"
    case up = "u"
    case down = "d"
}

/// A Hyprland-style dispatcher: the action a keybind triggers.
public enum Dispatcher: Sendable, Equatable {
    case exec(String)
    case killactive
    case movefocus(Direction)
    case movewindow(Direction)
    case workspace(Int)
    case movetoworkspace(Int)
    case togglefloating
    case fullscreen
    case resizeactive(dx: Int, dy: Int)
    case reload
}

public struct Keybind: Sendable, Equatable {
    public var mods: Set<Modifier>
    public var key: String
    public var dispatcher: Dispatcher

    public init(mods: Set<Modifier>, key: String, dispatcher: Dispatcher) {
        self.mods = mods
        self.key = key
        self.dispatcher = dispatcher
    }
}

/// An 8-bit-per-channel RGBA color from `rgba(RRGGBBAA)` / `rgb(RRGGBB)` syntax.
public struct ConfigColor: Sendable, Equatable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
    public var a: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    /// Config-file spelling of this color.
    public var rgbaText: String {
        String(format: "rgba(%02x%02x%02x%02x)", r, g, b, a)
    }
}

/// The focus border's fill: one color stop is solid, more make a gradient
/// along `angleDegrees` (CSS-style: 0° points up, clockwise).
public struct BorderFill: Sendable, Equatable {
    public var colors: [ConfigColor]
    public var angleDegrees: Int

    public init(colors: [ConfigColor], angleDegrees: Int = 0) {
        self.colors = colors
        self.angleDegrees = angleDegrees
    }

    /// Config-file spelling: color stops joined, angle appended when nonzero.
    public var configText: String {
        var text = colors.map(\.rgbaText).joined(separator: " ")
        if angleDegrees != 0 { text += " \(angleDegrees)deg" }
        return text
    }
}

public enum BorderAnimation: String, Sendable, Equatable {
    case none
    case rainbow
}

public struct GeneralConfig: Sendable, Equatable {
    public var gapsIn: Int = 5
    public var gapsOut: Int = 10
    public var borderSize: Int = 2
    /// Windows smaller than this in BOTH dimensions float; zero disables.
    public var floatBelowSize = CGSize(width: 350, height: 250)
    public var activeBorder = BorderFill(
        colors: [ConfigColor(r: 0x33, g: 0xcc, b: 0xff, a: 0xee)])
    public var borderAnimation = BorderAnimation.none
    public var borderAnimationSpeed = 1.0
    public var inactiveBorderColor = ConfigColor(r: 0x59, g: 0x59, b: 0x59, a: 0xff)

    public init() {}
}

public struct WindowRule: Sendable, Equatable {
    public enum Effect: String, Sendable {
        case float
        case tile
    }

    public var effect: Effect
    /// Regex matched against the owning application's name.
    public var appPattern: String

    public init(effect: Effect, appPattern: String) {
        self.effect = effect
        self.appPattern = appPattern
    }
}

/// Where a bind came from in the config file, for surgical UI edits that
/// preserve `$variables` and comments.
public struct BindProvenance: Sendable, Equatable {
    /// 1-based line number in the file.
    public var line: Int
    /// The mods field exactly as written, before variable substitution.
    public var rawMods: String
    /// Trailing comment on the line (including `#`), if any.
    public var comment: String?

    public init(line: Int, rawMods: String, comment: String? = nil) {
        self.line = line
        self.rawMods = rawMods
        self.comment = comment
    }
}

public struct InputConfig: Sendable, Equatable {
    /// Hyprland-style hover focus. Defaults on, like Hyprland's follow_mouse=1.
    public var followMouse: Bool = true

    public init() {}
}

public struct Config: Sendable, Equatable {
    public var input = InputConfig()
    public var binds: [Keybind] = []
    /// Parallel to `binds`: source location of each bind.
    public var bindProvenance: [BindProvenance] = []
    public var general = GeneralConfig()
    public var windowRules: [WindowRule] = []

    public init() {}
}

public enum ConfigParser {
    public static func parse(_ text: String) throws -> Config {
        try parseConfig(text)
    }
}
