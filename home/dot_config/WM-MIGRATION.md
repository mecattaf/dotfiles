# Scroll + DMS -> Niri + eqsh Migration

## Keybinding Fixes

| # | Activity | Detail |
|---|----------|--------|
| K1 | Remap `Mod+Shift+Q` from `quit` to `close-window` | Match scroll's kill behavior |
| K2 | Remove `Mod+Q` close-window binding | Scroll had no Mod+Q; only Mod+Shift+Q kills |
| K3 | Remove niri quit binding entirely | Scroll intentionally has no WM exit keybind |
| K4 | Decide on `Mod+Shift+E` (Google Drive webapp) | Currently dropped — conflicts in niri. Re-add on a different binding or accept loss |
| K5 | Decide on `Mod+Shift+F` / `Mod+Shift+G` (reverse cycle sizing) | Niri only cycles forward. Accept, or write wrapper that tracks state and resets to previous |
| K6 | Decide on `Mod+Grave` (layout transpose) | No niri equivalent. Accept loss or repurpose binding |
| K7 | Decide on `Mod+Page_Up/Down` (workspace scaling) | No niri equivalent. Repurpose for gap adjust via `niri msg` or leave unbound |
| K8 | Decide on `Mod+BackSpace` (set_mode) | No niri equivalent. Repurpose or leave unbound |

## eqsh IPC Wiring (DMS -> Quickshell)

Syntax: `quickshell ipc call <target> <method> [args]`

| # | Activity | Binding | eqsh IPC Call |
|---|----------|---------|---------------|
| E1 | Wire up spotlight/app launcher | `Mod+Shift+D` | `quickshell ipc call spotlight toggle` |
| E2 | Wire up settings panel | `Mod+Comma` | `quickshell ipc call settings toggle` |
| E3 | Wire up control center | `Mod+B` | `quickshell ipc call controlCenter open` |
| E4 | Wire up notification center | `Mod+O` | `quickshell ipc call notificationCenter toggle` |
| E5 | Wire up brightness down | `F1` | `quickshell ipc call display dimmer 5` |
| E6 | Wire up brightness up | `F2` | `quickshell ipc call display brighter 5` |
| E7 | Wire up media play/pause | `F3` | `quickshell ipc call music togglePlay` |
| E8 | Wire up media previous | `F4` | `quickshell ipc call music previous` |
| E9 | Wire up media next | `F5` | `quickshell ipc call music next` |
| E10 | Wire up screenshot tool | *(new or existing)* | `quickshell ipc call screenshot toggle` |
| E11 | Wire up launchpad | *(new binding)* | `quickshell ipc call launchpad toggle` |
| E12 | Wire up AI assistant (Sigrid) | *(new binding)* | `quickshell ipc call sigrid toggle` |
| E13 | Wire up widget edit mode | *(new binding)* | `quickshell ipc call widgets editMode` |
| E14 | Wire up wallpaper change | *(script/binding)* | `quickshell ipc call wallpaper change <path>` |

## eqsh Gaps (no IPC target exists in eqsh — need wrapper scripts or new IPC)

| # | Activity | Old DMS Command | Gap Reason |
|---|----------|----------------|------------|
| G1 | Volume mute | `dms ipc call audio mute` | eqsh has no audio IPC — OSD is passive listener only. Write wrapper script using `wpctl` or `pactl`, eqsh OSD auto-reacts |
| G2 | Volume down | `dms ipc call audio decrement 3` | Same — wrapper script with `wpctl set-volume @DEFAULT_AUDIO_SINK@ 3%-` |
| G3 | Volume up | `dms ipc call audio increment 3` | Same — wrapper script with `wpctl set-volume @DEFAULT_AUDIO_SINK@ 3%+` |
| G4 | Clipboard manager | `dms ipc call clipboard toggle` | eqsh has no clipboard component. Keep using `cliphist` + external picker (rofi/fzf) |
| G5 | Bar/panel toggle | `dms ipc call bar toggle` | eqsh bar uses EdgeTrigger autohide, no toggle IPC. Accept edge-trigger behavior or add IPC to eqsh |
| G6 | Power menu | `dms ipc call powermenu toggle` | eqsh has no power menu IPC. Write standalone script using rofi + `systemctl` + `niri msg action quit` |
| G7 | Pomodoro timer | `$scripts/pomodoro menu` | Generic script — but bar integration was via waybar. Decide how pomodoro displays in eqsh (popup IPC?) |

## Script Migration — Copy As-Is

Create `~/.config/niri/scripts/` and copy these 12 generic scripts from `scroll/scripts/`:

| # | Script | Purpose |
|---|--------|---------|
| S1 | `executable_battery` | Battery status rofi menu |
| S2 | `executable_brightness-control` | Brightness +/- with notify-send |
| S3 | `executable_colorpicker` | grim+slurp color picker (backup to niri built-in) |
| S4 | `executable_screenshot` | grim+slurp screenshot |
| S5 | `executable_swappy` | Screenshot + annotation |
| S6 | `executable_volume` | amixer volume control |
| S7 | `executable_pomo` | Pomodoro core timer |
| S8 | `executable_pomodoro` | Pomodoro menu + rofi |
| S9 | `executable_fzf-nmcli` | FZF network manager |
| S10 | `executable_fzf-shortcuts` | FZF shortcut reference viewer |
| S11 | `executable_wifi-menu.sh` | iwmenu WiFi selector |
| S12 | `executable_music-download` | yt-dlp music downloader |

