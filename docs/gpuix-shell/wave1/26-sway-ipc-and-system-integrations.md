# 26 · Sway IPC and system integrations — the builders' protocol reference

Reader: Claude (Fable 5.1), wave 1 of the gpuix-shell overnight build, written 2026-10-20 23:40 CEST
on the strix. Read-only; the only file written is this one. Labels: **MEASURED** (I ran it or read the
exact bytes tonight), **REPORTED** (a file, man page or earlier note says so), **INFERRED** (my reading).
Worktree root `WT` = `/home/tom/.wt/dotfiles/gpuix-shell`. All `file:line` pointers are relative to
`WT` unless they start with `/`.

Scope: every seam the TypeScript shell (`@gpuix/react` 0.11.0 + `@gpuix/native` 0.11.0, bun, no Qt)
has to talk to. One subsection per seam in §5, each with (a) the exact protocol facts, (b) the
TypeScript approach (dbus-next interface names or a subprocess), (c) a risk note. §3 is the
feature table the builders asked for; §6 is what I could not establish tonight.

Companion notes that already cover the *behaviour* Tom relies on (do not duplicate, cross-read):
`18-waybar-mako-vicinae-replacement-inventory.md` §3.1–3.3 (notify-send compatibility matrix, OSD,
makoctl verbs), `16-herdr-api-and-scripts.md` (herdr side), `13-prior-desktop-shell-code.md`
(the Hyprland-era TypeScript), `17-dotfiles-sway-theme-fonts.md` (theme tokens).

---

## 1. What this source is

This note is built from these primary sources, each read tonight:

| Source | Path | What it gave |
|---|---|---|
| `sway-ipc(7)` of the pinned Sway 1.12 | `/nix/store/04g9x522ddd3hi77v013n97li9ccyrhd-sway-1.12/share/man/man7/sway-ipc.7.gz` (rendered to `/tmp/claude-1000/sway-ipc.txt`, 2141 lines) | framing, message types, reply shapes, events (MEASURED text) |
| `swaymsg(1)` same store path | `.../share/man/man1/swaymsg.1.gz` | `-m -r -t -q -s` semantics |
| wlr-layer-shell protocol XML | `/nix/store/zzd5fw16p24abbxf5ci3arj3g7pr45z2-...-source/src/wayland-protocols/wlr-layer-shell-unstable-v1.xml` (v5, has `set_exclusive_edge`) | layer/anchor/zone/keyboard semantics |
| GPUIX 0.11.0 typings | `/home/tom/Downloads/gpuix/packages/native/index.d.ts:668-721,770-785`; `CHANGELOG.md:240-258` | `LayerShellOptions`, `appId` |
| The measured rail probe | `docs/gpuix-shell/evidence/rail-probe/{rail.tsx,smoke.py,shot.png}` | layer-shell works on isolated Sway (BRIEF 23:45) |
| Prior notifications daemon (dbus-next server pattern) | `/home/tom/.wt/hyprland-solid-shell/pkgs/desktop-shell/{notifications-daemon.ts,notifications.ts,notifications-integration.test.ts,ui.tsx,providers.ts,applications.ts,default.nix}` | exact `configureMembers` signatures, private-bus test, controls reads |
| Prior Sway adapter | `/home/tom/.wt/hyprland-solid-shell/design/gpuix-comparison/platform.ts` | `swaymsg` subprocess adapter, name quoting, verify-after-switch |
| Rust gpui-shell (feature mine) | `/home/tom/Downloads/gpui-shell/crates/services/src/{bluetooth,upower,tray,mpris,network,notification,brightness}` | the D-Bus members a working GPUI shell actually uses |
| System bus on the strix (read-only `busctl --system introspect`) | `org.freedesktop.login1`, `org.freedesktop.NetworkManager` 1.56.0, `org.bluez` (absent), `org.freedesktop.UPower` (not activatable here) | live signatures and property values |
| D-Bus interface XML in the store | `.../share/dbus-1/interfaces/org.freedesktop.UPower{,.Device}.xml`, `org.freedesktop.NetworkManager.{Device.Wireless,AccessPoint}.xml`; `bluez-5.87/share/man/man5/org.bluez.{Agent,AgentManager,Adapter,Device}.5.gz` | enums, property lists |
| dotfiles scripts | `home/dot_local/bin/{volume,brightness,osd,screenshot,colorpicker,media,audio-route,monitors-off,sleep-monitors,fzf-nmcli,theme,touchpad-toggle,pomodoro,record}` | subprocess contracts the shell must keep |
| Sway config and HM/NixOS modules | `home/dot_config/sway/{binds.conf,startup.conf,input.conf}`, `home/dot_config/kanshi/config`, `home/home.nix:148-170,436-462`, `home/vicinae.nix:10-171`, `home/themes/default.nix:125-138`, `modules/sway.nix:15-21,42-63,120-149,172-192`, `modules/common.nix:53,261-269`, `hosts/client/{default.nix:133-165,409-416,lid.nix,huion.nix:25-40,trackpad.nix:1-20}` | what exists on the client today |
| Unmerged branches | `/home/tom/.wt/dotfiles/herdr-sway-context/home/dot_local/bin/herdr-attention` (Sway subscribe loop, urgency, `notify-send --wait`), `/home/tom/.wt/dotfiles/morning-shell/home/dot_local/bin/sway-workspace-switcher` | event-loop and attention contracts |
| PipeWire on the strix (read-only) | `wpctl status`, `wpctl get-volume`, `pw-dump` | output formats, cubic-vs-linear volume |
| Tool presence on the strix | `command -v` sweep | which binaries exist here vs only on the client |

Nothing was run against the live Sway on the client (it is 100.121.160.100 over Tailscale and off-limits
tonight), so every client-only runtime value (e.g. the SNI items Chrome registers, UPower
`DisplayDevice` values, kanshi's JSON) is REPORTED or INFERRED, never MEASURED.

---

## 2. Tom's rulings that bind these integrations (verbatim, dated)

- **2026-10-20 ~22:50/23:05 CEST** (BRIEF §1): "the crux of it is that we write scripts and functionality
  that is either a bespoke swaywm shortcut ; or a mod+d menu (vicinae remplacement) that presents a
  given functionality. notify-send remplacement to mako ; a left bar with workspace switcher that
  remplaces waybar" and "the rest, including scripts and other functionality, you can use what comes
  instinctively to you. for wifi menu, or bluetooth pairing menu; etc."
- **2026-10-13 20:41 CEST** (session 7af325ec, via note 05 L115 / note 06 table): "1.11 volume keys
  through viciane popup yes i roll back on that; the way we control brightness and volume should be
  keypress>sway>script execution, no need to tie in vicinae if we don't have to" → the binds stay in
  Sway, the scripts stay the entry point, the shell only *renders* the OSD.
- **2026-10-14** (crepuscule `codex-dotfiles-branch.md:37`, via notes 05/06): "and having a deep sense of
  integation between them. and that way herdr "watiing for input" becomes sway workspace wayland
  urgency . and we can integarte notify-send just as easily aswell" → attention = Sway urgency + a
  notification with an action (the `herdr-attention` contract in §5.1 and §5.3).
- **2026-10-20 10:53:17Z** (note 07 L203): "f10 is just a brightness modiofier; same as f5 f6 . the only
  thing is that since i mn oti mkplementing real sleep (which is good btw, very mininalsostic)" → no
  suspend path in the power menu by default (note 07 ruling 4: monitors off / backlight toggle / lock /
  logout / reboot / poweroff).
- **2026-10-11** (`home/vicinae.nix:115` comment): mako "top and center not top right".
- **2026-10-12** (`home/themes/default.nix:125-126`): "the blue color is not the same as the vicinae
  launcher. i prefer the latter's" → progress bars take `selection.bg`.
- **2026-10-12** (`home/vicinae.nix:18`): "make the font larger than 11 (12 or 14, need to decide, start
  at 12)" → launcher UI font 12.
- **2026-10-11** (`home/dot_local/bin/screenshot:19-21`): "Pictures (i guess screenshots) must be sync'd
  with the strix halo as i want no images saved on the zenbook which is a thin client (transient ones
  eg. clipboard are fine)" → screenshots spool to the strix; clipboard history may live on the Zenbook.
- **2026-09-14** (`home/dot_local/bin/brightness:3`): brightness steps are 10 %; **2026-10-10**
  (`home/home.nix:161-166`): Shift = 2 % fine steps.
- **2026-10-14 13:13:13Z** (note 09 L124): "increase brightness on my asus zenbook to the max. this
  should become a shortcut like f1 f2 perpahs ; and a vicinae-remplacement-launcher" → a "max
  brightness" launcher command and key.
- **2026-10-07** (note 06 table): "the concept of a spotlight menu sort of thing, along with all of the
  contextual information that it can hold at any given moment is probably the most underused item on
  the modern desktop and it should be really strengthened given that we're on swaywm (with its ipc) on
  linux" → the launcher is Sway-IPC-aware (focused workspace/output/app).
- **2026-10-08** (`hosts/client/lid.nix`, `trackpad.nix`): the lid does nothing on any power source;
  F10 is the explicit "go dark"; Bluetooth bonds are per adapter and the trackpad must be `trust`ed
  before `pair`.
- **2026-09-30** (AGENTS.md "Speech input is OUT"): no wake listener, no resident transcription,
  so no microphone-listening surface in the shell beyond the mute toggle.
- Standing (AGENTS.md, BRIEF §1): never restart herdr, the user manager or the live Sway; every
  compositor test under `runtime-test --render-node /dev/dri/renderD128 -- ...`; no timers in dotfiles.

---

## 3. Feature / behaviour inventory

