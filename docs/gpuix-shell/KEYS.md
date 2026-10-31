# KEYS.md — the complete keybinding and command map for gpuix-shell

Synthesis note, revision 2, 2026-10-21 (overnight, Tom offline). Sources: BRIEF.md, ASSUMPTIONS.md,
the sibling syntheses (SCOPE.md, DESIGN.md, BOUNDARY.md) and **every** wave-1 note (01–30, 35, 36,
including the post-hoc revisions of 15, 18, 19, 21, 23, 24 and 26 written 2026-10-21 12:0x). Every row
cites the note that grounds it as `[w1-NN]`; `binds.conf:N` is `home/dot_config/sway/binds.conf` in this
worktree, re-read tonight (108 `bindsym` lines, 10 `workspace … output` lines, `$mod` = Mod4,
`$prompt = kitty --class`). Rows marked **INFERRED** fill a gap the notes leave; each such decision is
one `KEYS.md:` line in ASSUMPTIONS.md (revision 1 claimed this and had not done it; revision 2 does).
No row asks Tom anything.

**Authority.** DESIGN.md:17 says "keys to KEYS.md". Where SCOPE.md §22 / S-053 or DESIGN.md §8 spell a
key or a prefix differently, this file rules and §8.6 lists each difference. The CLI grammar follows
SCOPE S-002 (`gpuix-shell <surface> <verb>`), with the night brief's `toggle <surface>` spelling kept as
an alias (§7.0).

**Status legend**

| Status | Meaning |
|---|---|
| keep | the line stays byte-for-byte; the shell may observe or render its effect |
| changed | same key, new target (`exec` now calls `gpuix-shell …`), or same command whose backend script now calls the shell |
| new | a bind or verb that does not exist in dotfiles today |
| retired | removed, or kept only as a compatibility shim until a named wave verifies the replacement |
| conflict | two rulings disagree; the chosen side is stated and logged |

**Architecture facts the map relies on**

