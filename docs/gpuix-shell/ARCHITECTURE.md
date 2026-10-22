# gpuix-shell ARCHITECTURE: the engineering design

Synthesis for the overnight gpuix-shell build (2026-10-20/21, rerun 10-21 ~12:20). Written from
`BRIEF.md` and all 31 wave1 notes. It was checked against the sibling syntheses `SCOPE.md`,
`DESIGN.md`, `KEYS.md` and `BOUNDARY.md` as they stood at 12:33 on 10-21; those files were being
rewritten in parallel, so §22 lists every place where this file departs from them.

**What this file is.** This is how the shell is built: the process model, the wire protocols, the
package layout, the GPUIX usage rules, the data flows, the units, the Nix recipe, the tests and the
failure handling. It complements three siblings:

- `SCOPE.md` says what the shell does.
- `DESIGN.md` says what it looks like.
- `KEYS.md` says which key does what.

**Conventions**

- `[w1-NN]` cites the wave1 note that grounds a line. `[BRIEF]` cites `BRIEF.md`.
- **INFERRED** marks a decision taken tonight with no measurement or Tom ruling behind it. Each one is
  also logged as an `ARCHITECTURE:` line in `ASSUMPTIONS.md`.
- **MEASURED** means a wave1 reader or the orchestrator actually ran it. **UNVERIFIED** means nobody
  ran it.
- Paths are relative to the worktree `/home/tom/.wt/dotfiles/gpuix-shell` unless absolute. `PKG` means
  `pkgs/gpuix-shell`.

**Contents**

1. Ground rules this design obeys
2. Package layout
3. Process model
4. The command socket and the CLI protocol
5. GPUIX usage patterns
6. Data flows
7. Notification daemon
8. Launcher provider interface
9. Command registry
10. Theme and fonts
11. systemd user units
12. Sway binds
13. Home Manager module
14. Nix package recipe
15. Test strategy
16. Logging and diagnostics
17. Failure modes
18. Migration from vicinae and mako
19. Dependencies, versions and commands
20. Build order for wave 2
21. OpenUI `ask` (bounded, off the critical path)
22. Conflicts with sibling docs, resolved here
23. What this pass left unverified

---

## 1. Ground rules this design obeys

| # | Rule | Grounds |
|---|---|---|
| G-1 | Sway is the only compositor. The shell talks i3-ipc itself over `$SWAYSOCK`; there is no multi-compositor facade. | [BRIEF], [w1-02] ("let s stick to sway"), [w1-26], [w1-29 §4 v3] |
| G-2 | GPUIX 0.11.0 gives **one window per renderer** and has no window close, hide, resize, output selector or input region. The only way to close a surface is **process exit**. One surface = one process. | [w1-15 §3.4, G1–G3], [w1-03 L1/L2/L6] |
| G-3 | Keypress → Sway bind → `gpuix-shell` CLI is the only input path from keys. The shell never grabs global keys. | [w1-04], [w1-29 §4 v4], [w1-35 §3.4] |
| G-4 | herdr is read-only to the shell. The shell never calls `herdr workspace focus`, which is server-global. Slot identity comes from Sway marks. Workspace lifecycle stays with the `herdr-chord` and `sway-workspace` scripts. | [w1-07], [w1-16 §5.2] |
| G-5 | **One op, many callers.** Launcher rows, CLI verbs, Sway binds and rail clicks all invoke the same registry command id through the same socket. Every invoke carries `source` and returns `confirmed`, `failed` or `unknown` plus an echo. | [w1-12 C2.1/C2.7], [w1-10], [w1-04 C4], [w1-11 U-rules] |
| G-6 | **Verb classes:** READ, WRITE-reversible, ACTION-irreversible, SECRET.<br>• "Lock is a verb, unlock is not."<br>• Irreversible actions are gated: on screen by the hold, on the CLI by `--yes`.<br>• SECRET never crosses the socket: Wi-Fi passwords, Bluetooth passkeys and polkit stay inside a local form. | [w1-30 §3.2, §4.1 10], [w1-29 §4 v16] |
| G-7 | **No focus stealing.** A socket verb moves Sway focus only when its name says so (`focus`, `open`). | [w1-29 §3.3 P3], [w1-30 §4.1 11] |
| G-8 | **Render first.**<br>• A surface paints from the snapshot handed to it at spawn, then revalidates.<br>• Producers push full snapshots per topic on change. | [w1-29 §4 v19/v20] |
| G-9 | **Never both.** gpuix-shell replaces vicinae and mako in one Home Manager switch. Exactly one process owns each bus name. | [BRIEF], [w1-29 §3.5], [w1-21 §d] |
| G-10 | Nothing scheduled in dotfiles. No secrets in git. Fonts never in git. Tests never touch the live session: compositor tests run under `runtime-test --render-node`. | [BRIEF §4], Tom's runtime rules, [w1-21 §5.6] |
| G-11 | The shared core stays platform-neutral: it imports no I/O and no GPUIX. An import-fence test enforces this. | [w1-12 §3.2/§7], BOUNDARY §5 |

---

## 2. Package layout

### 2.1 Layers and the import fence

```
src/surfaces/<name>  ──►  src/ui/{kit,host}  ──►  src/platform/<area>  ──►  src/core/<area>
src/daemons/<name>   ──────────────────────────►  src/platform/<area>  ──►  src/core/<area>
src/cli              ──────────────────────────►  src/platform/socket   ──►  src/core/{socket,registry}
src/openui           ──►  src/core (+ react/@gpuix/react intrinsics in map.tsx only)
```

The task's `src/core` areas (sway-ipc, herdr, dbus, theme, fonts, registry, socket, logging) all
exist under `src/core/`. Each holds the **pure half**: types, codecs, models and derivations.
The **I/O half** of each area lives under `src/platform/<same name>/`. This satisfies the task's
layout and BOUNDARY §5's rule "nothing under `src/core` imports `child_process`, `node:net`,
`dbus-next`, `bun:sqlite`, `@gpuix/*`" at the same time (INFERRED split).

The fence is `src/fence.test.ts`, a `bun test` that greps import specifiers per glob. It is also wired
into the Nix check because `checkPhase` runs `bun test`.

| Glob | May import | Must not import |
|---|---|---|
| `src/core/**` | `src/core/**`, `zod` | `node:*`, `bun:*`, `dbus-next`, `react`, `@gpuix/*`, `@openuidev/*`, anything outside `src/core` |
| `src/platform/**` | core, `node:*`, `bun:sqlite`, `dbus-next` | `react`, `@gpuix/*`, `src/ui`, `src/surfaces`, `src/daemons` |
| `src/daemons/**` | core, platform | `react`, `@gpuix/*` (a headless daemon must never dlopen the 52 MB addon [w1-21 §4.3]) |
| `src/cli/**` | `src/core/{socket,registry,logging}`, `src/platform/{socket,fs}` | `react`, `@gpuix/*`, `bun:sqlite`, `dbus-next` (CLI budget ≤ 100 ms; bare bun is 81 ms MEASURED [w1-21]) |
| `src/ui/kit/**` | core, `react`, `@gpuix/react` (intrinsics and headless components) | `@gpuix/native`, `src/platform`, renderer init. This keeps the kit reusable on Marwan's macOS head [BOUNDARY §4.2, F9]. |
| `src/ui/host/**` | everything above, `@gpuix/react`, `@gpuix/native` | `src/surfaces` |
| `src/surfaces/<x>/**` | anything except `src/surfaces/<y>/**` internals | other surfaces (shared code goes to `ui/kit` or `core`) |
| `src/openui/**` | core, `@openuidev/lang-core`; `map.tsx` may use `react` + `@gpuix/react` | `src/platform` (the model client uses global `fetch` only) |
| all | — | herdr-web-ui `src/`, the kit's `apps/*`, the shared-parity bundle (copy with a provenance comment instead) [BOUNDARY §5 rule 2] |

### 2.2 Tree

Files marked (exists) are already on disk from the music design pass. All others are new.

```
pkgs/gpuix-shell/
  package.json            exact pins (§19); scripts: build, test, typecheck
  package-lock.json       the only lockfile Nix sees; bun.lock is git-ignored (§14)
  tsconfig.json           (exists) jsxImportSource @gpuix/react, strict, bundler resolution
  build.ts                Bun.build: src/main.ts, splitting, externals (§14.2)
  default.nix             buildNpmPackage recipe (§14.3)
  data/glyphs.json        P1: emoji + symbols from Vicinae glyph.cpp (GPL credit) [w1-35 §5]
  src/
    main.ts               argv dispatcher; dynamic-imports cli | daemons | surfaces | --check-*
    fence.test.ts         the import fence (§2.1)
    core/                 PURE (platform-neutral, extractable to the agency library)
      sway-ipc/           frame.ts (14-byte header, Msg, EVENT_NAMES), decode.ts (stream splitter),
                          model.ts (Output/Workspace/Con types), derive.ts (tree → SwayModel),
                          quote.ts (workspace-name quoting and reserved words [w1-08]), coalesce.ts
      herdr/              types.ts (snapshot shape [w1-16 §5.1]), marks.ts (5 mark regexes),
                          slots.ts (marks + snapshot → Slot[1..10]), status.ts (rank, glyph, word),
                          attention.ts (blocked-episode detector), mru.ts
      dbus/               notifications-spec.ts (signatures, caps, hint names, close reasons, limits),
                          markup.ts (b/i/u/a sanitiser), image-data.ts (iiibiiay → RGBA),
                          nm.ts / bluez.ts / upower.ts / mpris.ts / logind.ts (interface names, enums, types)
      theme/              schema.ts (zod, mirrors DESIGN §2.5), tokens.ts (Theme type), gpuix-theme.ts
      fonts/              families.ts (exact fontconfig names), weights.ts (weight → static face)
      registry/           types.ts, registry.ts, ids.ts (id ↔ JSON-RPC method), classes.ts,
                          grammar.ts (argv ↔ args), specs/<domain>.ts (pure CommandSpec tables)
      socket/             protocol.ts (JSON-RPC 2.0 types, error codes ↔ exit codes), ndjson.ts,
                          compat-frame.ts (4-byte length frames), sniff.ts, limits.ts
      logging/            logfmt.ts, redact.ts (no tokens, no URL queries, no clipboard bodies)
      state/              shell-state.ts (topic types), diff.ts (stable-stringify compare), rev.ts
      notifications/      store.ts (ids, replace, close reasons), rules.ts (first match), flood.ts
                          (20/s cap, 1 s coalesce), osd-route.ts, toast-layout.ts (card heights), history.ts
      launcher/           fuzzy.ts (herdr-bar constants), frecency.ts (Vicinae formula), rank.ts
      clipboard/          kinds.ts (mime → kind), policy.ts (password hint, eviction, pins)
      apps/               desktop-entry.ts (parser, Exec field codes, NoDisplay/Hidden/OnlyShowIn)
      scripts/            script-command.ts (Raycast/Vicinae header grammar [w1-36 §3.7])
      config/             schema.ts (zod for ~/.config/gpuix-shell/*.json), defaults.ts
    platform/             I/O adapters (Linux)
      sway/               ipc-client.ts (net socket), session.ts (cmd + event sockets, resync, SEND_TICK
                          barrier), output-pin.ts (focus dance), fake-server.ts (tests)
      herdr/              transport.ts (interface), local-socket.ts, ssh-forward.ts, ssh-exec.ts, poller.ts
      dbus/               bus.ts (session + system connection, reconnect), notifications-server.ts,
                          upower.ts, logind.ts, network-manager.ts, bluez.ts, bluez-agent.ts, mpris.ts,
                          later: ppd.ts, sni-watcher.ts, polkit-agent.ts, nm-secret-agent.ts
      socket/             server.ts (accept, sniff, route, per-connection replies), client.ts
      fs/                 paths.ts (XDG dirs, modes), atomic.ts (tmp + fsync + rename, 0600), watch.ts
      exec/               runner.ts (systemd-run scopes, timeouts, output cap), spawn.ts (surface children)
      clipboard/          watcher.ts (two wl-paste --watch children), ingest.ts, store.ts (bun:sqlite)
      apps/               index.ts (scan XDG application dirs, watch, cache)
      audio/              pipewire.ts (pw-dump --monitor), wpctl.ts
      tailscale/          status.ts (vpn-status JSON, else tailscale status --json)
      chrome/             native-messaging.ts (uint32 + JSON stdio), manifest.ts
      fonts/              static-dir.ts (reads GPUIX_SHELL_FONT_DIR)
      state/              frecency-db.ts (bun:sqlite), json-state.ts (versioned JSON files)
    daemons/              headless programs (never load @gpuix/native)
      core/               main.ts, hub.ts (state + topics), supervisor.ts (transient surfaces),
                          focus-guard.ts, handlers.ts, herdr.ts, status.ts, attention.ts
      notifications/      main.ts, server.ts, toasts.ts (child host), osd.ts (child host), handlers.ts
      native-host/        main.ts (Chrome native-messaging relay → shell.sock)
    ui/
      kit/                Row, Section, SearchField, VirtualRows, ActionPanel, Footer, Echo, Glyph, Dot,
                          ToastCard, ProgressFill, HoldToConfirm, Dialog, Keycap, Metadata, Empty, fields
      host/               mount.tsx, window-options.ts, fonts.ts, theme.tsx, core-client.tsx, keys.ts,
                          scale.tsx, exit.ts, ui-tree.ts, error-boundary.tsx, spawn-payload.ts
    surfaces/
      rail/ launcher/ switcher/ toasts/ osd/ center/ controls/ power/ cheatsheet/   (P0–P1)
      files/ (P1, xdg toplevel)   ask/ (P2)   gallery/ (should)
      launcher/providers/{apps,commands,calc,clipboard,files,windows,workspaces,herdr,emoji,wifi,
                          bluetooth,notifications,theme,tabs,shell,dmenu}.ts
    cli/                  main.ts, parse.ts (generated from registry specs), client.ts, output.ts,
                          dmenu.ts (stdin rows), compat.ts (Vicinae aliases), usage.ts
    openui/               spec.ts, library.spec.json (vendored), validate.ts, map.tsx, stream.ts, model.ts
    launcher/provider.ts  (exists) the frozen LauncherProvider contract (§8)
    music/**              (exists, partly) vertical slice per MUSIC.md §11; owner "music" in the registry
tests/gpuix-shell/        repo-root Python: smoke_<surface>.py (runtime-test only), test_*.py (hermetic),
                          fixtures/<host>-<hhmm>-<ipc>.json, driver.mjs (automation client) [w1-21 §5.6]
home/gpuix-shell.nix      Home Manager module (§13)
home/gpuix-shell-binds.nix  the generated Sway bind block appended to sway-local.conf (§12)
pkgs/anthropic-ui-static.nix   static Anthropic Sans/Serif instances (§10.3), store-only, never in git
```

Two rules for `src/launcher/provider.ts` and `src/music/**`:

- **They stay where the music pass put them.** Moving them would break the frozen contract
  (ASSUMPTIONS music line "provider.ts … verbatim from 05 §9.1").
- **The launcher surface imports the contract.** It reads `src/launcher/provider.ts` directly;
  `src/surfaces/launcher/` never redefines it.

---
## 3. Process model

### 3.1 The processes

| Process | Kind | Started by | Window | Owns | Lifetime |
|---|---|---|---|---|---|
| `gpuix-shell daemon core` | headless daemon | systemd `gpuix-shell-core.service` | none (no addon loaded) | `shell.sock` (the one command socket), the command registry and router, the Sway IPC session, the herdr poller, the status readers (UPower, NetworkManager, BlueZ, logind, MPRIS, PipeWire, Tailscale), the clipboard watchers and store, the apps index, frecency/MRU, the BlueZ Agent1 (P1), the Chrome tab list, the **surface supervisor** | session |
| `gpuix-shell daemon notifications` | headless daemon | systemd `gpuix-shell-notifications.service` (`Type=dbus`) | none | `org.freedesktop.Notifications`, the notification store, history, rules, DND, flood guard, OSD slot. It spawns the `toasts` and `osd` window children. | session |
| `gpuix-shell daemon rail --output eDP-1` | window daemon | systemd `gpuix-shell-rail.service` | 1 layer surface | `rail.sock`; the view only, a subscriber of core topics | session (exits to hide or to change width) |
| `gpuix-shell surface toasts` | window child | the notifications daemon | 1 overlay | `toasts.sock` | until the visible set changes, then replaced |
| `gpuix-shell surface osd` | window child | the notifications daemon | 1 overlay | `osd.sock` | while values arrive + hold 1500 ms |
| `gpuix-shell surface <launcher\|switcher\|center\|controls\|power\|cheatsheet\|ask\|gallery>` | toggled overlay | the core supervisor | 1 overlay | `<name>.sock` | one process per show; exits on Escape, toggle, focus loss or act-and-close |
| `gpuix-shell surface files` | ordinary window (xdg toplevel) | the core supervisor (or `files open` many times: one process per window) | 1 toplevel | `files-<n>.sock` | until the window closes |
| `gpuix-shell music serve` | headless daemon (P1) | systemd `gpuix-shell-music.service` | none | `music/ctl.sock`, MPRIS `org.mpris.MediaPlayer2.gpuix_music`, mpv | session (ASSUMPTIONS music lines) |
| `gpuix-shell native-host` | stdio relay | Chrome (native messaging) | none | — | while Chrome holds the port |
| `gpuix-shell <verb …>` | CLI client | Sway binds, scripts, Tom | none | — | one request |

Why a separate headless **core** instead of a router inside the rail (SCOPE S-002 rev places `shelld` in
the rail; INFERRED departure, §22):

1. **Hiding the rail kills it.** GPUIX cannot unmap a surface, so `rail hide` and `rail expand` are process
   exits [w1-15 §3.4, G3]. A router inside the rail would die with it.
2. **GPU faults hit only renderers.** A GPU reset or `ERROR_SURFACE_LOST_KHR` takes down renderer
   processes; the CLI, D-Bus clients and the clipboard history must survive that [w1-08].
3. **The core starts fast.** It never loads the 52 MB addon, so it starts in about 0.1 s and stays small
   (target ≤ 100 MiB RSS, UNVERIFIED).
4. **Every renderer is a view.** Each one is a subscriber that can restart without losing state.

Why notifications is its own daemon and not part of core:

- It must be `Type=dbus` with `BusName=` for activation and "never both" ownership [w1-13 HM precedent],
  [w1-21 §d].
- A crash in the store or rules must not cost the command socket. The reverse also holds: a core restart
  must not drop `notify-send` [w1-29 §3.5 single owner].

**One renderer per process** is a hard rule in production code, even though several renderers per
process work. Multi-renderer was measured only for 4–6 s [w1-15 §3.4 "UNVERIFIED long-run"], and a crash
should take down one surface only. `ui/host/mount.tsx` refuses a second mount.