| Feature | What exactly | Where it lives today | Keep / replace / new | Notes |
|---|---|---|---|---|
| Sway socket discovery | `$SWAYSOCK` (fallback `$I3SOCK`, `sway --get-socketpath`); the session exports it to systemd and D-Bus with `dbus-update-activation-environment --systemd WAYLAND_DISPLAY DISPLAY SWAYSOCK I3SOCK XDG_CURRENT_DESKTOP XDG_SESSION_TYPE ...` then starts `sway-physical-session.target` | `modules/sway.nix:15-21,122-126`; `/etc/sway/physical-session.conf` | keep | Client uid is 1001: `SWAYSOCK=/run/user/1001/sway-ipc.1001.<pid>.sock` (REPORTED note 07). Units get it from the manager environment; `ConditionEnvironment=WAYLAND_DISPLAY` as mako does (`home/vicinae.nix:130`). |
| Workspace list / focus | `swaymsg -r -t get_workspaces`, `workspace --no-auto-back-and-forth "<name>"`, `workspace number N` | `platform.ts:45-50`, `sway-workspace-switcher:28-29,82-83`, `binds.conf:60-83` | replace the adapter (in-process IPC), keep the commands | Name quoting rules in §5.1(d). Verify after switch (`platform.ts:49-50`). |
| Sway event stream | `swaymsg -m -r -t subscribe '["workspace","window","shutdown"]'`, one JSON object per line, first line `{"success":true}` | `herdr-attention:166-181` | replace with in-process `SUBSCRIBE` (§5.1 sketch) | Skip `title` and self-caused `urgent` events as herdr-attention does (`:179-182`). Reconnect with backoff on `shutdown`/EOF. |
| Urgency as attention | `[con_id=N] urgent enable|disable`; reconcile against `get_tree` `.urgent`; only herdr `blocked` triggers | `herdr-attention:203-247` | keep logic, host it in the rail/notifications daemon | Marks `herdr-slot-N`, `herdr-label-<label>`, `herdr-workspace-<id>` identify slots (`herdr-picker:25-27`). |
| Workspace rail (1–9 top, 10 bottom) | Mod+1..9 → eDP-1 workspaces, Mod+0 → 10 on eDP-2; 3-finger swipe = next/prev on output | `binds.conf:60-83`, `input.conf:18-19` | new surface (`gpuix-shell rail`), keep binds | Rail is a layer-shell `top` surface, anchor left/top/bottom, exclusive 56 (MEASURED working). GPUIX cannot pick the output → opened on the focused output at creation (§5.2 risk). |
| Notifications server | `org.freedesktop.Notifications` on the session bus, `Type=dbus` unit on `sway-physical-session.target` | mako via `home/vicinae.nix:111-143`; theme `home/themes/default.nix:127-138` | replace (`gpuix-shell notifications`) | Full behaviour matrix in note 18 §3.1. Protocol in §5.3 here. "Never both". |
| OSD | `osd <title> <body> [pct]` → `notify-send -p -t 1500 -a osd [-r id] [-h int:value:N]`, id kept in `$XDG_RUNTIME_DIR/osd-notify.id` | `home/dot_local/bin/osd:27-37`; callers `volume:15-35`, `brightness:170-183`, `touchpad-toggle:31-33`, `audio-route` | keep the script, replace the renderer | The daemon can route `app_name=="osd"` to the OSD window; `value` hint = progress. |
| Volume | `wpctl set-volume @DEFAULT_AUDIO_SINK@ 3%+/-`, `set-mute toggle`, `get-volume` → `Volume: 0.40 [MUTED]`; mic via `@DEFAULT_AUDIO_SOURCE@` | `home/dot_local/bin/volume`; `binds.conf:145-147,152-154`; `home.nix:167` | keep | Displayed number is cubic; linear gain = n³ (MEASURED `pw-dump`: 0.40 ↔ channelVolumes 0.064). |
| Audio route picker (F9) | stable node names by USB serial; `AUDIBLE_FLOOR=0.30` lift | `home/dot_local/bin/audio-route` | keep; a controls row may call it | Node ids are ephemeral; resolve names from `pw-dump` each time (`audio-route:8-10`). |
| Brightness | `brightnessctl --min-value=1 -d <dev> set 10%+/-`; `focused` mode maps Sway output → `/sys/class/backlight/*` by connector; `off/restore/toggle` with `-s/-r` | `home/dot_local/bin/brightness`; `home.nix:158-166` | keep | Duo: `intel_backlight` (eDP-1) mirrored to `card1-eDP-2-backlight` every 500 ms by the dock daemon (`brightness:40-42`). Spell `--min-value=1`, never `-n 1` (`:20-25`). |
| Media keys | `playerctl play-pause|next|previous` on the default player | `home/dot_local/bin/media`; `binds.conf:142-144,155-157` | keep | The music daemon will be an MPRIS player too (`ASSUMPTIONS.md`, music 04). |
| Monitors off / no sleep | `swayidle -w timeout 1 'swaymsg output "*" power off' resume 'swaymsg output "*" power on; kill $PPID'` | `home/dot_local/bin/monitors-off`, `sleep-monitors` (F10 fzf prompt), `binds.conf:127` | keep; power menu calls it | No swayidle *service*, no idle timeout anywhere (MEASURED grep). |
| Lock screen | none: `swaylock` is not installed on any host (MEASURED: zero hits in `home/ hosts/ modules/`; absent on the strix PATH) | — | new decision needed (§6 G2) | `loginctl lock-session` emits `Lock` on the session but nothing listens. |
| Lid / logind | `HandleLidSwitch*` = ignore (3 keys); Sway `bindswitch --reload --locked lid:on output eDP-1 disable` | `hosts/client/lid.nix:67-71`; `home.nix:156-157` | keep | UPower `percentageAction=5`, `criticalPowerAction=PowerOff` (`hosts/client/default.nix:412-416`). |
| Power actions | logind `PowerOff(b)`, `Reboot(b)`, (`Suspend(b)` exists but ruled out by default), `Terminate` session for logout | `org.freedesktop.login1` (MEASURED introspection) | new (`gpuix-shell power`) | No swap → no hibernate (`lid.nix:47-48`). |
| Wi-Fi menu | `fzf-nmcli` (python `gi.repository.NM`): list APs with strength bars, activate known connection, `nmcli device wifi connect <ssid> password <pw>` for new, `nmcli connection delete`, toggle wifi/networking, VPN/GSM rows; desktop entry "Network settings" → `kitty nmtui` | `home/dot_local/bin/fzf-nmcli`; `home/vicinae.nix:167-169` | replace with a GPUIX menu over NM D-Bus (§5.6) | NM 1.56.0 on the strix (MEASURED). The client's profiles are declared (`hosts/client/default.nix:133-163`). |
| Bluetooth pairing menu | nothing in the shell; Tom pairs in `bluetoothctl` with `agent NoInputNoOutput` + `default-agent`, `trust` before `pair` | `hosts/client/{huion.nix:25-37,trackpad.nix:7-16}` | new (§5.7) | Client runs a patched bluetoothd (`huion.nix:185`); never restart `bluetooth.service` from the shell. |
| Tray | Vicinae "Search Tray" today; waybar's tray deleted 2026-09-11 | Vicinae | new (`org.kde.StatusNotifierWatcher` host, §5.10) | Tom has no bar; where tray items go is a design gap (§6 G7). |
| Clipboard history | Vicinae's store (`monitoring=true`, `ignorePasswords=true`, `evictionThreshold=86400`, `preserveTagged=true`); cliphist installed but **no watcher** | `home/vicinae.nix:51-55`; `startup.conf:4`; `home.nix:451-452` | replace: `wl-paste --watch` + own store (§5.11) | Vicinae's history does not export (prior `providerGaps`). |
| Screenshots / colour / OCR | `grim -o <out>` / `grim -g "$(slurp)"` / window geometry from `get_tree`; `satty` annotate; spool + rsync to strix on the client; `slurp -p` + `grim -t ppm` colour; `screen-ocr-area` | `home/dot_local/bin/{screenshot,colorpicker,screen-ocr-area}`; `binds.conf:34,42-46` | keep; launcher commands call them | The launcher must close before `slurp` opens its own overlay (§5.13 risk). |
| Screen recording | `wf-recorder` + `notify-send -u critical -t 0 "Screen Recording Started"` | `home/dot_local/bin/record:10-26` | keep | Critical + `-t 0` must persist in the new daemon. |
| Output profiles | kanshi `Duo` / `DuoDocked` (+ three desktop profiles), each `exec busctl --user set-property rs.wl-gammarelay /outputs/<name> rs.wl.gammarelay Temperature q <K>`; started by `exec sh -c 'sleep 0.5 && kanshi'` | `home/dot_config/kanshi/config`; `startup.conf:3,5` | keep | `kanshictl status` prints JSON; `output` IPC event (`change: unspecified`) is the trigger to re-read `get_outputs`. |
| App launching | Vicinae app search; `xdg.desktopEntries` for dotfiles commands | `home/vicinae.nix:148-170`; entries under `$XDG_DATA_DIRS/applications` | replace (own desktop-entry index, `gio launch`) | §5.12. `gtk-launch` and `dex` are absent (MEASURED); `gio launch` present. |
| Touchpad toggle | `swaymsg input type:touchpad events disabled|enabled` + Caps LED + OSD | `home/dot_local/bin/touchpad-toggle:31-33`; `binds.conf:141` | keep | — |
| Theme reload | `theme` runs `swaymsg reload`, `makoctl reload` if `mako.service` active, `vicinae theme set dotfiles-current` | `home/dot_local/bin/theme:78-91` | replace the two tool reloads with "the shell watches `~/.config/theme`" (BRIEF §3.5) | Add a guarded `gpuix-shell reload` or nothing. |
| Portal screencast chooser | `xdg-desktop-portal-wlr` with `chooser_cmd = slurp -f %o -or` | `modules/sway.nix:181-191` | keep | Not a shell concern; listed so nobody re-implements it. |
| Colour temperature | `wl-gammarelay-rs` D-Bus `rs.wl-gammarelay` on the session bus, `/outputs/<name>`, property `Temperature` (q) | `startup.conf:3`; kanshi execs | new candidate: a controls slider | Session bus, `busctl --user`; per-output objects use `_` for `-` (`eDP_1`). |

---

## 4. Design values touching these integrations

All REPORTED from files unless marked.

| Value | Number | Source |
|---|---|---|
| mako card width / margin / padding / border / radius | 390 / 12 / 14 / 1 / 0 px | `home/vicinae.nix:116-120` |
| mako default timeout / max visible / layer / anchor / font | 5000 ms / 4 / overlay / top-center / "Anthropic Sans 11" | `home/vicinae.nix:114-123` |
| mako colours | bg `ground.raised`, text `fg`, border `border.active`, progress `over selection.bg`; low → `border.inactive`; high → `red` and `default-timeout=0` | `home/themes/default.nix:127-138` |
| OSD timeout | 1500 ms (`-t 1500`) | `bin/osd:28` |
| Volume step | 3 % | `bin/volume:25-26` |
| Brightness step / fine / floor | 10 % / 2 % (Shift) / raw 1 | `bin/brightness:3,13`, `home.nix:161-166` |
| herdr-attention notification | `--urgency=normal --expire-time=15000 --action=default=Open --wait`, summary `Herdr · <workspace>` | `herdr-attention:258-262` |
| Record notifications | `-u critical -t 0` (started), `-u low -t 0` (stopped) | `bin/record:10-26` |
| Rail probe palette (MEASURED file) | bg `#000000`, hairline `#373735`, raised `#171818`, fg `#EAECF0`, muted `#818898`, accent `#70B8FF`; slot cell 32×30 radius 8; rail 56 wide; "Anthropic Sans" 13, mono 11 | `docs/gpuix-shell/evidence/rail-probe/rail.tsx:5-12` |
| Layer geometry (BRIEF §3.3) | rail exclusive 56 (220 expanded); launcher 700×580 top margin 108; toasts 390 wide max 4; OSD bottom margin 96; switcher top margin 108 | BRIEF; conflicts with the 10-11 top-centre mako ruling (note 18 §6 G1) |
| Duo outputs | eDP-1 scale 2 at 0,0; eDP-2 scale 2 at 0,900; logical 1440×900 each | `home.nix:150-152`, kanshi `Duo` |
| Colour temperature | eDP-1 3850 K, eDP-2 3350 K | `kanshi/config:25-26` |
| Launcher font | 12 (Tom 2026-10-12) | `home/vicinae.nix:18` |

---

## 5. Reusable code, data and the per-seam protocol reference

### 5.1 Sway IPC (i3-ipc on `$SWAYSOCK`)

**(a) Facts, MEASURED from sway-ipc(7) of Sway 1.12.**

- Socket: `$SWAYSOCK`, compat `$I3SOCK`, or `sway --get-socketpath`. Stream Unix socket.
- Frame: `"i3-ipc"` (6 bytes) + payload length (u32, native byte order = little-endian on x86_64)
  + payload type (u32 LE) + payload. Replies use the same frame; the reply type equals the request
  type; events have bit 31 set (`0x80000000 | n`). Example in the man page: `69 33 2d 69 70 63 04 00
  00 00 00 00 00 00 65 78 69 74` = `exit` as RUN_COMMAND.
- Message types: 0 RUN_COMMAND, 1 GET_WORKSPACES, 2 SUBSCRIBE, 3 GET_OUTPUTS, 4 GET_TREE, 5 GET_MARKS,
  6 GET_BAR_CONFIG, 7 GET_VERSION, 8 GET_BINDING_MODES, 9 GET_CONFIG, 10 SEND_TICK, 11 SYNC,
  12 GET_BINDING_STATE, 100 GET_INPUTS, 101 GET_SEATS.
- RUN_COMMAND payload is the command text (`;` separates commands); reply is an array, one object
  per parsed command: `{success:boolean, error?:string, parse_error?:boolean}`.
