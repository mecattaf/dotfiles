# 17 — Dotfiles integration surface: Sway binds, theme system, fonts, HM gating, session units

Reader note for the gpuix-shell overnight build (2026-10-20/21). Read-only survey of
`/home/tom/mecattaf/dotfiles` at `main` = `f501e856` (2026-10-20 13:45 +0200, "claude: standing
rule to keep ultracode verify stages light"). Every `file:line` below is against that tree; the
worktree `/home/tom/.wt/dotfiles/gpuix-shell` branches off `dadb1426` so line numbers may drift by
a few lines there — grep the quoted text.

Labels: **MEASURED** = read from the file at the quoted line. **REPORTED** = a comment or doc in
the repo says so (often quoting Tom). **INFERRED** = my reading; verify before building on it.

---

## 1. What this source is

The dotfiles repo is the NixOS + Home Manager (HM) flake for Tom's fleet (strix, client, worker,
nas). The pieces the shell must integrate with:

| Piece | Path | Nature |
|---|---|---|
| Sway RAW config | `home/dot_config/sway/{config,binds.conf,layout.conf,rules.conf,startup.conf,input.conf}` | hot-reloaded out-of-store symlink on the strix; copied into the store on the client (`rawDotfiles.inStore`) |
| Per-host generated Sway slot | `home/home.nix:144-168` → `~/.config/sway-local.conf` | HM text, host-gated |
| Session lifetime (NixOS) | `modules/sway.nix` | `sway-physical.service`, `sway-physical-session.target`, `sway-physical-shutdown.target`, the launcher script, portals |
| Seat gate | `modules/display.nix` (`myDisplay.enable`, default true), `modules/common.nix:215-248` (greetd ← myDisplay) | NixOS options |
| Launcher + notifications HM module | `home/vicinae.nix` | vicinae 0.29.1 + mako + desktop entries, gated on `osConfig.myDisplay.enable` |
| Theme system | `home/theme.nix`, `home/themes/{default,noir,claude-dark,claude-light}.nix`, `home/dot_local/bin/theme`, `docs/theme-switcher-2026-09-17.md` | one palette per theme keyed by ROLE; per-consumer fragment renderers; runtime symlink flip |
| Fonts | `pkgs/anthropic-ui.nix`, `pkgs/anthropic-mono-nerd.nix`, `pkgs/anthropic-webfonts.nix`, `modules/common.nix:376-470`, `docs/fonts/{README,anthropic-suite,nas-and-bootstrap}.md` | NAS-pinned `requireFile` derivations; never in git |
| Helper scripts | `home/dot_local/bin/*` (whole dir linked to `~/.local/bin`, `home/home.nix:198`) | bash/python; what Sway binds exec |
| Flake checks | `flake.nix:1074-1379` (`checks.home-profiles`) | eval-time asserts on vicinae/mako/binds/themes/fonts |
| The Zenbook | `hosts/client/default.nix` | the only seat; thin client; everything that thinks runs on the strix |

---

## 2. Verbatim Tom rulings relevant to the desktop shell (with dates)

All are REPORTED (quoted inside repo comments/docs) unless marked otherwise. The BRIEF's own
rulings (2026-10-20 22:50/23:05/23:20) are not repeated here.

