import Foundation

/// Config key names → Carbon virtual key codes (ANSI layout, kVK_ constants),
/// and modifier sets → Carbon hotkey modifier flags. The numeric values are
/// ABI-stable; hardcoding them keeps HyprmacCore free of Carbon imports.
public enum KeyCodes {

    private static let table: [String: UInt32] = [
        "A": 0x00, "S": 0x01, "D": 0x02, "F": 0x03, "H": 0x04, "G": 0x05,
        "Z": 0x06, "X": 0x07, "C": 0x08, "V": 0x09, "B": 0x0B, "Q": 0x0C,
        "W": 0x0D, "E": 0x0E, "R": 0x0F, "Y": 0x10, "T": 0x11,
        "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17,
        "EQUAL": 0x18, "9": 0x19, "7": 0x1A, "MINUS": 0x1B, "8": 0x1C,
        "0": 0x1D, "RIGHTBRACKET": 0x1E, "O": 0x1F, "U": 0x20,
        "LEFTBRACKET": 0x21, "I": 0x22, "P": 0x23, "RETURN": 0x24,
        "L": 0x25, "J": 0x26, "APOSTROPHE": 0x27, "K": 0x28,
        "SEMICOLON": 0x29, "BACKSLASH": 0x2A, "COMMA": 0x2B,
        "SLASH": 0x2C, "N": 0x2D, "M": 0x2E, "PERIOD": 0x2F,
        "TAB": 0x30, "SPACE": 0x31, "GRAVE": 0x32, "BACKSPACE": 0x33,
        "ESCAPE": 0x35,
        "F1": 0x7A, "F2": 0x78, "F3": 0x63, "F4": 0x76, "F5": 0x60,
        "F6": 0x61, "F7": 0x62, "F8": 0x64, "F9": 0x65, "F10": 0x6D,
        "F11": 0x67, "F12": 0x6F,
        "LEFT": 0x7B, "RIGHT": 0x7C, "DOWN": 0x7D, "UP": 0x7E,
        "PAGEUP": 0x74, "PAGEDOWN": 0x79, "HOME": 0x73, "END": 0x77,
        "DELETE": 0x75,
    ]

    public static func keyCode(for name: String) -> UInt32? {
        table[name.uppercased()]
    }

    private static let reverseTable: [UInt32: String] =
        Dictionary(uniqueKeysWithValues: table.map { ($0.value, $0.key) })

    public static func name(for keyCode: UInt32) -> String? {
        reverseTable[keyCode]
    }

    public static func carbonFlags(for mods: Set<Modifier>) -> UInt32 {
        var flags: UInt32 = 0
        if mods.contains(.super) { flags |= 0x0100 }  // cmdKey
        if mods.contains(.shift) { flags |= 0x0200 }  // shiftKey
        if mods.contains(.alt) { flags |= 0x0800 }    // optionKey
        if mods.contains(.ctrl) { flags |= 0x1000 }   // controlKey
        return flags
    }
}