- GET_WORKSPACES reply: array of `{num:int (-1 if no leading number), name, visible, focused, urgent,
  rect:{x,y,width,height}, output}`. In practice each entry also carries `id` (the container id; the
  man page's event example shows it, `platform.ts:26` relies on it) — "properties not listed are
  subject to removal", so treat `id` as stable-in-practice (INFERRED).
- GET_OUTPUTS reply: `{name, make, model, serial, active, dpms, power, primary, scale, subpixel_hinting,
  transform, current_workspace, modes:[{width,height,refresh}], current_mode, rect, hdr}`; `focused`
  is also present (the `brightness:106` and `screenshot:111` jq filters depend on `.focused`).
- GET_TREE node: `{id, name, type: root|output|workspace|con|floating_con, border, current_border_width,
  layout, orientation, percent, rect, window_rect, deco_rect, geometry, urgent, sticky, marks:[],
  focused, focus:[ids], nodes:[], floating_nodes:[], representation, fullscreen_mode, floating,
  scratchpad_state, app_id, pid, visible, shell, inhibit_idle, idle_inhibitors, sandbox_engine,
  sandbox_app_id, sandbox_instance_id, tag, window (X11 id), window_properties:{class,instance,
  transient_for,...}}`. Window content box = `rect.x + window_rect.x` etc. (`screenshot:124-126`).
- SUBSCRIBE payload: JSON array of event names; reply `{"success":true}`; then events arrive on the
  same connection, each as a frame whose type is the event id.
- Events: `0x80000000 workspace` (`change: init|empty|focus|move|rename|urgent|reload`, `current`,
  `old` for focus), `0x80000001 output` (`change: "unspecified"` only), `0x80000002 mode`
  (`change`, `pango_markup`), `0x80000003 window` (`change: new|close|focus|title|fullscreen_mode|
  move|floating|urgent|mark`, `container`), `0x80000004 barconfig_update`, `0x80000005 binding`
  (`change: "run"`, `binding:{command, event_state_mask:[...], input_code, symbol, input_type}`),
  `0x80000006 shutdown` (`change: "exit"`), `0x80000007 tick` (`first`, `payload`),
  `0x80000014 bar_state_update`, `0x80000015 input` (`change: added|removed|xkb_keymap|xkb_layout|
  libinput_config`, `input`).
- GET_VERSION → `{major, minor, patch, human_readable, loaded_config_file_name}`;
  GET_BINDING_STATE → `{name}`.
- `swaymsg -m` is only valid with `-t subscribe`; `-r` raw JSON; `-q` no output; `-s <path>`.

**(b) Commands the shell will send** (all exist in the dotfiles today):
`workspace number N` (`binds.conf:60-69`), `workspace --no-auto-back-and-forth "<name>"`
(`platform.ts:50`), `workspace prev_on_output|next_on_output`, `move container to workspace number N`,
`[con_id=N] urgent enable|disable` (`herdr-attention:206`), `[con_id=N] focus`,
`output "*" power off|on` (`monitors-off:11-12`), `output eDP-1 disable|enable` (`home.nix:156`),
`input type:touchpad events disabled|enabled` (`touchpad-toggle:31-33`), `reload` (`theme:79`),
`exec <cmd>`, `kill`, `fullscreen toggle`, `floating toggle`, `mark --add <m>`.

**(c) 40-line TypeScript client (node:net, works under bun), INFERRED from (a):**

```ts
// pkgs/gpuix-shell/src/sway/ipc.ts — one socket for queries, a second instance for events.
import { connect, type Socket } from 'node:net';
const MAGIC = Buffer.from('i3-ipc');
export const Msg = { RUN_COMMAND:0, GET_WORKSPACES:1, SUBSCRIBE:2, GET_OUTPUTS:3, GET_TREE:4, GET_MARKS:5,
  GET_BAR_CONFIG:6, GET_VERSION:7, GET_BINDING_MODES:8, GET_CONFIG:9, SEND_TICK:10, SYNC:11,
  GET_BINDING_STATE:12, GET_INPUTS:100, GET_SEATS:101 } as const;
const EVENT_NAMES: Record<number,string> = { 0:'workspace', 1:'output', 2:'mode', 3:'window',
  4:'barconfig_update', 5:'binding', 6:'shutdown', 7:'tick', 0x14:'bar_state_update', 0x15:'input' };
export function frame(type: number, payload = ''): Buffer {
  const body = Buffer.from(payload, 'utf8'), head = Buffer.alloc(14);
  MAGIC.copy(head, 0); head.writeUInt32LE(body.length, 6); head.writeUInt32LE(type >>> 0, 10);
  return Buffer.concat([head, body]);
}
export class SwayIpc {
  private buf = Buffer.alloc(0); private pending: Array<(v: unknown) => void> = [];
  onEvent: (name: string, event: unknown) => void = () => {};
  onClose: () => void = () => {};
  private constructor(private sock: Socket) {
    sock.on('data', d => this.feed(d)); sock.on('close', () => this.onClose()); sock.on('error', () => {});
  }
  static connect(path = process.env.SWAYSOCK ?? process.env.I3SOCK): Promise<SwayIpc> {
    if (!path) throw new Error('SWAYSOCK unset: not inside the physical Sway session');
    return new Promise((res, rej) => { const s = connect(path, () => res(new SwayIpc(s))); s.once('error', rej); });
  }
  send<T>(type: number, payload = ''): Promise<T> {
    return new Promise<T>(res => { this.pending.push(res as (v: unknown) => void); this.sock.write(frame(type, payload)); });
  }
  command(cmd: string) { return this.send<Array<{ success: boolean; error?: string; parse_error?: boolean }>>(Msg.RUN_COMMAND, cmd); }
  subscribe(names: string[]) { return this.send<{ success: boolean }>(Msg.SUBSCRIBE, JSON.stringify(names)); }
  private feed(d: Buffer) {
    this.buf = Buffer.concat([this.buf, d]);
    for (;;) {
      if (this.buf.length < 14) return;
      if (!this.buf.subarray(0, 6).equals(MAGIC)) { this.sock.destroy(new Error('bad i3-ipc magic')); return; }
      const len = this.buf.readUInt32LE(6), type = this.buf.readUInt32LE(10);
      if (this.buf.length < 14 + len) return;
      const json = JSON.parse(this.buf.subarray(14, 14 + len).toString('utf8'));
      this.buf = this.buf.subarray(14 + len);
      if (type & 0x80000000) this.onEvent(EVENT_NAMES[type & 0x7fffffff] ?? String(type), json);
      else this.pending.shift()?.(json);
    }
  }
  close() { this.sock.end(); }
}
```

Usage pattern: `const q = await SwayIpc.connect(); const ws = await q.send(Msg.GET_WORKSPACES);` and a
second `const ev = await SwayIpc.connect(); ev.onEvent = ...; await ev.subscribe(['workspace','window',
'output','shutdown'])`. Replies and events can share one socket (events are demuxed by bit 31 and
replies arrive in request order), but a separate event socket keeps the pending queue trivially
correct and mirrors `swaymsg -m`. Reconnect with capped backoff on `close` (herdr-attention
`:160-198` does 1 s → wait); re-query the full state after every reconnect.

**(d) Name quoting (REPORTED, two implementations agree).** Sway does not decode JSON escapes in
workspace names. `herdr-picker:108-113` rejects `"`, `\`, `$` and control characters and wraps in
double quotes; `platform.ts:29` additionally rejects `;`, `,`, DEL, names starting with `--`, and the
reserved words `number next prev current back_and_forth next_on_output prev_on_output`. Reuse that
exact function (copy `quotedName`).

**(e) Risks.** (1) No atomic compare-and-switch: validate before, verify after (`platform.ts:33-51`).
(2) `output` events carry no detail; re-read `GET_OUTPUTS` and expect the rail's own surface to
receive a layer-shell `closed` if its output vanished (eDP-2 is turned off by the dock daemon;
eDP-1 by the lid bindswitch). (3) `title` events stream continuously while agents work; drop them.
(4) `binding` events reveal every Sway chord, useful for a "which key" OSD but noisy. (5) Under bun,
`node:net` Unix sockets work (the prior `platform.ts` note: "Node execFile also works under Bun"),
the sketch above was transpiled with bun 1.4.2 (`bun build --no-bundle`) and `frame(0,'exit')` produced
`69332d697063040000000000000065786974`, byte-identical to the man page's hexdump (MEASURED 23:48 CEST); the
socket path and event demux are still untested — the builder's `*.test.ts` should feed recorded frames.

### 5.2 wlr-layer-shell semantics that matter for `LayerShellOptions`

**(a) Protocol facts, MEASURED from the XML (v5).**

- Layers: `background=0, bottom=1, top=2, overlay=3`. `set_layer` since v2.
- Anchor bitfield: `top=1, bottom=2, left=4, right=8`. Anchoring two opposite edges stretches that
  axis; `set_size` with 0 on an axis requires opposite anchors on that axis or it is a protocol error.
- Exclusive zone: positive only meaningful when anchored to one edge or one edge plus both
  perpendicular edges; `0` = "move me to avoid others' exclusive zones" (a notification); `-1` =
  "do not move me, extend to my anchored edges" (lock screen, wallpaper). The compositor's use is
  "implementation-dependent"; Sway honours it (MEASURED: rail 56 → workspace rect x=56, width=1384).
- `set_exclusive_edge` (v5) disambiguates a corner anchor; the edge must be one of the anchors.
- Keyboard interactivity: `none=0` (default, never focused), `exclusive=1` (top/overlay: the seat
  always gives focus to the top-most exclusive surface; meant for lock screens and password
  prompts), `on_demand=2` (v4; normal click-to-focus semantics, "intended for desktop shell
  components (e.g. panels)").
- `set_margin(top,right,bottom,left)`; `configure(serial,width,height)` must be acked; `closed` is
  sent when the surface will no longer be shown (output destroyed) — "the client should destroy the
  resource ... and create a new surface if they so choose".
- Popups: `get_popup(xdg_popup)` exists; GPUIX draws its `FloatingLayer` inside the window
  (REPORTED CHANGELOG 1146), not as protocol popups.

**(b) GPUIX mapping (MEASURED `index.d.ts:678-713`, `CHANGELOG.md:240-258`).**
`render(node, { appId, width, height, windowBackground:'opaque', focus:false, layerShell: { namespace,
layer:'background'|'bottom'|'top'|'overlay' (default 'top'), anchor:[...] (default ['top','left',
'right']), exclusiveZone (0 compositor decides, negative none), exclusiveEdge, margin:[t,r,b,l]
(exactly four or ignored), keyboardInteractivity:'none'|'on-demand'|'exclusive' (default 'none') } })`.
`appId` "Required in practice for a layerShell surface a compositor is meant to target by rule".
There is **no output field** and no `set_layer` after creation; namespace "cannot be changed after
the surface is created".

**(c) Surface recipes (INFERRED from BRIEF §3.3 + (a)):**
rail: `layer:'top', anchor:['left','top','bottom'], exclusiveZone:56, keyboardInteractivity:'on-demand'`
(not `exclusive`: a panel must be unfocusable by clicking a toplevel). Launcher / switcher:
`layer:'overlay', anchor:['top'], margin:[108,0,0,0], exclusiveZone:0, keyboardInteractivity:
'exclusive'` and **close the window when done** (an idle exclusive overlay steals every key). Toasts:
`layer:'overlay', anchor:['top'] (Tom 10-11) or ['top','right'] (BRIEF), margin:[12,...],
exclusiveZone:0, keyboardInteractivity:'none'`. OSD: `layer:'overlay', anchor:['bottom'],
margin:[0,0,96,0], exclusiveZone:0, 'none'`. Lock-like surfaces would need `exclusiveZone:-1` on all
four anchors plus `exclusive` keyboard — but that is not a session lock (§5.8 risk).

**(d) Risks.** (1) Output choice: Sway puts a new layer surface on the *focused* output; on the Duo
the rail must be created while eDP-1 is focused (`[output=eDP-1]`? not a Sway command; use
`swaymsg focus output eDP-1` before spawn, INFERRED) and re-created on `closed`. (2) Whether GPUIX
re-emits `closed`/configure as a JS event is not in `index.d.ts` (gap G4). (3) Sway 1.12 + wlroots
implement at least v4 (`on_demand` is used by waybar/fuzzel on this fleet); v5 `set_exclusive_edge`
support in Sway 1.12 is unverified. (4) Touch on the Duo: layer surfaces receive touch via
`wl_touch`; GPUIX's handling is unknown (note 18 §6).

### 5.3 `org.freedesktop.Notifications` (Desktop Notifications spec 1.2/1.3)

**(a) Protocol facts (REPORTED spec; signatures MEASURED in the prior daemon and its D-Bus test).**

- Session bus name `org.freedesktop.Notifications`, object `/org/freedesktop/Notifications`.
- `GetCapabilities() → as`. Known capability strings: `action-icons`, `actions`, `body`,
  `body-hyperlinks`, `body-images`, `body-markup`, `icon-multi`, `icon-static`, `persistence`,
  `sound`. mako advertises `actions body body-markup icon-static` (note 18); gpui-shell `actions body
  body-markup persistence` (`notification/mod.rs:390-395`).
- `Notify(app_name s, replaces_id u, app_icon s, summary s, body s, actions as, hints a{sv},
  expire_timeout i) → u id`. `actions` is a flat list of pairs `[key, label, key, label, ...]`; key
  `default` is the "click the body" action. `expire_timeout`: -1 server default (mako 5000 ms), 0
  never, else ms. `replaces_id` 0 = new; a live id is updated in place; a stale id yields a new id
  (mako behaviour `bin/osd:11-13`, verified by Tom against mako 1.11).
- `CloseNotification(u)`; `GetServerInformation() → (name s, vendor s, version s, spec_version s)`.
- Signals: `NotificationClosed(u id, u reason)` with reason 1 expired, 2 dismissed by user, 3 closed
  by `CloseNotification`, 4 undefined; `ActionInvoked(u id, s action_key)`; `ActivationToken(u id,
  s token)` (xdg-activation, spec 1.3 / mako) emitted *before* `ActionInvoked`.
- Hints (`a{sv}`): `urgency` (y: 0 low, 1 normal, 2 critical), `category` (s, e.g. `device.added`,
  `email.arrived`, `im.received`), `desktop-entry` (s, basename without `.desktop`), `image-data`
  (`(iiibiiay)` = width, height, rowstride, has_alpha, bits_per_sample, channels, data; RGB/RGBA
  8-bit rows), `image_data` (deprecated 1.1 alias), `image-path` (s, file path, `file://` URI or
  icon name; `image_path` deprecated), `icon_data` (deprecated 1.0), `resident` (b: stay after an
  action), `transient` (b: not kept in history), `sound-file`, `sound-name`, `suppress-sound`,
  `action-icons` (b: action keys are icon names), `x`/`y` (i: screen position hint), and the
  de-facto `value` (i: progress percent, used by mako, dunst and `bin/osd:32-34`), plus
  `x-canonical-private-synchronous` / `x-dunst-stack-tag` (s: replace-by-tag).