| Fact | Consequence for keys | Source |
|---|---|---|
| One CLI, `gpuix-shell`, speaks length-prefixed JSON-RPC over `$XDG_RUNTIME_DIR/gpuix-shell/shell.sock`; replies routed per connection (the Vicinae 0.29.1 bug fixed). | every Sway bind is `exec gpuix-shell …`; `herdr-picker`'s framing code needs only a path change | SCOPE S-002; [w1-18 §5.5]; [w1-36 §4.6] |
| "keypress > sway > script execution" (Tom 2026-10-13). | volume, brightness, media, touchpad, screenshot, OCR, colour-picker and pomodoro keys keep calling their scripts; the shell renders only the OSD or an indicator | BRIEF; [w1-36 T10]; [w1-29 #104/#115/#123/#234/#237/#238/#250] |
| GPUIX 0.11.0 has no window close/hide: a toggled overlay is **one short-lived process per show**; `toggle` = spawn or kill; `state` reads the pid file. | second press of the same key closes; `Esc` exits the process; nothing is ever "hidden" | [w1-15 §5.2 D, G1]; SCOPE S-001 |
| GPUIX picks no output: a surface opens on the focused output at creation. | keyboard-exclusive overlays (launcher, switcher, centre, controls, power, cheatsheet) run `swaymsg focus output eDP-1` first and are re-created on output change (DESIGN A-07); toasts follow focus. **INFERRED** default | [w1-15 §3.16]; [w1-26 §5.2]; [w1-18 G3] |
| Inside a GPUIX surface, key names are lowercase and Super/Logo arrives as `cmd`; Sway consumes every `$mod` chord first. | surface keymaps use Ctrl/Alt/Shift only; nothing inside a surface binds Super | [w1-15 §3.10, P3] |
| GPUIX has no zoom API (Tom 2026-10-13 complaint) and no JS clipboard API. | overlays implement `Ctrl+=` / `Ctrl+-` / `Ctrl+0` themselves (0.8–1.6, rail exempt); copy actions shell out to `wl-copy` | [w1-15 G6/G8, §5.2 G]; SCOPE S-043 |
| Each CLI invocation costs ~0.1 s (addon load). | fine for binds; scripts that poll use `listen`, never a loop of `status` | [w1-21 §4.3] |
| herdr is read-only data (`herdr api snapshot`); focus moves only through `swaymsg`. | no key calls `herdr workspace focus` | [w1-26]; [w1-16] |
| No `nop`-binding dispatch tonight; no global-shortcut daemon. | the shell registers no keys of its own | [w1-17]; SCOPE S-003 |

---

## 1. Rules the map keeps (never violated by any row below)

| Rule | Source |
|---|---|
| `$mod+k` is `focus up`. The shell never takes Mod+K (Tom 2026-10-07). | [w1-17] |
| The three herdr chord lines (`binds.conf:9-11`) and the four `Alt+h/j/k/l` lines (`binds.conf:102-105`) stay verbatim; `flake.nix:1137-1144` asserts them. | [w1-17] |
| `Ctrl+n` / `Ctrl+Shift+n` stay bare Chrome grabs (Tom's request, `binds.conf:19-20`). | [w1-17] |
| Volume, brightness, media, touchpad, screenshot, colour picker, OCR and pomodoro keys keep calling their scripts; the shell adds only the OSD or an indicator. | BRIEF; [w1-36 T10]; [w1-29 #104/#115/#123/#234/#237/#238/#250] |
| The client's `sway-local.conf` (home.nix:149-168) must not override `$mod+Return` or `$mod+Shift+n`; strix has no `bindsym` at all. | [w1-17] |
| No Chrome `--app` desktop entries beyond the three bound ones, no Claude Desktop, no ChatGPT entry. | [w1-17] |
| `shell.sock` verbs never move focus unless the verb is named `focus` or `open`; no verb approves a polkit, NetworkManager or BlueZ prompt; `lock` may be a verb, `unlock` never is; power actions need the on-screen hold (or `--yes` from a terminal, never from a bind). | [w1-30 §3.2, §4.1 10–11]; [w1-29 §3.6, §4 16/18]; [w1-19 §3D] |
| Media keys stay `media` → playerctl; the Navidrome player is one MPRIS source (`org.mpris.MediaPlayer2.gpuix_music`) among others. | ASSUMPTIONS (music); [w1-18 G10] |
| Nothing scheduled, no timers, no secrets, no fonts in git; Vicinae `interval` commands and script `refreshTime` run only while the launcher is visible. | AGENTS.md; [w1-36 §4.5, G8] |
| One owner per bus name: the notifications daemon never runs beside mako; the launcher never beside Vicinae. | [w1-29 §3.5]; SCOPE S-012 |

---

## 2. Every current Sway bind, with its new target

### 2.1 Launcher, herdr, workspaces (`binds.conf:6-17`)

| Line | Bind | Today | Status | New target / note | Source |
|---|---|---|---|---|---|
| 6 | `$mod+d` | `exec vicinae toggle` | **changed** | `exec gpuix-shell launcher toggle` | BRIEF §3.2; [w1-17 §3.1]; [w1-18 §3.11]; [w1-36 §4.6]; SCOPE §22 |
| 7 | `$mod+space` | `exec vicinae toggle` | **changed** | `exec gpuix-shell launcher toggle` (same surface, second key kept) | [w1-17]; [w1-36 §3.13] |
| 8 | `$mod+Ctrl+space` | `exec ~/.local/bin/herdr-picker` | **changed (backend)** | line unchanged tonight: `herdr-picker` keeps the rows and validation and calls `gpuix-shell dmenu` instead of `vicinae.sock` (`herdr-picker:211-267`). Once wave 3 verifies the native view the line becomes `exec gpuix-shell launcher open --view herdr` (≡ SCOPE §22's `open -q "@"` spelling, see §4.3). **INFERRED** sequencing | [w1-18 §3.7, §3.11, §5.5]; [w1-35 App. A]; [w1-36 §3.6]; SCOPE S-086 |
| 9 | `$mod+Return` | `exec ~/.local/bin/herdr-chord new` | **keep** | verbatim (flake assert) | [w1-17] |
| 10 | `$mod+Shift+Return` | `exec kitty -e fish` | **keep** | verbatim (flake assert) | [w1-17] |
| 11 | `$mod+Ctrl+Shift+Return` | `exec ~/.local/bin/herdr-chord sidebar` | **keep** | verbatim (flake assert) | [w1-17] |
| 12 | `$mod+Shift+n` | `exec ~/.local/bin/sway-workspace rename` | **changed (backend)** | line unchanged: `sway-workspace rename` → `herdr-picker --workspace rename` → `gpuix-shell dmenu --free-text --prompt "Name workspace N"` (no rows, same character rules, workspace 10 refused); the rail re-reads the name from the `herdr-name-<hex>` mark | [w1-18 §3.7, §3.11]; [w1-26] |
| 13 | `$mod+t` | `exec ~/.local/bin/sway-workspace new` | **keep** | script unchanged; rail shows the new slot | [w1-17] |
| 14 | `$mod+Shift+t` | `exec ~/.local/bin/sway-workspace restore` | **keep** | script unchanged (`herdr-closed-<ns>` mark) | [w1-17]; [w1-26] |
| 15 | `$mod+w` | `exec ~/.local/bin/sway-workspace close` | **keep** | script unchanged (close/park) | [w1-17] |
| 17 | `$mod+Shift+q` | `kill` | **keep** | — | [w1-17] |

### 2.2 Applications (`binds.conf:21-31`)

| Line | Bind | Today | Status | New target / note | Source |
|---|---|---|---|---|---|
| 21 | `Ctrl+n` | `exec google-chrome-stable` | **keep** | bare grab by request | [w1-17] |
| 22 | `Ctrl+Shift+n` | `exec google-chrome-stable --incognito` | **keep** | bare grab by request | [w1-17] |
| 23 | `$mod+n` | `exec google-chrome-stable` | **keep** | — | [w1-17] |
| 24 | `$mod+Ctrl+n` | `exec google-chrome-stable --incognito` | **keep** | — | [w1-17] |
| 25 | `$mod+e` | `exec nautilus` | **keep** | nautilus stays until `files` passes its checks (Tom 10-20 keeps the Nautilus picker); `$mod+Shift+e` opens the shell explorer (§3). **INFERRED** split | [w1-17]; [w1-18 §3.6 Files]; [w1-20 §3.1 Super+E / Super+Shift+E]; SCOPE §10 |
| 28 | `$mod+Shift+c` | `exec google-chrome-stable --app=https://claude.ai/` | **keep** | — | [w1-17]; [w1-30 §3.4] |
| 29 | `$mod+Shift+w` | `exec google-chrome-stable --app=https://mail.google.com/` | **keep** | — | [w1-17] |
| 30 | `$mod+Shift+period` | `exec google-chrome-stable --app=https://calendar.notion.so/` | **keep** | — | [w1-17] |
| 31 | `$mod+Shift+semicolon` | `exec obs` | **keep** | the rail recording dot reads `recording-toggle` / PipeWire, not OBS directly | [w1-17]; [w1-29 #60/#235]; SCOPE S-033 |

### 2.3 Clipboard, speech, screenshots, OCR (`binds.conf:34-46`)

| Line | Bind | Today | Status | New target / note | Source |
|---|---|---|---|---|---|
| 34 | `$mod+c` | `exec ~/.local/bin/colorpicker` | **keep** | its `notify-send` toast now lands in the shell daemon (swatch + hex, "Copy" action) | [w1-17]; [w1-29 #46/#237]; SCOPE S-150 |
| 36 | `$mod+Ctrl+r` | `exec ~/.local/bin/speak-clipboard` | **keep** | — | [w1-17] |
| 42 | `$mod+s` | `exec ~/.local/bin/screenshot screen` | **keep** | result toast gains "Open / Copy / Annotate / Send to agent" | [w1-17]; [w1-29 #234]; SCOPE S-148 |
| 43 | `$mod+Shift+s` | `exec ~/.local/bin/screenshot area` | **keep** | — | [w1-17] |
| 44 | `$mod+Alt+s` | `exec ~/.local/bin/screenshot window` | **keep** | — | [w1-17] |
| 46 | `$mod+Ctrl+s` | `exec ~/.local/bin/screen-ocr-area` | **keep** | result shown as a notification; also the launcher commands "OCR selection" and `ocr:last` | [w1-17]; [w1-29 #238]; [w1-30 §3.5]; SCOPE S-089 |

### 2.4 Workspaces (`binds.conf:50-90`, `input.conf:18-19`)

| Line | Bind | Today | Status | New target / note | Source |
|---|---|---|---|---|---|
| 50-59 | `workspace 1..9 output eDP-1`, `workspace 10 output eDP-2` | assignments | **keep** | rail renders slots 1–9 (eDP-1) and treats 10 (`$mod+0`) as the Chrome output | [w1-17]; [w1-26]; SCOPE S-020 |
| 60-69 | `$mod+1`..`$mod+9`, `$mod+0` | `workspace number N` | **keep** | the rail highlights the active slot from the Sway `workspace` event; rail click = `swaymsg workspace number N` | [w1-17]; [w1-26]; [w1-30 §3.3 L3e]; SCOPE S-021 |
| 70-79 | `$mod+Shift+1..9`, `$mod+Shift+0` | `move container to workspace number N` | **keep** | — | [w1-17] |
| 80 | `$mod+Up` | `workspace prev_on_output` | **keep** | — | [w1-17] |
| 81 | `$mod+Down` | `workspace next_on_output` | **keep** | — | [w1-17] |
| 82 | `$mod+Shift+Up` | move + `workspace prev_on_output` | **keep** | — | [w1-17] |
| 83 | `$mod+Shift+Down` | move + `workspace next_on_output` | **keep** | — | [w1-17] |
| 85 | `--whole-window $mod+button4` | `workspace prev_on_output` | **keep** | the rail forwards wheel events on slots to the same commands | [w1-17]; [w1-29 #17] |
| 86 | `--whole-window $mod+button5` | `workspace next_on_output` | **keep** | — | [w1-17] |
| 87 | `--whole-window $mod+Ctrl+button4` | move + prev | **keep** | — | [w1-17] |
| 88 | `--whole-window $mod+Ctrl+button5` | move + next | **keep** | — | [w1-17] |
| 89 | `--whole-window $mod+button6` | `focus left` | **keep** | — | [w1-17] |
| 90 | `--whole-window $mod+button7` | `focus right` | **keep** | — | [w1-17] |
| input.conf:18-19 | `bindgesture swipe:3:up/down` | workspace next/prev on output | **keep** | — | [w1-17]; [w1-26] |

### 2.5 Focus, move, outputs (`binds.conf:92-109`)

| Line | Bind | Today | Status | Note | Source |
|---|---|---|---|---|---|
| 92-95 | `$mod+h/j/k/l` | `focus left/down/up/right` | **keep** | `$mod+k` protected (§1) | [w1-17] |
| 96-99 | `$mod+Shift+h/j/k/l` | `move left/down/up/right` | **keep** | — | [w1-17] |
| 100-101 | `$mod+bracketleft/bracketright` | `move left/right` | **keep** | — | [w1-17] |
| 102-105 | `Alt+h/j/k/l` | `focus output left/down/up/right` | **keep** | verbatim (flake assert) | [w1-17] |
| 106-109 | `$mod+Alt+h/j/k/l` | `move workspace to output …` | **keep** | — | [w1-17] |

### 2.6 Layout and session (`binds.conf:111-127`)

| Line | Bind | Today | Status | New target / note | Source |
|---|---|---|---|---|---|
| 111 | `$mod+f` | `fullscreen toggle` | **keep** | rail hides on the output whose focused container is fullscreen | [w1-17]; [w1-29 #10]; SCOPE S-038 |
| 112 | `$mod+equal` | `fullscreen toggle` | **keep** | — | [w1-17] |
| 113 | `$mod+b` | `splith` | **keep** | — | [w1-17] |
| 114 | `$mod+v` | `exec vicinae cmd launch clipboard:history` | **changed** | `exec gpuix-shell launcher open --view clipboard`; the Vicinae spelling `gpuix-shell cmd launch clipboard:history` (SCOPE §22) is an accepted alias of the same call; image previews | [w1-17]; [w1-29 #86/#233]; [w1-35]; [w1-36 §3.13]; SCOPE S-064 |
| 115 | `$mod+Ctrl+v` | `splitv` | **keep** | — | [w1-17] |
| 116 | `$mod+Tab` | `floating toggle` | **keep** | — | [w1-17] |
| 117 | `$mod+Shift+Tab` | `focus mode_toggle` | **keep** | — | [w1-17] |
| 118 | `$mod+Ctrl+t` | `layout tabbed` | **keep** | — | [w1-17] |
| 119 | `$mod+Ctrl+Shift+s` | `layout stacking` | **keep** | — | [w1-17] |
| 120 | `$mod+Ctrl+e` | `layout toggle split` | **keep** | — | [w1-17] |
| 121-122 | `$mod+minus` / `$mod+plus` | resize ±5 ppt | **keep** | — | [w1-17] |
| 123 | `$mod+Shift+r` | `reload` | **keep** | Sway reload does not restart the shell units; `gpuix-shell reload` is separate (§7.4) | [w1-17]; [w1-21]; [w1-26 §3 theme reload] |
| 124 | `--inhibited $mod+Escape` | `seat - shortcuts_inhibitor toggle` | **keep** | — | [w1-17] |
| 127 | `$mod+Shift+p` | `exec ~/.local/bin/monitors-off` | **keep** | also a power-menu row and a launcher command | [w1-17]; [w1-26 §3]; SCOPE S-092/S-140 |

### 2.7 Function row and hardware keys (`binds.conf:139-157`)

| Line | Bind | Today | Status | New target / note | Source |
|---|---|---|---|---|---|
| 139 | `--no-repeat F2` | `$prompt theme-prompt -e theme-prompt theme` | **keep** | kitty fzf prompt stays; the launcher `t ` view (S-069) and `gpuix-shell theme <name>` are additional routes, not replacements (SCOPE §22's "after S-069" switch is not taken tonight, §8.6). PR #566's F1/F2 brightness draft is not applied (§8.5) | [w1-17]; BRIEF §3.5; SCOPE S-069 |
| 140 | `--no-repeat Shift+F2` | `$prompt theme-prompt -e theme-prompt accent` | **keep** | — | [w1-17] |
| 141 | `--no-repeat Menu` (Caps Lock via `caps:menu`) | `exec ~/.local/bin/touchpad-toggle` | **keep** | its OSD (`osd` script) now renders in the shell (§5.6); rail shows a "touchpad off" mark | [w1-17]; commit 7e082fbb; [w1-29 #49/#124]; SCOPE S-117/S-036 |
| 142 | `F3` | `media play` | **keep** | shell shows the media OSD card after the script | [w1-17]; [w1-29 #115/#125]; SCOPE S-119 |
| 143 | `F4` | `media prev` | **keep** | — | [w1-17] |
| 144 | `F5` | `media next` | **keep** | — | [w1-17] |
| 145 | `F6` | `volume mute` | **keep** | `volume` calls `osd` → daemon (§5.6) | [w1-17]; [w1-29 #122]; SCOPE S-115 |
| 146 | `F7` | `volume down` | **keep** | same | [w1-17] |
| 147 | `F8` | `volume up` | **keep** | same | [w1-17] |
| 148 | `F9` | `$prompt audio-route-prompt -e audio-route` | **changed (wave 3)** | `exec gpuix-shell controls open audio`; rows call `audio-route <sink>` so the near-silent volume lift (commit 97ef81a9) stays in the script. Until `audio-route` accepts a sink argument non-interactively the line stays as today. **INFERRED** sequencing | [w1-17]; [w1-29 #106]; [w1-30 1.5 #106]; SCOPE S-074/S-128, §22 |
| 149 | `Shift+F9` | `$prompt call-record-prompt -e call-record-menu` | **keep** | rail recording dot reflects it; moves to `gpuix-shell select` when S-090–S-092 land | [w1-17]; [w1-29 #60]; [w1-19 §3B select] |
| 150 | `F10` | `$prompt sleep-monitors-prompt -e sleep-monitors` | **keep** | on the client `sway-local.conf` `--no-warn F10 exec brightness toggle` wins (existing double bind, unchanged) | [w1-17] |
| 151 | `Shift+F10` | `$prompt pomodoro-prompt -e pomodoro menu` | **keep** | rail pomodoro item + launcher command wrap the same script | [w1-17]; [w1-29 #250]; SCOPE S-034 |
| 152-154 | `--locked XF86AudioRaiseVolume/LowerVolume/Mute` | `volume up/down/mute` | **keep** | OSD as F6–F8 | [w1-17] |
| 155-157 | `--locked XF86AudioPlay/Next/Prev` | `media play/next/prev` | **keep** | — | [w1-17] |

### 2.8 Client-only lines (`home/home.nix:149-168`, `sway-local.conf`)

| Bind | Today | Status | Note | Source |
|---|---|---|---|---|
| `--locked XF86MonBrightnessDown` / `Up` | `brightness down/up` | **keep** | `brightness` calls `osd` → daemon; the script keeps owning the hardware (Tom's #123 caveat) | [w1-17]; [w1-29 #123]; SCOPE S-116 |
| `--locked Shift+XF86MonBrightnessDown/Up` | 2 % steps | **keep** | same OSD | [w1-17] |
| `--locked XF86AudioMicMute` | `volume micmute` | **keep** | `osd mic on\|off` | [w1-17]; SCOPE S-117 |
| `--no-warn F10` | `brightness toggle` | **keep** | wins over `binds.conf:150` on the client | [w1-17] |
| `bindswitch --reload --locked lid:on/off` | eDP-1 disable/enable | **keep** | the rail is re-created when eDP-1 comes back (A-07) | [w1-17]; [w1-26 §5.2] |

---

## 3. New binds

All lines go into `binds.conf` unless noted. Every key was checked free against the 108 current
lines and against §1.

| Bind | Line to add | Status | Grounds | Source |
|---|---|---|---|---|
| `$mod+i` | `bindsym $mod+i exec gpuix-shell switcher toggle` | **new** | PR #565's `sway-workspace-switcher --output eDP-1` absorbed (row model and guards ported, fuzzel rendering gone); the switcher is the "overview" Sway lacks; opens on eDP-1 | [w1-17]; [w1-13 §switcher]; [w1-18 §3.11]; [w1-29 #27/#173]; [w1-30 1.7 #165]; SCOPE S-121 |
| `$mod+o` | `bindsym $mod+o exec gpuix-shell notifications dismiss` | **new** | PR #571 (`makoctl dismiss --all`) re-targeted to "dismiss newest", matching the `notifications-dismiss` desktop entry's wording and DESIGN §8.4 ("Mod+o dismisses the newest"); the dismissed card goes to history | [w1-17]; [w1-18 §3.3, §3.11]; [w1-30 1.3 #77]; DESIGN §8.4 |
| `$mod+Ctrl+o` | `bindsym $mod+Ctrl+o exec gpuix-shell notifications dismiss --all` | **new** | keeps PR #571's exact behaviour (history kept, never wiped) on a second key. **INFERRED** key | [w1-17]; [w1-18 §3.3 "make dismiss-all keep history"] |
| `$mod+Shift+o` | `bindsym $mod+Shift+o exec gpuix-shell notifications toggle` | **new** | notification centre / history panel (MUST #67); Hyprland-era `$mod Shift v` notifications moves here | [w1-29 #67]; [w1-17]; SCOPE §22 |
| `$mod+x` | `bindsym $mod+x exec gpuix-shell power toggle` | **new** | power menu (MUST #37/#218/#242); CUBS `Mod+Shift+Escape` moves here; SCOPE §22's `$mod+Shift+e` for power is overridden (§8.6) | [w1-29 #218]; [w1-27]; [w1-28]; [w1-10]; night brief |
| `$mod+Shift+e` | `bindsym $mod+Shift+e exec gpuix-shell files open` | **new** | Pinax-like explorer in an ordinary Sway window (BRIEF §3.2); Pinax's own Super+Shift+E = "another window"; a second press opens a second window (one process per window) | [w1-20 §3.1]; BRIEF; SCOPE §10; DESIGN §8 |
| `$mod+Shift+slash` | `bindsym $mod+Shift+slash exec gpuix-shell cheatsheet toggle` | **new** | hotkey cheat sheet rendered from `sway/binds.conf` (+ this file's new lines) by the switcher process (DMS "hotkeys visualizations", gap G9); Sway resolves the shifted keysym, `$mod+question` is the equivalent spelling | [w1-30 G9, §3.5]; [w1-17]; [w1-19 §3D keybinds]; SCOPE §11, §22 |
| `$mod+grave` | `bindsym $mod+grave exec ~/.local/bin/herdr-context toggle` | **new** | kitty ⇄ Chrome swap from branch `herdr-sway-context` (c1a49b99); wins over CUBS "Mod+Grave rail collapse" and Hyprland-era "windows" (§8.5) | [w1-17]; [w1-10] |
| `$mod+Shift+grave` | `bindsym $mod+Shift+grave exec gpuix-shell rail toggle` | **new** | rail hide/show on the focused output ("toggle bars with a keybind", MUST #9/#20; one verb, one bar). **INFERRED** key | [w1-29 #9/#12/#20]; [w1-30 §3.3 L1c, G8]; SCOPE S-037 |
| `$mod+comma` | `bindsym $mod+comma exec gpuix-shell controls toggle` | **new** | per-domain menus (wifi / bluetooth / audio / tailscale / battery / DND / input); Hyprland-era `$mod comma` controls and CUBS `$mod+Comma` settings land here. **INFERRED** key | [w1-17]; [w1-10]; [w1-30 1.12]; SCOPE §6 |
| `$mod+Ctrl+w` | `bindsym $mod+Ctrl+w exec gpuix-shell controls open wifi` | **new** | direct door to the wifi menu Tom asked for ("wifi menu … bluetooth pairing menu"); SCOPE §22's INFERRED key adopted | BRIEF §1; SCOPE §22, S-126 |
| `$mod+Ctrl+b` | `bindsym $mod+Ctrl+b exec gpuix-shell controls open bluetooth` | **new** | direct door to the bluetooth pairing menu; SCOPE §22's INFERRED key adopted | BRIEF §1; SCOPE §22, S-127 |
| `$mod+m` | `bindsym $mod+m exec gpuix-shell launcher open --view music` | **new (proposed, not activated)** | Navidrome music view; `$mod+m` free since the 2026-10-12 SoundCloud removal; activated when the music lane passes its smoke | ASSUMPTIONS (music UX spec 05); SCOPE §22 |
| `$mod+Shift+m` | `bindsym $mod+Shift+m exec gpuix-shell music now` | **new (proposed, not activated)** | now-playing view; PR #565's desk-at-8443 bind on the same key is re-keyed to `$mod+Ctrl+m` if that PR merges (§8.5). **INFERRED** | ASSUMPTIONS (music); [w1-17] |
| `$mod+a` | `bindsym $mod+a exec gpuix-shell ask toggle` | **new (reserved, not activated)** | the exploratory OpenUI prompt (BRIEF §3.7, §5); bound only when the `ask` surface ships (S-200). **INFERRED** | BRIEF; [w1-24 §5.8, A1]; [w1-29 #247] |
| F-keys → OSD | no new `bindsym` | **changed (script)** | `osd` (home/dot_local/bin/osd) keeps its `notify-send -p -t 1500 -a osd -r <id> -h int:value:N` contract, which the daemon routes to the OSD window (`app_name == "osd"`); a later edit may call `gpuix-shell osd <kind> <value>` directly, falling back to `notify-send` when the socket is absent | [w1-18 §3.1, G4, G5]; [w1-19 §3C OSD]; [w1-29 #122/#123]; [w1-30 1.5 #122/#132]; SCOPE §4 |
| rail click map | no `bindsym` | **new** | see §6 | [w1-30 §3.3]; DESIGN §8.1 |
| lock | none | **not bound** | no locker is installed (no swaylock/gtklock/hyprlock in any `.nix`); `power` hides Lock until one exists; `gpuix-shell lock` exits 69; "lock is a verb, unlock is not" | [w1-10 T9]; [w1-18 G12]; [w1-19 §3B lock]; [w1-30 G10]; [w1-29 #203] |
| DND toggle | none | **not bound** | DND lives in the rail bell (right click), the controls menu, the launcher command "Do not disturb" and `gpuix-shell notifications dnd on\|off\|toggle`; no key tonight. **INFERRED** | [w1-29 #71]; SCOPE S-105/S-133 |

Sway binds that remain unreferenced on purpose: `$mod+K` (rule), F1 (PR #566 draft, not applied),
`$mod+Shift+Escape` and `$mod+Ctrl+l` (CUBS, not carried), `$mod+Ctrl+d` and `$mod+Shift+v`
(Hyprland-era launcher/notifications, not reused).

---

## 4. The launcher

Surface: overlay layer, keyboard exclusive, 700×580, top margin 108, eDP-1 (BRIEF §3.3; DESIGN §8.2).
Opens with `gpuix-shell launcher toggle|open [--view <id>] [-q|--query <text>]`; `Esc` navigates back
then closes at the root (`escape_key_behavior`), `Backspace` on an empty query pops
(`pop_on_backspace`), `pop_to_root_on_close` is on, focus loss closes [w1-29 #103]; [w1-36 §3.8];
SCOPE S-050. Root list = favourites (Tom's order: `applications:herdr-picker`, `clipboard:history`,
`browser-extension:browse-tabs`, `media:now-playing`, `core:search-tray`) / frecency / commands /
apps, fallbacks `files:search` and calculator; Raycast list layout, no grid at root [w1-29 #90-#94];
[w1-36 §3.8]; SCOPE S-051/S-052. `=` rows appear inline at the top like Vicinae's link/calculator
row [w1-35 §3.4].

### 4.1 Prefixes and providers

Single-character sigils act at column 0; word keywords need a trailing space (Raycast alias style).
The sigil set is the one named in the night brief (`>` `=` `:` `@` `#` `w`); precedents: gpui-shell
(`@ $ ! ;ws ~ ;s ?`) [w1-23 §launcher], herdr-bar (`@ % $ !`) [w1-23], caelestia's eight modes
[w1-30 1.4 #100], Vicinae's provider ids [w1-35], [w1-36 §4.2 Decision 4]. The grammar is
**INFERRED**; SCOPE S-053 and DESIGN §8.2 spell three sigils differently, resolved in §4.3.

| Prefix | Provider / view id (Vicinae id kept) | What it lists | Status | Source |
|---|---|---|---|---|
| *(none)* | `apps` + favourites + frecency + commands | XDG `.desktop` entries incl. the 11 PWA entries, pinned items, native commands; hide-list from config | replaces Vicinae root search | [w1-29 #83/#90/#102]; [w1-30 §3.4]; SCOPE S-051/S-060 |
| `>` | `commands` (`cmd:*`) | shell command execution with live output (Vicinae script-command modes fullOutput/compact/silent/terminal/inline kept); also every registered native command and `gpuix-shell` verb | new | [w1-29 #99]; [w1-23 caelestia `>`]; [w1-36 §3.7]; SCOPE S-061 |
| `=` | `calc` (`calculator:*`) | pure-TS calculator (units, %, hex/bin, basic dates), inline result row, Enter copies; history 20 | replaces Vicinae calculator | [w1-29 #84]; [w1-35]; SCOPE S-066 |
| `:` (alias `/`) | `files` (`files:search`) | `fd`-backed file search over ~/Downloads, ~/Documents, ~ (hidden off), category filter; Enter opens, action panel: open in `files`, copy path, reveal | replaces Vicinae files (no indexer) | [w1-29 #85]; [w1-30 1.4 #85]; SCOPE S-065 |
| `@` | `windows` (`wm:switch-windows`) | Sway `get_tree` leaves (title, app_id, workspace, output, herdr slot); Enter = `swaymsg [con_id=N] focus`; actions close / move to workspace | new (better than Vicinae's transient ids) | [w1-26]; [w1-23 gpui-shell `@`]; [w1-36 §3.2 WindowManagement]; SCOPE S-062 |
| `#` (alias `h `) | `workspaces` (`applications:herdr-picker`) | Sway workspaces 1–10 with herdr status glyph (◉ ◐ ● ✓ ○), projector slot, seat, running time, MRU + fuzzy; Enter = `swaymsg workspace number N`; actions rename / restore / close (confirm) / open sidebar via `sway-workspace` and `herdr-chord` | replaces the `herdr-picker` desktop entry | [w1-18 §3.7]; [w1-35 App. A]; [w1-26]; [w1-30 §3.3 L4]; SCOPE S-063 |
| `w ` | `wifi` (`network:*`) | NetworkManager: radio toggle, known networks first, scan list with strength/security/band/BSSID, connect (password form, SECRET class, never over the socket), disconnect, forget (confirm), hidden SSID, airplane mode | replaces `fzf-nmcli` and the `network-settings` nmtui entry | [w1-29 #133-#147]; [w1-30 1.6]; SCOPE S-072/S-126/S-136 |
| `bt ` | `bluetooth` (`bluetooth:*`) | BlueZ: power, discoverable, scan (RSSI order), paired/connected sections, connect, pair (Agent1 PIN/passkey/confirm sheet), forget (confirm), battery % | new (no Bluetooth UI exists today) | [w1-29 #148-#157]; SCOPE S-073/S-127 |
| `em ` | `emoji` (`emoji:*`) | emoji & symbols, skin tones, recents, grid view; Enter copies (+ paste when `wtype` is present) | replaces Vicinae emoji | [w1-29 #87]; SCOPE S-068/S-147 |
| `m ` (alias `♪`) | `music` | Navidrome: search (Top result · Songs · Artists · Albums · Playlists), library, queue, now playing; `♪` is not typeable, `m ` is its keyboard spelling | new | ASSUMPTIONS (music UX spec 05); BRIEF §5; SCOPE S-085 |
| `t ` | `theme` (`theme:set`) | `noir`, `claude-dark`, `claude-light` → `~/.local/bin/theme <name>`; accent sub-list → `theme-prompt accent` logic | new (Vicinae `theme set` dropped) | BRIEF §3.5; [w1-36 §3.6]; SCOPE S-069 |
| `n ` | `notifications` | history rows; Enter invokes the default action, action panel: dismiss, restore, copy body, open app | replaces `makoctl list/history` entries | [w1-18 §3.3]; SCOPE S-078 |
| `tabs ` | `browser-extension:browse-tabs` | Chrome tabs through the published extension `kcmipingpfbohfjckomimmahknoddnke` and the shell's own native host registered as `com.vicinae.vicinae`; Enter focuses the tab **and** workspace 10; actions close, copy url | parity with Vicinae (T14) | [w1-35]; [w1-36 §3.11, §4.6]; SCOPE S-067 |
| `tray ` | `core:search-tray` | SNI items (LATER; lists nothing tonight) | parity stub | [w1-29 #29]; SCOPE §12 |
| `?` | `cheatsheet` | this map, filterable; same data as `$mod+Shift+slash` | new | SCOPE S-053, §11 |

Views reachable by `--view` without typing a prefix: `clipboard` (Mod+v), `herdr` (= `workspaces`,
Mod+Ctrl+space), `music` (Mod+m), `wifi`, `bluetooth`, `audio`, `emoji`, `files`, `windows`,
`workspaces`, `theme`, `notifications`, `tabs`, `power`, `cheatsheet`. Vicinae's `provider:entrypoint`
ids are accepted as aliases (`gpuix-shell cmd launch clipboard:history` ≡ `launcher open --view
clipboard`) [w1-36 §4.2 Decision 4]; SCOPE S-061.

Native commands registered in the root list (replace the `home/vicinae.nix` desktop entries, §8.3):
"Herdr workspaces", "New Herdr workspace", "Restore Herdr workspace", "Rename workspace", "Dismiss
notification", "Restore notification", "Do not disturb on/off", "Network (wifi menu)", "Network
settings (nmtui)" (kept as the fallback), "Bluetooth", "Audio output", "Brightness", "Theme: noir /
claude-dark / claude-light", "Power menu", "Monitors off", "Sleep monitors", "Pomodoro", "OCR
selection", "OCR: last result", "Colour picker", "Screenshot: screen / area / window", "Recording
toggle", "Rail: collapse / expand / hide", "Cheat sheet", "Ask" (when S-200 ships), "Tailscale peers",
"Caffeine" (P2).

### 4.2 Launcher keymap

Base: Raycast's map with ⌘→Ctrl and ⌥→Alt, Vicinae's keybind ids kept so `Keyboard.Shortcut.Common`
names resolve [w1-36 §3.8, §4.1]; ASSUMPTIONS (music). The keybinding profile is a config value
(`keybinding = default|vim|emacs`, Vicinae's key); `default` is the shipped profile [w1-36 §3.8]; SCOPE
S-054. Inside the surface Super arrives as `cmd` but Sway owns every `$mod` chord, so no row uses it
[w1-15 §3.10].

| Key | Action | Status | Source |
|---|---|---|---|
| `Enter` | primary action (first action of the first section; armed cap in the footer shows it) | keep (Vicinae) | [w1-35 §3.4]; [w1-36 §4.1] |
| `Shift+Enter` | second action (music: play and close) | keep | [w1-36 §4.1]; ASSUMPTIONS (music) |
| `Ctrl+Enter` | tertiary action / open / drill-down; **submit** in forms | keep | [w1-36 §4.1]; ASSUMPTIONS (music UX spec 05); DESIGN §8.2 |
| `Esc` | navigate back; closes at root (`escape_key_behavior = navigate_back`) | keep | [w1-36 §3.8]; [w1-09 §4a] |
| `Backspace` on empty query | pop the view (`pop_on_backspace`) | keep | [w1-36 §3.8] |
| `Tab` | complete arguments / next field (≤ 3 inline arguments) | keep | [w1-35]; [w1-36 §4.1] |
| `Up`/`Down` | move selection, wraps at the ends | keep | [w1-35]; DESIGN §8.2 |
| `Ctrl+J`/`Ctrl+K` move, `Ctrl+U`/`Ctrl+D` page | only under the `vim` profile (off by default), where `Ctrl+K` therefore does **not** open the action panel. **INFERRED** profile split | changed vs rev 1 | [w1-23 gpui-shell]; [w1-36 §3.8 `keybinding`]; June 27 spec via [w1-30 §5] |
| `Ctrl+B` | action panel (Vicinae `toggle-action-panel`) | keep | [w1-36 §3.8, §4.1]; SCOPE S-054 |
| `Ctrl+K` | action panel (Raycast habit), default profile only | new | ASSUMPTIONS (music); DESIGN §8.2 |
| `Ctrl+Tab` | action panel (AM #96 "Action panel (Ctrl+Tab)"; SCOPE's INFERRED alias) | new | [w1-29 #96]; SCOPE S-054 |
| `Ctrl+P` | scope / provider dropdown (`open-search-filter`); never cursor-up (music ASSUMPTIONS: "Ctrl+P = scope") | keep | [w1-36 §3.8]; ASSUMPTIONS (music UX spec 05); DESIGN §8.2 |
| `Ctrl+Shift+P` | pin / unpin (`action.pin`) | keep | [w1-36 §3.8]; SCOPE S-052 |
| `Ctrl` held 250 ms + `1..9`, `0` / `Ctrl+1..9` | quick-access favourites | keep | [w1-35]; DESIGN §8.2 |
| `Ctrl+Alt+1..9` | desktop actions of the selected app | keep | [w1-35] |
| `Ctrl+Shift+1..9` | browse-apps actions | keep | [w1-35] |
| `Ctrl+Shift+C` | copy result (`action.copy`) | keep | [w1-36 §3.8] |
| `Ctrl+Shift+.` / `Ctrl+Shift+,` | copy name / copy path | keep | [w1-36 §3.8] |
| `Ctrl+O` | open (`action.open`); `Ctrl+Shift+O` open with | keep | [w1-36 §3.8]; [w1-35] |
| `Ctrl+S` save, `Ctrl+D` duplicate, `Ctrl+N` new (forms and lists with a "new" action) | keep | [w1-36 §3.8] |
| `Ctrl+Shift+Up`/`Down` | move item up / down (pins, queue) | keep | [w1-36 §3.8] |
| `Ctrl+R` | refresh provider | keep | [w1-36 §3.8] |
| `Ctrl+X` remove, `Ctrl+Shift+X` dangerous remove (two-step confirm, red) | keep | [w1-36 §3.8]; [w1-23 herdr-bar two-step]; SCOPE S-059 |
| `Ctrl+E` edit, `Ctrl+Shift+E` edit secondary | keep | [w1-36 §3.8] |
| `Ctrl+Shift+F` | favourites | keep | [w1-35] |
| `Ctrl+Q` | close window | keep | [w1-35] |
| `Ctrl+,` | settings | **retired** (no settings GUI; AM #174 vs #200, gap G6) | [w1-29 #174]; [w1-30 G6] |
| `Ctrl+I` | detail pane toggle (`isShowingDetail`) | new | ASSUMPTIONS (music); [w1-36 §3.1] |
| `Ctrl+=` / `Ctrl+-` / `Ctrl+0` | UI zoom 0.8–1.6 / reset (GPUIX has none; Tom's 10-13 complaint) | new | [w1-15 G8]; SCOPE S-043 |
| `Ctrl+Right`/`Left`, `Ctrl+Up`/`Down` | music next / previous (Spotify rule), player volume | new (music view) | ASSUMPTIONS (music) |
| `Alt+P`, `Alt+S`, `Alt+R`, `Alt+N`, `Alt+L`, `Ctrl+L`, `Ctrl+G`, `Ctrl+Shift+S` | add to playlist, shuffle, repeat, play next, like current, like, go to artist, shuffle play | new (music view) | ASSUMPTIONS (music) |
| Clipboard view: `Enter` copy + close (+ paste via `wtype` when present), `Ctrl+Shift+C` copy only, `Ctrl+X` delete entry, `Ctrl+Shift+P` pin, `Ctrl+Shift+X` clear history (two-step), kind dropdown on `Ctrl+P` | — | new, mirrors Vicinae clipboard actions | [w1-35]; [w1-29 #86]; SCOPE S-064/S-147 |
| Form views: `Ctrl+Enter` submit, `Tab`/`Shift+Tab` fields, `Esc` discards (drafts off) | — | keep (Vicinae) | [w1-36 §3.1 Form] |
| dmenu mode (`gpuix-shell dmenu`): `Enter` select, `Esc` dismiss (exit 1), typed text with no rows = free text only with `--free-text` | — | keep (Vicinae dmenu) | [w1-18 §5.5]; [w1-36 G17] |

### 4.3 Where SCOPE S-053 / DESIGN §8.2 spell a prefix differently (KEYS rules; **INFERRED**)

| Sigil | SCOPE / DESIGN | KEYS (this file) | Why |
|---|---|---|---|
| `:` | emoji | **files** (`em ` = emoji) | the night brief names `:` files; `em ` keeps emoji one keyword away |
| `/` | files (SCOPE) / provider picker (DESIGN) | alias of `:` files | both spellings reach files; the provider picker is `Ctrl+P` |
| `@` | herdr workspaces | **windows** (`#` = workspaces, with the herdr glyphs) | the brief names `@` windows, `#` workspaces; SCOPE §22's `open -q "@"` for Mod+Ctrl+space therefore reads `open --view herdr` here |
| `?` | cheatsheet | same | adopted |
| `♪` / `m:` | music | `m ` (alias `♪`) | `♪` is not typeable on the Glove80 or the Duo |
| `w`, `bt`, `t`, `n`, `tabs`, `tray` | — | word prefixes | the brief names `w` wifi; the rest follow the same shape |

---

## 5. Other surface keymaps

### 5.1 Switcher (`$mod+i`, eDP-1, PR #565 shape: text + herdr status, no thumbnails tonight)

| Key | Action | Source |
|---|---|---|
| type | fuzzy filter over slot number, workspace name, agent label | [w1-17 PR #565]; [w1-13 §switcher]; [w1-23 herdr-bar]; SCOPE S-121 |
| `1..9`, `0` | focus that workspace and close (`swaymsg workspace number N`, verify after switch; refuse on drift) | [w1-26]; [w1-13] |
| `Up`/`Down`, `j`/`k` (query empty), `Ctrl+N`/`Ctrl+P` | move | [w1-23]; SCOPE S-121 |
| `Enter` | focus selected (Sway only, never `herdr workspace focus`) | [w1-26]; [w1-16] |
| `$mod+i` again while open | second press closes (process per show); P1: holding Mod and repeating `i` cycles MRU slots, release commits (S-122, INFERRED there) | [w1-15 G1]; SCOPE S-122; DESIGN §8.3 |
| `!` as first char | only blocked / needs-you slots | [w1-23 herdr-bar `!`] |
| `Ctrl+O` | preview pane (herdr snapshot detail) | [w1-23] |
| `Ctrl+B` | row actions: rename, restore, close (confirm), move focused window here, open herdr sidebar (all via existing scripts) | SCOPE S-123; [w1-17] |
| `Ctrl+R` | rename → `sway-workspace rename` | [w1-23]; [w1-17] |
| `Esc` | close | — |

### 5.2 Notification centre (`$mod+Shift+o`; rail bell)

| Key | Action | Source |
|---|---|---|
| `Up`/`Down`, `j`/`k` | move; groups collapse per app | [w1-29 #68/#77] |
| `Enter` | invoke default action (`notifications invoke <id>`) | [w1-18 §3.3] |
| `1..9` | invoke the n-th action button of the selected notification | [w1-29 #69]; [w1-18 G8 actions kept for `herdr-attention`] |
| `d` / `Shift+D` | dismiss selected / dismiss all (history kept) | [w1-18 §3.3] |
| `u` | restore last dismissed (`makoctl restore`) | [w1-18] |
| `f` | DMS-style letter hints over visible toasts, then a letter selects | [w1-29 #77]; [w1-30 G7]; DESIGN §8.4 |
| `n` | DND toggle | [w1-29 #71]; SCOPE S-105 |
| `Tab` | Current ⇄ History (DMS) | [w1-29 #67] |
| `Ctrl+Shift+X` | clear history (two-step; separate from dismiss-all) | [w1-18 §3.3] |
| `Esc` | close | — |

### 5.3 Power menu (`$mod+x`; DMS shape: scrollable list **and** press-and-hold with a visible progress fill, Tom MUST)

| Key | Row | Source |
|---|---|---|
| `Up`/`Down`, `j`/`k`, wheel | move through the list | [w1-27]; [w1-28]; [w1-29 #37/#218] |
| hold `Enter` or the row letter ~1 s | fill completes → action fires; releasing early cancels (this hold is the confirmation, AM #222) | [w1-29 #218/#222]; [w1-30 §3.2 Session]; SCOPE S-140 |
| `m` | Monitors off (`monitors-off`) | [w1-17 binds.conf:127]; [w1-26 §3] |
| `z` | Sleep monitors (`sleep-monitors`) | SCOPE S-140 |
| `s` | Suspend (`systemctl suspend`), shown only when enabled in config (BRIEF: "not implementing real sleep"; logind `Suspend` ruled out by default) | [w1-26 §3 power]; [w1-29 #218]; SCOPE S-140 |
| `h` | Hibernate, shown only when `/sys/power/state` lists `disk` (no swap today → hidden); `Shift+H` suspend-then-hibernate | [w1-29 #219/#220]; [w1-26 lid.nix] |
| `r` | Reboot (`systemctl reboot`) | [w1-29 #218] |
| `p` | Power off (`systemctl poweroff`) | [w1-29 #218] |
| `e` | Exit Sway / logout (`swaymsg exit`) | [w1-29 #223]; [w1-30 1.9 #223] |
| `l` | Lock — hidden until a locker is installed (**INFERRED**) | [w1-18 G12]; [w1-30 G10] |
| `Esc` | close | — |

The footer shows uptime, battery and the herdr blocked count ("2 slots need input") before a logout
(SCOPE S-142). No Sway bind fires these actions directly; the CLI needs `--yes` (§7.6).

### 5.4 Controls (`$mod+comma`; `controls open wifi|bluetooth|audio|tailscale|battery|input`)

Per-domain menus, not a tile grid (control-centre WONT vs BRIEF `controls`, chosen: menus; "one domain
list at a time") [w1-29 §1.12, G1]; [w1-30 1.12]; [w1-19 §2]; SCOPE §6. Grammar "left = toggle, right =
detail, scroll = cycle" [w1-30 1.12 C13].

| Key | Action | Source |
|---|---|---|
| `Left`/`Right`, `h`/`l`, `Tab` | switch domain (wifi, bluetooth, audio, brightness, media, battery/profile, tailscale, DND/caffeine, input) | [w1-30 1.12]; SCOPE S-126–S-136 |
| `Up`/`Down`, `j`/`k` | move within the list | — |
| `Enter` | connect / pair / select / set default sink / pick exit node (confirm) | [w1-29 #133-#151, #106]; SCOPE S-126/S-127/S-128/S-135 |
| `Space` | toggle radio / power / discoverable / DND / caffeine / airplane | [w1-29 #136/#148/#71/#146] |
| `f` | forget network / device (two-step) | [w1-29 #137/#151] |
| `+` / `-`, wheel | volume / brightness / music volume ± | SCOPE S-128/S-129 |
| `Ctrl+R` | rescan | — |
| `Esc` | close (password / passkey prompt: Esc cancels, never submits) | [w1-30 §3.2 Network SECRET]; [w1-29 §4 16] |

### 5.5 Files (`$mod+Shift+e`, Pinax key set carried as-is [w1-20 §3.1]; DESIGN §8.7)

`Enter` open, `Backspace`/`Alt+Up` up, `Alt+Left`/`Right` history, `Home`/`End`/`PgUp`/`PgDn`, arrows
(grid moves by columns), typing jumps to a name (800 ms buffer), `Space` preview column, `Ctrl+B` rail,
`Ctrl+L` path field (`~` expands), `Ctrl+1/2/3` list/grid/gallery, `Ctrl+H` hidden files, `Ctrl+Shift+N`
new folder, `Ctrl+Alt+N` new file, `Ctrl+Shift+F` deep search (`fd`), `F2` rename (many → sheet),
`Delete` trash (gio, with Undo) / `Shift+Delete` delete for good (sheet, Enter = safe button),
`Ctrl+C`/`X`/`V`/`Z`, `Ctrl+Shift+C` copy path, `Ctrl+Shift+T` terminal here (kitty), `Ctrl+Shift+S`
send to, `Ctrl+W` close window, `Ctrl+=`/`-`/`0` grid zoom (shell-implemented), `Esc` ladder (stop
job → dismiss offer → cancel cut → close preview → clear filter → clear selection → nothing). Every
key is also reachable as `gpuix-shell files act <name>` [w1-20 §3.1 "perform()"].

### 5.6 OSD (no keys of its own)

Rendered by the notifications process, bottom-centre margin 96, 280×56 (DESIGN §8.5; SCOPE §4);
suppressed while the launcher or controls are open [w1-29 #129]. Kinds: `volume`, `brightness`,
`mic`, `caps`, `touchpad`, `media`, `audio-route`, `hud` (launcher `showHUD`) [w1-29 #122-#126];
[w1-30 §3.2 OSD]; [w1-19 §3D OSD]; SCOPE S-115–S-119. The `osd` script's contract (`notify-send -p
-t 1500 -a osd -r <id> -h int:value:<pct>`) is honoured by the daemon (`app_name == "osd"` routes to
the OSD window, never a 140 px toast), so `volume`, `brightness`, `touchpad-toggle` and `audio-route`
work before they are touched [w1-18 §3.1, G4, G5]. Toast anchor: SCOPE §3 and [w1-18 G1] say
top-centre (Tom 2026-10-11), DESIGN A-15 / BRIEF §3.3 say top-right with `layout.toast.anchor` as a
config value; no key depends on it (logged, §8.5).

### 5.7 Cheat sheet (`$mod+Shift+slash`, launcher `?`)

Read-only overlay rendered from `sway/binds.conf` (+ `sway-local.conf` on the client + this file's new
lines); type to filter, `Esc` closes. Rendered by the switcher process [w1-30 G9]; `gpuix-shell cheatsheet
lint` fails when a bind in `binds.conf` has no row in this file (SCOPE §11; [w1-19 §3D keybinds]).

### 5.8 Ask (`$mod+a`, reserved; `gpuix-shell ask [TEXT]`)

Overlay, keyboard exclusive, off the critical path (BRIEF §3.7; [w1-24 §5.8]). `Enter` sends,
`Shift+Enter` newline, `Esc` closes (streaming is cancelled), `Ctrl+C` copies the answer, `Ctrl+Shift+C`
copies the OpenUI tree, `Ctrl+Enter` runs the single validated action, `Ctrl+L` clears. Model output
is rendered, never executed; actions are a closed vocabulary validated before dispatch (the agent-RCE
firewall, [w1-30 §4.1 10]; [w1-24 §5.8]). **INFERRED** key set.

---

## 6. Rail pointer map (no `bindsym`; no tooltips, popovers or menus on the rail, U-11 / DESIGN §8.1)

| Target | Left click | Right click | Middle / wheel | Source |
|---|---|---|---|---|
| Anthropic mark (top) | `launcher toggle` | — | — | SCOPE S-040; [w1-30 1.2 #38] |
| slot 1–9 | `swaymsg workspace number N` | `switcher toggle` | wheel = prev/next on output (same as `binds.conf:85-86`) | [w1-30 §3.3 L3e]; [w1-29 #17]; SCOPE S-021 |
| herdr status dot on a slot | focus slot | `launcher open --view herdr` | — | [w1-26]; SCOPE S-022 |
| bell | `notifications toggle` | `notifications dnd toggle` | — | [w1-29 #35/#71]; SCOPE S-030 |
| wifi | `controls open wifi` | radio toggle (`nmcli radio wifi`) | — | [w1-29 #31]; SCOPE S-027 |
| bluetooth | `controls open bluetooth` | power toggle | — | [w1-29 #32]; SCOPE S-028 |
| volume | `controls open audio` | `volume mute` | wheel = `volume up/down` | [w1-29 #33/#18]; SCOPE S-029 |
| media / now-playing chip (expanded) | `launcher open --view music` (or the active player's view) | — | middle = play/pause; wheel = music volume (no popover: music ASSUMPTIONS X1) | [w1-29 #34/#116]; ASSUMPTIONS (music UX spec 05); SCOPE S-035 |
| tailscale | `controls open tailscale` | — | — | [w1-29 #41/#144]; [w1-30 G1]; SCOPE S-031 |
| battery | `controls open battery` (UPower detail, power profile) | — | — | [w1-29 #30]; SCOPE S-026/S-131 |
| clock | — (date only; no calendar grid, AM #240) | — | — | [w1-29 #28/#240] |
| recording / privacy dots | read-only (stop lives in the launcher) | — | — | [w1-29 #39/#60]; SCOPE S-032/S-033 |
| touchpad-off mark | `touchpad-toggle` | — | — | SCOPE S-036 |
| pomodoro | `launcher open --view pomodoro` (wraps `pomodoro menu`) | — | — | [w1-29 #250]; SCOPE S-034 |
| custom button | per-config command per button (click / right / middle / scroll-up / scroll-down) | per-config | per-config | [w1-29 #58]; SCOPE S-039 |
| power glyph (bottom) | `power toggle` | — | — | [w1-29 #37] |

---

## 7. CLI verbs: `gpuix-shell <surface|domain> <verb> [args]`

### 7.0 Grammar, framing, placement

- Canonical shape per SCOPE S-002: `gpuix-shell <surface> <verb> [args]` (`launcher toggle`,
  `notifications dismiss --all`, `rail toggle --output eDP-1`). The night brief's `gpuix-shell toggle
  <surface>` and the bare `gpuix-shell <surface>` (= toggle) are accepted aliases. One shape, three
  spellings; the socket method is always `<Surface>/<verb>`. **INFERRED** reconciliation.
- Socket `$XDG_RUNTIME_DIR/gpuix-shell/shell.sock`, 4-byte native-endian length + JSON-RPC 2.0 (the
  framing `herdr-picker:211-258` already speaks), replies keyed by (connection, id) [w1-36 §4.6]; [w1-18
  §5.5]. `--json` on every READ verb; `--check-native`, `--check-dbus`, `--check-theme <file>` are
  pre-socket self-checks used by the Nix install check [w1-21 §5.1].
- `toggle` on a process-per-show surface spawns the surface or kills the running one; `open` is
  idempotent; `close` kills; `state` exits 0 when open (Vicinae `state open`) [w1-15 G1]; [w1-36 §3.6].
- Overlay surfaces run `swaymsg focus output eDP-1` before spawning (A-07) and never move focus after.

### 7.1 Surfaces

| Verb | Args | Class | Status | Source |
|---|---|---|---|---|
| `launcher toggle\|open\|close\|state` | `[--view <id>] [-q\|--query <text>]`; `--view` ids in §4.1; `-q` = DMS `spotlight openQuery` | WRITE-rev | new | SCOPE S-050; [w1-30 §3.2 Launcher]; [w1-36 §3.6] |
| `switcher toggle\|open\|close` | `[--output <name>]` default eDP-1 | WRITE-rev | new | [w1-17 PR #565]; SCOPE S-121 |
| `notifications toggle\|open\|close` | the centre | WRITE-rev | new | [w1-29 #67]; SCOPE §3 |
| `controls toggle\|open\|close` | `open <wifi\|bluetooth\|audio\|brightness\|media\|battery\|tailscale\|dnd\|input>` | WRITE-rev | new | [w1-19 §3D]; SCOPE §6 |
| `power toggle\|open\|close` | the menu only | WRITE-rev | new | [w1-29 #218]; SCOPE §7 |
| `files open [<path>] [--select <path>]`, `files pick [--multiple] [--dirs]`, `files act <name>` | ordinary window; `pick` prints paths (Vicinae `Form.FilePicker`, `Action.ShowInFinder`) | WRITE-rev | new | [w1-20 §3.1]; [w1-19 §3D files]; [w1-36 §4.5]; SCOPE §10 |
| `cheatsheet toggle\|lint` | `lint` = every bind has a row here (READ) | WRITE-rev / READ | new | SCOPE §11; [w1-19 §3D] |
| `ask [TEXT]`, `ask toggle\|close` | exploratory | WRITE-rev | new (S-200) | [w1-24 §5.8] |
| `rail toggle\|show\|hide\|collapse\|expand\|reload\|status [--output <name>]` | one verb touches one bar; `collapse`/`expand` relaunch at 56/220 | WRITE-rev / READ | new | [w1-29 #12/#20]; [w1-30 G8]; SCOPE S-037 |
| `gallery open` | component gallery in three themes (storybook wish) | WRITE-rev | new (should) | [w1-19 §3B gallery]; [w1-30 §4.1 14] |
| `<surface> ui-tree` | dump the retained tree for tests | READ | new | SCOPE S-010 |
| `toggle\|show\|hide <surface>` | aliases of the rows above (night brief spelling) | — | alias | night brief; [w1-10 CUBS] |

### 7.2 Notifications and OSD (mirrors makoctl [w1-18 §3.3]; the D-Bus name is unchanged, so `notify-send` keeps working)

| Verb | Args | makoctl / Vicinae equivalent | Status |
|---|---|---|---|
| `notify <summary> [body] [-a app] [-u low\|normal\|critical] [-t ms] [-r id] [-h key:type:value] [-i icon] [-p]` | send one; `-p` prints the id | `notify-send` | new (convenience; same bus) |
| `notifications dismiss [--all] [--no-history] [<id>]` | newest, or all; `--all` keeps history | `makoctl dismiss [-a] [-n]` | new |
| `notifications dismiss-all`, `notifications restore-last`, `notifications invoke-last` | aliases (SCOPE §22 / [w1-19 §3D] spellings) | — | alias |
| `notifications restore` | bring back the last dismissed | `makoctl restore` | new |
| `notifications invoke <id> [action]` | fire an action (ACTION class) | `makoctl invoke` | new |
| `notifications list [--json]` / `history [--json]` / `count` | the smoke test greps `list` for the summary | `makoctl list -j` / `history -j` | new |
| `notifications clear-history` | wipes history (two-step in the UI, `--yes` on the CLI) | none (mako's `dismiss --all` keeps history) | new |
| `notifications dnd on\|off\|toggle\|status` | — | `makoctl mode` | new |
| `notifications privacy on\|off` | hide bodies on toasts | — | new (P2) |
| `notifications reload` | re-read rules and theme fragment | `makoctl reload` | new |
| `toast <info\|warn\|error> <text> [--action "label=cmd"]{0,2}` | shell-originated toast | DMS `toast` | new |
| `dismiss [--all]` | top-level alias of `notifications dismiss` | — | alias |
| `osd <volume\|brightness\|mic\|caps\|touchpad\|media\|audio-route\|hud> [value\|on\|off\|text]` | §5.6 kinds | the `osd` script | new |
| `osd show --icon <id> --label <text> [--value n]` | generic card for scripts that skip `notify-send` | Noctalia `osd-show` | new (S-119) |
| `osd suppress on\|off` | force-quiet while a prompt is up | — | new, later |

### 7.3 Clipboard, dmenu and select

| Verb | Args | Replaces | Status | Source |
|---|---|---|---|---|
| `clipboard ingest` | called by `wl-paste --watch gpuix-shell clipboard ingest` (text + image mimes), dedupe, `ignorePasswords`, eviction 24 h, pins exempt | Vicinae clipboard monitor; `startup.conf:4` cliphist note | new | [w1-26 §5]; [w1-18 G15]; SCOPE S-145 |
| `clipboard list [--json]`, `copy <id>`, `pin <id>`, `text`, `clear [--yes]`, `open` | `open` = `launcher open --view clipboard` | `cliphist list/decode`; Vicinae `clipboard:*` | new | [w1-19 §3D clipboard]; SCOPE S-146 |
| `dmenu [--prompt P] [--free-text] [--password] [-f data\|index] [-n] [-s] [-W] [-H] [--no-section] [--no-quick-look] [--no-metadata] [--no-footer]` | rows on stdin, selection on stdout, exit 1 on dismiss; `{count}` in section titles; Vicinae flags `herdr-picker` does not use are accepted and ignored (**INFERRED**) | `vicinae dmenu` / `Ipc/dmenu` | new (P0, `herdr-picker`) | [w1-18 §5.5]; [w1-36 §3.6, G17]; SCOPE S-086 |
| `select [--prompt P] [--multiple]` | stdin rows → stdout; the fzf-prompt migration path for `theme-prompt`, `audio-route`, `call-record-menu`, `sleep-monitors`, `pomodoro menu`, `fzf-nmcli` without rewriting them | floating-kitty fzf prompts | new (should) | [w1-19 §3B select, §3C] |

### 7.4 Theme, config, state, diagnostics

| Verb | Args | Status | Source |
|---|---|---|---|
| `theme <noir\|claude-dark\|claude-light>` | calls `~/.local/bin/theme <name>`; every process reloads on the symlink change | new | BRIEF §3.5; [w1-36 §3.13]; SCOPE S-007 |
| `theme reload` (alias `reload-theme`) | re-read `~/.config/theme/gpuix-shell.json` (replaces `makoctl reload` + `vicinae theme set` in `bin/theme:84-91`) | new | [w1-21]; [w1-26 §3]; [w1-19 §3D theme] |
| `reload` | reload config fragments + theme in every process (never Sway) | new | [w1-29 #199]; [w1-19 §3D config] |
| `registry ls [--json]` | every registered rail item / launcher command / verb; no enable/disable | new (READ) | [w1-19 §3D config]; [w1-29 §4 6] |
| `validate [<config.json>]` | one schema validates the fragments (AM #178 "programmatic") | new | [w1-29 #178]; SCOPE S-009 |
| `status [--json]` | liveness of every surface unit + socket | new (READ) | [w1-19 §3D liveness]; [w1-23 `;s`] |
| `doctor [--json]` | socket, units on `sway-physical-session.target`, `@gpuix/native` load, D-Bus name ownership (`org.freedesktop.Notifications`, no mako, no vicinae), theme fragment, fonts present, herdr reachable, Sway IPC, Chrome native host, credential file for music | new | [w1-21]; [w1-13 `--check-native`]; [w1-23 services view] |
| `snapshot [--json] [--surface <name>]` | dump state: visible surfaces, rail items, notification list, DND, herdr snapshot digest, active output | new (READ) | night brief; [w1-23 herdr-gpui `--json`] |
| `listen` (alias `events [--follow]`) | JSON event stream: surface shown/hidden, notification, osd, herdr state; scripts use it instead of polling | new (should) | [w1-19 §3D events]; [w1-23 `events --follow`] |
| `wait <cond>` | block until a surface is open/closed or a notification arrives (smoke tests) | new (should) | [w1-23 herdr-gpui `wait`] |
| `ping`, `version` | — | new | [w1-36 §3.6]; [w1-10] |
| `--check-native`, `--check-dbus`, `--check-theme <file>` | pre-socket self-checks (`{"ok":true,…}`), ~0.1 s each | new | [w1-21 §4.3, §5.1] |

### 7.5 Music (daemon `music serve`; ASSUMPTIONS music lines)

`music play|pause|toggle|next|prev|stop|seek <s>|volume <0-100>|now|queue|like|shuffle|repeat
<off|all|one>|search <q>|serve [--start]`. The CLI never starts audio implicitly (exit 3 + the fix);
MPRIS `org.mpris.MediaPlayer2.gpuix_music` is published, so `media`/playerctl keep working.

### 7.6 Power, lock, inhibit (ACTION class; never on a bind)

| Verb | Behaviour | Source |
|---|---|---|
| `power toggle` | opens the menu (the only power verb a bind may call) | §5.3 |
| `power <monitors-off\|sleep-monitors\|logout\|reboot\|poweroff\|hibernate\|suspend> --yes` | terminal / script use; without `--yes` prints the refusal and exits 1; `suspend`/`hibernate` also need the config flag; not replay-safe. **INFERRED** that the verbs exist at all | [w1-19 §3D power]; [w1-29 §5 `replaySafe`]; [w1-30 §3.2 Session] |
| `lock` | exits 69 until a locker is installed; no `unlock` verb ever | [w1-19 §3B lock]; [w1-18 G12]; [w1-30 §4.1 10] |
| `inhibit on\|off\|toggle` | caffeine via `systemd-inhibit` (the one survivor of the iceboxed idle suite) | [w1-19 §3D]; SCOPE S-133 |

### 7.7 Compatibility aliases (Vicinae [w1-36 §3.6, §4.6])

| Alias | Maps to | Kept for |
|---|---|---|
| `cmd launch <provider:entrypoint> [args] [--cwd] [-q]` | `launcher open --view <id>` | scripts and muscle memory; ids: `clipboard:history`, `applications:herdr-picker`, `browser-extension:browse-tabs`, `media:now-playing`, `core:search-tray`, `files:search`, `wm:switch-windows`, `theme:set`, `power:*` |
| `cmd ls [--json]` | `registry ls` filtered to launcher commands | — |
| `toggle [-q]`, `open [-q]`, `close`, `state open` | `launcher toggle\|open\|close\|state` | the smoke tests (`vicinae ping` / `state open` / `close`) |
| `deeplink gpuix-shell://…` | `toggle`, `open`, `close`, `launch/<provider>[/<entrypoint>]?arguments=&fallbackText=&toggle=`, `pop_current`, `pop_to_root`, `oauth` | extension OAuth; `x-scheme-handler/vicinae` is **not** registered while Vicinae is installed |
| `script check\|template`, `ext lint\|dev` | script-command parser and extension dev loop | P1/P3 |
| `theme set <id>` | **retired**: replaced by `theme <name>` | — |
| `config`, `fs query`, `app launch`, `logs` | **retired** (`logs` → `journalctl --user -u 'gpuix-shell-*'`) | — |

### 7.8 Exit codes and verb classes

| Code | Meaning | Source |
|---|---|---|
| 0 | ok (dmenu/select: a row or free text was chosen) | SCOPE S-002 |
| 1 | error, refused (ACTION without `--yes`, SECRET over the wire), or empty/dismissed selection (dmenu) | [w1-18 §5.5]; [w1-36 G17] |
| 2 | usage: unknown surface, verb, view or flag | SCOPE S-002 |
| 3 | surface or daemon not running (socket absent; `music` without `--start`) | SCOPE S-002; ASSUMPTIONS (music) |
| 69 | unavailable: `lock` without a locker, `music` without the credential file, `tray` tonight | [w1-19 §3B]; [w1-21 exit 69 convention] |

Revision 1's codes 4 and 5 fold into 2 and 1 (**INFERRED** alignment with SCOPE S-002).

Classes [w1-30 §3.2]; [w1-19 §3D]: READ (`status`, `snapshot`, `list`, `registry ls`, `cheatsheet
lint`, `ui-tree`), WRITE-reversible (`toggle|open|close`, `osd`, `dnd`, `theme`, `music`, `inhibit`,
`rail`), ACTION (`notifications invoke`, `clear-history`, `power <action> --yes`, `clipboard clear`),
SECRET (wifi password, bluetooth passkey, polkit: never a verb, only a local form).

---

## 8. Conflicts and retirements

### 8.1 Vicinae (replaced in full, BRIEF §5; [w1-35]; [w1-36 §3.13])

| Item | Status | Replacement |
|---|---|---|
| `binds.conf:6,7` `vicinae toggle` | retired | `gpuix-shell launcher toggle` |
| `binds.conf:114` `vicinae cmd launch clipboard:history` | retired | `launcher open --view clipboard` (`cmd launch clipboard:history` alias) |
| `herdr-picker:211-258` `Ipc/dmenu` over `vicinae.sock` | changed | `gpuix-shell dmenu` (same framing on `shell.sock`), then the native `#` view |
| `vicinae.service` (`home/vicinae.nix`, on `sway-physical-session.target`) | retired | `gpuix-shell-launcher.service` and siblings; module asserts exclusivity (S-012) |
| `home/vicinae.nix` package + theme hook (`vicinae theme set dotfiles-current`, `bin/theme:88-90`) | retired | `gpuix-shell theme reload` / symlink watch |
| Vicinae theme TOML rendered by `home/themes/default.nix:140-175` | retired | `gpuix-shell.json` fragment (slot mapping reused) |
| `startup.conf:4` "Vicinae owns clipboard history" | retired | `wl-paste --watch gpuix-shell clipboard ingest` |
| `flake.nix:151,1213-1228` input pin + asserts | changed | the swap updates the assertions |
| Vicinae keymap (`Ctrl+B`, `Ctrl+P`, `Ctrl+,`, action keys) | kept as aliases except `Ctrl+,` | §4.2 |
| Chrome extension `kcmipingpfbohfjckomimmahknoddnke` + native host name `com.vicinae.vicinae` (`~/.config/google-chrome/NativeMessagingHosts/com.vicinae.vicinae.json`) | **keep** | the shell's own Bun native host answers under the same name so the extension needs no change; the HM path collides with `home/vicinae.nix:98-99`, hence the exclusivity assert |
| `vicinae dmenu`, `cmd launch`, `state open`, `ping`, deeplinks | kept as `gpuix-shell` aliases | §7.7 |
| Vicinae `global_shortcuts` ("super+control+space") | retired | Sway owns keys |

### 8.2 mako (replaced, [w1-18 §3.1–§3.3])

| Item | Status | Replacement |
|---|---|---|
| `services.mako` + `mako.service` `ExecReload = makoctl reload` (`home/vicinae.nix:111-143`) | retired | notifications daemon owns `org.freedesktop.Notifications`; never both |
| `bin/theme:84-87` `makoctl reload` | retired | symlink watch / `gpuix-shell theme reload` |
| PR #571 `$mod+o exec makoctl dismiss --all` (unmerged) | retired | `$mod+o` = `notifications dismiss`, `$mod+Ctrl+o` = `dismiss --all` |
| `osd` script `notify-send -r` to mako | kept (works against the daemon; routed to the OSD window) | §5.6 |
| `herdr-attention` branch mako actions ("Go") | retired as a mako call | `notifications invoke`; actions kept (#69, S-109) |
| `desktop-notifications` shim (`makoctl dismiss\|restore` vs Hyprland) | retired | condition becomes "shell socket present" → `gpuix-shell notifications …` [w1-13] |
| `colorpicker`, `touchpad-toggle`, `screenshot`, `record` (`-t 0`), any `notify-send` caller | keep | same D-Bus name; explicit `-t` wins over urgency defaults [w1-18 G7] |
| mako theme fragment in `home/themes/default.nix:127-138` | retired | `gpuix-shell.json` |
| optional `makoctl` shim script | not shipped | all call sites move in the same commit [w1-18 G23] |

### 8.3 Desktop entries in `home/vicinae.nix:148-170`

| Entry | Status | Replacement |
|---|---|---|
| `herdr-picker` "Herdr workspaces" | retired | native `#` view / `applications:herdr-picker` |
| `sway-workspace-new` | retired | native command "New Herdr workspace" → `sway-workspace new` |
| `sway-workspace-restore` | retired | native command → `sway-workspace restore` |
| `sway-workspace-rename` | retired | native command → `sway-workspace rename` |
| `notifications-dismiss` (`makoctl dismiss`) | retired | native command → `gpuix-shell notifications dismiss` |
| `notifications-history` (`makoctl restore`) | retired | native command → `gpuix-shell notifications restore` |
| `network-settings` (kitty nmtui) | retired as an entry; kept as the fallback native command "Network settings (nmtui)" (**INFERRED**) | `w ` wifi menu; airplane row (S-136) |

### 8.4 Scripts and unmerged work

| Item | Status | Note | Source |
|---|---|---|---|
| `herdr-picker` script | kept (dmenu backend swapped) until wave 3 verifies the native view, then retired; `--json` feeds the native provider | dmenu shim | [w1-18 §3.7]; [w1-35] |
| `sway-workspace-switcher` (PR #565, unmerged) | retired, absorbed | `$mod+i` switcher; its 16 tests and Zenbook fixtures are reused | [w1-17]; [w1-13]; [w1-18 §5.6] |
| `fzf-nmcli` | kept as fallback | the exact NM flows the wifi menu reproduces | [w1-30 §5] |
| `audio-route` | keep | gains a non-interactive sink argument in wave 3 for F9 | [w1-29 #106]; SCOPE S-074 |
| `theme-prompt` (F2 / Shift+F2) | keep | — | [w1-17] |
| `theme` script | changed | drops the `makoctl reload` and `vicinae theme set` lines; keeps `swaymsg reload` | [w1-26 §3] |
| `herdr-context` (branch `herdr-sway-context`) | adopt on `$mod+grave` | — | [w1-17] |
| `vpn-status`, `recording-toggle`, `pomodoro`, `touchpad-toggle` | keep | rail data sources (JSON / state files) | [w1-30 §5]; SCOPE S-031–S-036 |
| `osd` | keep tonight | contract honoured by the daemon; may later call `gpuix-shell osd` | [w1-18 §3.1] |
| `desktop-shell` (Hyprland-era `main.ts` CLI `bar\|launcher\|controls\|…`, `--provider`) | retired | shape reused for `gpuix-shell` | [w1-13] |

### 8.5 Key conflicts and the ruling taken

| Key | Claimants | Chosen | Source |
|---|---|---|---|
| `$mod+grave` | herdr-context swap (branch) vs CUBS rail collapse vs Hyprland-era windows | herdr-context; rail → `$mod+Shift+grave`; windows → `@` / `$mod+i` | [w1-17]; [w1-10] |
| `$mod+Shift+m` | PR #565 desk at 8443 vs music now playing | music; desk → `$mod+Ctrl+m` if #565 merges | ASSUMPTIONS; [w1-17] |
| `$mod+m` | free since 2026-10-12 | music view (proposed, not activated) | ASSUMPTIONS |
| `$mod+Shift+e` | SCOPE §22 power (INFERRED there) vs night brief files | files; power on `$mod+x` | night brief; SCOPE §22 |
| `F1`/`F2` | PR #566 draft (brightness, theme → Mod+F2) vs `binds.conf:139-140` | binds.conf as is; the shell takes neither key | [w1-17] |
| `F2` | SCOPE §22 "launcher theme after S-069" vs kitty `theme-prompt` | kitty prompt stays; launcher `t ` is additional | SCOPE §22; [w1-17] |
| `F10` | binds.conf sleep-monitors vs client brightness toggle | existing client override stands | [w1-17] |
| `$mod+e` / `$mod+Shift+e` | nautilus vs shell files | both: nautilus on `$mod+e`, files on `$mod+Shift+e` | [w1-20]; [w1-18 §3.6] |
| `$mod+comma` | Hyprland-era controls vs CUBS settings | controls (no settings GUI) | [w1-17]; [w1-10]; [w1-30 G6] |
| `$mod+Ctrl+space` | `herdr-picker` script vs native view | script with `dmenu` backend first, native view after wave 3 | [w1-18 §3.11]; SCOPE §22 |
| `$mod+Shift+v` (Hyprland-era notifications) | — | not reused; centre on `$mod+Shift+o` | [w1-17] |
| `$mod+Ctrl+d` (Hyprland-era launcher) | — | not reused; `$mod+d` | [w1-17] |
| `$mod+Shift+Escape`, `$mod+Ctrl+l` (CUBS power / lock) | — | power → `$mod+x`; lock unbound | [w1-10] |
| `Ctrl+K` | Raycast action panel vs Sway focus up vs vim cursor-up | action panel inside the launcher (default profile); vim profile reassigns it; Sway's `$mod+k` untouched | ASSUMPTIONS; [w1-17]; [w1-23] |
| `Ctrl+P` | Vicinae search filter vs vim/Emacs cursor-up | filter (scope dropdown) in every profile | [w1-36 §3.8]; ASSUMPTIONS (music) |
| `:` / `@` / `#` / `/` | night brief vs SCOPE S-053 vs DESIGN §8.2 | night brief, aliases kept (§4.3) | night brief; SCOPE; DESIGN |
| Clipboard store | cliphist (Tom, AM #86/#233) vs own `wl-paste --watch` store (BRIEF §3.4) | BRIEF's own store (S-145); keys identical either way | [w1-29 #86, G2]; [w1-30 G5] |
| Control centre WONT (AM §1.12) vs BRIEF `controls` | — | per-domain menus, no tile grid | [w1-29 §1.12, G1]; [w1-30 1.12]; [w1-19 §2] |
| Toast anchor | Tom 2026-10-11 top-centre (SCOPE §3, [w1-18 G1]) vs DESIGN A-15 / BRIEF top-right | config value `layout.toast.anchor`; no key depends on it; logged | [w1-18 G1]; DESIGN §8.4 |
| Launcher corners | Tom's square (Vicinae `rounding = 0`) vs DESIGN A-05 radius 12 | not a key matter; flagged for MORNING.md | [w1-18 G2]; [w1-36 G12] |
| CLI grammar | SCOPE `<surface> <verb>` vs night brief `toggle <surface>` | SCOPE canonical, brief spelling aliased | SCOPE S-002; night brief |
| Exit codes | rev 1's 0–5 vs SCOPE 0/1/2/3/69 | SCOPE's | SCOPE S-002; [w1-21] |

### 8.6 Where this file overrides SCOPE §22 / DESIGN §8 (so the morning diff is one list)

| SCOPE §22 / DESIGN line | KEYS ruling |
|---|---|
| `Mod+Ctrl+space` → `gpuix-shell launcher open -q "@"` | line unchanged tonight (`herdr-picker` → `dmenu`); later `launcher open --view herdr` |
| `Mod+o` → `notifications dismiss-all` | `notifications dismiss` (newest); `Mod+Ctrl+o` = `dismiss --all` (DESIGN §8.4 agrees: "Mod+o dismisses the newest") |
| `Mod+Shift+e` → `power toggle` | `files open`; power is `Mod+x` |
| `F2` → `launcher open -q "theme"` after S-069 | F2 stays the kitty prompt; `t ` view additional |
| `Mod+v` → `cmd launch clipboard:history` | same call, canonical spelling `launcher open --view clipboard` |
| S-053 prefixes `:` emoji, `/` files, `@` herdr, `♪`/`m:` music | §4.3 |
| DESIGN §8.2 "Ctrl+J/K, Ctrl+N/P move cursor" | `Ctrl+N` = `action.new`, `Ctrl+P` = scope; `Ctrl+J/K` only in the `vim` profile |
| `Mod+Ctrl+w`, `Mod+Ctrl+b`, `Mod+Shift+slash`, `Mod+Shift+o` (SCOPE INFERRED) | adopted as is |

---

## 9. Counts

| Section | Rows |
|---|---|
| Current `binds.conf` lines mapped (§2.1–2.7) | 108 bindsym + 10 `workspace … output` + 2 gestures |
| of which keep / changed | 102 keep / 6 changed (`$mod+d`, `$mod+space`, `$mod+Ctrl+space` backend, `$mod+Shift+n` backend, `$mod+v`, F9 in wave 3) |
| Client `sway-local.conf` lines (§2.8) | 5 rows, all keep |
| New binds (§3) | 12 bindsym activated (`$mod+i`, `$mod+o`, `$mod+Ctrl+o`, `$mod+Shift+o`, `$mod+x`, `$mod+Shift+e`, `$mod+Shift+slash`, `$mod+grave`, `$mod+Shift+grave`, `$mod+comma`, `$mod+Ctrl+w`, `$mod+Ctrl+b`) + 1 script change (`osd`) + 3 proposed/reserved (`$mod+m`, `$mod+Shift+m`, `$mod+a`) + 2 deliberately unbound (lock, DND) |
| Launcher prefixes / providers (§4.1) | 15 (+ 3 aliases `/`, `h `, `♪`); 15 `--view` ids; 27 native root commands |
| Launcher keys (§4.2) | 34 rows |
| Surface keymaps (§5) | switcher 10, centre 10, power 11, controls 8, files 1 block (30 keys), OSD 8 kinds, cheat sheet 1, ask 7 |
| Rail pointer targets (§6) | 16 |
| CLI verbs (§7) | 12 surface, 15 notification/OSD, 4 clipboard/dmenu/select, 12 theme/state/diagnostics, 1 music family, 4 power/lock/inhibit, 7 compat aliases, 5 exit codes |
| Retirements (§8.1–8.4) | vicinae 12, mako 9, desktop entries 7, scripts 10 |
| Conflicts ruled (§8.5) | 22; SCOPE/DESIGN overrides (§8.6) 8 |
| INFERRED rows | 21, each one `KEYS.md:` line in ASSUMPTIONS.md |
