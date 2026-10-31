# 23 — Other GPUI shells: features and code shapes to copy (gpui-shell, herdr-bar, herdr-gpui)

Reader note for the overnight gpuix-shell build, written 2026-10-21 ~00:30 CEST by one
Fable reader; **revised ~01:40 CEST by a second Fable reader pass** that re-read the three
clones, re-verified every `path:line` pointer below against the files on disk, corrected
§3.3/§3.5/§6 (herdr-gpui hello/welcome structs, layout-mode names) and added the facts marked
"(2nd pass)". Scope: mine three GPUI/herdr projects in `/home/tom/Downloads/` for
features, D-Bus targets, herdr protocol facts and ranking rules that a TypeScript
`@gpuix/react` shell can copy. Read-only; nothing in the three clones was changed. Other
wave-1 docs already cite this file as `[w1-23 …]` (`KEYS.md`, `SCOPE.md`); every fact they
cite is kept where it was.

Labels: **MEASURED** = read in the source or observed on this box tonight; **REPORTED** =
the project's own README/docs claim, not exercised; **INFERRED** = my reading of what it
implies for our shell. Every file pointer is `path:line` as of the clone on disk.

---

## 1. What these sources are

| Source | Where | Identity (MEASURED) | Size | Relevance to us |
|---|---|---|---|---|
| **gpui-shell** | `/home/tom/Downloads/gpui-shell` | `github.com/andre-brandao/gpui-shell`, HEAD `110f0f7` (merge of PR #38), `crates/app/Cargo.toml` version 0.1.0; Rust 2024, `gpui` from zed `main` with `wayland` feature, `zbus 5.18`, `libpulse-binding 2.30`, `pipewire 0.10`, `udev 0.9`, `sysinfo 0.39`, `hyprland 0.4.0-beta.3`, `niri-ipc 26.4` (`Cargo.toml:8-27`, `crates/services/Cargo.toml:20-27`) | 46,545 lines of Rust across `crates/{app,services,ui,assets,story}` | The closest thing to our target: a layer-shell **bar + launcher + control center + OSD + notification daemon + tray + dock** with every D-Bus integration we need. Compositors: Hyprland, Niri, Mango — **not Sway** (`crates/services/src/compositor/mod.rs:44-45`). |
| **herdr-bar** | `/home/tom/Downloads/herdr-bar` | `github.com/jeffarese/herdr-bar`, HEAD `0d27f49`, `herdr-plugin.toml` version 0.9.1, `min_herdr_version = "0.9.0"` | 27,726 lines (Rust + tests; `src/` ~12k) | A herdr **popup-pane plugin** (TUI, not GPUI): Cmd+K fuzzy switcher over agents/tabs/workspaces, with the exact **status glyphs Tom uses** and an MRU/attention ranking worth copying for our Mod+i switcher and launcher. Shows how to read herdr state over the JSON API socket. |
| **herdr-gpui** | `/home/tom/Downloads/herdr-gpui` | `github.com/penso/herdr-gpui`, HEAD `c73d8192` (merge of PR #612); "GPUI 0.3.6 (`gpui-pre`) client" (`crates/herdr-gpui/README.md:3`) | 394,027 lines of Rust; crates `herdr-protocol`, `herdr-client`, `herdr-gpui`, `herdr-gpui-launcher`, `test-support` | A full native herdr desktop client (paints terminal cells). We do not copy the app; we copy its **wire facts** (binary client socket, snapshot record types, agent status enum, semantic notifications), its **sidebar status-dot values**, and its `herdr-gpui` control-socket CLI shape as a precedent for our `gpuix-shell` CLI. |

Local herdr facts on this box (MEASURED tonight, read-only): `herdr 0.9.3` at
`/nix/store/nrqha04nxiw268yyrnnm570fs4apc20d-herdr-0.9.3/bin/herdr` (also `HERDR_BIN_PATH`);
environment of this session carries `HERDR_SOCKET_PATH`, `HERDR_WORKSPACE_ID=wHW`,
`HERDR_TAB_ID=wHW:t1`, `HERDR_PANE_ID=wHW:p1`, `HERDR_ENV=1`; two sockets exist:
`~/.config/herdr/herdr.sock` (JSON API) and `~/.config/herdr/herdr-client.sock` (binary
client protocol). ID shapes are `<workspace>`, `<workspace>:t<n>`, `<workspace>:p<n>`.

Clone dates (MEASURED `git log -1`, 2nd pass): gpui-shell HEAD `110f0f7` is dated
2026-08-03 (so its gpui pin is two months older than herdr-gpui's `gpui-pre` 0.3.6);
herdr-bar HEAD `0d27f49` 2026-10-17 ("Lock files on Windows through a handle that can read",
tag `v0.9.1`); herdr-gpui HEAD `c73d8192` 2026-10-17, `git describe` = `v20261016.1-59-gc73d8192`.
herdr-bar 0.9.0/0.9.1 (`CHANGELOG.md:1-25`) is the Rust port of a Python plugin: its tests
replay ~19,000 recorded Python answers (`tests/data/fuzz-corpus.jsonl`) and drive the binary on
a pty against a fake herdr (`tests/parity/*`), which is why its pure functions are safe to port
line-for-line (§5).

---

## 2. Verbatim Tom rulings relevant to this note (dates from BRIEF.md)

Tom did not name herdr-bar or herdr-gpui himself; the orchestrator's BRIEF table lists
all three repos as "Other GPUI shells to mine for features" (`BRIEF.md:88`). The rulings
that govern what we take from them:

- 2026-10-20 ~22:50 CEST: "the crux of it is that we write scripts and functionality that is
  either a bespoke swaywm shortcut ; or a mod+d menu (vicinae remplacement) that presents a
  given functionality. notify-send remplacement to mako ; a left bar with workspace switcher
  that remplaces waybar" (`BRIEF.md:13-15`).
- 2026-10-20 ~22:50 CEST: "there is a lot of herdr-web-ui centricity here especially on the
  left sidebar idea ; but having a comprehensive list of all the options is important."
  (`BRIEF.md:16-17`).
- 2026-10-20 ~23:05 CEST: "make sure that the work you do will set the foundation for my
  subsequent work on achieving the world's most complete linux desktop shell without using
  quickshell. gpuix as the frontend all the way is desired. the rest, including scripts and
  other functionality, you can use what comes instinctively to you. for wifi menu, or
  bluetooth pairing menu; etc." (`BRIEF.md:21-24`).
- 2026-10-20 ~23:05 CEST: "lately i saw 'tacit' dotfiles ... more importantly however is the
  aesthetic that was achieved with this tacit os quickshell config: this is what i would like
  to remain close to" (`BRIEF.md:25-28`).
- Standing (MAP.md via BRIEF): "functionality pull from quickshell NOT visuals"; "flat and
  opaque, hairlines not shadows, no blur, no frost, wallpaper is #000000 solid"
  (`BRIEF.md:42-44`). → gpui-shell's `ElevationIndex` shadows are **not** copied (§4).
- Standing: Sway is the only compositor (`BRIEF.md:34-35`). → gpui-shell's compositor layer
  is a shape to copy, not code to port (§3.1, §6).
- Standing: herdr status glyphs "blocked ◉ / working ◐ / done ● / idle ✓ / unknown ○"
  (`BRIEF.md:40`). MEASURED: herdr-bar uses exactly this set (`src/tab_status.rs:33-34`,
  `src/theme.rs:58-66`); herdr-gpui's "symbols" indicator style uses a different set (§3.3).
- 2026-10-20 23:20 CEST addendum: "do not block further overnight work on 'waiting on
  tom's input'" (`BRIEF.md:29`). Assumptions below are marked INFERRED.

Older Tom words that bear on these three sources (REPORTED, quoted from the day map and the
design-handoff digs; 2nd pass):

- MEASURED 2nd pass: a grep of Tom's user turns in every Claude transcript listed in
  `BRIEF.md:91` and the Codex rollouts of 10-13/10-16/10-20 finds **no** turn where Tom typed
  "gpui-shell", "herdr-bar" or "herdr-gpui"; every hit is an agent summary or a teammate
  message. The three repos entered the plan through agent surveys (10-07 eco-survey; 10-17
  design-handoff digs), not through a Tom ruling.
- TOM 2026-10-13 23:19/23:21Z (via `/home/tom/tuesday-oct20/MAP.md:95`): "gpuix is a cool
  project but we can use it as stylistic inspiration if it's not adapted"; "'supplies
  another renderer' is fine for something that' react plus generic compositor
  functionlaity". → Rust GPUI code is a shape source only; nothing here is ported as Rust.
- TOM 2026-10-14 00:16 CEST (`MAP.md:95`): "whatever you just opened: i love it. this is good
  enough to also become a functional remplacement to waybar, vicinae and mako notifications."
  → the look is the Claude/Primer page, so gpui-shell's Zed theme and herdr-gpui's Catppuccin
  dots are measured for shape only (§4).
- TOM 2026-10-20T10:53:53Z (`MAP.md:99`): "i typically hae a one ot one mapping, with a limit
  of 9 open workspaces at a time; this helps with my mental overload" → the rail is nine herdr
  slots, which is why gpui-shell's generic workspace pills are "replace", not "keep" (§3.1).
- TOM on Vicinae (REPORTED `/home/tom/today/2026-10-17-frank/design-handoff/dig/05-gpuix-shell-state.md:47`):
  "i would like to fully supersede this." → the launcher view trait + prefix router (§3.1)
  and herdr-bar's ranking (§3.6) are the replacement's spine.
- Day map on herdr-bar (REPORTED `MAP.md:97`): "herdr-bar (jeffarese; Rust v0.9.1, 51
  commits, not Python 0.8.0; critic 1) is the Ctrl+K and auto-title inspiration". The
  design-handoff dig already took two rules from it: "Ordering with no query: recent first,
  then attention (blocked, done, working), and 'The tab you are currently in is never first.'"
  and "'**Never animates.**' and '**No colors.**' in herdr's own tab labels"
  (`dig/05-gpuix-shell-state.md:123-124`, citing `herdr-bar/README.md:321-323`, `:214-218`).
- Day map on gpui-shell / herdr-gpui (REPORTED `dig/05-gpuix-shell-state.md:36`):
  "**gpui-shell** (andre-brandao): six layer-shell surface kinds, no Sway backend, no licence:
  'reference only'"; "**herdr-gpui**: a terminal-cell head, 'zero layer-shell or Sway hits'".
  Both verdicts hold after tonight's read (§6).

---

## 3. Feature / behaviour inventory

Columns: **keep** = adopt the behaviour as-is in gpuix-shell; **replace** = we have or plan a
different mechanism; **new** = not yet in our plan, worth adding; **skip** = out of scope.
"Where it lives today" is the source file in the mined project.

### 3.1 gpui-shell (andre-brandao) — surfaces, services, config, IPC

#### Surfaces and windows

| Feature | What exactly | Where it lives today | Keep/replace/new | Notes for gpuix-shell |
|---|---|---|---|---|
| Bar as layer-shell window per output | `Layer::Top`, namespace `"bar"`, `exclusive_zone = bar.size`, `KeyboardInteractivity::None`; anchor `LEFT \| TOP \| BOTTOM` when `position="left"`; one window per display, re-opened on config reload | `crates/app/src/bar/view.rs:57-124` (window_options, init), `:145-179` (per display, reload) | keep (shape) | Matches our rail geometry decision (BRIEF §3.3: layer top, anchor left/top/bottom, exclusive 56). gpui-shell default `size = 32.0`, `position = "left"`, plus `padding = 14.0`, `show_border = true`, `widget_background = true`, `widget_border = true` (`bar/config.rs:45-66`, `:84-106`; 2nd pass). The bar surface draws its hairline on the screen-facing edge only (`border_r_1` for a left bar, `patterns/bar.rs:100-112`) — exactly Tom's "hairlines not shadows". |
| Output identity and logical size (2nd pass) | gpui's `Window::display()` and display bounds are unreliable for layer-shell windows, so the bar records the `DisplayId` it was opened with and matches it to a compositor monitor by `Uuid::new_v5(NAMESPACE_DNS, output_name)` (gpui_linux derives `PlatformDisplay::uuid()` that way); logical size is taken from the compositor's monitor `width/scale`, because gpui only sees the integer `wl_output.scale` and a 1.5 screen reports two thirds of its size | `crates/app/src/state.rs:14-94`; `bar/view.rs:62-80`; `bar/modules/workspaces/mod.rs:46-66` | keep (rule) | Relevant because GPUIX's layer surface "cannot choose its output" (MAP.md 10-14). Our rail must read `swaymsg -t get_outputs` for the real logical size and output name, and never trust the renderer's display enumeration order (INFERRED application of the same lesson). |
| Bar sections start/center/end with named widgets | TOML lists of widget names; unknown names logged and ignored; aliases (`Systray`=`Tray`, `Settings`=`Info`=`ControlCenter`, `LauncherBtn`=`Launcher`, `Mpris`=`Media`=`Player`) | `crates/app/src/bar/modules/registry.rs:57-80`; docs `docs/src/content/docs/reference/bar.md:31-45` | keep (shape) | Our rail is fixed-purpose (herdr slots), but a `start/center/end` registry keyed by string is the right shape for `~/.config/theme/gpuix-shell.json` or a `rail.json`. |
| Workspaces widget | Pill per workspace; active = accent bg, has-windows = element bg, empty = none; click focuses; wheel scrolls ±1; label modes numbers/icons; per-monitor active id preferred over compositor-wide | `crates/app/src/bar/modules/workspaces/mod.rs:36-74` (focus/scroll), `:78-115` (label), `:117-180` (pill), `:181-240` (strip, per-monitor active at `:191-201`) | replace | Our rail shows **herdr workspaces 1..9 + status glyph**, not raw Sway workspaces; keep the per-output active-id rule and the wheel-scroll behaviour. |
| Active window title | Focused window title + app icon, `max_length = 64` | `bar/modules/active_window/*`; docs `bar.md:93-98` | skip | Tom: "no top bar on the Linux head"; title not needed on the rail. |
| Clock | strftime, separate vertical format `"%H\n%M\n%S"` | `bar/modules/clock/*`; docs `bar.md:51-56` | new (small) | Vertical rail clock as stacked HH/MM is a nice vertical-bar idiom. |
| Battery | icon + percentage from UPower display device | `bar/modules/battery/*`, icon ramp `crates/app/src/icons/mod.rs:56-70` | new | Rail footer item; see UPower table §3.4. |
| SysInfo | CPU/mem/temp from `sysinfo` crate, 2 s poll in a thread | `crates/services/src/sysinfo/mod.rs:201` | skip | Tom: performance/stats not the point; herdr-gpui has host CPU/mem already. |
| System tray | Implements `org.kde.StatusNotifierWatcher` host itself, registers items, reads `IconPixmap`/`IconName`, `Menu` via `com.canonical.dbusmenu` | `crates/services/src/tray/dbus.rs:30-240`, `tray/mod.rs:89-200` | new (later) | Needed for Tailscale/Nextcloud-style trays if any; see §3.4. Heavy; defer. |
| Keyboard layout | Current layout from compositor, optional flag emoji | `bar/modules/keyboard_layout/*` | skip | Single layout on Tom's machines (INFERRED). |
| Settings button → control center panel | Click opens a panel anchored next to the bar at click position | `bar/modules/settings/*`, `crates/app/src/panel.rs:66-108` | keep (shape) | Our `gpuix-shell controls` surface; anchor math at `panel.rs:110-190` is worth porting. |
| Panel system | One panel open at a time; `PanelConfig{width 320, height 400, anchor TOP \| RIGHT, margin 5}`; `toggle_panel`, `close_panel`, `is_panel_open` | `crates/app/src/panel.rs:17-35`, `:210-320` | keep (shape) | Since GPUIX = one window per process, "one panel at a time" becomes "one controls process, toggled by CLI". |
| Launcher window | Overlay layer, namespace `"launcher"`, anchor TOP, margins from config (top 100), `KeyboardInteractivity::Exclusive`; 600×450 | `crates/app/src/launcher/mod.rs:611-680` | keep | Ours: 700×580, top margin 108 (BRIEF §3.3). Same layer/anchor/keyboard. Toggle semantics (`:605-634`, 2nd pass): closed → open (with optional prefilled input); open + input given → **update the query, keep open**; open + no input → close. `ITEMS_PER_PAGE = 7` for PageUp/PageDown (`:33`). The window is re-created on every open (no hidden window kept around). |
| Launcher prefix routing | Longest matching prefix wins; unknown prefix char → Help view; no prefix → default view (Apps) | `crates/app/src/launcher/mod.rs:143-200` | keep | Vicinae-replacement shape: `@` apps (default), `$` shell, `!` web, `;ws` workspaces, `;wp` wallpaper, `~` theme, `;s` services, `?` help (`launcher/modules/*/config.rs`). Add ours: `>` herdr, `♫`/`;m` navidrome, `;c` clipboard (INFERRED). |
| Launcher view trait | `prefix() name() icon() description() is_default() show_in_help() update_matches() match_count() render_item() render_header/footer/content() handle_input() on_select()` | `crates/app/src/launcher/view.rs:60-150` | keep (shape) | Port as a TS interface `LauncherView`; it is exactly the plugin seam for navidrome/clipboard/herdr views. |
| Launcher keybindings | arrows + `ctrl-k/p` up, `ctrl-j/n` down, `ctrl-u/d` page, `ctrl-backspace` word delete, `ctrl-a` select all, `ctrl-b/w` word left/right, `ctrl-f/h/l` cursor | `crates/app/src/keybinds.rs:30-61`; docs `launcher.md:68-97` | keep | Same table for our launcher and switcher. |
| Apps view | XDG desktop files from `$XDG_DATA_HOME` + `$XDG_DATA_DIRS`; search = case-insensitive substring on name or description; launch via `sh -c` with `%`-codes stripped | `crates/services/src/applications/mod.rs:102-135` (search), `:38-66` (launch), `:187-200` (dirs) | replace | Substring only, **no frecency** — take herdr-bar's fuzzy + MRU instead (§3.2). |
| Shell view | `$ cmd` runs in preferred terminal, falls back to `x-terminal-emulator` | `launcher/modules/shell/mod.rs:204-275` | keep | Ours: kitty. |
| Web view | `! query` → provider list, `{query}` templates: duckduckgo (default), google, youtube, github, nixos packages, wikipedia, crates.io, reddit; opens with `xdg-open` | `launcher/modules/web/config.rs:19-80`, `web/mod.rs:269-310` | keep | Add `nixos options`, `noogle`, `hm options` (INFERRED). |
| Workspaces view | `;ws` lists compositor workspaces, Enter focuses | `launcher/modules/workspaces/mod.rs:118-140` | replace | Ours lists herdr workspaces → Sway workspace via `herdr-picker` logic. |
| Wallpaper view | `;wp` browses `~/Pictures/Wallpapers`, sets via `awww`, optional matugen | `launcher/modules/wallpaper/*`, `services/src/wallpaper/mod.rs:100-150` | skip | Wallpaper is `#000000` solid. |
| Theme view | `~` lists Base16 schemes cloned from `tinted-theming/schemes` via git; writes `theme.toml`; Stylix scheme detection | `services/src/themes.rs:85-260`, `launcher/modules/theme/mod.rs:114` | replace | Ours: three themes via `~/.local/bin/theme`; a `~` view that runs `theme noir \| claude-dark \| claude-light` is the whole feature. |
| Services view | `;s` shows every service's status (Active/Starting/Error/Stopped/Unavailable), retained memory, restart/stop, mode eager/lazy/off persisted to `state.toml` | `launcher/modules/services/mod.rs:7-20`, `:316-340`; `services/src/lifecycle.rs:22-160`; `app/src/config/state.rs:1-70` | new | A `;s` doctor view listing our daemons (rail, notifications, launcher…) with `systemctl --user` status is cheap and valuable for Tom's morning. |
| Help view | `?` lists every view's prefix + description + shortcut table | `launcher/modules/help/*` | keep | |
| Control center | 340 wide, 288 collapsed; quick toggles row (mic mute, Wi-Fi, Bluetooth; Wi-Fi/BT are "expandable modules" that open a section), sliders (volume with mute icon, brightness), expandable sections Wi-Fi / Bluetooth / Power, notifications panel | `crates/app/src/control_center/mod.rs:45-46` (consts), `:114-125` (toggle_section), `quick_toggles.rs:21-170`, `sliders.rs:12-150` | keep | Our `gpuix-shell controls`. |
| Wi-Fi section | APs sorted connected-first then by strength; row = signal icon (0–25/26–50/51–75/76+), SSID, saved-key icon (green if known), lock icon if secured; click: known or open → connect directly; secured unknown → inline password input row; `WifiPasswordState{ssid,input,connecting,error}` | `control_center/wifi.rs:18-55` (state), `:55-225` (section, sort at `:77-85`, click rule at `:205-215`), `:228-330` (row); icons `icons/mod.rs:24-31` | keep | This is the "wifi menu" Tom asked for. Add "forget network" (not present) (INFERRED). |
| Bluetooth section | Scan button (discovery auto-stops after 15 s), device rows with battery, actions Pair / Connect / Disconnect / Remove; device icon by kind | `control_center/bluetooth.rs:17-150`, `:264-360`; `services/src/bluetooth/mod.rs:72-85` | keep | "bluetooth pairing menu". **Gap:** no `org.bluez.Agent1`, so PIN/passkey pairing cannot be confirmed (§6). |
| Power section | Buttons sleep/reboot/poweroff run `sh -c <configured command>` (empty string disables); battery time-remaining string; power-profile icon | `control_center/power.rs:12-115`; config `docs/.../control-center.md:8-18` | keep | Our `gpuix-shell power` surface; add lock (`swaylock`) and logout (`swaymsg exit`) (INFERRED). |
| OSD | 280×56 pill (or 56×280 vertical), margin 24, overlay layer, namespace `"osd"`, auto-dismiss 2 s; triggered by audio sink volume/mute or brightness change observed on the services, not by the keybind | `crates/app/src/osd/mod.rs:29-32` (consts), `:133-160` (window), `:160-230` (show/close/dismiss), `:232-290` (listeners) | keep | Ours: bottom, margin 96. Copy the "observe the service, not the key" rule so `wpctl` from any source shows the OSD. Colour rule (`osd/mod.rs:99-111`, 2nd pass): track fill = status.error when muted, status.warning when level > 100, else accent; icon = status.error when muted else text. Re-show while visible only updates the view and restarts a generation-counted dismiss timer (`:160-227`), so a held volume key never flickers. Initial service values are swallowed so nothing flashes at startup (`:238-253`). |
| Notification daemon | Owns `org.freedesktop.Notifications` with `AllowReplacement`; if name already owned → service `Unavailable`; capabilities `actions, body, body-markup, persistence`; server info `("GPUi Shell","gpuishell","0.1.0","1.2")`; history cap 200; default timeout 5000 ms when `expire_timeout < 0`; urgency hint default 1; actions parsed as (key,label) pairs; `NotificationClosed` reason 1 expired / 2 dismissed; `ActionInvoked` signal; DND suppresses popups but keeps history; "local slots" (ConfigError, ThemeError) use ids counting down from `u32::MAX` so a re-fired shell error replaces its card | `crates/services/src/notification/mod.rs:25-29` (consts), `:69-96` (LocalSlot, commands), `:305-345` (name request), `:389-408` (capabilities/info), `:410-556` (Notify), `:557-585` (close/signals) | keep | Our `gpuix-shell notifications` daemon (mako replacement). The image-hint handling (`:441-467`: `image-path`/`image_path`, then `app_icon` path, then XDG icon lookup, then `desktop-entry`) is exactly what Chrome and herdr send. |
| Notification popups | Overlay window top-right, 360×320, stack limit 4, card 92 collapsed / 170 expanded; one popup window per target display | `crates/app/src/notification/config.rs:39-55`, `popup.rs:105-245` | keep | Ours: 390 wide, max 4 (BRIEF §3.3). Card anatomy (`card.rs:31-200`, `:225-242`, 2nd pass): 3 px urgency stripe on the left (urgency 2 → status.error, 0 → text_muted, else accent), 64×64 image slot (app icon 28 px, or image with a 24 px icon badge bottom-right), app name + `%H:%M` time in XSmall, summary Small / line-height 18, body XSmall / 16, action chips (px 8, py 2, XSmall); popup card hover = element_hover bg + accent border, close glyph 8 px from the top-right (`popup.rs:171-205`). Dispatching a command spawns a one-off tokio runtime per click (`notification/mod.rs:15-25`) — a shape to avoid; ours is one event loop. |
| Notification center panel | 420×540; DND toggle, "Clear", list with mark-read | `notification/panel.rs:37-155`, `config.rs:23-24` | keep | |
| Dock | Pinned + running apps, positions, `primaryonly`/`all`, visibility `always-visible`/`intelligent-hide`/`dodge-windows`, hover `none/lift/magnify/glow/magnify-lift`, icon 40, reveal/hide 750 ms, context menu 160 wide rows 40 | `crates/app/src/dock/mod.rs:23-35`, `config.rs`; docs `configuration.md:48-66` | skip | No dock in Tom's model (rail is the dock). |
| Single instance / IPC | Unix socket `$XDG_RUNTIME_DIR/gpuishell.sock` (fallback `/tmp/gpuishell-<uid>.sock`); second launch connects, sends `"ipc:launcher:<input>"`, exits; primary decodes `LauncherToggle{input}` | `crates/app/src/ipc/service.rs:81-140`, `:248-260`; `ipc/messages.rs:6-51` | replace | Ours is a multi-verb socket at `$XDG_RUNTIME_DIR/gpuix-shell/shell.sock` (BRIEF §3.2). Keep their stale-socket removal (`service.rs:105-110`) and the read timeout on accepted connections (`:193-220`). |
| CLI | `gpuishell [--input TEXT] [--validate]`; `--validate` parses config and prints where parsing stopped | `crates/app/src/args.rs:11-36`; `config/mod.rs:211-236` | keep | Add `gpuix-shell validate` to our CLI. |
| Config files | `~/.config/gpuishell/config.toml` (hand-written, never written by app), `theme.toml` (written by theme view), `state.toml` (app-persisted overrides: dock pins, service modes); inotify hot reload with debounce; a file that stops parsing keeps the last good value and posts a sticky local notification naming the file | `AGENTS.md:46-55`; `crates/app/src/config/mod.rs:60-130`, `:237-276`; `config/state.rs:1-30`; `services/src/watcher.rs:28-70` | keep (rule) | Rule to copy verbatim: **config is read-only to the app; app-written state is a separate file; bad config never loses the file.** Our theme fragment is Nix-rendered so it's read-only by construction. |
| Service lifecycle | `ManagedService` with `Lifecycle{status, generation}`; `start()` hands a `RunToken`; listeners loop on `token.alive()`; modes `eager/lazy/off` from `[services]`; lazy starts on first access; status enum Active/Initializing/Error(msg)/Stopped/Unavailable | `crates/services/src/lifecycle.rs:1-20`, `:22-160`; `status.rs:8-45` | keep (shape) | In TS: each service = `{ status, subscribe(), get(), dispatch(cmd), start(), stop() }` with a generation counter; no need for the lazy mode. |
| Shared bus connections | One system + one session zbus connection shared by all services | `crates/services/src/bus.rs:1-25` | keep | dbus-next: one `systemBus()` and one `sessionBus()` per process. |
| Compositor abstraction | `CompositorState{workspaces, monitors, active_workspace_id, active_window, windows, keyboard_layout, submap}`; `CompositorCommand{FocusWorkspace, FocusSpecialWorkspace, FocusMonitor, ToggleSpecialWorkspace, ScrollWorkspace, NextKeyboardLayout, FocusWindow, Custom}`; backend detected at runtime | `crates/services/src/compositor/types.rs:1-185`; `mod.rs:32-110`, `:168` | replace | We have one backend (Sway i3-ipc). Keep the state struct shape; `Workspace{id,index,name,monitor,windows,is_special}` maps 1:1 onto `swaymsg -t get_workspaces` fields (`num,name,output,focused,visible,urgent` — INFERRED mapping). |
| Privacy indicators | PipeWire registry listener: nodes with `media.class` `Stream/Input/Video` (screenshare) or `Stream/Input/Audio` (mic); webcam via inotify on `/dev/video*` (`OPEN`, `CLOSE_*`, `ATTRIB`) | `crates/services/src/privacy/mod.rs:119-230` | new (later) | A rail dot when mic/screen is live is cheap if we shell out to `pw-dump`/`wpctl status` (INFERRED) rather than binding libpipewire. |
| Icons as config values | Built-in name or a path (`/`, `~`, `./` prefix); SVG tinted by theme, PNG/JPG as-is; a bad value warns and falls back, never invalidates config | docs `bar.md:112-125` | keep (rule) | Same leniency rule for our JSON theme/rail config. |
| Story crate | A component gallery (`cargo run -p story`) with a story per component and per shell pattern | `crates/story/src/stories/*.rs` (56 stories) | new | A `gpuix-shell gallery` window that renders every surface's components under the three themes is the right smoke test for the design kit (U-01..U-19). |
| Nix build precedent (2nd pass) | crane build; `buildInputs = openssl fontconfig libxkbcommon xorg.libxcb xorg.libX11 wayland vulkan-loader freetype libpulseaudio pipewire systemd`; `NIX_LDFLAGS = -rpath ${vulkan-loader}/lib:${wayland}/lib`; `dontPatchELF = true`; `matugen` as a native build input; bindgen scratch-dir workaround for `pipewire-sys` | `nix/build.nix:11-31`, `:64-118`, `:122-142`; `nix/shell.nix` | keep (list) | The same runtime libraries our `pkgs/gpuix-shell/default.nix` wrapper must expose on `LD_LIBRARY_PATH` for `@gpuix/native` (BRIEF §3.9 and the measured rail-probe recipe: libxkbcommon, wayland, vulkan-loader, fontconfig, freetype, libglvnd, libx11, libxcb, openssl). libpulseaudio/pipewire/systemd are only needed if we ever bind them natively; we shell out instead. |

#### gpui-shell's `ui` crate (component inventory, for parity planning)

`crates/ui/src/components/`: accordion, avatar, banner, breadcrumb, button{button, button_like, button_link, copy_button, icon_button, split_button, toggle_button}, callout, checkbox, decorated_icon, description_list, disclosure, divider, dropdown_menu, gradient_fade, group, hover_card, icon, indicator, input{buffer,line}, keybinding, keybinding_hint, label{headline, highlighted_label, label}, list, menu, modal, navigable, overlay, pagination, popover, progress, radio, scrollbar, scroll_metrics, sheet, skeleton, slider, spinner, squircle, stack, stepper, switch, tab, text_field, tooltip, tree_view_item, variable_list, virtual_list. Patterns: `patterns/{bar,launcher,osd,surface}.rs`. (MEASURED file list.) This overlaps heavily with OpenUI's default component library; use it as a checklist when the OpenUI → GPUIX adapter is extended (BRIEF §5 addendum).

### 3.2 herdr-bar (jeffarese) — switcher behaviour, ranking, herdr reading

| Feature | What exactly | Where it lives today | Keep/replace/new | Notes |
|---|---|---|---|---|
| Row model | One row per **agent**, plus one per tab **without** an agent, plus one per workspace once there is more than one; `%` filter switches to one row per **named pane** | `src/items.rs:1-6`, `:334-500` (build_items), `:503-570` (pane rows) | keep | Our Mod+i switcher: one row per herdr workspace (= Sway workspace 1..9) is the top level; agents inside as rows under `@`. |
| Row text | Tab label first (status prefix stripped), agent summary dimmer after; summary dropped when it repeats the title/cwd/workspace; narrow rows drop the summary; title fallback chain `label → summary → basename(cwd) → "agent"` | `src/items.rs:181-218`, `:429-440`; README `Using it` "What a row says" | keep | |
| Status vocabulary | `agent_status` ∈ `blocked, working, done, idle, unknown`; empty → `"none"` | `src/items.rs:191-197`; `src/tab_status.rs:33-34` | keep | Same five as BRIEF. |
| Status glyphs | `◉` blocked, `◐` working, `●` done, `✓` idle, `○` unknown; **static, never animated** (spinner glyphs retired at 0.7.0, `RETIRED_GLYPHS = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"` still stripped at `tab_status.rs:37`); the popup's own `status_glyph` adds `·` for `none` (no agent) | `src/tab_status.rs:33-37`; `src/theme.rs:58-66` (`README.md:201-236` "Live status in the tab bar") | keep | Exactly Tom's set. Rule to copy: a status change redraws only the row that changed, never on a timer. |
| Status ranking | `status_order`: blocked 0, done 1, working 2, idle 3, unknown/other 4, `none` 5 (2nd pass: full table) | `src/items.rs:20-28`, test `:700-705` | keep | "Needs you first, then finished, then busy, then idle; tabs with no agent last." |
| Plugin manifest and env (2nd pass) | `herdr-plugin.toml`: `[[panes]] id="bar" placement="popup" width="74%" height="62%" command=["bin/herdr-bar"]`; `[[actions]] open` = `herdr plugin pane open --plugin herdr-bar --entrypoint bar --placement popup`; `[[startup]]` and `[[events]] on="pane.agent_detected"` both run `--start-titles`. Env herdr injects: `HERDR_SOCKET_PATH`, `HERDR_BIN_PATH`, `HERDR_PLUGIN_ROOT`, `HERDR_PLUGIN_CONFIG_DIR` (→ `config.json`), `HERDR_PLUGIN_STATE_DIR` (→ `recent.json`, `tab-status.json`, `title-servers/<socket>/…`) | `herdr-plugin.toml:1-80`; `src/config.rs:93-99`; `src/cli.rs:41-51`; `src/title_watcher.rs` (grep `HERDR_`) | keep (facts) | Our switcher is a layer-shell overlay, not a herdr popup pane, but the state-dir split (config read-only, `recent.json` written) is the same rule as gpui-shell's config/state split. A bind like `[[keys.command]] key="prefix+k" type="plugin_action" command="herdr-bar.open"` is how herdr launches it (`README.md:52-58`). |
| Config keys and defaults (2nd pass) | `preview` `"auto"` (on when inner width ≥ 92 cols; forced true/false needs ≥ 60), `mouse` true, `agent_icons` `"auto" \| "font" \| "none"`, `refresh_ms` 900 (floor 200), `workspaces` `"auto"` (rows only when > 1 workspace), `selection_background` `"auto"`, `claude_config_dirs []`, `tab_renaming_plugins []`, `auto_titles` true, `lowercase_titles` false, `tab_status` false, `running_time` true, `colors {}`; a broken file falls back to defaults | `src/config.rs:59-133`; `README.md:331-380` | keep (shape) | The `refresh_ms` floor and the "preview only when wide enough" rule are worth copying for the switcher's preview column. |
| Resting order (no query) | recents by MRU rank → **current row inserted at index max(1, recents)** ("never first", alt-tab semantics) → rest by `(is_workspace, status_rank, workspace_label, tab_number, title)` | `src/app.rs:380-417` | keep | Port verbatim for the switcher and for the launcher's empty-query list. |
| Query order | `(-score, mru_rank or 999, status_rank, title_len)`; matches in the title get `TITLE_BONUS = 40` | `src/app.rs:46`, `:101-125`, `:354-378` | keep | |
| Fuzzy scoring | fzf-like subsequence DP: `SCORE_MATCH 16`, `BONUS_BOUNDARY 16`, `BONUS_CAMEL 12`, `BONUS_CONSECUTIVE 16`, first-char bonus ×2, `PENALTY_GAP_START -3`, `PENALTY_GAP_EXTENSION -1`; space-separated terms are AND-ed; quoted phrases kept; positions returned for highlighting | `src/fuzzy.rs:1-20`, `:36-66` (split_query), `:171-275` (match_prepared) | keep | ~275 lines, pure; port to TS as `fuzzy.ts` with the same constants and a golden test from `tests/data/fuzz-corpus.jsonl`. |
| MRU store | `recent.json` in plugin state dir, `MAX_ENTRIES = 120`, key+title, `touch()` on every jump, atomic write via temp+rename | `src/mru.rs:1-30`, `:60-120` | keep | Ours: `$XDG_STATE_HOME/gpuix-shell/recent.json`. Same for app launches and clipboard picks. |
| Filters on empty query | `@` agents, `%` panes, `$` plain tabs, `!` rows that need you; `tab`/`shift+tab` cycle | README `Using it` table | keep | |
| Keys | type/`↑↓`/`ctrl+p n k j` move; Enter jump; `esc ctrl+c ctrl+g` leave; `backspace` on empty clears filter then arms close; `delete` arms close; `ctrl+u/w/d`; `ctrl+o` preview; `ctrl+r` rename; `pgup/pgdn`; wheel/click | README `Using it` table | keep | Two-step destructive confirm ("enter or y does it, any other key calls it off, including the delete keys themselves, so a held key that repeats can never answer its own question") is a rule worth copying for workspace close. |
| Running time | Per row, from `pane.process_info` + `ps -o etime`, read once then ticked locally; `47s`, `12m`, `2h04m`, `4d3h` | `src/age.rs:187-205` (format), `:84-180` (batch etime) | new | Cheap "how long has this agent been running" column in the switcher. |
| Live refresh | Re-reads `session.snapshot` every `refresh_ms = 900` while open; byte-compare to skip repaint | `src/client.rs:259-285` (snapshot_since); README Configuring | keep | Our rail polls `herdr api snapshot`; same compare-bytes trick. |
| Preview | Right column tails selected pane via `pane.read` | `src/client.rs:287-300` | new (later) | A switcher preview of the agent's last lines is doable with `herdr pane read`. |
| Auto titles | Watcher renames unnamed Claude/Codex tabs from the agent task title, every 2 s; yields tabs the user renamed; Claude transcript fallback | `src/title_watcher.rs`, `src/auto_title.rs`; README `Auto title` | skip | Tab naming lives in herdr/kitty, not the shell. |
| Tab status prefix | `<logo>  <glyph> name` composed/stripped; most urgent agent leads a multi-agent tab | `src/tab_status.rs:77-104` | keep (rule) | "Most urgent of several agents" rule = `min(rank)` → use for the per-workspace glyph on the rail. |
| Event wake-up | One `events.subscribe` stream for `pane.agent_detected` + `pane.agent_status_changed{pane_id}` per known agent pane; reconnect backoff to 30 s | `src/tab_status.rs:483-500`, `src/client.rs:503-560`; README `How it works` | keep | Lets the rail update instantly instead of polling. |
| Colours | ANSI-first; `muted` derived from terminal bg; agent brand colours | `src/theme.rs:38-56` | partial | Take the **agent brand hexes** (§4); status colours are ours (noir/claude). |

### 3.3 herdr-gpui (penso) — protocol facts and status presentation

| Feature | What exactly | Where it lives today | Keep/replace/new | Notes |
|---|---|---|---|---|
| Daemon discovery | `HERDR_SOCKET_PATH` → sibling `<stem>-client.sock`; else `HERDR_CLIENT_SOCKET_PATH`; else `<config_root>/herdr[-dev]/[sessions/<name>/]herdr-client.sock` with `<name>` from `HERDR_SESSION` or `"default"`; config root = `$XDG_CONFIG_HOME` or `~/.config` | `crates/herdr-client/src/discovery.rs:49-63`, `:155-173`, `:199-262` | keep (facts) | MEASURED locally: `~/.config/herdr/herdr.sock` and `herdr-client.sock` both exist. |
| Client wire framing | 4-byte **little-endian** length prefix + `bincode` (standard config) payload; `MAX_FRAME_SIZE = 2 MiB`, `MAX_GRAPHICS_FRAME_SIZE = 32 MiB` | `crates/herdr-client/src/frame.rs:95-140`; `crates/herdr-protocol/src/codec.rs:8-9`, `:12-55` | skip | INFERRED: our shell should **not** speak this (bincode positional encoding of Rust enums is brittle from TS). Use the JSON API socket that herdr-bar uses (§3.2) and `herdr api snapshot`. |
| JSON API tunnelled over the client socket | `ClientMessage::ClientShellEndpointRequest{boot_id, request}` where `request = {"id":"gpui-N","method","params"}`; replies as `ClientShellEndpointResponseChunk{boot_id, request_id, final_chunk, data}` | `crates/herdr-client/src/handle.rs:252-284`; `herdr-protocol/src/wire.rs:192-195`, `:686-691` | skip | Confirms the JSON API envelope is `{id, method, params}` (same as herdr-bar `src/client.rs:144-146`). |
| Method vocabulary the client sends | `client_shell.surface.set, command.invoke, integration.install, integration.list, layout.set_split_ratio, pane.clear, pane.close, pane.copy_motion, pane.copy_search, pane.edit_scrollback, pane.focus, pane.focus_direction, pane.input.set, pane.link.activate, pane.link.resolve, pane.rename, pane.resize, pane.scroll, pane.selection.read, pane.split, pane.swap, pane.zoom, product_announcement.dismiss, release_notes.dismiss, server.reload_config, tab.close, tab.create, tab.focus, tab.move, tab.rename, workspace.close, workspace.create, workspace.focus, workspace.move, workspace.move_block, workspace.rename, worktree.create, worktree.list, worktree.open, worktree.remove` | `crates/herdr-client/src/method.rs:34-80` (keep-sorted table) | keep (facts) | Our shell needs only `workspace.focus`, `workspace.create`, `workspace.close`, `tab.focus`, `pane.focus`, `agent.focus` (herdr-bar), plus `session.snapshot`, `events.subscribe`, `pane.read`. |
| Snapshot record types | `ClientShellSnapshot{boot_id, revision, focused_workspace_id, focused_tab_id, focused_pane_id, agent_order, workspaces, tabs, panes, agents, commands, tab_bar_right, …}`; `ClientShellWorkspace{workspace_id, active_tab_id, number, label, custom_label, branch, git_ahead_behind, tokens, worktree{key,label,is_linked_worktree}, focused, agent_status}`; `ClientShellTab{tab_id, workspace_id, number, label, custom_label, zoomed, focused, agent_status}`; `ClientShellPane{pane_id, workspace_id, tab_id, label, cwd, foreground_cwd, focused, right_click_passthrough}`; `ClientShellAgent{pane_id, workspace_id, tab_id, name, display_agent, agent, title, terminal_title, terminal_title_stripped, agent_status, state_change_seq, state_labels, tokens, focused}` | `crates/herdr-protocol/src/wire.rs:312-336`, `:374-436` | keep (facts) | Field names agree with what herdr-bar reads from the JSON `session.snapshot` (`items.rs:334-345`, `:420-440`, `:466-476`): **the JSON API snapshot has the same shape** (INFERRED from agreement; verify with `herdr api schema`). |
| Agent status enum | `AgentStatus{Idle, Working, Blocked, Done, Unknown}`, serde `snake_case`; unknown strings → `Unknown` | `wire.rs:286-310` | keep | |
| Status priority (sidebar "priority" sort) | Blocked 4 > Done 3 > Working 2 > Idle 1 > Unknown 0, then most recent `state_change_seq` | `crates/herdr-gpui/src/sidebar/agents.rs:45-54`, `:81-86` | keep | Same order as herdr-bar; herdr-bar adds MRU on top. |
| Status dots (dot style) | 8 px dot: working filled `#f9e2af`, blocked filled `#f38ba8`, done filled `#94e2d5`, idle **hollow** `#a6e3a1`, unknown 3 px `#6c7086` (Catppuccin Mocha, darkened on light chrome by `theme.ink`) | `sidebar/agents.rs:425-440`, `:322-330`; `sidebar/metrics.rs:14-16` | partial | Keep "idle = hollow, unknown = tiny" as the shape; colours are ours. Note herdr-gpui deliberately uses **daemon palette, not terminal ANSI** so the dot matches the TUI. |
| Status symbols (symbol style) | `◐` working, `×` blocked, `✓` done, `○` idle, `·` unknown | `sidebar/agents.rs:296-304` | skip | Differs from Tom's set; keep herdr-bar's. |
| Semantic notifications from the daemon | `ServerMessage::SemanticNotification{kind NeedsAttention \| Finished \| UpdateInstalled \| Custom, title, body, sound Done \| Request, agent, workspace_id, tab_id, pane_id, position TopLeft \| TopRight \| BottomLeft \| BottomRight}`; `Notify{kind Sound \| Toast \| SystemToast, message, body}` | `wire.rs:589-626`, `:641-645` | keep (facts) | herdr emits these over the client socket; with `[ui.toast] delivery = "system"` the TUI/GUI forward them to **freedesktop Notifications on the session D-Bus** (`README.md:2776-2800`) → our notification daemon receives them with no herdr-specific code. Keep the skip rule: "a notification for the active tab of the selected host is skipped only while the window is focused". |
| Linux notification behaviour | Uses freedesktop service; click needs a server supporting the `default` action; raising depends on compositor focus policy; not replaced/retracted | `README.md:2808-2813` | keep | So our daemon must advertise `actions` and handle `default` → focus the Sway workspace of the herdr workspace (via `herdr workspace focus` or `swaymsg`). |
| Sidebar geometry | `SIDEBAR_WIDTH = 232`, collapsed `RAIL_WIDTH = 48`, status dot 8, agent row rail stripe 3 | `sidebar/metrics.rs:7`, `sidebar/rail.rs:26`, `sidebar/agents.rs:279` | compare | Tom's herdr-web-ui rail is 220/30/12/2/8; ours 56 collapsed / 220 expanded (BRIEF §3.3). |
| Sidebar layouts | `LayoutMode::NAMES` = `normal, compact, comfortable, normal-rounded, compact-rounded, comfortable-rounded, superset, orca, minimal, devices` (density × style; corrected 2nd pass) | `crates/herdr-gpui/src/config/layout.rs:58-70` | skip | One look (noir) for us. |
| herdr's own sidebar row config (2nd pass) | herdr-gpui reads the **daemon's** `[ui.sidebar.agents]`/`[ui.sidebar.spaces]` when `[usage] inline = true`: `rows` of tokens, `rows_by_agent` keyed by agent id (`claude`, `codex`…), `row_gap`, per-token `fg`/`bold`/`dim` and `rules` (equals/contains/starts_with/gt/lt). Default rows: agents `[["state_icon","machine","workspace","tab"],["agent"]]`, spaces `[["state_icon","workspace"],["branch","git_status"]]`. Tokens: `state_icon, state_text, machine, workspace, tab, pane, agent, terminal_title, terminal_title_stripped, branch, git_status, $custom` (values plugins report via `pane.report_metadata` / `workspace.report_metadata`). Limits 16 rows × 16 tokens × 16 rules | `crates/herdr-gpui/src/config/sidebar.rs:5-8`, `:81-96`, `:306-420`; `crates/herdr-gpui/README.md:1600-1630` | keep (facts) | Our rail row for a herdr workspace should show the same tokens herdr's TUI sidebar shows (`state_icon workspace`, then `branch git_status`), read from the snapshot's `workspaces[].branch`/`tokens`, so the rail, the TUI and herdr-web-ui agree. `rows_by_agent` keys = the `agent` field values. |
| Status icon styles (2nd pass) | GUI-only `status_icons = solid \| tiles \| rail`: solid = filled discs for done/blocked, ring for idle, half disc for working; tiles = mark on a tinted tile; rail = outline marks plus a bar on the row's edge while working/done/blocked. Herdr's own `ui.status_indicators` accepts only `dots` or `symbols` | `crates/herdr-gpui/src/config/status_icons.rs:1-31` | compare | "A bar on the row's edge while an agent needs you" is a cheap rail affordance for blocked slots (INFERRED). |
| Attention badge rule (2nd pass) | macOS Dock badge = count of agents `Done` or `Blocked` across all hosts/windows, deduplicated, cleared at zero; follows daemon acknowledgement, never cleared locally by foregrounding; existing attention counted from the first snapshot | `crates/herdr-gpui/README.md:3207-3240`; `src/app_badge.rs` | new | The same count is the right rail-top badge (and the `herdr-attention` → Sway urgency rule on `feat/herdr-sway-context`). Linux has no dock badge, so the rail is where it lives. |
| Toast / sound config herdr already has (2nd pass) | Daemon `[ui.toast] delivery = "system"` routes to freedesktop; `[ui.toast.clipboard] position` ∈ `top-left, top-center, top-right, bottom-left, bottom-center (default), bottom-right`; `[ui.sound] enabled, path, done_path, request_path` and `[ui.sound.agents] <agent> = "off"`; GUI `[sound] volume` 0–100 (default 50); `[bell] attention = true, sound = false` | `src/config/notifications.rs:1-90`; `README.md:1591-1640`; `wire.rs:603-626` (`SemanticNotificationSound{Done, Request}`) | keep (facts) | Two sounds (done / request) keyed by agent is the whole vocabulary our notification daemon needs for herdr events; the `[ui.sound]` files are herdr's, not ours. |
| Client limits (2nd pass) | `COMMAND_CAPACITY 64`, `EVENT_CAPACITY 8`, `POLL 10 ms`, `TIMEOUT 10 s` (handshake / partial frame), `PING_TIMEOUT 10 s`, `LIVENESS_TIMEOUT 3 s`, `COMMAND_TIMEOUT 60 s`, `SLOW_REQUEST 250 ms` (logged), `MAX_RESPONSE_BYTES 8 MiB`; a quiet link is pinged after 5 s; no reconnect/replay, a changed `boot_id` disconnects | `crates/herdr-client/src/limits.rs:1-17`; `session.rs:97-110`; `README.md` "Transport Rules" | keep (numbers) | Sensible defaults for our JSON-socket client: 10 s request timeout, 250 ms "slow" log line, reconnect with backoff (herdr-bar: up to 30 s), and treat a new `boot_id` in the snapshot as "forget everything cached". |
| Control socket + CLI | `$XDG_STATE_HOME/herdr/gpui/control.sock`; one JSON request line, one response line, socket closes; request `{"method","caller","op"}`; `--json`; exit codes 0..8 with fixed meanings; `events --follow`, `wait <cond>` | `docs/cli.md:10-18`, `:25-48`, `:158-171`, `:192-201` | keep (shape) | Precedent for `gpuix-shell` CLI: `--json`, numbered exit codes, `events --follow`, `wait`. |
| Agent-facing commands | `browser open/reload`, `notes`, `feedback --wait`, `checkpoint`, `review`, `fan-out` | `docs/cli.md:69-103` | skip | Utilities boundary (BRIEF §3.8); not the personal shell. |
| Deliberate limitations (their list) | no Nerd Font bundled; no draggable scrollback; no notification history; popups plain; two-pass cell painter | `README.md:3666-3691` | — | Our notification daemon **does** keep history (gpui-shell rule, cap 200). |
| Linux shortcut profile | Ctrl+Shift for app actions, Super left to the desktop, Ctrl+Shift+U unbound for IBus | `README.md:2911-2935` | keep (rule) | Our shell binds Mod (Super) in Sway; never Ctrl+Shift inside kitty. |

---

## 3.4 D-Bus targets (exact names) — so our `dbus-next` code hits the same interfaces

All MEASURED from gpui-shell `crates/services/src/**` proxy definitions. Property reads
go through `org.freedesktop.DBus.Properties.Get/GetAll`; change notifications through
`PropertiesChanged` on the object (zbus `receive_<prop>_changed`), which in dbus-next is
`proxy.getInterface('org.freedesktop.DBus.Properties').on('PropertiesChanged', …)`.

### NetworkManager (system bus, service `org.freedesktop.NetworkManager`)

| Interface | Path | Methods used | Properties used | Signals used | Source |
|---|---|---|---|---|---|
| `org.freedesktop.NetworkManager` | `/org/freedesktop/NetworkManager` | `ActivateConnection(connection o, device o, specific_object o) → o`; `AddAndActivateConnection(a{sa{sv}}, device o, specific_object o) → (o,o)`; `DeactivateConnection(o)`; `Enable(b)`; `GetDevices() → ao`; `GetAllDevices() → ao` | `ActiveConnections ao`, `Connectivity u`, `Devices ao`, `NetworkingEnabled b`, `PrimaryConnection o`, `State u`, `WirelessEnabled b` (rw), `WirelessHardwareEnabled b` | `DeviceAdded(o)`, `DeviceRemoved(o)`; property changes on `WirelessEnabled`, `Connectivity`, `ActiveConnections` | `network/dbus/nm.rs:5-90`; listener `network/mod.rs:210-250` |
| `org.freedesktop.NetworkManager.Device` | per device | `Delete()`, `Disconnect()` | `ActiveConnection o`, `Autoconnect b` (rw), `AvailableConnections ao`, `DeviceType u`, `Driver s`, `HwAddress s`, `Interface s`, `Managed b` (rw), `Mtu u`, `State u`, `StateReason (uu)` | — | `network/dbus/device.rs:9-69` |
| `org.freedesktop.NetworkManager.Device.Wireless` | wifi device | `GetAccessPoints() → ao`, `GetAllAccessPoints() → ao`, `RequestScan(a{sv})` | `AccessPoints ao`, `ActiveAccessPoint o`, `Bitrate u`, `HwAddress s`, `LastScan x`, `Mode u`, `WirelessCapabilities u` | `AccessPointAdded(o)`, `AccessPointRemoved(o)`; property change on `LastScan` (used as "scan finished") | `network/dbus/device/wireless.rs:5-60`; `network/mod.rs:278` |
| `org.freedesktop.NetworkManager.Device.Wired` | wired device | — | `Carrier b`, `HwAddress s`, `PermHwAddress s`, `Speed u` | — | `device/wired.rs` |
| `org.freedesktop.NetworkManager.Device.WireGuard` | wg device | — | `FwMark u`, `ListenPort q`, `PublicKey ay` | — | `device/wireguard.rs` |
| `org.freedesktop.NetworkManager.Device.Statistics` | per device | — | `RefreshRateMs u` (rw), `RxBytes t`, `TxBytes t` | property changes on `RxBytes`/`TxBytes` | `network/dbus/statistics.rs`; `network/mod.rs:366-400` |
| `org.freedesktop.NetworkManager.AccessPoint` | per AP | — | `Flags u` (0 = open), `Frequency u`, `HwAddress s`, `LastSeen i`, `MaxBitrate u`, `Mode u`, `RsnFlags u`, `Ssid ay`, `Strength y` (0–100), `WpaFlags u` | property change on `Strength` | `network/dbus/access_point.rs:5-49`; `network/mod.rs:312` |
| `org.freedesktop.NetworkManager.Connection.Active` | per active conn | — | `Connection o`, `Default b`, `Default6 b`, `Devices ao`, `Id s`, `Master o`, `SpecificObject o`, `State u`, `StateFlags u`, `Type s`, `Uuid s`, `Vpn b` | — | `network/dbus/active_connection.rs:5-57` |
| `org.freedesktop.NetworkManager.Settings` | `/org/freedesktop/NetworkManager/Settings` | `AddConnection(a{sa{sv}}) → o`, `GetConnectionByUuid(s) → o`, `ListConnections() → ao`, `ReloadConnections() → b`, `SaveHostname(s)` | `CanModify b`, `Connections ao`, `Hostname s` | `ConnectionRemoved(o)`, `NewConnection(o)` | `network/dbus/settings.rs:7-53` |
| `org.freedesktop.NetworkManager.Settings.Connection` | per profile | `Delete()`, `GetSettings() → a{sa{sv}}`, `GetSecrets(s) → a{sa{sv}}`, `Update(a{sa{sv}})`, `Save()` | `Filename s`, `Unsaved b` | `Removed()`, `Updated()` | `network/dbus/settings.rs:55-98` |

Logic to copy (`network/nm.rs`):
- **Known-network test**: iterate `Settings.ListConnections`, `GetSettings()["connection"]["id"] == ssid` (`:192-215`); known SSID set from `GetSettings()["802-11-wireless"]["ssid"]` (`:304-333`).
- **Connect** (`:219-272`): find AP by SSID in current scan; if a profile exists → `ActivateConnection(profile, device, "/")`; else `AddAndActivateConnection({"802-11-wireless": {"ssid": bytes}, "connection": {"id": ssid, "type": "802-11-wireless"}, "802-11-wireless-security": {"psk": pw, "key-mgmt": "wpa-psk"}}, device, ap_path)` — security block only when a password is given.
- **Disconnect** (`:275-301`): find the active connection whose `Id == ssid` → `DeactivateConnection`.
- **Scan + dedupe** (`:335-408`): `RequestScan({})` (errors ignored), `GetAccessPoints`, skip empty SSID, keep strongest per SSID, `public = Flags == 0`, sort by strength desc.
- **Enums** (`network/types.rs`): DeviceType 1 Ethernet, 2 Wifi, 5 Bluetooth, 14 Generic, 16 TunTap, 29 WireGuard; DeviceState 10 Unmanaged, 20 Unavailable, 30 Disconnected, 40 Prepare, 50 Config, 60 NeedAuth, 70 IpConfig, 80 IpCheck, 90 Secondaries, 100 Activated, 110 Deactivating, 120 Failed; Connectivity 1 None, 2 Portal, 3 Loss, 4 Full.
- **Not handled** (gaps for our wifi menu, INFERRED): WPA-EAP/802.1X, hidden SSIDs, "forget", `NeedAuth` re-prompt on wrong password (the UI shows `error` but the profile created with a bad PSK stays saved — `AddAndActivateConnection` persists it).

### BlueZ (system bus, service `org.bluez`)

| Interface | Path | Methods | Properties | Signals | Source |
|---|---|---|---|---|---|
| `org.freedesktop.DBus.ObjectManager` | `/` | `GetManagedObjects() → a{oa{sa{sv}}}` (find first object with `org.bluez.Adapter1`; devices = objects with `org.bluez.Device1`; battery present if `org.bluez.Battery1`) | — | `InterfacesAdded(o, a{sa{sv}})`, `InterfacesRemoved(o, as)` | `bluetooth/dbus.rs:18-47`, `:96-142`, `:180-205`; listener `bluetooth/mod.rs:234-241` |
| `org.bluez.Adapter1` | `/org/bluez/hci0` (first adapter found) | `StartDiscovery()`, `StopDiscovery()`, `RemoveDevice(o)` | `Powered b` (rw), `Discovering b` | property changes `Powered`, `Discovering` | `bluetooth/dbus.rs:207-234` |
| `org.bluez.Device1` | `/org/bluez/hci0/dev_XX_…` | `Pair()`, `Connect()`, `Disconnect()` | `Alias s`, `Connected b`, `Paired b` | (via ObjectManager + PropertiesChanged) | `bluetooth/dbus.rs:236-259` |
| `org.bluez.Battery1` | device path | — | `Percentage y` | — | `bluetooth/dbus.rs:261-267` |

Behaviour: toggle = `Powered` flip (`mod.rs:56-71`); discovery auto-stops after 15 s
(`mod.rs:72-85`); `rfkill list bluetooth` checked for "Soft blocked: yes" (`mod.rs:113-121`).
**Gap (INFERRED):** no `org.bluez.Agent1` object is exported and no
`org.bluez.AgentManager1.RegisterAgent/RequestDefaultAgent` call is made, so `Pair()`
only succeeds for Just-Works devices or when another agent (e.g. blueman) is running. A
real "pairing menu" needs our daemon to export `Agent1` with `RequestPinCode`,
`RequestPasskey`, `DisplayPasskey`, `RequestConfirmation`, `RequestAuthorization`,
`AuthorizeService`, `Cancel`, `Release` — dbus-next supports exporting interfaces.

### UPower and power-profiles-daemon (system bus)

| Interface | Path | Methods | Properties | Signals | Source |
|---|---|---|---|---|---|
| `org.freedesktop.UPower` | `/org/freedesktop/UPower` | `EnumerateDevices() → ao`, `GetDisplayDevice() → o`, `GetCriticalAction() → s` | `DaemonVersion s`, `OnBattery b`, `LidIsPresent b`, `LidIsClosed b` | `DeviceAdded(o)`, `DeviceRemoved(o)` | `upower/dbus.rs:231-271` |
| `org.freedesktop.UPower.Device` | display device (from `GetDisplayDevice`) | `Refresh()`, `GetHistory(s,u,u)`, `GetStatistics(s)` | `Type u`, `Percentage d`, `State u`, `TimeToEmpty x`, `TimeToFull x`, `WarningLevel u`, `BatteryLevel u`, `IconName s`, `EnergyRate d`, `Energy* d`, `IsPresent b`, `Temperature d`, `Capacity d`, … | property changes on `Percentage`, `State`, `TimeToEmpty` (also `TimeToFull`) | `upower/dbus.rs:87-229`; `upower/mod.rs:334-400` |
| `net.hadess.PowerProfiles` | `/net/hadess/PowerProfiles` (service `net.hadess.PowerProfiles`) | `HoldProfile(s,s,s) → u`, `ReleaseProfile(u)` | `ActiveProfile s` (rw; `balanced`/`performance`/`power-saver`), `Profiles aa{sv}`, `Actions`, `PerformanceDegraded s`, `PerformanceInhibited s`, `ActiveProfileHolds` | — | `upower/dbus.rs:273-323`; `upower/mod.rs:22-72` (cycle order balanced→performance→power-saver) |

Enums (`upower/dbus.rs:10-85`): BatteryState 0 Unknown, 1 Charging, 2 Discharging, 3 Empty,
4 FullyCharged, 5 PendingCharge, 6 PendingDischarge; WarningLevel 0 Unknown, 1 None,
2 Discharging, 3 Low, 4 Critical, 5 Action; BatteryLevel 0/1/3/4/6/7/8.
Icon ramp (`app/src/icons/mod.rs:56-70`): charging icon else ≥90 full, ≥60 medium, ≥20 low,
else warning.

### Brightness (system bus + udev)

| Interface | Path | Methods | Source |
|---|---|---|---|
| `org.freedesktop.login1.Session` | `/org/freedesktop/login1/session/auto` (service `org.freedesktop.login1`) | `SetBrightness(subsystem "backlight", name <device>, value u)` — unprivileged write for the active session | `brightness/mod.rs:189-198`, `:129` |

Device discovery and change monitoring via udev subsystem `backlight` (`brightness/mod.rs:200-280`);
current/max read from sysfs. Our existing `brightness`/`brightnessctl` script stays the
actuator (BRIEF §3.4); the logind call is the no-setuid alternative if we ever drop brightnessctl.

### MPRIS (session bus)

| Interface | Path | Methods | Properties | Source |
|---|---|---|---|---|
| `org.mpris.MediaPlayer2.Player` | `/org/mpris/MediaPlayer2` on every bus name starting `org.mpris.MediaPlayer2.` | `Next()`, `PlayPause()`, `Previous()` | `PlaybackStatus s` (Playing/Paused/Stopped), `Metadata a{sv}` (`xesam:artist as`, `xesam:title s`, `mpris:artUrl s`), `Volume d` (rw), `CanControl b` | `mpris/dbus.rs:5-24`; `mpris/mod.rs:19`, `:58-110` |

Player discovery: `org.freedesktop.DBus.ListNames` filtered by prefix, then
`NameOwnerChanged` for topology changes (`mpris/mod.rs:256`, `:354`); per-player
`PropertiesChanged` on `Metadata`/`Volume`/`PlaybackStatus` (`:389-410`); events debounced
(`EVENT_DEBOUNCE_MS`, `:429`). Our navidrome/mpv player should **expose** MPRIS (mpv does
with `mpv-mpris`) so the same bar module shows it (INFERRED).

### Notifications (session bus) — we are the server

| Interface | Path | Methods we implement | Signals we emit | Source |
|---|---|---|---|---|
| `org.freedesktop.Notifications` | `/org/freedesktop/Notifications`, well-known name `org.freedesktop.Notifications` requested with `AllowReplacement` | `GetCapabilities() → as` = `["actions","body","body-markup","persistence"]`; `GetServerInformation() → (name, vendor, version, spec "1.2")`; `Notify(app_name s, replaces_id u, app_icon s, summary s, body s, actions as, hints a{sv}, expire_timeout i) → u`; `CloseNotification(u)` | `NotificationClosed(id u, reason u)` (1 expired, 2 dismissed, 3 by call, 4 undefined — spec); `ActionInvoked(id u, action_key s)` | `notification/mod.rs:25-29`, `:305-345`, `:380-585` |

Hints read: `urgency y` (default 1), `image-path`/`image_path` (only kept if the file still
exists — Chromium unlinks its temp file), `app_icon`/`icon-path`/`icon_path`, `desktop-entry`
(→ XDG icon lookup in hicolor + `/usr/share/pixmaps`, `applications/icons.rs:20-80`).
`replaces_id` reuses the id only if that id is still in the list (`:421-435`).

### System tray (session bus) — we would be the watcher/host

| Interface | Path | Role | Source |
|---|---|---|---|
| `org.kde.StatusNotifierWatcher` | `/StatusNotifierWatcher`, well-known name `org.kde.StatusNotifierWatcher` | We **serve** it: `RegisterStatusNotifierItem(s)` (header sender + arg → service), `RegisterStatusNotifierHost(s)`; properties `RegisteredStatusNotifierItems as`, `IsStatusNotifierHostRegistered b`, `ProtocolVersion i`; signals `StatusNotifierItemRegistered/Unregistered(s)`, `StatusNotifierHostRegistered/Unregistered` | `tray/dbus.rs:30-240` |
| `org.kde.StatusNotifierItem` | item's path (usually `/StatusNotifierItem`) | We **consume**: props `IconName s`, `IconPixmap a(iiay)` (ARGB32, pick largest), `Menu o`, `Title s`, `Id s`, `Status s`, `ToolTip (sa(iiay)ss)`; methods `Activate(ii)`, `SecondaryActivate(ii)`, `ContextMenu(ii)`; signal `NewIcon` | `tray/dbus.rs:245-300`; `tray/mod.rs:240-270` |
| `com.canonical.dbusmenu` | from `Menu` property | `GetLayout(parent i, depth i, props as) → (u, layout)`, `Event(id i, "clicked", v, ts u)`, `AboutToShow(id) → b`; signal `LayoutUpdated(u,i)` | `tray/dbus.rs:319-340`; `tray/mod.rs:131-200` |

### Not D-Bus but part of the same service set

| Concern | Mechanism in gpui-shell | Source | Our plan |
|---|---|---|---|
| Audio monitoring | libpulse context `"gpuishell"`, `get_sink_info_by_name("@DEFAULT_SINK@")`, `get_source_info_by_name("@DEFAULT_SOURCE@")`, skip `monitor_of_sink` sources | `audio/mod.rs:204-290` | `wpctl status`/`wpctl get-volume @DEFAULT_AUDIO_SINK@` polled + `pw-mon` or our `volume` script (BRIEF §3.4) |
| Audio commands | `wpctl set-volume @DEFAULT_AUDIO_SINK@ N%`, `set-mute … toggle`, `AdjustSinkVolume(±delta)` | `audio/mod.rs:81-165` | identical |
| Privacy | PipeWire registry: `media.class` `Stream/Input/Video` / `Stream/Input/Audio`; inotify on `/dev/video*` | `privacy/mod.rs:119-230` | later |
| Wallpaper | `awww`/`awww-daemon` (swww renamed) | `wallpaper/mod.rs:100-150`, commit `b82254b` | skip |
| Config watch | inotify `MODIFY \| CLOSE_WRITE \| CREATE \| DELETE \| MOVED_TO \| MOVE_SELF \| DELETE_SELF`, debounced | `watcher.rs:28-70` | `fs.watch` on `~/.config/theme` symlink target + `gpuix-shell.json` |

---

## 3.5 herdr protocol facts the shell needs (consolidated)

**JSON API socket** (what herdr-bar uses; MEASURED from `src/client.rs`):
- Path: `$HERDR_SOCKET_PATH` (herdr injects it into every pane; on this box it is set).
  Fallback CLI: `$HERDR_BIN_PATH` or `herdr` on PATH (`client.rs:5-12`, `:113-118`).
- Framing: **one request per connection**, one JSON line `{"id": "<any string>", "method":
  "<name>", "params": {...}}\n`, one JSON response line, then close (`client.rs:144-156`).
  The response is a JSON object; herdr-bar's `unwrap` rejects anything not a map and treats a
  failure as "herdr request failed" (`:192-211`) — exact `result`/`error` key names were not
  read here (gap §6; `herdr api schema` will say).
- Read-only methods: `session.snapshot {}` (~15 ms, `README:How it works`); `pane.read {pane_id,
  lines, source}`; `pane.process_info {pane_id}`; `plugin.list` (polled every 10 s by the watcher).
- Acting methods: `tab.focus {tab_id}`, `pane.focus {pane_id}`, `agent.focus {target}`
  (target = `"w1:p1"` style pane id, `client.rs:713`), `workspace.focus {workspace_id}`,
  `tab.close {tab_id}`, `tab.rename {tab_id, …}`.
- Events: a **long-lived** connection sending `{"id":"bar-events","method":"events.subscribe",
  "params":{"subscriptions":[{"type":"pane.agent_detected"},{"type":"pane.agent_status_changed",
  "pane_id":"…"}]}}\n`; first line is the ack, then newline-delimited event objects follow
  (`client.rs:503-545`, `tab_status.rs:483-500`). Reconnect with backoff up to 30 s.
- CLI equivalents: `herdr api snapshot`, `herdr tab focus ID`, `herdr tab close ID`,
  `herdr agent focus TARGET` (`client.rs:241`, `:352-378`); BRIEF adds `herdr workspace
  list/focus/create/close`, `herdr api schema`, `herdr notification show`.
- Snapshot shape (keys read by herdr-bar `items.rs:334-345`, `:420-476`): top-level
  `workspaces[]`, `tabs[]`, `panes[]`, `agents[]`, `focused_tab_id`, `focused_pane_id`;
  workspace `{workspace_id, label, active_tab_id, worktree{branch}, focused, agent_status}`;
  tab `{tab_id, workspace_id, label, number, agent_status}`; pane `{pane_id, tab_id,
  workspace_id, title, label, cwd, foreground_cwd, terminal_title_stripped}`; agent
  `{pane_id, tab_id, workspace_id, agent, display_agent, name, title, terminal_title_stripped,
  foreground_cwd, cwd, agent_status}`. These match herdr-gpui's typed `ClientShell*` structs
  (`wire.rs:374-436`), which also carry `number`, `custom_label`, `git_ahead_behind`,
  `state_change_seq`, `tokens`.
- Status values: `idle | working | blocked | done | unknown` (+ herdr-bar's synthetic `none`).

**Binary client socket** (herdr-gpui; MEASURED, corrected 2nd pass): `<same dir>/herdr-client.sock`;
4-byte LE length + bincode 2 standard config (`codec.rs:8-12`). Two hello shapes exist in the
wire types: the legacy `ClientMessage::ClientShellHello{version: u32, cell_width_px,
cell_height_px, surface_size, pixel_mouse, direct_graphics, endpoint_keybindings,
mouse_capture}` (`wire.rs:168-176`) and the generation-1 **endpoint** hello
`EndpointClientHello{generation (= ENDPOINT_PROTOCOL_GENERATION = 1), cell_width_px,
cell_height_px, surface_size, pixel_mouse, direct_graphics, endpoint_keybindings,
mouse_capture, surface_active, surface_reuse, surface_delta, surface_scroll, snapshot_codecs,
surface_codecs, input_codecs, blob_codecs}` answered by `EndpointServerWelcome{generation,
server_version, snapshot_codec, surface_codec, input_codec, blob_codec, methods[],
capabilities[], error?}` (`crates/herdr-protocol/src/endpoint.rs:6`, `:19-44`, `:51-64`).
The welcome's `methods[]` is the daemon's advertised method list; the client refuses to send
anything not in it (`handle.rs:250-252`, `method.rs:79-85`). Required capabilities for an
inactive/SSH client: `surface_interest`, `presentation_effects_fence`, `health_check`
(`session.rs:37-42`). Server pushes `ClientShellSnapshot` (with `boot_id`, `revision`) and
`SemanticNotification`. INFERRED: not worth speaking from TypeScript; the JSON socket +
`events.subscribe` gives us the same snapshot and herdr's notifications already reach us via
freedesktop Notifications when `[ui.toast] delivery = "system"` is set in herdr's
`config.toml`. One thing to borrow anyway: ask the daemon what it supports (the JSON
`herdr api schema` is our equivalent of `welcome.methods`) before calling a method.

**herdr-gpui control socket** (precedent for ours): `$XDG_STATE_HOME/herdr/gpui/control.sock`,
one JSON line in/out, `{"method","caller","op"}`, `--json` flag, exit codes 0 done / 1 refused /
2 bad args / 3 not running / 4 nothing yet / 5 not there / 6 busy / 7 timeout / 8 unavailable
(`docs/cli.md:10-48`, `:192-201`). Our `gpuix-shell` CLI should adopt the same exit-code table.

---

## 3.6 Ranking / MRU rules worth copying (herdr-bar, exact)

1. `status_rank`: blocked 0 < done 1 < working 2 < idle 3 < other (`items.rs:20-26`).
   herdr-gpui's priority is the same order (`agents.rs:46-54`).
2. Empty query (`app.rs:380-417`):
   - skip the **current** row (the tab/pane you are in);
   - `recent` = rows with an MRU rank, ascending (most recent first);
   - `rest` sorted by `(is_workspace_row, status_rank, workspace_label, tab_number ?? 2^30, title)`;
   - `ordered = recent ++ rest`, then insert `current` at index `min(len, max(1, recent.len()))`
     → the current row is never first, so Enter immediately goes somewhere else (alt-tab).
3. With a query (`app.rs:101-125`, `:354-378`): every space-separated term must match
   (AND); score = sum of best field scores, `+40` when the match is in field 0 (title);
   sort key `(-score, mru_rank ?? 999, status_rank, title_length)`.
4. Fuzzy constants (`fuzzy.rs:12-18`): match 16, boundary 16, camel 12, consecutive 16,
   first-char multiplier 2, gap start −3, gap extension −1.
5. MRU (`mru.rs:11`, `:60-80`): cap 120, `touch(key,title)` on every jump, `rank(key,title)`
   returns position; persisted as JSON with atomic temp+rename.
6. Multi-agent tab glyph = most urgent agent (`tab_status.rs:87-100`, `min(rank)`).
7. Refresh while open: 900 ms, skip repaint when snapshot bytes unchanged
   (`client.rs:259-285`).
8. Running time format: `<60 s → "47s"`, `<60 m → "12m"`, `<24 h → "2h04m"`, else `"4d3h"`
   (`age.rs:187-205`).

---

## 4. Design values found (sizes, colours, fonts, radii, timings)

gpui-shell tokens (`crates/ui/src/theme/tokens.rs`, MEASURED) — Zed-derived, to compare
with our design kit, not to adopt wholesale:

| Token | Values |
|---|---|
| Spacing | None 0, XXSmall 2, XSmall 4, Small 6, Medium 8, Large 12, XLarge 16, XXLarge 20, XXXLarge 24 (`:37-47`) |
| Radius | None 0, XSmall 2, Small 4, Medium 6, Large 8, XLarge 12, Full 9999 (`:181-189`) — launcher/OSD/panel surfaces use **Large = 8**, inner cards **Medium = 6** (`patterns/surface.rs:12-24`, `patterns/launcher.rs:82`, `patterns/osd.rs:95`); Tom's rule is 8/12 inner corners, so this agrees. |
| Text | base 13 px; XSmall ×0.77 (10), Small ×0.85 (11), Default ×1.0, Medium ×1.08 (14), Large ×1.23 (16), XLarge ×1.38 (18) (`:76-84`); ours: Anthropic Sans 12 UI. |
| Icon | Indicator 10, XSmall 12, Small 14, Medium 16, Large 18, XLarge 20, XXLarge 48 (`:140-150`) |
| Bar | thickness 32, long-axis padding 14; vertical bar py 8, px 1; workspace pill 20×20 (24 wide active; horizontal 22/28); tray item 24; chip gap 4; section divider 14; vertical text line width 20 (`bar/modules/style.rs:19-37`, `patterns/bar.rs:97-111`) |
| Bar chip (2nd pass) | each widget sits in a chip: py 3 (4 horizontal), px 4 vertical / 8 horizontal (grouped: 2 / 7), radius Small 4 on a vertical bar and Large 8 on a horizontal one, outer margin 2, fixed 24 px height on a horizontal bar "so every chip shares one baseline"; chip bg = surface_background, border = border_variant at 0.9 opacity (vertical) or border, hover = elevated_surface_background; bar text = Small (0.85 rem) weight MEDIUM (`patterns/bar.rs:84-118`, `:204-275`; `bar/modules/style.rs:77-107`) |
| Launcher | 600×450, top margin 100; query row px 16 py 12 gap 12; prefix badge px 8 py 3 radius 4; footer px 16 py 8; 1 px hairline rows (`launcher/config.rs`; `patterns/launcher.rs:69-140`) |
| Panel | default 320×400, margin 5; control center 340 wide, 288 collapsed; gutter-clamped to display (`panel.rs:28-31`; `control_center/mod.rs:45-46`, `:226-238`) |
| OSD | 280×56 (vertical 56×280), margin 24, inner padding 8, text 12 px, value column 36, **2 s** auto-dismiss; track is a rounded bar (`osd/mod.rs:29-32`; `patterns/osd.rs:63-108`) |
| Notifications | popup 360×320 top-right, stack 4, card 92/170, center 420×540, default timeout **5000 ms**, history **200** (`notification/config.rs:39-55`; `services/notification/mod.rs:28-29`); card: 3 px urgency stripe, 64 px image slot, 28 px icon, 24 px icon badge, body line-height 16, summary 18, time `%H:%M` (`notification/card.rs:40-170`, `:225-233`) |
| herdr-bar popup (2nd pass) | herdr popup pane `74% × 62%` of the terminal; preview column = `clamp(inner/3, PREVIEW_MIN..PREVIEW_MAX)` when inner ≥ 92 cols; `SELECTED_BAR = "▌"` row marker; `PREVIEW_DEBOUNCE 0.07 s`, `PREVIEW_TTL 1.5 s`; refresh 900 ms (`herdr-plugin.toml:52-58`; `src/render.rs:19`, `:61-75`; `src/app.rs:46-48`) |
| Dock | icon 40, reveal/hide 750 ms, hidden strip 6, context menu 160×(40/row) (`dock/mod.rs:23-35`) |
| Bluetooth | discovery 15 s (`bluetooth/mod.rs:79`) |
| Sysinfo | 2 s poll (`sysinfo/mod.rs:201`) |
| Shadows | `ElevationIndex::ElevatedSurface` = 0 2px blur 3 α0.12 + 0 1px α0.03/0.06; `ModalSurface` = three layers (`styles/elevation.rs:36-80`) — **do not copy** (Tom: hairlines, not shadows). Surfaces otherwise are `bg + border_1 + rounded`, which is exactly our rule. |
| Default theme (`theme.md`) | bg #1E1E1E/#252526/#2D2D2D/#333333; text #FFFFFF/#CCCCCC/#888888/#6E6E6E; border #3C3C3C/#2D2D2D/focus #007ACC; accent #007ACC sel #094771 hover #1177BB; status success #4ADE80 warning #FBBF24 error #F87171 info #60A5FA; interactive #3B3B3B/#454545/#505050 — Zed blue, replaced by noir/claude. |

herdr-bar colours (`src/theme.rs:38-56`): agent brand hexes worth keeping for agent rows —
`agent_claude #D97757`, `agent_codex #10A37F`, `agent_kimi #9B8AFB`, `agent_gemini #4285F4`,
`agent_cursor #A78BFA`, `agent_opencode #38BDF8`; `working #c78a1f` (orange); the rest ANSI.
Herdr Agent Icons Max font maps `U+E1A0–U+E1B7` (README `Agent icons at a glance`); kitty:
`symbol_map U+E1A0-U+E1B7 Herdr Agent Icons Max` — relevant to the kitty projector, not the shell.

herdr-gpui status dots (`sidebar/agents.rs:425-440`, `sidebar/metrics.rs:14-16`): 8 px;
working `#f9e2af` filled, blocked `#f38ba8` filled, done `#94e2d5` filled, idle `#a6e3a1`
**hollow**, unknown 3 px `#6c7086`; sidebar 232, rail 48. These are Catppuccin Mocha (the
daemon's default palette); herdr-web-ui's Noir/Claude palettes (BRIEF table) govern ours.

Fonts: gpui-shell uses GPUI's default family; herdr-gpui Linux defaults DejaVu Sans Mono /
DejaVu Sans, no bundled Nerd Font (`README.md:3668-3673`). Ours: Anthropic Sans / Serif /
AnthropicMono Nerd Font via `@gpuix/native` 0.11.0 `registerFont(bytes)` (BRIEF table).

---

## 5. Reusable code or data, with exact paths

Rust that is small, pure and worth porting line-for-line to TS (`pkgs/gpuix-shell/src/…`):

| What | Path | Lines | Port to |
|---|---|---|---|
| fzf-style fuzzy scorer with positions | `/home/tom/Downloads/herdr-bar/src/fuzzy.rs` | 1–285 (+ golden data `tests/data/fuzz-corpus.jsonl`, `tests/data/fixtures.json`) | `src/lib/fuzzy.ts` + `fuzzy.test.ts` |
| Resting/query ordering | `/home/tom/Downloads/herdr-bar/src/app.rs` | 46, 101–125, 354–417 | `src/lib/rank.ts` |
| MRU store with atomic write | `/home/tom/Downloads/herdr-bar/src/mru.rs` | 1–120 | `src/lib/recent.ts` |
| Snapshot → rows (title/summary/cwd rules) | `/home/tom/Downloads/herdr-bar/src/items.rs` | 20–26, 129–230, 334–500 | `src/herdr/rows.ts` |
| Status glyph compose/strip, most-urgent rule | `/home/tom/Downloads/herdr-bar/src/tab_status.rs` | 33–104 | `src/herdr/status.ts` |
| Running-time format | `/home/tom/Downloads/herdr-bar/src/age.rs` | 187–205 | `src/lib/age.ts` |
| herdr JSON socket client (request line, CLI fallback, events) | `/home/tom/Downloads/herdr-bar/src/client.rs` | 91–300, 351–400, 467–560 | `src/herdr/client.ts` (Bun `net.connect` on the unix path) |
| NM connect/scan/known logic | `/home/tom/Downloads/gpui-shell/crates/services/src/network/nm.rs` | 186–408 | `src/services/network.ts` |
| NM enums | `/home/tom/Downloads/gpui-shell/crates/services/src/network/types.rs` | 7–95 | same |
| BlueZ helper | `/home/tom/Downloads/gpui-shell/crates/services/src/bluetooth/dbus.rs` | 16–178 | `src/services/bluetooth.ts` |
| UPower data model + profile cycle | `/home/tom/Downloads/gpui-shell/crates/services/src/upower/{dbus.rs,mod.rs}` | dbus 10–85, 231–323; mod 22–130, 160–250 | `src/services/power.ts` |
| Notification server (`Notify` parsing, hints, timers, slots) | `/home/tom/Downloads/gpui-shell/crates/services/src/notification/mod.rs` | 25–96, 305–345, 389–585, 602–640 | `src/notifications/server.ts` |
| XDG icon lookup | `/home/tom/Downloads/gpui-shell/crates/services/src/applications/icons.rs` | 20–84 | `src/lib/icons.ts` |
| Desktop-file scan + Exec cleaning | `/home/tom/Downloads/gpui-shell/crates/services/src/applications/mod.rs` | 38–66, 144–260 | `src/launcher/apps.ts` |
| MPRIS metadata extraction | `/home/tom/Downloads/gpui-shell/crates/services/src/mpris/mod.rs` | 58–110, 250–300, 350–490 | `src/services/mpris.ts` |
| Panel placement from click (anchor + margin clamped to usable area) | `/home/tom/Downloads/gpui-shell/crates/app/src/panel.rs` | 37–190 | `src/lib/placement.ts` |
| Launcher prefix parser + view trait | `/home/tom/Downloads/gpui-shell/crates/app/src/launcher/{mod.rs,view.rs}` | mod 143–200; view 60–155 | `src/launcher/{route.ts,view.ts}` |
| Launcher key table | `/home/tom/Downloads/gpui-shell/crates/app/src/keybinds.rs` | 30–61 | `src/launcher/keys.ts` |
| Icon ramps (wifi/volume/brightness/battery/profile/status) | `/home/tom/Downloads/gpui-shell/crates/app/src/icons/mod.rs` | 24–100 | `src/lib/ramps.ts` |
| Web search providers | `/home/tom/Downloads/gpui-shell/crates/app/src/launcher/modules/web/config.rs` | 19–80 | `src/launcher/views/web.ts` |
| Service lifecycle with generations | `/home/tom/Downloads/gpui-shell/crates/services/src/lifecycle.rs` | 1–160 | `src/lib/service.ts` |
| Config/state/theme separation rule + validate | `/home/tom/Downloads/gpui-shell/crates/app/src/config/{mod.rs,state.rs}` | mod 60–130, 211–276; state 1–70 | `src/config.ts` |
| herdr wire structs (field names, serde casing) | `/home/tom/Downloads/herdr-gpui/crates/herdr-protocol/src/wire.rs` | 286–436, 589–626 | `src/herdr/types.ts` (as TS types, JSON side only) |
| herdr JSON method names | `/home/tom/Downloads/herdr-gpui/crates/herdr-client/src/method.rs` | 34–80 | `src/herdr/methods.ts` |
| CLI exit-code table | `/home/tom/Downloads/herdr-gpui/docs/cli.md` | 38–48 | `src/cli.ts` |
| herdr endpoint hello/welcome field names (2nd pass) | `/home/tom/Downloads/herdr-gpui/crates/herdr-protocol/src/endpoint.rs` | 6, 19–64 | `src/herdr/types.ts` (only if we ever speak the binary socket) |
| herdr sidebar tokens + default rows (2nd pass) | `/home/tom/Downloads/herdr-gpui/crates/herdr-gpui/src/config/sidebar.rs` | 81–96, 306–420 | `src/rail/rows.ts` (which snapshot fields a slot row shows) |
| Runtime library list for the Nix wrapper (2nd pass) | `/home/tom/Downloads/gpui-shell/nix/build.nix` | 11–31, 64–118 | `pkgs/gpuix-shell/default.nix` (cross-check against the measured rail-probe `LD_LIBRARY_PATH`) |
| OSD colour/timer rules (2nd pass) | `/home/tom/Downloads/gpui-shell/crates/app/src/osd/mod.rs` | 99–121, 160–227, 232–290 | `src/osd/osd.tsx` |
| herdr-bar plugin manifest (shape of a herdr popup/action/startup/event hook) (2nd pass) | `/home/tom/Downloads/herdr-bar/herdr-plugin.toml` | 1–80 | reference for any herdr-side hook we add (none planned tonight) |

Data/assets:
- 230 MIT-licensed SVG icons (Lucide-style + brand marks) at
  `/home/tom/Downloads/gpui-shell/crates/assets/icons/*.svg` (`LICENSE` and `README.md` in that
  dir) — includes `wifi{,_high,_low,_zero,_off}`, `volume{,_low,_medium,_off}`,
  `sun{,_dim,_medium}`, `battery*`, `bluetooth*`, `bell*`, `moon`, `zap`, `gauge`, `power`,
  `tailscale`, `nixos`, `spotify`. Candidate fallback when Anthropicons lacks a glyph.
- Agent brand SVGs at `/home/tom/Downloads/herdr-gpui/assets/icons/agent-*.svg` (26 agents)
  and provider marks under `providers/` (check `assets/icons/README.md`/licence notes before
  shipping; vendor marks belong to their owners).
- Doc pages as config references: `/home/tom/Downloads/gpui-shell/docs/src/content/docs/reference/{bar,launcher,control-center,osd,theme,configuration}.md`.
- `/home/tom/Downloads/gpui-shell/scripts/notification_test.sh` (165 lines) — a `notify-send`
  battery for a daemon: `--quick`, `--sleep SECONDS` (default 1.5), `--image PATH` for the
  image-hint test; exercises icon display, image hints, text wrapping and layout consistency
  (`:1-22`, 2nd pass). Run it against `gpuix-shell notifications` under `runtime-test` as the
  first compositor smoke for the mako replacement.

---

## 6. Gaps and unknowns

- **Sway**: gpui-shell has no Sway backend (`compositor/{hyprland,niri,mango}.rs` only);
  nothing in the three repos talks i3-ipc. Our Sway adapter comes from
  `/home/tom/.wt/hyprland-solid-shell/design/gpuix-comparison/` (BRIEF table), not from here.
- **herdr in gpui-shell**: none. herdr integration shapes come only from herdr-bar/herdr-gpui.
- **herdr JSON response envelope**: herdr-bar only checks "is a map / failed"; the exact
  `result`/`error` keys and the event line shape of `events.subscribe` were not read. Run
  `herdr api schema` (read-only) in the builder's own wave to confirm; also whether
  `session.snapshot` over the socket equals `herdr api snapshot` output (INFERRED yes).
- **herdr-gpui hello version** — resolved 2nd pass: the generation-1 client sends
  `EndpointClientHello{generation: 1, …}` (`endpoint.rs:6`, `:19-44`); the legacy
  `ClientShellHello{version: u32}` variant (`wire.rs:168-176`) is kept only for the wire
  enum's positional stability. Codec names `shell.snapshot.v1`, `shell.surface.v1`,
  `shell.input.semantic.v1`, `shell.blob.v1`; `MIN_HERDR_VERSION = "0.9.0"`. Irrelevant if we
  stay on the JSON socket, which we should.
- **JSON API schema on this box** (2nd pass): `herdr api schema` was deliberately **not** run
  by this reader (the brief says never touch herdr; a read is harmless but the orchestrator
  owns live calls). The builder should run it once, read-only, and diff the method names
  against §3.3 and the snapshot keys against §3.5 before writing `src/herdr/client.ts`.
- **gpui-shell is two months stale**: its HEAD is 2026-08-03 against zed `main` of that day;
  layer-shell details (e.g. `wp_viewport` sizing at `bar/view.rs:62-80`) describe that gpui
  snapshot, not `@gpuix/native` 0.11.0. Treat its Wayland caveats as hypotheses to re-measure
  under `runtime-test`, not as facts about our renderer.
- **BlueZ pairing agent**: absent in gpui-shell (see §3.4); a pairing menu with PIN/passkey
  needs `org.bluez.Agent1` exported by our daemon. Unverified whether BlueZ on the Zenbook
  has another default agent registered.
- **Wi-Fi**: no 802.1X/EAP, no hidden SSID, no forget/delete profile, no captive-portal
  handling beyond the `Connectivity == Portal` enum; wrong-PSK profiles are left saved.
- **Notifications**: `body-markup` is advertised but I did not read how (or whether) the
  card renders markup; no sound; no per-app rules; no "critical never expires" rule visible
  (urgency 2 with `timeout_ms = 0` is only used for local slots) — mako's
  `[urgency=critical]` behaviour must be re-created by us.
- **Tray**: full SNI host + dbusmenu is ~600 lines; the icon pixmap path (ARGB → image) is
  the costly part (`tray/mod.rs:222-270`). Deferred.
- **Clipboard history**: none of the three has one (Vicinae's goes away; ours is `wl-paste
  --watch`, BRIEF §3.4).
- **OpenUI / generative UI**: none of the three; nothing to mine.
- **Audio**: gpui-shell binds libpulse for monitoring; a TS daemon cannot without native
  code — poll `wpctl` or subscribe via `pw-mon`/`pactl subscribe` (INFERRED; not tested).
- **Licensing**: gpui-shell has no top-level LICENSE file in the tree listing (icons dir has
  one); herdr-gpui wire types are "Adapted from herdr … Apache-2.0; see NOTICE.md"
  (`wire.rs:1`). We port shapes and constants, not files; agent/provider SVG marks are
  third-party trademarks.
- **Not run**: no binary from any of the three was built or executed tonight; every
  behaviour above is MEASURED from source or REPORTED from docs. No compositor test was
  performed by this reader.

---

### What this reader did / did not do

Did: read gpui-shell's README, AGENTS.md, both Cargo manifests, all six doc reference pages,
every D-Bus proxy file, the service listeners' control flow, the app's IPC/args/keybinds/
panel/config/launcher/bar/control-center/OSD/notification/dock entry points, the ui tokens/
patterns/elevation; herdr-bar's README, manifest, CHANGELOG, `items/mru/fuzzy/age/theme/
tab_status/client/app` sources; herdr-gpui's README, GUI README (intro, configuration,
notifications, shortcuts, supported, limitations), `docs/cli.md`, `AGENTS.md`, discovery/
frame/codec/handle/method sources, wire types, sidebar status code; `ls` of local herdr
sockets and `HERDR_*` env (read-only).

Did not: build or run anything; read gpui-shell's Hyprland/Niri backends, dock internals,
tray pixmap decoding, or the `story` crate bodies; read herdr-gpui's painting, SSH, teleport,
browser or orchestrator code; verify any claim against a live herdr API schema.

Second pass (2026-10-21 ~01:40 CEST, Fable): re-read the same files plus gpui-shell
`nix/build.nix`, `osd/mod.rs` in full, `notification/card.rs`, `state.rs`, `bar/config.rs`,
`patterns/bar.rs` in full, `scripts/notification_test.sh`; herdr-bar `herdr-plugin.toml`,
`config.rs`, `cli.rs`, `render.rs` layout, `CHANGELOG.md`; herdr-gpui `herdr-protocol/src/
endpoint.rs`, `herdr-client/src/{limits,session,method,event,compat,connect,discovery}.rs`,
`herdr-gpui/src/config/{sidebar,status_icons,notifications,layout}.rs`, README sections on
sidebar rows, sounds, system notifications, dock badge, plugins. Spot-checked every pointer
the first pass cited in §3.3, §3.6 and §4 by printing the lines; all held except the sidebar
layout-mode list, corrected above. Grepped Tom's user turns in the BRIEF-listed transcripts
for the three project names (none found; §2). `git log` / `git describe` on the three clones
(read-only). Still unverified: everything marked INFERRED; no live `herdr api schema`; no
compositor run.