- `notify-send` 0.8.8 (client only, `home/vicinae.nix:145`): `-p` prints the id, `-r ID` replaces,
  `-h int:value:N`, `-a APP`, `-u low|normal|critical`, `-t MS`, `-A key=Label`, `-w/--wait`
  (prints the invoked key and exits when `NotificationClosed` arrives), `-e` transient, `-i ICON`.
  `herdr-attention:258-268` expects stdout `default` after `ActionInvoked(id,"default")` followed by
  `NotificationClosed(id, 2)`.

**(b) TypeScript: the dbus-next server pattern** (MEASURED `/home/tom/.wt/hyprland-solid-shell/pkgs/
desktop-shell/notifications-daemon.ts`, dbus-next 0.10.2 at `.../node_modules/dbus-next`):

```ts
import dbus from 'dbus-next';
const bus = dbus.sessionBus();                      // reads DBUS_SESSION_BUS_ADDRESS from the unit env
bus.on('error', e => { console.error(e); process.exit(1) });
const owner = await bus.requestName('org.freedesktop.Notifications', dbus.NameFlag.DO_NOT_QUEUE);
if (owner !== dbus.RequestNameReply.PRIMARY_OWNER) throw new Error('another daemon owns the name'); // :13
class Notifications extends dbus.interface.Interface {
  constructor() { super('org.freedesktop.Notifications') }
  GetCapabilities() { return ['actions','body','body-markup','icon-static','persistence'] }
  GetServerInformation() { return ['gpuix-shell','Tom','0.1.0','1.2'] }
  Notify(app: string, replaces: number, icon: string, summary: string, body: string, actions: string[],
         hints: Record<string, dbus.Variant>, timeout: number): number { /* store.notify(...) */ return 1 }
  CloseNotification(id: number) { /* store.close(id, 3) */ }
  NotificationClosed(id: number, reason: number) { return [id, reason] }   // signal emitters return the args
  ActionInvoked(id: number, key: string) { return [id, key] }
  ActivationToken(id: number, token: string) { return [id, token] }
}
Notifications.configureMembers({
  methods: { GetCapabilities: { outSignature: 'as' }, GetServerInformation: { outSignature: 'ssss' },
             Notify: { inSignature: 'susssasa{sv}i', outSignature: 'u' }, CloseNotification: { inSignature: 'u' } },
  signals: { NotificationClosed: { signature: 'uu' }, ActionInvoked: { signature: 'us' }, ActivationToken: { signature: 'us' } } });
const service = new Notifications(); bus.export('/org/freedesktop/Notifications', service);
// later: service.NotificationClosed(id, 2); service.ActionInvoked(id, 'default');
```

Hint decoding in dbus-next: `hints.urgency?.value` (number), `hints.value?.value` (number),
`hints['image-data']?.value` is `[w, h, rowstride, hasAlpha, bps, channels, Buffer]` (struct → array,
`ay` → Buffer) — INFERRED from the README type table (`ay`→Buffer, struct→array). Convert to PNG
for `<img>` (GPUIX takes file paths and `data:` URLs; no raw-pixel API in `index.d.ts`) — a tiny
zlib+PNG encoder in TS is ~40 lines; `node:zlib` is available. Chrome writes `image-path` to a temp
file and unlinks it quickly — read it immediately (`gpui-shell notification/mod.rs:441-447`).

Unit: `Type=dbus`, `BusName=org.freedesktop.Notifications`, `After=/PartOf=sway-physical-session.
target`, `ConditionEnvironment=WAYLAND_DISPLAY` (copy `home/vicinae.nix:127-143`); the HM option must
set `services.mako.enable = false` (note 18). Private-bus test recipe: `notifications-integration.
test.ts` under `runtime-test` + `dbus-run-session`, gated by an env var (`DESKTOP_SHELL_DBUS_TEST=1`).

**(c) Risks.** (1) dbus-next 0.10.2 is from 2021 and unmaintained; it works under bun for the prior
daemon's tests (REPORTED), and bun's `bun:test` ran them. (2) Body markup: callers escape HTML
(`herdr-attention:256`); decode entities and strip/convert `<b><i><u><a>` before rendering (GPUIX has
no inline markup). (3) The daemon must own exactly one bus name; Vicinae and mako must be off (BRIEF).
(4) Critical + `-t 0` must never expire (record script).

### 5.4 UPower (`org.freedesktop.UPower`, system bus)

**(a) Facts.** MEASURED from `org.freedesktop.UPower{,.Device}.xml` in the store; the strix has no
UPower ("name is not activatable"), the client enables it (`hosts/client/default.nix:412-416`).

- Manager `/org/freedesktop/UPower`: `EnumerateDevices() → ao`, `GetDisplayDevice() → o`,
  `GetCriticalAction() → s`, `EnumerateKbdBacklights`; properties `DaemonVersion s`, `OnBattery b`,
  `LidIsClosed b`, `LidIsPresent b`; signals `DeviceAdded(o)`, `DeviceRemoved(o)`.
- Display device `/org/freedesktop/UPower/devices/DisplayDevice`, interface
  `org.freedesktop.UPower.Device`: `Type u` (0 Unknown, 1 Line Power, 2 Battery, 3 Ups, 4 Monitor,
  5 Mouse, 6 Keyboard, 7 Pda, 8 Phone, ...), `State u` (0 Unknown, 1 Charging, 2 Discharging,
  3 Empty, 4 Fully charged, 5 Pending charge, 6 Pending discharge), `Percentage d`, `TimeToEmpty x`
  (s), `TimeToFull x`, `EnergyRate d` (W), `Energy/EnergyFull/EnergyFullDesign d`, `IsPresent b`,
  `IconName s`, `WarningLevel u` (0 Unknown, 1 None, 2 Discharging(UPS), 3 Low, 4 Critical,
  5 Action), `BatteryLevel u`, `Online b` (line power), `PowerSupply b`, `UpdateTime t`, `Refresh()`.
  Changes arrive as `org.freedesktop.DBus.Properties.PropertiesChanged`.
- Per-device paths look like `/org/freedesktop/UPower/devices/battery_BAT0`, `.../line_power_AC`;
  Bluetooth peripherals (trackpad, Huion) appear as their own devices with `Type` mouse/keyboard.

**(b) TypeScript.** `const sys = dbus.systemBus(); const o = await sys.getProxyObject(
'org.freedesktop.UPower', '/org/freedesktop/UPower/devices/DisplayDevice'); const props =
o.getInterface('org.freedesktop.DBus.Properties'); const all = await props.GetAll(
'org.freedesktop.UPower.Device'); props.on('PropertiesChanged', (iface, changed) => ...)`. Fallback
when UPower is absent (strix, tests): read `/sys/class/power_supply/*/{type,capacity,status}` as the
prior `ui.tsx:163-180` does.

**(c) Risk.** `getProxyObject` introspects; UPower supports it. The display device aggregates all
batteries and is the right thing for the rail; per-device rows for the trackpad/Huion batteries are a
nice-to-have (BlueZ `Battery1` gives the same number, §5.7).

### 5.5 logind (`org.freedesktop.login1`, system bus)

**(a) Facts, MEASURED by introspection on the strix (systemd of NixOS unstable).**

- Manager `/org/freedesktop/login1`: methods `PowerOff(b interactive)`, `Reboot(b)`, `Suspend(b)`,
  `Hibernate(b)`, `SuspendThenHibernate(b)`, `*WithFlags(t)`, `CanPowerOff/CanReboot/CanSuspend/
  CanHibernate/... → s` ("yes"/"no"/"na"/"challenge"), `LockSession(s)`, `LockSessions()`,
  `UnlockSession(s)`, `GetSession(s) → o`, `GetSessionByPID(u) → o`, `ListSessions() → a(susso)`,
  `Inhibit(what s, who s, why s, mode s) → h` (fd; `what` is a colon list of `shutdown sleep idle
  handle-power-key handle-lid-switch ...`; `mode` `block|delay`), `ListInhibitors() → a(ssssuu)`,
  `CancelScheduledShutdown`. Signals `PrepareForSleep(b)`, `PrepareForShutdown(b)`,
  `PrepareForShutdownWithMetadata(ba{sv})`, `SessionNew/SessionRemoved(so)`, `SeatNew/SeatRemoved(so)`,
  `UserNew/UserRemoved(uo)`. Properties `HandleLidSwitch s`, `HandleLidSwitchDocked s`,
  `HandleLidSwitchExternalPower s` (client sets all three to `ignore`), `IdleAction s` (strix:
  `ignore`), `IdleActionUSec t`, `BlockInhibited s`, `DelayInhibited s` (`shutdown:sleep` here).