Memory (MEASURED for 0.11: one surface 148.5 MiB, two in one process 163.4 MiB [w1-15]):

- **Always on:** about 150 MiB for the rail, plus two headless bun daemons (UNVERIFIED, about 60–90 MiB
  each).
- **While visible:** a further ~150 MiB per visible surface.
- **0.10 baseline:** the old build peaked at 869 MB [w1-03 L16]. The doctor reports RSS per unit (§16).

### 3.2 Singleton socket per surface

Every process that owns a window (and the two daemons) listens on its own socket:

```
$XDG_RUNTIME_DIR/gpuix-shell/            mode 0700, created by whichever process starts first
  shell.sock                             core: the ONE command socket (CLI, binds, scripts, surfaces)
  notifications.sock                     notifications daemon (core forwards notifications/* and osd/*)
  rail.sock  launcher.sock  switcher.sock  center.sock  controls.sock  power.sock  cheatsheet.sock
  toasts.sock  osd.sock  ask.sock  files-<n>.sock
  music/ctl.sock                         music daemon (existing contract)
  spawn/<nonce>.json                     one-shot spawn payloads, 0600, unlinked by the child
  herdr.sock                             ssh -L forward of the strix herdr socket (Zenbook only)
  ssh-<hash>                             ssh ControlPath for ssh-exec mode
```

Singleton rule ("bind is the lock", INFERRED; Bun has no `flock`):

1. **Probe.** Connect to `<name>.sock` with a 1 s timeout [w1-03 singleton contact 1 s] and send `ping`.
2. **Defer.** If a live instance answers, hand it the request instead of starting.
3. **Clear stale.** On `ECONNREFUSED`/`ENOENT`, `unlink` the stale path and `listen()`.
4. **Settle races.** `bind()` is atomic, so of two starters the loser gets `EADDRINUSE` and goes back to
   step 1.
5. **Check the session.** The `ping` reply carries `{pid, protocol, session}`, where
   `session = sha256($SWAYSOCK)[:16]` (the token from the prior switcher [w1-13]). A reply from another
   Sway session counts as stale. This guards against a leftover process from a previous Sway session.

Under the core supervisor only core spawns overlays, so races are core-internal; the rule still protects
the rail and the daemons when systemd and a manual start overlap.

### 3.3 The surface supervisor (in core)

```
CLI "launcher toggle --view clipboard"
  └► shell.sock ─► registry: launcher.toggle (owner surface:launcher)
        └► supervisor.toggle("launcher", args)
             state machine per surface:  closed ─spawn─► spawning ─ready─► open ─close/exit─► closed
             • closed:   close any other open exclusive overlay (DESIGN U-rule "one exclusive overlay");
                         write spawn payload; spawn child; state = spawning
             • spawning: second toggle ⇒ closeOnReady = true (a bind pressed twice fast never leaves a
                         window up); same-surface toggles within 150 ms are ignored (INFERRED debounce)
             • open:     args differ from the open view (new --view / --query) ⇒ send `update` to
                         <name>.sock (gpui-shell semantics "open, or update the query, or close") [w1-23];
                         same args ⇒ send `close`
```

Details:

- **Spawn.** The child is spawned by `platform/exec/spawn.ts`:
  - `Bun.spawn([GPUIX_SHELL_EXECUTABLE, "surface", name], { stdin: "ignore", stdout: "inherit", stderr: "inherit", env })`.
  - `stdin` is **ignored** because `createRenderer()` turns on stdio automation whenever stdin is not a
    TTY; `/dev/null` gives EOF and is harmless, while a stdin pipe would let the parent drive the GUI
    [w1-15 §3.1, G16].
  - The env carries `GPUIX_SHELL_SPAWN=$XDG_RUNTIME_DIR/gpuix-shell/spawn/<nonce>.json`.
- **Spawn payload** (INFERRED shape). It is everything needed for the first frame without a round trip
  (G-8):
  `{surface, args, nonce, session, output:{name,width,height,scale}, theme:<resolved tokens>, data:<per-surface snapshot>}`.
  The `data` per surface:
  - **launcher:** apps index, favourites, the frecency top 200, root registry commands, the last 50
    clipboard rows (metadata only).
  - **switcher:** slots.
  - **controls:** the network, bluetooth and audio snapshots.
- **Ready.** After its first commit the child sends `surface/ready {surface, nonce, pid}` on `shell.sock`.
  Core moves the state machine to `open` and, if `closeOnReady`, sends `close` at once.
