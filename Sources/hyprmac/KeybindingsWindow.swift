import SwiftUI
import HyprmacCore

// MARK: - Model

@MainActor
final class KeybindingsModel: ObservableObject {

    enum RecordingTarget: Equatable {
        case row(Int)
        case newBind
    }

    @Published private(set) var config = Config()
    @Published var recording: RecordingTarget?
    /// Changes on every reload so row views rebuild with fresh state.
    @Published private(set) var refreshToken = UUID()
    @Published private(set) var axTrusted = false
    /// Mirrors the tiling controller's pause state (session-only).
    @Published private(set) var tilingPaused = false

    private let configManager: ConfigManager
    var onRecordingStarted: (() -> Void)?
    var onRecordingEnded: (() -> Void)?
    /// Toggles the controller's pause; wired by the app delegate.
    var onSetTilingEnabled: ((Bool) -> Void)?
    private var monitor: Any?

    var followMouse: Bool { config.input.followMouse }

    func setTilingPaused(_ paused: Bool) {
        tilingPaused = paused
    }

    func setTilingEnabled(_ enabled: Bool) {
        onSetTilingEnabled?(enabled)
    }

    func setFollowMouse(_ enabled: Bool) {
        configManager.setFollowMouse(enabled)
    }

    init(configManager: ConfigManager) {
        self.configManager = configManager
        refresh()
    }

    func refresh() {
        config = configManager.config
        axTrusted = AX.isTrusted
        refreshToken = UUID()
    }

    /// Replace the whole config file with the shipped defaults (confirmed
    /// destructive action — offered from the empty state).
    func restoreDefaults() {
        let alert = NSAlert()
        alert.messageText = "Restore default keybindings?"
        alert.informativeText = "This replaces hyprmac.conf with the default configuration. Any custom settings in the file are overwritten."
        alert.addButton(withTitle: "Restore Defaults")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        configManager.write(text: ConfigManager.defaultConfigText)
    }

    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    /// Key combos used by more than one bind, e.g. "ALT+H".
    var conflicts: Set<String> {
        let combos = config.binds.map { comboKey($0) }
        var seen: Set<String> = []
        var duplicated: Set<String> = []
        for combo in combos {
            if !seen.insert(combo).inserted { duplicated.insert(combo) }
        }
        return duplicated
    }

    func comboKey(_ bind: Keybind) -> String {
        ConfigEditor.serialize(Keybind(mods: bind.mods, key: bind.key, dispatcher: .reload))
    }

    // MARK: File write-through

    func update(at index: Int, _ transform: (inout Keybind) -> Void) {
        guard config.binds.indices.contains(index),
              config.bindProvenance.indices.contains(index),
              let text = configManager.fileText() else { return }
        let old = config.binds[index]
        var new = old
        transform(&new)
        guard new != old else { return }
        configManager.write(text: ConfigEditor.updateBind(
            in: text, provenance: config.bindProvenance[index],
            oldBind: old, newBind: new))
    }

    func delete(at index: Int) {
        guard config.bindProvenance.indices.contains(index),
              let text = configManager.fileText() else { return }
        configManager.write(text: ConfigEditor.deleteBind(
            in: text, provenance: config.bindProvenance[index]))
    }

    func add(_ bind: Keybind) {
        guard let text = configManager.fileText() else { return }
        configManager.write(text: ConfigEditor.addBind(
            to: text, bind, afterLine: config.bindProvenance.last?.line))
    }

    func openConfigFile() {
        NSWorkspace.shared.open(configManager.configURL)
    }

    // MARK: Shortcut recording

    func startRecording(_ target: RecordingTarget) {
        guard monitor == nil else { return }
        recording = target
        onRecordingStarted?()  // suspend global hotkeys
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            MainActor.assumeIsolated { self.handleRecorded(event) }
            return nil  // consume while recording
        }
    }

    func cancelRecording() {
        guard recording != nil else { return }
        stopRecording()
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = nil
        onRecordingEnded?()  // resume global hotkeys
    }

    private func handleRecorded(_ event: NSEvent) {
        guard let target = recording else { return }
        if event.keyCode == 53 {  // Escape cancels
            stopRecording()
            return
        }
        guard let key = KeyCodes.name(for: UInt32(event.keyCode)) else { return }

        var mods: Set<Modifier> = []
        if event.modifierFlags.contains(.command) { mods.insert(.super) }
        if event.modifierFlags.contains(.option) { mods.insert(.alt) }
        if event.modifierFlags.contains(.control) { mods.insert(.ctrl) }
        if event.modifierFlags.contains(.shift) { mods.insert(.shift) }

        // Bare keys make terrible global hotkeys; require a modifier except
        // for function keys.
        let isFunctionKey = key.count > 1 && key.hasPrefix("F") && Int(key.dropFirst()) != nil
        guard !mods.isEmpty || isFunctionKey else { return }

        stopRecording()
        switch target {
        case .row(let index):
            update(at: index) { bind in
                bind.mods = mods
                bind.key = key
            }
        case .newBind:
            add(Keybind(mods: mods, key: key, dispatcher: .exec("open -a Terminal")))
        }
    }
}

