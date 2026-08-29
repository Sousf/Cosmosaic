# hyprmac

A Hyprland-like tiling window manager for macOS. Automatic dwindle tiling,
nine instant workspaces, directional focus, and Hyprland's config syntax —
built on public APIs only (Accessibility), no SIP changes, distributed as a
direct download.

## How it works

hyprmac is a menu-bar agent. It watches every normal window through the
Accessibility API and tiles them into a dwindle BSP layout — each new window
splits the focused one, alternating orientation by region aspect, exactly like
Hyprland's default layout.

Float-or-tile is decided in layers, most trustworthy first: your
`windowrule`s (regex on app name or title; a `tile` rule overrides every
heuristic), then structure (modals and dialogs raise above the tiles
unmanaged; immovable windows are left alone; non-resizable windows float),
then size (windows born smaller than `float_below_size` in both dimensions
float). Finally the layout is verified after it's applied: a window that
refuses its assigned tile size — resizable-but-clamped settings panels —
is automatically demoted to floating at the size it insists on. Global hotkeys are registered through Carbon
`RegisterEventHotKey`, so bound keys are consumed before apps see them and no
Input Monitoring permission is needed.

Workspaces are emulated (the AeroSpace approach): windows on inactive
workspaces are parked just off the bottom-right screen edge, so switching is
instant with no Mission Control animation. Cmd-Tabbing to a window on another
workspace automatically switches you there. The quirk of this model: hidden
windows still appear in Cmd-Tab and Mission Control.

## Install / build

Requires macOS 14+ and Xcode command line tools.

```sh
./scripts/build-app.sh          # builds dist/hyprmac.app (release)
open dist/hyprmac.app
```

On first launch, grant the Accessibility permission when asked
(System Settings → Privacy & Security → Accessibility → enable hyprmac).
The onboarding window closes itself once granted and tiling starts.

Signing: the build script signs with a local `hyprmac-dev` certificate when
one exists in the keychain, so the Accessibility grant survives rebuilds.
Without it, builds are ad-hoc signed and macOS demands a fresh grant after
every rebuild (remove the entry with −, re-add, toggle on — toggling alone is
not enough). Proper distribution needs Developer ID + notarization.

## Configuration

Everything lives in `~/.config/hyprmac/hyprmac.conf`, written in Hyprland's
syntax and hot-reloaded on save. A commented default is created on first run.

```ini
general {
    gaps_in = 6                          # gap between windows
    gaps_out = 12                        # gap at screen edges
    border_size = 2                      # focused-window border (0 = off)
    col.active_border = rgba(33ccffee)   # or a gradient:
                                         #   rgba(..) rgba(..) 45deg
    border_animation = none              # rainbow = moving rainbow border
    border_animation_speed = 1.0
}

input {
    follow_mouse = 1                     # hover focus, Hyprland-style
}                                        # (0 to disable)

$mod = ALT                               # ALT = Option. SUPER = Command —
                                         # careful, SUPER binds shadow macOS
                                         # shortcuts like Cmd+Q.

bind = $mod, RETURN, exec, open -a Terminal
bind = $mod, Q, killactive
bind = $mod, H, movefocus, l             # l / r / u / d
bind = $mod SHIFT, H, movewindow, l      # swap with neighbor
bind = $mod CTRL, L, resizeactive, 40 0  # grow 40px horizontally
bind = $mod, 1, workspace, 1             # workspaces 1–9
bind = $mod SHIFT, 1, movetoworkspace, 1
bind = $mod, V, togglefloating
bind = $mod, F, fullscreen
bind = $mod SHIFT, C, reload

windowrule = float, ^(System Settings)$  # regex on app name
```

Supported dispatchers: `exec`, `killactive`, `movefocus`, `movewindow`,
`workspace`, `movetoworkspace`, `togglefloating`, `fullscreen`,
`resizeactive`, `reload`.

Key names: letters, digits, `F1`–`F12`, `RETURN`, `SPACE`, `TAB`, `ESCAPE`,
arrows (`LEFT`/`RIGHT`/`UP`/`DOWN`), `MINUS`, `EQUAL`, `COMMA`, `PERIOD`,
`SLASH`, `SEMICOLON`, `APOSTROPHE`, brackets, `BACKSLASH`, `GRAVE`,
`BACKSPACE`, `DELETE`, `HOME`, `END`, `PAGEUP`, `PAGEDOWN`.

A parse error never kills the running layout: hyprmac keeps the last good
config and shows ⚠︎ in the menu bar with the line number.

## Menu bar & keybindings UI

The status item shows the current workspace (◫ 1). **Left-click it to open
the Keybindings window**: click any shortcut chip and press a new combo to
rebind it, change actions from a dropdown, add or delete bindings, and see
conflict warnings. Edits are written straight into `hyprmac.conf` as surgical
single-line changes — your comments and `$mod` variables survive — so the UI
and hand-editing stay interchangeable. Right-click the icon for the menu:
Pause/Resume Tiling, Reload Config, Open Config File, Quit.

## Development

```sh
swift test        # config parser, layout tree, geometry — all pure, TDD'd
swift build       # debug build
./scripts/build-app.sh debug
```

`Sources/HyprmacCore` is pure logic (no AppKit/AX imports) and fully unit
tested. `Sources/hyprmac` is the thin system layer: AX calls, Carbon hotkeys,
and AppKit UI, verified by hand against the live WindowServer.

## Roadmap

Master layout, `hyprmacctl` CLI, scratchpad/special
workspace, per-app workspace rules, cross-monitor `movewindow`, Homebrew cask,
Developer ID signing + notarization. Window-move animations were considered
and deliberately skipped: without compositor access macOS can only fake them
(AX frame-stepping or snapshot fly-overs), and the tradeoffs weren't worth it.
