# gpuix-shell — SCOPE (the functionality list)

Synthesis for the overnight gpuix-shell build (2026-10-20/21), second pass (2026-10-21, after the
re-run of notes 15, 18, 19, 21, 23, 24, 26 and the reading of 27–30). Written from `BRIEF.md` and
all 31 wave1 notes. This is THE feature list of the shell: what it does, how each thing is
triggered, where its data comes from, what it replaces, when it is built, and how we know it works.

**Reading guide**

- `S-nnn` is the feature id. Ids are stable; never renumber, only append. Rows added in this pass
  are marked **(new)**; rows whose substance changed are marked **(rev)**.
- **Trigger**: `bind` (a Sway bindsym calling the CLI), `launcher` (a root item / provider in Mod+d),
  `CLI` (`gpuix-shell <verb>` over `$XDG_RUNTIME_DIR/gpuix-shell/shell.sock`), `auto` (daemon reacts
  to an event), `click` (pointer on a surface), `D-Bus` (another process calls us).
- **Replaces**: `vicinae`, `mako`, `waybar` (deleted 2026-09-11, nothing on screen today), `script`
  (an fzf/kitty prompt or a `~/.local/bin` script is retired or wrapped), `none` (new).
- **Priority**: **P0** = must be on the Zenbook for Tom in the morning; **P1** = built this run after
  P0; **P2** = foundation seam or later. Counts are at the end.
- **Acceptance**: a pure `bun test`, a compositor smoke under
  `runtime-test --render-node /dev/dri/renderD128 -- …` (WLR_RENDERER=gles2, grim pixel asserts), or a
  hand check Tom can do in a minute. Nothing here runs against the live session. No test dials
  strix:8731.
- `[w1-NN]` cites the wave1 note that grounds the row; `[BRIEF]` cites `BRIEF.md`. **INFERRED** marks
  a decision made tonight without a Tom ruling; each is also logged as a `SCOPE:` line in
  `ASSUMPTIONS.md`.
- Standing verb taxonomy for every write: READ / WRITE-reversible / ACTION-irreversible /
  SECRET-AUTH. "Lock is a verb, unlock is not." Irreversible actions always hold-to-confirm. Secrets
  (wifi passwords, BT passkeys, polkit) never travel over `shell.sock`. The shell never steals focus
  from IPC, never calls `herdr workspace focus` (server-global), never writes Sway config
  [w1-07][w1-10][w1-16][w1-29 §4][w1-30 §3.2].
- Tom's March 2026 priorities list (280 rows, `ANNOTATED-feature-matrix.md`, "AM #n") and the kmux
  rulings are the acceptance backbone; four March rulings were reversed later and must not be
  restored: niri → Sway, dark glass → flat opaque, SF fonts → Anthropic fonts, "no light theme" →
  three themes switched by hand [w1-27 §6.1][w1-28 §1.4][w1-29 §2.6][w1-30 §4.3].

---

## 0. Foundations (cross-cutting)

