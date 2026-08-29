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

    enum BorderStyleChoice: String, CaseIterable, Identifiable {
        case solid = "Solid"
        case gradient = "Gradient"
        case rainbow = "Rainbow"
        var id: String { rawValue }
    }

    var activeBorderColor: ConfigColor {
        config.general.activeBorder.colors.first
            ?? ConfigColor(r: 0x33, g: 0xcc, b: 0xff, a: 0xee)
    }

    var borderStyle: BorderStyleChoice {
        if config.general.borderAnimation == .rainbow { return .rainbow }
        return config.general.activeBorder.colors.count > 1 ? .gradient : .solid
    }

    func setBorderStyle(_ style: BorderStyleChoice) {
        let first = activeBorderColor
        switch style {
        case .solid:
            configManager.applyGeneralEdits([
                (key: "col.active_border", value: BorderFill(colors: [first]).configText),
                (key: "border_animation", value: "none"),
            ])
        case .gradient:
            let second = ConfigColor(r: 0x88, g: 0x39, b: 0xef, a: first.a)
            configManager.applyGeneralEdits([
                (key: "col.active_border",
                 value: BorderFill(colors: [first, second], angleDegrees: 45).configText),
                (key: "border_animation", value: "none"),
            ])
        case .rainbow:
            configManager.applyGeneralEdits([(key: "border_animation", value: "rainbow")])
        }
    }
    /// Pending value shown while a debounced write is in flight, so rapid
    /// stepper clicks accumulate instead of re-reading the stale config.
    @Published private var pendingBorderSize: Int?
    var borderSize: Int { pendingBorderSize ?? config.general.borderSize }

    private var borderSizeDebounce: DispatchWorkItem?

    func setBorderSize(_ size: Int) {
        pendingBorderSize = size
        borderSizeDebounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.configManager.setBorderSize(size)
        }
        borderSizeDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private var colorDebounce: DispatchWorkItem?

    /// Color pickers fire continuously while dragging; debounce the file write.
    func setActiveBorderColor(_ color: ConfigColor) {
        colorDebounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.configManager.setActiveBorderColor(color)
        }
        colorDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    init(configManager: ConfigManager) {
        self.configManager = configManager
        refresh()
    }

    func refresh() {
        config = configManager.config
        axTrusted = AX.isTrusted
        pendingBorderSize = nil
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

    /// Section grouping for the editor list, in display order.
    var category: String {
        switch self {
        case .exec: return "Launch"
        case .killactive, .togglefloating, .fullscreen: return "Windows"
        case .movefocus: return "Focus"
        case .movewindow: return "Move Windows"
        case .resizeactive: return "Resize"
        case .workspace, .movetoworkspace: return "Workspaces"
        case .reload: return "System"
        }
    }

    static let categoryOrder = ["Launch", "Windows", "Focus", "Move Windows",
                                "Resize", "Workspaces", "System"]

    var symbol: String {
        switch self {
        case .exec: return "terminal.fill"
        case .killactive: return "xmark.square.fill"
        case .movefocus: return "scope"
        case .movewindow: return "rectangle.2.swap"
        case .workspace: return "square.grid.3x3.middle.filled"
        case .movetoworkspace: return "arrowshape.turn.up.forward.fill"
        case .togglefloating: return "macwindow.on.rectangle"
        case .fullscreen: return "arrow.up.left.and.arrow.down.right"
        case .resizeactive: return "arrow.left.and.right.square.fill"
        case .reload: return "arrow.clockwise"
        }
    }

    var tint: Color {
        switch self {
        case .exec: return .green
        case .killactive: return .red
        case .movefocus: return .blue
        case .movewindow: return .indigo
        case .workspace: return .purple
        case .movetoworkspace: return .pink
        case .togglefloating: return .orange
        case .fullscreen: return .cyan
        case .resizeactive: return .mint
        case .reload: return .gray
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

    private var sections: [(title: String, rows: [(index: Int, bind: Keybind)])] {
        let grouped = Dictionary(grouping: Array(model.config.binds.enumerated())) {
            DispatcherKind($0.element.dispatcher).category
        }
        return DispatcherKind.categoryOrder.compactMap { title in
            guard let rows = grouped[title], !rows.isEmpty else { return nil }
            return (title, rows.map { (index: $0.offset, bind: $0.element) })
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.config.binds.isEmpty {
                emptyState
            } else {
                bindList
            }
            Divider()
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 720, minHeight: 500)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Keybindings").font(.title2.bold())
                Text("\(model.config.binds.count) bindings · hyprmac.conf")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.recording == .newBind {
                Label("Press shortcut… (esc cancels)", systemImage: "keyboard")
                    .foregroundStyle(.orange)
                    .font(.callout.weight(.medium))
            }
            Button {
                model.startRecording(.newBind)
            } label: {
                Label("Add Binding", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.recording != nil)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: List

    private var bindList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                togglesCard
                if !model.axTrusted {
                    permissionCard
                }
                ForEach(sections, id: \.title) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(section.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 6)
                        card {
                            ForEach(section.rows, id: \.index) { row in
                                BindRow(model: model, index: row.index, bind: row.bind,
                                        conflicted: model.conflicts.contains(model.comboKey(row.bind)))
                                if row.index != section.rows.last?.index {
                                    Divider().padding(.leading, 122)
                                }
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .id(model.refreshToken)
    }

    private var togglesCard: some View {
        card {
            settingRow(symbol: "squares.leading.rectangle", tint: .blue,
                       title: "Tiling",
                       subtitle: "Pause leaves every window where it is (until quit)") {
                Toggle("", isOn: Binding(
                    get: { !model.tilingPaused },
                    set: { model.setTilingEnabled($0) }))
                    .toggleStyle(.switch).labelsHidden()
            }
            Divider().padding(.leading, 56)
            settingRow(symbol: "cursorarrow.motionlines", tint: .teal,
                       title: "Focus follows mouse",
                       subtitle: "Hover focus, Hyprland-style — saved to hyprmac.conf") {
                Toggle("", isOn: Binding(
                    get: { model.followMouse },
                    set: { model.setFollowMouse($0) }))
                    .toggleStyle(.switch).labelsHidden()
            }
            Divider().padding(.leading, 56)
            settingRow(symbol: "paintbrush.fill", tint: .pink,
                       title: "Focus border",
                       subtitle: "Style, color, and thickness (0 px hides it) — saved to hyprmac.conf") {
                HStack(spacing: 12) {
                    Picker("", selection: Binding(
                        get: { model.borderStyle },
                        set: { model.setBorderStyle($0) })) {
                        ForEach(KeybindingsModel.BorderStyleChoice.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 100)
                    ColorPicker("", selection: Binding(
                        get: { Color(configColor: model.activeBorderColor) },
                        set: { model.setActiveBorderColor(ConfigColor(color: $0)) }),
                        supportsOpacity: true)
                        .labelsHidden()
                        .disabled(model.borderStyle == .rainbow)
                        .opacity(model.borderStyle == .rainbow ? 0.4 : 1)
                    Stepper(value: Binding(
                        get: { model.borderSize },
                        set: { model.setBorderSize($0) }), in: 0...12) {
                        Text("\(model.borderSize) px")
                            .monospacedDigit()
                            .frame(minWidth: 36, alignment: .trailing)
                    }
                }
            }
        }
    }

    private var permissionCard: some View {
        card {
            settingRow(symbol: "exclamationmark.triangle.fill", tint: .orange,
                       title: "Waiting for Accessibility permission",
                       subtitle: "Keybindings can be edited now; tiling starts once granted") {
                Button("Open Settings") { model.openAccessibilitySettings() }
            }
        }
    }

    private func settingRow(symbol: String, tint: Color, title: String,
                            subtitle: String,
                            @ViewBuilder control: () -> some View) -> some View {
        HStack(spacing: 12) {
            IconTile(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            control()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func card(@ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: 0) { content() }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.035)))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07)))
    }

    // MARK: Empty / footer

    private var emptyState: some View {
        VStack {
            Spacer()
            ContentUnavailableView {
                Label("No Keybindings", systemImage: "keyboard")
            } description: {
                Text("This config file has no bind lines.")
            } actions: {
                Button("Restore Default Keybindings") { model.restoreDefaults() }
                    .buttonStyle(.borderedProminent)
            }
            Spacer()
        }
    }

    private var footer: some View {
        HStack {
            Label("Edits write straight to hyprmac.conf — comments and $variables are preserved.",
                  systemImage: "checkmark.seal")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                model.openConfigFile()
            } label: {
                Label("Open Config File", systemImage: "doc.text")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }
}

extension Color {
    init(configColor: ConfigColor) {
        self.init(.sRGB,
                  red: Double(configColor.r) / 255,
                  green: Double(configColor.g) / 255,
                  blue: Double(configColor.b) / 255,
                  opacity: Double(configColor.a) / 255)
    }
}

extension ConfigColor {
    init(color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .cyan
        self.init(r: UInt8((ns.redComponent * 255).rounded()),
                  g: UInt8((ns.greenComponent * 255).rounded()),
                  b: UInt8((ns.blueComponent * 255).rounded()),
                  a: UInt8((ns.alphaComponent * 255).rounded()))
    }
}

/// Small tinted rounded-square icon, System Settings style.
private struct IconTile: View {
    let symbol: String
    let tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 27, height: 27)
            .background(RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                .fill(tint.gradient))
    }
}

private struct BindRow: View {
    @ObservedObject var model: KeybindingsModel
    let index: Int
    let bind: Keybind
    let conflicted: Bool
    @State private var hovering = false

    private var kind: DispatcherKind { DispatcherKind(bind.dispatcher) }

    var body: some View {
        HStack(spacing: 12) {
            shortcutChip
                .frame(width: 92, alignment: .center)
            IconTile(symbol: kind.symbol, tint: kind.tint)
            kindPicker
            argumentEditor
            Spacer(minLength: 8)
            if conflicted {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .help("Another binding uses this shortcut")
            }
            Button {
                model.delete(at: index)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .opacity(hovering ? 1 : 0)
            .help("Delete binding")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private var recordingThis: Bool { model.recording == .row(index) }

    private var shortcutChip: some View {
        Button {
            model.startRecording(.row(index))
        } label: {
            Text(recordingThis ? "⌨ …" : prettyShortcut)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospaced()
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .frame(minWidth: 64)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(recordingThis
                              ? AnyShapeStyle(Color.orange.opacity(0.22))
                              : AnyShapeStyle(.background)))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(recordingThis
                                      ? Color.orange.opacity(0.8)
                                      : Color.primary.opacity(0.18)))
                .shadow(color: .black.opacity(0.18), radius: 0.5, y: 1)
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
            .frame(minWidth: 180, maxWidth: 340)

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
                contentRect: NSRect(x: 0, y: 0, width: 780, height: 560),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered, defer: false)
            window.title = "hyprmac Keybindings"
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(
                rootView: KeybindingsView(model: model))
            self.window = window
        }
        model.refresh()
        // Always open dead-center of the screen with the mouse (the one whose
        // menu bar icon was clicked).
        if let window, let screen = NSScreen.screens.first(where: {
            $0.frame.contains(NSEvent.mouseLocation)
        }) ?? NSScreen.main {
            let frame = window.frame
            window.setFrameOrigin(NSPoint(
                x: screen.visibleFrame.midX - frame.width / 2,
                y: screen.visibleFrame.midY - frame.height / 2))
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        // Accessory apps can be denied activation (cooperative activation),
        // which would leave the window ordered behind the active app's tiles.
        window?.orderFrontRegardless()
    }
}