| Date | Quote (verbatim as the repo carries it) | Where | Consequence for gpuix-shell |
|---|---|---|---|
| 2026-07-15 | "a kitty split reads as a quiet divider" | `home/themes/default.nix:67-68` | split/divider colour = `border.inactive`; hairlines, not accents |
| 2026-08-21 | SF Pro survives: "it's too good to have" | `modules/common.nix:378-380`, `:391` | SF Pro Display/Text stay as the sans FALLBACK; never remove |
| 2026-09-11 | "no display output on that box: Tom's ruling" (the worker) | `flake.nix:1164-1165` | shell never runs on worker/nas; `myDisplay.enable` is the gate |
| 2026-09-13 | "instrumentalizing herdr's own sidebar is VERY desirable" | `DECISIONS.md:505-506` | Mod+Ctrl+Shift+Return = herdr sidebar with agents panel stays a herdr feature, not a shell surface |
| 2026-09-14 | brightness "10% steps" | `home/dot_local/bin/brightness:3` | OSD step semantics |
| 2026-10-01 | "keep the originals on NAS so I don't have to do them again"; asked for "all the SF Mono ones" (symbols) | `docs/fonts/README.md:18-22, 94-95` | fonts are a fixed input; shell consumes family names only |
| 2026-10-10 | Shift+F5/F6: 2% fine steps | `home/home.nix:161` | keep 2% fine step on the Duo |
| 2026-10-11 | mako anchor: "top and center not top right" | `home/vicinae.nix:115` | **toast placement ruling: top-center.** Note: BRIEF §3.3 says toasts top-right (SHELLS-DIGEST). CONFLICT — record in ASSUMPTIONS.md; the dotfiles ruling is the more recent explicit Tom quote on this box (2026-10-11), the digest is a design-kit default. |
| 2026-10-11 | "Pictures (i guess screenshots) must be sync'd with the strix halo as i want no images saved on the zenbook which is a thin client (transient ones eg. clipboard are fine)" | `home/dot_local/bin/screenshot:19-21` | a shell screenshot surface must keep the spool-to-strix behaviour; never persist images locally on the client |
| 2026-10-11 | "i dnt need here" (about ~/dotfiles and ~/mecattaf on the thin client) | `hosts/client/default.nix:95-96`, `home/raw-dotfiles-guard.nix:35-38` | no checkout on the client: the shell ships from the Nix store; no hot-reload-by-editing there |
| 2026-10-11 | "can't that be done on the strix side of things? since it's a much more powerful device" | `hosts/client/default.nix:58-59` | build on the strix, `deploy ...#client`; never build on the Zenbook |
| 2026-10-12 | vicinae font: "make the font larger than 11 (12 or 14, need to decide, start at 12)" | `home/vicinae.nix:37` | **launcher UI font = Anthropic Sans 12** (asserted `flake.nix:1228` on family) |
| 2026-10-12 | "the blue color is not the same as the vicinae launcher. i prefer the latter's" | `home/themes/default.nix:125-126` | progress/selection colour = `selection.bg` (#264F78 on dark), not `blue` |
| 2026-10-12 | "Report Vicinae Bug" and "Donate to Vicinae" root items hidden | `home/vicinae.nix:63-65` | no vendor self-promotion rows in the launcher |
| 2026-10-12 | "i do not want th e chrome shortcuts neither. this goes for cross-nixosfleet" | `home/home.nix:263-264`; asserted `flake.nix:1259-1286` | **no Chrome `--app` .desktop launcher entries** (chatgpt, claude, gcloud, github, open-webui, perplexity, photos, railway, soundcloud, whatsapp, youtube-music). The shell's launcher must not re-create them as desktop entries. Mod+Shift+C/W/period binds (`binds.conf:28-30`) remain as Sway binds, not entries. |
| 2026-10-12 | "installed chatgp and claude apps must also be gone" | `home/client-apps.nix:20-21` | no Claude Desktop / ChatGPT packages |
| 2026-10-12 | ROG Control Center launcher entry hidden (asusd stays) | `home/vicinae.nix:101-109` | launcher must honour `NoDisplay=true`/`Hidden=true` desktop entries |
| 2026-10-13 | "niri and scroll are retired (Tom, settled 2026-10-13)" | `modules/display.nix:6` | Sway only |
| 2026-10-07 | (REPORTED, not verbatim) "Tom paused further feature work after this recovery. Clipboard paste polish, Wi-Fi, Bluetooth, native volume HUD, and deeper Herdr/Vicinae integration are tracked as GitHub issues; do not resume automatically." | `docs/client-sway-vicinae.md:295-297` | superseded by the 2026-10-20 order; those four items are exactly the shell's quick-settings scope |
| 2026-10-12 | Ctrl+N / Ctrl+Shift+N bare grabs "restored by request; they shadow the focused app's own Ctrl+N everywhere" | `home/dot_config/sway/binds.conf:19-20` | keep |

Standing non-Tom rulings that bind (REPORTED):
- ruling B5/B6: ONE herdr server, strix only, never `PartOf` the compositor (`flake.nix:1112-1116`, `home/herdr.nix:98-129`).
- `#385` (2026-09-13): all herdr chords go through `herdr-chord` → `herdr-picker --chord`; asserted by content on the RAW `binds.conf` (`flake.nix:1126-1145`).
- `#538`: Mod+Shift+N moves a window on Sway, so rename is **not** a chord (`flake.nix:1131`). MEASURED: `binds.conf:12` binds `$mod+Shift+n exec ~/.local/bin/sway-workspace rename` — the comment at `flake.nix:1131` is stale relative to binds.conf (rename IS bound to Mod+Shift+N, via sway-workspace, not via herdr-chord). INFERRED: the assert only cares that it is not asserted; no conflict at eval.
- AGENTS.md seat rule: Alt+H/L = focus output left/right, Alt+J/K = down/up (`flake.nix:1140-1144`).
- "MacTahoe on every session (non-negotiable)" (`flake.nix:1231-1253`): GTK3 theme name must start `MacTahoe-`, icons `MacTahoe`, gtk-4.0 css via the theme pointer.

---

## 3. Feature / behaviour inventory

### 3.1 Sway binds today — the exact list (MEASURED, `home/dot_config/sway/binds.conf` + `home/home.nix:144-168`)

`$mod` = `Mod4` (`layout.conf:3`). `$prompt` = `kitty --class` (`binds.conf:4`). `~` = `/home/tom`.

**Launchers / herdr / workspaces** (`binds.conf:6-17`)

| Key | Command | line | keep/replace/new |
|---|---|---|---|
| `$mod+d` | `exec vicinae toggle` | 6 | **replace** → `gpuix-shell launcher toggle` |
| `$mod+space` | `exec vicinae toggle` | 7 | **replace** (same) |
| `$mod+Ctrl+space` | `exec ~/.local/bin/herdr-picker` | 8 | **replace** → switcher/picker surface (herdr-picker uses Vicinae's `Ipc/dmenu` socket, see §5.4) |
| `$mod+Return` | `exec ~/.local/bin/herdr-chord new` | 9 | **keep** (asserted verbatim `flake.nix:1137`) |
| `$mod+Shift+Return` | `exec kitty -e fish` | 10 | **keep** (asserted `flake.nix:1139`) |
| `$mod+Ctrl+Shift+Return` | `exec ~/.local/bin/herdr-chord sidebar` | 11 | **keep** (asserted `flake.nix:1138`) |
| `$mod+Shift+n` | `exec ~/.local/bin/sway-workspace rename` | 12 | keep; the rename prompt itself is a Vicinae dmenu today → **replace** the prompt |
| `$mod+t` | `exec ~/.local/bin/sway-workspace new` | 13 | keep (herdr-picker `--workspace new`) |
| `$mod+Shift+t` | `exec ~/.local/bin/sway-workspace restore` | 14 | keep |
| `$mod+w` | `exec ~/.local/bin/sway-workspace close` | 15 | keep |
| `$mod+Shift+q` | `kill` | 17 | keep |

**Apps** (`binds.conf:21-31`)

| Key | Command | line | note |
|---|---|---|---|
| `Ctrl+n` | `exec google-chrome-stable` | 21 | bare grab, by request |
| `Ctrl+Shift+n` | `exec google-chrome-stable --incognito` | 22 | |
| `$mod+n` | `exec google-chrome-stable` | 23 | |
| `$mod+Ctrl+n` | `exec google-chrome-stable --incognito` | 24 | |
| `$mod+e` | `exec nautilus` | 25 | **replace candidate** → `gpuix-shell files` (Pinax-like); keep nautilus installed |
| `$mod+Shift+c` | `exec google-chrome-stable --app=https://claude.ai/` | 28 | keep |
| `$mod+Shift+w` | `exec google-chrome-stable --app=https://mail.google.com/` | 29 | keep |
| `$mod+Shift+period` | `exec google-chrome-stable --app=https://calendar.notion.so/` | 30 | keep |
| `$mod+Shift+semicolon` | `exec obs` | 31 | keep |

**Clipboard / speech / screenshots** (`binds.conf:34-46`)

| Key | Command | line | note |
|---|---|---|---|
| `$mod+c` | `exec ~/.local/bin/colorpicker` | 34 | keep (grim+slurp, hex → clipboard, no popup) — **new**: a shell toast with the swatch would be a natural add |
| `$mod+Ctrl+r` | `exec ~/.local/bin/speak-clipboard` | 36 | keep (ssh to strix Speech intake) |
| `$mod+s` | `exec ~/.local/bin/screenshot screen` | 42 | keep |
| `$mod+Shift+s` | `exec ~/.local/bin/screenshot area` | 43 | keep (slurp + satty) |
| `$mod+Alt+s` | `exec ~/.local/bin/screenshot window` | 44 | keep |
| `$mod+Ctrl+s` | `exec ~/.local/bin/screen-ocr-area` | 46 | keep |

**Workspace ↔ output pinning** (`binds.conf:50-59`): `workspace 1..9 output eDP-1`, `workspace 10 output eDP-2`.

**Workspace navigation** (`binds.conf:60-90`)

| Key | Command | line |
|---|---|---|
| `$mod+1..9` | `workspace number 1..9` | 60-68 |
| `$mod+0` | `workspace number 10` | 69 |
| `$mod+Shift+1..9` | `move container to workspace number 1..9` | 70-78 |
| `$mod+Shift+0` | `move container to workspace number 10` | 79 |
| `$mod+Up` / `$mod+Down` | `workspace prev_on_output` / `next_on_output` | 80-81 |
| `$mod+Shift+Up` / `Down` | `move container to workspace prev/next_on_output; workspace prev/next_on_output` | 82-83 |
| `--whole-window $mod+button4/5` | `workspace prev/next_on_output` | 85-86 |
| `--whole-window $mod+Ctrl+button4/5` | move container + follow prev/next | 87-88 |
| `--whole-window $mod+button6/7` | `focus left` / `focus right` | 89-90 |
| gesture `swipe:3:up` / `swipe:3:down` | `workspace next_on_output` / `prev_on_output` | `input.conf:18-19` |

**Focus / move / outputs** (`binds.conf:92-109`)

| Key | Command |
|---|---|
| `$mod+h/j/k/l` | `focus left/down/up/right` |
| `$mod+Shift+h/j/k/l` | `move left/down/up/right` |
| `$mod+bracketleft` / `bracketright` | `move left` / `move right` |
| `Alt+h/j/k/l` | `focus output left/down/up/right` (asserted `flake.nix:1141-1144`) |
| `$mod+Alt+h/j/k/l` | `move workspace to output left/down/up/right` |

**Layout** (`binds.conf:111-127`)

| Key | Command | line | note |
|---|---|---|---|
| `$mod+f`, `$mod+equal` | `fullscreen toggle` | 111-112 | |
| `$mod+b` | `splith` | 113 | |
| `$mod+v` | `exec vicinae cmd launch clipboard:history` | 114 | **replace** → `gpuix-shell launcher clipboard` (own `wl-paste --watch` store) |
| `$mod+Ctrl+v` | `splitv` | 115 | |
| `$mod+Tab` | `floating toggle` | 116 | |
| `$mod+Shift+Tab` | `focus mode_toggle` | 117 | |
| `$mod+Ctrl+t` | `layout tabbed` | 118 | |
| `$mod+Ctrl+Shift+s` | `layout stacking` | 119 | |
| `$mod+Ctrl+e` | `layout toggle split` | 120 | |
| `$mod+minus` / `$mod+plus` | `resize shrink/grow width 5 ppt` | 121-122 | |
| `$mod+Shift+r` | `reload` | 123 | |
| `--inhibited $mod+Escape` | `seat - shortcuts_inhibitor toggle` | 124 | |
| `$mod+Shift+p` | `exec ~/.local/bin/monitors-off` | 127 | keep (swayidle one-shot) |

**Hardware / F-keys** (`binds.conf:139-157`) — Glove80 sends plain F-keys; the Duo's keyboard sends XF86 keysyms via the dock daemon (`binds.conf:132-138`).

| Key | Command | line | keep/replace |
|---|---|---|---|
| `--no-repeat F2` | `exec $prompt theme-prompt -e ~/.local/bin/theme-prompt theme` | 139 | **replace** the fzf-in-kitty prompt → shell theme picker (calls `theme <name>`) |
| `--no-repeat Shift+F2` | `exec $prompt theme-prompt -e ~/.local/bin/theme-prompt accent` | 140 | **replace** → accent picker (calls `wallpaper <accent>`) |
| `--no-repeat Menu` (= Caps Lock, `input.conf:2` `caps:menu`) | `exec ~/.local/bin/touchpad-toggle` | 141 | keep; it pops `osd` |
| `F3` / `F4` / `F5` | `exec ~/.local/bin/media play/prev/next` | 142-144 | keep (playerctl) |
| `F6` / `F7` / `F8` | `exec ~/.local/bin/volume mute/down/up` | 145-147 | keep; OSD → **replace** notify-send path with shell OSD |
| `F9` | `exec $prompt audio-route-prompt -e ~/.local/bin/audio-route` | 148 | **replace** the fzf prompt → quick-settings audio route (keep `audio-route speaker|inzone|internal` as the actuator) |
| `Shift+F9` | `exec $prompt call-record-prompt -e ~/.local/bin/call-record-menu` | 149 | keep (or wrap) |
| `F10` | `exec $prompt sleep-monitors-prompt -e ~/.local/bin/sleep-monitors` | 150 | **replace** the fzf prompt → power menu item (calls `monitors-off`) |
| `Shift+F10` | `exec $prompt pomodoro-prompt -e ~/.local/bin/pomodoro menu` | 151 | **replace** the fzf menu → shell pomodoro; keep `pomodoro start|stop|pause|status` |
| `--locked XF86AudioRaiseVolume/LowerVolume/Mute` | `exec ~/.local/bin/volume up/down/mute` | 152-154 | keep |
| `--locked XF86AudioPlay/Next/Prev` | `exec ~/.local/bin/media play/next/prev` | 155-157 | keep |

**Client-only slot, generated** (`home/home.nix:149-168`, `~/.config/sway-local.conf`, `hostName == "client"`)

| Line | Content |
|---|---|
| `output eDP-1 scale 2 position 0 0` / `output eDP-2 scale 2 position 0 900` | logical 1440x900 each, stacked (asserted shape `flake.nix:1230`) |
| `input type:touch map_to_output eDP-1` | asserted `flake.nix:1363` |
| `bindswitch --reload --locked lid:on output eDP-1 disable` / `lid:off ... enable` | asserted `flake.nix:1365` |
| `bindsym --no-warn F10 exec ~/.local/bin/brightness toggle` | **note**: F10 is bound twice (binds.conf:150 sleep-monitors prompt; here brightness toggle) — `--no-warn` suppresses the duplicate warning; the LATER include wins in Sway (sway-local.conf is included after binds.conf, `config:9`), so **on the client F10 = backlight toggle**, not the sleep prompt. INFERRED from include order. |
| `bindsym --locked XF86MonBrightnessDown/Up exec ~/.local/bin/brightness down/up` | |
| `bindsym --locked Shift+XF86MonBrightnessDown/Up exec ~/.local/bin/brightness down/up 2%` | |
| `bindsym --locked XF86AudioMicMute exec ~/.local/bin/volume micmute` | |

Strix slot (`home.nix:145-148`): only `output DP-4 scale 2 position 0 0`, `output DP-1 scale 2 position 2560 0`; must contain no `bindsym` (`flake.nix:1369`). The strix has `myDisplay.enable = false` (`hosts/strix/default.nix:123`) so this is dormant.

Keys reachable in the old docs table but NOT in today's binds.conf (REPORTED `docs/client-sway-vicinae.md:46-65`, stale): "Mod+C opens Chrome" (now colorpicker), "Mod+K focus up" (true). Treat that table as history.

### 3.2 Sway appearance / rules / startup (MEASURED)

| Setting | Value | file:line |
|---|---|---|
| Title/bar font | `font pango:Anthropic Sans 11` | `layout.conf:2` |
| Gaps | `gaps inner 0`, `gaps outer 0`, `smart_gaps off` | `layout.conf:4-6` |
| Borders | `default_border pixel 1`, `default_floating_border pixel 1`, `hide_edge_borders smart` | `layout.conf:7-9` |
| Layout | `workspace_layout default`, `focus_wrapping no`, `floating_modifier $mod normal`, `tiling_drag enable`, `xwayland enable` | `layout.conf:10-14` |
| Background | `output * bg #000000 solid_color` (also re-asserted by every theme fragment, `themes/default.nix:121-122`) | `layout.conf:16` |
| Cursor | `seat seat0 xcursor_theme Bibata-Modern-Classic 48`, `hide_cursor 1000` | `input.conf:16-17` |
| Mouse | `focus_follows_mouse no`, `mouse_warping output`, `primary_selection disabled` | `input.conf:13-15` |
| Keyboard | `xkb_options caps:menu`, `xkb_numlock enabled` | `input.conf:1-4` |
| Touchpad | tap, dwt, natural_scroll, accel adaptive, clickfinger | `input.conf:5-11` |
| Chrome | `shortcuts_inhibitor disable` for `^chrome-.*` and `^google-chrome$` | `rules.conf:1-2` |
| Floating apps | gcr-prompter, pavucontrol (2 app_ids), blueman-manager, Amberol, firefox PiP (sticky) | `rules.conf:3-8` |
| fzf prompt tier | `^(sleep-monitors\|audio-route\|call-record)-prompt$` → floating, 640x200 px, centred, border 2; `^(theme\|pomodoro)-prompt$` → 640x300 | `rules.conf:12-13` |
| Startup | `wl-gammarelay-rs run`; `sh -c 'sleep 0.5 && kanshi'`; gsettings cursor theme/size 48, text-scaling 1.0, button-layout ''; `theme apply`; nautilus-open-any-terminal = kitty | `startup.conf:3-11` |
| Config includes (order) | `/etc/sway/physical-session.conf`, `input.conf`, `layout.conf`, `binds.conf`, `rules.conf`, `startup.conf`, `~/.config/sway-local.conf`, `~/.config/theme/sway.conf` | `config:3-10` |
| Header comment | "No bar: Vicinae is the command surface; Mako owns notifications." | `config:2` |
| Startup comment | "Vicinae owns clipboard history; do not start a second cliphist watcher." | `startup.conf:4` — **the shell's own clipboard watcher replaces this; `cliphist` is still in home.packages (`home.nix:454`)** |

Rule for new shell windows (INFERRED): the shell's ordinary windows (`gpuix-shell files`, `power`) need `for_window` rules by `app_id` in `rules.conf` if they should float; layer-shell surfaces need none.

### 3.3 Vicinae today (MEASURED `home/vicinae.nix`) — what the launcher replaces

| Feature | Exactly | line | replace with |
|---|---|---|---|
| Package | `inputs.vicinae.packages.<system>.default`, flake input `github:vicinaehq/vicinae/v0.29.1` (`flake.nix:151`); cachix substituter declared in `modules/sway.nix:108-113` | 11 | drop input + cachix when vicinae goes (ASSUMPTION: keep until the shell is accepted) |
| systemd | `programs.vicinae.systemd = { enable; target = "sway-physical-session.target"; environment.QT_QPA_PLATFORM = "wayland"; }` | 29-33 | same target for `gpuix-shell-*.service` |
| Font | `font.normal = { family = "Anthropic Sans"; size = 12; }` | 35-38 | Anthropic Sans 12 (asserted family `flake.nix:1228`) |
| Window | `opacity = 1; material = "none"; rounding = 0; client_side_decorations = { border_width = 1; shadow_size = 0; }; layer_shell = { enabled; layer = "overlay"; keyboard_interactivity = "exclusive"; }` | 48-61 | **design values**: flat, opaque, 1 px border, no shadow, square (rounding 0 — BRIEF §3.6 says 8/12 inner corners for Tacit feel; the Vicinae window was 0) |
| Theme | `theme.dark.name = theme.light.name = "dotfiles-current"`; `~/.local/share/vicinae/themes/dotfiles-current.toml` → out-of-store symlink to `~/.config/theme/vicinae.toml` | 44-47, 96-97 | shell reads `~/.config/theme/gpuix-shell.json` |
| Telemetry/tray/input | `telemetry.system_info = false; tray.enabled = false; input_server.enabled = false; pop_to_root_on_close = true; favicon_service = "none"` | 39-43 | no tray icon; no input injection |
| Hidden root items | `providers.core.entrypoints.{report-bug,sponsor}.enabled = false` | 66-69 | — |
| Clipboard | `providers.clipboard.preferences = { monitoring = true; ignorePasswords = true; evictionThreshold = "86400"; preserveTagged = true; }` | 70-75 | shell clipboard: 24 h eviction, ignore password-hinted entries, pin/tag support |
| Files | `providers.files.preferences = { autoIndexing = true; indexingPaths = [ ~/Downloads ~/Documents ]; }` | 76-82 | shell file search scope |
| Favorites | `applications:herdr-picker`, `clipboard:history`, `browser-extension:browse-tabs`, `media:now-playing`, `core:search-tray` | 84-90 | the launcher's pinned rows: herdr picker, clipboard, Chrome tabs (needs the native-messaging host — gone with Vicinae; GAP), now-playing, tray |
| Chrome native messaging | `~/.config/google-chrome/NativeMessagingHosts/com.vicinae.vicinae.json` from the package | 98-99 | GAP: browser-tab search loses its bridge |
| xdg-terminals | `~/.config/xdg-terminals.list` = `kitty.desktop` | 100 | keep (independent of Vicinae) |
| Hidden entry | `rog-control-center.desktop` NoDisplay/Hidden | 103-109 | keep |
| Desktop entries (appear in app search) | `herdr-picker` ("Herdr workspaces"), `sway-workspace-new/restore/rename`, `notifications-dismiss` (`makoctl dismiss`), `notifications-history` (`makoctl restore`), `network-settings` (`kitty --class network-settings nmtui`) | 148-170 | the shell provides these as built-in commands; the two `makoctl` entries and `network-settings` go with mako/vicinae |
| libnotify | `home.packages = [ pkgs.libnotify ]` (notify-send) | 145 | keep: scripts call `notify-send` (osd, pomodoro) — the shell's notification daemon must implement `org.freedesktop.Notifications` incl. `-r` replace-id and `int:value` hint |

### 3.4 mako today (MEASURED `home/vicinae.nix:111-143`, `home/themes/default.nix:125-138`)

| Setting | Value | line |
|---|---|---|
| font | `Anthropic Sans 11` (asserted `flake.nix:1229`) | 114 |
| anchor | `top-center` (Tom 2026-10-11) | 115 |
| width | 390 | 116 |
| margin | 12 | 117 |
| padding | 14 | 118 |
| border-size / border-radius | 1 / 0 | 119-120 |
| default-timeout | 5000 ms | 121 |
| max-visible | 4 | 122 |
| layer | overlay | 123 |
| include | `~/.config/theme/mako.conf` | 124 |
| theme fragment | `background-color=ground.raised`, `text-color=fg`, `border-color=border.active`, `progress-color=over selection.bg`; `[urgency=low] border-color=border.inactive`; `[urgency=high] border-color=red` + `default-timeout=0` | `themes/default.nix:127-138` |
| unit | `Unit.ConditionEnvironment = "WAYLAND_DISPLAY"`, `After = [ "sway-physical-session.target" ]`, `PartOf = mkForce [ "sway-physical-session.target" ]`; `Service.Type = "dbus"`, `BusName = "org.freedesktop.Notifications"`, `ExecStart = <mako>/bin/mako`, `ExecReload = makoctl reload`; `Install.WantedBy = mkForce [ "sway-physical-session.target" ]` | 127-143 |
| reload hook | `theme apply` runs `makoctl reload` when `mako.service` is active | `bin/theme:85-87` |

OSD contract the daemon must honour (MEASURED `bin/osd`): `notify-send -p -t 1500 -a osd [-r <id>] [-h int:value:<pct>] <title> <body>`; id stored in `$XDG_RUNTIME_DIR/osd-notify.id`; a stale id must create a fresh popup (osd:12-13). Callers: `volume` (up/down/mute/micmute, 3% steps, `wpctl`), `brightness` (report: "Brightness NN%"/"Backlight off"), `touchpad-toggle` ("Touchpad on/off"), `audio-route` (lifted volume). `pomodoro` uses bare `notify-send -t ...` with title/body.

### 3.5 Theme system (MEASURED)

**Wiring** (`home/theme.nix:7-20`, `docs/theme-switcher-2026-09-17.md:24-40`):
- HM writes `~/.config/themes/<name>/<fragment>` for every theme × every fragment (`theme.nix:41-42` via `themes.fragments`).
- `~/.config/theme` (singular) is a plain symlink to `~/.config/themes/<name>`; HM never writes it except the bootstrap/heal activation (`theme.nix:64-78`: missing → noir; pointing outside `themes/` → same-named theme or noir).
- `~/.local/bin/theme <name>` retargets atomically (`ln -sfn` + `mv -T`, `bin/theme:182-183`) and fires reloads (kitty sockets, `swaymsg reload`, `makoctl reload`, `vicinae theme set dotfiles-current`, nvim `--remote-expr`, gsettings gtk-theme/color-scheme/icon-theme, `~/.claude.json` theme key) — `bin/theme:48-175`. "A symlink retarget fires no file-watcher event, so every reload below is load-bearing" (`bin/theme:14-15`). **The shell must therefore be reloaded explicitly OR watch the pointer by polling/`inotify` on `~/.config` (IN_MOVED_TO of `theme`)** — `mv -T` on the symlink does produce a directory event on `~/.config` (INFERRED; verify in the test).
- `theme apply` runs at every Sway start (`startup.conf:10`) — so the shell must tolerate being told to reload while it is starting.
- Verbs: `theme` (print), `theme list`, `theme <name>`, `theme toggle`, `theme apply`, `theme icons` (`bin/theme:4-9`). `THEMES_DIR` env previews a render (`bin/theme:20`).
- `theme-prompt theme|accent` (`bin/theme-prompt`) = fzf rows with `●` marking current; picks call `theme <name>` or `wallpaper <accent>`.
- Preview without a switch: `nix eval --json --impure --expr '... (import ./home/themes { inherit lib; }).fragments'` (`docs/theme-switcher-2026-09-17.md:83-91`).

**Role → value table (MEASURED from `home/themes/{noir,claude-dark,claude-light}.nix`).** claude-dark is `noir // {...}` (`claude-dark.nix:12`): every role not listed in its override is noir's.

| Role | noir | claude-dark | claude-light | role comment (noir/light file) |
|---|---|---|---|---|
| `name` | noir | claude-dark | claude-light | |
| `polarity` | dark | dark | light | |
| `catppuccinFlavour` | mocha | mocha | latte | nvim |
| `claudeCode` | dark | dark | light | `~/.claude.json` theme |
| `ground.base` | `#000000` | `#1A1A1A` | `#F9F9F7` | terminal/editor bg; claude: code-block ground / `--bg-100` |
| `ground.dim` | `#000000` | `#151515` | `#F3F3F0` | tab bar, one step below base; `--bg-100` / `--bg-200` |
| `ground.raised` | `#000000` | `#20201F` | `#FFFFFF` | popups, one step above base; `--bg-000` |
| `ground.desktop` | `#000000` | `#20201F` | `#F0EFEC` | desktop background (Sway bg stays #000000 regardless, `default.nix:121-122`) |
| `fg` | `#EAECF0` | `#EAECF0` | `#131313` | Claude Dark `fg` / `--text-000` |
| `fgDim` | `#D3D7DE` | `#D3D7DE` | `#52514E` | punctuation / `--cds-text-secondary` |
| `comment` | `#818898` | `#818898` | `#6E7687` | |
| `muted` | `#45475a` | `#52514E` | `#A5A49A` | inactive UI text; `--_gray-600` / `--_gray-300` |
| `red` | `#F47B85` | `#F47B85` | `#B80A18` | property |
| `green` | `#9BE963` | `#9BE963` | `#008000` | string |
| `yellow` | `#f9e2af` | `#f9e2af` | `#A66A00` | no Claude yellow role; mocha yellow / `--warning-100` |
| `blue` | `#70B8FF` | `#70B8FF` | `#0051C2` | function |
| `magenta` | `#CC7BF4` | `#CC7BF4` | `#8100C2` | keyword |
| `cyan` | `#5EEDED` | `#5EEDED` | `#007F80` | number |
| `orange` | `#FBAD60` | `#FBAD60` | `#B24A00` | variable |
| `accent` | `#70B8FF` | `#70B8FF` | `#0051C2` | URLs, cursor trail |
| `brand` | `#D97757` | `#D97757` | `#D97757` | Anthropic clay — identical in light and dark |
| `ansi.black` | `#000000` | `#1A1A1A` | `#2B303B` | |
| `ansi.white` | `#D3D7DE` | `#D3D7DE` | `#52514E` | |
| `ansi.brightBlack` | `#818898` | `#818898` | `#6E7687` | |
| `ansi.brightWhite` | `#EAECF0` | `#EAECF0` | `#131313` | |
| `selection.bg` | `#264F78` | `#264F78` | `#CDE2FB` | Claude Code TUI selection / `--accent-900` light; **this is the "vicinae blue" Tom prefers** |
| `selection.fg` | `#EAECF0` | `#EAECF0` | `#131313` | |
| `cursor` | `#EAECF0` | `#EAECF0` | `#131313` | |
| `cursorText` | `#000000` | `#1A1A1A` | `#F9F9F7` | |
| `border.active` | `#555451` | `#555451` | `#A5A49A` | `--_gray-300` on light |
| `border.inactive` | `#373735` | `#373735` | `#D2D1C7` | `--_gray-150` on light |
| `border.urgent` | `#F47B85` | `#F47B85` | `#B80A18` | |
| `tabIndicator.active` | `#CC7BF4` | `#CC7BF4` | `#8100C2` | |
| `tabIndicator.inactive` | `#818898` | `#818898` | `#97958D` | `--text-400` light |
| `insertHint` | `#CC7BF480` | `#CC7BF480` | `#8100C280` | 8-digit hex (alpha) |
| `gtk.package` | `mactahoe-gtk-theme` | `mactahoe-claude-gtk-theme` | `mactahoe-claude-gtk-theme` | pkgs attr resolved in `theme.nix:33` |
| `gtk.theme` | `MacTahoe-Dark-grey` | `MacTahoe-Claude-Dark-orange` | `MacTahoe-Claude-Light-orange` | |
| `gtk.colorScheme` | `prefer-dark` | `prefer-dark` | `prefer-light` | |

The `roles` list that every theme must fill is at `themes/default.nix:242-269`; a missing role throws at eval (`:270-279`).

**Fragment renderers today** (`themes/default.nix`, `render` at `:281-290`): `kitty.conf` (:19-71), `ghostty` (:75-113), `sway.conf` (:115-123), `mako.conf` (:127-138), `vicinae.toml` (:140-177), `colors.fish` (:181-201), `theme.lua` (:204-219), `meta` (:224-231, `key=value`: name, polarity, claude_code, gtk_theme, color_scheme, icon_suffix).

**Sway fragment** (`:115-123`): `client.focused border.active ground.base fg border.active border.active`; `client.focused_inactive border.inactive ground.base fgDim ...`; `client.unfocused` same as focused_inactive; `client.urgent red ground.base fg red red`; `output * bg #000000 solid_color`.

**Vicinae fragment** (`:140-177`) — the most complete UI mapping and the template for `gpuix-shell.json`: `background=ground.base`, `secondary_background=ground.raised`, `foreground=fg`, `border=border.inactive`, `accent=accent`, `accent_foreground=ground.base`, accents blue/green/magenta/orange/red/yellow/cyan (purple=magenta), text `default=fg`, `muted=comment`, `placeholder=comment`, `danger=red`, `success=green`, selection `{selection.bg, selection.fg}`, list selection same + `secondary_foreground=selection.fg`, loading `bar=brand`, `spinner=fg`.

**How a new theme fragment is added** (MEASURED procedure):
1. In `home/themes/default.nix`, add a renderer `gpuixShell = t: builtins.toJSON { ... }` (or a string) in the `let` block next to `vicinae` (`:140`). It is pure `{ lib }` — no pkgs.
2. Add the key to `render` (`:281-290`): `"gpuix-shell.json" = gpuixShell t;`.
3. Nothing else: `fragments` (`:293-295`) fans out to `themes/<name>/gpuix-shell.json` for all three themes, and `home/theme.nix:42` emits every entry as `xdg.configFile`. The shell reads `~/.config/theme/gpuix-shell.json`.
4. If a new ROLE is needed, add it to `roles` (`:242-269`) and to all three theme files, or the eval throws.
5. Add a reload hook in `bin/theme` `reload_desktop_tools` (`:83-92`), guarded by `systemctl --user -q is-active gpuix-shell-rail.service` (same pattern as mako/vicinae), e.g. `gpuix-shell theme reload` over the socket — or rely on the pointer watch. Both is safest (REPORTED hazard `docs/theme-switcher-2026-09-17.md:111-112`).
6. The `home-profiles` check asserts `themes/noir/gtk-4.0` exists and no `themes/noir/gtk4.css` (`flake.nix:1247-1249`); a `gpuix-shell.json` fragment trips nothing. Add an assert `clientHome.xdg.configFile ? "themes/noir/gpuix-shell.json"` next to them.

**GTK side of a theme** (`theme.nix:30-48`, `bin/theme:129-164`): `themes/<name>/gtk-4.0` is a store path to the MacTahoe variant's `gtk-4.0/`; `~/.config/gtk-4.0/{gtk.css,gtk-dark.css,assets}` point through the pointer. Icon theme = `MacTahoe[-<accent>]-{dark,light}`, accent from `~/.local/state/wallpaper/accent` (written by `bin/wallpaper`; accents: oat olive cactus sky fig heather coral, default olive, `wallpaper:21-22`). INFERRED: the shell's quick-settings can expose "theme" (3 rows) and "accent" (7 rows) by calling these two scripts.

### 3.6 Fonts (MEASURED)

| Family (fontconfig name) | Package / pkgs attr | Files | Installed via | Consumers today |
|---|---|---|---|---|
| `Anthropic Sans` (variable `wght` 300-800, `opsz` 16-48) | `pkgs/anthropic-ui.nix` → `anthropic-ui` (overlay `flake.nix:308`) | `$out/share/fonts/truetype/` 4 variable TTFs + 1 static | `modules/common.nix:396` `fonts.packages` (system-wide, every host) | Sway title font 11 (`layout.conf:2`), GTK `font-name = "Anthropic Sans 11"` (`home.nix:192`), Vicinae 12 (`vicinae.nix:36-37`), mako 11 (`vicinae.nix:114`), `sans-serif` alias (`common.nix:458-462`) |
| `Anthropic Serif` (variable, same axes) | same package | same | same | GTK `document-font-name = "Anthropic Serif 12"` (`home.nix:193`), `serif` alias (`common.nix:463-466`) |
| `Anthropicons` (static pinned `wght=400 opsz=20 ANIM=0 ANM2=0`; 307 codepoints U+E000-E134; nameID1 `Anthropicons`, PS `Anthropicons-Regular`) | same package | 1 TTF | same | nothing today ("Installing Anthropicons changes no font resolution", `anthropic-suite.md:941`). Brand marks U+E11A-E11E (`ASlash.pua`, `Anthropic.pua`, `Claude.pua`, `Spark.pua`, `Code.pua`) live in the **text** faces, not the icon face (`anthropic-suite.md:1162`, `anthropic-ui.nix:11-12`) |
| `AnthropicMono Nerd Font` (12 statics: Light/Regular/Medium/SemiBold/Bold/ExtraBold × Roman/Italic; nameID1 `AnthropicMono NF`, PS `AnthropicMonoNF-<Style>` — Regular is bare `AnthropicMonoNF`) | `pkgs/anthropic-mono-nerd.nix` → `anthropic-mono-nerd` (`flake.nix:307`) | `AnthropicMonoNerdFont-<Style>.ttf` | `common.nix:395` `fonts.packages` | kitty 16.0 (`kitty.conf:86-93`, bold = SemiBold by ruling), GTK `monospace-font-name = "AnthropicMono Nerd Font 11"` (`home.nix:194`), `monospace` alias (`common.nix:467-470`) |
| (none — webfonts) | `pkgs/anthropic-webfonts.nix` → `anthropic-webfonts` (`flake.nix:309`) | 7 woff2 + `css/anthropic-fonts.css` at `/etc/profiles/per-user/tom/share/webfonts/{woff2,css}`; handle `~/.local/share/webfonts` (`home.nix:212`) | `home.packages` (`home.nix:431`), DELIBERATELY not `fonts.packages`; fontconfig rejects `*/share/webfonts/*`, `*.woff2`, `*.woff` (`common.nix:422-434`) | local web pages only |

Fallbacks kept on purpose: `sf-pro` (SF Pro Display/Text), `sfmono-liga`, `maple-mono.NF`, `nerd-fonts.jetbrains-mono`, `google-fonts`, `noto-fonts-color-emoji` (`common.nix:386-396`). `fc-match "Anthropic Sans"` returns the opsz=16 "Text" default (`home.nix:190-191`, `common.nix:456-457`).

Bytes: `nas:/mnt/fast/fonts/anthropic/{anthropic-mono-nerd-fonts,anthropic-ui-fonts,anthropic-webfonts}.tar.zst`, sha256 pinned in the three `pkgs/*.nix` (`docs/fonts/README.md:67-80`). A fresh builder needs `nix-store --add-fixed sha256 <tarball>` first (`anthropic-ui.nix:33-38`). Rules: no font bytes in git (`.gitignore` refuses ttf/otf/woff/woff2/tar.zst, `README.md:84-87`); never `fc-cache` from a build/test (`:102-104`); "These faces are personal use only" (`:109`) — the branch stays private (BRIEF §1).

For GPUIX (INFERRED): `@gpuix/native` 0.11.0 `registerFont(bytes)` can load `/run/current-system/sw/share/fonts/truetype/...` or resolve via fontconfig by family name "Anthropic Sans"; the rail probe already rendered Anthropic Sans by family (BRIEF, MEASURED 23:45). Use family names exactly: `Anthropic Sans`, `Anthropic Serif`, `AnthropicMono Nerd Font`, `Anthropicons`. The variable Sans supports `opsz`; pick opsz 16 for 11-14 px UI text, larger opsz for display sizes.

### 3.7 Scripts the shell wraps or replaces (MEASURED, `home/dot_local/bin/`)

| Script | Verbs / contract | Depends on | keep/replace/new |
|---|---|---|---|
| `osd` (38 l.) | `osd <title> <body> [percent]` → single replaceable notify-send (see §3.4) | notify-send, `$XDG_RUNTIME_DIR/osd-notify.id` | **keep the CLI; the daemon behind it is replaced.** Optional: make `osd` call `gpuix-shell osd` when the socket exists, else fall back |
| `volume` (37 l.) | `up|down` (3%), `mute`, `micmute`; `wpctl` on `@DEFAULT_AUDIO_SINK@/SOURCE@`; parses "Volume: 0.88 [MUTED]" | wpctl, osd | keep as actuator |
| `brightness` (193 l.) | `up|down [focused] [N%]` (10% default, floor `--min-value=1`), `off`, `restore`, `toggle`; DRM backlights only; Duo: `intel_backlight` mirrored to eDP-2 by the dock daemon | brightnessctl, swaymsg get_outputs, osd | keep as actuator |
| `media` (11 l.) | `play|toggle`, `next`, `prev` → `playerctl` default player | playerctl | keep; the shell's now-playing can use MPRIS over D-Bus directly |
| `audio-route` (234 l.) | `speaker|inzone|internal|menu`; stable node names (Sound Blaster GS3 sink, iContact webcam source, INZONE buds sink/source, internal `sof-hda-dsp` by regex); lifts a sink below 0.30 to 0.50; sets both default sink and source | pw-dump, jq, wpctl, fzf (menu only), osd | keep the three named verbs; **replace** the fzf `menu` with a quick-settings list; node names at `:14-17,32-34` are the data |
| `screenshot` (136 l.) | `screen|area|window`; grim/slurp/satty; client spool `~/.local/state/screenshot-spool/` → rsync to `strix:Pictures/Screenshots/`; naming "Screenshot from YYYY-MM-DD HH-MM-SS.png" | grim, slurp, satty, wl-copy, swaymsg, rsync/ssh | keep |
| `colorpicker` (17 l.) | `slurp -p` → `grim -t ppm` → hex → `wl-copy`; no popup by design (`:5-6`) | grim, slurp | keep; new: optional toast |
| `pomodoro` (167 l.) | `start|stop|pause|restart|status|notify|menu`; state file `~/.local/share/pomo` (mtime = start; content = paused seconds); `WORK_TIME` 25 / `BREAK_TIME` 5 (env `POMO_*`); `status` prints "Focus MM:SS" / "Break MM:SS" / "Paused MM:SS" / "Timer stopped"; `notify` daemon loop via `pgrep -f "pomodoro notify"` | notify-send, fzf (menu) | keep state + verbs; **replace** `menu` (fzf) with a shell widget that polls `pomodoro status` or reads the file |
| `monitors-off` (12 l.) | `swayidle -w timeout 1 'swaymsg output "*" power off' resume 'swaymsg output "*" power on; kill $PPID'` | swayidle | keep; power menu calls it (`setsid -f`, `sleep-monitors:27-28`) |
| `sleep-monitors` (30 l.) | fzf Yes/No → `setsid -f monitors-off` | fzf | **replace** by power menu |
| `touchpad-toggle` (34 l.) | reads `swaymsg -t get_inputs` touchpad `send_events`; toggles `input type:touchpad events`; Caps LED on vendor 0b05/product 1b2c; `osd "Touchpad" "on|off"` | swaymsg, jq, brightnessctl | keep |
| `theme` (201 l.) | see §3.5 | — | keep; add a reload hook |
| `theme-prompt` (51 l.) | fzf picker for theme/accent | fzf, theme, wallpaper | **replace** |
| `wallpaper` (52 l.) | `wallpaper [accent|path|list]`; `swaybg -i <path> -m fill`; state `~/.local/state/wallpaper/accent`; calls `theme icons` | swaybg | keep (NOTE: `startup.conf` does not call it; Sway bg is `#000000 solid_color`; MEASURED there is no `exec wallpaper` in startup.conf — INFERRED the accent only drives folder icon colours on this seat today) |
| `claude-capacity` (382 l., python, stdlib) | `--waybar` (default): JSON `{"text","tooltip","class":[...],"percentage"}`; `--json`; `--check --window five_hour|seven_day|seven_day_opus|seven_day_sonnet|any --threshold N` exit 0/1/2; cache in `$XDG_RUNTIME_DIR` TTL 60 s, STALE_GRACE 900 s; endpoint `https://api.anthropic.com/api/oauth/usage` with `~/.claude/.credentials.json` token; **rate-limits (429)**; ICON `U+F06A9` nerd robot | python3, creds (strix only — `hosts/client/default.nix:31-32`: no Claude credential on the client) | **new rail/status widget on the strix side only**; on the client it must be fetched via `ssh strix ~/.local/bin/claude-capacity --json` (INFERRED) or omitted |
| `fzf-nmcli` (255 l., python, `gi.NM`) | Wi-Fi list sorted by strength with security string + bars; toggles Wi-Fi/networking; VPN/GSM rows; connect known / `nmcli device wifi connect <ssid> password <pw>`; deletes a failed new connection | python3 + pygobject + NM (in `pythonForScripts`, `home.nix:77-98`), fzf | **replace** the fzf UI; port the NM logic (D-Bus `org.freedesktop.NetworkManager` via dbus-next). Not bound to any key today (MEASURED: no `fzf-nmcli` in binds.conf); `network-settings` desktop entry opens `nmtui` instead |
| `herdr-picker` (574 l., python) | `--workspace new|close|detach|rename|restore`, `--chord new|sidebar|rename`, `--json` (read-only rows, no GUI); Sway IPC via `swaymsg -r` (`:51-60`); herdr snapshot: `herdr api snapshot` locally when `HERDR_SWAY_LOCAL=1` else `ssh -n ... $HERDR_PROJECTOR_TARGET 'herdr api snapshot'` (`:163-184`, target default `strix`); snapshot shape `{result:{snapshot:{workspaces:[{label,workspace_id,agent_status,...}],agents:[{title,terminal_title_stripped,pane_id,agent_status,agent}]}}}`; marks on projector containers `herdr-slot-N`, `herdr-label-<host>-slot-N-<hex6>`, `herdr-workspace-wXXX`, `herdr-closed-<n>`, `herdr-name-<hex>` (`:24-28`); projector `app_id = herdr-projector`; parked = scratchpad `__i3_scratch`; menu = Vicinae `Ipc/dmenu` JSON-RPC over `$XDG_RUNTIME_DIR/vicinae/vicinae.sock` (`:211-258`) | swaymsg, ssh, vicinae socket, kitty remote control | **the single biggest replacement seam**: the `--json` mode gives rows+actions without GUI (`:505`); the shell's switcher can call `herdr-picker --json` and perform `('view', id)` → `swaymsg [con_id=…] focus`, `('agent', pane_id)`, `('new'|'restore'|'rename'|'open'|'refresh')`. Alternatively patch `vicinae_menu()` to talk to the shell's socket (same request/response shape: rows in, chosen row text out). |
| `sway-workspace` (8 l.) | → `herdr-picker --workspace <verb>` | | keep |
| `herdr-chord` (24 l.) | → `herdr-picker --chord <verb>` | | keep |
| `speak-clipboard`, `screen-ocr-area`, `call-record-menu` | ssh to strix; fzf controller for call-record | | keep (call-record-menu could become a quick-settings toggle: state file `~/.local/state/call-record/current`) |

`HERDR_SWAY_LOCAL` / `HERDR_SWAY_SEAT` are HM `home.sessionVariables` (`home/herdr.nix:93-96`): `HERDR_SWAY_LOCAL = "1"` only on the strix with a display, else `"0"` (asserted `"0"` on both hosts, `flake.nix:1224-1225`). They reach Sway children via the session launcher (`modules/sway.nix:58-62`).

### 3.8 The Zenbook (hosts/client/default.nix, MEASURED)

- ASUS Zenbook Duo UX8406MA, Meteor Lake, two 2880×1800 eDP panels (logical 1440×900 at scale 2), detachable keyboard; "a thin client" (`:21-27`); uid of tom is **1001** (`:184-194`), not 1000.
- `rawDotfiles.inStore = true` (`:101`): no checkout; deploy from the strix (`deploy github:mecattaf/dotfiles/<rev>#client`, `:60`).
- No herdr server, no Claude/Codex credential, no tally, no voxtype (`:29-35`; asserted `flake.nix:1331-1349`).
- Dock daemon (`modules/zenbook-duo-daemon.nix`, `services.zenbook-duo-daemon.enable = true`, `:285`): keyboard on → eDP-2 off; backlights synced; Fn keys → XF86 keysyms. kanshi profiles `Duo` (both panels, gamma 3850/3350 K) and `DuoDocked` (eDP-1 only) (`home/dot_config/kanshi/config:22-32`).
- Panels at max brightness on boot via udev (`:266-274`); Caps LED writable by group video (`:275-277`).
- upower: `percentageAction = 5`, `criticalPowerAction = "PowerOff"` (`:412-416`) — the battery widget should warn before 5%; asusd owns the platform profile (Quiet on AC and battery, `:325-359`); charge cap 60% (`:393-402`) — a battery indicator should expect "not charging at 60%".
- iio-sensor-proxy on (`:421`); rotation deferred.
- Chrome: `--enable-features=WaylandWindowDecorations,AcceleratedVideoEncoder` (`:245-251`).
- Bluetooth radio is here (huion.nix) — a Bluetooth pairing menu talks to local BlueZ.

### 3.9 Feature table (summary, for the PLAN)

| Feature | What exactly | Where it lives today | keep/replace/new | Notes |
|---|---|---|---|---|
| App launcher | Mod+d / Mod+space; app search honouring NoDisplay/Hidden; favorites; calculator, files (Downloads/Documents), clipboard, scripts, tray, media | `vicinae.nix`, `binds.conf:6-7` | replace | font Anthropic Sans 12; overlay layer, exclusive keyboard; opaque; 1 px border |
| Clipboard history | 24 h eviction, ignore passwords, preserve tagged; Mod+v | `vicinae.nix:70-75`, `binds.conf:114`, `startup.conf:4` | replace | `cliphist` + `wl-clipboard` installed (`home.nix:453-454`) but not started; shell runs `wl-paste --watch` |
| Herdr workspace picker | Mod+Ctrl+space; rows: projectors by slot with status, windows, agents, actions | `herdr-picker` | replace UI, reuse `--json` | glyphs ◉/◐/●/✓/○ are NOT in dotfiles main (REPORTED in BRIEF; they are on the `morning-shell` branch) |
| Workspace rename prompt | Mod+Shift+n → Vicinae dmenu free-text | `herdr-picker:402-418` | replace prompt | validation: rejects `"`, `\`, `$`, control chars (`docs/client-sway-vicinae.md:73-76`) |
| Notifications | mako top-center 390 wide, margin 12, padding 14, border 1, radius 0, 5 s, max 4, overlay | `vicinae.nix:111-143` | replace (daemon + toasts) | D-Bus name `org.freedesktop.Notifications`, `Type=dbus` unit |
| OSD | notify-send replace-id + `int:value` progress; 1500 ms | `bin/osd` | replace backend | volume 3%, brightness 10%/2%, touchpad, mic |
| Theme picker | F2 fzf; Shift+F2 accent | `theme-prompt` | replace | call `theme <name>` / `wallpaper <accent>` |
| Audio route | F9 fzf | `audio-route menu` | replace UI | keep verbs |
| Power/sleep monitors | F10 fzf (client: F10 = backlight toggle, see §3.1); Mod+Shift+p | `sleep-monitors`, `monitors-off`, `brightness toggle` | replace UI | new: power menu (lock? none exists — no swaylock in packages, GAP) |
| Pomodoro | Shift+F10 fzf | `pomodoro` | replace UI | rail could show `pomodoro status` |
| Wi-Fi | `fzf-nmcli` (unbound), `network-settings` → nmtui | `bin/fzf-nmcli`, `vicinae.nix:167-169` | replace | NM over D-Bus |
| Bluetooth | none in dotfiles (blueman-manager floats by rule, `rules.conf:6`; not in home.packages MEASURED) | — | new | BlueZ over D-Bus |
| Workspace bar / rail | none ("No bar", `config:2`); old waybar deleted 2026-09-11 (bottom of eDP-2, modules: sway/workspaces, custom/claude-capacity, pulseaudio, backlight, battery, clock; font JetBrainsMono NF 16 px; mocha colours) | git `1d926f2e^:home/dot_config/waybar/*` | new | left rail per BRIEF; waybar's module list is the minimum content set |
| Claude capacity | waybar JSON module, interval 300 s, click → drop cache + `pkill -RTMIN+8 waybar` | `bin/claude-capacity`, old waybar modules | new (rail) | creds strix-only |
| Screenshot/OCR/colour | grim/slurp/satty; ssh OCR | scripts | keep | optional toast |
| Media | playerctl; Vicinae now-playing | `bin/media`, favorites | keep + new | MPRIS via D-Bus |
| Tray (SNI) | Vicinae `core:search-tray` (fallback StatusNotifierWatcher) | `vicinae.nix:89` | new or drop | with Vicinae gone there is no `org.kde.StatusNotifierWatcher` on the bus at all (REPORTED `docs/vicinae-research.md:20-22`) |
| Browser tabs search | Vicinae Chrome extension + native messaging host | `vicinae.nix:98-99`, `modules/sway.nix:102-107` (extension `kcmipingpfbohfjckomimmahknoddnke`) | drop (GAP) | the Chrome policy extension stays declared in `modules/sway.nix:104-106` until removed |
| GTK/icons/cursor | MacTahoe variants via `theme`; Bibata-Modern-Classic 48 | `theme.nix`, `home.nix:320-340`, `input.conf:16` | keep | non-negotiable MacTahoe assert |
| Night light | `wl-gammarelay-rs` + kanshi exec busctl Temperature (eDP-1 3850 K, eDP-2 3350 K) | `startup.conf:3`, `kanshi/config` | keep; new: quick-settings slider via `busctl --user set-property rs.wl-gammarelay /outputs/eDP_1 rs.wl.gammarelay Temperature q N` | |
| Files explorer | nautilus (Mod+e), nautilus-open-any-terminal=kitty | `binds.conf:25`, `startup.conf:11` | new (Pinax-like) alongside | portal FileChooser = gnome (`modules/sway.nix:173`) |

---

## 4. Design values (MEASURED unless noted)

| Token | Value | Source |
|---|---|---|
| UI font (launcher) | Anthropic Sans 12 | `vicinae.nix:36-37` |
| UI font (Sway titles, GTK, mako) | Anthropic Sans 11 | `layout.conf:2`, `home.nix:192`, `vicinae.nix:114` |
| Document font | Anthropic Serif 12 | `home.nix:193` |
| Mono font | AnthropicMono Nerd Font 11 (GTK) / 16.0 (kitty) | `home.nix:194`, `kitty.conf:93` |
| Mono bold | SemiBold, never Bold | `kitty.conf:87`, `docs/fonts/README.md:138-140` |
| Kitty text padding | `window_padding_width 10` | `kitty.conf:112` |
| Kitty cell @192 dpi | 26×54 px (AnthropicMono NF 16.0) | `docs/fonts/README.md:145-150` |
| Window border | 1 px (tiled and floating); `hide_edge_borders smart` | `layout.conf:7-9` |
| Gaps | 0 | `layout.conf:4-6` |
| Desktop bg | `#000000` solid, every theme | `layout.conf:16`, `themes/default.nix:122` |
| Launcher window | opacity 1, material none, rounding 0, border 1, shadow 0, overlay layer, exclusive keyboard | `vicinae.nix:48-61` |
| Notification | width 390, margin 12, padding 14, border 1, radius 0, timeout 5000, max 4, overlay, top-center; bg `ground.raised`, text `fg`, border `border.active` / low `border.inactive` / high `red` + sticky; progress `selection.bg` | `vicinae.nix:114-123`, `themes/default.nix:127-138` |
| OSD timeout | 1500 ms | `bin/osd:28` |
| Volume step | 3% | `bin/volume:25-26` |
| Brightness step | 10% (2% with Shift on the Duo), floor raw 1 | `bin/brightness:3,93`, `home.nix:165-166` |
| fzf prompt floats | 640×200 (audio/sleep/call), 640×300 (theme/pomodoro), centred, border 2 | `rules.conf:12-13` |
| Cursor | Bibata-Modern-Classic, size 48, hide after 1000 ms | `input.conf:16-17`, `startup.conf:6-7` |
| Scale | 2 on every output (client eDP-1/2, strix DP-4/DP-1) | `home.nix:146-151` |
| Gamma | eDP-1 3850 K, eDP-2 3350 K (Duo); DP-4/DP-1 4000 K | `kanshi/config` |
| Pomodoro | 25 / 5 min | `bin/pomodoro:5-6` |
| Clipboard eviction | 86400 s | `vicinae.nix:73` |
| Theme accents list order | noir, claude-dark, claude-light (`theme list` = sorted dir names: claude-dark, claude-light, noir — `bin/theme:35`; `theme toggle` cycles that sorted order) | `bin/theme:33-36,192-198` |
| Wallpaper accents | oat olive cactus sky fig heather coral; default olive | `bin/wallpaper:21-22` |
| Old waybar (history, do not copy visuals) | font 16 px JetBrainsMono NF; `@crust` bar, `@base` modules, 1 px `@mantle` borders, `margin 3px 0`, `padding 0 10px`, radius 0; workspace icons `<span font='16'>` | git `1d926f2e^:…/waybar/style.css` |

Colours: see the role table in §3.5. Rounding: nothing in dotfiles rounds anything (Sway `pixel` borders, mako radius 0, Vicinae rounding 0). BRIEF §3.6's 8/12 inner radii are a new decision from the Tacit aesthetic, not a dotfiles value (INFERRED; flag in ASSUMPTIONS.md).

---

## 5. Reusable code or data (exact paths)

### 5.1 HM module shape to copy for `home/gpuix-shell.nix`

- Gating idiom (MEASURED `home/vicinae.nix:9-10,24`): `let enabled = osConfig.myDisplay.enable; in { config = lib.mkIf enabled { ... }; }`. `osConfig` is available because HM runs as the NixOS module (`docs/theme-switcher-2026-09-17.md:98-100`). Host-specific: `hostName = osConfig.networking.hostName; ... lib.mkIf (hostName == "client")` (`home/herdr.nix:68,98`, `home/home.nix:23,149`).
- Import: add `./gpuix-shell.nix` to `imports` in `home/home.nix:102-115` (alphabetical list; `./vicinae.nix` at `:114`).
- Mutual exclusion with vicinae/mako (BRIEF §2): INFERRED pattern — `options.programs.gpuixShell.enable = lib.mkEnableOption ...;` in the new module, and in `home/vicinae.nix:10` change `enabled = osConfig.myDisplay.enable;` to `enabled = osConfig.myDisplay.enable && !config.programs.gpuixShell.enable;` (vicinae.nix already receives `config`). Add `assertions = [ { assertion = !(cfg.enable && config.programs.vicinae.enable); message = ...; } ]`.
- Packages reach disk through `users.users.tom.packages` (`home-manager.useUserPackages = true`), so binaries land in `/etc/profiles/per-user/tom/bin`, NOT `~/.nix-profile` (`home.nix:411-420`). `home.sessionPath` adds `~/.nix-profile/bin` and `~/.local/bin` (`home.nix:123-126`).
- Overlay registration: `flake.nix:298-311` (add `gpuix-shell = final.callPackage ./pkgs/gpuix-shell { };` beside `fontbuilder`). Hot packages from `nixpkgs-fresh` at `:315-330`.
- Raw files (if any shell config is kept RAW): `config.lib.rawDotfiles.link "dot_config/<dir>"` (`home/raw-dotfiles-guard.nix:96-106`); the guard requires any `%h/.local/bin/<prog>` named in `ExecStart` to exist in the checkout (`:21-26`) — prefer a store path `${pkgs.gpuix-shell}/bin/gpuix-shell` in ExecStart.

### 5.2 Systemd user unit facts (MEASURED)

- Target: `sway-physical-session.target` (`modules/sway.nix:141-150`): `bindsTo graphical-session.target`; `wants graphical-session-pre.target, xdg-desktop-autostart.target`; started by `/etc/sway/physical-session.conf`'s `exec dbus-update-activation-environment --systemd WAYLAND_DISPLAY DISPLAY SWAYSOCK I3SOCK XDG_CURRENT_DESKTOP XDG_SESSION_TYPE XDG_SESSION_DESKTOP && systemctl --user start sway-physical-session.target` (`:122-126`). So units `After=` this target see `WAYLAND_DISPLAY` and `SWAYSOCK` in the manager environment.
- Shutdown: `sway-physical-shutdown.target` conflicts with graphical-session*, `sway-physical-session.target` (`:151-167`); the launcher's `cleanup` starts it and unsets the session vars (`:81-84`).
- The mako unit is the template (`home/vicinae.nix:127-143`): `Unit.ConditionEnvironment = "WAYLAND_DISPLAY"`, `After = [ "sway-physical-session.target" ]`, `PartOf = lib.mkForce [ "sway-physical-session.target" ]`, `Install.WantedBy = lib.mkForce [ "sway-physical-session.target" ]`. Vicinae uses the HM module's `systemd.target = "sway-physical-session.target"` (`:31`). For a D-Bus-activated daemon: `Service.Type = "dbus"; BusName = "org.freedesktop.Notifications"`.
- Env a shell process can rely on: `WAYLAND_DISPLAY`, `SWAYSOCK`, `I3SOCK`, `XDG_CURRENT_DESKTOP=sway-physical`, `XDG_SESSION_DESKTOP=sway`, `XDG_SESSION_TYPE=wayland` (`modules/sway.nix:15-23,63-64`), plus every HM `home.sessionVariables` (`HERDR_SWAY_LOCAL`, `HERDR_SWAY_SEAT`, `:58-62`) and the login vars list (`:24-41`: PATH, SHELL, XDG_DATA_DIRS incl. gsettings schema dirs, XDG_SESSION_ID/SEAT/VTNR...). `theme` checks `XDG_CURRENT_DESKTOP == sway-physical && SWAYSOCK` before `swaymsg reload` (`bin/theme:78`).
- `sway-physical.service`: `Type=simple`, `Slice=session.slice`, `ExecStart=<sway>/bin/sway`, `Restart=no`, `restartIfChanged = false` (`:128-140`; asserted `flake.nix:1227`). Never restart it.
- herdr's unit is the counter-example: NO PartOf, `WantedBy default.target`, `X-SwitchMethod = keep-old` (`home/herdr.nix:98-129`). The shell daemons should NOT use keep-old (they are cheap to restart) — INFERRED.
- Portal config for `sway-physical` (`modules/sway.nix:170-184`): FileChooser gnome, ScreenCast/Screenshot wlr (chooser `slurp -f %o -or`), Secret gnome-keyring, Inhibit none.

### 5.3 Flake checks that must change when vicinae/mako are replaced (MEASURED `flake.nix`, check `home-profiles` at `:1074-1379`)

| Line | Assert | Action |
|---|---|---|
| 1213 | `clientHome.programs.vicinae.enable` | → `!…` when `programs.gpuixShell.enable`; or assert the XOR |
| 1214 | `clientHome.services.mako.enable` | same |
| 1215-1219 | mako unit `Type == "dbus"`, `BusName == "org.freedesktop.Notifications"`, `ExecStart == [ "<mako>/bin/mako" ]` | port to `gpuix-shell-notifications.service` with the same three facts |
| 1220, 1223 | `!…programs.waybar.enable` on both hosts | keep (no waybar) |
| 1221-1222 | strix has no vicinae/mako | keep; add `!strixHome.programs.gpuixShell.enable` or allow (strix `myDisplay.enable = false` anyway) |
| 1228 | `clientHome.programs.vicinae.settings.font.normal.family == "Anthropic Sans"` | → assert the shell's font setting/fragment contains "Anthropic Sans" |
| 1229 | `clientHome.services.mako.settings.font == "Anthropic Sans 11"` | → shell equivalent |
| 1230 | `clientHome.xdg.configFile ? "sway-local.conf"` | keep |
| 1236-1253 | MacTahoe GTK3/GTK4 pointer facts | keep |
| 1259-1286 | no Claude Desktop/ChatGPT, no Chrome `--app` desktop entries (11 names) | keep; the shell must not add `xdg.desktopEntries` with those names |
| 1132-1145 | RAW `binds.conf` must contain the three herdr chord lines + four `Alt+h/j/k/l` lines verbatim | keep those lines untouched when editing binds.conf |
| 1363-1369 | `sway-local.conf` contents (touch map, lid bindswitch, no `$mod+Return `/`$mod+Shift+n ` override; strix has no `bindsym`) | keep |
| 1196-1209 | greetd == swayPhysical == myDisplay; `!programs.niri.enable`; greetd `initial_session.command` ends with `/bin/sway-physical-session` | keep |
| 1224-1225 | `HERDR_SWAY_LOCAL == "0"` on both | keep |

Also `modules/sway.nix:108-113` (vicinae cachix) and `flake.nix:151` (vicinae input) are the removal points; `modules/sway.nix:102-107` the Chrome Vicinae extension policy.

The flake also has an exported-packages comment at `flake.nix:517-522`: the three anthropic-* font packages are UNEXPORTED (built via `nixosConfigurations.<host>.pkgs.<attr>` with `--impure`); a `gpuix-shell` check that builds the package must not depend on the NAS tarballs at eval of the check (INFERRED: keep the font load at runtime by family name, not as a build input).

### 5.4 Data a builder can lift verbatim

- Sway IPC usage patterns: `swaymsg -r -t get_tree`, `get_workspaces`, `get_outputs`, `get_inputs`; `[con_id=N] focus|mark --add|unmark` (`herdr-picker:51-60,204-209`); focused output: `swaymsg -r -t get_outputs | jq -r 'map(select(.focused))[0].name'` (`brightness:106`, `screenshot:111`); focused window content rect (`screenshot:124-126`).
- Herdr snapshot shape and marks: `herdr-picker:24-28,163-202`. Row grammar for the picker: `:466-500` (`Focus|Reopen <slot> · [assigned ]<status> · <label> · view <id>`; `Window <ws> · <title> · view <id>`; `Agent · <status> · <agent> · <label> · <pane_id> · open navigator`; then `New Sway workspace · first available 1–9`, `Restore last closed Herdr workspace`, `Rename current Sway workspace`, `Open Herdr in current workspace`, `Refresh Herdr status`).
- Vicinae dmenu JSON-RPC shape (if the shell wants to be a drop-in for `herdr-picker`'s menu): request `{"jsonrpc":"2.0","id":<random>,"method":"Ipc/dmenu","params":{"req":{"rawContent":"<rows joined by \n>","placeholder":"<prompt>","format":"Data","noSection":true,"noQuickLook":true,"noIcon":false,"noMetadata":false,"noFooter":false,"password":false}}}`, framed by a native-endian `uint32` length; reply `{"id":…, "result":{"output":"<row>"}}` (`herdr-picker:211-258`). Socket `$XDG_RUNTIME_DIR/vicinae/vicinae.sock`. INFERRED: cheapest migration is an env var `HERDR_PICKER_MENU_SOCKET` in herdr-picker pointing at `$XDG_RUNTIME_DIR/gpuix-shell/shell.sock` with the same framing — but that edits a main-branch script; alternatively the shell calls `herdr-picker --json`.
- PipeWire node names for the dock routes: `audio-route:14-17,32-34`.
- NM Wi-Fi row format: `"{active_flag} {ssid:<w}  {sec:<w}  {bars}"` with `NM.utils_wifi_strength_bars` (`fzf-nmcli:125-141`); connect/delete sequence `:217-224`.
- Waybar module content list (what the old bar showed): `sway/workspaces` (icons per workspace), `custom/claude-capacity` (300 s, signal 8), `pulseaudio` (scroll 5, click mute, right-click pavucontrol), `backlight` (intel_backlight, scroll 1%), `battery` (states good 95/warning 30/critical 20, interval 3), `clock` (`%R`, calendar tooltip), `network` (essid, on-click nm-connection-editor) — git `1d926f2e^:home/dot_config/waybar/modules`.
- Theme fragment headers: every generated file starts `# GENERATED by home/theme.nix from home/themes/<name>.nix — edit the palette, not this file.` (`themes/default.nix:15-17`); for JSON use a `"_generated"` key instead (INFERRED).
- `meta` file grammar (`themes/default.nix:224-231`): `name=`, `polarity=`, `claude_code=`, `gtk_theme=`, `color_scheme=`, `icon_suffix=` — read with `read`, never sourced (`bin/theme:38-46`). The shell can read `~/.config/theme/meta` for `polarity` without a new fragment.
- Font check recipe: `fc-list | grep -c AnthropicMonoNerdFont` (expect 12); `fc-match sans-serif` (`docs/fonts/README.md:209-228`).
- Isolation: `~/.local/bin/runtime-test -- cmd` (`home/dot_local/bin/runtime-test`, bubblewrap in `home.packages`, `home.nix:503-504`); the `--render-node` variant is on the hyprland-solid-shell worktree (BRIEF §1).

---

## 6. Gaps / unknowns

1. **Toast anchor conflict**: dotfiles ruling top-center (Tom 2026-10-11, `vicinae.nix:115`) vs BRIEF §3.3 top-right (SHELLS-DIGEST). Not resolvable tonight; recommend top-center (the later, box-specific Tom quote) and note in ASSUMPTIONS.md.
2. **Corner radius**: dotfiles has 0 everywhere; BRIEF wants 8/12 inner. No Tom quote in dotfiles either way.
3. **herdr status glyphs** (◉ ◐ ● ✓ ○) are not in `main`; they come from the unmerged `morning-shell` branch (PR #565). This note did not read that branch.
4. **Browser-tab search** dies with Vicinae's native-messaging host; no replacement in dotfiles. Chrome remote-debugging or the `chrome-stream` package (strix only, `flake.nix:1188-1191`) are the only hooks; unresolved.
5. **StatusNotifier tray**: with Vicinae gone nothing hosts `org.kde.StatusNotifierWatcher`. Decide whether the rail hosts SNI or the shell drops tray support (Vicinae's `tray.enabled=false` already hid the icon; only "Search Tray" used it).
6. **Lock screen**: no swaylock/gtklock in `home.packages` (MEASURED list `home.nix:407-533`); a power menu "lock" item has no actuator. `swayidle` is installed but only used one-shot by `monitors-off`.
7. **Bluetooth**: no tooling in dotfiles (`blueman-manager` only in a float rule). `bluez` is on the client for the Huion (`hosts/client/huion.nix`, not read). Pairing UX is entirely new.
8. **claude-capacity on the client**: needs the strix's credentials; the script reads `~/.claude/.credentials.json` locally. Cross-host fetch path (ssh) is INFERRED, not present.
9. **F10 double binding** on the client (sleep-monitors prompt vs brightness toggle): INFERRED that the later include wins; not measured on the box.
10. **Pointer watch**: whether `mv -T` of the `theme` symlink yields a usable inotify event on `~/.config` is INFERRED; `bin/theme:14-15` says retargets fire no watcher event (for the files behind it). Add the explicit `theme apply` hook regardless.
11. **`docs/client-sway-vicinae.md` keys table** is stale (Mod+C "Open Chrome", Mod+Shift+N "through Vicinae") — use `binds.conf` as truth.
12. **`flake.nix:1131` comment** says rename is not bound; `binds.conf:12` binds it via `sway-workspace rename`. Harmless at eval; the comment is stale.
13. **Not read**: `docs/fonts/nas-and-bootstrap.md`, `pkgs/fontbuilder/*`, `hosts/client/{lid,huion,audio,trackpad}.nix`, `modules/zenbook-duo-daemon.nix`, `home/dot_config/herdr/config.toml`, `docs/vicinae-research.md` beyond line 60, the `morning-shell` / `herdr-sway-context` / `dotfiles-sway-mod-o` worktrees. The strix's Hyprland-era `~/colors` material is outside the repo.
14. **Verification**: nothing here was executed; all MEASURED claims are file reads at `f501e856`. No `nix eval` of the theme fragments was run.

