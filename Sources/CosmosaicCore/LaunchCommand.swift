import Foundation

/// Maps between app names and the `open -a` shell commands stored in the
/// config, so the UI can offer an app picker while the config file keeps
/// plain Hyprland `exec` lines.
public enum LaunchCommand {

    /// `-n` launches a fresh instance instead of refocusing a running one.
    public static func exec(forApp name: String) -> String {
        "open -n -a \"\(name)\""
    }

    /// The app name if the command is exactly an `open [-n] -a` launch, else
    /// nil (custom commands stay custom).
    public static func appName(fromExec command: String) -> String? {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        let prefix = ["open -n -a ", "open -a "].first { trimmed.hasPrefix($0) }
        guard let prefix else { return nil }
        let rest = trimmed.dropFirst(prefix.count)
            .trimmingCharacters(in: .whitespaces)
        guard !rest.isEmpty else { return nil }

        if rest.hasPrefix("\"") {
            guard rest.count >= 2, rest.hasSuffix("\"") else { return nil }
            let name = rest.dropFirst().dropLast()
            guard !name.isEmpty, !name.contains("\"") else { return nil }
            return String(name)
        }
        // Unquoted form: a single bare token only; anything more (arguments,
        // multi-word names) is treated as a custom command.
        guard !rest.contains(" ") else { return nil }
        return rest
    }
}