- **Exit.** The child exits with `process.exit(code)`. Core sees the child's `exit` event and moves to
  `closed`. A non-zero exit is logged with the signal or code and published as
  `event surface.failed {surface, code}`. Core never retries a transient automatically, and core dumps
  are never suppressed (Tom's runtime rule).
- **Focus guard** (`daemons/core/focus-guard.ts`): this is how a toggle process closes on focus loss
  (§5.4).
- **Warm spare (P1, INFERRED, behind `supervisor.warmSpare`).**
  - **The spare.** Core keeps one pre-spawned `gpuix-shell surface --spare` process that has loaded the
    bundle and the addon but has not called `init()`.
  - **Handing over.** On `show`, core gives the spare its surface name over `spare.sock`; the spare
    calls `init()` and renders, and core starts a new spare.
  - **What it saves.** Bun start, bundle eval and the addon `dlopen` come off the measured ~0.3 s warm
    first paint [w1-15 §4]; `init()` itself costs 92–177 ms.
  - **When to turn it on.** Measure before enabling.

### 3.4 Who talks to whom

```
           Sway binds / scripts / Tom
                    │  argv
                    ▼
            gpuix-shell (CLI) ──NDJSON──► shell.sock ◄──── gpuix-shell native-host ◄─ Chrome extension
                                              │ core
      ┌──────────────┬────────────────────────┼─────────────────────┬───────────────────────┐
      │ Sway IPC ×2  │ herdr transport         │ D-Bus (system+session)│ wl-paste --watch ×2   │
      ▼              ▼                         ▼                       ▼                       │
   $SWAYSOCK   herdr.sock / ssh strix   UPower NM BlueZ logind MPRIS   clipboard store          │
                                              │                                                 │
      topics (state, events) ◄── subscribe ── rail, launcher, switcher, center, controls, power  │
      forwards notifications/*, osd/*  ──────► notifications.sock ◄─ D-Bus Notify (notify-send) │
                                              notifications daemon ──spawn──► toasts, osd         │
      forwards music/* ──────────────────────► music/ctl.sock (music daemon, MPRIS server)        │
      supervisor spawns ─────────────────────► launcher | switcher | center | controls | power ───┘
```

---

## 4. The command socket and the CLI protocol

### 4.1 Wire format

`shell.sock` speaks **JSON-RPC 2.0 messages, one per line** (NDJSON, `\n`-terminated UTF-8). This is the
task's "JSON lines + verbs":

- The method is the verb path, `<domain>/<verb>` (KEYS §7.0).
- The envelope is JSON-RPC 2.0 (SCOPE S-002).
- herdr's own socket uses the same newline framing [w1-16 §5.3].

The format can be debugged with `socat - UNIX-CONNECT:$XDG_RUNTIME_DIR/gpuix-shell/shell.sock`.

```jsonc
// client → core (request)
{"jsonrpc":"2.0","id":7,"method":"launcher/toggle",
 "params":{"args":{"view":"clipboard"},"source":"bind","tty":false,"cwd":"/home/tom","session":"3f9c…"}}
// core → client (reply, only ever on the requesting connection)
{"jsonrpc":"2.0","id":7,"result":{"outcome":"confirmed","echo":"Clipboard opened","data":null}}
// core → client (error)
{"jsonrpc":"2.0","id":7,"error":{"code":-32002,"message":"notifications daemon not running",
 "data":{"exit":69,"fix":"systemctl --user start gpuix-shell-notifications"}}}
// core → subscriber (notification, no id)
{"jsonrpc":"2.0","method":"state","params":{"topic":"slots","rev":4211,"value":{…full snapshot…}}}
{"jsonrpc":"2.0","method":"event","params":{"type":"surface.opened","surface":"launcher","at":1761040000123}}
```

**Compatibility framing (P1, INFERRED).** The listener also accepts Vicinae's framing: a 4-byte
native-endian length, then JSON-RPC 2.0 with `Ipc/<fn>` methods. With it, `herdr-picker`'s existing
`vicinae_menu()` client (`herdr-picker:211-258`) works after a path change alone [w1-36 §4.6].

- **Telling the two framings apart** (`core/socket/sniff.ts`):
  - An NDJSON request always starts with `{` and its third byte is never `0x00`.
  - A length frame is capped at 64 KiB − 1, so its third byte (length bits 16–23) is always `0x00`.
  - So: read 3 bytes; if `b0 === 0x7B && b2 !== 0x00` the connection is NDJSON, otherwise it is
    length-framed.
- **Supported methods:** `Ipc/ping`, `Ipc/dmenu`, `Ipc/launchCommand`, `Ipc/deeplink`, `Ipc/describe`.
- **Preferred port:** herdr-picker should still move to `gpuix-shell dmenu` (KEYS §7.3); the compat
  codec exists so that no flag day is needed.

**Reply routing.** Replies are keyed by **(connection, id)**, never by id alone. This fixes Vicinae's
reply-stealing bug, where every CLI connection starts at id 1 [w1-36 §3.5, G17]. When core forwards a
request to `notifications.sock` or `music/ctl.sock` it allocates its own ids and maps them back to the
original connection.

**Limits** [w1-03 §3.2 caps; w1-29 §5 MA B15]:

| Limit | Value |
|---|---|
| Request line | 16 KiB |
| `dmenu/*`, `select/*`, `clipboard/*`, `browser/*` | 1 MiB |
| Subscriber backlog | 4 MiB; past that the subscriber is dropped with an `events_lost` event, and the client re-subscribes and receives a full snapshot (the herdr pattern [w1-16 §5.3]) |
| Notification action entries | 32 |
| Action key | 256 B |
| Summary | 1 KiB |
| Body | 8 KiB |
| App name | 256 B |

**Security.** The directory is 0700 and the sockets are 0600, so only the same uid can connect. SECRET
methods do not exist (G-6). A password typed into a local form goes from the surface straight to D-Bus or
the store, never through `shell.sock`.

### 4.2 Built-in methods (not registry commands)

| Method | Direction | Purpose |
|---|---|---|
| `core/hello {role, name, pid, protocol}` | any → core | first message; `role` is one of `cli`, `surface`, `service`, `native-host`. The reply carries `{protocol:1, version, session}`; on a protocol mismatch the client prints "restart gpuix-shell-core" and exits 1 |
| `core/subscribe {topics[]}` / `core/unsubscribe` | surface → core | the reply carries the current snapshot of each topic; later changes arrive as `state` notifications |
| `core/invoke {id, args, source}` | any → core | generic invoke by registry id; `<domain>/<verb>` methods are sugar for it |
| `surface/ready`, `surface/closed {reason}` | surface → core | supervisor bookkeeping |
| `service/register {name, methods[]}`, `service/publish {topic, value}` | notifications, music → core | a daemon declares which methods core should forward to it, and publishes its topics through core |
| `core/ping`, `core/version` | any | liveness, under 5 ms |

### 4.3 Error codes and exit codes

The exit codes follow KEYS §7.8 and SCOPE S-002: 0, 1, 2, 3 and 69. Revision 1's 4 and 5 fold into 2
and 1.

| JSON-RPC error | Meaning | CLI exit |
|---|---|---|
| (result) | ok, or dmenu/select returned a row | 0 |
| -32000 `failed` | the action ran and failed (outcome `failed`), dmenu dismissed, or timeout | 1 |
| -32001 `refused` | ACTION without `--yes` off a TTY, or a SECRET path over the wire | 1 |
| -32700 / -32600 / -32601 / -32602 | parse error / invalid request / unknown method, surface, verb or view / invalid args (zod path in `data.issues`) | 2 |
| -32003 `not-running` | `shell.sock` absent or refusing (exit raised by the CLI itself), or a target daemon absent | 3 |
| -32002 `unavailable` | a capability is missing: no locker for `lock`, no music credentials, the bus name is held by mako, the tray tonight | 69 |

The error vocabulary below carries the CUBS codes in `error.data.kind` [w1-29 §5 S06:378]:
`NOT_FOUND`, `NOT_INITIALIZED`, `NOT_SUPPORTED`, `PERMISSION_DENIED`, `INVALID_PARAMS`, `TIMEOUT`, `BUSY`,
`CANCELLED`, `INTERNAL`.

### 4.4 The CLI

`src/cli/main.ts` takes argv through these steps:

1. **Match.** `core/registry/grammar.ts` finds the longest matching CLI path among the registry specs.
2. **Aliases.** Before matching, aliases are applied:
   - `toggle <surface>` and a bare `<surface>` mean `<surface> toggle`;
   - the Vicinae compat aliases `cmd launch`, `cmd ls`, `dmenu`, `open`, `close`, `state open`
     (KEYS §7.7).
3. **Flags.** Flags are parsed into an args object, which is validated with the spec's zod schema; a
   usage error exits 2 with generated usage text.
4. **Connect.** The CLI connects to `shell.sock` with a 1 s connect timeout.
5. **Request.** It sends `core/hello` and then the request.
6. **Output.** It prints the `echo` (human) or `data` (`--json`, available on every verb [w1-10]) and
   exits with the mapped code.

Rules:

- **Two flags exist on every verb:**
  - `--json` gives machine output.
  - `--source <bind|script|test>` defaults to `cli` on a TTY and to `script` otherwise. Binds pass
    `--source bind`.
- **Two flags apply to some verbs:**
  - `--hud` makes core show the echo as an OSD `hud` card, for verbs with no visible effect such as
    `dnd toggle`.
  - `--yes` is required for ACTION verbs when stdin is not a TTY [w1-10].
- **Streaming verbs:**
  - `listen` keeps the connection open and prints `event` and `state` lines.
  - `dmenu` and `select` read all of stdin, cap it at 1 MiB, send it, and print the chosen row (or its
    index with `-f index`) [w1-35 §3.1 dmenu].
- **Pre-socket self-checks:** `--check-native`, `--check-dbus` and `--check-theme <file>` run without a
  socket and print `{"ok":true,…}`. They are used by the Nix install check [w1-21 §4.3].
  `--check-native` dynamic-imports `@gpuix/native` and prints `err.cause` on failure.
- **Never load the addon.** The CLI never loads `@gpuix/native` (fence), and its cold start target is
  ≤ 100 ms.

---
## 5. GPUIX usage patterns

### 5.1 Render options per surface (exact `init()` options)

All surfaces share these base options:

- `windowBackground` is `'opaque'` for the rail and files and `'transparent'` for overlays (flat and
  opaque look, no blur [w1-28], [BRIEF]). A transparent
  overlay draws its own opaque, radius-12 panel and is sized to its content, never larger, because the
  transparent area of a layer surface still swallows clicks [DESIGN §7.2, line "never oversized"].
- `appId` equals `namespace`, which equals `gpuix-shell-<surface>`.
- `focus` and `show` are not passed, because they are ignored on Linux [w1-15 §3.2].
- Margins are `[top, right, bottom, left]`.

| Surface | layer | anchor | width × height | margin | exclusiveZone | keyboardInteractivity | Notes |
|---|---|---|---|---|---|---|---|
| rail (collapsed) | `top` | `['left','top','bottom']` | 56 × 0 (0 = stretch) | `[0,0,0,0]` | 56 | `none` | MEASURED geometry: rect x=56 width=1384 on 1440 [BRIEF rail probe], [w1-15 §4]. DESIGN says the rail never takes the keyboard. |
| rail (expanded) | `top` | same | 220 × 0 | `[0,0,0,0]` | 220 | `none` | A separate launch; see the width change below |
| launcher | `overlay` | `['top']` | 700 × 580 | `[108,0,0,0]` | 0 | `exclusive` | 108 is a fixed value (12 % of 900, DESIGN A-11); `tabNavigation:false` [w1-15 §3.10] |
| ask | `overlay` | `['top']` | 700 × 580 | `[108,0,0,0]` | 0 | `exclusive` | P2 |
| switcher | `overlay` | `['top']` | 560 × (48 + rows×44 + 36), max 580 | `[108,0,0,0]` | 0 | `exclusive` | rows = 10 slots, so 524. It is computed at spawn, because there is no resize. |
| cheatsheet | `overlay` | `['top']` | 700 × 580 | `[108,0,0,0]` | 0 | `exclusive` | INFERRED: launcher geometry |
| notification centre | `overlay` | `['top','right']` | 500 × 650 | `[12,12,0,0]` | 0 | `exclusive` | DESIGN A-28 |
| controls | `overlay` | `['top','right']` | 420 × content (≤ 640) | `[12,12,0,0]` | 0 | `on-demand`; `exclusive` while a field is focused | `on-demand` is UNVERIFIED [w1-15 G11]. The first smoke decides; if it fails, use `exclusive` (INFERRED fallback). The height comes from the spawn payload's row count. |
| power | `overlay` | `[]` (centred) | 360 × (46 + rows×44 + 36) | `[0,0,0,0]` | 0 | `exclusive` | DESIGN A-22 |
| toasts | `overlay` | `['top']` (default) or `['top','right']` | 390 × (Σ card heights + 8 × (n−1) [+ 32 "(N more)"]) | `[12,0,0,0]` or `[12,12,0,0]` | 0 | `none` | Anchor from `layout.toast.anchor`, default `top-center` (DESIGN A-15, Tom 2026-10-11 [w1-18], [w1-35 §1.1]) |
| OSD | `overlay` | `['bottom']` | 280 × 56 | `[0,0,96,0]` | 0 | `none` | DESIGN A-19, [BRIEF §3.3] |
| files | xdg toplevel (no `layerShell`) | — | 1000 × 640 default; Sway tiles it | — | — | — | `windowBackground:'opaque'`; app zoom applies (DESIGN A-39) |
| gallery | xdg toplevel | — | 1200 × 800 | — | — | — | storybook wish [w1-30 §4.1 14] |

How the options behave:

- **exclusiveZone.** A value of `0` means "the compositor decides": the surface respects other exclusive
  zones but reserves none. `-1` reserves nothing and ignores other zones (MEASURED on an overlay) [w1-15
  §3.3]. Only the rail uses a positive zone.
- **Centring.** A non-zero size with a single anchor centres the surface on the other axis (MEASURED).
- **Output placement.** Every layer surface opens **on the focused output**, because there is no output
  selector [w1-15 §3.3].
  - The rail and the switcher must be on eDP-1. Core does an **output-pin dance**
    (`platform/sway/output-pin.ts`):
    1. record the focused output and container;
    2. `focus output eDP-1`;
    3. spawn;
    4. wait for `surface/ready`;
    5. restore with `[con_id=<id>] focus`.
  - Focus events caused by the dance are ignored until a `SEND_TICK` barrier with payload
    `gpuix-shell:pin:<nonce>` comes back [w1-10 tick barrier].
  - Launcher, toasts, OSD, centre, controls and power open wherever focus is (mako "focused output"
    parity [w1-18]; Vicinae `wantsToBeOnActiveScreen` [w1-35 §3.3]). This departs from DESIGN A-07 for
    those surfaces (§22).
  - The real fix is the patch sketched in [w1-15 §6]: `WindowOptions.displayName` → `display_id`.
- **Width changes.** A change of width, such as rail expand or collapse, needs a **new surface**:
  1. core writes `rail.json {mode}`;
  2. it runs `systemctl --user restart gpuix-shell-rail`;
  3. the new rail reads the mode.

  Sway re-tiles twice; that is accepted [DESIGN line 467]. Spawn-new-then-kill-old is **not** used for the
  rail, because two exclusive zones would stack side by side. For toasts it **is** used (§7.5).

### 5.2 How a process keeps exactly one window (`ui/host/mount.tsx`)

```tsx
export function mountSurface(spec: SurfaceSpec, app: React.ReactNode): void {
  if ((globalThis as any).__gpuixShellMounted) throw new Error("gpuix-shell: one window per process");
  (globalThis as any).__gpuixShellMounted = true;
  const payload = readSpawnPayload();               // GPUIX_SHELL_SPAWN file → unlink; or defaults for daemons
  const r = createRenderer();                       // never `render()` alone: it hard-codes an 8 ms poll
  r.init(windowOptions(spec, payload));             // table §5.1
  for (const face of staticFaces()) r.registerFont(face.bytes);   // §10.3, per renderer
  render(<SurfaceRoot spec={spec} payload={payload}>{app}</SurfaceRoot>, {
    renderer: r,                                    // injected: render() does no init and no loop
    keyboardFocusDim: false,                        // never dim [w1-15 §3.10]
    tabNavigation: spec.tabNavigation ?? false,     // Tab handled by hand at the root (DESIGN §7.2)
    onKeyDown: (e) => windowKey(spec, e),           // §5.3
  });
  startFrameLoop(r, { frameMs: spec.daemon ? 250 : 100, onTerminated: () => exitSurface(0, "window-closed") });
  process.on("uncaughtException", (e) => exitSurface(1, "uncaught", e));     // registered AFTER render()
  process.on("unhandledRejection", (e) => exitSurface(1, "unhandled", e));  // so GPUIX's red overlay
  process.on("SIGTERM", () => exitSurface(0, "sigterm"));                  // never sticks [w1-15 §3.1]
}
```

Facts this relies on [w1-15]:

- **The frame loop only detects termination.** On Linux GPUI renders on its own thread, so
  `startFrameLoop` only polls `tick()`. 250 ms is safe for daemons and adds no paint latency (MEASURED P5).
- **`render()` is a process singleton.** A second call remounts React on the same window and ignores the
  new options, and the process exits when the window closes.
- **Never `root.unmount()`.** The layer surface stays mapped after an unmount, so leaving a surface means
  exiting the process.
- **`exitSurface(code, reason)`:**
  1. logs one line;
  2. sends `surface/closed {reason}` to core, best effort, capped at 50 ms;
  3. calls `process.exit(code)`.

### 5.3 How a toggle process exits on Escape or on focus loss

**Escape and keys.** These go to the window-level `onKeyDown`, which receives every key [w1-15 P3/P7
MEASURED]:

- **Key names.** They are lowercase; modifiers are `{shift, ctrl, alt, cmd}`, and Super = `cmd`
  [w1-03 L8], [w1-15 §3.10].
- **Normalising.** `ui/host/keys.ts` turns an event into the GPX keystroke string (`"ctrl-shift-enter"`,
  the `Keystroke` type of `provider.ts`). Keymaps are data tables per surface (KEYS §4–§5).
- **What Escape does.** It closes the **top layer only** (DESIGN §7.2):
  1. an open action panel;
  2. then a pushed view (back);
  3. then a scope;
  4. at the root, `exitSurface(0, "escape")`.

**Second press of the bind.** Core finds the surface `open` and sends `close` to `<name>.sock`, and the
surface exits 0.

**Focus loss.** Under Sway a layer surface with exclusive keyboard keeps the keyboard until it unmaps, so
Vicinae's `close_on_focus_loss` "has no effect" there [w1-36 §3.8]. "Focus loss" is therefore detected
from outside, by core's `focus-guard.ts`. While an exclusive overlay is `open`, the guard sends `close`
when any of these happens:

| Trigger | Typical cause |
|---|---|
| a Sway `workspace` event with `change: "focus"` | the user pressed Mod+N, which Sway handles before the client |
| a `window` event with `change: "focus"` | the user clicked a window |
| an `output` focus change | |
| a request to open another exclusive overlay | opening one exclusive overlay closes the others |
| logind `PrepareForSleep(true)` | |

Exceptions:

- **Events from the shell's own actions.** The guard ignores focus events produced by an action of the
  overlay itself, such as the switcher's Enter → `workspace number N`. The surface first sends
  `surface/closing`, then invokes the action.
- **Events from the pin dance.** Focus events caused by the output-pin dance are ignored (tick barrier,
  §5.1).
- **In-window backstop.** As a second safeguard the surface root has `onBlur` on its outermost focus
  handle. It exits when GPUIX reports that the window lost keyboard focus (for example, another exclusive
  surface mapped), with a 100 ms debounce (INFERRED, smoke-tested).

**Act-and-close.** An action whose outcome sets `close: true` (the `ActionOutcome` of `provider.ts`) exits
after the echo has been handed to core. Core then shows that echo as a HUD for 1.5 s [w1-35 §3.3 HUD
1500 ms].

### 5.4 Fonts via installed faces

Summary; details in §10.3:

- **Families by name.** Every family resolves through fontconfig by its exact name: "Anthropic Sans",
  "Anthropic Serif", "AnthropicMono Nerd Font", "Anthropicons". These are installed system-wide by
  `fonts.packages` from the NAS-pinned derivations [w1-17 §3.6].
- **Set font and colour on every root.** Every surface root sets `fontFamily` **and** `color`: an unset
  colour renders black, and an unset family falls back to an unidentified face [w1-15 §3.8].
- **The unit needs fontconfig.** An empty fontconfig makes the `gpuix-ui` thread panic, so the unit
  environment must keep a working fontconfig [w1-15 §3.8].
- **Weights 500 and 600 need static faces.** The variable Anthropic Sans and Serif lose their weights in
  GPUIX: 300, 400 and 700 all render the same (MEASURED P4). The fix is static instances generated in the
  Nix store from the installed variable faces and registered per renderer. They are never in git.
- **Mono weights work as installed.**
- **Override the GPUIX theme fonts.** `GpuixTheme.fontSans` and `fontMono` default to DejaVu and must be
  overridden for `<input>`, `<code>`, `<markdown>` and `<diff>`.

### 5.5 React component conventions

1. **Function components and hooks only.** TS/JSX authoring in one language for shell and apps is a
   requirement that never died [w1-22 N1–N2]. The one class component is `ui/host/error-boundary.tsx`. It
   renders an error card, logs once, and makes a daemon surface exit 1 so systemd restarts it.
2. **One root per surface.** `<SurfaceRoot>` provides:
   - `ThemeProvider` (tokens);
   - `CoreClientProvider` (the `shell.sock` client);
   - `ScaleProvider` (zoom, files only);
   - `KeymapProvider`.

   The root `div` sets `display:'flex'`, `flexDirection:'column'`, `fontFamily`, `fontSize`, `color` and
   `backgroundColor` from tokens [w1-15 §5.2 E].
3. **No hex in components.** Components read `useTokens()`. A design-lint `bun test` greps `src/ui` and
   `src/surfaces` for `#[0-9a-f]{3,8}`, `shadow` and surface alpha below 1 (SCOPE S-008).
4. **GPUIX styling limits** [w1-03 L9–L11], [w1-15 §3.6]:
   - numeric px only;
   - `display` is `flex` or `grid` only, and a `div` is block unless `display:'flex'` is set;
   - no `zIndex` (tree order decides);
   - no `fontStyle` or `letterSpacing`, and uppercase is typed into the string;
   - exactly one template string per `<text>`, so strings are composed in JS first;
   - an `svg` always carries `style.color`;
   - one font family per text node, so a glyph and a word are two nodes (DESIGN A-03).
5. **Data hooks.**
   - `useTopic<T>(name)` is built on `useSyncExternalStore` over the core client; it starts from the spawn
     payload snapshot and is then live.
   - `useInvoke()` returns `(id, args) => Promise<InvokeResult>`.
   - No component fetches on mount for its first frame (G-8).
   - Local UI state is `useState`/`useReducer`. There is no global state library.
6. **Pure logic in `.ts`.** Logic lives in `.ts` files beside the `.tsx`, or in `src/core`, and is
   unit-tested. Components are not unit-tested: there is no test renderer on Linux
   (`hasTestGpuixRenderer() === false`, MEASURED in MUSIC.md). They are covered by `ui-tree` and the
   automation smokes (§15).
7. **Test ids.** Every interactive node gets a `testId` of the form `<surface>.<part>.<id>` (for example
   `launcher.row.apps:org.gnome.Nautilus`, `rail.slot.3`), following the music pass's `music.row.<kind>.<id>`
   [w1-15 §3.12].
8. **Inputs.** An `<input>` takes focus only with `autoFocus`. Enter is `onSubmit`; Up and Down arrive at
   `onKeyDown` [w1-15 §3.7].
9. **Motion.**
   - `motion.div` animates opacity and transform only.
   - Durations come from the tokens × `motion.scale`.
   - Overlays snap open with no enter animation (DESIGN §5, [w1-11 X1]).
   - The working pulse is a 600 ms stepped opacity change on the rail and switcher only (DESIGN A-06).
10. **`ui-tree` seam (SCOPE S-010).**
    - `ui/host/ui-tree.ts` answers `ui-tree` on `<name>.sock` with `renderer.getAutomationTree()`,
      which works on Linux [w1-15 §3.12].
    - `gpuix-shell <surface> ui-tree` prints it.
    - Smokes assert content through this tree and colours through grim pixels, because the tree carries
      no styles [w1-03 L14].

### 5.6 Virtual lists

`<virtual-list>` is the GPUIX element for long lists. It supports variable heights and windowing through
`estimatedItemHeight`, `itemCount` + `windowStart`, `overdraw` and `onVisibleRange`, and offers
`scrollToItem(id, index, offset?)` [w1-15 §3.7]. The kit wraps it once, in `ui/kit/VirtualRows.tsx`:

- **Flat items.** The sectioned model (`Section[]` of `provider.ts`) is flattened into items of kind
  `header` (30 px), `row` (launcher 44 / list 40 / dense 34 / rail 30) or `card` (56). Each kind has a
  **fixed height** from the tokens, so `estimatedItemHeight` is exact per kind and scroll positions are
  stable. Grid sections become row items with N cells.
- **Cursor and hover.** The cursor is an item index into the flat list. Arrow keys skip headers.
  `scrollToItem` runs on each cursor change, with `offset` keeping one row of context.
- **Hover.** The element has no hover style [w1-15 §3.7], so each row is wrapped in a `div` with
  `onMouseEnter` → `setCursor(i)`. Hover equals the cursor (DESIGN U-11).
- **Windowing.** Only `onVisibleRange` ± 8 items are rendered. Art and thumbnails load lazily for the
  visible range (`Art.load(bucket, signal)`, aborted when an item leaves).
- **When to use it.**
  - Every list that can exceed about 100 rows uses `VirtualRows`: launcher results, clipboard, emoji,
    files, notification history, music [w1-30 §4.2].
  - Short fixed lists stay plain `div`s: the switcher's 10 rows, power, the controls domains.

---

## 6. Data flows

### 6.1 Sway events → store → rail

```
$SWAYSOCK ── event socket ──► SUBSCRIBE ["workspace","window","output","mode","binding","shutdown","tick"]
   (subscribe BEFORE the first query [w1-10])
        │ every event: mark dirty; `window` events with change "title" are dropped unless the
        │ focused-window line is enabled (S-042) [w1-26 §3]
        ▼
   coalesce 40 ms [w1-03 timings] ──► ONE batch on the command socket: GET_TREE + GET_WORKSPACES + GET_OUTPUTS
        ▼
   core/sway-ipc/derive.ts (pure): {outputs, focusedOutput, workspaces, focusedWs, urgent[],
        fullscreenByOutput, marks → slot identities, windows[] (lazy: only when a launcher/switcher asks)}
        ▼
   core/herdr/slots.ts (pure): join SwayModel + HerdrModel → Slot[1..10]
        {n, swayName, focused, urgent, visibleOnOutput, herdr:{workspaceId,label,name,status,agents,
         age,madeInSlot?}, lastVisited}   (marks regexes [w1-16 §5.2]; status rank blocked 0 … none 5 [w1-23];
         "made in slot N" chip only when the label's slot differs [w1-25 §3])
        ▼
   hub.ts: rev++ (generation counter [w1-12]); diff per topic (stable stringify); publish changed topics
        ▼  NDJSON `state` notification, full snapshot per topic [w1-29 §4 v20]
   rail process: useTopic("slots") → React re-render (GPUI paints on its own thread; no frame-loop delay)
```

Rules:

- **Two connections.** Commands and events use separate sockets [w1-10], [w1-26]. Commands are
  serialised on one connection, with a pending queue.
- **Verify, never assume** ("a command is never assumed to have worked" [w1-10]). `sway.focus-slot n`
  sends `workspace number n`, then waits up to 500 ms for the matching `workspace` focus event or
  re-reads `GET_WORKSPACES`. The outcome is `confirmed`, `failed` or `unknown`.
- **Quoting.** Workspace names go through `quote.ts`. It rejects `" \ $ ; ,`, control characters, DEL, a
  leading `--`, and the reserved words `number next prev current back_and_forth next_on_output
  prev_on_output` [w1-08 platform.ts].
- **Reconnect and resync.**
  - Reconnect with a backoff from 250 ms to 10 s [w1-03].
  - Every connect does a full resync: re-subscribe, then re-query.
  - A `workspace` event with `change: "reload"` (a Sway reload) also forces a full resync [w1-10].
  - The `shutdown` event makes core exit 0, since the session is ending.
- **Fullscreen.** When the focused container on the rail's output becomes fullscreen, the topic carries
  `fullscreenByOutput[eDP-1]=true`. The rail cannot unmap, so core **stops** the rail unit and restarts it
  on unfullscreen (S-038, P1, INFERRED mechanism).

### 6.2 herdr snapshot poll

**Transport** (`platform/herdr/transport.ts`, config `herdr.transport`, default `auto`):

| Mode | When | Read | Wake-ups |
|---|---|---|---|
| `local` | `HERDR_SWAY_LOCAL=1` or `~/.config/herdr/herdr.sock` exists (the strix) | `{"id","method":"session.snapshot","params":{}}\n`, one request per connection (~5 ms MEASURED) | `events.subscribe` with lifecycle events only, used as a wake-up and never as state [w1-16 §5.3] |
| `ssh-forward` | the Zenbook (`auto` tries this first) | the same, over `$XDG_RUNTIME_DIR/gpuix-shell/herdr.sock`. Core owns `ssh -N -o BatchMode=yes -o ExitOnForwardFailure=yes -L <that>:/home/tom/.config/herdr/herdr.sock strix` with a backoff from 250 ms to 10 s. | the same subscribe as `local` |
| `ssh-exec` | fallback when the forward fails 3 times | `ssh -n -o BatchMode=yes -o ConnectTimeout=3 -o ControlMaster=auto -o ControlPath=$XDG_RUNTIME_DIR/gpuix-shell/ssh-%C -o ControlPersist=60 strix 'herdr api snapshot'`, 6 s timeout (the picker's path [w1-16 §5.3]) | none (floor poll only) |

The forward is INFERRED and unmeasured: OpenSSH supports a Unix-socket `-L`, but nobody has run it here
[w1-16 §5.3]. The `ControlMaster` option is INFERRED: the fleet ssh config has none
(`home/dot_config/kitty/ssh.conf:32`).

**Poll loop** (from herdr-attention and herdr-bar [w1-16 §5.3], [w1-23]):

- **Wake-ups.** Each of these triggers a snapshot read, coalesced to **300 ms**, with a single read in
  flight:
  - a herdr event;
  - a Sway `workspace` or `window` event;
  - `surface/ready` of the launcher or switcher (their pickers refresh on open).
- **Floor poll every 3 s** when no event stream is up.
- **Byte comparison.** A read whose bytes are identical to the previous one is dropped before any
  parsing or publishing (herdr-bar [w1-23]).
- **Time budget.** 6 s per read. After 2 consecutive failures the state becomes
  `herdr.status = "unavailable"` with `since`.
  - Slots then show Sway-only names and the ○ glyph meaning unknown, never idle, plus a stale age
    [w1-11 run-state table].
  - `events_lost` means: re-subscribe, then take a fresh snapshot. Snapshots and events are never
    replayed onto each other [w1-16 §5.3].
- **Attention** (`core/herdr/attention.ts`, port of `herdr-attention:44-115` [w1-16 §5.4]):
  - Only `blocked` raises attention. A new episode starts on a status change into `blocked`, or on a
    `state_change_seq` advance while blocked.
  - **Notification.** Each new episode sends **one** notification through the shell's own D-Bus server:
    - D-Bus `Notify`, app `herdr`, urgency normal, `expire 15000`;
    - `replaces_id` per slot;
    - actions `default=Go` and `dismiss=Dismiss`.
  - **Go** maps to `sway.focus-slot n`, which never steals focus on its own (G-7).
  - **Sway urgency.** `[con_id=<projector>] urgent enable` on the slot's projector window is optional
    (`herdr.attention.urgent`, default true; INFERRED replacement for the unmerged branch).
  - **First snapshot after an outage.** It sets a baseline and raises nothing unless a
    `state_change_seq` advanced.
  - **herdr's own toasts stay off** (`[ui.toast] delivery`) [w1-16 §5.4].

### 6.3 D-Bus servers and clients

One session-bus connection and one system-bus connection per process (dbus-next 0.10.2 `sessionBus()` /
`systemBus()`). On disconnect: reconnect with a backoff from 250 ms to 10 s, then **re-read everything**.
A `NameOwnerChanged` for a watched service makes core re-read that service [w1-23 service lifecycle].

| Role | Process | Bus | Interface and calls | Phase |
|---|---|---|---|---|
| **server** `org.freedesktop.Notifications` | notifications daemon | session | §7 | P0 |
| **server** MPRIS `org.mpris.MediaPlayer2.gpuix_music` | music daemon | session | ASSUMPTIONS music (04) | P1 |
| **server** BlueZ `org.bluez.Agent1` at `/org/gpuix_shell/agent` | core | system | `RegisterAgent(path,"KeyboardDisplay")` + `RequestDefaultAgent` at start. `RequestPasskey`, `RequestConfirmation`, `RequestPinCode`, `DisplayPasskey` and `AuthorizeService` open the controls pairing sheet (SECRET, a local form); after 30 s without an answer, reply `org.bluez.Error.Rejected`. Never restart bluetoothd [w1-26], [w1-20 pairing]. | P1 |
| **server** NM SecretAgent | — | system | LATER. v1 sends credentials in an `AddAndActivateConnection` settings dict over D-Bus (never on an `nmcli` argv) [w1-29 G6], [w1-23 NM] | P2 |
| **server** polkit `AuthenticationAgent` | controls host (or core) | system | needs `polkit-agent-helper-1` for PAM; a Tom MUST, but P2 tonight [w1-29 #216, w1-30 G2] | P2 |
| **server** SNI watcher + dbusmenu host | core | session | the `tray ` provider; P2 [w1-35 §3.1 core:search-tray] | P2 |
| client UPower `/org/freedesktop/UPower/devices/DisplayDevice` | core | system | `GetAll` + `PropertiesChanged`; fallback to `/sys/class/power_supply` [w1-26] | P0 |
| client logind | core | system | `PrepareForSleep` (resync on resume; close overlays), `PowerOff(true)`, `Reboot(true)`, `Session.Terminate` (logout fallback), `Suspend` gated by config [w1-26], [w1-07] | P0 |
| client NetworkManager | core | system | device state, active connection, wireless APs on demand. When controls opens: `RequestScan` + `LastScan`, rescan every 15 s while open [w1-20], [w1-23] | P0 |
| client BlueZ (ObjectManager, Adapter1, Device1, Battery1) | core | system | `InterfacesAdded`/`InterfacesRemoved` + `PropertiesChanged`; discovery retries 900 ms × 8, power watchdog 4 s, trust before connect [w1-20] | P1 |
| client MPRIS `org.mpris.MediaPlayer2.*` | core | session | `NameOwnerChanged` filter; Player properties; position extrapolated from `positionAt` epoch ms (music assumption) | P0 |
| client `net.hadess.PowerProfiles` | core | system | LATER [w1-29 #54] | P2 |

Non-D-Bus status readers in core:

- **PipeWire:** a `pw-dump --monitor --no-colors` child gives the default sink and its volume and mute,
  plus the privacy and recording dots (capture streams, screencast nodes). Volume is shown as
  `wpctl`'s cubic value [w1-26 §6]. P0; the reader is INFERRED.
- **Tailscale:** the `vpn-status` script's JSON if it exists, else `tailscale status --json`, every 5 s
  [w1-29 §3.5 TailscaleProducer]. This is display refresh, not scheduled work.
- **Pomodoro and recording:** state files from the existing scripts. They are read when the scripts
  signal the shell (`gpuix-shell status set <key> <text>`, the cmux keyed-status model [w1-29 §3.3 P1]),
  never by polling.

### 6.4 Clipboard watcher

Core owns two watcher children. Each is restarted with a backoff from 250 ms to 10 s if it dies:

```
wl-paste --type text      --watch gpuix-shell clipboard ingest --type text
wl-paste --type image/png --watch gpuix-shell clipboard ingest --type image/png
```

Each copy runs one CLI process (~80 ms). The data arrives on its stdin, and `CLIPBOARD_STATE` is set by
wl-clipboard [w1-26 §5]:

1. **Skip.** `CLIPBOARD_STATE` of `nil`, `clear` or `sensitive` (the
   `x-kde-passwordManagerHint` case) means: skip, and exit 0 (Tom's `ignorePasswords` [w1-35 §1.1]).
2. **Write the blob.** The bytes go to `$XDG_STATE_HOME/gpuix-shell/clipboard/blobs/<sha256>`: written to a
   temporary file at mode 0600, then renamed. The rename is atomic and makes the file content-addressed,
   which is the dedupe.
3. **Report metadata only.** `clipboard/ingest {sha, mime, size, kind, preview≤200 chars}` goes to core;
   blobs never cross the socket.
4. **Store.** Core inserts the row into `clipboard.sqlite` (bun:sqlite, WAL), runs the kind and policy
   rules, and publishes the `clipboard` topic (top 50 rows).

Policy (pure `core/clipboard/policy.ts`, from Tom's Vicinae settings [w1-35 §1.1], [w1-18]):

- **Eviction** after 24 h (`evictionThreshold 86400`), except pinned and tagged entries.
- **Kinds** text, image, link, file, from the mime type; a `text/uri-list` of local paths is a file.
- **Search** over text uses FTS5; if bun's SQLite lacks FTS5, it falls back to `LIKE` (UNVERIFIED).
- **Ownership.** No cliphist watcher runs alongside (`startup.conf:4`).
- **Copy back.** Copying an entry back runs `wl-copy` with the bytes on stdin, never on argv. Paste is
  copy plus HUD, because the input server is off [w1-35 §6.6].

### 6.5 State persistence under `$XDG_STATE_HOME/gpuix-shell`

Write discipline:

- Every write is atomic: a temporary file, `fsync`, then `rename`.
- Files are mode 0600, directories 0700 (the units also run with `UMask=0077`).
- Every JSON file has `"schemaVersion"`.
- A file that fails to parse is moved aside to `<name>.bad-<epoch>`; the process starts empty and logs
  one warning (INFERRED).

| Path | Owner | Content | Retention |
|---|---|---|---|
| `rail.json` | core | `{schemaVersion, mode:"collapsed"\|"expanded", hidden:false, lastVisited:{[slot]:epochMs}}` | — |
| `frecency.sqlite` | core | `visits(item_id, count, last_at)`. Rank = Vicinae `min(25, 5·ln(1+0.1·visits) + 10·e^(−days/30))/25` [w1-35 §3.1] | rows unused for 180 days pruned at start (INFERRED) |
| `recent.json` | core | herdr MRU, cap 120, atomic [w1-23 herdr-bar] | cap |
| `pins.json` | core | launcher pins and favourites added at runtime (Nix favourites come from config) | — |
| `launcher/state.json` | core | the last view per `--view`, `storeValue` dropdowns, per-command preferences overrides | — |
| `clipboard/clipboard.sqlite`, `clipboard/blobs/` | core | entries + blobs | 24 h except pins and tags |
| `notifications/history.jsonl` | notifications | one closed notification per line (no `transient`); images by hash | 500 entries or 30 days (INFERRED) |
| `notifications/images/<sha>.png` | notifications | `image-data` converted to PNG with `node:zlib` [w1-26] | with history |
| `notifications/state.json` | notifications | `{dnd, privacy, restoreStack:[≤5]}` (`makoctl restore` depth 5 [w1-18]) | — |
| `files/{state.json,undo.json,jobs/}` | files | Pinax state; jobs from `files-job` [w1-20] | Undo 60 s [w1-20] |
| `zoom.json` | files, ask | per-surface UI scale, 0.8–1.6 in 0.1 steps [w1-04/05]; Tom asked for Ctrl+=/−/0 with reflow [w1-01/02] | — |
| `extensions/<id>/storage.json` | launcher | Vicinae `LocalStorage` per extension [w1-36 §4.5] | — |
| `ask/`, `panels/*.openui` | ask | sessions, pinned panels [w1-24] | — |
| `music/*` | music | `state.json`, `queue.json`, `now.json` (ASSUMPTIONS music) | — |

Other locations:

- `$XDG_CACHE_HOME/gpuix-shell/` holds rebuildable data: `apps-index.json`, `icons/` (resolved icon PNGs),
  `thumbnails/`, `music/{art,library.json}`.
- `$XDG_CONFIG_HOME/gpuix-shell/` holds only Nix-rendered read-only config:
  - `config.json`, validated by `core/config/schema.ts`;
  - `model.json`, the runtime file for ask [w1-24].
- A bad config keeps the last good copy (`$XDG_STATE_HOME/gpuix-shell/config.last-good.json`) and raises
  one notification [w1-23 "bad config keeps last good"].

---
## 7. Notification daemon

### 7.1 Bus-name ownership

```ts
// daemons/notifications/server.ts (shape from [w1-26 §4])
const bus = dbus.sessionBus();
const reply = await bus.requestName("org.freedesktop.Notifications", DBUS_NAME_FLAG_DO_NOT_QUEUE);
if (reply !== RequestNameReply.PRIMARY_OWNER) {
  const owner = await nameOwnerInfo(bus, "org.freedesktop.Notifications"); // unique name → pid → /proc/<pid>/comm
  log.error("bus-name-held", { owner: owner.comm, pid: owner.pid });     // e.g. comm=mako
  process.exit(69);                    // unit has RestartPreventExitStatus=69 → no restart loop
}
bus.export("/org/freedesktop/Notifications", new NotificationsInterface(store));
```

The pieces around it:

- **The unit.** It is `Type=dbus` with `BusName=org.freedesktop.Notifications`, so systemd considers it
  started once the name is acquired [w1-13 HM precedent], [w1-21 §d].
- **D-Bus activation file** (optional, INFERRED). `$out/share/dbus-1/services/org.freedesktop.Notifications.service`
  contains `Name=…`, `Exec=/bin/false` and `SystemdService=gpuix-shell-notifications.service`. A
  `notify-send` that arrives before the session target is up then starts our unit and never mako's
  [w1-21 gap list].
- **Never both.** This is enforced in three places:
  1. the HM assertion (§13);
  2. the flake asserts (§14.4);
  3. the exit 69 above.
- **Mako must not be installable alongside.** When `programs.gpuixShell.enable` is set, the mako package
  must not be in the profile, because its own D-Bus service file would offer activation.

### 7.2 Methods and signals (freedesktop spec 1.2)

| Member | Signature | Behaviour |
|---|---|---|
| `GetCapabilities` | `→ as` | `["actions","body","body-markup","icon-static","persistence"]` [w1-26 §4] |
| `GetServerInformation` | `→ ssss` | `["gpuix-shell","Tom","0.1.0","1.2"]` [w1-26 §4] |
| `Notify` | `susssasa{sv}i → u` | §7.3 |
| `CloseNotification` | `u →` | closes with reason 3; an unknown id is a no-op |
| signal `NotificationClosed` | `uu` | reason 1 expired, 2 dismissed by the user, 3 closed by call, 4 undefined |
| signal `ActionInvoked` | `us` | action key; a body click is `default` [w1-18] |
| signal `ActivationToken` | `us` | sent before `ActionInvoked` **only** when an xdg-activation token is available. GPUIX exposes none, so v1 omits it (INFERRED; `notify-send --wait` does not need it) |

### 7.3 Notify: what happens to one call

1. **Limits.** Out-of-range fields are clamped and logged once per app:
   - summary 1 KiB, body 8 KiB, app name 256 B;
   - at most 32 action entries, each key at most 256 B [w1-03].
2. **Flood guard** (`core/notifications/flood.ts`):
   - A **hard cap of 20 per second** applies across all apps [w1-27]. Over the cap, a call gets an id back but
     is stored silently, with no toast.
   - **Identical repeats are coalesced within 1 s.** A call with the same app, summary and body within
     1 s of the previous one bumps a counter on the existing card instead of creating a new one
     [w1-29 #82, MA B6].
3. **OSD routing** (`core/notifications/osd-route.ts`). A call goes to the **OSD slot** instead of the
   toast stack when any of these hold:
   - `app_name == "osd"` (the dotfiles `osd` script);
   - the hint `x-canonical-private-synchronous` is present;
   - a config rule says `route-to-osd` (S-108).

   For OSD calls:
   - **One stable id.** The daemon allocates one id for the OSD slot on first use and returns it for
     **every** OSD call, whatever `replaces_id` was sent. That keeps
     `osd`'s `-r $(cat $XDG_RUNTIME_DIR/osd-notify.id)` working across daemon restarts [w1-18 OSD
     contract].
   - **Mapping.** The `int:value` hint becomes the bar value. Summary and icon map to the kind
     (volume, brightness, mic, caps, touchpad, media, audio-route, hud).
   - **Not counted.** OSD calls are never stored in history or counted as unread, and DND does not
     silence them (INFERRED).
   - **Suppression.** They are hidden while the launcher or controls is open (#129). The daemon learns
     that from core's `overlays` topic.
4. **Rules** (`core/notifications/rules.ts`). The first match wins over
   `{match:{app?, summary?: regex, body?: regex, urgency?}, action: drop | dnd-exempt | urgency | timeout | silent | route-to-osd}`
   [w1-29 #72, MA A4].
5. **Store** (`core/notifications/store.ts`, semantics of the prior `notifications.ts` [w1-13] and mako
   [w1-18]):
   - **Ids** are u32, wrap around and skip 0.
   - **`replaces_id` matches a live notification:** the content is replaced in place and the card moves
     to the newest position.
   - **`replaces_id` is stale or unknown:** a **new** id is allocated, as mako does [w1-18].
   - **Capacity:** at most 100 active.
   - **Hints:**
     - `transient` means never written to history;
     - `resident` keeps the card after an action;
     - `urgency` is a byte 0, 1 or 2.
6. **Timeout.** `-1` → 5000 ms. `0` → never expires. An explicit timeout is honoured, even on critical. A
   critical notification with `-1` never expires [w1-18].
7. **Images.**
   - `image-data`, `image_data` and `icon_data` (`iiibiiay`) are decoded at once into RGBA and then a
     PNG in the image cache. They are read **at Notify time**, because the client may disappear
     [w1-23].
   - `image-path` and `image_path`: a file path is used directly; a name goes through the icon theme
     lookup and the result is cached.
8. **Markup.**
   - `core/dbus/markup.ts` keeps entities and `b`, `i`, `u` and `a href`, and strips everything else.
   - `<i>` renders upright, because GPUIX has no italic [w1-18], [w1-15 §3.6].
   - Links open through `xdg-open` after the scheme is checked (http and https only).
9. **DND.** Under DND, toasts are not shown except for critical notifications and rules marked
   `dnd-exempt`. Everything is still stored. The unread count grows.
10. **Publish.** The daemon publishes the `notifications` topic to core: unread count, DND, the newest 50.
    Then it updates the toast child (§7.5).

### 7.4 mako feature parity and `notify-send` compatibility

The conformance cases come from [w1-18]. Each one is a D-Bus test under `dbus-run-session` plus a toast
smoke (§15):

| # | Case | Expected |
|---|---|---|
| 1 | `notify-send "a" "b"` | toast with summary and body; id returned; expires after 5000 ms with reason 1 |
| 2 | `notify-send -p` then `notify-send -r <id>` | the same card updates and moves to the newest position; the same id is returned |
| 3 | `notify-send -r 999999` (stale id) | a new notification with a new id |
| 4 | `notify-send -u critical` | red border (`status.danger.line`); never expires unless `-t` is given |
| 5 | `notify-send -t 0` | never expires; `-t 2000` honoured even when critical |
| 6 | `notify-send --action=default=Open --wait` and a body click | `ActionInvoked(id,"default")` then `NotificationClosed(id,2)`; `--wait` returns `default` |
| 7 | right-click or touch on a card | dismissed, reason 2, no action |
| 8 | `-h int:value:42` | a 3 px bar in `selection.bg` (DESIGN A-18) |
| 9 | `-h string:image-path:/…png` and `image-data` | 48 px image; cached for history |
| 10 | 6 notifications at once | 4 cards, newest on top, plus a "(2 more)" row (DESIGN A-36; max-visible 4 [w1-18]) |
| 11 | `osd` script (volume key) | OSD card, no toast, no history, stable id |
| 12 | `notify-send -e` (transient) | toast shown; never in `history` |
| 13 | 50 identical calls in 1 s | one card with a ×N counter; at most 20 accepted per second |
| 14 | `gpuix-shell notifications dismiss` / `--all` / `restore` / `invoke <id>` / `list --json` / `history --json` | makoctl verb parity (KEYS §7.2) |

### 7.5 Toast and OSD windows (children of the notifications daemon)

The toast window is a child process, `gpuix-shell surface toasts`:

- **Payload.** Its spawn payload is the visible set: at most 4 cards plus a "(N more)" count, each card
  with a precomputed height.
- **Card height.** There is no resize, and a surface cannot be measured before it exists, so card height
  comes from the pure function `core/notifications/toast-layout.ts`:
  - range 72–140 px (DESIGN A-17): title on 1 line, body on 0–2 lines, actions row 0 or 28, image 48;
  - lines are estimated from character counts against the measured advance of Anthropic Sans
    (0.525 em at 24 px [w1-15 §3.8]) on a 300 px text column, rounding up;
  - the card itself uses `lineClamp` and ellipsis, so text never overflows the estimate.

  INFERRED estimator; a golden test pins it.
- **When the set changes** (a new card, a card expiring or dismissed):
  1. the daemon spawns a new child with the new set;
  2. it waits for `surface/ready` (spawn ~150 ms, respawn ~30 ms [w1-03 timings]);
  3. then it SIGTERMs the old child.

  Only the new card fades in; the other cards are already on screen (DESIGN A-16, [w1-11 X1]). With an
  empty set, the child is simply killed.
- **Expiry and hover.** Timers run in the daemon, never in the child. Hovering a card pauses its countdown:
  the child sends `toast/hover {id, on}` [w1-29 MA B6].
- **Pointer.** Left click invokes `default` (or opens the centre when there is no default). Right click
  dismisses. Action buttons (at most 2 drawn, 28 px) invoke their key [w1-18], DESIGN.
- **Output.** The child opens on the **focused output** (mako parity). It is not pinned.

The OSD window is a child process, `gpuix-shell surface osd`:

- It is spawned on the first OSD value. Later values go to `osd.sock` as `osd/update {kind, value, label}`
  without a respawn.
- It exits 1500 ms after the last value (the `osd` script's own timeout, DESIGN A-19).
- **Brightness and volume keys stay keypress → Sway → script**; the OSD only displays [w1-36 T10].

The notification centre (`center`) is an ordinary toggled overlay, spawned by core and not by the
notifications daemon. It reads the `notifications` topic plus `notifications/history` and acts through
`notifications/*` verbs (KEYS §5.2):

- groups per app;
- Current and History tabs;
- letter hints;
- DND toggle.

---

## 8. Launcher provider interface

The contract is the file `PKG/src/launcher/provider.ts` (exists, 249 lines, frozen by the music pass).
In short:

```ts
interface LauncherProvider<D> extends ListSource<D> {
  id: string; title: string; icon: string; keywords: string[];          // name + root matching
  prime(ctx: ProviderContext): Promise<void>;     // once at launcher start; ≤ 50 ms from disk/daemon/spawn payload;
                                                  // revalidate in background then ctx.invalidate("data")
  search(query: string, signal: AbortSignal): Section[] | Promise<Section[]> | AsyncIterable<Section[]>;
                                                  // every yield is a COMPLETE snapshot; signal aborts on next keystroke
  actions(row: Row<D>): Action<D>[];              // [0] = Enter, [1] = Ctrl+Enter unless shortcuts say otherwise
  detail?(row, signal): Promise<DetailPane | null>;
  rootLimit?: number;                             // rows in the mixed root list (default 3)
  open?(route: Route): LauncherView<D> | null;    // pushed views (album, queue, wifi network …)
  rowState?(row): RowState | undefined;           // live decoration without re-searching
  commands?: Command[];                           // no-view commands → also registry entries (§9)
  strip?(props): ReactNode | null;                // persistent strip slot (mini-player)
  dispose?(): void;
}
// ProviderContext: cacheDir, stateDir, runtimeDir, invalidate("state"|"data"), log(event, fields)
// ActionContext adds push/pop/close/echo(text, undo)/copy/openExternal/route
```

How the host (`src/surfaces/launcher/`) uses it:

- **Registration.** Providers are listed statically in `surfaces/launcher/providers/index.ts`. A provider
  is turned off by `providers.<id>.enabled = false` in config; there is no enable UI ("no hierarchy"
  [w1-29 #200]).
- **Prefixes** route to one provider's view: `=` calc, `>` commands and shell, `:` files, `@` windows,
  `#` workspaces, `w ` wifi, `bt ` bluetooth, `em ` emoji, `m ` music, `h ` herdr, `t ` theme,
  `n ` notifications, `tabs `, `tray `. Single-character sigils act at column 0; word prefixes need a
  space (KEYS §4.1). `--view <id>` opens a view without typing.
- **Root list.**
  - **With an empty query:** favourites, then frecency suggestions, then the context section
    (focused-app actions, current-slot actions, the newest notification's actions; S-088). Tom's
    "sway has a contextual launcher" [w1-06 R12].
  - **With a query:**
    - Every provider's `search()` runs concurrently. Each gets at most `rootLimit` rows, and the rows
      are merged.
    - **Score** = fuzzy score + 6 × frecency (the Vicinae formula), with `MIN_QUALITY 60`. Rows whose
      alias matches as a prefix sort first [w1-35 §3.1].
    - **The fuzzy scorer** uses the herdr-bar constants: match 16, boundary 16, camel 12,
      consecutive 16, first ×2, gap start −3, gap extension −1 [w1-23].
    - **Ties** break on `(−score, mru, status, length)`.
  - **Then** files (only if `launcher.filesInRoot`), then fallbacks ("Use '<query>' with …").
- **Async refresh.**
  - `search()` may return an `AsyncIterable` of snapshots: a local-first partial, then a merged final.
  - The host keeps the **last complete snapshot per provider** and replaces it whole on each yield. It
    never merges rows across yields.
  - On every keystroke it aborts `signal`, and anything yielded after the abort is ignored.
  - Background revalidation calls `ctx.invalidate("data")`, which re-runs the current query.
    `invalidate("state")` repaints the visible rows only (`rowState`, `strip`).
  - Section `status` (`loading`, `partial`, `stale`, `empty`, `failed`) is drawn in the section header
    and never as a modal.
- **Time budgets.**
  - Before first paint: `prime()` must be satisfied from the spawn payload or from disk within 50 ms.
  - Network-backed providers (music, wifi scan) start with cached sections and refresh later. Music:
    60 ms debounce, then server `search3` (ASSUMPTIONS music).
- **Actions.**
  - Ctrl+K opens the action panel; Ctrl+B is the Vicinae alias (KEYS §4.2). It is drawn as an
    `anchored` popover **inside** the launcher surface (GPUIX cannot pop outside the window [w1-29 G7]).
  - Every action's `run()` returns an `ActionOutcome`. The `echo` shows in the footer for 6 s with
    "Undo Ctrl+Z" when `undo` is present (U-rule "an echo after every act").
  - A `consequence` of `writes-server` or `opens-external` is shown in the panel before the action runs
    (U-09).
- **Providers built on core data.** These read core topics or the spawn payload, never their own
  daemons: apps (core apps index), commands (the registry), clipboard, windows and workspaces (Sway
  model), herdr (slots), notifications, tabs (the Chrome tab list from the native host).
- **Providers that call platform code directly from the launcher process:** calc (pure), files (an `fd`
  subprocess with a 30 s timeout and a 3-char minimum [w1-36 §4.1]), emoji (`data/glyphs.json`), theme,
  shell `>` (the runner, streaming output into a detail view).
- **Vicinae ids are accepted as aliases**: `clipboard:history`, `applications:herdr-picker`,
  `browser-extension:browse-tabs`, `media:now-playing`, `core:search-tray`, `files:search`,
  `wm:switch-windows` → views (KEYS §7.7), [w1-36 §4.2 decision 4].
- **Extension host.** Hosting Vicinae and Raycast extensions as Bun Workers with the reconciler port
  [w1-36 §4.2–§4.8] is **P2**. It plugs in as one more `LauncherProvider` whose views come from the
  intrinsic tree; it is not part of v1.

---

## 9. Command registry

### 9.1 One registry, three drivers

`src/core/registry/` is pure data plus routing. It is the single catalogue behind CLI verbs, launcher
command rows, Sway binds (through the CLI), rail clicks, D-Bus actions and `registry ls`
[w1-04 C4], [w1-12 C2.1], [w1-19 §3D IPC crosswalk], [w1-29 §4 v6].

```ts
export type VerbClass = "READ" | "WRITE" | "ACTION" | "SECRET";
export type Owner = "core" | "notifications" | "music" | `surface:${SurfaceName}` | "exec";
export interface CommandSpec<A = unknown> {
  id: string;                         // "<domain>.<verb>[-<noun>]" (U-10), e.g. "launcher.toggle", "sway.focus-slot"
  title: string;                      // sentence case, for the launcher root ("Toggle launcher")
  subtitle?: string; keywords?: string[]; icon?: string;
  class: VerbClass;                   // SECRET specs are never callable over shell.sock (registry refuses)
  owner: Owner;                       // which process executes it
  args: z.ZodType<A>;                 // validated at every entry point
  cli: { path: string[]; positional?: (keyof A)[]; aliases?: string[][] };   // ["launcher","toggle"]
  launcher?: { root: boolean; when?: "always" | "context" };                 // shows as a root row
  replaySafe: boolean;                // reboot/poweroff/logout/suspend: false [w1-29 §5 replaySafe]
  confirm?: "hold" | "yes-flag" | "two-step";
  hud?: boolean;                      // echo as OSD hud when source === "bind" and no visible effect
}
export interface InvokeRequest { id: string; args: unknown; source: "cli"|"bind"|"launcher"|"rail"|"dbus"|"script"|"test"|"surface"; tty: boolean }
export interface InvokeResult  { outcome: "confirmed"|"failed"|"unknown"; echo?: string; data?: unknown;
                                 undo?: { id: string; args: unknown }; error?: { kind: string; message: string; fix?: string } }
```

How the pieces fit:

- **Specs and handlers are separate.**
  - Specs are pure tables in `core/registry/specs/<domain>.ts`, so core, the CLI and the launcher can
    all import the full catalogue without importing React or I/O.
  - Handlers live with their owner: `daemons/core/handlers.ts`, `daemons/notifications/handlers.ts`,
    `music/service`, `surfaces/<x>/commands.ts`.
  - The router maps `owner` to a transport:
    - **in-process** for `core`;
    - **forwarding** to `notifications.sock` or `music/ctl.sock`;
    - **the supervisor** for `surface:*` (`toggle`, `open`, `close`, `update` with args);
    - **the runner** for `exec`.
- **Method naming.** id `a.b-c` ↔ JSON-RPC method `a/b-c`, a one-to-one mapping in `ids.ts`.
- **Drivers.**
  - CLI: argv → `grammar.ts` → id + args → `core/invoke`.
  - Launcher: root rows come from `registry.list({launcher:true})` plus provider `commands`; activation
    sends `core/invoke` with `source:"launcher"`.
  - Binds: Sway runs `gpuix-shell … --source bind [--hud]`.
  - Rail: a click handler calls `useInvoke()(id, args)` with `source:"rail"`.
  - D-Bus: notification actions such as herdr's **Go** call `sway.focus-slot`.
- **Gates.** ACTION with `confirm:"yes-flag"` refuses (exit 1) without `args.yes` when
  `source ∈ {cli, script}` and `tty === false`. ACTION with `confirm:"hold"` (power) is registered with
  `launcher.root:false` and no bind; from the CLI it needs `--yes`, and on screen the hold is the
  confirmation (KEYS §7.6). SECRET specs exist only to document local-form flows; the router refuses
  them (exit 1).
- **The exec runner** (`platform/exec/runner.ts`, `cubs msg` semantics [w1-29 §5 S06:376]):
  - argv only, never `sh -c` for registry commands;
  - a non-zero exit is rejected;
  - 30 s timeout, then SIGTERM, then SIGKILL after a 5 s grace;
  - output capped at 10 MB;
  - apps start in `systemd-run --user --scope --collect --slice=app.slice -- gio launch <desktop-file>`
    so they never become children of a surface [w1-26 §7].
- **Static checks** (`registry.test.ts`):
  - ids are unique;
  - every `cli.path` is unique;
  - every KEYS §7 verb resolves;
  - every bind line generated for §12 parses to a registered id;
  - no SECRET spec has a CLI path.

### 9.2 Initial catalogue (P0 unless noted; full verb list in KEYS §7)

| Domain | Ids (owner) |
|---|---|
| core | `core.ping`, `core.version`, `core.status`, `core.snapshot`, `core.listen`, `core.reload`, `core.registry-ls`, `core.doctor`, `core.validate` (core) |
| surfaces | `launcher.{toggle,open,close,state}`, `switcher.{toggle,open,close}`, `notifications.{toggle,open,close}` (the centre), `controls.{toggle,open,close}`, `power.{toggle,open,close}`, `cheatsheet.{toggle,lint}`, `files.{open,pick}` (P1), `ask.{toggle,close}` (P2), `gallery.open` (should) (all `surface:*`) |
| rail | `rail.{toggle,show,hide,expand,collapse,reload,status}` (core: systemd start/stop/restart plus `rail.json`) |
| sway | `sway.focus-slot {n}`, `sway.focus-window {conId}`, `sway.pin-output`/`restore-focus` (internal) (core) |
| herdr (exec) | `herdr.new` (`herdr-chord new`), `herdr.restore`, `herdr.rename`, `herdr.close` (`sway-workspace …`) (exec, WRITE; close is ACTION + two-step) |
| notifications | `notifications.{dismiss,restore,invoke,list,history,count,clear-history,dnd,reload}`, `toast`, `notify`, `osd`, `osd.show` (notifications) |
| clipboard | `clipboard.{ingest,list,copy,pin,text,clear}` (core) |
| theme | `theme.set {name}` (exec `~/.local/bin/theme`), `theme.reload` (core) |
| dmenu | `dmenu.run`, `select.run` (surface:launcher in dmenu mode) |
| power | `power.{monitors-off,logout,reboot,poweroff,suspend,hibernate} --yes` (core → logind or the scripts; ACTION, not replay-safe), `lock` (69 until a locker exists), `inhibit.{on,off,toggle}` (core: a `systemd-inhibit` child) |
| status | `status.set {key, text}` (core; the keyed status model for scripts [w1-29 §3.3 P1]) |
| music | `music.*` (music) (P1) |

---

## 10. Theme and fonts

### 10.1 The theme fragment

- **Rendering.** `home/themes/default.nix` gains `gpuixShell = t: builtins.toJSON {...}` and the line
  `"gpuix-shell.json" = gpuixShell t;` in `render` (`default.nix:281-290`). `fragments` fans out on its
  own, so the three themes each get `~/.config/theme/gpuix-shell.json` behind the `~/.config/theme`
  symlink [w1-17 §3.3 steps 1–4].
- **Content** (DESIGN §2): flat, resolved literals; no references and no runtime alpha math. Per-theme
  literals that are not derivable from roles live inside `gpuixShell`, keyed by theme name (DESIGN A-01).
- **Schema.** `core/theme/schema.ts` is the zod transcription of DESIGN §2.5:
  - required groups, `x-keys` children, a hex pattern;
  - a fragment that fails is refused, with the zod path of the first missing key (U-04).
- **Nix checks.** `gpuix-shell --check-theme <file>` runs the same schema in
  `checks.gpuix-shell-themes` over the three rendered fragments [w1-21 §5.3c].

### 10.2 Live reload

1. **Watch** (`platform/fs/watch.ts`, in core). Two watches run, because a symlink retarget fires no
   watch event on the old target [w1-17 §3.3]:
   - `fs.watch(~/.config)` filtered to the entry `theme`;
   - `fs.watch` on the resolved target directory, in case the fragment changes in place, as in dev.
2. **Explicit hook.** In `home/dot_local/bin/theme`, `reload_desktop_tools` (`:83-92`) replaces
   `makoctl reload` and `vicinae theme set dotfiles-current` with:
   `systemctl --user -q is-active gpuix-shell-core && gpuix-shell theme reload --source script`
   [w1-17 §3.3 step 5], [w1-36 §3.13].
3. **Debounce 50 ms** [w1-03], then read, `realpath`, parse and validate:
   - **valid:** `theme` topic `{name, polarity, rev, tokens}` → every subscribed surface swaps its
     `ThemeProvider` value → re-render;
   - **invalid:** keep the last good tokens, log `theme-invalid path=…`, and raise one notification.
4. **Daemons.** Notifications and music subscribe too: the toast child is respawned with new tokens.
   Transient surfaces that are open re-render; new spawns get the tokens in their payload.
5. **GPUIX theme.** The `GpuixTheme` (input and markdown colours, `fontSans`/`fontMono`) is derived
   from the tokens on every change. Whether GPUIX re-applies a changed theme on the fly is UNVERIFIED;
   the fallback is to restart the rail and respawn the open overlay. The smoke checks a symlink flip
   repaints within 300 ms (SCOPE S-007).

### 10.3 Fonts via installed faces

**Families** (fontconfig names, exact [w1-17 §3.6]):

| Role | Family |
|---|---|
| ui | `Anthropic Sans` |
| prose | `Anthropic Serif` |
| mono, glyph | `AnthropicMono Nerd Font` |
| icons | `Anthropicons` (U+E000–E134) |

**Regular weight resolves by family name.** It is installed system-wide (`modules/common.nix:396`
`fonts.packages`). This is MEASURED: the rail probe rendered Anthropic Sans [BRIEF].

**Weights 500 and 600.** The installed Sans and Serif are variable fonts; GPUIX ignores the axes
[w1-15 G5]. The fix is a new derivation, `pkgs/anthropic-ui-static.nix` (INFERRED; nothing in git
changes except the recipe):

```nix
{ lib, runCommand, python3Packages, anthropic-ui }:
runCommand "anthropic-ui-static" { nativeBuildInputs = [ python3Packages.fonttools ]; } ''
  out_dir=$out/share/gpuix-shell/fonts; mkdir -p $out_dir
  for w in 400 500 600; do
    fonttools varLib.instancer ${anthropic-ui}/share/fonts/truetype/AnthropicSans-Roman.ttf \
      wght=$w opsz=16 --update-name-table -o $out_dir/AnthropicSans-Static-$w.ttf
  done
  for w in 400 600; do
    fonttools varLib.instancer ${anthropic-ui}/share/fonts/truetype/AnthropicSerif-Roman.ttf \
      wght=$w opsz=16 --update-name-table -o $out_dir/AnthropicSerif-Static-$w.ttf
  done
  # then a small fontTools script sets nameID 1 to exactly "Anthropic Sans" / "Anthropic Serif"
  # so that fontWeight picks the instance (MEASURED trick, w1-15 P4 "same-family-bold")
''
```

- **Inputs and visibility.** The derivation depends on the NAS-pinned `anthropic-ui` (`requireFile`), so
  fresh builders need the tarball first (`nix-store --add-fixed`) [w1-17 §3.6]. It is **not** added to
  `fonts.packages`, so no other application's font resolution changes.
- **Registration.** The HM module passes `GPUIX_SHELL_FONT_DIR=${pkgs.anthropic-ui-static}/share/gpuix-shell/fonts`
  in each window unit's environment. `ui/host/fonts.ts` calls `registerFont(bytes)` for each file, on
  every renderer [w1-15 §3.8 "per renderer"].
- **Fallback.** If the directory is absent, the shell logs once and renders weights 500 and 600 as 400.
  Hierarchy then rests on size and ink, as DESIGN A-04 allows.
- **Mono.** The statics work as installed. `fontWeight` 600 on mono works; Bold is avoided (kitty's
  "SemiBold, never Bold" [w1-17]).
- **No font bytes in the package or in git, ever.** `pkgs/gpuix-shell` builds without any font input.

---
## 11. systemd user units

Unit names (SCOPE S-013 `gpuix-shell-<surface>`):

- `gpuix-shell-core.service`
- `gpuix-shell-notifications.service`
- `gpuix-shell-rail.service`
- `gpuix-shell-music.service` (P1, off by default)

Transient surfaces are **not** units: they are children of core (or of the notifications daemon) inside
its cgroup, so they die with it (`KillMode=control-group`, the default).

The template follows mako's existing unit [w1-17 §3.5] and the Hyprland precedent [w1-13]:

- `ConditionEnvironment=WAYLAND_DISPLAY`;
- `After=`, `PartOf=` and `WantedBy=` all `sway-physical-session.target`;
- **never** `Requires=sway-physical.service` [w1-17], [w1-26];
- `Restart=on-failure`, `RestartSec=2`, `Slice=app.slice`, `UMask=0077`.

These are the rendered units as `home/gpuix-shell.nix` emits them (`${pkg}` is the store path):

```ini
# ~/.config/systemd/user/gpuix-shell-core.service
[Unit]
Description=gpuix-shell core (command socket, state hub, surface supervisor)
Documentation=file:///home/tom/.wt/dotfiles/gpuix-shell/docs/gpuix-shell/ARCHITECTURE.md
PartOf=sway-physical-session.target
After=sway-physical-session.target
ConditionEnvironment=WAYLAND_DISPLAY
ConditionEnvironment=SWAYSOCK
StartLimitIntervalSec=60
StartLimitBurst=10

[Service]
Type=exec
ExecStart=${pkg}/bin/gpuix-shell daemon core
Restart=on-failure
RestartSec=2
RestartPreventExitStatus=69
Slice=app.slice
UMask=0077
StandardInput=null
SyslogIdentifier=gpuix-shell-core
TimeoutStopSec=5
Environment=OPENUI_TELEMETRY_DISABLED=1 DO_NOT_TRACK=1
Environment=GPUIX_SHELL_FONT_DIR=${anthropic-ui-static}/share/gpuix-shell/fonts

[Install]
WantedBy=sway-physical-session.target
```

```ini
# ~/.config/systemd/user/gpuix-shell-notifications.service
[Unit]
Description=gpuix-shell notifications (org.freedesktop.Notifications, toasts, OSD)
PartOf=sway-physical-session.target
After=sway-physical-session.target
Wants=gpuix-shell-core.service
ConditionEnvironment=WAYLAND_DISPLAY
StartLimitIntervalSec=60
StartLimitBurst=10

[Service]
Type=dbus
BusName=org.freedesktop.Notifications
ExecStart=${pkg}/bin/gpuix-shell daemon notifications
Restart=on-failure
RestartSec=2
RestartPreventExitStatus=69
Slice=app.slice
UMask=0077
StandardInput=null
SyslogIdentifier=gpuix-shell-notifications
Environment=GPUIX_SHELL_FONT_DIR=${anthropic-ui-static}/share/gpuix-shell/fonts

[Install]
WantedBy=sway-physical-session.target
```

```ini
# ~/.config/systemd/user/gpuix-shell-rail.service
[Unit]
Description=gpuix-shell rail (left bar on eDP-1)
PartOf=sway-physical-session.target
After=sway-physical-session.target gpuix-shell-core.service
Wants=gpuix-shell-core.service
ConditionEnvironment=WAYLAND_DISPLAY
ConditionEnvironment=SWAYSOCK
StartLimitIntervalSec=60
StartLimitBurst=10

[Service]
Type=exec
ExecStart=${pkg}/bin/gpuix-shell daemon rail --output eDP-1
Restart=on-failure
RestartSec=2
RestartPreventExitStatus=69
Slice=app.slice
UMask=0077
StandardInput=null
SyslogIdentifier=gpuix-shell-rail
Environment=GPUIX_SHELL_FONT_DIR=${anthropic-ui-static}/share/gpuix-shell/fonts

[Install]
WantedBy=sway-physical-session.target
```

```ini
# ~/.config/systemd/user/gpuix-shell-music.service   (P1; only when programs.gpuixShell.music.enable)
[Unit]
Description=gpuix-shell music (Navidrome player, MPRIS)
PartOf=sway-physical-session.target
After=sway-physical-session.target
ConditionPathExists=/run/agenix/navidrome-credentials
[Service]
Type=exec
ExecStart=${pkg}/bin/gpuix-shell music serve
Restart=on-failure
RestartSec=2
RestartPreventExitStatus=69
Slice=app.slice
UMask=0077
StandardInput=null
[Install]
WantedBy=sway-physical-session.target
```

Notes on the units:

- **Ordering.**
  - Only the rail orders `After=gpuix-shell-core`, since it needs topics to draw anything but the
    skeleton.
  - Notifications deliberately does not wait on core, so `notify-send` works even if core is broken.
  - Every client reconnects with a backoff anyway (§17).
- **`StandardInput=null`** keeps GPUIX automation harmless: stdin is `/dev/null`, so EOF [w1-15 G16].
- **`RestartPreventExitStatus=69`** stops restart loops for an "unavailable" condition: the bus name is
  held by mako, the rail output is absent, the credential file is missing. Core restarts the rail itself
  when its output comes back (§17).
- **Start limits.** `StartLimitBurst=10` in 60 s (INFERRED) tolerates a burst of GPU resets without
  locking the unit out.
- **Environment.**
  - `PATH` comes from the imported login environment; the wrapper needs none [w1-21 §5.5].
  - `XDG_CURRENT_DESKTOP=sway-physical` comes from the session import; desktop-entry
    `OnlyShowIn`/`NotShowIn` evaluation uses it [w1-26 §7], [w1-17].
- **No units for transients or for wl-paste, ssh or pw-dump.** Those children belong to core's cgroup.
  `systemctl --user status gpuix-shell-core` shows them, and the journal attributes their stderr to
  `gpuix-shell-core` with a `surface=` field.
- **Home Manager switches.** `sd-switch` restarts changed units. The shell never sets
  `X-SwitchMethod=keep-old`; that setting is herdr's, so its PTYs survive [SCOPE S-001], [flake.nix:1393].

---

## 12. Sway binds

Mechanism (INFERRED):

- **No edits to `binds.conf` tonight.** `home/gpuix-shell.nix` appends one generated block to the
  per-host `~/.config/sway-local.conf` (HM `xdg.configFile."sway-local.conf".text`, a `lines` option, so
  `lib.mkAfter` concatenates). That file is already included **after** `binds.conf`
  (`home/dot_config/sway/config:6,9`).
- **Overrides use `bindsym --no-warn`.** The later binding wins, the same mechanism the client's F10
  override already uses (`home.nix:160`).
- **Benefits.**
  - `binds.conf` keeps its flake-asserted lines (`flake.nix:1126-1145`, `1213-1229`).
  - "Never both" holds per host: the block exists only when `programs.gpuixShell.enable` is set, and is
    gone on rollback.
  - The strix stays free of binds (gated on `osConfig.myDisplay.enable`).
- **Later cleanup.** Once the shell has proved itself, the four overridden `binds.conf` lines can be
  edited in place and the overrides dropped. That is wave 3 or later.
- **Binds call the canonical spelling** `gpuix-shell <surface> <verb>` (KEYS §7.0) with `--source bind`.
- **Toggles use `--no-repeat`**, so a held key does not flap the overlay. Core also debounces at 150 ms
  (§3.3).

The full block (each line cites its KEYS row):

```
# ---- gpuix-shell (GENERATED by home/gpuix-shell.nix; present only while programs.gpuixShell.enable) ----
# Overrides of binds.conf lines (vicinae → gpuix-shell)                              KEYS §2.1/§2.6
bindsym --no-warn --no-repeat $mod+d          exec gpuix-shell launcher toggle --source bind              # binds.conf:6
bindsym --no-warn --no-repeat $mod+space      exec gpuix-shell launcher toggle --source bind              # binds.conf:7
bindsym --no-warn --no-repeat $mod+Ctrl+space exec gpuix-shell launcher toggle --view herdr --source bind  # binds.conf:8 (was herdr-picker)
bindsym --no-warn --no-repeat $mod+v          exec gpuix-shell launcher toggle --view clipboard --source bind  # binds.conf:114
# New binds (keys checked free by KEYS §3)
bindsym --no-repeat $mod+i            exec gpuix-shell switcher toggle --source bind          # Mod+i switcher, eDP-1 [w1-17 PR #565]
bindsym $mod+o                        exec gpuix-shell notifications dismiss --source bind    # newest toast (PR #571 retargeted)
bindsym $mod+Ctrl+o                   exec gpuix-shell notifications dismiss --all --source bind
bindsym --no-repeat $mod+Shift+o      exec gpuix-shell notifications toggle --source bind     # notification centre
bindsym --no-repeat $mod+x            exec gpuix-shell power toggle --source bind             # power menu (hold-to-confirm inside)
bindsym --no-repeat $mod+comma        exec gpuix-shell controls toggle --source bind          # per-domain menus
bindsym --no-repeat $mod+Shift+e      exec gpuix-shell files open --source bind               # Pinax-like explorer (P1)
bindsym --no-repeat $mod+Shift+slash  exec gpuix-shell cheatsheet toggle --source bind        # hotkey sheet
bindsym --no-repeat $mod+Shift+grave  exec gpuix-shell rail toggle --source bind              # rail 56 ⇄ 220
# Proposed, emitted only when programs.gpuixShell.binds.proposed = true (not tonight)
# bindsym --no-repeat $mod+m          exec gpuix-shell launcher toggle --view music --source bind
# bindsym --no-repeat $mod+Shift+m    exec gpuix-shell music now --source bind
# bindsym --no-repeat $mod+a          exec gpuix-shell ask toggle --source bind
```

What stays unchanged (KEYS §2):

- **Untouched binds:**
  - the herdr chords and `sway-workspace` lines (`binds.conf:9-15`, flake-asserted);
  - `$mod+k`;
  - `Alt+h/j/k/l`;
  - every F-key and XF86 line. Volume, brightness, media, touchpad and pomodoro keep calling their
    scripts.
- **The OSD path.** The OSD appears because the `osd` script's `notify-send -r` now lands in our daemon
  (§7.3). The script change to `gpuix-shell osd <kind> <value>`, with a fallback to `notify-send` when
  the socket is absent, is optional (KEYS §3 "F-keys → OSD").
- **Deferred to wave 3** (needs `audio-route <sink>` non-interactive):
  `$mod+grave` (herdr-context, another branch) and F9 → `controls open audio`.

---

## 13. Home Manager module (`home/gpuix-shell.nix`)

```nix
{ config, lib, pkgs, osConfig, ... }:
let
  cfg = config.programs.gpuixShell;
  json = pkgs.formats.json { };
  target = cfg.target;
  fontDir = lib.optionalString (cfg.fontPackage != null) "${cfg.fontPackage}/share/gpuix-shell/fonts";
  unit = { description, exec, extraUnit ? { }, extraService ? { } }: {
    Unit = { Description = description; PartOf = [ target ]; After = [ target ];
             ConditionEnvironment = [ "WAYLAND_DISPLAY" ]; StartLimitIntervalSec = 60; StartLimitBurst = 10; } // extraUnit;
    Service = { Type = "exec"; ExecStart = "${cfg.package}/bin/gpuix-shell ${exec}";
                Restart = "on-failure"; RestartSec = 2; RestartPreventExitStatus = 69;
                Slice = "app.slice"; UMask = "0077"; StandardInput = "null";
                Environment = [ "OPENUI_TELEMETRY_DISABLED=1" "DO_NOT_TRACK=1" ]
                  ++ lib.optional (fontDir != "") "GPUIX_SHELL_FONT_DIR=${fontDir}"
                  ++ lib.mapAttrsToList (k: v: "${k}=${v}") cfg.extraEnvironment; } // extraService;
    Install.WantedBy = [ target ];
  };
in {
  options.programs.gpuixShell = with lib; {
    enable = mkEnableOption "gpuix-shell (replaces vicinae + mako; never both)";
    package = mkOption { type = types.package; default = pkgs.gpuix-shell; };
    fontPackage = mkOption { type = types.nullOr types.package; default = pkgs.anthropic-ui-static or null;
      description = "Static Anthropic Sans/Serif instances registered per renderer (weights 500/600)."; };
    target = mkOption { type = types.str; default = "sway-physical-session.target"; };
    rail = {
      enable = mkOption { type = types.bool; default = true; };
      output = mkOption { type = types.str; default = "eDP-1"; };
      boot = mkOption { type = types.enum [ "collapsed" "expanded" ]; default = "collapsed"; }; # DESIGN A-08
    };
    toastAnchor = mkOption { type = types.enum [ "top-center" "top-right" ]; default = "top-center"; }; # DESIGN A-15
    binds = {
      enable = mkOption { type = types.bool; default = true; };   # append §12 block to sway-local.conf
      proposed = mkOption { type = types.bool; default = false; }; # $mod+m, $mod+Shift+m, $mod+a
    };
    herdr = {
      transport = mkOption { type = types.enum [ "auto" "local" "ssh-forward" "ssh-exec" ]; default = "auto"; };
      host = mkOption { type = types.str; default = "strix"; };
    };
    chromeNativeHost = mkOption { type = types.bool; default = true; };   # com.vicinae.vicinae → our host
    music.enable = mkOption { type = types.bool; default = false; };     # P1
    settings = mkOption { type = json.type; default = { };
      description = "Merged into ~/.config/gpuix-shell/config.json (favourites, hidden apps, provider prefs, rules)."; };
    extraEnvironment = mkOption { type = types.attrsOf types.str; default = { }; };
  };

  config = lib.mkIf (cfg.enable && osConfig.myDisplay.enable) {
    assertions = [
      { assertion = !config.services.mako.enable;   message = "gpuix-shell owns org.freedesktop.Notifications: disable services.mako (never both)."; }
      { assertion = !config.programs.vicinae.enable; message = "gpuix-shell replaces vicinae: disable programs.vicinae (never both)."; }
    ];
    home.packages = [ cfg.package pkgs.libnotify pkgs.wl-clipboard pkgs.fd ];
    xdg.configFile."gpuix-shell/config.json".source = json.generate "gpuix-shell-config.json"
      (lib.recursiveUpdate { rail = { inherit (cfg.rail) output boot; }; toast.anchor = cfg.toastAnchor;
                             herdr = cfg.herdr; schemaVersion = 1; } cfg.settings);
    xdg.configFile."sway-local.conf".text = lib.mkIf cfg.binds.enable (lib.mkAfter (import ./gpuix-shell-binds.nix { inherit lib cfg; }));
    xdg.configFile."google-chrome/NativeMessagingHosts/com.vicinae.vicinae.json" = lib.mkIf cfg.chromeNativeHost {
      text = builtins.toJSON { name = "com.vicinae.vicinae"; description = "gpuix-shell browser bridge";
        path = "${cfg.package}/bin/gpuix-shell-native-host"; type = "stdio";
        allowed_origins = [ "chrome-extension://kcmipingpfbohfjckomimmahknoddnke/" ]; };   # [w1-36 §3.11, §4.6]
    };
    systemd.user.services = {
      gpuix-shell-core = unit { description = "gpuix-shell core (command socket, state hub, surface supervisor)";
        exec = "daemon core"; extraUnit.ConditionEnvironment = [ "WAYLAND_DISPLAY" "SWAYSOCK" ]; };
      gpuix-shell-notifications = unit { description = "gpuix-shell notifications (org.freedesktop.Notifications, toasts, OSD)";
        exec = "daemon notifications"; extraUnit.Wants = [ "gpuix-shell-core.service" ];
        extraService = { Type = "dbus"; BusName = "org.freedesktop.Notifications"; }; };
    } // lib.optionalAttrs cfg.rail.enable {
      gpuix-shell-rail = unit { description = "gpuix-shell rail (left bar on ${cfg.rail.output})";
        exec = "daemon rail --output ${cfg.rail.output}";
        extraUnit = { ConditionEnvironment = [ "WAYLAND_DISPLAY" "SWAYSOCK" ];
                      Wants = [ "gpuix-shell-core.service" ]; After = [ target "gpuix-shell-core.service" ]; }; };
    } // lib.optionalAttrs cfg.music.enable {
      gpuix-shell-music = unit { description = "gpuix-shell music (Navidrome player, MPRIS)"; exec = "music serve";
        extraUnit.ConditionPathExists = "/run/agenix/navidrome-credentials"; };
    };
  };
}
```

Wiring:

- **Imports.** Add `./gpuix-shell.nix` to the imports in `home/home.nix` beside `./vicinae.nix`
  (`home.nix:114`).
- **Gate vicinae and mako.** In `home/vicinae.nix:10`, set
  `enabled = osConfig.myDisplay.enable && !config.programs.gpuixShell.enable;`. That one gate turns off
  vicinae, mako (`vicinae.nix:111-143`) and the seven desktop entries (`:148-170`), which the registry's
  native commands replace (KEYS §8.3) [w1-21 §d].
- **The native-host shim.** `gpuix-shell-native-host` is a second `makeWrapper` binary
  (`--add-flags native-host`). Chrome launches the `path` in the manifest without arguments, so it
  cannot pass `native-host` itself.
- **Enable on the client.** `hosts/client/default.nix` gets
  `home-manager.users.tom.programs.gpuixShell.enable = true;` beside `:101` [w1-21 §d]. It is not set
  on the strix.
- **Config generation is pure Nix.**
  - The zod schema in `core/config/schema.ts` re-validates the file at start (S-009).
  - A flake check runs `gpuix-shell validate <file>` on the client's rendered config (§14.4).

---

## 14. Nix package recipe

### 14.1 `package.json` (exact pins; §19)

```json
{
  "name": "gpuix-shell", "version": "0.1.0", "private": true, "type": "module",
  "scripts": { "build": "bun build.ts", "test": "bun test", "typecheck": "tsc --noEmit" },
  "dependencies": {
    "@gpuix/native": "0.11.0", "@gpuix/react": "0.11.0", "dbus-next": "0.10.2",
    "react": "19.2.0", "zod": "4.6.7", "@openuidev/lang-core": "1.0.1"
  },
  "devDependencies": { "@types/bun": "1.3.13", "@types/react": "19.2.0", "typescript": "5.9.3" }
}
```

How this differs from the scaffold on disk:

- The scaffold has `"version": "0.0.0"`, `"zod": "^4"` and `"@types/bun": "latest"`, and only a
  `bun.lock`. Pin both exactly.
- Generate `package-lock.json` with `npm install --save-exact --ignore-scripts` (§19.3).
- Add `bun.lock` to `PKG/.gitignore`, so Nix and the dev loop share one lock [w1-21 §5.10].
- `@openuidev/lang-core` runs a postinstall telemetry ping, so it is installed with `--ignore-scripts`
  everywhere and `OPENUI_TELEMETRY_DISABLED=1` is set at runtime [w1-24 §5.5].
- **Lock hash.** The measured `npmDepsHash` (`sha256-r6hZuPIv97JGR1F1oaeePCcUG60BWDn0Xt3+qOQwp5o=`) belongs
  to w1-21's exact lock, which has no lang-core. Adding lang-core changes the lock, so: set
  `lib.fakeHash`, build once, paste the reported hash (or run `prefetch-npm-deps package-lock.json`).

### 14.2 `build.ts` (one dispatcher, lazy chunks)

```ts
export {};
const result = await Bun.build({
  entrypoints: ["./src/main.ts"],
  target: "bun", format: "esm", outdir: "dist", splitting: true,
  external: ["@gpuix/native", "@gpuix/native/*", "usocket", "x11"],   // dbus-next optional natives stay out
});
if (!result.success) { console.error(result.logs); process.exit(1); }
```

`src/main.ts` dispatches on `argv[2]` with **dynamic** `import()`:

| argv | Loads |
|---|---|
| `daemon core`, `daemon notifications`, `native-host` | daemons (no addon) |
| `daemon rail`, `surface <name>` | `ui/host` + the surface (loads the addon) |
| `--check-native` | the addon only |
| anything else | the CLI |

With `splitting: true` each dynamic import becomes its own chunk, so CLI calls never `dlopen` the 52 MB
addon. A static bundle hoists `@gpuix/native` into every path, about 0.1 s per CLI call [w1-21 §4.3,
measured]. The chunking itself is INFERRED: measure `time gpuix-shell ping` ≤ 100 ms.

### 14.3 `default.nix` (w1-21 §5.2, measured building, plus tonight's deltas)

```nix
{ lib, stdenv, buildNpmPackage, nodejs_24, bun, autoPatchelfHook, makeWrapper,
  libxkbcommon, libxcb, wayland, vulkan-loader, libGL }:
buildNpmPackage {
  pname = "gpuix-shell"; version = "0.1.0";
  src = lib.cleanSourceWith {
    src = ./.;
    filter = path: type: let b = baseNameOf path; in
      !(builtins.elem b [ "node_modules" "dist" "result" "default.nix" ".local-state" "bun.lock" "bun.lockb" ])
      && !(lib.hasSuffix ".log" b) && !(lib.hasSuffix ".err" b);
  };
  nodejs = nodejs_24;
  npmDepsHash = lib.fakeHash;               # refresh after every lock change (§14.1)
  npmFlags = [ "--ignore-scripts" ];
  nativeBuildInputs = [ bun autoPatchelfHook makeWrapper ];
  buildInputs = [ stdenv.cc.cc.lib libxkbcommon libxcb ];
  appendRunpaths = map (p: "${lib.getLib p}/lib") [ wayland vulkan-loader libGL ];
  buildPhase = ''
    runHook preBuild
    npm run typecheck
    bun run build
    runHook postBuild
  '';
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    export LD_LIBRARY_PATH=${lib.makeLibraryPath [ wayland vulkan-loader libGL ]}
    bun test                                 # pure logic + import fence + registry + schemas
    runHook postCheck
  '';
  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/gpuix-shell/node_modules $out/bin $out/share/dbus-1/services
    cp -r dist package.json $out/lib/gpuix-shell/
    for m in @gpuix/native @gpuix/native-linux-x64-gnu zod eventsource-parser; do
      mkdir -p $out/lib/gpuix-shell/node_modules/$(dirname $m)
      cp -r node_modules/$m $out/lib/gpuix-shell/node_modules/$m
    done
    rm -rf $out/lib/gpuix-shell/node_modules/@gpuix/native/wasm
    makeWrapper ${bun}/bin/bun $out/bin/gpuix-shell \
      --add-flags $out/lib/gpuix-shell/dist/main.js \
      --set GPUIX_SHELL_EXECUTABLE $out/bin/gpuix-shell
    makeWrapper ${bun}/bin/bun $out/bin/gpuix-shell-native-host \
      --add-flags "$out/lib/gpuix-shell/dist/main.js native-host"
    cat > $out/share/dbus-1/services/org.freedesktop.Notifications.service <<EOF2
    [D-BUS Service]
    Name=org.freedesktop.Notifications
    Exec=/bin/false
    SystemdService=gpuix-shell-notifications.service
    EOF2
    runHook postInstall
  '';
  doInstallCheck = true;
  installCheckPhase = ''
    export HOME=$TMPDIR
    $out/bin/gpuix-shell --check-native | grep -q '"ok":true'
    $out/bin/gpuix-shell --check-dbus   | grep -q '"ok":true'
  '';
  meta = { description = "Tom's Sway desktop shell on GPUIX"; mainProgram = "gpuix-shell";
           platforms = [ "x86_64-linux" ]; license = lib.licenses.unfree; };  # private (fonts, personal)
}
```

Notes on the recipe:

- **The heredoc.** Nix strips the common indentation of the `''` string, so the inner heredoc body and
  its `EOF2` terminator land at column 0 in the build script. The delimiter name is arbitrary.
- **Node modules.** The four copied `node_modules` are the runtime set w1-21 measured. Bun bundles
  everything else, including dbus-next and lang-core.
- **Libraries.** `autoPatchelfHook` plus `appendRunpaths` resolve the addon's `dlopen`s
  (`libvulkan.so.1`, `libwayland-client.so`, `libEGL.so.1`, `libxkbcommon.so.0`, `libxcb.so.1`). The
  Vulkan loader finds its ICDs under `/run/opengl-driver` at runtime [w1-21 §4.2], [w1-15 §5.1]. Which
  ICD the Zenbook should use is an open question (pin Intel if the default is wrong) [w1-21 gap list].
- **Fontconfig.** The binding parses `/etc/fonts/fonts.conf` itself, which a NixOS host provides [w1-21].
- **Self-check timings** (MEASURED [w1-21]): `--check-native` 102 ms, `--check-dbus` 123 ms.

### 14.4 Flake wiring [w1-21 §5.3]

1. **Overlay.** In `overlays/default.nix` after line 5, add
   `gpuix-shell = final.callPackage ../pkgs/gpuix-shell { };` and
   `anthropic-ui-static = final.callPackage ../pkgs/anthropic-ui-static.nix { };`. The second is
   INFERRED, beside the font overlay at `flake.nix:307-309`.
2. **Package export.** Add `gpuix-shell` in `flake.nix:506-536`, after `chrome-stream`.
3. **Checks.**
   - `checks.gpuix-shell = pkgs.gpuix-shell;`, which runs `bun test` and the install checks.
   - `checks.gpuix-shell-themes` runs `gpuix-shell --check-theme` over the three fragments rendered by
     `import ./home/themes { inherit (nixpkgs) lib; }`.
   - `checks.gpuix-shell-contract` runs `python3 -m unittest discover -s ./tests/gpuix-shell -p 'test_*.py'`
     (hermetic tests only; smokes are never flake checks).
4. **`home-profiles` asserts** (`flake.nix:1074-1379`). Revise them as follows:
   - **XOR asserts.** On the client, `gpuixShell.enable != vicinae.enable` and
     `gpuixShell.enable != services.mako.enable`.
   - **Units.** When the shell is on, `gpuix-shell-notifications` has `BusName`, and
     `gpuix-shell-{core,rail}` are `WantedBy` `[sway-physical-session.target]`.
   - **Package.** `home.packages` contains the package.
   - **Theme fragment.** `themes/noir/gpuix-shell.json` exists.
   - **Strix.** Never enabled on the strix.
   - **Font assert.** The font assert at `:1228-1229` moves to `config.json`'s font family or to the
     theme fragment's `font.ui == "Anthropic Sans"`.
5. **Guards.**
   - deadnix scans `home/`.
   - Units must use store paths (raw-dotfiles-guard). `ExecStart` uses `${cfg.package}`, never
     `~/.local/bin`.

---
## 15. Test strategy

Every compositor or daemon experiment runs under the branch copy of the runtime-test wrapper:
`home/dot_local/bin/runtime-test --render-node /dev/dri/renderD128 -- …`. The installed wrapper lacks
`--render-node` [BRIEF §4]. It gives the test a private `/run/user` and PID/IPC namespaces, so the live
session, systemd, D-Bus and herdr are never touched (Tom's runtime rules).

### 15.1 Level 1: `bun test`, pure logic

These are `*.test.ts` files beside the code; no I/O beyond fixtures, no network. They run in
`checkPhase`.

| Area | Tests | Fixture or source |
|---|---|---|
| sway-ipc | `frame(0,'exit')` byte-identical to the man page (MEASURED in [w1-26]); header split across chunks; bit 31 = event; `EVENT_NAMES`; coalescer; `derive()` on the live tree | `live-client-sway-tree.json` [w1-09], `zenbook-0221-{get_tree,get_workspaces,get_outputs}.json` [w1-16] |
| quoting | the 26 mocked cases of `platform.ts` (reserved words, forbidden characters, a `--` prefix) | [w1-08] |
| herdr | nine-slot mapping; repeated labels (`client-slot-N-hex6` is the creation slot, not unique); closed marks; status rank; the "made in slot N" chip rule; attention episodes (`state_change_seq`); the outage baseline | `live-herdr-snapshot.json` [w1-09], [w1-16 §5.1] |
| registry and CLI | ids unique; every KEYS §7 verb parses; `--json` everywhere; usage → exit 2; the §12 bind block parses to registered ids; no SECRET verb has a CLI path | KEYS.md table snapshot |
| socket | NDJSON codec; compat-frame codec; **sniff** (`{`+non-zero vs a length frame, including the 0x227B edge); per-connection reply routing: concurrent `dmenu` + `state` on two connections with the same id never cross [w1-36 G17]; backlog drop → `events_lost` | — |
| notifications | id wrap, skipping 0; replace semantics; a stale `replaces_id` → new id; close reasons; timeout table; flood 20/s + 1 s coalesce; rules first-match; OSD routing and the stable id; markup sanitiser; `image-data` → RGBA; toast height estimator (golden) | [w1-18], [w1-13] |
| launcher | fuzzy golden corpus (herdr-bar constants); frecency formula; root merge order; alias-first; abort semantics (a yield after abort is ignored) | [w1-23], [w1-35] |
| clipboard | kinds; password-hint skip; eviction with pins exempt; dedupe by hash | [w1-35 §1.1] |
| theme and config | the three rendered fragments validate; each missing required key is rejected with its path; config defaults render with no user file | DESIGN §2.5, SCOPE S-009 |
| desktop entries, scripts | Exec field codes; `NoDisplay`, `Hidden`, `OnlyShowIn=sway-physical`; the script-command header parser (port of Vicinae's 7 C++ suites) | [w1-26 §7], [w1-36 §5] |
| fence and design-lint | the import globs of §2.1; no hex or `shadow` in `src/ui` and `src/surfaces` | BOUNDARY §5 |

### 15.2 Level 2: D-Bus and daemon tests (hermetic, under the wrapper)

The run command is:

```
home/dot_local/bin/runtime-test --render-node /dev/dri/renderD128 -- \
  dbus-run-session --config-file=tests/gpuix-shell/dbus-session.conf -- bun test src/platform/dbus src/daemons
```

- **Notifications daemon on a private bus.** It runs as a child with `--check-dbus` off.
- **The client is the real `notify-send`** from libnotify. The cases are the 14 of §7.4: `-p`, `-r`,
  `--wait`, `--action`, `-u critical`, `-t 0`, `-e`, `-h int:value`, `image-data`.
- **Daemon logic without windows.** Toast and OSD windows are replaced by a fake child (an env flag swaps
  in a no-window stub that answers `surface/ready`), so these tests need no GPU.
- **Name contention.** A first `requestName` owner (a stub posing as mako) must make our daemon exit 69.
- **Core with fakes.** Core runs against `platform/sway/fake-server.ts`, a fake i3-ipc server replaying
  fixture events, and a fake `herdr` (`tests/gpuix-shell/bin/herdr` printing the fixture), to check
  topics end-to-end over `shell.sock` without Sway.

### 15.3 Level 3: Python smokes under headless Sway (gles2)

The smokes are `tests/gpuix-shell/smoke_<surface>.py` (BOUNDARY naming: never `test_*.py`, never a flake
check). The template follows `smoke_rail.py` [w1-21 §5.6] and the P7 harness [w1-15 §4]:

- **Paths.** `flake_paths()` evaluates the client's `sway` (1.12) and `grim` from the flake; the tool
  paths are pinned in BRIEF.
- **Inner `sway.conf`:**
  - `output HEADLESS-1 mode 1440x900 bg #202020 solid_color`;
  - a second variant at `mode 2880x1800 scale 2`, the Duo's DPI (INFERRED addition, MUST #22);
  - a two-output variant for the switcher and the rail pinning;
  - `xwayland disable`;
  - `seat seat0 fallback true`.
- **Environment.** `WLR_BACKENDS=headless WLR_RENDERER=gles2 WLR_RENDER_DRM_DEVICE=/dev/dri/renderD128
  WLR_LIBINPUT_NO_DEVICES=1 SWAY_DISABLE_SD_NOTIFY=1 XDG_CURRENT_DESKTOP=sway-physical`. Strip
  `LD_LIBRARY_PATH` and `VK_ICD_*`. Pixman fails with `ERROR_SURFACE_LOST_KHR` [w1-08].
- **Guards.** Assert there is no `$XDG_RUNTIME_DIR/bus`, no `/dev/input` and no `/dev/dri/card*`.
  `main()` re-execs itself through `ROOT/home/dot_local/bin/runtime-test --render-node`.
- **Driving the UI.**
  - Use the GPUIX automation client (`tests/gpuix-shell/driver.mjs`, shaped like `driver7.mjs`):
    `launch` → `getByTestId` → `fill`/`press`/`click`.
  - **Do not use** `wtype`, which loses its first key, or Sway cursor injection, which does not reach
    GPUIX [w1-15 §3.13], [w1-08].
  - Each surface is launched with stdin as a pipe **only** inside the smoke, which is how automation is
    meant to be used.
- **Asserts:**
  - geometry through `swaymsg -t get_workspaces` rects (layer surfaces are not in `get_tree`);
  - colours through `grim -o HEADLESS-1` PPM pixel checks;
  - content through `gpuix-shell <surface> ui-tree`.
- **Output.** Each smoke writes `results.json` plus evidence under `docs/gpuix-shell/evidence/<smoke>/`.

P0 smokes:

| Smoke | Proves |
|---|---|
| `smoke_rail.py` | workspace rect x==56 (collapsed) and x==220 after `rail expand`; nine slot rows from the fake herdr; glyph colours by pixel; a theme symlink flip repaints in 300 ms |
| `smoke_launcher.py` | toggle maps in ≤ 0.6 s; typing filters; Enter on a command row invokes it (echo arrives); Escape exits (process gone); a second toggle closes; `--view clipboard` opens the lens |
| `smoke_notifications.py` | `notify-send` → toast pixels at top-centre; `-r` replaces in place; automation click → `ActionInvoked`; `osd` script → OSD card at bottom 96 and no toast |
| `smoke_switcher.py` | with two outputs and eDP-2 focused, the switcher maps on eDP-1 (pin dance) and focus is restored after Escape |
| `smoke_clipboard.py` | `wl-copy` text and PNG → history rows; a `x-kde-passwordManagerHint` offer is skipped |

### 15.4 Level 4: fixtures

- **Location.** `tests/gpuix-shell/fixtures/<host>-<hhmm>-<ipc>.json`, for example
  `client-2310-get_tree.json` [w1-21 §5.6].
- **Sources.** Copies of the live fixtures (with provenance comments):
  - `/home/tom/tuesday-oct20/research_notes/Memory policy and harvest history/{live-client-sway-tree.json,live-herdr-snapshot.json}`
    [w1-09];
  - `morning-shell/tests/workspace-switcher/fixtures/zenbook-0221-*.json` [w1-16].
- **Recording.** New fixtures are read-only captures (`swaymsg -t get_tree`, `herdr api snapshot`).
  Nothing is ever written to herdr.
- **Hard rules:**
  - no test dials `strix:8731` or any network model (the Halogen incident [w1-24]);
  - no test reads `/run/agenix/*`;
  - live-only tests are `test.skipIf(!process.env.NAVIDROME_LIVE)` [w1-21 gap].

### 15.5 What is never automated

- The live seat.
- Real keyboards: `on-demand` keyboard mode is UNVERIFIED [w1-15 G11].
- Multi-hour renderer stability.
- Chrome with the real extension.

Tom's morning hand checks live in SCOPE (the P0 acceptance column).

---

## 16. Logging and diagnostics

### 16.1 Journal

- **Format.** Every process writes **logfmt lines to stderr**, which systemd sends to the journal
  under the unit's `SyslogIdentifier`.
- **Priority** uses the sd-daemon prefix: `<3>` error, `<4>` warn, `<6>` info, `<7>` debug, honoured
  because `SyslogLevelPrefix` defaults to yes.
- **Example:**
  `<6>event=surface.opened surface=launcher pid=4123 spawn_ms=287 source=bind`.
- **Level.** `GPUIX_SHELL_LOG=debug|info|warn` (default `info`).
- **Redaction** (`core/logging/redact.ts`), enforced by a unit test:
  - never clipboard bodies, notification bodies at info level, passwords, Subsonic tokens, or URL query
    strings;
  - summaries are logged only at debug.
- **Transient surfaces** inherit core's stderr and prefix `surface=<name> pid=<pid>`, so
  `journalctl --user -u gpuix-shell-core` shows them.
- **Reading logs:** `journalctl --user -u 'gpuix-shell-*' -f`. Vicinae's `logs` verb is retired (KEYS
  §7.7).
- **Timing events** for budgets:
  - `spawn_ms` (spawn → ready);
  - `paint_ms` (first commit);
  - `herdr_ms` (snapshot read);
  - `sway_batch_ms`;
  - `invoke_ms` (per registry id; a slow-request warning at 250 ms [w1-23 herdr-gpui]).

### 16.2 `gpuix-shell doctor [--json]`

The doctor runs in the CLI process, and spawns `--check-native` as a child so the CLI never loads the
addon. Each check is `ok`, `warn` or `fail`; the exit is 0 unless something fails, then 1.

| # | Check | How |
|---|---|---|
| 1 | core reachable, protocol and version match, session token matches `$SWAYSOCK` | `core/hello` |
| 2 | units active on `sway-physical-session.target` | `systemctl --user is-active gpuix-shell-{core,notifications,rail}` |
| 3 | `org.freedesktop.Notifications` is owned by **us** | `GetNameOwner` → `GetConnectionUnixProcessID` → `/proc/<pid>/comm`; a `mako` owner fails with the fix |
| 4 | vicinae and mako absent | no `vicinae`/`mako` process; no `com.vicinae.vicinae` host other than ours |
| 5 | the native addon loads | `gpuix-shell --check-native` child → `{"ok":true}` |
| 6 | theme fragment valid, symlink resolves | the zod schema |
| 7 | fonts | `fc-match "Anthropic Sans"` returns Anthropic; the static instance directory exists (warn if not: weights fall back) |
| 8 | Sway IPC | `GET_VERSION` 1.12; the configured rail output exists |
| 9 | herdr | transport mode, last snapshot age, read time |
| 10 | clipboard | both `wl-paste` watchers alive; store row count; directory modes 0700/0600 |
| 11 | Chrome bridge | manifest present and pointing at `gpuix-shell-native-host`; last `browser/init` age |
| 12 | runtime dir | `$XDG_RUNTIME_DIR/gpuix-shell` mode 0700, no stale sockets |
| 13 | memory | RSS per unit; warn above 400 MiB per surface (SCOPE S-014 target) |
| 14 | GPU | the render node exists; `VK_ICD_FILENAMES` unset or valid |
| 15 | music (P1) | credential file present; `music/ctl.sock` answers |

Also available:

- `gpuix-shell status [--json]` gives liveness of units and sockets only.
- `snapshot` dumps state.
- `listen` streams events for live debugging (KEYS §7.4).

---

## 17. Failure modes

| Failure | Detection | Behaviour | Grounds |
|---|---|---|---|
| **GPU loss / device lost** (GPU reset, resume, `ERROR_SURFACE_LOST_KHR`) | the renderer panics, or `tick()` returns false, and the process exits non-zero | the rail is restarted by systemd (2 s, burst 10 per 60 s); transient overlays just exit and the next toggle respawns; the toast child is respawned once by the notifications daemon, then it degrades to "store-only, no toasts" and shows an error state on the rail bell; core and notifications never touch the GPU, so the CLI, D-Bus and the clipboard keep working; **core dumps are not suppressed** | Tom's runtime rules, [w1-15 G14] |
| **herdr down / unreachable** | 2 failed reads, or the forward is down after backoff | `herdr.status=unavailable{since}`; slots show Sway names and ○ unknown with a stale age, never idle; no attention notifications; after recovery the first snapshot is a baseline; the transport falls back from ssh-forward to ssh-exec | [w1-16 §5.3], [w1-11] |
| **D-Bus name held by mako** | `requestName` ≠ PRIMARY_OWNER | the daemon logs the owner's pid and comm and exits **69**; `RestartPreventExitStatus=69` stops the loop; `notifications/*` verbs return 69 with the fix; doctor check 3 fails; HM and flake asserts prevent the state in the first place | §7.1, [w1-29 §3.5] |
| **core down** | the CLI cannot connect | the CLI exits **3** with `systemctl --user start gpuix-shell-core`; the rail keeps its last frame, shows a "disconnected" mark and reconnects with a 250 ms → 10 s backoff; notifications keep serving D-Bus | §3.1 |
| **Sway exits** | the `shutdown` event, or the IPC socket closing | core exits 0; `PartOf` stops the rest | [w1-26] |
| **Rail output disappears** (eDP-1 off, lid) | Sway `output` event | the rail exits 69 (no restart loop); core starts the unit again when the output returns | [w1-15 G14], [w1-17 lid binds] |
| **Fullscreen** | `fullscreen_mode` on the rail's output | the rail unit is stopped, then restarted on unfullscreen (S-038) | §6.1 |
| **Theme fragment invalid** | zod fails | keep the last good tokens; one notification; `theme reload` exits 1 with the path; doctor | §10.2 |
| **Config invalid** | zod fails at start | use `config.last-good.json` or the defaults; one notification naming the key | [w1-23] |
| **Spawn failure** (addon load, empty fontconfig panic) | child exit ≠ 0 before ready | supervisor outcome `failed` → CLI exit 1; one toast per minute at most; doctor checks 5 and 7 | [w1-15 §3.8] |
| **Clipboard watcher dies** | child exit | restart with backoff; doctor check 10 | §6.4 |
| **Socket backlog** (a slow subscriber) | over 4 MiB queued | drop the subscriber with `events_lost`; it re-subscribes and gets snapshots | §4.1 |
| **Disk full or state write fails** | write error | log, keep in memory, retry on the next change | §6.5 |
| **Two shells at once** (manual start beside units) | singleton ping answers | the second instance hands its request over and exits 0 | §3.2 |
| **Stale socket from another Sway session** | the session token differs | treated as stale: unlink and bind | §3.2 |
| **notify-send flood** | flood guard | 20/s cap, coalescing, history only | §7.3 |
| **Network model unreachable** (ask) | `discover()` fails | ask shows "model unavailable"; nothing else is affected (off the critical path) | [w1-24] |

What the shell never does to repair itself (Tom's runtime rules):

- restart herdr or the user manager;
- restart Sway;
- kill other users' processes;
- suppress a core dump.

---

## 18. Migration from vicinae and mako (one HM switch, never both)

One commit, one switch on the client:

| # | Change | File |
|---|---|---|
| 1 | Add `home/gpuix-shell.nix` (§13) and import it | `home/home.nix:114` |
| 2 | Gate vicinae, mako and the 7 desktop entries on `!programs.gpuixShell.enable` | `home/vicinae.nix:10` |
| 3 | Enable on the client | `hosts/client/default.nix` beside `:101` |
| 4 | Add the theme fragment `gpuix-shell.json` + `checks.gpuix-shell-themes` | `home/themes/default.nix:242-290`, `flake.nix` |
| 5 | Theme hook: replace `makoctl reload` and `vicinae theme set dotfiles-current` with `gpuix-shell theme reload` guarded by `is-active gpuix-shell-core` | `home/dot_local/bin/theme:83-92` |
| 6 | Change the comment "Vicinae owns clipboard history; do not start a second cliphist watcher" to name gpuix-shell | `home/dot_config/sway/startup.conf:4` |
| 7 | Binds block via `sway-local.conf` (§12); `binds.conf` unchanged | `home/gpuix-shell.nix` |
| 8 | Chrome native host manifest `com.vicinae.vicinae` → our host (XOR with vicinae's link at `vicinae.nix:98-99`) | `home/gpuix-shell.nix` |
| 9 | Overlay, package, checks and `home-profiles` asserts revised | `overlays/default.nix`, `flake.nix:506-536`, `:1074-1379` |
| 10 | Optional: `osd` script calls `gpuix-shell osd <kind> <pct>` and falls back to `notify-send -r` | `home/dot_local/bin/osd:8-12` |
| 11 | `herdr-picker` keeps working. Without the compat codec it needs `gpuix-shell dmenu`; the `$mod+Ctrl+space` bind now opens the native herdr view, and the script is retired once S-063 and S-121 pass (KEYS §8.4) | `home/dot_local/bin/herdr-picker:211-258` |

Order of operations at switch time (systemd and sd-switch do this; nothing is manual):

1. `vicinae.service` and `mako.service` stop, because they are removed from the target.
2. `gpuix-shell-notifications` starts and acquires the name now that mako has released it. If mako
   lingers, the unit exits 69 and the next `systemctl --user start` succeeds.
3. Core and the rail start.

Rollback is setting `programs.gpuixShell.enable = false` and switching: every vicinae and mako line comes
back verbatim, because none were edited.

**Not tonight:** BRIEF says "no deploy tonight". The switch is prepared, evaluated with
`nix flake check --offline --no-build` and a client toplevel build, and left for Tom.

---

## 19. Dependencies, versions and commands

### 19.1 JavaScript (exact pins)

| Package | Version | Role | Notes |
|---|---|---|---|
| `react` | 19.2.0 | UI | exact; GPUIX's reconciler peer [BRIEF A1] |
| `@gpuix/react` | 0.11.0 | JSX intrinsics, reconciler, `render`, `createRenderer`, `startFrameLoop`, headless components | exact, matched with native [w1-03 L5] |
| `@gpuix/native` | 0.11.0 | napi-rs addon over the GPUI fork (+ `@gpuix/native-linux-x64-gnu` 0.11.0 via the lock) | exact; external in the bundle |
| `dbus-next` | 0.10.2 | D-Bus server and client | optional natives `usocket` and `x11` are kept external |
| `zod` | 4.6.7 | config, theme, args and manifest schemas | the scaffold's `^4` resolves to 4.6.7 today; pin it |
| `@openuidev/lang-core` | 1.0.1 | OpenUI parser, streaming parser, prompt generation (ask, P2) | `--ignore-scripts` (postinstall telemetry ping) [w1-24 §5.5] |
| `typescript` (dev) | 5.9.3 | `tsc --noEmit` | |
| `@types/react` (dev) | 19.2.0 | | |
| `@types/bun` (dev) | 1.3.13 | matches the Nix-built bun | the scaffold has 1.4.3 ("latest") |

### 19.2 Toolchain and system tools

| Tool | Version / source | Used by |
|---|---|---|
| bun | 1.3.13 (`pkgs.bun`, nixpkgs e2587cae) for Nix builds and runtime; 1.4.2 (`/home/tom/today/2026-10-14-convergence-soak/build/bun/bin/bun`) for the dev loop | everything |
| node / npm | 24.18.0 / 11.16.0 (`nodejs_24`; dev at `…/build/node/bin/`) | lockfile, `buildNpmPackage` |
| sway / swaymsg | 1.12 (`/nix/store/04g9x522…-sway-1.12`) | the compositor, smokes (swaymsg only in smokes) |
| grim | 1.5.0 | smokes |
| wl-clipboard | nixpkgs | the clipboard watcher (`wl-paste --watch`, `CLIPBOARD_STATE`), copy back (`wl-copy`) |
| libnotify | nixpkgs | `notify-send` for scripts and D-Bus tests |
| fd | nixpkgs | the files provider |
| pipewire (`pw-dump`), wireplumber (`wpctl`) | system | audio status, privacy dots |
| systemd (`systemd-run`, `systemd-inhibit`) | system | app launch scopes, inhibit |
| glib (`gio launch`) | nixpkgs | desktop-entry launch |
| openssh | system | the herdr transport on the Zenbook |
| tailscale | system | the Tailscale status item |
| dbus (`dbus-run-session`) | system | D-Bus tests |
| python3 + fonttools | nixpkgs | smokes; `anthropic-ui-static` build |
| fontconfig | system | font resolution (it must not be empty) |

### 19.3 Commands

All of these run from `pkgs/gpuix-shell`, inside the worktree.

```bash
# enter the toolchain (Nix-pinned) — or use the BRIEF paths for bun 1.4.2 / node 24.18
nix shell --inputs-from ../.. nixpkgs#bun nixpkgs#nodejs_24 nixpkgs#prefetch-npm-deps

# pin and lock (npm writes package-lock.json; bun.lock is git-ignored)
npm install --save-exact --ignore-scripts \
  react@19.2.0 @gpuix/react@0.11.0 @gpuix/native@0.11.0 dbus-next@0.10.2 zod@4.6.7 @openuidev/lang-core@1.0.1
npm install --save-exact --save-dev --ignore-scripts typescript@5.9.3 @types/react@19.2.0 @types/bun@1.3.13
npm ci --ignore-scripts                     # every fresh checkout

# inner loop
bun test                                    # pure logic, fence, registry, schemas
npx tsc --noEmit && bun build.ts            # typecheck + bundle (dist/main.js + chunks)
prefetch-npm-deps package-lock.json         # → npmDepsHash for default.nix

# isolated runs (NEVER against the live session)
../../home/dot_local/bin/runtime-test --render-node /dev/dri/renderD128 -- \
  dbus-run-session --config-file=../../tests/gpuix-shell/dbus-session.conf -- bun test src/platform/dbus src/daemons
../../home/dot_local/bin/runtime-test --render-node /dev/dri/renderD128 -- python3 ../../tests/gpuix-shell/smoke_rail.py

# Nix
cd ../.. && git add -N pkgs/gpuix-shell home/gpuix-shell.nix pkgs/anthropic-ui-static.nix tests/gpuix-shell
nix build .#gpuix-shell                     # runs bun test + install checks
nix flake check --offline --no-build        # eval-time asserts (home-profiles XOR, units, fragments)
nix build .#nixosConfigurations.client.config.system.build.toplevel   # client closure builds
# a dev run of one surface from the checkout, inside the wrapper's headless Sway only:
GPUIX_SHELL_DEV=1 bun src/main.ts daemon rail --output HEADLESS-1
```

Adding a dependency later:

1. `npm install --save-exact --ignore-scripts <pkg>@<ver>`;
2. `prefetch-npm-deps package-lock.json`;
3. update `npmDepsHash`;
4. if the package has native parts, add it to `external` and to the `installPhase` copy list.

---

## 20. Build order for wave 2 (what unblocks what)

1. **Wire contracts first** (pure, testable, no GPU):
   - `core/socket` (NDJSON, error codes, sniff);
   - `core/registry` (+ specs from KEYS §7);
   - `core/theme/schema.ts`, `core/config/schema.ts`;
   - `core/sway-ipc`, `core/herdr`, `core/notifications`;
   - `fence.test.ts`.
2. **Platform adapters:** sway session, socket server and client, fs paths and atomic writes, logging,
   the exec runner, the herdr transport.
3. **CLI** (`src/cli`), plus `main.ts` dispatch and `build.ts` splitting. Measure `ping` ≤ 100 ms.
4. **Core daemon:** hub and topics, supervisor, focus guard, Sway and herdr pollers, status readers,
   clipboard.
5. **Notifications daemon**, with the D-Bus tests (§15.2) green under the wrapper.
6. **`ui/host`** (mount, fonts, theme, core client, keys, exit, ui-tree) and **`ui/kit`** rows, lists,
   footer, echo.
7. **Surfaces in P0 order:** rail → launcher (apps, commands, calc, clipboard, herdr, windows) → toasts
   and OSD → switcher → centre → power → controls (wifi first).
8. **Nix:** `default.nix`, `anthropic-ui-static.nix`, `home/gpuix-shell.nix`, the flake wiring, then
   `nix build` and `flake check`.
9. **Smokes** (§15.3) for each P0 surface, with evidence directories.

---

## 21. OpenUI `ask` (bounded, off the critical path)

`ask` is P2 and must not delay P0 [BRIEF §3.7], [w1-24]. It is an overlay surface using the launcher's
geometry.

**Layout of `src/openui/`:**

| File | Content |
|---|---|
| `spec.ts` | the merged component spec: the vendored `library.spec.json` (`OU/docs/generated/playground-library.spec.json`, 82 components) pruned by `subsetSpec`, plus host components `WorkspaceSlot`, `AgentRow`, `Battery`, `AudioSink`, `NotificationRef` and the action `ShellAction(id, arg?)` |
| `model.ts` | reads `~/.config/gpuix-shell/model.json`, a runtime file and not Nix: `{base:"http://strix:8731", transport, prefer:["qwen3.8-flash-next","halogen-qwen3.8-flash-next"], maxTokens:1500, firstByteTimeoutMs:20000, totalTimeoutMs:90000}` |
| `stream.ts` | the `completionChunks` SSE reader |
| `validate.ts` | `validateAsk` |
| `map.tsx` | ElementNode → `@gpuix/react` JSX |

**Request.**

- `discover()` goes through `/v1/models`. `/health` costs about 1 s, so it is a status hint only.
- Each request sets `stream:true`, `stream_options.include_usage`, `temperature 0`,
  `chat_template_kwargs.enable_thinking=false`.

**Pipeline.**

1. `createStreamingParser(schema, root)`.
2. Partial nodes are inert, and nodes are keyed by `statementId`.
3. Errors are ignored until the stream completes.
4. `validateAsk` checks action ids against the registry, refuses `OpenUrl`, `Set`, `Reset`, `Run`,
   `Query` and `Assign`, and gates buttons on validation.
5. `map.tsx` maps the result to JSX. This is option B, own mapper [w1-24 §6]; `react-lang` is not
   imported.

**Actions.** A `ShellAction` goes through `core/invoke` with `source:"surface"` under the **same registry
gates** as any caller. SECRET and ACTION commands are never offered to the model, which protects the
socket from model output [w1-30 §4.1 10].

**Persistence.** `$XDG_STATE_HOME/gpuix-shell/ask/` holds sessions; `panels/*.openui` holds pinned
programs.

**Environment.** `OPENUI_TELEMETRY_DISABLED=1 DO_NOT_TRACK=1` are set on every unit (§11). There is no
remote fallback, and no test ever dials the model.

**Reference only.** The shared-parity MutationHost adapter (`src/native/adapter.ts` there [w1-14]) is not
imported. BOUNDARY rule 2 forbids importing it; copying it with provenance is allowed if the gallery
needs it.

---

## 22. Conflicts with sibling docs, resolved here

| # | Topic | Sibling says | This file decides | Why |
|---|---|---|---|---|
| C-1 | Socket framing | SCOPE S-002 / KEYS §7.0: 4-byte length + JSON-RPC 2.0 | **NDJSON** JSON-RPC 2.0 as canonical, plus the length framing accepted on the same socket by an unambiguous 3-byte sniff (P1) | the task specifies "JSON lines + verbs"; herdr uses the same newline framing; `herdr-picker` still works with only a path change |
| C-2 | Where the router lives | SCOPE S-002: `shelld` inside the rail | a headless **`gpuix-shell-core`** daemon | `rail hide`/`expand` are process exits; the router must survive GPU faults; the CLI must not depend on a renderer (§3.1) |
| C-3 | Who spawns overlays | SCOPE S-001 rev: "spawned per show by the CLI" | the **core supervisor** spawns them; the CLI only asks | one place for one-exclusive-overlay, focus-loss closing, debounce, the warm spare and logging (§3.3) |
| C-4 | Output of toasts, OSD, launcher, centre, controls, power | DESIGN A-07: every layer surface on eDP-1 | only the **rail and switcher** are pinned to eDP-1 (focus dance); the others open on the focused output | a dance per notification would steal focus during typing; mako and Vicinae open on the focused output [w1-18], [w1-35] |
| C-5 | Directory layering | BOUNDARY §5: `surfaces → platform → core`; task: `src/core` holds sway-ipc, herdr, dbus, socket, logging | both: the pure half in `src/core/<area>`, the I/O half in `src/platform/<area>`; plus `src/ui`, `src/daemons` | satisfies the task's names and BOUNDARY's fence (§2.1) |
| C-6 | `src/core/ui` (BOUNDARY F9) | React components without layer-shell under core | `src/ui/kit` | core must not import react or `@gpuix/*`; the kit is still I/O-free and extractable |
| C-7 | Font bytes | DESIGN §3: "the shell never ships or registers font bytes" | registers **store-generated static instances** of the installed faces | weights 500/600 are impossible otherwise [w1-15 G5]; the bytes stay in the Nix store, never in git |
| C-8 | Binds | KEYS §2: edit `binds.conf` lines 6, 7, 8, 114 | an HM-generated `--no-warn` block appended to `sway-local.conf` | keeps flake-asserted lines; never-both and rollback for free (§12) |
| C-9 | Daemon entry names | KEYS: `notifications toggle` = the centre | daemons start as `gpuix-shell daemon <name>` | no clash between a unit's `ExecStart` and user verbs |

---

## 23. What this pass left unverified

Per the light-verification rule, nothing in this file was run by this pass. It is a design built on the
wave1 measurements. The items below are design-critical and UNVERIFIED; each has a smoke or measurement
listed in §15/§16:

1. `splitting: true` dynamic chunks keep `@gpuix/native` out of the CLI path (§14.2).
2. Bun `Bun.spawn` with `stdin:"ignore"` plus the spawn-payload file, and `surface/ready` timing
   (§3.3).
3. The output-pin focus dance and its SEND_TICK suppression of focus-guard events (§5.1).
4. Focus-loss closing from Sway events while an exclusive layer surface holds the keyboard; the `onBlur`
   backstop (§5.3).
5. `keyboardInteractivity: "on-demand"` for controls (fallback `exclusive`) [w1-15 G11].
6. Swapping the toast window as spawn-new-then-kill-old without visible flicker; the card-height
   estimator against real text (§7.5).
7. `ssh -L` Unix-socket forwarding of the herdr socket, and `ControlMaster` reuse (§6.2).
8. `pw-dump --monitor` as the audio and privacy source (§6.3).
9. bun's SQLite having FTS5 (§6.4).
10. HM `xdg.configFile."sway-local.conf".text` concatenating with `lib.mkAfter` (§12).
11. fontTools instancing plus the name-table fix producing faces that `registerFont` accepts with the
    family "Anthropic Sans" (§10.3).
12. Live re-application of a changed `GpuixTheme` (§10.2).
13. Memory of the headless daemons (no figure measured) and of each surface under 0.11 on the Zenbook
    (§3.1).
14. The D-Bus activation file being honoured by the user bus on the client (§7.1).
15. The 3-byte sniff (pure logic, unit-testable; not yet written).
