import Foundation
import CosmosaicCore

/// Loads ~/.config/cosmosaic/cosmosaic.conf, writes the default on first run, and
/// hot-reloads on change. A broken config keeps the last good one running.
@MainActor
final class ConfigManager {

    static let defaultConfigText = """
    # Cosmosaic — Hyprland-like tiling for macOS
    # Syntax follows hyprland.conf; see https://wiki.hyprland.org
    # ALT is the Option key. SUPER is Command (careful: SUPER binds shadow
    # standard macOS shortcuts like Cmd+Q).

    general {
        gaps_in = 6
        gaps_out = 12
        border_size = 2
        col.active_border = rgba(33ccffee)
        # Gradient: col.active_border = rgba(33ccffee) rgba(8839efee) 45deg
        # Moving rainbow: border_animation = rainbow (speed via
        # border_animation_speed = 1.0)
        border_animation = none
        col.inactive_border = rgba(59595900)
        float_below_size = 350 250    # windows smaller than this in BOTH
                                      # dimensions float; 0 0 disables
    }

    input {
        follow_mouse = 1    # Hyprland-style hover focus; 0 to disable
    }

    island {
        enabled = 1         # notch island: workspace + media controls
    }

    $mod = ALT

    # Launch things
    bind = $mod, RETURN, exec, open -a Terminal
    bind = $mod, B, exec, open -a Safari

    # Window management
    bind = $mod, Q, killactive
    bind = $mod, V, togglefloating
    bind = $mod, F, fullscreen

    # Move focus (vim keys and arrows)
    bind = $mod, H, movefocus, l
    bind = $mod, L, movefocus, r
    bind = $mod, K, movefocus, u
    bind = $mod, J, movefocus, d
    bind = $mod, LEFT, movefocus, l
    bind = $mod, RIGHT, movefocus, r
    bind = $mod, UP, movefocus, u
    bind = $mod, DOWN, movefocus, d

    # Swap windows
    bind = $mod SHIFT, H, movewindow, l
    bind = $mod SHIFT, L, movewindow, r
    bind = $mod SHIFT, K, movewindow, u
    bind = $mod SHIFT, J, movewindow, d

    # Resize the focused window
    bind = $mod CTRL, H, resizeactive, -40 0
    bind = $mod CTRL, L, resizeactive, 40 0
    bind = $mod CTRL, K, resizeactive, 0 -40
    bind = $mod CTRL, J, resizeactive, 0 40

    # Workspaces
    bind = $mod, 1, workspace, 1
    bind = $mod, 2, workspace, 2
    bind = $mod, 3, workspace, 3
    bind = $mod, 4, workspace, 4
    bind = $mod, 5, workspace, 5
    bind = $mod, 6, workspace, 6
    bind = $mod, 7, workspace, 7
    bind = $mod, 8, workspace, 8
    bind = $mod, 9, workspace, 9
    bind = $mod SHIFT, 1, movetoworkspace, 1
    bind = $mod SHIFT, 2, movetoworkspace, 2
    bind = $mod SHIFT, 3, movetoworkspace, 3
    bind = $mod SHIFT, 4, movetoworkspace, 4
    bind = $mod SHIFT, 5, movetoworkspace, 5
    bind = $mod SHIFT, 6, movetoworkspace, 6
    bind = $mod SHIFT, 7, movetoworkspace, 7
    bind = $mod SHIFT, 8, movetoworkspace, 8
    bind = $mod SHIFT, 9, movetoworkspace, 9

    # Reload this file (also happens automatically on save)
    bind = $mod SHIFT, C, reload

    # Window rules: float or tile, matched (regex) against app name OR window
    # title. A tile rule overrides every automatic heuristic.
    windowrule = float, ^(System Settings)$
    windowrule = float, ^(Calculator)$
    windowrule = float, ^(Activity Monitor)$
    windowrule = float, Picture-in-Picture
    """

    let configDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/cosmosaic")
    var configURL: URL { configDirectory.appendingPathComponent("cosmosaic.conf") }