## Script Migration — Rewrite for Niri IPC

Replace `scrollmsg`/`swaymsg` with `niri msg` equivalents:

| # | Script | What Changes |
|---|--------|-------------|
| R1 | `powermenu` | Replace `swaymsg exit` with `niri msg action quit` for logout |
| R2 | `record` | Replace `swaymsg -t get_outputs \| jq` with `niri msg outputs` for focused output |
| R3 | `workspace-indicator` | Replace `swaymsg -t get_tree \| jq` with `niri msg workspaces` |
| R4 | `gestures` | Replace `scrollmsg` cursor button presses with `niri msg action` or `wtype` |
| R5 | `fzf-tree-switcher` | Replace `swaymsg -t get_tree` with `niri msg windows` for window list |
| R6 | `host-terminal` | Replace `scrollmsg` tree queries with `niri msg windows` + `niri msg action` |
| R7 | `nvim-terminal.sh` + `nvim-terminal.lua` | Full rewrite: shell script using `niri msg` to find nvim window and spawn adjacent terminal |
| R8 | `lisgd-start` | Rebind touchscreen gestures from `scrollmsg` to `niri msg action` commands |

## Script Migration — Drop or Decide

| # | Script | Decision Needed |
|---|--------|----------------|
| D1 | `smart-marks.lua` | Dropped with marks system. Decide if marks are wanted via niri IPC alternative |
| D2 | `scroll-mark-toggle` | Dropped with marks system |
| D3 | `scroll-mark-switch` | Dropped with marks system |
| D4 | `scroll-mark-remove` | Dropped with marks system |
| D5 | `sway-tree-switcher` | Redundant with `fzf-tree-switcher` — pick one to port |
| D6 | `scratchpad-indicator` | Niri has no scratchpad concept — drop or find alternative |

## New Wrapper Scripts to Write

| # | Script | Purpose | Implementation |
|---|--------|---------|----------------|
| W1 | `volume-up` | Volume increment + eqsh OSD | `wpctl set-volume @DEFAULT_AUDIO_SINK@ 3%+` (OSD auto-reacts) |
| W2 | `volume-down` | Volume decrement + eqsh OSD | `wpctl set-volume @DEFAULT_AUDIO_SINK@ 3%-` |
| W3 | `volume-mute` | Volume mute toggle + eqsh OSD | `wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle` |
| W4 | `clipboard` | Clipboard picker | `cliphist list \| rofi -dmenu \| cliphist decode \| wl-copy` (or fzf variant) |
| W5 | `powermenu` (new) | Power menu for niri | rofi menu: suspend/reboot/shutdown, logout via `niri msg action quit` |

## eqsh Configuration

| # | Activity | Detail |
|---|----------|--------|
| C1 | Review eqsh `Default.qml` config defaults | Adjust for personal preferences (dark mode, accent colors, notch behavior, etc.) |
| C2 | Configure eqsh paths in `Directories.qml` | Verify `~/.config/aureli/` runtime dir works, adjust if needed |
| C3 | Add eqsh to niri startup | Add `spawn-at-startup "quickshell"` (or `equora run`) to `niri/startup.kdl` |
| C4 | Remove DMS from startup | Remove `exec dms run` equivalent if it existed in niri startup |
| C5 | Review eqsh bar vs niri hotkey-overlay interaction | Ensure eqsh panel doesn't conflict with niri's built-in overlay |
| C6 | Review eqsh screenshot vs niri built-in screenshot | Decide which to use — eqsh has `screenshot toggle` IPC, niri has `screenshot` action |
| C7 | Configure eqsh wallpaper path | Set wallpaper or disable eqsh wallpaper if using separate tool |
| C8 | Configure eqsh gsettings vs niri gsettings | Both configs set gtk-theme/cursor — deduplicate in one place |

## Features: Lost from Scroll (no equivalent)

- Workspace scaling (`scale_workspace` zoom in/out)
- Layout transpose (swap horizontal/vertical)
- Jump labels (vim-like window jump overlay)
- set_mode (layout mode switching)
- Reverse cycle sizing (`cycle_size prev`)
- 4-finger native gesture scrolling
- Smart marks (replaced by numbered workspaces)

## Features: Gained in Niri (new capabilities)

- Column tabbed display (`Mod+W`)
- Overview mode (`Mod+Ctrl+O`)
- Center column (`Mod+Ctrl+C`)
- Maximize to edges (`Mod+Ctrl+F`)
- Reset window height (`Mod+Ctrl+R`)
- Built-in screenshots (Print, Ctrl+Print, Alt+Print)
- Built-in color picker via `niri msg`
- Hotkey overlay (`Mod+Slash`)
- Power off monitors (`Mod+Shift+P`)
- Keyboard shortcut inhibit (`Mod+Escape`)
- Consume/expel windows between columns (`Mod+Alt+H/L`)

## Features: Gained from eqsh (new capabilities over DMS)

- Notch UI (macOS-style dynamic island)
- Launchpad (app grid)
- Sigrid AI assistant
- Desktop widgets system
- Lockscreen
- Wallpaper engine
- Popup notification system with IPC
- Modal dialog system with IPC
- Control center with Bluetooth/WiFi sub-panels
- Polkit authentication agent
- Screen corner triggers