// MARK: - Dispatcher picker plumbing

enum DispatcherKind: String, CaseIterable, Identifiable {
    case exec = "Launch command"
    case killactive = "Close window"
    case movefocus = "Move focus"
    case movewindow = "Move window"
    case workspace = "Go to workspace"
    case movetoworkspace = "Send to workspace"
    case togglefloating = "Toggle floating"
    case fullscreen = "Toggle fullscreen"
    case resizeactive = "Resize window"
    case reload = "Reload config"

    var id: String { rawValue }

    init(_ dispatcher: Dispatcher) {
        switch dispatcher {
        case .exec: self = .exec
        case .killactive: self = .killactive
        case .movefocus: self = .movefocus
        case .movewindow: self = .movewindow
        case .workspace: self = .workspace
        case .movetoworkspace: self = .movetoworkspace
        case .togglefloating: self = .togglefloating
        case .fullscreen: self = .fullscreen
        case .resizeactive: self = .resizeactive
        case .reload: self = .reload
        }
    }

    /// A sensible starting dispatcher when the user switches kinds.
    var defaultDispatcher: Dispatcher {
        switch self {
        case .exec: return .exec("open -a Terminal")
        case .killactive: return .killactive
        case .movefocus: return .movefocus(.left)
        case .movewindow: return .movewindow(.left)
        case .workspace: return .workspace(1)
        case .movetoworkspace: return .movetoworkspace(1)
        case .togglefloating: return .togglefloating
        case .fullscreen: return .fullscreen
        case .resizeactive: return .resizeactive(dx: 40, dy: 0)
        case .reload: return .reload
        }
    }
}

// MARK: - Views

struct KeybindingsView: View {
    @ObservedObject var model: KeybindingsModel

    var body: some View {
        VStack(spacing: 0) {
            header
            if !model.axTrusted {
                permissionBanner
            }
            Divider()
            if model.config.binds.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Text("This config has no keybindings.")
                        .foregroundStyle(.secondary)
                    Button("Restore Default Keybindings") { model.restoreDefaults() }
                    Text("or click “Add Binding” to start from scratch")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            } else {
                bindList
            }
            Divider()
            footer
        }
        .frame(minWidth: 700, minHeight: 460)
    }

    private var permissionBanner: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Keybindings can be edited now, but tiling stays inactive until the Accessibility permission is granted.")
                .font(.callout)
            Spacer()
            Button("Open Accessibility Settings") { model.openAccessibilitySettings() }
        }
        .padding(.horizontal)
        .padding(.bottom, 10)
    }

    private var header: some View {
        HStack(spacing: 16) {
            Text("Keybindings").font(.title2.bold())
            Spacer()
            Toggle("Tiling", isOn: Binding(
                get: { !model.tilingPaused },
                set: { model.setTilingEnabled($0) }))
                .toggleStyle(.switch)
                .help("Pause or resume window tiling (until quit; not saved)")
            Toggle("Focus follows mouse", isOn: Binding(
                get: { model.followMouse },
                set: { model.setFollowMouse($0) }))
                .toggleStyle(.switch)
                .help("Hover focus — saved to hyprmac.conf")
            if model.recording == .newBind {
                Text("Press shortcut… (Esc cancels)")
                    .foregroundStyle(.orange)
            }
            Button {
                model.startRecording(.newBind)
            } label: {
                Label("Add Binding", systemImage: "plus")
            }
            .disabled(model.recording != nil)
        }
        .padding()
    }

    private var bindList: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(Array(model.config.binds.enumerated()), id: \.offset) { index, bind in
                    BindRow(model: model, index: index, bind: bind,
                            conflicted: model.conflicts.contains(model.comboKey(bind)))
                }
            }
            .padding()
        }
        .id(model.refreshToken)
    }

    private var footer: some View {
        HStack {
            Text("Edits write straight to hyprmac.conf — comments and $variables are preserved.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Open Config File") { model.openConfigFile() }
        }
        .padding()
    }
}

private struct BindRow: View {
    @ObservedObject var model: KeybindingsModel
    let index: Int
    let bind: Keybind
    let conflicted: Bool

