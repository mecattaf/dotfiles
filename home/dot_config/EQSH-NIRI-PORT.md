# eqsh Niri Port — Activity List

## Upstream Requests (for Enviction)

Features eqsh doesn't have that we need — candidates to request from the maintainer.

| # | Request | Detail | Precedent |
|---|---------|--------|-----------|
| U1 | Niri compositor support | Replace all `Quickshell.Hyprland` usage with niri IPC / standard Wayland | Maintainer confirmed willing; DMS already solved this with `NiriService.qml` |
| U2 | Power menu component | eqsh has no power menu IPC. DMS had `powermenu toggle` | Logout = `niri msg action quit`, but suspend/reboot/shutdown needs UI |
| U3 | Clipboard history component (with image support) | eqsh has no clipboard manager. Need `cliphist` integration with image preview | DMS had `clipboard toggle`; cliphist supports both text and image |
| U4 | Audio volume IPC target | eqsh OSD is passive (reacts to Pipewire changes) but has no IPC to *set* volume | DMS had `audio mute/increment/decrement`; eqsh already imports `Quickshell.Services.Pipewire` |
| U5 | Bar toggle IPC | eqsh bar uses EdgeTrigger autohide only, no programmatic toggle | DMS had `bar toggle` |

## eqsh Niri Port — Hyprland API Removal

### Files that ACTUALLY USE Hyprland API (13 files)

| # | File | Hyprland API Used | Niri Replacement |
|---|------|-------------------|------------------|
| P1 | `ui/controls/providers/HyprlandExt.qml` | `Hyprland.activeToplevel`, `onRawEvent("fullscreen"/"activewindow"/"closewindow")` | Rewrite as `NiriExt.qml`: use `ToplevelManager.activeToplevel` + niri IPC event stream |
| P2 | `ui/controls/windows/FollowingPanelWindow.qml` | `Hyprland.focusedMonitor.name`, `onFocusedMonitorChanged` | `NiriService.currentOutput` from niri IPC `WorkspaceActivated` events |
| P3 | `ui/controls/windows/Pop.qml` | `HyprlandFocusGrab { windows, active, onCleared }` | `WlrKeyboardFocus.Exclusive` + transparent click-catcher `PanelWindow` with `Region` mask |
| P4 | `ui/components/panel/StatusBar.qml` | `Hyprland.focusedMonitor`, `HyprlandExt.appInFullscreen`, `hyprctl dispatch exit` | `NiriService.currentOutput`, `NiriExt.appInFullscreen`, `niri msg action quit` |
| P5 | `ui/components/spotlight/Launcher.qml` | `HyprlandFocusGrab { windows: [launcher] }` | Same click-catcher pattern as P3 |
| P6 | `ui/components/modal/Modal.qml` | `HyprlandFocusGrab { windows: [panelWindow] }` | Same click-catcher pattern as P3 |
| P7 | `ui/components/screenshot/Screenshot.qml` | `Hyprland.focusedMonitor`, `Hyprland.monitorFor(screen).name` | `NiriService.currentOutput` for grim, or use `niri msg action screenshot` (built-in) |
| P8 | `ui/components/notch/Notch.qml` | `HyprlandExt.appInFullscreen` (indirect) | Depends on P1 (`NiriExt.qml` rewrite) |
| P9 | `ui/components/ai/AI.qml` | `HyprlandFocusGrab { windows: [panel, statusbar] }` | Click-catcher with multi-rect `Region` exclusion (exclude both AI panel + statusbar) |
| P10 | `ui/components/about/About.qml` | `Hyprland.activeToplevel?.title` | `ToplevelManager.activeToplevel?.title` (standard Wayland, works as-is) |
| P11 | `ui/components/background/WidgetAdd.qml` | `HyprlandFocusGrab`, `Hyprland.monitorFor(screen).scale` | Click-catcher + `NiriService.displayScales[screen.name]` or `screen.devicePixelRatio` |
| P12 | `ui/components/widgets/wi/BaseWidget.qml` | `Hyprland.monitorFor(screen).scale` | `NiriService.displayScales[screen.name]` or `screen.devicePixelRatio` |
| P13 | `HyprPersist.qml` | 7x `hyprctl keyword` commands (blur, abovelock, ignorezero, blurpopups, session_lock_xray) | Rewrite as `NiriPersist.qml`: blur → niri `layer-rule` KDL fragment; `abovelock`/`xray` → no niri equivalent |

### Files with UNUSED Hyprland import (19 files — just remove import line)