- Session `/org/freedesktop/login1/session/auto` (the caller's own session): methods `Lock()`,
  `Unlock()`, `Activate()`, `Terminate()`, `SetIdleHint(b)`, `SetLockedHint(b)`,
  `SetBrightness(subsystem s, name s, value u)`; properties `Id`, `Active b`, `State s`, `Type s`
  (`tty` on the strix's session 2; expected `wayland` under greetd on the client — unverified),
  `Class`, `Seat (so)`, `IdleHint b`, `IdleSinceHint t`, `LockedHint b`, `Name`, `TTY`, `Display`;
  signals `Lock`, `Unlock`.
- `SetBrightness` lets the session owner write a backlight without root (gpui-shell uses it:
  `brightness/mod.rs:189-197`): `subsystem="backlight"`, `name="intel_backlight"`, raw value.

**(b) TypeScript.** `systemBus().getProxyObject('org.freedesktop.login1', '/org/freedesktop/login1')`
→ `getInterface('org.freedesktop.login1.Manager')`; `.on('PrepareForSleep', (start: boolean) => ...)`.
For `Inhibit` the returned `h` needs `new dbus.MessageBus(..., { negotiateUnixFd: true })` or the
low-level `dbus.systemBus({ negotiateUnixFd: true })` (README "Negotiating Unix File Descriptors");
simpler: shell out to `systemd-inhibit --what=... --mode=delay sleep 1`? No — hold the fd in-process
or skip inhibitors entirely (nothing today uses them). Power menu verbs map 1:1 (`PowerOff(true)`,
`Reboot(true)`, `Terminate()` on the session for logout, `Lock()` only once a locker exists).

**(c) Risks.** (1) `Lock()` emits the session `Lock` signal; **no locker is installed** (§3) so the
power-menu "lock" row must either add swaylock to `home.nix` or be omitted (G2). (2) polkit: NixOS
grants active-session users `org.freedesktop.login1.power-off`/`reboot` without a prompt by default
(INFERRED, usual polkit rule); `PowerOff(true)` asks for authorization if needed. (3) `Suspend` works
but Tom ruled it out by default; keep it behind a flag. (4) `PrepareForSleep(true)` is the moment to
pause the music daemon and close toasts; on `false`, re-query Sway outputs (kanshi may re-apply).

### 5.6 NetworkManager (`org.freedesktop.NetworkManager`, system bus)

**(a) Facts.** MEASURED on the strix (NM 1.56.0) and from the store XML; the client has NM too
(`modules/common.nix:53`, profiles `hosts/client/default.nix:133-163`, `logLevel=INFO`).

- Manager `/org/freedesktop/NetworkManager`: `GetDevices() → ao`, `GetAllDevices() → ao`,
  `GetDeviceByIpIface(s) → o`, `ActivateConnection(connection o, device o, specific_object o) → o`
  (`"/"` for "any"), `AddAndActivateConnection(a{sa{sv}} settings, device o, specific_object o) →
  (o path, o active)`, `DeactivateConnection(o)`, `Enable(b)`, `CheckConnectivity() → u`;
  properties `Devices ao`, `ActiveConnections ao`, `PrimaryConnection o`, `State u` (70 =
  CONNECTED_GLOBAL measured; 20 disconnected, 40 connecting, 50 connected-local, 60 connected-site:
  INFERRED NM enum), `Connectivity u` (4 FULL measured; 1 none, 2 portal, 3 limited), `NetworkingEnabled b`,
  `WirelessEnabled b` (writable), `WirelessHardwareEnabled b`, `Version s`; signals `StateChanged(u)`,
  `DeviceAdded(o)`, `DeviceRemoved(o)`, `CheckPermissions`.
- Device `/org/freedesktop/NetworkManager/Devices/N`, interface `.Device`: `Interface s`,
  `DeviceType u` (measured: 1 ethernet `enp191s0`, 13 bridge `cni0`, 16 tun `tailscale0`, 19 vxlan
  `flannel.1`, 32 loopback `lo`; **2 = wifi**), `State u` (100 ACTIVATED measured; 30 DISCONNECTED,
  60 NEED_AUTH, 120 FAILED, 20 UNAVAILABLE, 40/50/70 PREPARE/CONFIG/IP_CONFIG: INFERRED enum),
  `ActiveConnection o`, `Managed b`; signal `StateChanged(u new, u old, u reason)`.
- `.Device.Wireless` (XML): `GetAccessPoints() → ao`, `GetAllAccessPoints() → ao`, `RequestScan(a{sv}
  options)` (empty dict; rate-limited by NM, ~10 s), signals `AccessPointAdded(o)`,
  `AccessPointRemoved(o)`; properties `AccessPoints ao`, `ActiveAccessPoint o` (`/` when none),
  `HwAddress s`, `LastScan x` (ms, CLOCK_BOOTTIME; -1 never), `Mode u`, `Bitrate u`,
  `WirelessCapabilities u`.
- `.AccessPoint` (XML): `Flags u` (bit 0x1 PRIVACY), `WpaFlags u`, `RsnFlags u` (key-mgmt bits:
  0x100 PSK, 0x200 802.1X, 0x400 SAE/WPA3, 0x800 OWE — INFERRED from the NM headers; both 0 and
  Flags&1 → WEP), `Ssid ay` (raw bytes; decode UTF-8 with replacement), `Frequency u` (MHz),
  `HwAddress s` (BSSID), `Mode u`, `MaxBitrate u`, `Bandwidth u`, `Strength y` (0–100),
  `LastSeen i` (s, -1 never).
- `.Connection.Active` (measured on `ActiveConnection/2`): `Id s` (`strix-lan`), `Uuid s`, `Type s`
  (`802-3-ethernet`, `802-11-wireless`, `tun`, `vpn`, `wireguard`), `State u` (2 ACTIVATED measured;
  1 activating, 3 deactivating, 4 deactivated), `Default b`, `Devices ao`, `Connection o`,
  `SpecificObject o` (the AP for wifi), `Vpn b`, `Ip4Config o`.
- `.Settings` at `/org/freedesktop/NetworkManager/Settings`: `ListConnections() → ao`,
  `AddConnection(a{sa{sv}}) → o`, `GetConnectionByUuid(s) → o`; signals `NewConnection(o)`,
  `ConnectionRemoved(o)`. `.Settings.Connection`: `GetSettings() → a{sa{sv}}` (secrets stripped),
  `GetSecrets(s setting) → a{sa{sv}}`, `Update(a{sa{sv}})`, `Delete()`.
- New Wi-Fi connection settings dict (gpui-shell `network/nm.rs:242-266`): `{ "connection": { "id": s,
  "type": "802-11-wireless" }, "802-11-wireless": { "ssid": ay }, "802-11-wireless-security":
  { "key-mgmt": "wpa-psk", "psk": s } }`; use `"sae"` for WPA3-only networks (INFERRED). Passing the
  AP path as `specific_object` ties it to that BSSID's SSID.
- `nmcli` fallbacks (what `fzf-nmcli` does, MEASURED file): list via libnm (`client.get_devices()`,
  `ap.get_strength()`, `NM.utils_wifi_strength_bars`), activate known `client.activate_connection_async`,
  new: `nmcli device wifi connect <ssid> password <pw>` (`:221`), failure cleanup `nmcli connection
  delete <ssid>` (`:224`), toggles `client.wireless_set_enabled`, `client.networking_set_enabled`,
  VPN rows (`is_type(NM.SETTING_VPN_SETTING_NAME)`), GSM rows. Equivalent CLI: `nmcli -t -f
  SSID,SIGNAL,SECURITY,BSSID,ACTIVE,IN-USE device wifi list --rescan yes|no`, `nmcli radio wifi on|off`,
  `nmcli networking on|off`, `nmcli connection up|down <id>`, `nmcli -t -f NAME,UUID,TYPE,DEVICE
  connection show` (measured output format `name:uuid:type:device`).

**(b) TypeScript.** `systemBus().getProxyObject('org.freedesktop.NetworkManager', '/org/freedesktop/
NetworkManager')` → interfaces `org.freedesktop.NetworkManager` and `org.freedesktop.DBus.Properties`.
Find the wifi device: iterate `Devices`, `Get('org.freedesktop.NetworkManager.Device','DeviceType')
=== 2`. Scan: `wireless.RequestScan({})`, wait for `PropertiesChanged` on `LastScan`, then read
`AccessPoints` and each AP's properties with `GetAll`. Dedupe by SSID keeping the strongest BSSID.
Secrets prompt: the shell asks for the PSK in a GPUIX field and passes it in the settings dict
(stored by NM in `/etc/NetworkManager/system-connections`, mode 0600 — no secret agent needed).
`nmcli` stays as the fallback for anything not wired (VPN import, GSM, captive portal).

**(c) Risks.** (1) polkit: adding connections system-wide needs
`org.freedesktop.NetworkManager.settings.modify.system`; NixOS grants it to the `networkmanager`
group, which Tom's user is in (`modules/common.nix:189`). (2) A wrong PSK leaves a half-created
profile: delete it on `Device.StateChanged` reason NO_SECRETS/SUPPLICANT (the `fzf-nmcli:224` idiom).
(3) `AccessPoints` churn; subscribe to `AccessPointAdded/Removed` rather than re-scanning. (4) The
strix has no wifi radio (disabled on reboot), so the menu's wifi half can only be smoke-tested on the
client; test the Ethernet/Tailscale rows on the strix.

### 5.7 BlueZ (`org.bluez`, system bus)

**(a) Facts.** MEASURED from bluez 5.87 man pages; `org.bluez` is not running on the strix (no
adapter), so no live introspection. The client's adapter is `A0:B3:39:06:75:AB` (`trackpad.nix:3`);
`hardware.bluetooth.enable` fleet-wide (`modules/common.nix:269`), `FastConnectable=true`
(`trackpad.nix:29`), patched bluetoothd (`huion.nix:185`).

- Discovery: `org.freedesktop.DBus.ObjectManager` at `/`: `GetManagedObjects() → a{oa{sa{sv}}}`,
  signals `InterfacesAdded(o, a{sa{sv}})`, `InterfacesRemoved(o, as)`. Adapters are
  `/org/bluez/hciN`, devices `/org/bluez/hciN/dev_XX_XX_XX_XX_XX_XX`.
- `org.bluez.Adapter1`: `StartDiscovery()`, `StopDiscovery()`, `SetDiscoveryFilter(a{sv})` (keys
  `Transport` `auto|bredr|le`, `RSSI n`, `DuplicateData b`, `UUIDs as`), `GetDiscoveryFilters()`,
  `RemoveDevice(o)`; properties `Address`, `Name`, `Alias rw`, `Powered rw`, `Discoverable rw`
  (default false, `DiscoverableTimeout` 180), `Pairable rw` (default true), `Discovering ro`,
  `UUIDs`, `Roles`.
- `org.bluez.Device1`: `Pair()`, `CancelPairing()`, `Connect()`, `Disconnect()`,
  `ConnectProfile(uuid)`, `DisconnectProfile(uuid)`; properties `Address`, `AddressType`, `Name`
  (optional), `Alias rw`, `Icon` (optional, e.g. `input-mouse`, `audio-headset`), `Class`,
  `Appearance`, `UUIDs`, `Paired`, `Bonded`, `Connected`, `Trusted rw`, `Blocked rw`, `RSSI`
  (optional, only while discovering), `TxPower`, `Adapter`, `LegacyPairing`, `ManufacturerData`.
  `org.bluez.Battery1`: `Percentage y`.
- Agent: `org.bluez.AgentManager1` at `/org/bluez`: `RegisterAgent(agent o, capability s)` with
  capability `""` (= KeyboardDisplay), `DisplayOnly`, `DisplayYesNo`, `KeyboardOnly`,
  `NoInputNoOutput`, `KeyboardDisplay`; `RequestDefaultAgent(o)`; `UnregisterAgent(o)`. The agent
  object we export implements `org.bluez.Agent1`: `Release()`, `RequestPinCode(device o) → s`,
  `DisplayPinCode(o, s)`, `RequestPasskey(o) → u`, `DisplayPasskey(o, u passkey, q entered)`,
  `RequestConfirmation(o, u passkey)`, `RequestAuthorization(o)`, `AuthorizeService(o, s uuid)`,
  `Cancel()`; reject with `org.bluez.Error.Rejected` or `org.bluez.Error.Canceled`.
- Tom's working sequences (MEASURED files): Huion — `agent NoInputNoOutput`, `default-agent`,
  `scan on`, `trust <mac>`, `connect <mac>` and answer yes (`huion.nix:28-33`); trackpad — `trust`
  **before** `pair`, then `pair`, then `connect` immediately (`trackpad.nix:10-14`); `remove` first
  if a half bond is left. "A bluetoothctl with no stdin hangs at that prompt forever" (`huion.nix:35`).

**(b) TypeScript.** `systemBus()`; `getProxyObject('org.bluez','/')` → `org.freedesktop.DBus.
ObjectManager`; list devices from `GetManagedObjects` filtering keys with `org.bluez.Device1`.
Export an agent: `class Agent extends dbus.interface.Interface { constructor(){super('org.bluez.
Agent1')} RequestConfirmation(device, passkey){ return ui.confirm(...) } ... }` with
`configureMembers({ methods: { RequestPinCode:{inSignature:'o',outSignature:'s'}, RequestPasskey:
{inSignature:'o',outSignature:'u'}, DisplayPasskey:{inSignature:'ouq'}, RequestConfirmation:
{inSignature:'ou'}, RequestAuthorization:{inSignature:'o'}, AuthorizeService:{inSignature:'os'},
DisplayPinCode:{inSignature:'os'}, Release:{}, Cancel:{} } })`, `bus.export('/org/gpuix_shell/agent',
agent)`, then `AgentManager1.RegisterAgent('/org/gpuix_shell/agent','KeyboardDisplay')` and
`RequestDefaultAgent(...)`. Throwing `new dbus.DBusError('org.bluez.Error.Rejected','...')` rejects.
Pairing flow for the menu: `Adapter1.StartDiscovery()` (with filter `{Transport:'auto'}`), list
`InterfacesAdded` devices with `RSSI`, on select: set `Trusted=true` via `Properties.Set`, `Pair()`,
`Connect()`, `StopDiscovery()`.

**(c) Risks.** (1) The patched bluetoothd (`huion.nix:182-185`) must not be restarted by anything the
shell does; a D-Bus client never restarts it. (2) Only one default agent: `bluetoothctl` sessions
Tom opens by hand will fight the shell's agent (`agent off` there, or the shell unregisters when a
pairing dialog is not showing). (3) The Huion's reconnect loop (`huion.nix:23-26`) means device
lists churn; debounce `InterfacesAdded/Removed`. (4) No BlueZ on the strix → only pure-logic tests
there; the compositor smoke must stub the bus (`dbus-run-session` + a fake `org.bluez`).

### 5.8 swayidle / swaylock / idle

**(a) Facts (MEASURED repo state).** `swayidle` is installed (`home.nix:446`) and used exactly once,
as a one-shot (`monitors-off:10-12`). `swaylock` is installed nowhere; no `swayidle` service, no
`timeout` config, no `idlehint`. logind `IdleAction=ignore`. Sway `bindsym --locked` already guards
the media/volume/brightness keys (`binds.conf:152-157`, `home.nix:156-166`), and `bindswitch
--locked lid:*` too. swayidle verbs (help text): `timeout <s> <cmd> [resume <cmd>]`,
`before-sleep <cmd>`, `after-resume <cmd>`, `lock <cmd>`, `unlock <cmd>`, `idlehint <s>`, `-w` wait.
Sway's idle-inhibit state is visible in `get_tree` (`inhibit_idle`, `idle_inhibitors`).

**(b) TypeScript.** Keep `monitors-off` as a subprocess (`spawn('setsid',['-f', ...])` as
`sleep-monitors:30` does). If an idle timeout is ever wanted, run a `swayidle` *user service* on the
session target, not from the shell process (it needs the Wayland idle-notify protocol, which GPUIX does
not expose). Lock: the ext-session-lock-v1 role is not in `LayerShellOptions`; a GPUIX "lock" window
would be a cosmetic overlay, not a lock. The honest options: add `swaylock` (nix) and call
`swaylock -f -c 000000` from the power menu and from `swayidle lock`, or leave "lock" out.

**(c) Risk.** A layer-shell overlay with `exclusive` keyboard and `exclusiveZone:-1` looks like a
lock but can be bypassed (new outputs, crash → desktop visible). Never ship it as a lock.

### 5.9 MPRIS (`org.mpris.MediaPlayer2.*`, session bus)

**(a) Facts (REPORTED spec 2.2; members confirmed by gpui-shell `mpris/dbus.rs` and playerctl).**
Bus names `org.mpris.MediaPlayer2.<player>[.instance-N]`, single object `/org/mpris/MediaPlayer2`.
`org.mpris.MediaPlayer2`: `Raise()`, `Quit()`, properties `Identity s`, `DesktopEntry s`, `CanRaise`,
`CanQuit`, `SupportedUriSchemes`, `SupportedMimeTypes`. `org.mpris.MediaPlayer2.Player`: `Next()`,
`Previous()`, `Pause()`, `PlayPause()`, `Stop()`, `Play()`, `Seek(x offset_us)`, `SetPosition(o
trackid, x pos_us)`, `OpenUri(s)`; properties `PlaybackStatus s` (`Playing|Paused|Stopped`),
`LoopStatus s` (`None|Track|Playlist`, rw), `Rate d`, `Shuffle b` (rw), `Metadata a{sv}`
(`mpris:trackid o`, `mpris:length x` µs, `mpris:artUrl s`, `xesam:title s`, `xesam:artist as`,
`xesam:album s`, `xesam:url s`), `Volume d` (0–1, rw), `Position x` (no change notification; poll),
`MinimumRate`, `MaximumRate`, `CanGoNext/CanGoPrevious/CanPlay/CanPause/CanSeek/CanControl b`;
signal `Seeked(x)`. Discover players with `org.freedesktop.DBus.ListNames()` filtered by the prefix
and track `NameOwnerChanged(name, old, new)`. Chrome exposes `org.mpris.MediaPlayer2.chromium.
instanceN` (REPORTED common behaviour).
`playerctl`: `-l`, `-p NAME`, `-a`, `-F/--follow`, `metadata --format '{{status}} {{artist}} -
{{title}}'`, `play-pause|next|previous|position|volume`. The music daemon will export
`org.mpris.MediaPlayer2.gpuix_music` with dbus-next (ASSUMPTIONS, music 04), so `media` →
`playerctl` keeps working unchanged.

**(b) TypeScript.** `sessionBus().getProxyObject(name, '/org/mpris/MediaPlayer2')` →
`getInterface('org.mpris.MediaPlayer2.Player')` and `Properties.on('PropertiesChanged')` for
`PlaybackStatus`/`Metadata` (README example `:44-66`). For the "now playing" rail chip pick the most
recently changed player (playerctl's `-F` rule). Art: `mpris:artUrl` is `file://` or `https://`;
cache to a file before giving it to `<img>` (music UX rule: no http `<img>`).

**(c) Risk.** Players that die without `NameOwnerChanged` (crash) leave stale proxies; wrap calls in
timeouts. Position needs polling (1 s) only while the chip is visible.

### 5.10 StatusNotifierItem / StatusNotifierWatcher (tray), session bus

**(a) Facts (REPORTED freedesktop SNI draft + KDE dbusmenu; members confirmed in gpui-shell
`tray/dbus.rs`).**
- Watcher: bus name `org.kde.StatusNotifierWatcher`, object `/StatusNotifierWatcher`, interface
  `org.kde.StatusNotifierWatcher`: `RegisterStatusNotifierItem(s service)`,
  `RegisterStatusNotifierHost(s)`; properties `RegisteredStatusNotifierItems as`,
  `IsStatusNotifierHostRegistered b`, `ProtocolVersion i`; signals
  `StatusNotifierItemRegistered(s)`, `StatusNotifierItemUnregistered(s)`,
  `StatusNotifierHostRegistered`, `StatusNotifierHostUnregistered`. The `service` argument is either
  a bus name (item at `/StatusNotifierItem`) or an object path, in which case the item is
  `<sender unique name> + path` (gpui-shell `register_status_notifier_item_manual:155-166`).
  The watcher must drop items whose owner vanishes (`NameOwnerChanged`) and, on start, sweep
  `ListNames()` for names containing `StatusNotifierItem` (`discover_items:110-135`). The host
  registers as `org.kde.StatusNotifierHost-<pid>`.
- Item: interface `org.kde.StatusNotifierItem` (also `org.freedesktop.StatusNotifierItem`):
  properties `Category s` (`ApplicationStatus|Communications|SystemServices|Hardware`), `Id s`,
  `Title s`, `Status s` (`Passive|Active|NeedsAttention`), `WindowId i`, `IconName s`,
  `IconThemePath s`, `IconPixmap a(iiay)` (width, height, ARGB32 big-endian rows),
  `OverlayIconName/Pixmap`, `AttentionIconName/Pixmap`, `AttentionMovieName`, `ToolTip (s a(iiay) s s)`
  (icon name, pixmaps, title, text), `ItemIsMenu b`, `Menu o`; methods `ContextMenu(i x, i y)`,
  `Activate(i,i)`, `SecondaryActivate(i,i)`, `Scroll(i delta, s orientation)`; signals `NewTitle`,
  `NewIcon`, `NewAttentionIcon`, `NewOverlayIcon`, `NewToolTip`, `NewStatus(s)`.
- Menu: `com.canonical.dbusmenu` at the `Menu` path: `GetLayout(i parent, i depth, as props) → (u
  revision, (ia{sv}av) item)` where item props are `label`, `enabled`, `visible`, `icon-name`,
  `icon-data ay`, `toggle-type` (`checkmark|radio`), `toggle-state`, `children-display` (`submenu`),
  `type` (`separator`); `Event(i id, s eventId "clicked"|"hovered"|"opened"|"closed", v data, u
  timestamp)`, `AboutToShow(i) → b`; signals `LayoutUpdated(u revision, i parent)`,
  `ItemsPropertiesUpdated`.

**(b) TypeScript.** Export the watcher with `dbus.interface.Interface` (`configureMembers` with
`properties: { RegisteredStatusNotifierItems: { signature:'as', access:'read' }, ... }`), request the
name with `DO_NOT_QUEUE`, listen to `org.freedesktop.DBus.NameOwnerChanged`. For each item,
`getProxyObject(busName, path)` may fail introspection on some apps; dbus-next's low-level
`bus.call(new dbus.Message({destination, path, interface:'org.freedesktop.DBus.Properties', member:
'GetAll', signature:'s', body:['org.kde.StatusNotifierItem']}))` is the robust path. Decode
`IconPixmap` ARGB → PNG for `<img>`; prefer `IconName` resolved through the icon theme dirs.

**(c) Risks.** (1) No bar: tray items need a home (rail footer or controls popover) — design gap G7.
(2) Only one watcher may exist; Vicinae's "Search Tray" (it hosts its own watcher) must be off.
(3) dbusmenu layouts are deep and lazily populated (`AboutToShow`); render as a GPUIX menu, not a
native popup. (4) Electron/Chrome apps use libappindicator and expect `ProtocolVersion` 0.

### 5.11 Clipboard history (`wl-paste --watch`, wlr-data-control)

**(a) Facts (MEASURED `wl-paste --help` and man page).** `wl-paste -w|--watch <command...>` runs the
command on every selection change with the contents on stdin, "requires a compositor that supports
the wlroots data-control protocol" (Sway does). Env `CLIPBOARD_STATE` = `data` (contents on stdin),
`nil` (empty), `clear` (after `wl-copy --clear`), `sensitive` (the source hinted a secret; `wl-copy
--sensitive`). `-l` lists offered MIME types, `-t` picks one, `-p` primary selection, `-n` no newline,
`-s seat`. `wl-copy --type image/png < file` (`screenshot:114`). `cliphist` is installed (db
`~/.cache/cliphist/db`, `max-items 750`, verbs `store|list|decode|delete|delete-query|wipe`) but no
watcher runs (`startup.conf:4`). Vicinae's policy to carry over: `ignorePasswords`, one-day eviction,
preserve tagged, never auto-paste (`home/vicinae.nix:22,51-55`). Password managers mark secrets with the
MIME `x-kde-passwordManagerHint` (value `secret`) — skip any offer that lists it (INFERRED standard).

**(b) TypeScript.** The daemon spawns `wl-paste --watch gpuix-shell clip ingest` for text (default
type) and a second `wl-paste --type image/png --watch ...` for images, or one watcher that runs
`wl-paste -l` on each event and then `wl-paste -t <best>`; store in `$XDG_STATE_HOME/gpuix-shell/
clipboard/` (sqlite via `bun:sqlite`, or cliphist's db by piping into `cliphist store` and reading
`cliphist list` = `id\tpreview`, `cliphist decode <id>`). Paste = `wl-copy` of the chosen entry
(never type it: no `wtype` injection, matching Vicinae `input_server.enabled=false`).

**(c) Risks.** (1) Each watcher is a Wayland client; it must run inside the session env (unit on the
session target). (2) Large images on every copy; cap bytes and dedupe by hash. (3) The Zenbook is a
thin client: Tom allowed transient clipboard data on it (2026-10-11), so a local store is fine, but
treat it as cache (eviction, no secrets). (4) `CLIPBOARD_STATE=sensitive` only comes from cooperating
copiers (`wl-copy --sensitive`); console copies of tokens carry no mark (note 06 G12) — offer a
"pause history" toggle.

### 5.12 XDG desktop entries and launching

**(a) Facts (MEASURED on the strix).** `XDG_DATA_DIRS=/home/tom/.nix-profile/share:/nix/profile/share:
/home/tom/.local/state/nix/profile/share:/etc/profiles/per-user/tom/share:/nix/var/nix/profiles/
default/share:/run/current-system/sw/share`; entries under `<dir>/applications/*.desktop`, plus
`~/.local/share/applications`. HM's `xdg.desktopEntries` land in `~/.nix-profile/share/applications`
(`home/vicinae.nix:148-170` defines `herdr-picker`, `sway-workspace-new|restore|rename`,
`notifications-dismiss|history`, `network-settings`). Keys that matter: `Type=Application`, `Name`,
`GenericName`, `Comment`, `Keywords`, `Categories`, `Exec` with field codes (`%u %U %f %F` → args,
`%i` icon, `%c` name, `%k` path; strip the rest), `TryExec`, `Icon`, `Terminal`, `NoDisplay`,
`Hidden`, `OnlyShowIn/NotShowIn` (vs `XDG_CURRENT_DESKTOP=sway-physical`), `StartupNotify`,
`StartupWMClass`, `DBusActivatable`, `Actions=` + `[Desktop Action x]` groups (Brave's entry shows the
shape). Launchers: `gio launch DESKTOP-FILE [FILE-ARG...]` is present; `gtk-launch`, `gtk4-launch` and
`dex` are absent; `xdg-open` present.

**(b) TypeScript.** Reuse the parser shape of the prior `applications.ts` (`[Desktop Entry]` group
only, `\s`/`\n` unescape, localized keys ignored). Launch with `gio launch <path>` (handles field
codes, `Terminal=true` and `DBusActivatable`) spawned `detached:true, stdio:'ignore'`, then `unref()`
(prior `providers.ts:85-91`). Better cgroup hygiene (INFERRED): `systemd-run --user --scope
--collect --slice=app.slice -- gio launch <path>` so apps outlive and are not killed with the shell
process (`KillMode=control-group` default).

**(c) Risks.** `Terminal=true` resolution in GLib picks a terminal from its built-in list; set
`org.gnome.desktop.default-applications.terminal exec kitty` via gsettings (the startup.conf already
sets other gsettings keys) or run `kitty -e <exec>` yourself. Icon resolution needs an icon-theme
lookup (hicolor + the active theme under `<dir>/icons/`); GPUIX `<img>` takes paths and `data:` URLs.

### 5.13 Screenshots, colour picker, OCR (grim / slurp / satty)

**(a) Facts (MEASURED help texts and scripts).** `grim [-o OUTPUT] [-g "x,y WxH"] [-t png|ppm|jpeg]
[-s scale] [-c cursor] [-T toplevel-handle] [file|-]`; `slurp [-p point] [-o output] [-d dims] [-f
format] [-b/-c/-s/-B colours] [-r]`, Esc exits non-zero; `satty --filename F --output-filename F
--copy-command wl-copy --actions-on-enter save-to-clipboard,save-to-file,exit --actions-on-escape
exit --disable-notifications` (`screenshot:102-106`). Window geometry from `get_tree`
(`screenshot:124-126`). Colour: `grim -g "$(slurp -p)" -t ppm -` and read the three bytes after the
`P6\nW H\n255\n` header (`colorpicker:14`). Client spool: `~/.local/state/screenshot-spool/`, rsync
`--ignore-existing --mkpath` to `strix:Pictures/Screenshots/`, delete only after a remote sha256
check (`screenshot:40-81`). OCR: `screen-ocr-area` → ssh strix → `http://strix:8731`.

**(b) TypeScript.** Launcher commands run the existing scripts via `spawn` detached. Because the
launcher is an `exclusive`-keyboard overlay, **close the launcher window first** (or hide it) and
then spawn; `slurp` opens its own overlay layer surface and needs the pointer.

**(c) Risk.** A GPUIX overlay still mapped during `grim` appears in the shot; hide toasts/OSD for the
capture (`grim -o` of the focused output includes every layer).

### 5.14 Brightness (brightnessctl / sysfs / logind)

**(a) Facts (MEASURED script + help).** Devices under `/sys/class/backlight/<name>/{brightness,
max_brightness,actual_brightness}`; the script keeps only those whose resolved path contains
`/drm/` (`brightness:54-62`) and maps a Sway output to a device whose path contains `-<connector>/`
(`:65-73`). Duo: `intel_backlight` (eDP-1) and `card1-eDP-2-backlight` (mirrored by the dock daemon
every 500 ms), `asus_screenpad` excluded (`systemd-backlight@backlight:asus_screenpad` disabled,
`hosts/client/default.nix:409`). brightnessctl: `-l`, `g`, `m`, `set N|N%|N%+|N%-`, `-d DEV`,
`-c CLASS`, `--min-value=1` (**not** `-n 1`), `-s/-r` save/restore under `/tmp`, `-m` machine
readable (`device,class,current,percent,max`). Writes work for the `video` group / via udev rules
(brightnessctl's NixOS package is setuid-free and relies on udev ACLs) — REPORTED; the alternative
with no permissions at all is logind `Session.SetBrightness("backlight","intel_backlight",raw)`
(§5.5).

**(b) TypeScript.** Keep calling `brightness up|down|toggle` for the keys (ruling). For a controls
slider, read sysfs directly (`readFile`) and write through `brightnessctl --min-value=1 -d DEV set N%`
(or `SetBrightness`). Change detection: sysfs attributes do not emit inotify; use `udevadm monitor
--subsystem-match=backlight -u` lines, or simply re-read after own writes and on the OSD trigger.

**(c) Risk.** Raw 0 on i915 is backlight power-off (`brightness:13-18`): the slider's minimum is 1.

### 5.15 PipeWire volume (wpctl / pw-dump)

**(a) Facts (MEASURED on the strix, PipeWire 1.6.8).** `wpctl get-volume @DEFAULT_AUDIO_SINK@` →
`Volume: 0.40` or `Volume: 0.40 [MUTED]`; `wpctl set-volume ID VOL[%][-/+]`, `set-mute ID 1|0|toggle`,
`set-default ID`, `status` (tree with `*` on defaults, `[vol: 0.40]`), `inspect ID`. Displayed values
are cubic: `pw-dump` shows the same sink with `Props.channelVolumes [0.064, 0.064]` (0.4³) and
`volume 1.0`, `mute false`. `pw-dump` objects: `type: "PipeWire:Interface:Node"`, `info.props`
(`media.class` `Audio/Sink|Audio/Source|Stream/Output/Audio`, `node.name`, `node.description`,
`object.serial`), `info.params.Props[0]` (`volume`, `mute`, `channelVolumes`); the defaults live in
the `PipeWire:Interface:Metadata` object with `props["metadata.name"] == "default"`, keys
`default.audio.sink` / `default.audio.source` / `default.configured.audio.sink` → `{name}`
(measured: configured = the dock's Sound Blaster, effective = the Ryzen analog sink because the dock
is on the client). Names are stable (USB serial), ids are not (`audio-route:8-10`).

**(b) TypeScript.** Subprocess only (no PipeWire binding in TS): `wpctl get-volume` for the chip,
`pw-dump` (one JSON array) for the route picker, `pw-dump -m`/`pw-mon` long-running for live
updates (REPORTED flag; test it). Keep `volume` as the key handler; the controls slider can call
`wpctl set-volume @DEFAULT_AUDIO_SINK@ N%`.

**(c) Risk.** `pw-dump` is 100s of KB on the client with the dock; parse once and diff, never per
frame. The audible-floor lift (`audio-route:45-52`) must stay in the script path.

### 5.16 kanshi and outputs

**(a) Facts (MEASURED files).** Profiles `Desktop`, `DesktopLeft`, `DesktopRight`, `Duo`, `DuoDocked`
(`home/dot_config/kanshi/config`); each `exec busctl --user set-property rs.wl-gammarelay
/outputs/<Name_with_underscores> rs.wl.gammarelay Temperature q <K>`; started by Sway
`exec sh -c 'sleep 0.5 && kanshi'` after `exec wl-gammarelay-rs run` (`startup.conf:3,5`).
`kanshictl reload|switch <profile>|status` (status = JSON). The dock daemon (`modules/
zenbook-duo-daemon.nix`) flips eDP-2's DRM status and kanshi re-applies a profile.

**(b) TypeScript.** Treat Sway's `output` event as the only trigger: re-read `GET_OUTPUTS`, re-place
surfaces, and if the rail's output disappeared re-create the window. `kanshictl status` is optional
telemetry for a controls "Displays" row; `kanshictl switch Duo|DuoDocked` is a safe action.

**(c) Risk.** Output names are stable (`eDP-1`, `eDP-2`) on the Duo; the desktop profiles name
`DP-1`/`DP-4` for a seat that no longer exists (the strix is headless) — do not show them.

### 5.17 D-Bus plumbing and units (common to 5.3–5.10)

- `dbus-next` 0.10.2: `dbus.sessionBus()` / `dbus.systemBus()` read `DBUS_SESSION_BUS_ADDRESS` /
  the system socket; `getProxyObject(name, path)` introspects (fails for objects without
  `Introspectable` — fall back to `bus.call(new dbus.Message({...}))`); `Variant(signature, value)`;
  `setBigIntCompat(true)` if JSBI is wanted for `x`/`t`; signals via `iface.on('Name', ...)`;
  properties via `org.freedesktop.DBus.Properties` `Get/GetAll/Set` and `PropertiesChanged(iface,
  changed, invalidated)`; services via `dbus.interface.Interface` + `configureMembers` + `bus.export`
  + `bus.requestName` (`NameFlag.DO_NOT_QUEUE`, reply `RequestNameReply.PRIMARY_OWNER`). Unix FDs need
  `negotiateUnixFd: true`. The prior build marks `dbus-next` as an esbuild external
  (`build.ts:23`); the Nix wrapper sets `LD_LIBRARY_PATH` for wayland/vulkan/xkbcommon/fontconfig/
  freetype/libGL/X11/xcb/openssl (`default.nix:34-38`).
- Units: every shell daemon is a user service with `After=` and `PartOf=sway-physical-session.target`,
  `WantedBy=sway-physical-session.target`, `ConditionEnvironment=WAYLAND_DISPLAY` (copy
  `home/vicinae.nix:127-143`); the session script exports `WAYLAND_DISPLAY DISPLAY SWAYSOCK I3SOCK
  XDG_CURRENT_DESKTOP XDG_SESSION_TYPE ...` to the manager and the bus before starting the target
  and **unsets** them at exit (`modules/sway.nix:68-70,122-126`). `sway-physical.service` runs
  `sway` itself (`:128-140`); never `Requires=` it from the shell (restart storms). The
  `raw-dotfiles-guard` fails activation if a unit's `%h/.local/bin/<program>` is missing from the
  checkout (AGENTS.md) — shell units point at the Nix package, not `~/.local/bin`.

### 5.18 Reusable code and data, exact paths

| What | Path | Reuse how |
|---|---|---|
| dbus-next notifications server (79 lines) | `/home/tom/.wt/hyprland-solid-shell/pkgs/desktop-shell/notifications-daemon.ts` | copy; add `value`, `image-*`, `desktop-entry`, `category`, `x-*` tags, `ActivationToken`; change default timeout 6000 → 5000 |
| Notification store + reasons (1/2/3/4), command parser | `.../desktop-shell/notifications.ts` (83 lines), `notifications-client.ts` | copy; add `restore`, keep history on dismiss-all (note 18) |
| Private D-Bus lifecycle test | `.../desktop-shell/notifications-integration.test.ts` | copy as the daemon's smoke under `runtime-test` + `dbus-run-session` |
| Sway adapter with name quoting and verify-after-switch | `/home/tom/.wt/hyprland-solid-shell/design/gpuix-comparison/platform.ts` (+ `platform.test.ts`, 26 mocked tests) | lift `quotedName`, `outputs()`, `workspaces()`, the snapshot shape; swap `swaymsg` for the §5.1 socket |
| Sway subscribe loop with reconnect, urgency reconcile, `notify-send --wait` action | `/home/tom/.wt/dotfiles/herdr-sway-context/home/dot_local/bin/herdr-attention:160-200,203-247,252-280` | port the state machine (python → TS) into the rail/notifications daemon |
| Mod+i switcher rows and fuzzel command (fixtures + tests) | `/home/tom/.wt/dotfiles/morning-shell/home/dot_local/bin/sway-workspace-switcher`, `tests/workspace-switcher/{fixtures,test_switcher.py,smoke.py}` | reuse fixtures as `*.test.ts` inputs for the switcher surface |
| Desktop-entry parser + provider catalogue + gaps | `.../desktop-shell/applications.ts`, `providers.ts:1-90` | copy parser; the catalogue ids become launcher commands |
| Controls reads (wpctl, sysfs battery) | `.../desktop-shell/ui.tsx:160-183` | pattern for `Promise.allSettled` polling every 15 s |
| Rust D-Bus members for every seam | `/home/tom/Downloads/gpui-shell/crates/services/src/{bluetooth/dbus.rs,upower/dbus.rs,tray/dbus.rs,mpris/dbus.rs,network/dbus/*.rs,network/nm.rs:225-272,notification/mod.rs:388-470,brightness/mod.rs:185-210}` | the member lists in §5.4–5.10 were cross-checked against these |
| Scripts to keep calling | `home/dot_local/bin/{volume,brightness,osd,media,audio-route,monitors-off,screenshot,colorpicker,screen-ocr-area,touchpad-toggle,theme,record,pomodoro}` | subprocess; never re-implement the device logic |
| Wi-Fi menu logic to port | `home/dot_local/bin/fzf-nmcli` (libnm python; `nmcli` for connect/delete) | behaviour reference for §5.6 |
| Pairing recipes | `hosts/client/huion.nix:25-37`, `hosts/client/trackpad.nix:7-16` | the Bluetooth menu's happy path and its ordering rule |
| mako theme fragment (tokens) | `home/themes/default.nix:127-138` | the toast colours; render a `gpuix-shell.json` sibling |
| Session target and env export | `modules/sway.nix:15-21,42-70,120-149`; `home/vicinae.nix:127-143` | unit template |
| Layer-shell proof + smoke | `docs/gpuix-shell/evidence/rail-probe/{rail.tsx,smoke.py}` | every surface smoke starts from this recipe |
| Protocol text dumps made tonight | `/tmp/claude-1000/sway-ipc.txt` (volatile) | re-render from the store path in §1 if needed |

---

## 6. Gaps and unknowns

- **G1 Toast position.** Tom 2026-10-11 "top and center not top right" vs BRIEF §3.3 / SHELLS-DIGEST
  top-right. Note 18 §6 G1 proposes top-centre with a config option; integrator to log in
  ASSUMPTIONS.md.
- **G2 Lock.** No `swaylock` anywhere; logind `Lock` has no listener; GPUIX has no session-lock role.
  Either add swaylock in `home.nix` (one line) and bind it, or drop "lock" from the power menu.
  Default tonight (INFERRED): drop it and record the decision.
- **G3 Output targeting.** `LayerShellOptions` has no output; the rail lands on the focused output at
  creation. Whether GPUIX surfaces a `closed` event (so the rail can re-create itself on eDP-1 after
  the dock daemon/lid toggles) is not in `index.d.ts`. Needs a probe under `runtime-test` with two
  headless outputs (`WLR_HEADLESS_OUTPUTS=2`).
- **G4 Layer-shell v5 in Sway 1.12.** `exclusiveEdge` support unverified; avoid corner anchors
  that need it (toasts anchored to one edge only).
- **G5 Touch on layer surfaces** through GPUIX (Duo panels): unknown (note 18 §6 says the same).
- **G6 dbus-next under bun with `bun build`** for the *production* bundle: the prior build marked it
  external and ran from `node_modules`; confirm `autoPatchelf`-free pure-JS works in the Nix build.
- **G7 Tray home.** Tom has no bar; SNI items (Chrome, Brave, OBS, Tailscale?) need a surface: rail
  footer, controls popover, or launcher "Search Tray" rows (Vicinae parity). Design call.
- **G8 Sway event demux under load.** The sketch shares a socket for replies and events; untested.
  Builder test: feed interleaved recorded frames (`herdr-attention` fixtures are JSON lines, not
  frames — generate frames with `frame()`).
- **G9 UPower on the client.** Not measurable from the strix; `DisplayDevice` values (Duo battery,
  Bluetooth peripherals as separate devices) are INFERRED. Fallback sysfs path is in place.
- **G10 Wi-Fi WPA3/SAE and enterprise (802.1X)** need different settings dicts and a secret agent for
  identity/password; only PSK is specified above. The client's declared profile `thomas-6ghz`
  (`hosts/client/default.nix:136`) must not be re-created by the menu — activate the existing one.
- **G11 BlueZ agent vs bluetoothctl.** When Tom pairs by hand with `default-agent`, the shell's agent
  must step back; no mechanism specified. Also `bluetoothctl` is absent on the strix, so the pairing
  UI can only be exercised on the client or against a fake bus.
- **G12 Clipboard image handling** and size caps; `wl-paste --watch` per type vs one watcher with
  `-l` — pick one in the build (recommend one text watcher + one `image/png` watcher).
- **G13 App launch cgroups.** `gio launch` children inherit the shell service's cgroup; use
  `systemd-run --user --scope` or `KillMode=process` — unverified under the HM unit.
- **G14 `pw-dump -m` / `pw-mon` as a long-running monitor** under bun `spawn`: output framing
  (one JSON array per update) untested.
- **G15 polkit prompts.** `PowerOff/Reboot`, NM `AddAndActivateConnection`, BlueZ pairing may raise
  polkit challenges on the client; there is no polkit agent in the session (grep: none declared).
  If a challenge appears, the call fails with `org.freedesktop.DBus.Error.AccessDenied` — surface it.
- **G16 `ActivationToken` and xdg-activation**: Chrome web notifications want a token to raise their
  window; GPUIX has no `xdg_activation_v1` API — INFERRED limitation; actions can instead
  `[app_id=...] focus` via Sway.
- **G17 kanshi `status` JSON shape** not captured (needs a live session).

What was not done: no live Sway, no client host, no `bun` run of the sketch, no D-Bus write of any
kind. Every call above that mutates state is still only text.

---

## 7. Verification addendum (second pass, 2026-10-21, same reader)

A second pass of this reader found the note already written and re-checked a sample of its claims
against the worktree and the strix instead of rewriting it (light verification per Tom's 2026-10-20
workflow rule). MEASURED on this pass, all consistent with the text above:

- `file:line` pointers resolve as cited: `bin/osd:27-37` (`-p -t 1500 -a osd`, `-r <id>`,
  `-h int:value:N`, id file `$XDG_RUNTIME_DIR/osd-notify.id`), `bin/volume:25-26` (3 % steps),
  `bin/brightness:3,13,20-25` (10 % steps, `--min-value=1` spelling rule), `home/vicinae.nix:111-123`
  (mako top-center / 390 / 12 / 14 / 1 / 0 / 5000 / 4 / overlay), `home/themes/default.nix:125-138`,
  `bin/screenshot:102-106,124-126`, `bin/monitors-off:10-12`, `sway/startup.conf` (wl-gammarelay-rs,
  kanshi after 0.5 s, `theme apply`), `kanshi/config` Duo profile (3850 K / 3350 K), `bin/fzf-nmcli:219-226`
  (`nmcli device wifi connect … password …`, delete on failure), `sway/binds.conf:60-69,127,141-157`,
  `home/home.nix:156-167`, the 79-line `notifications-daemon.ts` (`DO_NOT_QUEUE`/`PRIMARY_OWNER` guard
  at lines 12-13), and `index.d.ts:668-713` (`LayerShellOptions`: namespace, layer, anchor,
  exclusiveZone, exclusiveEdge, margin, keyboardInteractivity; no output field).
- `swaylock`/`swayidle` grep over `home/ hosts/ modules/`: swayidle only in `home.nix:445-446`,
  `binds.conf:126`, `monitors-off`; swaylock nowhere. Unchanged.
- sway-ipc(7) event ids re-read from the store man page: `0x80000000..07` and `0x80000014`,
  `0x80000015` exactly as listed in §5.1.
- Tool presence on the strix (`command -v`): present `gio xdg-open wl-paste wl-copy cliphist playerctl
  brightnessctl wpctl pw-dump pw-mon kanshi kanshictl satty grim slurp swayidle busctl nmcli`; absent
  `gtk-launch gtk4-launch dex swaylock notify-send bluetoothctl`. (`notify-send` and `bluetoothctl`
  are client-only, as §5.3 and §5.7 say.)

Still unverified after this pass (unchanged from §6): no live Sway or client host was touched, the
§5.1 socket demux has not run against a real `$SWAYSOCK`, and no D-Bus call that mutates state was made.