    var body: some View {
        HStack(spacing: 10) {
            shortcutChip
            if conflicted {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .help("Another binding uses this shortcut")
            }
            kindPicker
            argumentEditor
            Spacer()
            Button {
                model.delete(at: index)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Delete binding")
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }

    private var shortcutChip: some View {
        Button {
            model.startRecording(.row(index))
        } label: {
            Text(model.recording == .row(index) ? "Press shortcut…" : prettyShortcut)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6)
                    .fill(model.recording == .row(index)
                          ? Color.orange.opacity(0.25)
                          : Color.accentColor.opacity(0.15)))
        }
        .buttonStyle(.plain)
        .help("Click, then press the new shortcut")
    }

    private var prettyShortcut: String {
        var parts: [String] = []
        if bind.mods.contains(.ctrl) { parts.append("⌃") }
        if bind.mods.contains(.alt) { parts.append("⌥") }
        if bind.mods.contains(.shift) { parts.append("⇧") }
        if bind.mods.contains(.super) { parts.append("⌘") }
        let keyNames = ["RETURN": "↩", "SPACE": "␣", "TAB": "⇥", "ESCAPE": "⎋",
                        "LEFT": "←", "RIGHT": "→", "UP": "↑", "DOWN": "↓",
                        "BACKSPACE": "⌫", "DELETE": "⌦"]
        parts.append(keyNames[bind.key] ?? bind.key)
        return parts.joined()
    }

    private var kindPicker: some View {
        Picker("", selection: Binding(
            get: { DispatcherKind(bind.dispatcher) },
            set: { kind in
                model.update(at: index) { $0.dispatcher = kind.defaultDispatcher }
            })) {
            ForEach(DispatcherKind.allCases) { kind in
                Text(kind.rawValue).tag(kind)
            }
        }
        .labelsHidden()
        .frame(width: 170)
    }

    @ViewBuilder
    private var argumentEditor: some View {
        switch bind.dispatcher {
        case .exec(let command):
            CommitTextField(placeholder: "shell command", initial: command) { text in
                model.update(at: index) { $0.dispatcher = .exec(text) }
            }
            .frame(minWidth: 180)

        case .movefocus(let direction):
            directionPicker(Binding(
                get: { direction },
                set: { dir in model.update(at: index) { $0.dispatcher = .movefocus(dir) } }))

        case .movewindow(let direction):
            directionPicker(Binding(
                get: { direction },
                set: { dir in model.update(at: index) { $0.dispatcher = .movewindow(dir) } }))

        case .workspace(let n):
            workspacePicker(Binding(
                get: { n },
                set: { number in model.update(at: index) { $0.dispatcher = .workspace(number) } }))

        case .movetoworkspace(let n):
            workspacePicker(Binding(
                get: { n },
                set: { number in model.update(at: index) { $0.dispatcher = .movetoworkspace(number) } }))

        case .resizeactive(let dx, let dy):
            CommitTextField(placeholder: "dx dy", initial: "\(dx) \(dy)") { text in
                let parts = text.split(separator: " ").compactMap { Int($0) }
                guard parts.count == 2 else { return }
                model.update(at: index) { $0.dispatcher = .resizeactive(dx: parts[0], dy: parts[1]) }
            }
            .frame(width: 80)

        case .killactive, .togglefloating, .fullscreen, .reload:
            EmptyView()
        }
    }

    private func directionPicker(_ selection: Binding<Direction>) -> some View {
        Picker("", selection: selection) {
            Text("← left").tag(Direction.left)
            Text("→ right").tag(Direction.right)
            Text("↑ up").tag(Direction.up)
            Text("↓ down").tag(Direction.down)
        }
        .labelsHidden()
        .frame(width: 100)
    }

    private func workspacePicker(_ selection: Binding<Int>) -> some View {
        Picker("", selection: selection) {
            ForEach(1...9, id: \.self) { Text("\($0)").tag($0) }
        }
        .labelsHidden()
        .frame(width: 60)
    }
}

/// TextField that commits on Return or focus loss, not per keystroke —
/// each commit is a config-file write.
private struct CommitTextField: View {
    let placeholder: String
    let initial: String
    let commit: (String) -> Void

    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.roundedBorder)
            .focused($focused)
            .onAppear { text = initial }
            .onSubmit { commit(text) }
            .onChange(of: focused) { _, isFocused in
                if !isFocused && text != initial { commit(text) }
            }
    }
}

// MARK: - Window controller

@MainActor
final class KeybindingsWindowController {

    private var window: NSWindow?
    private let model: KeybindingsModel

    init(model: KeybindingsModel) {
        self.model = model
    }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 500),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered, defer: false)
            window.title = "hyprmac Keybindings"
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(
                rootView: KeybindingsView(model: model))
            window.center()
            self.window = window
        }
        model.refresh()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