| ID | Behaviour | Trigger | Data source | Replaces | P | Acceptance | Refs |
|---|---|---|---|---|---|---|---|
| S-001 **(rev)** | Process model. Always-on daemons: `gpuix-shell rail` (one per output), `gpuix-shell notifications` (toasts + OSD + centre), `gpuix-shell music serve` (P1); each a user unit `PartOf=sway-physical-session.target`, `Restart=on-failure`, `XDG_CURRENT_DESKTOP=sway-physical` on the seat. On-demand overlays (launcher, switcher, controls, power, cheatsheet, files, ask) are **spawned per show** by the CLI and `process.exit(0)` on close: GPUIX 0.11.0 has one window per renderer and no window close/hide, so "toggle" = spawn if absent, SIGTERM if present (~0.3 s warm start measured). Several renderers per process work, but we keep one surface per process for crash isolation. | auto (unit) / CLI | systemd user units from `home/gpuix-shell.nix` | vicinae unit, mako unit | P0 | `systemctl --user list-units 'gpuix-shell-*'` shows rail + notifications active after a fresh Sway session (hand check); smoke: launcher toggle twice → map then unmap within 0.5 s | [BRIEF §3.2][w1-03][w1-15][w1-21] |
| S-002 **(rev)** | One CLI, one socket: `gpuix-shell <surface> <verb> [args]` over `$XDG_RUNTIME_DIR/gpuix-shell/shell.sock`; length-prefixed JSON (4-byte native-endian + JSON-RPC 2.0, the Vicinae framing `herdr-picker` already speaks) with per-connection reply routing; exit codes 0 ok / 1 error / 2 usage / 3 surface not running / 69 unavailable. The CLI entry point must **not** load `@gpuix/native` (the addon load costs ≈0.1 s per call); it is a plain Bun script that talks to the socket and spawns surfaces. Router (`shelld`) lives in the rail process (INFERRED: the rail is the one always-on surface on eDP-1); the notifications process registers its verbs with it. | CLI | socket | `vicinae` CLI, `makoctl`, `$prompt` fzf wrappers | P0 | bun test: framing round-trip, concurrent `select` + `status` replies do not cross; `gpuix-shell ping` exits 0 in < 50 ms | [w1-10][w1-18][w1-21][w1-36 §3.5] |
| S-003 | Sway binds call the CLI; keypress → Sway → script/CLI is the only input path. No global-shortcut daemon, no key grabbing in the shell; Super is `cmd` inside GPUIX key handlers. | bind | `home/dot_config/sway/binds.conf` | vicinae `global_shortcuts` | P0 | every rewired bind in §22 resolves to an existing CLI verb (bun test over a rendered binds list) | [w1-04][w1-09][w1-15][w1-17] |
| S-004 | Sway i3-ipc client in TypeScript: two sockets (one command, one subscribe), subscribe-before-query, SEND_TICK barrier, verify-after-switch, name quoting for workspaces, ~50 ms event coalescing, reconnect backoff 2 s → 30 s, 1 MiB buffer guard. | auto | `$SWAYSOCK` | own | P0 | bun test against a fake i3-ipc server; smoke: `workspace` events arrive within one frame on headless Sway 1.12 | [w1-10][w1-26][w1-29 §5 MA B15][w1-30 AM #171] |
| S-005 **(rev)** | herdr reader: `herdr api snapshot` + `herdr workspace list` + `herdr agent list` polled on wake-ups from `events.subscribe` (one request per connection; events are a wake-up only, never state). Slot identity from Sway marks `herdr-slot-N`, `herdr-label-<seat>-slot-N-<hex6>` with seat `client\|strix`, `herdr-closed-<ns>`, `herdr-name-<hex>`; labels may repeat slot numbers, and the label's own slot number is history (shown as a dim chip only when it differs). Status enum `idle\|working\|blocked\|done\|unknown` → glyphs ◉ ◐ ● ✓ ○ and the words "Needs input" / "New activity"; the March seven-state FSM maps `waiting_*` → blocked, `spawning` → unknown. Metadata fields (`report-metadata`: model, tokens, diff stat) are optional: render only what the snapshot proves. **Read-only**: the shell never spawns, closes or focuses herdr workspaces itself; lifecycle stays with the `herdr-chord` / `sway-workspace` binds. | auto | herdr CLI + Sway marks | `herdr-bar` scraping | P0 | bun test on recorded snapshots (nine-slot mapping, label repeats, `strix-slot-*`, closed marks, missing metadata); smoke: a fake `herdr` on PATH drives the rail glyphs | [w1-07][w1-16][w1-25 §5.6 §6][w1-28 §6.10] |
| S-006 | D-Bus layer via dbus-next 0.10.2: session bus server roles (`org.freedesktop.Notifications`; later SNI watcher, BlueZ Agent1, polkit agent, NM SecretAgent) and system bus clients (UPower, logind, NetworkManager, BlueZ, power-profiles-daemon, MPRIS, wl-gammarelay-rs). One connection per process, reconnect on NameLost. Exactly one owner per bus name (never beside mako / polkit-gnome). `--check-dbus` self-test flag. | auto | session + system bus | own | P0 | bun test with `dbus-run-session`: name ownership, introspection; `gpuix-shell notifications --check-dbus` exits 0 | [w1-21][w1-23][w1-26][w1-29 §3.5] |
| S-007 **(rev)** | Theme fragment `~/.config/theme/gpuix-shell.json` rendered by `home/themes/default.nix` for noir (default, OLED `#000000`), claude-dark, claude-light; DTCG-style keys: surface ladder, text three levels, selection.bg ("the vicinae blue"), both run-state families (`--dot-*` Primer attention/danger/success for the rail, `--status-*` elsewhere), **corners**: outer surfaces 0 (Tom set Vicinae rounding 0, "square corners", dart's "lack of rounded borders"), inner rows/popups 6, kit 12/16 kept as keys (INFERRED), motion one token 120 ms curve (0.2,0,0,1) with a scale that may be 0, **type**: launcher UI 16 px (= Tom's Vicinae `font.size` 12 pt), rail chrome 13 px, row titles 14 px (INFERRED reconciliation of DESIGN 13/14 px with Tom's 12 pt), AnthropicMono Nerd Font for figures, Anthropic Serif for documents, Anthropicons glyphs with Lucide SVG fallback. Variable Anthropic Sans renders no bold in GPUIX: static Regular/Medium/Semibold instances are registered via `registerFont` from `~/.local/share/fonts`, never committed. Every surface watches the `~/.config/theme` symlink and re-renders live; the `GpuixTheme` defaults (DejaVu, indigo) are always overridden. Fonts never in git. | auto | theme symlink + fragment | vicinae `theme set`, mako colours | P0 | bun test: fragment schema validates for all three themes (`checks.gpuix-shell-themes`); smoke: flip the symlink, grim shows the rail background change within 300 ms; smoke: a Semibold run renders heavier than Regular | [BRIEF §3.5][w1-11][w1-15][w1-17][w1-25 §6.1][w1-27 §2.3][w1-28 §4] |
| S-008 | Flat opaque look everywhere: hairlines not shadows, no blur, no frost, no gradients, generous insets (12–20 px), no tooltips on the rail, overlays snap (no slide), motion only opacity/transform, colour only for meaning (one accent + semantic). | — | theme fragment | — | P0 | design-lint bun test over the component library (no `shadow`, no alpha < 1 on surfaces, no colour literal outside the fragment) | [BRIEF §1][w1-11][w1-20][w1-29 §4 11–12] |
| S-009 | Config: one JSON config per surface rendered by Nix next to the theme fragment (rail zones per output, toast anchor, hidden apps, favourites, provider prefs, clipboard rules, chords); validated at start by one TypeScript schema (zod 4); no settings GUI, no plugin browser ("no hierarchy"), no TOML. State lives in `$XDG_STATE_HOME/gpuix-shell/`, caches in `$XDG_CACHE_HOME/gpuix-shell/`. | auto | `~/.config/gpuix-shell/*.json` | vicinae `settings.json` + `VICINAE_OVERRIDES` | P0 | bun test: schema rejects a bad key; defaults render without a user file | [w1-29 AM #175 #178 #200][w1-30 §2.7][w1-36 §3.8] |
| S-010 | `ui-tree` test seam: every surface exposes its rendered tree (29-node vocabulary, testIds) over the socket (`gpuix-shell <surface> ui-tree`) so tests assert content without screenshots; GPUIX has no test renderer on Linux (`hasTestGpuixRenderer() === false`). Automation `launch()` works and is the smoke driver. | CLI | in-process React tree | none | P0 | bun test: tree JSON validates; smoke: `ui-tree` of the rail lists nine slot rows | [w1-03][w1-10][w1-14][w1-15] |
| S-011 **(rev)** | Compositor smoke harness `tests/gpuix-shell/smoke_<surface>.py` (never `test_*.py`, so pytest discovery stays clean): headless Sway 1.12 under `runtime-test --render-node /dev/dri/renderD128`, WLR_RENDERER=gles2 (pixman fails), grim pixel asserts, `simulateClick`/keystrokes only; never against the live session. `wtype` loses its first key: smokes send a no-op key first. | CI/dev | — | — | P0 | each P0 surface has one smoke that passes under the wrapper; measured baseline: a 56 px rail with exclusive zone maps on headless Sway | [BRIEF §4][w1-03][w1-08][w1-14][w1-15][w1-21] |
| S-012 **(rev)** | Nix: `pkgs/gpuix-shell/default.nix` (buildNpmPackage + autoPatchelf, appendRunpaths, bun build with externals, lockfile = `package-lock.json` only, `bun.lock` deleted, `git add -N` so untracked files are visible to the flake), native self-tests `--check-native` / `--check-dbus` in **`installCheckPhase`** (they need the patched binary), `--check-theme` in a separate `checks.gpuix-shell-themes`, no `LD_LIBRARY_PATH` in the wrapper, closure ≈213 MiB; HM module `programs.gpuixShell` with an assertion that vicinae and mako are disabled when enabled (never both), flake asserts in `home-profiles` updated. | build | flake | vicinae HM module, mako HM | P0 | `nix build .#gpuix-shell` runs installCheckPhase; `nix flake check` runs the theme check; HM evaluation fails if `services.mako.enable` is also true | [w1-18 plumbing][w1-21 rev2] |
| S-013 | Dev loop and logs: `journalctl --user -u gpuix-shell-<surface>`, `gpuix-shell <surface> logs -f`, `GPUIX_SHELL_DEV=1` runs a surface from the checkout. | CLI | journald | `vicinae logs` | P1 | hand check | [w1-21][w1-36 §3.6] |
| S-014 **(rev)** | Bun/GPUIX engineering rules baked into the component library: lowercase key names, one template string per text node, explicit svg colour, `height:0` stretches (never use it to hide), no layer reconfigure / no input region / no window resize (respawn instead), `keyboardFocusDim:false`, single-line inputs handle up/down in `onKeyDown` and Enter in `onSubmit`, `render()` installs a runtime-error overlay so daemons wrap in try/catch and `process.exit(1)` (systemd restarts), `startFrameLoop({frameMs: 250})` for daemons, tick loop for timers, no zoom API (zoom = theme scale factor), memory budget ≤ 250 MiB RSS per process (measured 150–200 MiB; INFERRED target). | — | — | — | P0 | lint bun test; smoke memory sample under budget per surface | [w1-03][w1-15] |
| S-015 **(new)** | Output pinning: GPUIX has no output selector; a layer surface opens on the focused output. Daemons that must sit on eDP-1 (rail, switcher) run the `swaymsg focus output eDP-1` → spawn → restore-focus dance (verify with `get_outputs`), and toasts/OSD open on the focused output (wanted). Seam for the ~20-line GPUIX patch adding `output` to `layerShell`. | auto | Sway IPC | none | P0 | smoke at two headless outputs: rail maps on the named output; focus returns to the previous output | [w1-15][w1-17] |
| S-016 **(new)** | `gpuix-shell listen [--json] [--filter notifications\|rail\|herdr\|theme]` streams shell events (notification posted/closed/action, slot status change, theme change, surface opened/closed) to stdout for scripts; back-pressure safe, one line per event. | CLI | socket broadcast | none | P1 | bun test: subscribe, two events, EOF on daemon exit | [w1-18][w1-30 §3.2] |
| S-017 **(new)** | `gpuix-shell validate` (config + theme fragments against the schemas, binds in §22 resolve, fonts present, `herdr`/`fd`/`wl-paste` on PATH) and `gpuix-shell status --json` (which surfaces run, socket version, theme, output map). `validate` is the morning doctor; exit 0/1. | CLI | S-009, PATH | `vicinae ping`, dependency doctor | P0 | bun test: a broken fragment fails validate with the key path | [w1-21][w1-29 AM #178 #266] |
| S-018 **(new)** | Keyed status: `gpuix-shell status set <key> <text> [--ttl s]` / `status clear <key>` (cmux pattern) so scripts (`pomodoro`, `recording-toggle`, `call-record`, `screen-ocr`) write rail state without clobbering each other; replaces ad-hoc state files; shown as rail cluster items and in `status --json`. | CLI | socket | state files under `$XDG_RUNTIME_DIR` | P1 | bun test: two keys, ttl expiry | [w1-28 §3.13 P1][w1-29 §3.3] |
| S-019 **(new)** | Command runner: one module spawns everything (`gio launch`, scripts, `swaymsg`), `sh -c` only for `>` mode, nonzero exit = error, 30 s timeout, SIGTERM → SIGKILL 5 s grace, 10 MB output cap, never inherits the surface's env (`GPUIX_*`, socket paths stripped); error vocabulary NOT_FOUND / NOT_SUPPORTED / PERMISSION_DENIED / INVALID_PARAMS / TIMEOUT / BUSY / CANCELLED / INTERNAL on socket replies. | — | — | — | P0 | bun test: timeout, env scrub, exit mapping | [w1-29 §5 S06:376–378][w1-36] |

---

## 1. Rail (left bar)

Geometry: layer `top`, anchor left+top+bottom, exclusive zone 220 expanded (default) / 56 collapsed
(a separate launch `gpuix-shell rail --collapsed`, not a live resize), rows 220/196 × 30, inset 12,
hairline 2, gap 8, radius 0 outer (rows 6), keyboard `on-demand`, one surface per output that carries
it (eDP-1 top with ws 1–9; eDP-2 shows the reduced rail or none, config). No tooltips. The March
"workspace switcher as a separate left bar" (AM #27) and the kmux CCD sidebar merge into this one
surface. [BRIEF §3.3][w1-01][w1-11][w1-25][w1-28 §3.13]

| ID | Behaviour | Trigger | Data source | Replaces | P | Acceptance | Refs |
|---|---|---|---|---|---|---|---|
| S-020 | Nine workspace slot rows 1–9 (eDP-1 only), 1:1:1 with Sway workspace N = herdr slot N = kitty projector window; each row: slot number, herdr workspace name (or the Sway name), status glyph/word, focused highlight (selection.bg hairline, 2 px left accent). Workspace 10 (Chrome) is a separate pinned row at the bottom of the slot zone. | auto | S-004 + S-005 | waybar workspaces (deleted) | P0 | smoke: nine rows in `ui-tree`; switching with `swaymsg workspace 3` moves the highlight within one event; bun test on mark→slot mapping | [BRIEF §1][w1-07][w1-16][w1-25] |
| S-021 | Click a slot row → `swaymsg workspace number N` (verify after switch); middle/right do nothing (no herdr focus, no close). | click | Sway IPC | — | P0 | smoke: simulateClick row 3 → focused workspace 3 | [w1-10][w1-16] |
| S-022 **(rev)** | Run-state marks: blocked ◉ orange "Needs input" (the only attention state), working ◐ blue (static dot, no pulse: near-zero animation), done ● green "New activity" until the slot is visited, idle ✓ no mark, unknown ○ (also "herdr unreachable"); colours from `--dot-*` in the theme. Visiting a slot clears its "done" mark (the rail remembers last-visited per slot). | auto | S-005 | herdr-bar / herdr-web-ui rail | P0 | bun test: transition table; smoke: fake snapshot blocked → orange pixel at the row glyph | [w1-05][w1-11][w1-25][w1-29 §4 10] |
| S-023 | Empty slot rows render dim with a "+" affordance; click runs the same command as Mod+t (`sway-workspace new`) scoped to that number (INFERRED: `sway-workspace new N` if the script accepts a number, else no-op). | click | S-005 | — | P1 | smoke: empty row shows "+" | [w1-07][w1-17] |
| S-024 | Status cluster (bottom zone), in this order: privacy dots, recording dot, tailscale, network, bluetooth, audio, battery, notifications bell, pomodoro, keyed statuses (S-018), clock. Each item is a `registry.ts` entry = React component + data source ("turn any functionality into a bar addition"); order fixed by config, per-output overrides allowed. Omarchy's built-in widget list is the completeness check. | auto | S-009 | waybar modules | P0 | bun test: registry resolves config; smoke: cluster present | [w1-13][w1-19][w1-30 AM #1–#8 §3.4] |
| S-025 | Clock: time (and date in expanded mode), format from config, mono figures, updates on the minute. | auto | system clock | waybar clock | P0 | smoke: text matches `HH:MM` | [w1-30 AM #28] |
| S-026 | Battery glyph + percent (expanded) via UPower `DisplayDevice`; charging/discharging/critical states; critical (<10 %, discharging) also raises a critical notification once. | auto | UPower D-Bus | waybar battery | P0 | bun test on UPower property fixtures | [w1-23][w1-26] |
| S-027 | Network glyph: wifi SSID + strength bars, or wired, or off; click opens the wifi menu (S-126). | auto/click | NetworkManager D-Bus | waybar network | P0 | bun test on NM fixtures; click opens controls view `wifi` | [w1-23][w1-26] |
| S-028 | Bluetooth glyph: off / on / connected (count); click opens the bluetooth menu (S-127). | auto/click | BlueZ D-Bus (ObjectManager) | none | P1 | bun test on BlueZ fixtures | [w1-23][w1-30 AM #32] |
| S-029 | Audio glyph: default sink volume + mute, mic mute state; wheel on the glyph → `volume up/down`; click opens the audio route menu (S-128). | auto/click | `wpctl` + `pw-dump` subscribe (poll 1 s or `pw-mon`) | waybar pulseaudio | P0 | bun test parses `wpctl get-volume`; smoke | [w1-17][w1-30 AM #33] |
| S-030 | Notifications bell: unread count badge and DND state; click toggles the notification centre (S-107). | auto/click | notifications daemon over the socket | none | P0 | smoke: send 2 notifications → badge "2" | [w1-30 AM #35] |
| S-031 | Tailscale glyph ("CRUCIAL", AM #41): connected/disconnected, exit-node state; expanded mode shows peer count; click opens the tailscale peers menu (S-135). Reuses `vpn-status` JSON. | auto/click | `tailscale status --json` every 15 s + `vpn-status` | none | P1 | bun test on a recorded status JSON | [w1-26][w1-30 AM #41 G1] |
| S-032 | Privacy dots: mic (red-ish) / camera / screen-share in use, from PipeWire node graph (`pw-dump` stream nodes with `media.class` Audio/Source or Video/Source, excluding `cava\|monitor\|system`; screencast portal nodes); camera fallback `lsof /dev/video*` 2 s poll. | auto | `pw-dump` | none | P1 | bun test on a pw-dump fixture with a capture stream | [w1-27 §5.1][w1-30 AM #39] |
| S-033 **(rev)** | Recording dot: lit while `recording-toggle` / `call-record` run (they set a keyed status, S-018); click stops nothing (read-only). | auto | S-018 | none | P1 | bun test: key present → dot | [w1-17][w1-30 AM #60] |
| S-034 **(rev)** | Pomodoro item: remaining time while a `pomodoro` session runs (keyed status with ttl, or `pomodoro status`); click opens the pomodoro launcher view (S-090). Tom: "the first feature i release AFTER base webshell". | auto/click | S-018 / `pomodoro status` | none | P1 | bun test on `pomodoro status` output | [w1-17][w1-30 AM #250] |
| S-035 | Media item (expanded only): now-playing title, play/pause on click; from MPRIS (any player incl. `org.mpris.MediaPlayer2.gpuix_music`). | auto/click | MPRIS D-Bus | none | P1 | smoke with a fake MPRIS player | [w1-23][w1-30 AM #34] |
| S-036 | Caps/touchpad state: the Duo caps LED is handled by `touchpad-toggle`; the rail shows a small "touchpad off" mark while off (keyed status). | auto | S-018 | none | P2 | bun test | [w1-17][w1-30 AM #49] |
| S-037 | `gpuix-shell rail toggle [--output eDP-1]` hides/shows one bar; `rail collapse\|expand` relaunches at 56/220; `rail reload`. One verb touches one bar (AM #20). | CLI/bind | socket | waybar IPC toggle | P0 | smoke: toggle → exclusive zone 0 then back | [w1-11][w1-30 AM #9 #12 #20] |
| S-038 | Auto-hide when the focused container on that output is fullscreen (Sway `window` event, `fullscreen_mode`); return on unfullscreen (respawn, since no hide API). | auto | S-004 | none | P1 | smoke: `fullscreen toggle` on a window → rail unmapped | [w1-15][w1-30 AM #10] |
| S-039 | Custom command button: config item kind `command` with click/right/middle/scroll-up/scroll-down → shell verb or script. | click | S-009 | waybar custom | P1 | bun test: config → handlers | [w1-30 AM #58] |
| S-040 | Launcher button at the top of the rail (Anthropic mark) → `gpuix-shell launcher toggle`. | click | — | none | P1 | smoke | [w1-30 AM #38] |
| S-041 | Per-output configuration: eDP-2 (Chrome, ws 10) shows a reduced rail (clock + status, no slots) or no rail (INFERRED default: reduced); keyed by output name; honour output scale (Duo logical 1440×900 each, scale 2). | auto | S-009 + Sway outputs | — | P1 | smoke at two headless outputs | [BRIEF §1][w1-17][w1-29 §6 G4][w1-30 AM #5 #6 #22] |
| S-042 | Focused-window line (expanded, under the slot zone): app_id/title of the focused container, truncated; herdr workspace name preferred. | auto | S-004 | waybar window | P2 | smoke | [w1-30 AM #36] |
| S-043 | Zoom: rail is exempt from the Ctrl+/− UI scale (0.8–1.6) that overlays honour via the theme scale factor (GPUIX has no zoom API). | bind | S-009 | none | P2 | bun test | [w1-05][w1-11][w1-15] |
| S-044 | System monitor mini (cpu/mem/disk, claude-capacity, seats) as optional cluster items; see §14. | auto | `claude-capacity`, `seats`, /proc | none | P2 | bun test | [w1-17][w1-30 AM #40] |
| S-045 **(new)** | Agent marks per slot: Claude / Codex / Cursor / fallback-initial marks from herdr-web-ui `AgentMark.tsx` (verbatim path data), Mono mode default on noir (tile hidden, glyph currentColor; "a list where most rows run Claude is not a stripe of orange tiles"), brand colour on the Claude themes (INFERRED). GPUIX SVG path support is unverified: rasterise to PNG at build if vector paths are unavailable. | auto | S-005 agent field | herdr-web-ui rail | P1 | bun test: agent → mark id; smoke: mark node per occupied slot | [w1-25 §5.3 §6.8] |
| S-046 **(new)** | Scroll on the slot zone cycles workspaces (Mod+wheel already does this in Sway); hot corners stay out (Sway has none). | click | Sway IPC | none | P2 | smoke | [w1-29 AM #17 #26] |

---

## 2. Launcher (Mod+d, the Vicinae replacement)

Geometry: layer `overlay`, 700×580, anchor top, margin top 12 % of output height (108 px on the Duo),
keyboard `exclusive`, flat, radius 0 outer (Tom: Vicinae rounding 0, no shadow, hairline 1), header
60, footer 40, row 44, UI font 16 px (Tom's 12 pt), row titles 14 px, three-level text, selection.bg
"the vicinae blue". Spawned per show (S-001). Raycast is the north star (AM general note); Vicinae
parity (incl. Chrome tabs) is the acceptance bar. [BRIEF §3.3 §5][w1-09][w1-11][w1-35 App. B][w1-36 T14]

### 2.1 Root, grammar, navigation

| ID | Behaviour | Trigger | Data source | Replaces | P | Acceptance | Refs |
|---|---|---|---|---|---|---|---|
| S-050 **(rev)** | `gpuix-shell launcher toggle [-q text] [--view <provider>]` on Mod+d and Mod+space; `launcher open` / `close`; Escape = navigate back then close (`escape_key_behavior`), Backspace on empty pops (`pop_on_backspace`), `pop_to_root_on_close` true (trivially, since the process exits), closes on focus loss (`close_on_focus_loss`), `wrap_navigation` off. Toggle while open = SIGTERM. | bind/CLI | — | `vicinae toggle\|open\|close` | P0 | smoke: toggle maps a 700×580 overlay with exclusive keyboard in < 0.5 s; second toggle unmaps | [w1-15][w1-18][w1-36 §3.6 §3.8] |
| S-051 | Root search: one fuzzy query over favourites, apps, commands, scripts, shortcuts, extension commands; sections "Favorites", "Suggestions" (frecency), "Commands", "Apps"; ranking `fuzzy*0.7 + frecency*0.3` with title > subtitle > keywords; `fallbacks` (files:search, calculator) when nothing matches; hidden items list; no vendor/self-promotion items; no favicons (`favicon_service none`). | launcher | provider registry | vicinae root | P0 | bun test: ranking, hidden ids absent; smoke: typing "chrome" shows Google Chrome first | [w1-18][w1-27 §5.1][w1-35][w1-36 §3.8] |
| S-052 | Favourites with Tom's order: `applications:herdr-picker` (→ S-063), `clipboard:history`, `browser-extension:browse-tabs`, `media:now-playing`, `core:search-tray`; pins via `action.pin` (Ctrl+Shift+P); frecency store in `bun:sqlite` (caelestia style, Vicinae decay formula). | launcher | state sqlite | vicinae favorites | P0 | bun test: frecency decay; pin persists | [w1-18][w1-30 AM #90 #91] |
| S-053 | Prefix modes: `=` calculator, `>` shell command, `:` emoji, `/` files, `@` herdr workspaces, `♪`/`m:` music, `?` cheatsheet, `;` shell services (INFERRED set); typing the prefix switches the placeholder and provider. | launcher | registry | vicinae/caelestia prefixes | P1 | bun test: prefix → provider | [w1-30 AM #100] |
| S-054 | Action panel (Ctrl+B; Ctrl+Tab alias INFERRED) per item: Enter primary, Shift+Enter secondary, named shortcuts `action.copy` Ctrl+Shift+C, `action.copy-name`, `action.copy-path`, `action.open` Ctrl+O, `action.pin`, `action.refresh` Ctrl+R, `action.remove` Ctrl+X, `action.dangerous-remove` Ctrl+Shift+X, `action.edit` Ctrl+E, `action.new` Ctrl+N, `action.save` Ctrl+S, `action.move-up/down`; `open-search-filter` Ctrl+P; keybinding profile `default\|vim\|emacs`. | launcher | config | vicinae action panel | P0 | bun test: keymap table; smoke: Ctrl+B opens the panel over the footer | [w1-35][w1-36 §3.8] |
| S-055 | Footer: navigation title bottom-left, primary action hint + "Actions ⌃B" bottom-right, optional clock; header: search field, loading bar, search-bar dropdown accessory, back chevron. | launcher | — | vicinae chrome | P0 | smoke pixels | [w1-35][w1-36 §4.1] |
| S-056 | Navigation stack: push/pop views (List, Grid, Detail, Form), per-view search text with event counting to drop stale echoes, `popToRoot`. | launcher | — | vicinae | P0 | bun test on the view-stack reducer | [w1-36 §3.1 §3.2] |
| S-057 | Detail pane (`isShowingDetail`) with markdown + metadata column; Markdown renderer limited to headings, paragraphs, lists, code, links, images (no HTML). | launcher | — | vicinae | P1 | bun test markdown → tree | [w1-36 §3.1] |
| S-058 | Toast-in-launcher (`showToast` success/failure/animated with up to 2 actions) and HUD (`showHUD` → OSD S-119). | launcher | — | vicinae | P1 | bun test | [w1-36 §3.2] |
| S-059 | Confirm dialog (`confirmAlert`, destructive style red) used by every ACTION-irreversible launcher command (power, trash, forget network, close workspace). | launcher | — | vicinae | P0 | smoke: power-off item → dialog before anything runs | [w1-10][w1-36 §3.2] |

### 2.2 Providers (builtins)

| ID | Behaviour | Trigger | Data source | Replaces | P | Acceptance | Refs |
|---|---|---|---|---|---|---|---|
| S-060 | Apps: XDG `.desktop` entries (incl. the 11 PWA entries and the 7 dotfiles entries: Herdr workspaces, New/Restore/Rename workspace, Dismiss/Restore notification, Network settings), icons via icon theme + Anthropicons, `NoDisplay`/hidden list honoured, launch with `gio launch` through S-019 (never inherits the launcher env), actions: open, open in workspace N, copy name, show desktop file. Watches the dirs. | launcher | `$XDG_DATA_DIRS/applications` | vicinae applications | P0 | bun test: parser on fixtures incl. `Actions=`; smoke: Enter launches a fake app under Sway | [w1-13][w1-18][w1-36 §3.13] |
| S-061 | Commands: first-party command list (≈66 Vicinae ids kept where Linux-relevant: `clipboard:history`, `calculator:*`, `files:search`, `media:*`, `power:*`, `wm:*`, `emoji:*`, `snippets:*`, `manage-shortcuts:*`, `theme:set`, `font:browse`, `screenshots:browse`, `browser-extension:*`, `core:search-tray`, `core:settings` reduced). `gpuix-shell cmd ls [--json]` and `cmd launch <provider:entry> [args] [--cwd] [-q]` (positional args map to declared arguments in order). | launcher/CLI | registry | vicinae commands | P0 | bun test: every id in the table resolves; `cmd launch clipboard:history` opens the clipboard view | [w1-35 App. A][w1-36 §3.6] |
| S-062 | Windows: `wm:switch-windows` lists Sway containers (app_id, title, workspace, output, herdr slot), Enter focuses by con_id, actions close / move to workspace; no transient ids. | launcher | S-004 | vicinae wm | P0 | smoke: two windows listed; Enter focuses | [w1-36 §3.2 WindowManagement] |
| S-063 | Workspaces / herdr picker: `@` view lists herdr workspaces with status glyph, projector slot, seat, running time (herdr-bar format), MRU + fuzzy ranking (status rank blocked < done < working < idle; the current row never first); Enter → `swaymsg workspace N`; actions: rename (`sway-workspace rename`), restore (`sway-workspace restore`), close (`sway-workspace close`, confirm), open sidebar (`herdr-chord sidebar`). Replaces the `herdr-picker` dmenu flow and keeps the `applications:herdr-picker` id. | launcher/bind (Mod+Ctrl+space) | S-005 | `herdr-picker` + vicinae dmenu | P0 | bun test: ranking constants from herdr-bar; smoke with fake herdr | [w1-16][w1-23][w1-25 §5.1][w1-36 §3.13] |
| S-064 | Clipboard history (`clipboard:history`, Mod+v): see §8 for the store; view shows text rows with preview, image rows with thumbnails, kind filter dropdown (text/link/image/file/colour), pins, FTS; Enter copies (and pastes when an input path exists), actions: paste, copy, pin, delete, clear all (confirm), open link, save image. "Opening it never pastes." | launcher/bind | S-145 store | vicinae clipboard | P0 | smoke: copy "hello" via `wl-copy` under the harness → row appears; image fixture → thumbnail node | [w1-18][w1-30 AM #86] |
| S-065 | Files: `/` view and `files:search` fallback over `fd` (no indexer daemon; AM #85) in configured roots (~/Downloads, ~/Documents, ~, hidden off, `search_files_in_root` off), category filter (image/video/audio/document/archive/dir), actions: open (`gio launch`/`xdg-open`), reveal in explorer (S-155), copy path, copy file, trash (`gio trash`, never `rm`), open in kitty here, send to agent (S-194). | launcher | `fd` | vicinae files | P0 | bun test: `fd` argv builder; smoke on a temp tree | [w1-18][w1-30 AM #85][w1-36 Action.Trash] |
| S-066 | Calculator: `=` prefix and root fallback; pure TS (units, percentages, hex/bin, date arithmetic basic), result row with "Copy result"; history of the last 20. | launcher | own | vicinae calculator (numen/soulver) | P0 | bun test: 30 expressions | [w1-18][w1-35] |
| S-067 **(rev)** | Browser tabs: `browser-extension:browse-tabs` lists Chrome tabs (title, url, window, audible, pinned), fuzzy url 1.0 / title 0.6, Enter focuses the tab (and the Chrome window / workspace 10), actions close, copy url, mute (if supported), "Create shortcut from active tab". Reuses the published Vicinae Chrome extension id `kcmipingpfbohfjckomimmahknoddnke` (already installed on the Zenbook) with our own native host under the name `com.vicinae.vicinae` installed declaratively by Nix. | launcher | native-messaging host → socket | vicinae browser bridge | P1 | bun test: native host framing + tabs-changed → model; hand check: tabs list under the real extension | [w1-18][w1-36 §3.11 T14] |
| S-068 | Emoji & symbols: `:` prefix, Unicode 15 table with names/keywords, skin tones, recent, Enter copies (+paste), grid view. | launcher | bundled table (generated at build) | vicinae emoji / old fzf menu | P1 | bun test: search "shrug" | [w1-18][w1-30 AM #87] |
| S-069 | Theme: `theme:set` lists noir / claude-dark / claude-light and calls `~/.local/bin/theme <name>` (manual only, AM #184); accent sub-list calls `theme-prompt accent` logic (F2/Shift+F2 keep working). | launcher | `theme` script | `theme-prompt` fzf | P0 | smoke: select → symlink changes | [w1-17][w1-36 §3.13] |
| S-070 | Power: `power:*` items (monitors off, lock placeholder, logout, reboot, power off, suspend if enabled) each confirm then dispatch to the same backend as §7. | launcher | S-140 | vicinae power | P0 | smoke: item → confirm dialog | [w1-10][w1-35] |
| S-071 | Scripts: Vicinae script-command header grammar (`@vicinae.*` / `@raycast.*`, schemaVersion, title, mode fullOutput/compact/silent/terminal/inline, argument1..3, needsConfirmation, exec, terminal) scanned from `~/.local/share/gpuix-shell/scripts` and dotfiles-declared dirs; `refreshTime` only refreshes while visible (no background timers); `gpuix-shell script template` prints a header. | launcher | script files | vicinae scripts | P1 | bun test: parser fixtures; fullOutput streams into a Detail view | [w1-36 §3.7] |
| S-072 | Wifi: `network:*` view = the same model as S-126 inside the launcher (list networks, connect with password form, disconnect, forget, toggle radio). | launcher | NM D-Bus | `fzf-nmcli` | P0 | shared tests with S-126 | [w1-17][w1-18] |
| S-073 | Bluetooth: `bluetooth:*` view = S-127 inside the launcher. | launcher | BlueZ | none | P1 | shared with S-127 | [w1-10] |
| S-074 | Audio route: `audio:route` view = S-128 inside the launcher; Enter calls `audio-route <sink>` (keeps the near-silent volume lift). | launcher | `wpctl` + `audio-route` | F9 fzf prompt | P0 | smoke: rows from a `wpctl status` fixture | [w1-17][w1-18] |
| S-075 | Snippets & shortcuts: `snippets:create/manage` (text with `{clipboard}`/`{date}` placeholders, paste on Enter) and `manage-shortcuts:*` (quicklinks with `{query}`), stored as JSON in state. | launcher | state JSON | vicinae snippets/shortcuts | P1 | bun test placeholders | [w1-35] |
| S-076 | Shell command `>`: run with live output in a Detail view, Enter re-run, "Run in kitty" action; history. | launcher | S-019 | noctalia | P1 | bun test | [w1-30 AM #99] |
| S-077 | Media: `media:now-playing` detail (art, title, progress bar with seek), `media:play-pause/next/prev/volume-N/toggle-mute` call `media`/`volume` scripts. | launcher | MPRIS + scripts | vicinae media | P1 | bun test with fake MPRIS | [w1-35][w1-30 AM #115–#117] |
| S-078 | Notifications: `notifications:history` (opens the centre), `notifications:dismiss-all`, `notifications:dnd-toggle`, `notifications:restore-last`. | launcher | notifications socket | the two dotfiles desktop entries + makoctl | P0 | smoke | [w1-18][w1-36 §3.13] |
| S-079 | Tray: `core:search-tray` lists SNI items with their dbusmenu entries (needs §12; empty state until then). | launcher | SNI watcher | vicinae tray | P2 | bun test | [w1-35] |
| S-080 | Screenshots: `screenshots:browse` greps `~/Pictures/Screenshots` (grid with thumbnails), `screenshots:paste-last`. | launcher | fs | vicinae screenshots | P1 | bun test | [w1-35] |
| S-081 | Font browse `font:browse` (fontconfig list, preview row) and `internal:markdown-showcase` / component gallery (design gallery, honours the "lego / storybook" wish and doubles as the OpenUI-coverage check). | launcher | fontconfig | vicinae | P2 | smoke | [w1-30 §2.7 §4.1 14][w1-35] |
| S-082 | Settings provider `core:settings`: searchable list of config keys with current values and the file they come from (read-only; no GUI editing: dotfiles own config; AM #174/#176 MUST vs #200 "no hierarchy", INFERRED resolution). | launcher | S-009 | vicinae settings window | P2 | bun test | [w1-29 AM #174 #176 G3] |
| S-083 **(rev)** | Units & containers view: running user/system units, quadlets and podman containers (`systemctl --user list-units`, `podman ps --format json`), restart/stop actions (confirm); Tom's "see running systemd services and quadlets" idea. | launcher | systemctl, podman | none | P2 | bun test | [w1-30 AM #251 #263] |
| S-084 | Updates/health: `system:health` shows failure markers, tripwire state, last `nixos-rebuild` generation, fwupd pending; no auto-check timers. | launcher | `/var/lib/failure-markers`, `nixos-rebuild list-generations` | none | P2 | bun test | [AGENTS.md D41–D49][w1-30 AM #47 #248] |
| S-085 | Music (Navidrome demo, `♪`): search albums/artists/tracks/playlists, play/queue/shuffle, now-playing with art, seek, volume (mpv daemon over fd IPC, MPRIS `org.mpris.MediaPlayer2.gpuix_music`, Subsonic tokens never on argv/logs); `gpuix-shell music serve` daemon; Mod+m proposed. Credentials are strix-only tonight, so on the Zenbook the view shows the "no credentials" empty state. | launcher/bind | Navidrome Subsonic API + mpv | none | P1 | music test suite in `docs/gpuix-shell/music`; smoke of the view with a fake server | [BRIEF §5][ASSUMPTIONS music:*] |
| S-086 **(rev)** | `gpuix-shell select` (alias `dmenu`): `[-n title] [-s section] [-f data\|index] [-p placeholder] [-q query] [-W width] [-H height] [--no-section] [--free-text] [--password] < stdin`, one row per line, rows starting with `/` show the basename, "Pass search text" on empty result, prints the choice, exits 1 on cancel; concurrent callers routed per connection. Any script that used `$prompt`/fzf can move to it. | CLI | stdin | vicinae dmenu, fzf prompts | P0 | bun test: index/data formats, exit 1 on cancel | [w1-18][w1-36 §3.6] |
| S-087 | Deeplinks `gpuix-shell://toggle\|open\|close\|launch/<provider>[/<entry>]?arguments=&fallbackText=&toggle=` and `vicinae://` accepted as an alias for muscle memory; registered as an x-scheme-handler. | CLI | — | vicinae deeplinks | P1 | bun test parser | [w1-36 §3.9] |
| S-088 | Contextual root: the launcher's first section reflects context — focused window's app actions, current herdr slot actions (rename/restore/close, open sidebar), the active notification's actions — so Ctrl+K predictability holds. | launcher | S-004 + S-005 + notifications | none | P1 | bun test: context section built from fixtures | [w1-04][w1-36 T2 T3] |
| S-089 | OCR result and "ask" entries: `ask:prompt` (S-200) and the last `screen-ocr` result (`ocr:last`, copy) appear as root commands. | launcher | S-151, S-200 | none | P2 | bun test | [w1-24] |
| S-090 | Pomodoro: `pomodoro:start/stop/status` wrapping the `pomodoro` script (Shift+F10 keeps the prompt until this lands). | launcher | `pomodoro` | fzf prompt | P1 | bun test argv | [w1-17] |
| S-091 | Call record menu `call-record:*` wrapping `call-record-menu` (Shift+F9). | launcher | script | fzf prompt | P1 | bun test | [w1-17] |
| S-092 | Sleep monitors `display:sleep` wrapping `sleep-monitors` (F10) and `display:off` (`monitors-off`). | launcher | script | fzf prompt | P0 | bun test | [w1-17] |
| S-093 | Speak clipboard `speech:speak-clipboard` (Mod+Ctrl+r script) and `/speak`-style publish to `~/Speech/intake`. | launcher | script | none | P2 | bun test | [w1-17][AGENTS.md speech] |
| S-094 **(new)** | Shell services / doctor view (`;` prefix, `shell:services`): the shell's own surfaces and units with state, last error line, restart action; `shell:doctor` runs S-017 `validate` and lists failures with the fix hint. | launcher | S-017, systemctl | none | P1 | bun test on `status --json` fixture | [w1-21][w1-29 AM #266] |

### 2.3 Extension host (Vicinae/Raycast-style)

| ID | Behaviour | Trigger | Data source | Replaces | P | Acceptance | Refs |
|---|---|---|---|---|---|---|---|
| S-095 | `LauncherProvider` contract (`pkgs/gpuix-shell/src/launcher/provider.ts`: prime / search(query, signal) / actions / detail; Section/Row/Action/DetailPane; AsyncIterable snapshots) is the spine every builtin, every controls view and the music view implement; one registry for rail items and launcher commands. | — | — | DMS getItems/executeItem | P0 | bun test: a trivial provider passes the conformance test | [ASSUMPTIONS music:][w1-29 §4 6][w1-30 AM #88] |
| S-096 | Extension runtime: one Bun `Worker` per launched command, `@gpuix-shell/api` with the Vicinae component vocabulary (List, List.Item, Section, Accessory, Detail, Metadata, Grid, Form fields, ActionPanel, Action.*), a react-reconciler host serializing a view tree (handlers → ids, 60/s debounce), `useNavigation`, `LocalStorage`, `Cache` (pure TS, reused), `getPreferenceValues`, `environment` (appearance from the theme pointer), `LaunchProps`, `launchCommand`, `Clipboard` (via `wl-copy`), `showToast`, `showHUD`, `confirmAlert`, `open`/`getApplications`/`runInTerminal` (kitty)/`showInFileBrowser` (S-155)/`trash` (gio), `WindowManagement` on Sway IPC, `BrowserExtension` (S-067); ids `provider:entrypoint`; `@raycast/api` aliased with throwing stubs for unsupported symbols; `Wallpaper` and `AI` report `canAccess=false` (AI may later route to the local model). Manifest = Vicinae `package.json` schema; `menu-bar` mode dropped; `interval` commands gated off (no scheduled work). | launcher | `~/.local/share/gpuix-shell/extensions/*` (+ optionally Vicinae's dir) | vicinae extension-manager | P1 (core: List/Detail/ActionPanel/Form/Storage), P2 (Grid, OAuth, FilePicker, DatePicker, dev CLI) | the boilerplate's 23 sample commands as a conformance suite: list, list-detail, form, nested-form, paginated, controlled-list, window-switcher render and act; `mkVicinaeExtension` output loads unchanged | [w1-36 §3.1–3.5 §3.12 §4] |
| S-097 | Store browse is out at runtime; extensions are installed by Nix (`programs.gpuixShell.extensions`). | — | — | vicinae store | P2 | HM option exists | [w1-36 §3.10] |

---

## 3. Notifications (daemon, toasts, centre)

Process `gpuix-shell notifications`: owns `org.freedesktop.Notifications` (spec 1.2 + the mako
extras), renders toasts in one overlay window and hosts the OSD (§4) and the notification centre
(S-107) as views of the same process. Toasts: 390 wide, fixed 140 px cards, max 4, **newest on top**,
anchor **top-centre** (Tom 2024-05-30 and 2026-10-11: "top and center not top right"; BRIEF says
top-right: INFERRED top-centre wins as the later explicit words, a config key `toasts.anchor` keeps
both), on the focused output. "Non-negociable" (AM #65). [w1-11][w1-18][w1-36 T5]

| ID | Behaviour | Trigger | Data source | Replaces | P | Acceptance | Refs |
|---|---|---|---|---|---|---|---|
| S-100 | D-Bus server: `GetServerInformation`, `GetCapabilities` (`body`, `body-markup`, `actions`, `action-icons`, `icon-static`, `persistence`), `Notify` with replaces_id, app_icon, hints (`urgency`, `int:value` progress, `image-data`/`image-path`, `category`, `desktop-entry`, `transient`, `resident`, `x-canonical-private-synchronous`), `CloseNotification`, signals `NotificationClosed(reason 1 expired/2 dismissed/3 closed/4 undefined)` and `ActionInvoked`; `notify-send` round-trips. Never co-running with mako (HM assertion). | D-Bus | session bus | mako | P0 | bun test with `dbus-run-session` + `notify-send -r 7 -h int:value:40`; smoke: toast pixels | [w1-18][w1-26] |
| S-101 **(rev)** | Toast card: app name + icon, summary, body (markup subset b/i/u/a), image, progress bar for `int:value`, up to 2 action buttons, hairline colour per urgency (low dim / normal / critical orange), timeouts: default 5000 ms for low and normal (mako's value), critical 0 (stays) **unless an explicit `-t` is passed, which wins**; respawn-not-resize when the stack height changes; hover pauses the countdown. | auto | S-100 | mako | P0 | smoke: 5 toasts → 4 visible; critical stays after 10 s; `-t 2000` critical gone after 3 s | [w1-03][w1-11][w1-18] |
| S-102 **(rev)** | Toast interaction: click body → default action (or focus the app window via Sway if `desktop-entry`/app_id matches); click × → dismiss; Mod+o `notifications dismiss-all` (keeps history); `notifications dismiss-last`; `notifications restore-last` (restores from the last 5 dismissed). | click/bind | — | makoctl dismiss / restore | P0 | smoke: dismiss-all empties the stack; restore-last brings one back | [w1-18] |
| S-103 | Grouping: same app → collapsible group after 3; same summary within 1 s coalesces (count badge). | auto | — | mako group-by | P1 | bun test | [w1-30 AM #68] |
| S-104 | Flood protection: hard cap 20 notifications/s per sender, excess coalesced into one "N more from X" card; duplicates within 1 s merge; critical bypasses the cap. | auto | — | none | P0 | bun test: 100 Notify calls in 100 ms → ≤20 cards | [w1-27 §5.1][w1-30 AM #82] |
| S-105 | DND: `notifications dnd on\|off\|toggle`, state in the bell, critical still shows (config), queued normals go to history only; OSD unaffected; never scheduled. | CLI/bind/click | state | mako modes | P0 | bun test | [w1-18][w1-30 AM #71] |
| S-106 | History: JSONL in `$XDG_STATE_HOME/gpuix-shell/notifications.jsonl` (cap 500, images cached under state, 7-day retention), restored on restart (cross-generation). | auto | — | mako history (lost on restart) | P0 | bun test: write/read/evict | [w1-13][w1-30 AM #70 #80 #81] |
| S-107 | Notification centre: 500×650 overlay, tabs Current / History, grouped by app, keyboard navigation (j/k, Enter action, x dismiss, hints overlay with letter keys like DMS), clear all (confirm), DND toggle in the header; opened from the bell or `notifications toggle` (spawned per show). | click/CLI/bind (Mod+Shift+o INFERRED) | S-106 | none | P1 | smoke: toggle maps 500×650; hints letters render | [w1-11][w1-30 AM #67 #77] |
| S-108 | Rules engine: config list of `{match: {app, summary regex, body regex}, action: drop\|dnd-exempt\|urgency\|timeout\|silent\|route-to-osd}`, first match wins; the `osd` app rule routes to §4. | auto | S-009 | mako criteria | P1 | bun test: rules fixtures | [w1-30 AM #72] |
| S-109 | herdr attention path: herdr's own toasts stay off; a `blocked` transition from S-005 raises one normal notification "Slot N needs input" with actions "Go" (→ `swaymsg workspace N`) and "Dismiss", app `herdr`, replace-id per slot; `done` raises nothing (rail mark only). OSC 99 from kitty arrives as ordinary notifications. | auto | S-005 | the unmerged herdr-attention branch's mako actions | P0 | bun test: blocked → Notify with 2 actions; invoking Go switches workspace | [w1-05][w1-07][w1-16] |
| S-110 | Phone notifications (KDE Connect / Valent, "extremely desirable") are accepted as ordinary fd.o clients, grouped under the device app name; the package is not in dotfiles tonight. | D-Bus | — | none | P2 | hand check later | [w1-30 AM #252 G4] |
| S-111 | Notification sounds: off by default ("i barely expect nofitication sounds"); config per urgency; plays via `pw-play`. | auto | — | none | P2 | bun test argv | [w1-30 AM #75] |
| S-112 | Privacy mode: `notifications privacy on` hides bodies on toasts (summary only). | CLI | — | none | P2 | bun test | [w1-30 AM #79] |
| S-113 | Focused-app suppression: if the notifying app's window is focused and the hint `transient` is set, skip the toast and write history only (INFERRED). | auto | S-004 | none | P2 | bun test | [w1-26] |
| S-114 **(new)** | Toast hints overlay (AM #77 MUST): `notifications hints` (Mod+o held, or Mod+Shift+o then letter, INFERRED chord) overlays a letter on each visible toast; the letter invokes the default action, Shift+letter dismisses; Escape clears. | bind/CLI | — | none | P1 | smoke: letters render; key invokes action | [w1-27 §2.1][w1-30 G7] |

---

## 4. OSD

The OSD is a view of the notifications process: bottom-centre overlay on the focused output, margin
bottom 96, one card (icon, label, bar/value), 1.2 s auto-hide, replaces itself, suppressed while the
launcher/controls are open. The scripts keep owning hardware: `volume`, `brightness`,
`touchpad-toggle`, `audio-route` keep calling `osd …`, whose `notify-send -a osd -r <id> -h int:value:N`
contract routes here via the rule S-108 (`app == osd`). Tom: eqsh's OSD is the reference look; "i
really don't care if the brightness is managed by my shell". [w1-17][w1-18][w1-30 AM #122 #123][w1-36 T10]

| ID | Behaviour | Trigger | Data source | Replaces | P | Acceptance | Refs |
|---|---|---|---|---|---|---|---|
| S-115 **(rev)** | Volume OSD (level, mute glyph) from the `osd` contract; 0–100 only (AM #109). "Observe the service, not the key": the daemon also watches the default sink via `pw-dump`/`wpctl` and shows the card on any change (P1 part), so a bind that calls `wpctl` directly still produces an OSD. | auto (script / observed) | S-100, PipeWire | mako-rendered osd | P0 | smoke: `notify-send -a osd -h int:value:42` → bar at 42 %; P1: `wpctl set-volume` under the harness → card | [w1-17][w1-18][w1-19] |
| S-116 | Brightness OSD, same card type; eDP-1/eDP-2 label when the script passes it. | auto | S-100 | mako | P0 | smoke | [w1-17] |
| S-117 | Mic mute OSD and touchpad on/off OSD (Menu key / caps). | auto | S-100 | mako | P0 | smoke | [w1-17] |
| S-118 | Audio output switched OSD (device name + icon) when `audio-route` changes sinks. | auto | S-100 | none | P1 | smoke | [w1-30 AM #126] |
| S-119 | Media OSD (track, art) on `media next/prev` and HUD text from `showHUD`; `gpuix-shell osd show --icon x --label y [--value n]` CLI for scripts that want to skip notify-send. | auto/CLI | MPRIS, socket | none | P1 | bun test | [w1-30 AM #125][w1-36 showHUD] |
| S-120 | OSD position config (8 anchors, default bottom-centre) and per-type enable. | — | S-009 | none | P2 | bun test | [w1-30 AM #127 #128] |

(Ids S-120 onward in §5 restart at S-121 to avoid the clash above.)

---

## 5. Workspace switcher (Mod+i)

Overlay on eDP-1 only (S-015), top margin 108, keyboard exclusive, spawned per show, a vertical list
of the nine slots with herdr status, running time, seat and projector state; Tom's "i love it" look.
Sway has no overview; this is the overview (AM #173). [w1-01][w1-02][w1-06]

| ID | Behaviour | Trigger | Data source | Replaces | P | Acceptance | Refs |
|---|---|---|---|---|---|---|---|
| S-121 | `gpuix-shell switcher toggle`: list of slots 1–9 (+10 Chrome), row = number, name, glyph/word, running time, agent name/mark; j/k or arrows, 1–9 jump, Enter → `swaymsg workspace N` with verify, Escape closes; opened with the current slot highlighted. | bind (Mod+i)/CLI | S-004 + S-005 | `herdr-picker` fzf for switching | P0 | smoke: toggle maps on eDP-1 only; Enter switches; `ui-tree` has 9 rows | [BRIEF §3.2][w1-06][w1-16] |
| S-122 | Alt+Tab-style cycle: holding Mod and repeated i cycles MRU slots; release switches (INFERRED chord: Mod+i again moves selection; Mod release commits). | bind | S-004 focus history | none | P1 | smoke | [w1-10 G] |
| S-123 | Row actions (Ctrl+B): rename, restore, close (confirm), move focused window here, open herdr sidebar; all via existing scripts. | launcher-style | scripts | none | P1 | bun test argv | [w1-07][w1-17] |
| S-124 | Thumbnails via `grim -o eDP-1` snapshot per workspace (screencopy) cached 2 s, shown on the right of the row. | auto | grim | none | P2 | smoke | [w1-30 AM #165] |
| S-125 | Cull idle shells: an action "Close idle slots" that lists idle herdr workspaces with no agent and offers `sway-workspace close` per row (confirm each). | launcher-style | S-005 | none | P2 | bun test | [w1-07] |

---

## 6. Quick controls (per-domain menus)

Tom's March ruling "WONT, i do not need a control center" (AM `:597`) stands against a tile grid;
tonight's order asks for "wifi menu, or bluetooth pairing menu; etc." and the June 2026 D20 ruling
made network + bluetooth "critical to v1". So `gpuix-shell controls` opens **one domain list at a
time** (`controls open wifi\|bluetooth\|audio\|brightness\|media\|battery\|power-profile\|night-light\|dnd\|input\|tailscale`),
560×710 precedent, overlay, keyboard exclusive, spawned per show, same row grammar as the launcher;
each view is also a launcher provider. Toggle grammar on rail glyphs: left = toggle, right = open
detail, scroll = cycle. No grid. INFERRED. [BRIEF §1][w1-10][w1-29 §1.12 G1][w1-30 AM #268 §2.7]

| ID | Behaviour | Trigger | Data source | Replaces | P | Acceptance | Refs |
|---|---|---|---|---|---|---|---|
| S-126 | Wifi menu: radio toggle, known networks first, scan list (SSID, strength, security, band/channel/BSSID detail), connect (password form, WRITE-reversible; wrong password surfaces NM's reason), disconnect, forget (confirm), hidden SSID entry, wired section (IP/MAC/speed/DNS), NM VPN profiles up/down, airplane mode (rfkill wifi + bt), network speed line (/proc/net/dev deltas). NM SecretAgent is P2; v1 uses `nmcli dev wifi connect … password` through a password field (SECRET-AUTH, never logged, never on the socket). `fzf-nmcli` (255-line Python) is the behaviour to port. | bind (INFERRED chord Mod+Ctrl+w; Mod+Shift+w is Gmail)/launcher/click | NetworkManager D-Bus + `nmcli` | `fzf-nmcli` | P0 | bun test: NM fixtures → rows; smoke: view maps; hand check: connect to the home SSID | [w1-17][w1-23][w1-26][w1-29 G6][w1-30 AM #133–#147] |
| S-127 | Bluetooth menu: power toggle, discoverable toggle, scan (RSSI order), paired/connected sections, connect/disconnect, pair/forget (confirm), battery %, codec line, top-3 pins; pairing agent (BlueZ Agent1: PIN/passkey/confirm sheet, Tacit style; needed for the Magic Trackpad and Huion) is P1 within this row. | bind (INFERRED Mod+Ctrl+b)/launcher/click | BlueZ D-Bus | none (nothing exists today) | P1 | bun test on BlueZ fixtures; agent methods under dbus-run-session | [w1-20][w1-23][w1-30 AM #148–#157] |
| S-128 | Audio menu: sinks and sources with default marks, Enter = `audio-route <sink>`, mic default, per-app streams with volume (per-app mixer, P2), volume slider 0–100, mute; wheel adjusts. | bind (F9)/launcher/click | `wpctl status`, `pw-dump` | F9 fzf prompt | P0 | bun test: parser of `wpctl status`; smoke | [w1-17][w1-18][w1-30 AM #104–#111] |
| S-129 | Brightness: slider per output calling `brightness set N [output]` (script keeps floor/mirroring); keyboard ±. | launcher/click | `brightnessctl` via script | none | P1 | bun test argv | [w1-17][w1-30 AM #123] |
| S-130 | Media: MPRIS players list, art, title/artist, progress with seek (scroll to seek, "love the progress bar"), play/pause/next/prev, shuffle/loop, volume; multi-player pick; cover-art cache. | launcher/click | MPRIS | none | P1 | smoke with fake player | [w1-30 AM #115–#118 #121 #48] |
| S-131 | Battery/power profile: UPower detail (rate, time to empty/full, health), power-profiles-daemon selector (performance/balanced/power-saver). | launcher/click | UPower, PPD D-Bus | none | P1 | bun test fixtures | [w1-23][w1-30 AM #54] |
| S-132 **(rev)** | Night light: temperature presets per output via `rs.wl-gammarelay` D-Bus (`/outputs/eDP_1` `Temperature`), "set once" semantics, never auto-scheduled. Tom's AM #243 "WONT … set once and not from the shell" stands against ownership; the row exists only because tonight's task names it: P2, read + one-shot set (INFERRED). | launcher/click | wl-gammarelay-rs D-Bus | none | P2 | bun test: D-Bus call shape | [w1-17][w1-26][w1-27 §2.1 :546][w1-30 AM #53] |
| S-133 | DND and caffeine: DND toggle (S-105); caffeine = `systemd-inhibit` idle/sleep toggle (ICEBOX section; shipped only as the single toggle). | launcher/click | S-105, systemd-inhibit | none | P1 (DND) / P2 (caffeine) | bun test | [w1-30 AM #71 #232] |
| S-134 | Input: touchpad toggle (`touchpad-toggle`), caps LED state, keyboard layout (read-only), natural scroll from Sway config (read-only). | launcher/click | scripts, `swaymsg -t get_inputs` | none | P1 | bun test | [w1-17] |
| S-135 | Tailscale peers: connection state, exit node pick (`tailscale set --exit-node`, confirm), peer list with online dots and `ssh` action (opens kitty); "what other devices are connected on my tailscale network". | launcher/click | `tailscale status --json` | none | P1 | bun test | [w1-26][w1-30 AM #41 #144] |
| S-136 | Airplane mode row and "Network settings" entry (replaces the dotfiles desktop entry). | launcher | rfkill | desktop entry | P1 | bun test | [w1-30 AM #146][w1-36 §3.13] |

---

## 7. Power / session menu

`gpuix-shell power toggle`: overlay list (DMS style, AM #37/#218): scroll/select AND press-and-hold
the row's key (1.2 s, visible progress fill) to run; Escape closes; spawned per show. "No real sleep"
on the Zenbook: suspend is behind `power.allowSuspend` (default off); no swap → hibernate and
suspend-then-hibernate are hidden (INFERRED). Bind: Mod+Shift+e (unused today) INFERRED. [w1-07][w1-10][w1-30 AM #218]

| ID | Behaviour | Trigger | Data source | Replaces | P | Acceptance | Refs |
|---|---|---|---|---|---|---|---|
| S-140 **(rev)** | Rows: Monitors off (`monitors-off`), Sleep monitors (`sleep-monitors`), Lock (placeholder → S-188; hidden until a locker exists), Logout (`swaymsg exit`), Reboot (`systemctl reboot`), Power off (`systemctl poweroff`), Hibernate / suspend-then-hibernate (only when `/sys/power/state` lists `disk` and a swap device exists: never on the Zenbook tonight), Suspend (flag). Reboot/poweroff/logout = ACTION-irreversible → hold-to-confirm, single-action guard; monitors off = plain Enter. Fallback chain `systemctl → loginctl`, caching the winner. | bind/CLI/launcher | logind + scripts | fzf-less today (Mod+Shift+p monitors-off) | P0 | smoke: toggle maps; holding `r` for 1.2 s on a fake backend fires once; Enter on reboot does nothing; hibernate row absent without swap | [w1-10][w1-17][w1-27 §5.1][w1-30 AM #218–#220] |
| S-141 | logind `PrepareForSleep`/`Inhibit` delay lock so a future locker runs first; today only logs. | auto | logind D-Bus | none | P2 | bun test | [w1-26] |
| S-142 | Session screen footer: uptime, battery, herdr blocked count ("2 slots need input") as a reminder before logout. | auto | S-005, UPower | none | P1 | smoke | [w1-20] |

---

## 8. Clipboard

Own store (BRIEF §3.4, the newer ruling) with the cliphist semantics Tom cares about (images, no
Rust, no second daemon beyond `wl-paste --watch`); Tom's March preference was cliphist ("could
convince me to move away from cliphist", AM `:634`), so an import path from cliphist's store is kept
(INFERRED). [w1-18][w1-29 G2][w1-30 AM #86 #233 G5]

| ID | Behaviour | Trigger | Data source | Replaces | P | Acceptance | Refs |
|---|---|---|---|---|---|---|---|
| S-145 **(rev)** | Watcher: `wl-paste --watch gpuix-shell clipboard ingest` (text and image mimes), dedupe by hash, kinds text/link/colour/file/image, `ignorePasswords` (x-kde-passwordManagerHint), concealed copies skipped, eviction 24 h (`evictionThreshold 86400`) except pinned (`preserveTagged`), cap 1000 entries, images stored as files under state with thumbnails, SQLite FTS for text; `clipboard import-cliphist` one-shot; the launcher view S-064 reads it. Only one watcher ever runs (`startup.conf` rule). | auto | wl-paste | cliphist + vicinae clipboard | P0 | bun test: ingest/dedupe/evict/pin/import; smoke under the harness with `wl-copy` | [w1-18][w1-30 AM #86] |
| S-146 **(rev)** | CLI: `clipboard list [--json]`, `clipboard copy <id>` (GPUIX has no JS clipboard API: copy goes through `wl-copy` with the stored mime), `clipboard pin <id>`, `clipboard clear` (confirm flag), `clipboard ingest`. | CLI | store | cliphist CLI | P0 | bun test (fake `wl-copy` on PATH) | [w1-15][w1-18] |
| S-147 **(rev)** | Paste path: Enter copies then sends a paste keystroke via `wtype` if present (prefixed by a no-op key, since `wtype` loses its first key), else copy only (Tom runs no input server). | launcher | — | vicinae input server (off) | P1 | bun test argv | [w1-15][w1-36 Action.Paste] |

---

## 9. Screenshot / record / colour picker / OCR integration

Sway binds and scripts stay the owners (AM #234 "existing window manager is sufficient", #237); the
shell displays results and offers launcher entries.

| ID | Behaviour | Trigger | Data source | Replaces | P | Acceptance | Refs |
|---|---|---|---|---|---|---|---|
| S-148 | Screenshot result toast with image preview and actions "Open", "Copy", "Annotate (satty)", "Send to agent" when `screenshot` notifies (it calls notify-send); launcher entries `screenshot:screen/area/window` call the script (Mod+s/Shift+s/Alt+s unchanged). | auto/launcher | S-100 | none | P0 | smoke: a notify-send with image-path shows the preview | [w1-17][w1-30 AM #234] |
| S-149 | Recording: `recording-toggle` and OBS entries in the launcher; rail dot S-033; stop action in the dot's menu (P2). | launcher | scripts | none | P1 | bun test | [w1-17] |
| S-150 | Colour picker: Mod+c `colorpicker` unchanged; its result toast shows a swatch + hex with "Copy" (the shell renders the `image-data`/colour hint). | auto | S-100 | none | P1 | smoke | [w1-17][w1-30 AM #237] |
| S-151 | OCR: Mod+Ctrl+s `screen-ocr-area` unchanged (local model at strix:8731, thinking off, model id discovered from `/v1/models`, never pinned; Tom's "qwen multimodal, not tesseract" realised); result toast with "Copy" and "Send to agent"; launcher action "OCR selection"; `ocr:last` in the launcher. | auto/launcher | S-100 + script | none | P1 | bun test on a recorded notify payload; no network in tests | [w1-17][w1-24][w1-30 AM #238] |

---

## 10. File explorer (Pinax-inspired)

`gpuix-shell files` is a normal top-level window (not layer-shell), the Tacit/Pinax grammar: left
places rail, header with path crumbs and view switch, list/grid/gallery, preview column, shelf,
jobs with 60 s undo, trash. Nautilus stays the portal file picker (Mod+e today) until `files` is
proven; picker mode is later. [w1-09][w1-20]

| ID | Behaviour | Trigger | Data source | Replaces | P | Acceptance | Refs |
|---|---|---|---|---|---|---|---|
| S-155 | Window + places rail (Home, Downloads, Documents, Paper/inbox, Speech/intake, Screenshots, NAS mounts, devices via `udisksctl`/GIO mounts, Trash), header crumbs, list view with size/modified/kind columns, sort, hidden toggle, filter-as-you-type vs search grammar (`kind:`, `>1M`, `age:`), recent, "large & old" smart view. | launcher `files:open` / CLI `files open <path>` (no bind tonight: Mod+Shift+e is power, Mod+e keeps nautilus; INFERRED) | fs + GIO | none (nautilus stays) | P1 | smoke: window opens on a temp tree, list rows; bun test: search grammar | [w1-20] |
| S-156 | Preview column: text/code (mono), images, PDF first page (`pdftoppm`), audio/video (metadata), markdown rendered; offer pill with the likely action. | click | fs | none | P1 | bun test mime → previewer | [w1-20] |
| S-157 | Actions: open, open with (apps list), rename (inline), new file/folder, copy/cut/paste (mime dance: `text/uri-list` + `x-special/gnome-copied-files` via `wl-copy`), move to trash (`gio trash`), restore from trash, delete permanently (confirm), duplicate, compress, copy path, open terminal here, DnD between panes/windows; jobs runner (`job.sh` style) with progress + 60 s undo for move/rename/trash. | keyboard map (Tacit) / context menu | GIO | none | P1 | bun test: job plans + undo inverse; smoke: trash then restore | [w1-20] |
| S-158 | Send to agent: "Send to slot N" copies the path(s) and switches to workspace N; nothing is typed into the PTY (INFERRED safe behaviour). | context menu | S-005 | none | P1 | bun test | [w1-16][w1-20] |
| S-159 | Grid + gallery views, shelf (temporary multi-select basket), twins (two-pane), status line, empty states. | click | — | none | P2 | smoke | [w1-20] |
| S-160 | Picker mode (`files pick --multiple --dirs`) for the extension host's `Form.FilePicker`; portal remains Nautilus. | CLI | — | none | P2 | bun test | [w1-20][w1-36] |

---

## 11. Keybinding cheatsheet

| ID | Behaviour | Trigger | Data source | Replaces | P | Acceptance | Refs |
|---|---|---|---|---|---|---|---|
| S-165 | `gpuix-shell cheatsheet toggle` (Mod+Shift+slash INFERRED; `?` prefix in the launcher): parses the rendered Sway config (`swaymsg -t get_config` or the dotfiles binds files) + the shell's own keymap into grouped columns (Launch, Workspaces, Windows, Media, Shell), searchable, shows the comment above each bind as its label; Tom's 2025 "hotkeys visualizations" wish. | bind/launcher | Sway config | none | P1 | bun test: binds.conf → groups; smoke | [w1-10 G][w1-30 §2.1 G9] |
| S-166 | Collision report: binds that shadow each other or chords used by Chrome/herdr-web-ui (Mod+Shift+K palette) flagged in the sheet; a CLI `cheatsheet lint` (also run by S-017). | CLI | same | none | P2 | bun test | [w1-09] |

---

## 12. Tray (SNI)

| ID | Behaviour | Trigger | Data source | Replaces | P | Acceptance | Refs |
|---|---|---|---|---|---|---|---|
| S-168 | `org.kde.StatusNotifierWatcher` host in the rail process, items as rail glyphs with dbusmenu rendered as a launcher-style menu; Tom "won't be using it personally"; no own tray icon (`tray.enabled false`). | auto/click | session bus | waybar tray, vicinae tray | P2 | bun test with a fake SNI item under dbus-run-session | [w1-23][w1-26][w1-30 AM #29] |

---

## 13. Calendar / clock

| ID | Behaviour | Trigger | Data source | Replaces | P | Acceptance | Refs |
|---|---|---|---|---|---|---|---|
| S-170 | Clock in the rail (S-025) and launcher footer; `clock` popover on click shows date, week number, timezone list (config) — no month grid (AM #240 WONT), no events (calendar app is launched, not built; Notion Calendar PWA on Mod+Shift+period). | click | system | none | P1 | smoke | [BRIEF §3.8][w1-30 AM #239 #240] |
| S-171 | Start-of-day sheet (idea): at first launcher open of the day show yesterday's done slots and blocked ones; opt-in config. | auto | S-005 history | none | P2 | bun test | [w1-07] |

---

## 14. System monitor

| ID | Behaviour | Trigger | Data source | Replaces | P | Acceptance | Refs |
|---|---|---|---|---|---|---|---|
| S-175 | `claude-capacity` and `seats` in the launcher (`system:capacity`) and as optional rail items: per-seat usage bars from `~/.local/state/tally-rewrite/meters`. | launcher/auto | scripts | none | P1 | bun test on script output | [w1-17][AGENTS.md seats] |
| S-176 | CPU/mem/disk/temp mini view (`system:monitor`), top processes, kill (confirm) — later. | launcher | /proc, `ps` | none | P2 | bun test | [w1-30 AM #245] |

---

## 15. Updates

| ID | Behaviour | Trigger | Data source | Replaces | P | Acceptance | Refs |
|---|---|---|---|---|---|---|---|
| S-178 | NixOS meaning of "updates": current generation, last switch time, pending `fwupd` updates, failure markers; shown in S-084; no polling timers in dotfiles. | launcher | local state | none | P2 | bun test | [w1-29 G15][w1-30 AM #47 #248][AGENTS.md D41–D49] |

---

## 16. Theme switching

| ID | Behaviour | Trigger | Data source | Replaces | P | Acceptance | Refs |
|---|---|---|---|---|---|---|---|
| S-180 | Follow `~/.config/theme` live (S-007); `theme` script drops its `vicinae theme set` line; F2/Shift+F2 keep the prompt until S-069 lands, then call `gpuix-shell launcher open -q "theme"`; manual only, no auto dark/light (AM #184). | auto/bind | symlink | vicinae theme | P0 | smoke: flip symlink → re-render | [w1-17][w1-36 §3.13] |
| S-181 | UI scale Ctrl+/− on overlays (0.8–1.6, persisted as a theme scale factor; GPUIX has no zoom API), rail exempt. | bind in-surface | state | none | P2 | bun test | [w1-05][w1-11][w1-15] |

---

## 17. Wallpaper

| ID | Behaviour | Trigger | Data source | Replaces | P | Acceptance | Refs |
|---|---|---|---|---|---|---|---|
| S-185 | Solid `#000000` only (AM #185 OLED): Sway `output * bg #000000 solid_color` stays in dotfiles; the shell never sets wallpaper; `Wallpaper` API reports unavailable. | — | Sway config | none | P0 (nothing to build; assert) | bun test: `canAccess(Wallpaper) === false` | [BRIEF §1][w1-30 AM #191–#196] |

---

## 18. Lock screen / auth

| ID | Behaviour | Trigger | Data source | Replaces | P | Acceptance | Refs |
|---|---|---|---|---|---|---|---|
| S-188 | Not built tonight: no swaylock installed, Tom "rarely to never" locks (AM #203 icebox), GPUIX has no `ext-session-lock` binding. Seam: the power row "Lock" and logind delay-inhibit (S-141) are wired to a `gpuix-shell lock` verb that exits 69 until a locker exists; there is no `unlock` verb, ever. | CLI | — | none | P2 | bun test: exit 69; no `unlock` in the verb table | [w1-11][w1-26][w1-29 §3.6][w1-30 AM #203] |
| S-189 | Polkit agent (`org.freedesktop.PolicyKit1.AuthenticationAgent`) with a credential modal (SECRET-AUTH, PAM via `polkit-agent-helper-1`, 90 s wall timer, 3 retries): Tom's MUST ("low-hanging fruit", AM #216/#256) and no agent is configured today, but GPUIX has no PAM path tonight; P2 with the modal core shared with wifi passwords and BT passkeys (INFERRED). | D-Bus | polkit | gtk agent (none configured) | P2 | bun test modal; later: `pkexec true` prompts in the shell | [w1-10 G][w1-29 §3.5 G2][w1-30 AM #216 #256 G2] |

---

## 19. Agent / herdr surfaces

herdr now holds every role the 2026 designs gave to shpool, kerdr, the ccd daemon, semaphore files,
OSC 99 and `.title` files: one source (`herdr api snapshot`) instead of seven; the shell reads it and
acts only through Sway. [w1-28 §3.13][w1-29 §3.8][w1-30 §2.9]

| ID | Behaviour | Trigger | Data source | Replaces | P | Acceptance | Refs |
|---|---|---|---|---|---|---|---|
| S-190 | Attention routing: blocked slot → rail orange mark (S-022) + one notification with "Go" (S-109) + Sway urgency already set by herdr; done → green "New activity" until visited; never auto-focus; no approve button in the rail (answering stays in the projector). | auto | S-005 | herdr-attention branch | P0 | covered by S-022/S-109 | [w1-05][w1-16][w1-28 §6.7] |
| S-191 | Picker: S-063 (launcher `@`) and S-121 (Mod+i) are the two herdr pickers; `herdr-picker` script is retired after both pass; Mod+Ctrl+space rewired to `launcher open -q "@"`. | bind | S-005 | `herdr-picker` | P0 | binds table | [w1-17][w1-36 §3.13] |
| S-192 | Projector management (read + lifecycle via existing scripts only): new/restore/rename/close rows in S-063/S-123; "projector collapsed" state (slot has a herdr workspace but no kitty window) shown as a hollow glyph with a "Restore" action (`sway-workspace restore`). | launcher | S-005 + Sway marks | — | P1 | bun test: collapsed detection from marks | [w1-07][w1-16] |
| S-193 | Terminal⇄chat toggle (Mod+grave, `herdr-context`): the swap between kitty projector and the herdr-web-ui Chrome app stays a script; the rail reflects which face is up (glyph suffix). Rail collapse uses a different chord (Mod+Shift+grave INFERRED). | bind | script + Sway marks | — | P1 | bun test | [w1-09][w1-10 G] |
| S-194 | "Send to agent" from files/screenshot/OCR/clipboard: copies the payload and switches to the chosen slot; never injects into the PTY. | launcher/context | S-005 | none | P1 | bun test | [w1-16][w1-20] |
| S-195 | Agent list view (`@agents`): `herdr agent list` rows (name, slot, status, running time), read-only. | launcher | herdr | none | P1 | bun test | [w1-16] |
| S-196 | Remote seats: `herdr --remote strix` snapshot merged under a seat prefix when reachable; rail shows the seat letter on labels. | auto | herdr | none | P2 | bun test | [w1-16] |
| S-197 **(new)** | Optional herdr metadata: when `report-metadata` fields (model badge, context %, diff stat, cost) are present in the snapshot, the switcher row and the rail expanded row show them (kmux L3 anatomy); absent fields render nothing, never a placeholder. | auto | S-005 | none | P2 | bun test: with/without fields | [w1-28 §6.8][w1-30 §3.3] |

---

## 20. OpenUI "ask" (exploratory, bounded)

No live generation probes during the night (Halogen restart incident [w1-24]); everything here is
validated with recorded responses. Model id is discovered from `/v1/models` at call time; there is no
remote-model fallback (INFERRED). Tom AM #247: "i have some ideas here so not marking this as won't".

| ID | Behaviour | Trigger | Data source | Replaces | P | Acceptance | Refs |
|---|---|---|---|---|---|---|---|
| S-200 | `gpuix-shell ask "<prompt>"` / launcher `ask:prompt`: streams a chat completion (SSE `completionChunks` parser) from `http://strix:8731/v1/chat/completions` into a Detail view; copy / send to agent actions; model id from `/v1/models`; timeouts and a 4 k token cap. | launcher/CLI | local model | none | P2 | bun test with recorded SSE fixtures; no network in tests | [w1-08][w1-14][w1-24] |
| S-201 | OpenUI adapter: library `gpuix-shell.ask@1`, `ShellAction` vocabulary (open app, switch workspace, copy, notify, run script from an allow-list), `validateAsk` rejects anything else (untrusted model output is firewalled from exec/window verbs), replay log in state; generated quick-controls and notification summaries are experiments behind `ask.experimental`. | launcher | same | none | P2 | bun test: validator rejects unknown actions; replay round-trip | [w1-14][w1-24][w1-30 §4.1 10] |
| S-202 **(new)** | Halogen liveness: `ask` and `screen-ocr` paths check `/v1/models` once (2 s timeout) and show "local model offline" instead of hanging; no retry loop, no remote fallback, no test ever dials strix:8731. | auto | `/v1/models` | none | P2 | bun test with a fake server | [w1-24] |

---

## 21. Explicitly out (do not build; ruled)

Hyprland/niri/any second compositor; blur/frost/shadows/glass; Material You/matugen; GTK/Qt theming;
wallpaper pickers/per-monitor/fill/slideshow/parallax/procedural sky; i18n/RTL; animation knobs;
audio visualizers; volume >100 %; screenshot editor (satty is the script's); screen pin/measure/palette;
notes/notepad; webcam mirror; shutdown timer; SDDM/greeter; lock screen tonight; idle suite; video
screensaver; scheduled DND; inline reply; notification FTS/snooze/urgency grouping; hotspot; dGPU
launch; BongoCat; desktop widgets; global menu bar; weather; keyboard-layout widget; tray icon of
our own; settings GUI; plugin browser/store; TOML config; any timer/OnCalendar in dotfiles; wake word /
dictation; NPU paths; on-screen keyboard; touch gestures (Sway `bindgesture` exists, "icebox
maximally"); calendar grid/events/CRM/mail (cfos webapps); printer UI (paper-daemon); herdr focus
calls; approve-from-rail; writing Sway config from the shell; Vicinae/mako/waybar running beside the
shell. [BRIEF][w1-27 §3][w1-29 §3.1 §3.7][w1-30 §3.1 §4.3][AGENTS.md]

---

## 22. Keybinding rewire (the morning diff to `binds.conf`)

| Bind | Today | Tomorrow |
|---|---|---|
| Mod+d, Mod+space | `vicinae toggle` | `gpuix-shell launcher toggle` |
| Mod+v | `vicinae cmd launch clipboard:history` | `gpuix-shell cmd launch clipboard:history` |
| Mod+Ctrl+space | `herdr-picker` | `gpuix-shell launcher open -q "@"` |
| Mod+i | (PR #565, not in this branch's binds.conf) | `gpuix-shell switcher toggle` |
| Mod+o | (PR #571) | `gpuix-shell notifications dismiss-all` |
| Mod+Shift+o | — | `gpuix-shell notifications toggle` (INFERRED) |
| Mod+Shift+e | — | `gpuix-shell power toggle` (INFERRED) |
| F9 | `$prompt audio-route-prompt` | `gpuix-shell controls open audio` |
| F2 / Shift+F2 | `$prompt theme-prompt` | `gpuix-shell launcher open -q "theme"` (after S-069) |
| F10 / Shift+F10 / Shift+F9 | fzf prompts | keep until S-090–S-092 land, then launcher |
| Mod+Ctrl+w / Mod+Ctrl+b | — | `controls open wifi` / `controls open bluetooth` (INFERRED) |
| Mod+Shift+slash | — | `cheatsheet toggle` (INFERRED) |
| Mod+Shift+grave | — | `rail collapse` toggle (INFERRED; Mod+grave stays `herdr-context`) |
| Mod+m | — | `launcher --view music` (proposed in ASSUMPTIONS) |
| volume/brightness/media keys, Mod+s*, Mod+c, Mod+Ctrl+s, Mod+Shift+p, Menu, Mod+e | scripts / nautilus | unchanged |

---

## 23. Left unverified tonight (light verification, by rule)

- GPUIX SVG path rendering for agent marks (S-045) and whether `layerShell` can take an output
  parameter without the patch (S-015): both read from notes, not measured.
- Whether Chrome's installed Vicinae extension accepts a replacement native host under the same
  name without re-pairing (S-067).
- `sway-workspace new N` accepting a slot number (S-023).
- BlueZ Agent1 under dbus-run-session only; no real pairing was attempted (S-127).
- Memory budget per process (S-014) is a target, not a measurement of this build.
- Nothing in this document was checked against the live Sway session or strix:8731.

---

## P0 — must be on the Zenbook in the morning

1. S-001 process model: daemons as user units, overlays spawned per show
2. S-002 CLI + socket with per-connection routing (CLI never loads the native addon)
3. S-003 binds call the CLI (§22 diff)
4. S-004 Sway IPC client
5. S-005 herdr reader (read-only, nine-slot mapping, both seats)
6. S-006 D-Bus layer + `--check-dbus`
7. S-007 theme fragment, three themes, live symlink watch, static font instances
8. S-008 flat opaque look rules
9. S-009 config JSON + schema validation
10. S-010 `ui-tree` seam
11. S-011 compositor smoke harness under `runtime-test`
12. S-012 Nix package (installCheckPhase), HM module, vicinae/mako exclusivity, flake asserts
13. S-014 GPUIX engineering rules in the component library
14. S-015 output pinning dance
15. S-017 `validate` + `status --json`
16. S-019 command runner
17. S-020 rail slot rows 1–9 (+10)
18. S-021 click slot → workspace
19. S-022 run-state marks (blocked orange, done green)
20. S-024 status cluster registry
21. S-025 clock
22. S-026 battery
23. S-027 network glyph
24. S-029 audio glyph
25. S-030 notifications bell
26. S-037 rail toggle/collapse/expand verbs
27. S-050 launcher toggle + escape/backspace/pop-to-root
28. S-051 root search with sections, fallbacks, hidden list
29. S-052 favourites + frecency
30. S-054 action panel + keymap
31. S-055 header/footer chrome
32. S-056 navigation stack
33. S-059 confirm dialog for irreversible commands
34. S-060 apps provider (+PWA and dotfiles entries)
35. S-061 command registry + `cmd ls/launch`
36. S-062 windows provider on Sway IPC
37. S-063 herdr workspaces picker (`@`)
38. S-064 clipboard history view
39. S-065 files provider over `fd`
40. S-066 calculator
41. S-069 theme provider
42. S-070 power provider
43. S-072 wifi view in launcher
44. S-074 audio route view in launcher
45. S-078 notifications commands
46. S-086 `select` / dmenu bridge
47. S-092 sleep-monitors / monitors-off entries
48. S-095 `LauncherProvider` contract
49. S-100 fd.o Notifications server (notify-send parity)
50. S-101 toast card (urgency, timeouts, progress, actions, max 4, newest on top)
51. S-102 toast interaction + dismiss-all/restore-last
52. S-104 flood protection
53. S-105 DND
54. S-106 JSONL history restored on restart
55. S-109 herdr attention notification with "Go"
56. S-115 volume OSD
57. S-116 brightness OSD
58. S-117 mic/touchpad OSD
59. S-121 Mod+i switcher
60. S-126 wifi menu (controls)
61. S-128 audio menu (controls)
62. S-140 power menu with hold-to-confirm
63. S-145 clipboard store + watcher
64. S-146 clipboard CLI
65. S-148 screenshot result toast with preview
66. S-180 theme follow + `theme` script edit
67. S-185 wallpaper stays solid black (assert only)
68. S-190 attention routing
69. S-191 pickers replace `herdr-picker`

## P1 — this run, after P0

1. S-013 dev loop / logs
2. S-016 `listen` event stream
3. S-018 keyed status for scripts
4. S-023 empty slot "+"
5. S-028 bluetooth glyph
6. S-031 tailscale glyph
7. S-032 privacy dots
8. S-033 recording dot
9. S-034 pomodoro item
10. S-035 media item
11. S-038 fullscreen auto-hide
12. S-039 custom command button
13. S-040 launcher button
14. S-041 per-output rail config
15. S-045 agent marks per slot
16. S-053 prefix modes
17. S-057 detail pane + markdown
18. S-058 launcher toasts + HUD
19. S-067 Chrome tabs (reused extension + own native host)
20. S-068 emoji & symbols
21. S-071 script commands
22. S-073 bluetooth view in launcher
23. S-075 snippets & shortcuts
24. S-076 shell command mode
25. S-077 media commands
26. S-080 screenshots browse
27. S-085 Navidrome music demo
28. S-087 deeplinks
29. S-088 contextual root section
30. S-090 pomodoro provider
31. S-091 call-record provider
32. S-094 shell services / doctor view
33. S-096 extension host core (List/Detail/ActionPanel/Form/Storage)
34. S-103 grouping
35. S-107 notification centre
36. S-108 rules engine
37. S-114 toast hints overlay
38. S-118 audio-switch OSD
39. S-119 media OSD + `osd show` CLI
40. S-122 Alt+Tab-style cycle
41. S-123 switcher row actions
42. S-127 bluetooth menu + pairing agent
43. S-129 brightness view
44. S-130 media view
45. S-131 battery / power profile
46. S-133 DND toggle in controls
47. S-134 input view
48. S-135 tailscale peers
49. S-136 airplane mode + network settings entry
50. S-142 power footer reminder
51. S-147 paste path
52. S-149 recording entries
53. S-150 colour picker swatch toast
54. S-151 OCR result toast + `ocr:last`
55. S-155 files window + places + list + search grammar
56. S-156 preview column
57. S-157 file actions + jobs + undo + trash
58. S-158 send to agent
59. S-165 keybinding cheatsheet
60. S-170 clock popover
61. S-175 claude-capacity / seats
62. S-192 projector collapsed state + restore
63. S-193 terminal⇄chat face in the rail
64. S-194 send-to-agent plumbing
65. S-195 agent list view

## P2 — foundation seams and later (count only)

S-036, S-042, S-043, S-044, S-046, S-079, S-081, S-082, S-083, S-084, S-089, S-093, S-097, S-110,
S-111, S-112, S-113, S-120, S-124, S-125, S-132, S-141, S-159, S-160, S-166, S-168, S-171, S-176,
S-178, S-181, S-188, S-189, S-196, S-197, S-200, S-201, S-202 — 37 rows (plus the P2 halves of
S-096 and S-133, counted once above).

**Totals:** 171 feature rows; P0 69, P1 65, P2 37. Twenty surfaces plus foundations, the out-list,
the bind rewire and the unverified list. Eleven rows added this pass (S-015–S-019, S-045, S-046,
S-094, S-114, S-197, S-202); S-132 moved P1 → P2.