| # | File |
|---|------|
| I1 | `ui/controls/auxiliary/CustomShortcut.qml` |
| I2 | `ui/controls/auxiliary/EdgeTrigger.qml` |
| I3 | `ui/controls/auxiliary/BButton.qml` |
| I4 | `ui/controls/auxiliary/GlintButton.qml` |
| I5 | `ui/controls/auxiliary/NotchApplication.qml` |
| I6 | `ui/controls/auxiliary/NotchApplicationAdvanced.qml` |
| I7 | `ui/controls/windows/FullWindow.qml` |
| I8 | `ui/components/panel/Barblock.qml` |
| I9 | `ui/components/dialog/Dialog.qml` |
| I10 | `ui/components/popup/Popup.qml` |
| I11 | `ui/components/launchpad/LaunchPad.qml` |
| I12 | `ui/components/dock/Dock.qml` |
| I13 | `ui/components/lockscreen/LockSurface.qml` |
| I14 | `ui/components/background/WidgetGridItem.qml` (if exists) |
| I15 | `ui/controls/windows/dropdown/DropDownMenu.qml` |
| I16 | `ui/controls/windows/dropdown/DropDownItem.qml` |
| I17 | `ui/controls/windows/dropdown/DropDownSpacer.qml` |
| I18 | `ui/controls/windows/dropdown/DropDownText.qml` |
| I19 | `ui/controls/windows/dropdown/DropDownItemToggle.qml` |

## Three Things to Build for Niri Support

### B1: `NiriService.qml` singleton (~200-400 lines)

Connect to `$NIRI_SOCKET`, subscribe to event stream, expose:
- `currentOutput` (string) — focused monitor name
- `displayScales` (object) — per-output scale factors
- `windows` (array) — with `is_fullscreen`, `is_focused` per window
- `quit()` / `focusWindow()` action methods

Reference: DMS `NiriService.qml` (~1400 lines, only ~30% needed)

### B2: Click-catcher pattern (replaces `HyprlandFocusGrab`)

Transparent full-screen `PanelWindow` with `WlrKeyboardFocus.Exclusive` and `Region` mask excluding popup content area. Needed in 5 places (P3, P5, P6, P9, P11).

```qml
PanelWindow {
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    visible: popupIsOpen
    color: "transparent"
    mask: Region { /* exclude popup rect */ }
    MouseArea { anchors.fill: parent; onClicked: popupIsOpen = false }
}
```

### B3: `CustomShortcut.qml` redesign

`GlobalShortcut` doesn't work at runtime on niri. Shortcuts must be pre-configured in niri KDL config as `spawn "quickshell" "ipc" "call" ...` bindings. Either:
- Generate a `~/.config/niri/eqsh/binds.kdl` fragment (like DMS does)
- Or just document the required bindings for users to add manually

## eqsh Niri Port — Edge Cases

| # | Issue | Detail |
|---|-------|--------|
| X1 | Notch above lockscreen | `abovelock` layer rule has no niri equivalent. Notch hidden during session lock (niri limitation via `ext-session-lock-v1`) |
| X2 | `session_lock_xray` | Hyprland-only. No niri equivalent — lockscreen cannot see through to desktop |
| X3 | `ignorezero` / `blurpopups` | Hyprland blur features. No niri equivalent yet — popups may need manual blur via Qt `MultiEffect` |
| X4 | Fullscreen detection latency | Hyprland fires instant raw events; niri IPC `WindowOpenedOrChanged` may have slight latency. Imperceptible in practice |
| X5 | Multi-window focus groups | `HyprlandFocusGrab { windows: [a, b] }` (AI.qml). Click-catcher must exclude multiple rectangles from `Region` mask |
| X6 | Niri blur support | Landing imminently. DMS handles with `layer-rule { match namespace="..."; place-within-backdrop true }` KDL fragment |

## eqsh Components — Fully Niri Compatible (no changes needed)

| Component | Why |
|-----------|-----|
| `core/system/Brightness.qml` | Uses `brightnessctl` / `ddcutil` / sysfs — no WM dependency |
| `core/system/MusicPlayerProvider.qml` | Pure MPRIS D-Bus — cross-WM standard |
| `core/system/NotificationDaemon.qml` | FDO notification protocol — cross-WM standard |
| `core/system/NetworkManager.qml` | Pure `nmcli` wrapper — cross-WM |
| `core/system/Plugins.qml` | QML/JS plugin system — no WM dependency |
| `core/foundation/SPPathResolver.qml` | Pure Qt path utilities |
| `core/foundation/SPAppName.qml` | `DesktopEntries` API — standard |
| `config/*` | JSON config via `FileView`/`JsonAdapter` — standard |
| `agents/*` | Pure JS (AI providers, KVO parser) — standard |
| `Logger.qml` | ANSI terminal output — standard |
| `Time.qml` | Qt `SystemClock` — standard |
| `Translation.qml` | JSON i18n — standard |
| `ReloadPopup.qml` | Quickshell reload API — standard |
| `ScreenCorners*.qml` | `WlrLayershell` — standard Wayland |
| `Runtime.qml` | QML state management — standard |

## Port Difficulty Summary

| Difficulty | Count | Items |
|---|---|---|
| Trivial (remove unused import) | 19 | I1-I19 |
| Trivial (1-line API swap) | 2 | P10 (About), P12 (BaseWidget) |
| Moderate (needs NiriService) | 8 | P1, P2, P4, P7, P8, P9, P11, P13 |
| Moderate (click-catcher pattern) | 5 | P3, P5, P6, P9, P11 |
| Hard (architectural) | 2 | P13 (HyprPersist layer rules), B3 (CustomShortcut redesign) |