    private(set) var config = Config()
    private(set) var lastError: ConfigError?
    private var watcher: DispatchSourceFileSystemObject?
    private var reloadDebounce: DispatchWorkItem?

    var onConfigChanged: ((Config) -> Void)?
    var onError: ((ConfigError) -> Void)?

    func start() {
        createDefaultIfMissing()
        load()
        watchDirectory()
    }

    private func createDefaultIfMissing() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: configURL.path) else { return }
        do {
            try fm.createDirectory(at: configDirectory, withIntermediateDirectories: true)
            // Migrate a config from the app's pre-rename days rather than
            // clobbering the user's customizations with defaults.
            let legacy = fm.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/hyprmac/hyprmac.conf")
            if fm.fileExists(atPath: legacy.path) {
                try fm.copyItem(at: legacy, to: configURL)
            } else {
                try Self.defaultConfigText.write(to: configURL, atomically: true, encoding: .utf8)
            }
        } catch {
            lastError = ConfigError(line: 0,
                                    message: "cannot create \(configURL.path): \(error.localizedDescription)")
            onError?(lastError!)
        }
    }

    func load() {
        let text: String
        do {
            text = try String(contentsOf: configURL, encoding: .utf8)
        } catch {
            lastError = ConfigError(line: 0, message: "cannot read \(configURL.path)")
            onError?(lastError!)
            return
        }
        do {
            config = try ConfigParser.parse(text)
            lastError = nil
            onConfigChanged?(config)
        } catch let error as ConfigError {
            lastError = error
            onError?(error)
        } catch {
            lastError = ConfigError(line: 0, message: "\(error)")
            onError?(lastError!)
        }
    }

    /// Persist the notch-island toggle.
    func setIslandEnabled(_ enabled: Bool) {
        guard let text = fileText() else { return }
        write(text: ConfigEditor.setOption(in: text, block: "island",
                                           key: "enabled",
                                           value: enabled ? "1" : "0"))
    }

    /// Persist the follow-mouse toggle into the config file (surgical edit;
    /// hot-reload then applies it everywhere).
    func setFollowMouse(_ enabled: Bool) {
        guard let text = fileText() else { return }
        write(text: ConfigEditor.setOption(in: text, block: "input",
                                           key: "follow_mouse",
                                           value: enabled ? "1" : "0"))
    }

    /// Apply several block-option edits as one write (one reload).
    func applyGeneralEdits(_ edits: [(key: String, value: String)]) {
        guard var text = fileText() else { return }
        for edit in edits {
            text = ConfigEditor.setOption(in: text, block: "general",
                                          key: edit.key, value: edit.value)
        }
        write(text: text)
    }

    /// Persist the focus-border color (replaces any gradient with a solid).
    func setActiveBorderColor(_ color: ConfigColor) {
        applyGeneralEdits([(key: "col.active_border", value: color.rgbaText)])
    }

    /// Persist the focus-border thickness (0 hides the border).
    func setBorderSize(_ size: Int) {
        guard let text = fileText() else { return }
        write(text: ConfigEditor.setOption(in: text, block: "general",
                                           key: "border_size",
                                           value: String(size)))
    }

    /// Current raw file text, for UI-driven surgical edits.
    func fileText() -> String? {
        try? String(contentsOf: configURL, encoding: .utf8)
    }

    /// Write edited text and reload immediately (the watcher would also fire,
    /// but this makes UI edits apply without the debounce delay).
    func write(text: String) {
        do {
            try text.write(to: configURL, atomically: true, encoding: .utf8)
        } catch {
            lastError = ConfigError(line: 0,
                                    message: "cannot write \(configURL.path): \(error.localizedDescription)")
            onError?(lastError!)
            return
        }
        load()
    }

    /// Watch the directory, not the file: editors save atomically by replacing
    /// the file, which would orphan a file-level watch.
    private func watchDirectory() {
        let fd = open(configDirectory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            self.reloadDebounce?.cancel()
            let work = DispatchWorkItem { self.load() }
            self.reloadDebounce = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        watcher = source
    }
}
