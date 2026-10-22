# gpuix-shell — PLAN (wave 2 build, wave 3 integrate + complete + test)

Written by the planner on 2026-10-21 (Tom offline; nothing here asks him anything). It is the build
plan for `pkgs/gpuix-shell/`, `home/gpuix-shell.nix`, `tests/gpuix-shell/` and `docs/gpuix-shell/`
on branch `experimental/gpuix-shell` (worktree `/home/tom/.wt/dotfiles/gpuix-shell`). Every builder
reads `BRIEF.md` plus the five syntheses (`SCOPE.md`, `DESIGN.md`, `ARCHITECTURE.md`, `KEYS.md`,
`BOUNDARY.md`) and then **only its own packet below plus §1–§4 of this file**. Where a synthesis
disagrees with another, `ARCHITECTURE.md §22` rules (NDJSON JSON-RPC on `shell.sock`, a headless
`gpuix-shell-core` daemon, the core supervisor spawns overlays, HM-generated bind block); for keys
`KEYS.md` rules; for pixels `DESIGN.md` rules; for the feature list `SCOPE.md` rules.

## 1. Standing rules for every packet

- Work only inside `/home/tom/.wt/dotfiles/gpuix-shell`. Never touch `/home/tom/mecattaf/dotfiles`.
  `cd` into the worktree for every command; use absolute paths.
- Toolchain (absolute): `BUN=/home/tom/today/2026-10-14-convergence-soak/build/bun/bin/bun` (1.4.2),
  `NPM=/home/tom/today/2026-10-14-convergence-soak/build/node/bin/npm` (11.16, node 24.18). Never run
  `bun install`/`npm install` after the scaffold except the Nix packet (P-19) and only via
  `$NPM install --save-exact --ignore-scripts`; a new dependency is a BUILD-LOG request to P-19.
- Tests: pure logic is `*.test.ts` beside the code, run with `$BUN test <files>` from `pkgs/gpuix-shell`.
  Anything that opens a compositor, a D-Bus bus, a socket in `$XDG_RUNTIME_DIR`, or spawns daemons runs
  **only** under `home/dot_local/bin/runtime-test --render-node /dev/dri/renderD128 -- …`
  (the wrapper copy in this branch has `--render-node`; the installed one does not). Never against the
  live Sway, herdr, the user manager or `strix:8731`. Never suppress a core dump. Smokes are
  `tests/gpuix-shell/smoke_<surface>.py` (never `test_*.py`); hermetic unittest is `tests/gpuix-shell/test_*.py`.
- Typecheck your own files with `$BUN x tsc --noEmit -p .`; errors in files you do not own are noted
  in BUILD-LOG, not fixed.
- Commit nothing. Append, never rewrite, `docs/gpuix-shell/ASSUMPTIONS.md` (one line per decision,
  prefixed `P-nn:`) and `docs/gpuix-shell/BUILD-LOG.md` (a `## P-nn <title>` block at the end: done /
  not done / untested, test counts, requests for other packets under `### Requests for P-mm`).
  Never claim a test ran if it did not; "unverified" is a valid word.
- Verification is light by standing rule: one builder, one self-check, no critique loops. Log what
  was left unverified.
- No secrets in git, no font bytes in git, no timers/OnCalendar in dotfiles, no `herdr workspace focus`,
  no key grabbing, SECRET values never on `shell.sock`/argv/logs, `src/core` imports no I/O (fence).

## 2. Stages and scheduling

| Stage | Packets | Runs | Notes |
|---|---|---|---|
| `scaffold` | P-00 | alone, first | creates every seam file and stub; proves `@gpuix/native` 0.11.0 opens a layer surface under the harness |
| `build` | P-01 … P-23 (23 packets) | in parallel after P-00, 16 at a time | each owns disjoint paths; code against §4 and the scaffold stubs |
| `integrate` | P-30 | alone, after every build packet | typecheck + `bun test` green, seams wired, `bun build.ts` splits, `gpuix-shell ping` works |
| `complete` | P-31 … P-51 (21 packets) | in parallel after P-30 | smokes, P1 features, Nix build, docs; same path owners as wave 2 |
| `deliver` | P-52 | alone, last | final integrate, MORNING.md, logical commits, push, draft PR |

Suggested first 16 of `build` (the ones most others code against): P-01, P-02, P-03, P-04, P-05,
P-06, P-07, P-08, P-09, P-10, P-11, P-13, P-14, P-15, P-19, P-22; then P-12, P-16, P-17, P-18,
P-20, P-21, P-23.

## 3. File ownership rules and seam files

1. **A path has exactly one owner per stage.** The ownership table (§5) and each packet's
   `owner_paths` are the law; globs are relative to the worktree root. Wave-3 owners equal wave-2
   owners for the same paths, so no two parallel agents ever edit one file.
2. **Seam files are created by P-00 with their final import lists and are never edited again**
   (except by P-30/P-52 during integrate/deliver): `pkgs/gpuix-shell/src/main.ts`,
   `src/surfaces/index.ts`, `src/daemons/index.ts`, `src/core/registry/specs/index.ts`,
   `src/daemons/core/handlers/index.ts`, `src/surfaces/launcher/providers/index.ts`,
   `src/items/index.ts`, `package.json`, `tsconfig.json`, `build.ts`.
3. **Stubs are replaced in place.** P-00 writes a stub at every path a seam imports (a `main.tsx` that
   logs `not built` and exits 69; an empty `specs: CommandSpec[] = []`; an empty providers list). The
   owner packet overwrites the stub with the real module, keeping the **same default/named exports**
   the seam imports (§4.1). Never rename or move a seam-imported file.
4. **Frozen files**: `src/launcher/provider.ts` (the LauncherProvider contract) and the music
   contracts `src/music/{types,errors,config,format}.ts`, `src/music/subsonic/{types,api,map}.ts`
   are read-only for everyone except P-23 (music), who may only append.
5. **Cross-packet needs** go into BUILD-LOG under `### Requests for P-mm`; P-30 applies them.
   If you need a function another packet owns and it does not exist yet, code against the §4
   signature and test with a local stub inside your own test file.
6. `docs/gpuix-shell/ASSUMPTIONS.md` and `BUILD-LOG.md` are append-only shared files (rule 1 does
   not apply to appends). `NIGHT-LOG.md` is the orchestrator's.

## 4. Seam contract (what every packet may rely on)

### 4.1 Process entry and dispatch (`src/main.ts`, written by P-00)

`gpuix-shell <argv…>` dispatches on `argv[2]` with **dynamic `import()`** so CLI calls never load the
52 MB addon (`build.ts` uses `splitting: true`; P-30 verifies `grep -c '^import .*@gpuix' dist/main.js` is 0):

| argv | module loaded (owner) |
|---|---|
| `daemon core` | `src/daemons/core/main.ts` (P-06) |
| `daemon notifications` | `src/daemons/notifications/main.ts` (P-11) |
| `daemon rail [--output X] [--collapsed\|--expanded]` | `src/surfaces/rail/main.tsx` (P-08) via `src/surfaces/index.ts` |
| `surface <name>` | `src/surfaces/<name>/main.tsx` via `src/surfaces/index.ts`; names: `rail toasts osd launcher switcher center controls power cheatsheet files ask gallery` |
| `native-host` | `src/daemons/native-host/main.ts` (P-10) |
| `music …` | `src/music/cli.ts` `runMusicCli(argv)` (P-23) |
| `--check-native`, `--check-dbus`, `--check-theme <file>` | pre-socket self-checks: print `{"ok":true,…}` and exit 0, else exit 1 |
| anything else | `src/cli/main.ts` `runCli(argv)` (P-05) |

Daemon and surface entry modules export `default async function main(argv: string[]): Promise<void>`.
`src/surfaces/index.ts` exports `SURFACES: Record<SurfaceName, () => Promise<{default: (argv: string[]) => Promise<void>}>>`.

### 4.2 Socket protocol (`shell.sock`, ARCHITECTURE §4)

NDJSON, one JSON-RPC 2.0 message per line, at `$XDG_RUNTIME_DIR/gpuix-shell/shell.sock` (dir 0700, socket
0600). Method = `<domain>/<verb>` ↔ registry id `<domain>.<verb>`. Request params:
`{args, source: "cli"|"bind"|"launcher"|"rail"|"dbus"|"script"|"test"|"surface", tty, cwd, session}`.
Result `{outcome:"confirmed"|"failed"|"unknown", echo?, data?, undo?}`. Errors: `-32000 failed`→exit 1,
`-32001 refused`→1, `-32700/-32600/-32601/-32602`→2, `-32003 not-running`→3, `-32002 unavailable`→69;
`error.data.kind` ∈ `NOT_FOUND NOT_INITIALIZED NOT_SUPPORTED PERMISSION_DENIED INVALID_PARAMS TIMEOUT BUSY CANCELLED INTERNAL`.
Built-ins: `core/hello {role,name,pid,protocol:1}` → `{protocol,version,session}`; `core/subscribe {topics[]}`
→ current snapshots, then `{"method":"state","params":{topic,rev,value}}` notifications;
`core/invoke {id,args,source}`; `surface/ready {surface,nonce,pid}`, `surface/closing`, `surface/closed {reason}`;
`service/register {name,methods[]}`, `service/publish {topic,value}`; `core/ping`, `core/version`.
Replies are routed per (connection, id). Per-surface sockets `<name>.sock` accept `ping`, `close`,
`update {args}`, `ui-tree` (returns `renderer.getAutomationTree()`), and `osd/update` for the OSD.
Session token = `sha256($SWAYSOCK).slice(0,16)`. Limits: request line 16 KiB; `dmenu/select/clipboard/browser` 1 MiB; subscriber backlog 4 MiB → `events_lost`.

### 4.3 Topics (`core/state/shell-state.ts`, P-05)

`sway` (SwayModel), `slots` (Slot[1..10]), `herdr` ({status, since, snapshotDigest}), `theme`
({name, polarity, rev, tokens}), `overlays` ({open: SurfaceName[]}), `notifications` ({unread, dnd,
newest: Notification[≤50]}), `clipboard` (top 50 rows, metadata only), `network`, `bluetooth`, `audio`,
`battery`, `media`, `tailscale`, `status` (keyed statuses), `apps` (index digest + count), `tabs`,
`music` (PlayerState). Producers push **full snapshots**; the hub diffs and bumps `rev`.

### 4.4 Exports each area must provide (owners in §5)

- `core/socket`: `encodeLine(msg)`, `class NdjsonDecoder {push(buf): Message[]}`, `sniffFraming(first3: Uint8Array): "ndjson"|"frame"`, `ErrorCode`, `exitCodeFor(code)`, `LIMITS`, `compat-frame.ts` `{encodeFrame, decodeFrame}` (P-05).
- `core/registry`: `CommandSpec`, `VerbClass`, `Owner`, `InvokeRequest`, `InvokeResult`, `createRegistry(specs)` → `{get(id), list(filter?), byCli(path[])}`, `idToMethod`, `methodToId`, `parseArgv(registry, argv)` → `{id, args, flags:{json,source,hud,yes}}` | `UsageError`, `specs/index.ts` `allSpecs` (P-05). Each domain's specs file `specs/<domain>.ts` exports `const specs: CommandSpec[]` (owner = that domain's packet).
- `core/config`: `ConfigSchema` (zod), `Config`, `defaultConfig()`, `parseConfig(json)`; `core/logging`: `log(level, event, fields?)`, `redact(fields)`; `core/state`: `Topic`, `TopicValue<T>`, `createHub()` (pure: `publish(topic, value)` → `{changed, rev}`); `platform/fs`: `xdg()` → `{config, state, cache, runtime}`, `writeAtomic(path, bytes, mode)`, `readVersionedJson(path, schema)`; `platform/exec`: `run(argv, {timeoutMs, maxBytes, env})`, `spawnSurface(name, payload)`, `launchDesktop(path)`; `platform/socket`: `createServer(path, onMessage)`, `connectCore(opts)` → `CoreClient {hello, invoke, subscribe(topics, onState), close}`; `cli/main.ts` `runCli(argv)` (P-05).
- `core/sway-ipc`: `MessageType`, `EVENT_NAMES`, `encodeMessage(type, payload)`, `class SwayDecoder`, `SwayModel`, `deriveModel({tree, workspaces, outputs})`, `quoteWorkspaceName(name)` (throws on reserved/forbidden), `Coalescer(ms)`; `platform/sway`: `createSwaySession({socketPath})` → `{command(cmd), query(type), on(event), focusWorkspace(n)` (verify-after-switch) `, focusContainer(conId), pinOutput(name)` → restore fn, `close()}`, `fake-server.ts` `startFakeSway(fixtures)` (P-01).
- `core/herdr`: `HerdrSnapshot`, `AgentStatus`, `STATUS_RANK`, `glyphFor(status)`, `wordFor(status)`, `parseMarks(marks: string[])`, `joinSlots(sway, herdr, lastVisited)` → `Slot[]`, `class AttentionDetector`, `class Mru(cap=120)`; `platform/herdr`: `createHerdrTransport(mode)` → `{snapshot(), subscribe(onWake), close()}`, `createPoller(transport, onSnapshot)` (P-02).
- `core/dbus`: `NOTIFICATIONS` constants (caps, hints, close reasons, limits), `sanitizeMarkup(s)`, `imageDataToPng(iiibiiay)`, interface/member tables for NM, BlueZ, UPower, logind, MPRIS, PPD, wl-gammarelay and model types `NetworkState`, `BluetoothState`, `BatteryState`, `MediaState`, `PowerProfileState`; `platform/dbus`: `getBus("session"|"system")` (reconnecting), `watchUPower(onState)`, `watchNetworkManager(...)` + `nmConnect(ssid, psk)` (D-Bus settings dict, never argv), `watchBlueZ(...)` + `bluezAgent`, `watchMpris(...)`, `logind` (`prepareForSleep(on)`, `powerOff()`, `reboot()`, `terminateSession()`), `platform/audio` `watchPipewire(onState)` + `wpctl`, `platform/tailscale` `readTailscale()` (P-03).
- `core/theme`: `ThemeSchema`, `Theme`, `parseTheme(json)`, `toGpuixTheme(theme)`, `NOIR` (a complete literal for tests); `core/fonts`: `FAMILIES`, `faceFor(weight)`; `platform/theme`: `watchThemePointer(onChange)`, `loadThemeFile(path)`; `platform/fonts`: `staticFaces()` → `{family, weight, bytes}[]` (P-04).
- `ui/host`: `mountSurface(spec: SurfaceSpec, node)`, `SurfaceSpec` (`{name, daemon?, window: WindowOptions, tabNavigation?}`), `readSpawnPayload()`, `exitSurface(code, reason)`, `normalizeKey(e)` → Keystroke, `useTokens()`, `useTopic<T>(topic)`, `useInvoke()`, `useKeymap(table)`, `serveUiTree(renderer, socketPath)`, `ErrorBoundary`; `ui/kit`: `Row`, `Section`, `SearchField`, `VirtualRows`, `ActionPanel`, `Footer`, `Echo`, `Glyph`, `Dot`, `ToastCard`, `ProgressFill`, `HoldToConfirm`, `Dialog`, `Keycap`, `Metadata`, `Empty`, `Switch`, `Slider`, `PasswordField` (P-07).
- `daemons/core`: `main`, `createHub`, `createSupervisor`, `focusGuard`, `handlers/index.ts` (aggregates `handlers/<domain>.ts` each exporting `handlers: Record<id, Handler>`) (P-06; domain handler files by domain owners).
- `core/notifications`: `NotificationStore`, `applyRules`, `FloodGuard`, `routeOsd`, `estimateCardHeight`, `historyCodec` (P-11); `daemons/notifications/main.ts` (P-11).
- `surfaces/launcher/providers/index.ts` exports `PROVIDERS: Array<() => LauncherProvider>` in a fixed order: apps, commands, windows, workspaces, calc, clipboard, files, tabs, emoji, wifi, bluetooth, audio, theme, notifications, music, cheatsheet, shell, dmenu. Each provider file exports `createProvider(deps): LauncherProvider` (owners in §5).
- `src/items/index.ts` exports `ITEMS: Record<string, () => RailItem>` where `RailItem = {id, topic?, render(props: {collapsed, tokens}): ReactNode, onClick?, onAuxClick?, onScroll?}`; rail reads `config.rail.items` order (P-08 defines `RailItem` in `surfaces/rail/item.ts`; P-00 stubs it).

### 4.5 Surfaces, geometry, testIds

Surface names and layer-shell options are ARCHITECTURE §5.1 verbatim; tokens come from `useTokens()`
and never from hex literals (design-lint test). testIds are `<surface>.<part>.<id>` (`rail.slot.3`,
`launcher.row.apps:org.gnome.Nautilus`, `launcher.input`, `toasts.card.<id>`, `power.row.reboot`).
Every surface answers `ui-tree` on its socket. Every surface root sets `fontFamily`, `color`,
`backgroundColor`, `fontSize` from tokens.

### 4.6 Test layout (`tests/gpuix-shell/`, P-00 + P-22)

`harness.py` exports `Harness` (`with Harness(outputs=1|2, scale=1|2, dbus=False) as h:` → `h.env`,
`h.swaymsg(...)`, `h.grim(path)`, `h.pixel(path, x, y)`, `h.workspace_rect()`, `h.spawn(argv)`,
`h.wait(fn, label)`, `h.evidence` dir; re-execs itself under `runtime-test --render-node` when not
inside; refuses a live runtime). `driver.mjs` wraps `@gpuix/native/automation` (`launch`, `getByTestId`,
`fill`, `press`, `click`, `textContent`). Fixtures under `fixtures/`. A fake `herdr` and fake `swaymsg`
under `bin/`. Each smoke writes `results.json` and evidence under `docs/gpuix-shell/evidence/<smoke>/`.

## 5. Ownership table (path → owner; wave 3 keeps the same owners)

| Path (under `pkgs/gpuix-shell/` unless rooted) | Wave 2 | Wave 3 |
|---|---|---|
| `package.json package-lock.json tsconfig.json build.ts .gitignore src/main.ts src/fence.test.ts` and all seam files of §3.2 | P-00 | P-30 / P-52 |
| `src/core/sway-ipc/** src/platform/sway/**` | P-01 | P-31 |
| `src/core/herdr/** src/platform/herdr/**` | P-02 | P-31 |
| `src/core/dbus/** src/platform/dbus/** (except notifications-server.ts) src/platform/audio/** src/platform/tailscale/**` | P-03 | P-37 |
| `src/core/theme/** src/core/fonts/** src/platform/theme/** src/platform/fonts/** home/themes/default.nix` | P-04 | P-33 |
| `src/core/registry/** (except specs/<domain>.ts) src/core/socket/** src/core/config/** src/core/logging/** src/core/state/** src/platform/socket/** src/platform/fs/** src/platform/exec/** src/platform/state/** src/cli/**` | P-05 | P-48 |
| `src/daemons/core/** (except handlers/<domain>.ts)` | P-06 | P-31 |
| `src/ui/**` | P-07 | P-45 |
| `src/surfaces/rail/** src/core/registry/specs/rail.ts src/daemons/core/handlers/rail.ts` | P-08 | P-33 |
| `src/surfaces/launcher/** (except providers/{clipboard,files,tabs,emoji,wifi,bluetooth,audio,music}.ts) src/core/launcher/** src/core/apps/** src/platform/apps/** src/core/scripts/** specs/launcher.ts specs/dmenu.ts handlers/launcher.ts` | P-09 | P-34 |
| `src/surfaces/launcher/providers/{clipboard,files,tabs,emoji}.ts src/core/clipboard/** src/platform/clipboard/** src/platform/chrome/** src/daemons/native-host/** data/glyphs.json specs/clipboard.ts handlers/clipboard.ts` | P-10 | P-35 (clipboard) / P-42 (tabs) |
| `src/core/notifications/** src/platform/dbus/notifications-server.ts src/daemons/notifications/** src/surfaces/toasts/** src/surfaces/center/** specs/notifications.ts` | P-11 | P-32 / P-39 |
| `src/surfaces/osd/** specs/osd.ts` | P-12 | P-38 |
| `src/surfaces/switcher/** specs/switcher.ts specs/sway.ts handlers/sway.ts` | P-13 | P-36 |
| `src/surfaces/controls/** src/surfaces/launcher/providers/{wifi,bluetooth,audio}.ts specs/controls.ts handlers/controls.ts` | P-14 | P-37 |
| `src/surfaces/power/** specs/power.ts handlers/power.ts` | P-15 | P-38 |
| `src/surfaces/files/** src/core/files/** specs/files.ts` | P-16 | P-40 |
| `src/surfaces/cheatsheet/** src/core/cheatsheet/** src/items/{sysmon,capacity,calendar}/** specs/cheatsheet.ts specs/status.ts handlers/status.ts` | P-17 | P-46 |
| `src/openui/** src/surfaces/ask/** src/surfaces/gallery/** specs/ask.ts` | P-18 | P-45 |
| `pkgs/gpuix-shell/default.nix pkgs/anthropic-ui-static.nix home/gpuix-shell.nix flake.nix overlays/default.nix home/home.nix home/vicinae.nix hosts/client/default.nix` | P-19 | P-41 |
| `home/gpuix-shell-binds.nix home/gpuix-shell-entries.nix home/dot_local/bin/{osd,theme,herdr-picker,gpuix-notify} home/dot_config/sway/startup.conf` | P-20 | P-47 |
| `docs/gpuix-shell/{README,RUNBOOK,MORNING}.md` | P-21 | P-48 |
| `tests/gpuix-shell/** (except harness.py, smoke_hello.py, hello/, music/)` | P-22 | smoke owners per surface (P-31…P-40, P-42) |
| `src/music/** src/surfaces/launcher/providers/music.ts tests/gpuix-shell/music/** docs/gpuix-shell/music/**` | P-23 | P-43 |
| `src/extensions/**` (extension host) | — | P-44 |
| `docs/gpuix-shell/GAPS.md docs/gpuix-shell/PERF.md docs/gpuix-shell/SECURITY.md docs/gpuix-shell/REPORT.md` | — | P-51 / P-49 / P-50 / P-52 |

## 6. Packets
Owner-path globs are relative to the worktree root; a leading `!` excludes a sub-path from the packet's ownership (it belongs to the packet named in §5). Word counts are of the brief alone.

## 6.1 Stage scaffold (runs alone, first)

### P-00 — Scaffold: package, dispatcher, seams, stubs, harness, hello layer-shell smoke
- **stage**: `scaffold`  
- **depends_on**: —  
- **owner_paths**:
  - `pkgs/gpuix-shell/package.json`
  - `pkgs/gpuix-shell/package-lock.json`
  - `pkgs/gpuix-shell/tsconfig.json`
  - `pkgs/gpuix-shell/build.ts`
  - `pkgs/gpuix-shell/.gitignore`
  - `pkgs/gpuix-shell/default.nix`
  - `pkgs/gpuix-shell/src/main.ts`
  - `pkgs/gpuix-shell/src/fence.test.ts`
  - `pkgs/gpuix-shell/src/surfaces/index.ts`
  - `pkgs/gpuix-shell/src/daemons/index.ts`
  - `pkgs/gpuix-shell/src/core/registry/specs/index.ts`
  - `pkgs/gpuix-shell/src/daemons/core/handlers/index.ts`
  - `pkgs/gpuix-shell/src/surfaces/launcher/providers/index.ts`
  - `pkgs/gpuix-shell/src/items/index.ts`
  - `pkgs/gpuix-shell/src/core/*/index.ts`
  - `pkgs/gpuix-shell/src/platform/*/index.ts`
  - `pkgs/gpuix-shell/src/ui/host/index.ts`
  - `pkgs/gpuix-shell/src/ui/kit/index.ts`
  - `pkgs/gpuix-shell/src/surfaces/*/main.tsx`
  - `pkgs/gpuix-shell/src/surfaces/rail/item.ts`
  - `pkgs/gpuix-shell/src/daemons/*/main.ts`
  - `pkgs/gpuix-shell/src/cli/main.ts`
  - `pkgs/gpuix-shell/src/core/registry/specs/*.ts`
  - `pkgs/gpuix-shell/src/daemons/core/handlers/*.ts`
  - `pkgs/gpuix-shell/src/surfaces/launcher/providers/*.ts`
  - `tests/gpuix-shell/harness.py`
  - `tests/gpuix-shell/smoke_hello.py`
  - `tests/gpuix-shell/hello/**`
  - `tests/gpuix-shell/README.md`
  - `docs/gpuix-shell/BUILD-LOG.md`
  - `home/dot_local/bin/runtime-test`
- **brief** (382 words):

Runs alone before every build packet; everything it creates is a seam (§3) that later packets replace in place but never move.
1. `package.json` exactly as ARCHITECTURE §14.1 (version 0.1.0; deps `@gpuix/native 0.11.0`, `@gpuix/react 0.11.0`, `dbus-next 0.10.2`, `react 19.2.0`, `zod 4.6.7`, `@openuidev/lang-core 1.0.1`; dev `@types/bun 1.3.13`, `@types/react 19.2.0`, `typescript 5.9.3`; scripts build/test/typecheck). `rm bun.lock`; `.gitignore` adds `bun.lock` and `result`. Generate the lock with `$NPM install --package-lock-only --ignore-scripts`, then `$NPM ci --ignore-scripts` (node_modules for everyone; nobody re-installs). `tsconfig.json`: keep the existing one, add `build.ts` to `include`.
2. `build.ts` (ARCHITECTURE §14.2, `splitting: true`, externals `@gpuix/native`, `@gpuix/native/*`, `usocket`, `x11`). `src/main.ts` = the §4.1 dispatcher with the three `--check-*` modes (`--check-theme` imports `platform/theme/loadThemeFile`).
3. Seam files with final import lists: `surfaces/index.ts` (12 names), `daemons/index.ts`, `core/registry/specs/index.ts` (domains: core, rail, launcher, dmenu, clipboard, notifications, osd, switcher, sway, controls, power, files, cheatsheet, status, ask, music, theme, herdr), `daemons/core/handlers/index.ts` (same domains), `surfaces/launcher/providers/index.ts` (18 providers, §4.4 order), `items/index.ts` (clock, battery, network, bluetooth, audio, bell, tailscale, media, pomodoro, recording, privacy, touchpad, sysmon, capacity, calendar, custom).
4. Stubs: one `index.ts` per `core/<area>` and `platform/<area>` of ARCHITECTURE §2.2 exporting the §4.4 **types** (full TypeScript interfaces, copied from §4.4 and ARCHITECTURE §9.1/§8) and functions that `throw new Error("P-nn not built")`; `surfaces/<name>/main.tsx` stubs exit 69 with `not built`; empty `specs: []`, `handlers: {}`, provider stubs returning a provider whose `search` yields an `empty` section "not built". `ui/kit/index.ts` and `ui/host/index.ts` export typed stubs. `surfaces/rail/item.ts` exports `RailItem`.
5. `fence.test.ts`: the ARCHITECTURE §2.1 import-glob table as a passing `bun test` (regex over import specifiers per glob).
6. `tests/gpuix-shell/harness.py` (§4.6; merge of `docs/gpuix-shell/evidence/rail-probe/smoke.py` and wave1/21 §5.6: gles2, `WLR_RENDER_DRM_DEVICE`, LD_LIBRARY_PATH from the `/nix/store` globs listed in BRIEF §5, `VK_ICD_FILENAMES` radeon, `XDG_CURRENT_DESKTOP=sway-physical`, outputs 1 or 2, scale 1 or 2, optional `dbus-run-session`, live-runtime refusals) and `smoke_hello.py` + `hello/hello.tsx` (the rail probe rewritten to `mountSurface`-free plain `render`, 56 px, exclusive zone): run it under `runtime-test --render-node /dev/dri/renderD128`; it must report `workspace_rect.x == 56` and a grim pixel; save `results.json` to `docs/gpuix-shell/evidence/hello/`.
7. `default.nix` skeleton = ARCHITECTURE §14.3 with `npmDepsHash = lib.fakeHash` (P-19 completes it). `docs/gpuix-shell/BUILD-LOG.md` with the header and your block. Acceptance: `$BUN x tsc --noEmit -p .` clean, `$BUN test` green (fence + music format tests), `$BUN build.ts` succeeds, `bun src/main.ts --check-native` prints ok under the harness env, smoke_hello passes. Record measured numbers; never claim the smoke ran if it did not.

## 6.2 Stage build (parallel, 16 at a time)

### P-01 — core/sway-ipc + platform/sway: i3-ipc client, model derivation, fake server
- **stage**: `build`  
- **depends_on**: P-00  
- **owner_paths**:
  - `pkgs/gpuix-shell/src/core/sway-ipc/**`
  - `pkgs/gpuix-shell/src/platform/sway/**`
  - `tests/gpuix-shell/fixtures/sway/**`
- **brief** (292 words):

Build SCOPE S-004/S-015 and ARCHITECTURE §6.1 as pure core plus a platform adapter. Core (`src/core/sway-ipc/`, no I/O): `frame.ts` (`encodeMessage(type, payload)` with the 14-byte `i3-ipc` header, `MessageType` enum incl. SUBSCRIBE=2, GET_TREE, GET_WORKSPACES, GET_OUTPUTS, SEND_TICK, `EVENT_NAMES`, bit-31 event flag), `decode.ts` (`SwayDecoder.push(Buffer): Message[]` tolerant of headers split across chunks, 1 MiB guard), `model.ts` (`Output`, `Workspace`, `Con`, `SwayModel {outputs, focusedOutput, workspaces, focusedWorkspace, urgent, fullscreenByOutput, windows, marksByCon}`), `derive.ts` (`deriveModel({tree, workspaces, outputs})` walking `nodes` + `floating_nodes`, app_id/`window` for Xwayland, marks collected per con), `quote.ts` (`quoteWorkspaceName` rejecting `" \ $ ; ,`, control chars, DEL, leading `--`, the reserved words `number next prev current back_and_forth next_on_output prev_on_output`), `coalesce.ts` (`Coalescer(40)`). Platform (`src/platform/sway/`): `ipc-client.ts` (one `node:net` connection, request queue, reply matching), `session.ts` `createSwaySession({socketPath = $SWAYSOCK})` with **two** connections (command + event), subscribe `["workspace","window","output","mode","binding","shutdown","tick"]` **before** the first query, 40 ms coalescing into one GET_TREE+GET_WORKSPACES+GET_OUTPUTS batch, `focusWorkspace(n)` = `workspace number n` then wait ≤500 ms for the matching `workspace` focus event or re-query, returning `confirmed|failed|unknown`; `focusContainer(conId)`; `tickBarrier(payload)` (SEND_TICK and wait for the echoed tick); reconnect backoff 250 ms→10 s with full resync; `reload` event → resync; `shutdown` → `onShutdown`. `output-pin.ts`: `pinOutput(session, name)` records focused output + con, `focus output <name>`, returns `restore()` that re-focuses `[con_id=N]` and marks the tick barrier so the focus guard ignores the dance. `fake-server.ts`: `startFakeSway(fixtures, {socketPath})` replaying recorded replies and emitting events on demand (for P-06 and P-31). Fixtures: copy `live-client-sway-tree.json` and `zenbook-0221-*.json` (paths in ARCHITECTURE §15.4) under `tests/gpuix-shell/fixtures/sway/` with a provenance comment. Tests: `frame.test.ts` (`encodeMessage(0,'exit')` bytes vs the man page), `decode.test.ts` (split chunks, event flag), `derive.test.ts` on both fixtures (nine workspaces, focused, marks), `quote.test.ts` (the 26 cases from wave1/08 `platform.ts`, reconstructed), `session.test.ts` against the fake server (subscribe-before-query, coalescing 4 events → 1 batch, verify-after-switch, reconnect). No compositor needed. Acceptance: all green with `$BUN test src/core/sway-ipc src/platform/sway`; fence passes.

### P-02 — core/herdr + platform/herdr: snapshot poller, marks, slots, attention, MRU
- **stage**: `build`  
- **depends_on**: P-00  
- **owner_paths**:
  - `pkgs/gpuix-shell/src/core/herdr/**`
  - `pkgs/gpuix-shell/src/platform/herdr/**`
  - `pkgs/gpuix-shell/src/core/registry/specs/herdr.ts`
  - `pkgs/gpuix-shell/src/daemons/core/handlers/herdr.ts`
  - `tests/gpuix-shell/fixtures/herdr/**`
  - `tests/gpuix-shell/bin/herdr`
- **brief** (312 words):

Build SCOPE S-005, S-109, S-190–S-192 and ARCHITECTURE §6.2 (read-only herdr; the shell never focuses, spawns or closes herdr work). Core (`src/core/herdr/`): `types.ts` (`HerdrSnapshot` per wave1/16 §5.1: workspaces with id, name, label, slot, seat, status, agents[], stateChangeSeq, bootId, optional report-metadata), `status.ts` (`AgentStatus = "idle"|"working"|"blocked"|"done"|"unknown"`, open-ended strings map to unknown; `STATUS_RANK` blocked 0 < done 1 < working 2 < idle 3 < unknown 4; `glyphFor` ◉ ◐ ● ✓ ○; `wordFor` Needs input / Working / New activity / Ready / Unknown), `marks.ts` (`parseMarks(marks[])` for `herdr-slot-N`, `herdr-label-<seat>-slot-N-<hex6>`, `herdr-closed-<ns>`, `herdr-name-<hex>`, `herdr-workspace-<id>`; the label's slot number is history, exposed as `madeInSlot`), `slots.ts` (`joinSlots(swayModel, herdrModel, lastVisited)` → `Slot[1..10]` `{n, swayName, focused, urgent, visible, projector?: conId, herdr?: {workspaceId, label, name, status, agents, age, madeInSlot?}, mirrorsSlot?, unverified, lastVisited}`: collapsed projector detection, mirrored duplicates "Mirrors slot N", `done` cleared when visited), `attention.ts` (`AttentionDetector.feed(snapshot, now)` → episodes on a transition into `blocked` or a `stateChangeSeq` advance while blocked; baseline after an outage raises nothing), `mru.ts` (`Mru` cap 120, "current never first", atomic-save shape). Platform (`src/platform/herdr/`): `transport.ts` interface `{snapshot(): Promise<Buffer>, subscribe(onWake), close()}`; `local-socket.ts` (NDJSON `session.snapshot` + `events.subscribe` on `~/.config/herdr/herdr.sock`); `ssh-forward.ts` (`ssh -N -o BatchMode=yes -o ExitOnForwardFailure=yes -L $XDG_RUNTIME_DIR/gpuix-shell/herdr.sock:/home/tom/.config/herdr/herdr.sock strix`, backoff 250 ms→10 s); `ssh-exec.ts` (`herdr api snapshot` over ssh, 6 s timeout, ControlMaster); `cli-exec.ts` (`herdr api snapshot` locally when `herdr` is on PATH — the test path); `poller.ts` (`createPoller(transport, onSnapshot, {coalesceMs: 300, floorMs: 3000})`: wake-ups from events, Sway events (injected), surface/ready; byte-identical reads dropped; two failures → `{status:"unavailable", since}`). `specs/herdr.ts`: `herdr.new/restore/rename/close` (exec `herdr-chord new`, `sway-workspace restore|rename|close`; close ACTION two-step) and `herdr.list` READ. `handlers/herdr.ts` runs them through `platform/exec`. Fake: `tests/gpuix-shell/bin/herdr` (Python) prints `tests/gpuix-shell/fixtures/herdr/<name>.json` chosen by `HERDR_FAKE_SNAPSHOT`; fixtures: copy `live-herdr-snapshot.json` (provenance comment) plus hand-made `blocked.json`, `mirrored.json`, `closed.json`, `nometa.json`. Tests: marks (label repeats, closed, strix seat), slots (nine-slot join, collapsed, mirrored, missing metadata renders nothing), attention table, MRU, poller (fake transport: coalescing, identical bytes, unavailable after 2 failures). Acceptance: `$BUN test src/core/herdr src/platform/herdr` green.

### P-03 — core/dbus + platform/dbus: UPower, logind, NetworkManager, BlueZ (+Agent1), MPRIS, PPD, PipeWire, Tailscale readers
- **stage**: `build`  
- **depends_on**: P-00  
- **owner_paths**:
  - `pkgs/gpuix-shell/src/core/dbus/**`
  - `pkgs/gpuix-shell/src/platform/dbus/**`
  - `!pkgs/gpuix-shell/src/platform/dbus/notifications-server.ts`
  - `pkgs/gpuix-shell/src/platform/audio/**`
  - `pkgs/gpuix-shell/src/platform/tailscale/**`
  - `tests/gpuix-shell/fixtures/dbus/**`
  - `tests/gpuix-shell/dbus-session.conf`
- **brief** (345 words):

Build SCOPE S-006 (client side), S-026–S-029, S-031, S-032, S-035, S-126–S-131 data layer, S-141 and ARCHITECTURE §6.3, as pure core tables plus dbus-next 0.10.2 adapters. You do not own `platform/dbus/notifications-server.ts` (P-11). Core (`src/core/dbus/`): `notifications-spec.ts` (capabilities list, hint names, close reasons 1–4, limits summary 1 KiB / body 8 KiB / app 256 B / 32 actions), `markup.ts` (`sanitizeMarkup` keeps entities and b/i/u/`a href`), `image-data.ts` (`imageDataToPng(iiibiiay)` via `node:zlib`-free pure RGBA + a PNG encoder in platform), and per-service tables `nm.ts`, `bluez.ts`, `upower.ts`, `mpris.ts`, `logind.ts`, `ppd.ts`, `gammarelay.ts` (bus names, object paths, interfaces, members, enums such as NM device state 10–120, BlueZ `Device1` props) with the model types `NetworkState {wifiEnabled, airplane, wired?, active?: {ssid, strength, band, bssid, ip}, known[], scan[]}`, `BluetoothState {powered, discoverable, scanning, devices[]{address, name, paired, connected, rssi, battery, icon}}`, `BatteryState {present, percent, state, rate, timeToEmpty, timeToFull, health}`, `MediaState {players[]{bus, identity, status, title, artist, art, position, positionAt, length, canSeek}}`, `PowerProfileState`. Platform (`src/platform/dbus/`): `bus.ts` `getBus(kind)` (one connection per process, reconnect 250 ms→10 s, `NameOwnerChanged` re-read hooks); `upower.ts` `watchUPower(onState)` (`DisplayDevice` GetAll + PropertiesChanged, `/sys/class/power_supply` fallback); `logind.ts` (`onPrepareForSleep`, `powerOff`, `reboot`, `suspend` gated, `terminateSession`, delay-inhibit seam S-141); `network-manager.ts` (`watchNetworkManager`, `requestScan`, `nmConnect(ssid, psk)` through `AddAndActivateConnection` settings dict, `nmDisconnect`, `nmForget`, `setWifiEnabled`, airplane via rfkill); `bluez.ts` (ObjectManager `InterfacesAdded/Removed` + PropertiesChanged, `setPowered`, `startDiscovery` with the 900 ms × 8 retry and 4 s power watchdog, `connect` trust-before-connect, `pair`, `remove`); `bluez-agent.ts` (`registerAgent(path "/org/gpuix_shell/agent", "KeyboardDisplay", callbacks)` with `RequestPasskey/RequestConfirmation/RequestPinCode/DisplayPasskey/AuthorizeService`, 30 s → `org.bluez.Error.Rejected`); `mpris.ts` (`watchMpris`, `playerCommand(bus, verb)`, position extrapolation epoch ms); `ppd.ts` (`net.hadess.PowerProfiles` get/set). `platform/audio/pipewire.ts` (`watchPipewire(onState)` over a `pw-dump --monitor --no-colors` child: default sink volume/mute (cubic), default source, capture streams → privacy dots, screencast nodes; restart backoff) and `wpctl.ts` (`setVolume`, `setMute`, `listSinks` parsing `wpctl status`). `platform/tailscale/status.ts` (`readTailscale()`: `vpn-status` JSON if present else `tailscale status --json`; exit-node and peers). Fixtures: recorded property dicts for each service under `tests/gpuix-shell/fixtures/dbus/` (hand-written where no capture exists, say so). `tests/gpuix-shell/dbus-session.conf` for `dbus-run-session`. Tests: pure table/model tests per service from fixtures; `bluez-agent.test.ts` and `bus.test.ts` under `dbus-run-session` guarded by `test.skipIf(!process.env.DBUS_SESSION_BUS_ADDRESS)`; `pipewire.test.ts` on a recorded `pw-dump` fixture; `wpctl.test.ts` parser. Acceptance: green with `$BUN test src/core/dbus src/platform/dbus src/platform/audio src/platform/tailscale`; nothing dials a real system bus outside the wrapper.

### P-04 — core/theme + fonts + tokens: schema, three fragments in Nix, live watcher, static faces
- **stage**: `build`  
- **depends_on**: P-00  
- **owner_paths**:
  - `pkgs/gpuix-shell/src/core/theme/**`
  - `pkgs/gpuix-shell/src/core/fonts/**`
  - `pkgs/gpuix-shell/src/platform/theme/**`
  - `pkgs/gpuix-shell/src/platform/fonts/**`
  - `pkgs/gpuix-shell/src/core/registry/specs/theme.ts`
  - `pkgs/gpuix-shell/src/daemons/core/handlers/theme.ts`
  - `home/themes/default.nix`
  - `tests/gpuix-shell/fixtures/theme/**`
- **brief** (314 words):

Build SCOPE S-007, S-008 (schema half), S-180 and ARCHITECTURE §10. Core (`src/core/theme/`): `schema.ts` = the zod transcription of DESIGN §2.5 (groups `_generated color font type space size radius motion layout focus`, every `x-keys` child required, hex pattern `^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$`, enums for `layout.toast.anchor` and `layout.rail.boot`); `tokens.ts` (`Theme` type inferred from the schema; `NOIR` literal = DESIGN §2.3 noir column + §2.4 shared block, used by every test); `gpuix-theme.ts` (`toGpuixTheme(theme)` → `GpuixTheme` with `appearance` from polarity, `fontSans/fontMono`, bg/border/text/accent/caret/selection from tokens, never DejaVu or indigo); `parse.ts` (`parseTheme(json)` → `{ok, theme}|{ok:false, path, message}` naming the first missing key). `core/fonts/`: `families.ts` (`FAMILIES = {ui:"Anthropic Sans", prose:"Anthropic Serif", mono:"AnthropicMono Nerd Font", glyph:"AnthropicMono Nerd Font", icons:"Anthropicons"}`), `weights.ts` (`faceFor(weight)` → static file name, 500/600 → 400 fallback flag). Platform: `platform/theme/load.ts` (`loadThemeFile(path)` used by `--check-theme`, throws with the zod path), `platform/theme/watch.ts` (`watchThemePointer(onChange)`: `fs.watch(~/.config)` filtered to `theme` plus a watch on the resolved target dir, 50 ms debounce, realpath, parse; invalid keeps last good and reports), `platform/fonts/static-dir.ts` (`staticFaces()` reads `GPUIX_SHELL_FONT_DIR`, returns `{family, weight, bytes}[]`, empty with one log line when absent). `specs/theme.ts`: `theme.set {name}` (exec `~/.local/bin/theme <name>`, WRITE), `theme.reload` (core), `theme.current` READ; `handlers/theme.ts`. Nix: in `home/themes/default.nix` add `gpuixShell = t: builtins.toJSON {...}` rendering DESIGN §2.3/§2.4 **exactly** (per-theme literals keyed by `t.name` for noir raised `#101111`, light brand `#A74B2F`, Primer dots, pre-blended states; `_generated.by = "home/themes/default.nix"`) and the line `"gpuix-shell.json" = gpuixShell t;` in `render`. Check it with `nix eval --json --impure --expr 'let t = import ./home/themes { lib = (builtins.getFlake "nixpkgs").lib; }; in t.fragments'` or the simplest working form, and copy the three rendered fragments to `tests/gpuix-shell/fixtures/theme/{noir,claude-dark,claude-light}.json` (these are generated, not hand-written; say how). Tests: schema accepts all three fixtures and rejects a fragment missing `color.run.blocked` with that path; `toGpuixTheme` never yields DejaVu; `faceFor`; watcher test on a temp dir with a symlink retarget (pure node, no compositor). Acceptance: `bun src/main.ts --check-theme tests/gpuix-shell/fixtures/theme/noir.json` prints ok. Log the `nix eval` command you used in BUILD-LOG.

### P-05 — core/registry + socket + config + logging + state + platform/{socket,fs,exec,state} + CLI
- **stage**: `build`  
- **depends_on**: P-00  
- **owner_paths**:
  - `pkgs/gpuix-shell/src/core/registry/**`
  - `!pkgs/gpuix-shell/src/core/registry/specs/*.ts`
  - `pkgs/gpuix-shell/src/core/registry/specs/core.ts`
  - `pkgs/gpuix-shell/src/core/socket/**`
  - `pkgs/gpuix-shell/src/core/config/**`
  - `pkgs/gpuix-shell/src/core/logging/**`
  - `pkgs/gpuix-shell/src/core/state/**`
  - `pkgs/gpuix-shell/src/platform/socket/**`
  - `pkgs/gpuix-shell/src/platform/fs/**`
  - `pkgs/gpuix-shell/src/platform/exec/**`
  - `pkgs/gpuix-shell/src/platform/state/**`
  - `pkgs/gpuix-shell/src/cli/**`
  - `pkgs/gpuix-shell/src/daemons/core/handlers/core.ts`
- **brief** (400 words):

Build SCOPE S-002, S-009, S-016–S-019, S-086 (CLI half) and ARCHITECTURE §4, §9, §6.5, §16.1. You own `core/registry/**` except the per-domain `specs/<domain>.ts` (you own `specs/core.ts`). Core: `registry/types.ts` (ARCHITECTURE §9.1 verbatim: `CommandSpec`, `VerbClass`, `Owner`, `InvokeRequest`, `InvokeResult`), `registry.ts` (`createRegistry(specs)`: unique ids, unique cli paths, SECRET never callable, `list({launcher:true})`), `ids.ts` (`a.b-c` ↔ `a/b-c`), `classes.ts` (gates: ACTION `yes-flag` refused without `yes` when source ∈ {cli,script} and `tty=false`), `grammar.ts` (`parseArgv`: longest cli path, aliases `toggle <surface>` / bare `<surface>`, Vicinae compat `cmd launch|ls`, `dmenu`, `open|close|toggle|state`, flags `--json --source --hud --yes`, positionals, zod → `UsageError` exit 2, generated usage), `specs/core.ts` (`core.ping/version/status/snapshot/listen/reload/registry-ls/doctor/validate`, `status.set/clear` keyed status S-018). `socket/`: `protocol.ts` (JSON-RPC types, `ErrorCode`, `exitCodeFor`, `error.data.kind` vocabulary), `ndjson.ts`, `compat-frame.ts` (4-byte native-endian + JSON, `Ipc/<fn>` methods), `sniff.ts` (3-byte rule incl. the `0x227B` edge), `limits.ts`. `config/schema.ts` (zod for `~/.config/gpuix-shell/config.json`: `schemaVersion`, `rail {output, boot, items[], perOutput}`, `toast {anchor}`, `herdr {transport, host}`, `launcher {favourites[], hidden[], filesInRoot, keybinding}`, `providers.<id>.enabled`, `clipboard {evictionSeconds, cap}`, `notifications {rules[], muted[]}`, `power {allowSuspend}`, `supervisor {warmSpare}`) + `defaults.ts`. `logging/` logfmt with `<N>` priority prefixes and `redact`. `state/` (`Topic` union §4.3, `createHub()` pure diff by stable stringify, `rev`). Platform: `fs/paths.ts` (`xdg()`), `fs/atomic.ts` (tmp + fsync + rename, 0600), `fs/watch.ts`; `socket/server.ts` (`createServer(path, handler)`: 0700 dir, singleton probe → defer → unlink stale → bind, sniff per connection, per-connection reply routing, subscriber backlog 4 MiB → `events_lost`), `socket/client.ts` (`connectCore({timeoutMs: 1000})` → `CoreClient`); `exec/runner.ts` (argv only, 30 s timeout, SIGTERM→SIGKILL 5 s, 10 MB cap, env scrub of `GPUIX_*`/socket vars, error kinds), `exec/spawn.ts` (`spawnSurface(name, payload)`: payload file `spawn/<nonce>.json` 0600, `Bun.spawn` with `stdin:"ignore"`, `GPUIX_SHELL_SPAWN` env, `GPUIX_SHELL_EXECUTABLE`), `exec/launch.ts` (`systemd-run --user --scope --collect --slice=app.slice -- gio launch <file>`); `state/frecency-db.ts` (bun:sqlite, the Vicinae formula), `state/json-state.ts`. CLI (`src/cli/`): `main.ts` `runCli(argv)` (parse → connect → `core/hello` → request → print echo or `--json` data → exit code; `listen` streams; `dmenu`/`select` read stdin ≤1 MiB, print the row or index, exit 1 on dismiss; `doctor` runs `--check-native` as a child; never imports `@gpuix/*`), `output.ts`, `usage.ts`, `compat.ts`. `handlers/core.ts` for the core domain. Tests: registry static checks (ids, paths, SECRET has no cli path, every KEYS §7 verb in your specs parses), grammar table, sniff, ndjson/compat codecs, per-connection routing (two connections same id never cross), backlog drop, config defaults and a bad key with its path, redact, runner (timeout, env scrub, exit mapping) with `/bin/sh`-free argv, atomic write mode 0600. Acceptance: `$BUN test src/core/registry src/core/socket src/core/config src/core/logging src/core/state src/platform src/cli` green; `time $BUN src/cli/main.ts ping` against a tiny in-test server ≤ 100 ms (report the number).

### P-06 — daemons/core: hub, topics, surface supervisor, focus guard, pollers, status readers wiring
- **stage**: `build`  
- **depends_on**: P-00  
- **owner_paths**:
  - `pkgs/gpuix-shell/src/daemons/core/**`
  - `!pkgs/gpuix-shell/src/daemons/core/handlers/*.ts`
  - `pkgs/gpuix-shell/src/daemons/core/handlers/supervisor.ts`
- **brief** (395 words):

Build the headless `gpuix-shell daemon core` of ARCHITECTURE §3: the one `shell.sock` owner, never loads `@gpuix/*`. Files under `src/daemons/core/`: `main.ts` (default export; creates `$XDG_RUNTIME_DIR/gpuix-shell` 0700, starts the P-05 socket server, registers built-ins `core/hello|subscribe|unsubscribe|invoke|ping|version`, `surface/ready|closing|closed`, `service/register|publish`; loads config via `core/config` with last-good fallback; exits 0 on Sway `shutdown`; `uncaughtException` → exit 1), `hub.ts` (wraps `core/state.createHub`: `publish(topic, value)`, `subscribe(conn, topics)` sending full snapshots then `state` notifications, `events_lost` on backlog), `router.ts` (registry invoke: `owner core` in-process via `handlers/index.ts`; `owner notifications|music` forwarded to `notifications.sock` / `music/ctl.sock` with id remapping; `owner surface:*` → supervisor; `owner exec` → runner; gates from `core/registry/classes`; `source`/`tty` honoured; `--hud` echo → `osd/show` forward), `supervisor.ts` (per-surface state machine closed→spawning→open→closed; one exclusive overlay at a time; 150 ms debounce; `closeOnReady`; `update` vs `close` on re-toggle; spawn through `platform/exec/spawn`; pin dance via `platform/sway/output-pin` for `switcher` and `rail` daemons; `surface.failed` event; warm spare behind `config.supervisor.warmSpare`, off), `focus-guard.ts` (closes the open exclusive overlay on Sway workspace/window/output focus events, logind `PrepareForSleep`, or another overlay opening; ignores events after `surface/closing` and during the tick barrier), `sway.ts` (P-01 session → `sway` topic → `slots` via P-02 `joinSlots` + `rail.json` lastVisited; fullscreen → stop/restart the rail unit via `systemctl --user`), `herdr.ts` (P-02 transport auto-select local → ssh-forward → ssh-exec → cli-exec when `herdr` on PATH and `HERDR_FAKE_SNAPSHOT` set; attention episodes → one `Notify` through our own daemon with actions `default=Go`, `dismiss=Dismiss`, `replaces_id` per slot; optional Sway urgency), `status.ts` (P-03 watchers → `battery network bluetooth audio media tailscale` topics; keyed `status` topic with ttl), `clipboard.ts` (two `wl-paste --watch gpuix-shell clipboard ingest --type …` children with backoff; P-10 owns ingest/store), `apps.ts` (P-09 index → `apps` topic), `theme.ts` (P-04 watcher → `theme` topic; `theme.reload` handler re-reads), `rail.ts` (`rail.toggle|show|hide|expand|collapse|reload|status` via `rail.json` + `systemctl --user start|stop|restart gpuix-shell-rail`; in dev mode spawn directly), `handlers/supervisor.ts` (the `launcher|switcher|center|controls|power|cheatsheet|ask|gallery .toggle|open|close|state` and `files.open|pick` handlers calling the supervisor). Write `src/daemons/core/README.md` (one page: topics, who publishes, how to run with fakes). Tests (`*.test.ts`, no compositor): supervisor state machine with a fake spawner (toggle twice fast → never left open; update vs close; one exclusive overlay), focus guard table, router gating (ACTION without yes from a script → refused), end-to-end: start `main` on a temp `XDG_RUNTIME_DIR` with P-01 `startFakeSway` and the P-02 fake `herdr`, connect with P-05 `connectCore`, `subscribe(["slots"])` → nine slots; `launcher/toggle` → fake spawner called. Acceptance: green with `$BUN test src/daemons/core`; RSS of the daemon printed in BUILD-LOG (target ≤ 100 MiB, unverified until measured).

### P-07 — ui/host + ui/kit: mount, fonts, theme, core client hooks, keys, ui-tree, component library, design-lint
- **stage**: `build`  
- **depends_on**: P-00  
- **owner_paths**:
  - `pkgs/gpuix-shell/src/ui/**`
- **brief** (394 words):

Build ARCHITECTURE §5 and DESIGN §7 as the one React library every surface uses; nothing here spawns processes. `ui/host/`: `mount.tsx` (`mountSurface(spec, node)` exactly as ARCHITECTURE §5.2: one mount per process, `readSpawnPayload()` (reads and unlinks `GPUIX_SHELL_SPAWN`, else daemon defaults), `createRenderer()` + `init(windowOptions(spec, payload))`, `registerFont` for each `staticFaces()` entry, `render(<SurfaceRoot/>, {renderer, keyboardFocusDim:false, tabNavigation, onKeyDown})`, `startFrameLoop({frameMs: daemon ? 250 : 100})`, `uncaughtException`/`unhandledRejection`/`SIGTERM` → `exitSurface`), `window-options.ts` (the ARCHITECTURE §5.1 table as data: layer, anchor, size, margin, exclusiveZone, keyboardInteractivity, windowBackground, appId=namespace=`gpuix-shell-<name>`; toast/switcher/controls/power heights computed from payload counts), `exit.ts` (`exitSurface(code, reason)`: log, `surface/closed` best effort ≤50 ms, `process.exit`), `theme.tsx` (`ThemeProvider`, `useTokens()`, live swap on the `theme` topic, `GpuixTheme` from P-04 `toGpuixTheme`), `core-client.tsx` (`CoreClientProvider` over P-05 `connectCore`, `useTopic<T>(topic)` via `useSyncExternalStore` seeded from the spawn payload, `useInvoke()`, `surface/ready` after first commit using `onLayout` of the root), `keys.ts` (`normalizeKey(e)` → `"ctrl-shift-enter"` style; Super = `cmd`; `useKeymap(table)` with the launcher profile `default|vim|emacs` hook), `scale.tsx` (`ScaleProvider`, `px(n)` 0.8–1.6, Ctrl+=/−/0, persisted in `zoom.json`; files only), `ui-tree.ts` (`serveUiTree(renderer, socketPath)`: a tiny NDJSON server on `<name>.sock` answering `ping`, `close`, `update`, `ui-tree` = `getAutomationTree()`, plus an `onUpdate` hook), `error-boundary.tsx`, `spawn-payload.ts`, `surface-root.tsx` (root div with `display:flex`, `flexDirection:column`, `fontFamily`, `fontSize`, `color`, `backgroundColor` from tokens; providers; window `onKeyDown` Escape ladder: panel → view → scope → `exitSurface(0,"escape")`; `onBlur` backstop 100 ms). `ui/kit/`: `Row` (DESIGN §7.1 grammar: leading 34, title, subtitle, trailing state, trailing action, states hover=cursor, selected, current bar, urgent edge, disabled), `Section` header 30, `SearchField` (`<input autoFocus>`, Enter via `onSubmit`, up/down via `onKeyDown`, scope pill), `VirtualRows` (ARCHITECTURE §5.6 flat items with fixed heights per kind, cursor, `scrollToItem`, hover=cursor, windowing ±8), `ActionPanel` (anchored inside the window, 300 wide, rows 40, filter at >6), `Footer` 36 with key caps, `Echo` (6 s with Undo), `Glyph` (one family per node, explicit ink), `Dot`, `ToastCard`, `ProgressFill`, `HoldToConfirm` (1500 ms fill + countdown, release cancels), `Dialog`, `Keycap`, `Metadata`, `Empty` (one muted row), `Switch` 32×18, `Slider` (3 px track, knob 14), `PasswordField`. Rules baked in: no hex literals, one template string per `<text>`, every `<svg>` has `color`, numeric px, no `zIndex`. `ui/design-lint.test.ts`: grep `src/ui` and `src/surfaces` for `#[0-9a-fA-F]{3,8}`, `shadow`, `blur`, and alpha < 1 on `backgroundColor` outside `src/core/theme`. Write `ui/README.md` (how to mount a surface in 20 lines). Tests: `keys.test.ts`, `window-options.test.ts` (every surface row of §5.1), `virtual-rows.logic.test.ts` (flatten + cursor skipping headers), `scale.test.ts`, design-lint. Components themselves are not unit-tested (no Linux test renderer); the smokes cover them. Acceptance: green with `$BUN test src/ui`; `tsc` clean for `src/ui`.

### P-08 — surfaces/rail: nine slots, status cluster items, collapsed/expanded, verbs
- **stage**: `build`  
- **depends_on**: P-00  
- **owner_paths**:
  - `pkgs/gpuix-shell/src/surfaces/rail/**`
  - `pkgs/gpuix-shell/src/items/{clock,battery,network,bluetooth,audio,bell,tailscale,media,pomodoro,recording,privacy,touchpad,custom}/**`
  - `pkgs/gpuix-shell/src/core/registry/specs/rail.ts`
  - `pkgs/gpuix-shell/src/daemons/core/handlers/rail.ts`
- **brief** (399 words):

Build SCOPE §1 (S-020–S-046; P0 rows first, P1 where cheap) and DESIGN §8.1 as `gpuix-shell daemon rail [--output eDP-1] [--collapsed|--expanded]`, a window daemon that subscribes to core topics and acts only through registry invokes. `surfaces/rail/main.tsx`: read `rail.json` mode (boot default `collapsed`, DESIGN A-08) and the `--output`; `mountSurface({name:"rail", daemon:true})` with the §5.1 collapsed (56 × 0, exclusive 56) or expanded (220) options; subscribe `slots theme notifications battery network bluetooth audio media tailscale status music overlays`; exit 69 when the configured output is absent (no restart loop), exit 0 on `close`. `slots.tsx`: exactly nine rows (ws 10 is a pinned row at the bottom of the slot zone), DESIGN §8.1 geometry for both widths (collapsed cell 32×30 with a 6 px dot top-right; expanded row 196×30: numeral at x=8, glyph 13 at x=20, title at x=42 elided, trailing dot/count, 2 px accent current bar, "Mirrors slot N" / "unverified" words, `–` for empty slots, "+" affordance on empty rows (S-023, invoke `herdr.new`), summary line "2 working · 1 needs input"), working-dot stepped pulse 600 ms (DESIGN A-06), done cleared on visit (core tracks `lastVisited`). Click → `sway.focus-slot {n}` with `source:"rail"`, right-click dot → `launcher.open --view herdr`, wheel over slots → `workspace prev/next_on_output` (KEYS §6). `cluster.tsx`: ordered from `config.rail.items` through `src/items/index.ts`, footer rows 24 high, DESIGN A-10 default order. Items you own under `src/items/<name>/index.tsx` each exporting `createItem(): RailItem` (`surfaces/rail/item.ts` defines `RailItem`): `clock` (minute tick, stacked "HH"/"MM" collapsed, date line expanded), `battery` (UPower topic; critical <10 % discharging → one `notify` through core), `network` (SSID + bars or wired/off; click `controls.open wifi`, right `nmcli radio wifi` toggle via registry), `bluetooth`, `audio` (volume/mute/mic; wheel → `volume up|down` script via `exec`; click `controls.open audio`), `bell` (unread badge, DND glyph 󰂛; click `notifications.toggle`, right `notifications.dnd toggle`), `tailscale`, `media` (expanded only; middle = play/pause), `pomodoro`, `recording`, `privacy`, `touchpad` (keyed statuses), `custom` (config-driven click/right/middle/scroll → registry id). `specs/rail.ts`: `rail.toggle|show|hide|expand|collapse|reload|status [--output]`; `handlers/rail.ts` delegates to P-06 `rail.ts` API (code against the §4 signature). Pure logic in `.ts` beside the `.tsx`: `slot-row.ts` (slot → row model: numeral ink, glyph, word, dot colour from `color.dot.*`, chips), `cluster-order.ts`, `clock-format.ts`, `battery-format.ts`. Tests: `slot-row.test.ts` (transition table blocked/working/done/idle/unknown/unavailable/mirrored/unverified), `cluster-order.test.ts` (config resolves, unknown id ignored with a log), `clock-format.test.ts`, `battery-format.test.ts`. Acceptance: tests green; under the harness (if time allows, else P-33 does it) `bun src/main.ts daemon rail --output HEADLESS-1` with `GPUIX_SHELL_DEV=1` and no core running paints the skeleton (nine numerals) and reserves 56 px. Log what ran.

### P-09 — surfaces/launcher host + providers apps/commands/windows/workspaces/calc + fuzzy/frecency + desktop entries + dmenu
- **stage**: `build`  
- **depends_on**: P-00  
- **owner_paths**:
  - `pkgs/gpuix-shell/src/surfaces/launcher/**`
  - `!pkgs/gpuix-shell/src/surfaces/launcher/providers/{clipboard,files,tabs,emoji,wifi,bluetooth,audio,music}.ts`
  - `!pkgs/gpuix-shell/src/surfaces/launcher/providers/index.ts`
  - `pkgs/gpuix-shell/src/core/launcher/**`
  - `pkgs/gpuix-shell/src/core/apps/**`
  - `pkgs/gpuix-shell/src/platform/apps/**`
  - `pkgs/gpuix-shell/src/core/scripts/**`
  - `pkgs/gpuix-shell/src/core/registry/specs/launcher.ts`
  - `pkgs/gpuix-shell/src/core/registry/specs/dmenu.ts`
  - `pkgs/gpuix-shell/src/daemons/core/handlers/launcher.ts`
  - `tests/gpuix-shell/fixtures/apps/**`
- **brief** (384 words):

Build SCOPE §2.1 (S-050–S-059), S-060–S-063, S-066, S-069, S-070, S-078, S-086, S-088, S-092 and ARCHITECTURE §8 on the frozen `src/launcher/provider.ts` (import it, never redefine it). `surfaces/launcher/main.tsx`: `mountSurface({name:"launcher", window: 700×580 overlay, top 108, keyboard exclusive, tabNavigation:false})`; args from the spawn payload `{view?, query?, dmenu?: {rows, flags}}`; the `update {args}` socket message switches view/query without respawn. `host.tsx` + `view-stack.ts` (push/pop, per-view query, stale-echo counter, `popToRoot`), `root.ts` (favourites in Tom's order `applications:herdr-picker clipboard:history browser-extension:browse-tabs media:now-playing core:search-tray` → frecency → context section (S-088) → merged provider results with `rootLimit` → files if `launcher.filesInRoot` → fallbacks), `prefixes.ts` (KEYS §4.1 table: `>` `=` `:`(files, `/` alias) `@` windows `#` workspaces, `w ` `bt ` `em ` `m ` `h ` `t ` `n ` `tabs ` `tray ` `?`), `keymap.ts` (KEYS §4.2, profiles default/vim/emacs), `actions.tsx` (panel, consequence shown, echo → footer, `close:true` → `surface/closing` then exit), `confirm.tsx`, `detail.tsx` (Ctrl+I), `hud.ts`, `dmenu.tsx` (rows from stdin via the payload, `-f data|index`, `--free-text`, `--password`, prints the choice through the reply, exit 1 on Escape). `core/launcher/`: `fuzzy.ts` (herdr-bar constants match 16, boundary 16, camel 12, consecutive 16, first ×2, gap start −3, extension −1; golden corpus test), `frecency.ts` (Vicinae formula `min(25, 5·ln(1+0.1·visits) + 10·e^(−days/30))/25`), `rank.ts` (score = fuzzy + 6 × frecency, `MIN_QUALITY 60`, alias-prefix first, ties by `(−score, mru, status, length)`), `abort.ts` (last complete snapshot per provider; yields after abort ignored). `core/apps/desktop-entry.ts` (Exec field codes, `Actions=`, `NoDisplay`, `Hidden`, `OnlyShowIn` against `sway-physical`, Icon) + `platform/apps/index.ts` (scan `$XDG_DATA_DIRS/applications`, watch, cache). `core/scripts/script-command.ts` (Vicinae header grammar, `refreshTime` gated off). Providers you own (`providers/<id>.ts` each `createProvider(deps)`): `apps` (hidden list, `gio launch` via `platform/exec/launch`, actions open / open in workspace N / copy name), `commands` (registry `launcher.root` rows plus the 27 native root commands of KEYS §4.1), `windows` (`@`, Enter `sway.focus-window`, close / move), `workspaces` (`#`/`h `: glyphs, MRU + fuzzy, current never first, Enter `sway.focus-slot`, rename/restore/close(confirm)/sidebar via `herdr.*`), `calc` (pure; 30-expression test), `theme` (`t `), `notifications` (`n `), `shell` (`>`, live output, "Run in kitty"), `cheatsheet` (`?`, P-17 data), `dmenu`. `specs/launcher.ts` (`launcher.toggle|open|close|state [--view] [-q]`, `cmd.launch`, `cmd.ls` aliases), `specs/dmenu.ts` (`dmenu.run`, `select.run`); `handlers/launcher.ts` (dmenu/select = spawn the launcher with the rows payload and relay the reply). Tests: fuzzy golden, frecency, rank/root order, abort semantics, view-stack, prefixes, keymap (no Super chord), desktop-entry fixtures, calc, workspaces ranking, dmenu formats. Acceptance: `$BUN test src/surfaces/launcher src/core/launcher src/core/apps src/platform/apps src/core/scripts` green; `tsc` clean for your files.

### P-10 — providers clipboard + files + browser tabs + emoji; clipboard store; Chrome native host
- **stage**: `build`  
- **depends_on**: P-00  
- **owner_paths**:
  - `pkgs/gpuix-shell/src/surfaces/launcher/providers/{clipboard,files,tabs,emoji}.ts`
  - `pkgs/gpuix-shell/src/core/clipboard/**`
  - `pkgs/gpuix-shell/src/platform/clipboard/**`
  - `pkgs/gpuix-shell/src/platform/chrome/**`
  - `pkgs/gpuix-shell/src/daemons/native-host/**`
  - `pkgs/gpuix-shell/data/glyphs.json`
  - `pkgs/gpuix-shell/data/README.md`
  - `pkgs/gpuix-shell/src/core/registry/specs/clipboard.ts`
  - `pkgs/gpuix-shell/src/daemons/core/handlers/clipboard.ts`
  - `tests/gpuix-shell/fixtures/clipboard/**`
  - `tests/gpuix-shell/fixtures/chrome/**`
- **brief** (373 words):

Build SCOPE S-064, S-065, S-067, S-068, S-145–S-147 and ARCHITECTURE §6.4 on the frozen `src/launcher/provider.ts`. Clipboard: `core/clipboard/kinds.ts` (`kindOf(mime, text)` → text/link/colour/file/image; `text/uri-list` of local paths = file), `policy.ts` (skip when `CLIPBOARD_STATE` ∈ nil/clear/sensitive or the `x-kde-passwordManagerHint` offer; eviction 86400 s except pinned/tagged; cap 1000; dedupe by sha256), `platform/clipboard/ingest.ts` (the `clipboard ingest --type <mime>` CLI path: read stdin, write `$XDG_STATE_HOME/gpuix-shell/clipboard/blobs/<sha>` 0600 atomically, send `clipboard/ingest {sha, mime, size, kind, preview ≤ 200}` to core, exit 0; blobs never cross the socket), `store.ts` (bun:sqlite WAL `clipboard.sqlite`, FTS5 with a `LIKE` fallback, `list/copy/pin/delete/clear/import-cliphist`), `copy.ts` (`wl-copy` with bytes on stdin and the stored mime; paste = copy + HUD, `wtype` only if present and prefixed by a no-op key), `thumbs.ts` (image thumbnails under cache). `specs/clipboard.ts`: `clipboard.ingest|list|copy|pin|text|clear|open|import-cliphist`; `handlers/clipboard.ts` (runs in core; publishes the `clipboard` topic top 50). Provider `clipboard` (rows 56 with thumbnails, kind dropdown on Ctrl+P, Enter copy(+paste) and close, Ctrl+Shift+C copy only, Ctrl+X delete, Ctrl+Shift+P pin, Ctrl+Shift+X clear two-step). Files provider `files` (`:`/`/`, `files:search` fallback): `fd` argv builder over config roots (`~/Downloads`, `~/Documents`, `~`; hidden off; 3-char minimum; 30 s timeout), category filter, actions open (`gio launch`/`xdg-open`), reveal in explorer (`files.open --select`), copy path, copy file (uri-list), trash (`gio trash`, never `rm`), open kitty here, send to agent (copy path + `sway.focus-slot`). Chrome: `platform/chrome/native-messaging.ts` (uint32 LE length + JSON stdio framing; messages `browser/init`, `browser/tabs-changed`, `browser/focus-tab`, `browser/close-tab` per wave1/36 §3.11), `manifest.ts` (the `com.vicinae.vicinae` manifest shape for P-19), `daemons/native-host/main.ts` (relay: Chrome stdio ⇄ `shell.sock` `service/register {name:"browser"}` + `service/publish {topic:"tabs"}`; `tabs/focus` → extension), provider `tabs` (`tabs `: rows title/url/window/audible/pinned, fuzzy url 1.0 / title 0.6, Enter → `browser/focus-tab` then `sway.focus-slot 10`; actions close, copy url; disabled scope with "needs the browser bridge" when no `browser/init` seen). Emoji: `data/glyphs.json` generated from `/home/tom/Downloads/vicinae` `glyph.cpp` (write the generator as `data/gen-glyphs.ts`, GPL provenance in `data/README.md`), provider `emoji` (`em `: grid 8 columns, skin tones, recents in state, Enter copies). Fixtures: a `pw`-free `cliphist`-style export, PNG blob, a recorded `tabs-changed` payload (hand-made, say so). Tests: kinds, policy (password hint skipped, eviction with pins exempt, dedupe), store round-trip on a temp dir (FTS or LIKE), `fd` argv builder, tabs model + framing codec (incl. a 0-length and a 1 MiB cap), emoji search "shrug", glyph table loads. Acceptance: green with `$BUN test src/core/clipboard src/platform/clipboard src/platform/chrome src/daemons/native-host src/surfaces/launcher/providers`.

### P-11 — notifications daemon: fd.o server, store, rules, flood, OSD routing, toasts window, notification centre
- **stage**: `build`  
- **depends_on**: P-00  
- **owner_paths**:
  - `pkgs/gpuix-shell/src/core/notifications/**`
  - `pkgs/gpuix-shell/src/platform/dbus/notifications-server.ts`
  - `pkgs/gpuix-shell/src/daemons/notifications/**`
  - `pkgs/gpuix-shell/src/surfaces/toasts/**`
  - `pkgs/gpuix-shell/src/surfaces/center/**`
  - `pkgs/gpuix-shell/src/core/registry/specs/notifications.ts`
  - `tests/gpuix-shell/fixtures/notifications/**`
- **brief** (393 words):

Build SCOPE §3 (S-100–S-109), ARCHITECTURE §7 and DESIGN §8.4. Core (pure): `store.ts` (`NotificationStore`: u32 ids skipping 0, `replaces_id` live → in place and newest, stale → new id, 100 active, hints `transient`/`resident`/`urgency`, timeouts −1→5000 / 0→never / explicit wins, close reasons 1–4, restore stack ≤5, dismiss-all keeps history), `rules.ts` (first match over `{match:{app?, summary?, body?, urgency?}, action: drop|dnd-exempt|urgency|timeout|silent|route-to-osd}`), `flood.ts` (20/s global cap, identical app+summary+body within 1 s → counter), `osd-route.ts` (`app_name == "osd"`, `x-canonical-private-synchronous`, rule → the OSD slot with one stable id; kind from summary/icon; never in history/unread, DND-exempt, suppressed while launcher/controls are open), `toast-layout.ts` (`estimateCardHeight(card)` 72–140 from DESIGN §8.4 using 0.525 em advance on a 300 px column; golden test), `history.ts` (JSONL codec, cap 500 / 30 days, images by sha), `grouping.ts` (same app > 3 collapses; S-103). Platform: `platform/dbus/notifications-server.ts` (dbus-next interface at `/org/freedesktop/Notifications`: `GetCapabilities` `["actions","body","body-markup","icon-static","persistence"]`, `GetServerInformation` `["gpuix-shell","Tom","0.1.0","1.2"]`, `Notify`, `CloseNotification`, signals `NotificationClosed`, `ActionInvoked`; `requestName` with DO_NOT_QUEUE, on failure log the owner's pid/comm and exit 69). Daemon (`src/daemons/notifications/`): `main.ts` (owns the name and `notifications.sock`, `service/register {methods: notifications/*, osd/*, toast, notify}`, publishes the `notifications` topic, serves D-Bus even when core is down; expiry/hover timers live here), `toasts.ts` (child host: spawn `gpuix-shell surface toasts` with the visible set ≤4 + "(N more)", wait `surface/ready`, SIGTERM the old; empty set → kill), `osd.ts` (child host: spawn `surface osd` on the first value, `osd/update` after, close after 1500 ms idle; P-12 builds the window), `handlers.ts` (KEYS §7.2 verbs: `dismiss [--all] [--no-history] [id]`, `restore`, `invoke <id> [action]`, `list|history --json`, `count`, `clear-history --yes`, `dnd on|off|toggle|status`, `privacy`, `reload`, `toast`, `notify`, `osd <kind> <value>`, `osd.show`). `specs/notifications.ts` for all of them (owner `notifications`). Surfaces: `surfaces/toasts/main.tsx` (transparent 390 × Σ heights, anchor from `config.toast.anchor` default top-center, DESIGN §8.4 cards: urgency edge, image 48, 3 px value bar, ≤2 action caps, click → `default`, right-click dismiss, hover → `toast/hover`), `surfaces/center/main.tsx` (500×650 top-right, exclusive, Current/History, groups per app, rows 56, hint letters, KEYS §5.2 keys, DND switch, clear-all two-step). Fixtures: recorded `Notify` argument arrays. Tests: store, rules, flood (100 calls in 100 ms → ≤20 cards), osd-route (stable id), toast-layout golden, history, grouping; `server.test.ts` under `dbus-run-session` with the real `notify-send` for the 14 cases of ARCHITECTURE §7.4 (`test.skipIf` without a bus; toast/osd children replaced by a no-window stub via `GPUIX_SHELL_FAKE_CHILD=1`), name-contention → exit 69. Acceptance: pure tests green; D-Bus tests green under `runtime-test -- dbus-run-session --config-file=tests/gpuix-shell/dbus-session.conf -- $BUN test src/daemons/notifications src/platform/dbus/notifications-server.test.ts` (state which ran).

### P-12 — surfaces/osd: the 280×56 bottom card for volume, brightness, mic, caps, touchpad, media, audio-route, hud
- **stage**: `build`  
- **depends_on**: P-00  
- **owner_paths**:
  - `pkgs/gpuix-shell/src/surfaces/osd/**`
  - `pkgs/gpuix-shell/src/core/registry/specs/osd.ts`
- **brief** (315 words):

Build SCOPE §4 (S-115–S-120) and DESIGN §8.5 as `gpuix-shell surface osd`, a child of the notifications daemon (P-11 spawns it and sends updates; you build the window and its model). `surfaces/osd/main.tsx`: `mountSurface({name:"osd", window: overlay, anchor ['bottom'], 280×56, margin [0,0,96,0], keyboard none, windowBackground transparent})`; the first value comes in the spawn payload `{kind, value?, label?, icon?, muted?, output?}`; later values arrive as `osd/update` on `osd.sock` (P-07 `serveUiTree`'s `onUpdate` hook) and replace content in place without re-animating; a 120 ms opacity fade on first show only; the process exits when the daemon sends `close` (1500 ms after the last update) or on SIGTERM. `model.ts` (pure): `osdModel(update)` → `{glyph, label, figure, bar?: {value 0..100, muted}, kind}` for kinds `volume` (󰕾/󰖁, "45 %"/"Muted"), `brightness` (label "Brightness eDP-1" when the output is passed), `mic` (󰍬, "On/Off"), `caps`, `touchpad` (boolean kinds: no track, a word), `media` (track title + ▶/‖), `audio-route` ("Speakers → Magic Trackpad…" elided, device icon), `hud` (free text from `showHUD`/`--hud`); values clamp to 0–100 (never >100, AM #109); the brightness floor never draws 0 while lit. `card.tsx`: panel radius `radius.outer`, `surface.raised`, 1 px `line.strong`, icon 18 at x=16, label chrome 12 `ink.muted` at x=46, figures 12 right at x=264, 3 px track at y=42 `line.hairline` with `accent.default` fill (`ink.disabled` when muted, width kept). `specs/osd.ts`: `osd {kind} {value|on|off|text}`, `osd.show --icon --label [--value]`, `osd.suppress on|off` (owner `notifications`; P-11's handlers call into the daemon's osd child host). Also document in `surfaces/osd/README.md` the contract the `osd` script already honours (`notify-send -p -t 1500 -a osd -r <id> -h int:value:N`) and that P-11 routes it here, so the `volume`/`brightness`/`touchpad-toggle` scripts need no change tonight. Tests: `model.test.ts` (every kind, clamping, muted, boolean kinds, elision of long route names at 190 px using the 0.525 em estimate), `update-merge.test.ts` (a `brightness` update replacing a `volume` card keeps one card). Acceptance: `$BUN test src/surfaces/osd` green; `tsc` clean; the window itself is verified by P-38's smoke (say so).

### P-13 — surfaces/switcher (Mod+i) + sway domain specs/handlers
- **stage**: `build`  
- **depends_on**: P-00  
- **owner_paths**:
  - `pkgs/gpuix-shell/src/surfaces/switcher/**`
  - `pkgs/gpuix-shell/src/core/registry/specs/switcher.ts`
  - `pkgs/gpuix-shell/src/core/registry/specs/sway.ts`
  - `pkgs/gpuix-shell/src/daemons/core/handlers/sway.ts`
  - `tests/gpuix-shell/fixtures/switcher/**`
- **brief** (329 words):

Build SCOPE §5 (S-121–S-123; S-122 Alt-Tab cycle as a seam, S-124/S-125 not tonight) and DESIGN §8.3 as `gpuix-shell surface switcher`, pinned to eDP-1 by the core supervisor's pin dance (you never pick an output yourself; if the payload says the output is absent, show a toast via `notify` "no top display" and exit 69). `surfaces/switcher/main.tsx`: `mountSurface({name:"switcher", window: overlay, anchor ['top'], 560 × (48 + rows×44 + 36) max 580, margin [108,0,0,0], keyboard exclusive})`; rows from the spawn payload `slots` (ten: 1–9 plus 0 = ws 10 "Chrome"), live via `useTopic("slots")`. `rows.ts` (pure): order = herdr-bar's (most recent first by MRU, the current workspace never first, then status rank blocked < done < working < idle < unknown; fixed while open), row model (numeral, glyph, name, subtitle = focused window title elided, trailing dot + word, `●` current marker, `!` urgent, agent mark id, running time "4 m"/"2 h", "Mirrors slot N", optional report-metadata chips only when present), filter (fuzzy over number, name, agent label; `!` first char = blocked only). `keymap.ts` (KEYS §5.1: type to filter, `1..9`/`0` jump at once, Up/Down, j/k when the query is empty, Ctrl+N/P, Enter = `sway.focus-slot` with verify then exit, Ctrl+O preview pane (snapshot detail), Ctrl+B row actions rename/restore/close(two-step)/move focused window here/open sidebar via `herdr.*` and `sway.move-to-slot`, Ctrl+R rename, Esc close). Before invoking an action that moves focus send `surface/closing` so the focus guard ignores the resulting event. `specs/switcher.ts`: `switcher.toggle|open|close [--output]`. `specs/sway.ts`: `sway.focus-slot {n}` (WRITE, verify-after-switch, echo "Workspace 3"), `sway.focus-window {conId}`, `sway.move-to-slot {conId, n}`, `sway.workspace-prev|next` (on output), internal `sway.pin-output`/`sway.restore-focus`; `handlers/sway.ts` implements them on the P-01 session held by core (code against `createSwaySession`'s §4 signature). Fixtures: `tests/gpuix-shell/fixtures/switcher/` reuse the PR #565 Zenbook fixtures (`/home/tom/.wt/dotfiles/morning-shell/tests/workspace-switcher/fixtures/`, copied with provenance) and port its 16 row/guard tests that still apply. Tests: `rows.test.ts` (ordering incl. "current never first", filter, `!`, metadata absent → nothing), `keymap.test.ts`, `handlers/sway.test.ts` against P-01's fake server (focus-slot confirmed/unknown, name quoting refusal). Acceptance: green with `$BUN test src/surfaces/switcher src/daemons/core/handlers/sway.test.ts`; `tsc` clean. The two-output pin-dance smoke is P-36's.

### P-14 — surfaces/controls: per-domain menus wifi, bluetooth, audio, brightness, media, battery/power-profile, tailscale, dnd, input + launcher views
- **stage**: `build`  
- **depends_on**: P-00  
- **owner_paths**:
  - `pkgs/gpuix-shell/src/surfaces/controls/**`
  - `pkgs/gpuix-shell/src/surfaces/launcher/providers/{wifi,bluetooth,audio}.ts`
  - `pkgs/gpuix-shell/src/core/registry/specs/controls.ts`
  - `pkgs/gpuix-shell/src/daemons/core/handlers/controls.ts`
- **brief** (394 words):

Build SCOPE §6 (S-126–S-136), S-072–S-074 and DESIGN §8.6: list menus per domain, never a grid; every row shows real state or a declared "Unavailable". `surfaces/controls/main.tsx`: `mountSurface({name:"controls", window: overlay, anchor ['top','right'], 420 × content ≤ 640, margin [12,12,0,0], keyboard "on-demand"})` with a fallback to `exclusive` when `GPUIX_SHELL_CONTROLS_KB=exclusive` (P-37's smoke decides the default; log the assumption); the spawn payload carries `{page, network, bluetooth, audio, battery, media, tailscale, dnd, input}` snapshots and the pages stay live through `useTopic`. Pages (`pages/<domain>.tsx`, each also exported as a `LauncherView` for the launcher providers you own: `wifi` (`w `), `bluetooth` (`bt `), `audio`): `home` (one row per domain with state word + chevron), `wifi` (header switch; Connected / Networks (scan 500 ms after open, then every 15 s while open) / Saved sections; Enter on a secured unknown SSID opens the inline 36 px password row = a SECRET local form calling P-03 `nmConnect` directly from this process, never through `shell.sock`; disconnect; forget two-step; hidden SSID via Ctrl+H; wired section; airplane row; NM failure reason shown in `status.danger.fg`), `bluetooth` (power/discoverable switches; Your devices with battery %, Enter connect/disconnect; Pair a new device "Searching…"; confirm card with code figures 20, Enter armed after 600 ms, Esc refuses; forget two-step; P-03 `bluezAgent` wired to the card behind `controls.bluetooth.agent`), `audio` (Output/Input rows from `wpctl`, ✓ default, Enter → `audio-route <sink>` script via exec; volume and mic sliders step 5 with figures; wheel adjusts), `brightness` (slider per output → `brightness set N [output]` script), `media` (MPRIS players, art, seekable progress, transport, volume), `battery` (UPower detail + PPD selector), `tailscale` (status, exit-node two-step, peers with online dots, `ssh` action in kitty), `dnd` (switch → `notifications.dnd`), `input` (touchpad toggle script, caps LED state, layout read-only). `keymap.ts` (KEYS §5.4: Left/Right/h/l/Tab switch domain, Up/Down/j/k, Enter, Space toggles, `f` forget, `+`/`-` and wheel, Ctrl+R rescan, Esc back then close; a focused password field is exclusive and Esc cancels, never submits). `specs/controls.ts`: `controls.toggle|open|close [page]`; `handlers/controls.ts` (page validation, spawn via supervisor with the snapshots from core's topics). Pure logic in `.ts`: `wifi-rows.ts` (sections, signal glyphs by strength, known first), `bluetooth-rows.ts` (RSSI order), `audio-rows.ts`, `tailscale-rows.ts`, `battery-rows.ts`. Tests: each rows module on P-03's fixtures; keymap table; "unavailable" rendering when a backend state is `absent`; the password form never produces a registry invoke (assert no `invoke` call). Acceptance: `$BUN test src/surfaces/controls` green; `tsc` clean; the smoke and the real-SSID hand check are P-37's and Tom's.

### P-15 — surfaces/power: session menu with hold-to-confirm + power/lock/inhibit verbs
- **stage**: `build`  
- **depends_on**: P-00  
- **owner_paths**:
  - `pkgs/gpuix-shell/src/surfaces/power/**`
  - `pkgs/gpuix-shell/src/core/registry/specs/power.ts`
  - `pkgs/gpuix-shell/src/daemons/core/handlers/power.ts`
- **brief** (329 words):

Build SCOPE §7 (S-140–S-142), S-188 seam and DESIGN §8.7 as `gpuix-shell surface power`. `surfaces/power/main.tsx`: `mountSurface({name:"power", window: overlay, anchor [] (centred), 360 × (46 + rows×44 + 36), keyboard exclusive})`; payload `{rows, uptime, battery, blockedCount, config.power}`. `rows.ts` (pure): the DESIGN A-23 list in order Monitors off (`m`, safe, `monitors-off` script), Backlight off (`b`, safe, `brightness toggle`), Sleep monitors (`z`, safe, `sleep-monitors`), Log out (`l`, destructive, `swaymsg exit`), Reboot (`r`, destructive), Power off (`p`, destructive), Suspend (`s`, only when `config.power.allowSuspend`), Hibernate / suspend-then-hibernate (`h`/`Shift+H`, only when `/sys/power/state` lists `disk` and a swap device exists — read in core, passed in the payload; absent on the Zenbook), Lock (`l` conflict resolved: Lock is hidden until a locker exists, so `l` stays Log out); cursor starts on the first safe row. `hold.ts` (pure timing model for `HoldToConfirm`: 1500 ms, progress 0→1, release cancels and snaps back, fires exactly once; pointer press-and-hold identical). Footer: uptime, battery, "2 slots need input" (S-142). Keys: Up/Down/j/k/wheel, Enter or the letter starts the hold on destructive rows and fires at once on safe rows, Esc closes. Every row invokes a registry id with `source:"surface"`: `power.monitors-off|backlight-off|sleep-monitors` (exec), `power.logout|reboot|poweroff|suspend|hibernate` (ACTION, `confirm:"hold"`, `replaySafe:false`, `launcher.root:false`, CLI needs `--yes`; backend logind `PowerOff(true)`/`Reboot(true)`/`Suspend` gated / `Session.Terminate` fallback, `systemctl`→`loginctl` chain cached), `lock` (exits 69 with "no locker installed"; there is **no** `unlock` id — add a test asserting the registry has none), `inhibit.on|off|toggle` (a `systemd-inhibit --what=idle:sleep` child kept by core). `specs/power.ts` and `handlers/power.ts` (in core, using P-03 logind and P-05 exec; `power.toggle|open|close` is the only verb a bind may call). Tests: `rows.test.ts` (hibernate hidden without swap, suspend hidden by default, order, first safe row), `hold.test.ts` (fires once at 1500 ms, cancelled at 1400 ms, pointer path), `handlers/power.test.ts` with a fake logind (reboot without `--yes` from a script is refused; `--yes` from a TTY confirmed; `lock` → 69), registry has no `unlock`. Acceptance: `$BUN test src/surfaces/power src/daemons/core/handlers/power.test.ts` green; the smoke (hold `r` 1.2 s on a fake backend fires once; Enter alone does nothing) is P-38's.

### P-16 — surfaces/files: Pinax-like explorer as an ordinary window + platform-neutral file model
- **stage**: `build`  
- **depends_on**: P-00  
- **owner_paths**:
  - `pkgs/gpuix-shell/src/surfaces/files/**`
  - `pkgs/gpuix-shell/src/core/files/**`
  - `pkgs/gpuix-shell/src/core/registry/specs/files.ts`
  - `tests/gpuix-shell/fixtures/files/**`
- **brief** (398 words):

Build SCOPE §10 (S-155–S-158 P1; S-159/S-160 as seams) and DESIGN §8.8: a browser, never a chooser (Nautilus stays the portal picker). `core/files/` (pure, extractable, no `node:fs`): `model.ts` (`Entry {path, name, kind, size, mtime, hidden, mime?}`, `sort(entries, by, dir)`, `filterGrammar(query)` parsing `kind:`, `>1M`, `age:` plus plain substring), `places.ts` (Now · Recent · Shelf · Places (Home, Downloads, Documents, Paper/inbox, Speech/intake, Screenshots) · Pinned · Drives · Trash as data from config + mounts), `jobs.ts` (`planJob(op, items, dest)` → steps with their inverse for move/rename/trash; 60 s undo window model; copy/cut/paste mime dance `text/uri-list` + `x-special/gnome-copied-files`), `preview.ts` (`previewerFor(mime)` → text/code/image/pdf-first-page/markdown/metadata), `keymap.ts` (KEYS §5.5 + DESIGN: Enter, Backspace/Alt+Up, Alt+Left/Right, Home/End/PgUp/PgDn, arrows (grid by columns), type-to-jump 800 ms, Space preview, Ctrl+B rail, Ctrl+L path, Ctrl+1/2/3 views, Ctrl+H hidden, Ctrl+Shift+N folder, Ctrl+Alt+N file, Ctrl+Shift+F deep search, F2 rename, Delete trash with Undo, Shift+Delete sheet with a 1500 ms hold, Ctrl+C/X/V/Z, Ctrl+Shift+C path, Ctrl+Shift+T kitty here, Ctrl+Shift+S send to, Ctrl+W close, Ctrl+=/−/0 zoom, Esc ladder stop job → dismiss offer → cancel cut → close preview → clear filter → clear selection), `actions.ts` (the `files act <name>` table: every key reachable by name). Surface (`surfaces/files/`): `main.tsx` (`mountSurface({name:"files", window: xdg toplevel 1000×640 min 640×400, windowBackground opaque, title "Files"})`, one process per window, `files open [<path>] [--select <path>]`, `ScaleProvider` zoom), `io.ts` (the only `node:fs`/GIO user: list dir, stat, `gio trash`, `gio open`, `udisksctl`/GIO mounts, `fd` deep search, `pdftoppm` first page into cache, job runner with progress and the 60 s undo, atomic state under `$XDG_STATE_HOME/gpuix-shell/files/`), views `list.tsx` (rows 34/48, columns name/age/size), `grid.tsx` (156×176), `gallery.tsx` (strip), `rail.tsx` (248/60 compact), `header.tsx` (crumbs, Ctrl+L path field, view toggles, sort, hidden eye), `preview.tsx` (300 wide at ≥1240 using `<markdown>`, `<code>`, `<img>`), `sheets.tsx` (rename, new, properties, delete-for-good with hold), `undo-pill.tsx`, `context-menu.tsx`, `status-line.tsx`, `send-to-agent.tsx` (copy paths + `sway.focus-slot N`; never types into the PTY). `specs/files.ts`: `files.open`, `files.pick` (P2 seam: prints paths), `files.act`. Fixtures: a generator `tests/gpuix-shell/fixtures/files/make-tree.py` creating a temp tree (hidden files, 1 MB file, old file, nested dirs). Tests: sort, filter grammar (`kind:image >1M age:7d`), job plans and inverses (trash → restore; rename → rename back), places from config, previewer by mime, keymap/actions table has no duplicates and names every `files act`, type-to-jump buffer. `io.test.ts` on a temp tree: list, trash via `gio trash` skipped if `gio` is absent. Acceptance: `$BUN test src/core/files src/surfaces/files` green; the window smoke (open on a temp tree, rows in `ui-tree`, trash then restore) is P-40's.

### P-17 — surfaces/cheatsheet + keyed status + calendar/sysmon/capacity rail items
- **stage**: `build`  
- **depends_on**: P-00  
- **owner_paths**:
  - `pkgs/gpuix-shell/src/surfaces/cheatsheet/**`
  - `pkgs/gpuix-shell/src/core/cheatsheet/**`
  - `pkgs/gpuix-shell/src/items/{sysmon,capacity,calendar}/**`
  - `pkgs/gpuix-shell/src/core/registry/specs/cheatsheet.ts`
  - `pkgs/gpuix-shell/src/core/registry/specs/status.ts`
  - `pkgs/gpuix-shell/src/daemons/core/handlers/status.ts`
  - `tests/gpuix-shell/fixtures/binds/**`
- **brief** (341 words):

Build SCOPE §11 (S-165, S-166), S-018 (keyed status), S-170 (clock/date without a month grid), S-175 and S-044 as optional rail items. Cheatsheet: `core/cheatsheet/parse.ts` (pure: parse Sway config text — `bindsym [--flags] <chord> <command>`, `bindswitch`, `bindgesture`, `set $mod`, `$prompt` expansion, the comment line above a bind as its label, `include` lines ignored but listed), `groups.ts` (Launch, Workspaces, Windows, Layout, Media, Shell, Session by command pattern; the shell's own in-surface keymaps from KEYS §4–§5 as a static table `shell-keys.ts`), `lint.ts` (`lintBinds(parsed, keysTable)` → binds without a KEYS row, chords that shadow each other, chords used by Chrome/herdr-web-ui (Mod+Shift+K)). Surface `surfaces/cheatsheet/main.tsx` (`mountSurface({name:"cheatsheet", launcher geometry 700×580 overlay top 108, exclusive})`; source = `swaymsg -t get_config` via the payload (core runs it) or the dotfiles files when `GPUIX_SHELL_DEV=1`; grouped columns, type to filter, Esc closes; also exported as the launcher `?` provider's data source through `core/cheatsheet/index.ts` `cheatsheetRows()`). `specs/cheatsheet.ts`: `cheatsheet.toggle|open|close`, `cheatsheet.lint` (READ, exit 1 on findings; S-017 `validate` calls it). Keyed status: `specs/status.ts` `status.set {key, text, --ttl}`, `status.clear {key}`, `status.list`; `handlers/status.ts` (in core: map with ttl expiry, publishes the `status` topic; scripts `pomodoro`, `recording-toggle`, `call-record`, `touchpad-toggle` will call it — P-20 edits the scripts). Rail items (`src/items/<name>/index.tsx` exporting `createItem(): RailItem` per `surfaces/rail/item.ts`): `calendar` (expanded rail: date line "Mon 20 Oct", week number, configured timezones as extra lines; click → `launcher.open --view calendar`, a launcher view rendering the same data; no month grid, no events), `capacity` (`claude-capacity` and `seats` bars from `~/.local/state/tally-rewrite/meters`, read on `status` wake-ups, never polled), `sysmon` (cpu/mem/disk from `/proc` and `statvfs`, refresh on the minute tick; P2, off by default in config). Fixtures: copy `home/dot_config/sway/binds.conf` (this branch) and the client `sway-local.conf` text from `home/home.nix:149-168` into `tests/gpuix-shell/fixtures/binds/`. Tests: parser on the fixture (108 bindsym, 10 workspace output lines, 2 gestures as KEYS §9 counts), groups, lint (a bind absent from the KEYS table is reported; the KEYS §3 new lines all resolve to `gpuix-shell` verbs), keyed status ttl expiry with a fake clock, calendar formatting (U-17 relative times), capacity parser on a sample meters file (hand-made, say so). Acceptance: `$BUN test src/core/cheatsheet src/surfaces/cheatsheet src/items src/daemons/core/handlers/status.test.ts` green.

### P-18 — openui: contract, validator, streaming client, GPUIX mapper; ask surface; gallery surface
- **stage**: `build`  
- **depends_on**: P-00  
- **owner_paths**:
  - `pkgs/gpuix-shell/src/openui/**`
  - `pkgs/gpuix-shell/src/surfaces/ask/**`
  - `pkgs/gpuix-shell/src/surfaces/gallery/**`
  - `pkgs/gpuix-shell/src/core/registry/specs/ask.ts`
  - `tests/gpuix-shell/fixtures/openui/**`
- **brief** (374 words):

Build SCOPE §20 (S-200–S-202), ARCHITECTURE §21, DESIGN §8.9 and U-19 (the gallery). Off the critical path; nothing here may delay P0, and no test ever dials `strix:8731`. `src/openui/`: `spec.ts` (vendor `library.spec.json` from `/home/tom/tuesday-oct20/build/shared-parity-reference/openui/docs/generated/playground-library.spec.json` with a provenance comment; `subsetSpec(spec, names)`; host components `WorkspaceRow`, `AgentStatus`, `NotificationCard`, `SliderRow`, `Note`, `Battery`, `AudioSink` and the single action `ShellAction(id, arg?)` — the model may only name ids, the host fills every status/word/count/age from live topics at render time), `library.ts` (`createLibrary` with `@openuidev/lang-core` `defineComponent({component:null})`), `validate.ts` (`validateAsk(program, registry)`: action ids must exist in the registry and be READ or WRITE class, never ACTION/SECRET; refuses `OpenUrl`, `Set`, `Reset`, `Run`, `Query`, `Assign`; refuses literal status words; returns `{ok}|{ok:false, reason}`), `stream.ts` (SSE `completionChunks` reader + `createStreamingParser`; partial nodes inert, keyed by `statementId`; errors ignored until completion; `discover()` via `/v1/models` with a 2 s timeout; request shape `stream:true`, `stream_options.include_usage`, `temperature 0`, `chat_template_kwargs.enable_thinking=false`, 4 k token cap), `model.ts` (reads `~/.config/gpuix-shell/model.json`; no remote fallback), `prompt.ts` (pruned-subset prompt builder), `map.tsx` (ElementNode → `@gpuix/react` JSX using `ui/kit` components; `RunStep`-style controls become `<div role="button" tabIndex=0>` drawn disabled until validated), `replay.ts` (sessions and `panels/*.openui` under state). `surfaces/ask/main.tsx` (launcher geometry; input row at the bottom; header with the clay mark, "Ask", status word "thinking on strix… / ready / model unavailable"; prose 15 Serif for model text; KEYS §5.8 keys: Enter send, Shift+Enter newline, Esc cancels the stream then closes, Ctrl+C copy answer, Ctrl+Shift+C copy tree, Ctrl+Enter run the one validated action through `core/invoke` with `source:"surface"`, Ctrl+L clear). `surfaces/gallery/main.tsx` (xdg toplevel 1200×800: every token group and every `ui/kit` component in the running theme, the five run states, a toast, an OSD card, a power row mid-hold, and every OpenUI component of the subset rendered from a fixture program — the visual test and the OpenUI coverage test; `gallery open` verb). `specs/ask.ts`: `ask.toggle|close`, `ask.run {text}` (P2), `gallery.open`. Fixtures: recorded SSE transcripts (hand-made in the exact `completionChunks` shape, say so), one valid and three invalid programs (unknown action, ACTION class, literal status), a `/v1/models` reply. Tests: validator (rejects each invalid, accepts the valid), streaming parser end state equals the batch parse, `discover` against an in-test fake HTTP server (timeout path), replay round-trip, prompt builder subset, `map` produces one node per element (pure tree assertion, no renderer). Acceptance: `$BUN test src/openui src/surfaces/ask src/surfaces/gallery` green; `tsc` clean.

### P-19 — Nix: package recipe, static fonts derivation, HM module, flake/overlay wiring, vicinae/mako gate
- **stage**: `build`  
- **depends_on**: P-00  
- **owner_paths**:
  - `pkgs/gpuix-shell/default.nix`
  - `pkgs/anthropic-ui-static.nix`
  - `home/gpuix-shell.nix`
  - `flake.nix`
  - `overlays/default.nix`
  - `home/home.nix`
  - `home/vicinae.nix`
  - `hosts/client/default.nix`
- **brief** (374 words):

Build SCOPE S-012 and ARCHITECTURE §11, §13, §14, §18 (prepare the one-switch migration; deploy nothing). 1. `pkgs/gpuix-shell/default.nix` = ARCHITECTURE §14.3 verbatim with these facts from wave1/21: `buildNpmPackage`, `nodejs_24`, `npmFlags ["--ignore-scripts"]`, `autoPatchelfHook`, `appendRunpaths [wayland vulkan-loader libGL]`, `buildInputs [stdenv.cc.cc.lib libxkbcommon libxcb]`, `src` filter excluding `node_modules dist result default.nix .local-state bun.lock bun.lockb *.log *.err`, buildPhase `npm run typecheck && bun run build`, checkPhase `bun test` with the three-lib `LD_LIBRARY_PATH`, installPhase copying `dist`, `package.json` and the runtime `node_modules` set (`@gpuix/native`, `@gpuix/native-linux-x64-gnu`, `zod`, `eventsource-parser`; remove `@gpuix/native/wasm`), the two `makeWrapper` binaries (`gpuix-shell` with `--set GPUIX_SHELL_EXECUTABLE`, `gpuix-shell-native-host` with `--add-flags "… native-host"`), the D-Bus activation file, `installCheckPhase` running `--check-native` and `--check-dbus`, `nativeCheckInputs = [ mpv dbus ]` for the music tests; compute `npmDepsHash` with `nix shell --inputs-from . nixpkgs#prefetch-npm-deps -c prefetch-npm-deps pkgs/gpuix-shell/package-lock.json` and paste it. 2. `pkgs/anthropic-ui-static.nix` (ARCHITECTURE §10.3: fontTools `varLib.instancer` wght 400/500/600 for Sans, 400/600 for Serif, name-table fix to the exact family names; depends on the NAS-pinned `anthropic-ui`; not in `fonts.packages`). 3. `home/gpuix-shell.nix` = ARCHITECTURE §13 verbatim (options `enable package fontPackage target rail.{enable,output,boot} toastAnchor binds.{enable,proposed} herdr.{transport,host} chromeNativeHost music.enable settings extraEnvironment`; assertions against `services.mako.enable` and `programs.vicinae.enable`; `xdg.configFile."gpuix-shell/config.json"`; the bind block via `import ./gpuix-shell-binds.nix { inherit lib cfg; }` (P-20 writes that file; until it exists use a placeholder string and log a request); the Chrome manifest; units `gpuix-shell-core`, `gpuix-shell-notifications` (`Type=dbus`, `BusName`), `gpuix-shell-rail`, optional `gpuix-shell-music`; `RestartPreventExitStatus=69`, `UMask=0077`, `StandardInput=null`, `Slice=app.slice`, `OPENUI_TELEMETRY_DISABLED=1 DO_NOT_TRACK=1`, `GPUIX_SHELL_FONT_DIR`; import P-20's `./gpuix-shell-entries.nix` the same way). 4. Wiring: overlay lines in `overlays/default.nix`, package export and `checks.gpuix-shell`, `checks.gpuix-shell-themes` (runs `--check-theme` over the three fragments rendered by `import ./home/themes`), `checks.gpuix-shell-contract` (`python3 -m unittest discover -s tests/gpuix-shell -p 'test_*.py'`), revised `home-profiles` asserts (XOR with vicinae/mako on the client, units `WantedBy`, package present, `themes/noir/gpuix-shell.json` exists, never on the strix, font assert moved to the fragment); `home/home.nix` imports `./gpuix-shell.nix`; `home/vicinae.nix:10` gated `&& !config.programs.gpuixShell.enable`; `hosts/client/default.nix` enables it. 5. `git add -N pkgs/gpuix-shell home/gpuix-shell.nix pkgs/anthropic-ui-static.nix tests/gpuix-shell home/gpuix-shell-binds.nix home/gpuix-shell-entries.nix` so the flake sees the files; run `nix build .#gpuix-shell -L` (expect tsc → bun test → autoPatchelf 0 unsatisfied → installCheck), `nix flake check --offline --no-build`, `nix build .#checks.x86_64-linux.gpuix-shell-themes -L`. The client toplevel build is P-41's. Acceptance: the package builds (paste the store path and the log order); every failure you cannot fix is a BUILD-LOG request naming the packet. Log the lockfile policy (`package-lock.json` only) in ASSUMPTIONS.

### P-20 — Sway binds block, desktop entries, script edits (osd, theme, herdr-picker, gpuix-notify, startup.conf)
- **stage**: `build`  
- **depends_on**: P-00  
- **owner_paths**:
  - `home/gpuix-shell-binds.nix`
  - `home/gpuix-shell-entries.nix`
  - `home/dot_local/bin/osd`
  - `home/dot_local/bin/theme`
  - `home/dot_local/bin/herdr-picker`
  - `home/dot_local/bin/gpuix-notify`
  - `home/dot_config/sway/startup.conf`
  - `tests/gpuix-shell/test_binds.py`
  - `tests/gpuix-shell/test_scripts.py`
- **brief** (379 words):

Build KEYS §2–§3, §8 and ARCHITECTURE §12, §18 rows 5, 6, 10, 11 without editing `binds.conf`. 1. `home/gpuix-shell-binds.nix`: a function `{ lib, cfg }: string` returning the ARCHITECTURE §12 block **verbatim** (the four `--no-warn --no-repeat` overrides for `$mod+d`, `$mod+space`, `$mod+Ctrl+space` (`launcher toggle --view herdr`), `$mod+v` (`--view clipboard`); the new lines `$mod+i`, `$mod+o`, `$mod+Ctrl+o`, `$mod+Shift+o`, `$mod+x`, `$mod+comma`, `$mod+Shift+e`, `$mod+Shift+slash`, `$mod+Shift+grave`, `$mod+Ctrl+w` (`controls open wifi`), `$mod+Ctrl+b` (`controls open bluetooth`); the proposed `$mod+m`, `$mod+Shift+m`, `$mod+a` emitted only when `cfg.binds.proposed`; every exec carries `--source bind`; `$mod+grave` and F9 stay out tonight). 2. `home/gpuix-shell-entries.nix`: `{ lib, cfg, pkgs }: attrset` of `xdg.desktopEntries` for the shell's own windows (`gpuix-shell-files` "Files" `Exec=gpuix-shell files open %U`, `gpuix-shell-gallery`) and the seven retired `home/vicinae.nix` entries re-expressed as launcher native commands are **not** desktop entries (KEYS §8.3) — document that in a comment. 3. Scripts: `osd` → try `gpuix-shell osd <kind> <value> --source script` when `$XDG_RUNTIME_DIR/gpuix-shell/shell.sock` exists, else the existing `notify-send -p -t 1500 -a osd -r <id> -h int:value:N` path unchanged (the daemon honours both); `theme` → replace the `makoctl reload` and `vicinae theme set dotfiles-current` lines in `reload_desktop_tools` with `systemctl --user -q is-active gpuix-shell-core && gpuix-shell theme reload --source script`, keep `swaymsg reload`; `herdr-picker` → `vicinae_menu()` connects to `$XDG_RUNTIME_DIR/gpuix-shell/shell.sock` (same length-framed `Ipc/dmenu` JSON-RPC, which core's compat sniff accepts) with the old path as a fallback; `gpuix-notify` (new, notify-send-compatible argv subset `-a -u -t -r -h -i -p --action`) → `gpuix-shell notify …` when the socket exists else `exec notify-send "$@"`; `startup.conf:4` comment names gpuix-shell as the clipboard owner (no second watcher). 4. Tests (hermetic unittest, no compositor): `tests/gpuix-shell/test_binds.py` renders the block with `nix eval --impure --raw --expr 'import ./home/gpuix-shell-binds.nix { lib = (builtins.getFlake "nixpkgs").lib; cfg = { binds.proposed = false; }; }'` (or the simplest working form; record it) and asserts every line parses as `bindsym [flags] <chord> exec gpuix-shell <surface> <verb> …`, that no chord collides with `binds.conf` lines other than the four overrides, that `$mod+k` is untouched and `--source bind` is present; `test_scripts.py` runs `osd`, `theme --help`-style dry paths and `gpuix-notify` with a fake `gpuix-shell` and fake `notify-send` on a temp PATH logging argv (the `tests/desktop-control/test_helpers.py` pattern from wave1/13 §5.9), asserting the fallback when the socket is absent. Acceptance: both test files green with `python3 -m unittest tests/gpuix-shell/test_binds.py tests/gpuix-shell/test_scripts.py`; scripts stay executable; `bash -n` on each.

### P-21 — Docs: README, RUNBOOK, MORNING.md skeleton
- **stage**: `build`  
- **depends_on**: P-00  
- **owner_paths**:
  - `docs/gpuix-shell/README.md`
  - `docs/gpuix-shell/RUNBOOK.md`
  - `docs/gpuix-shell/MORNING.md`
- **brief** (375 words):

Write the three documents Tom reads first, from BRIEF.md and the five syntheses, so they are true to the plan even before the code lands (P-48 updates them with measured facts; P-52 finalises MORNING.md). `docs/gpuix-shell/README.md` (≤ 250 lines): what gpuix-shell is (one paragraph; the shell replaces vicinae, mako and the deleted waybar on Sway; GPUIX 0.11.0 + React 19; one headless core, one notifications daemon, one rail daemon, overlays spawned per show), the surface list with its key (from KEYS §3/§7), the process diagram from ARCHITECTURE §3.4, the directory map from ARCHITECTURE §2.2 with one line per area and its owner packet id, the CLI cheat sheet (`gpuix-shell <surface> <verb>`, `--json`, `--source`, `--yes`, exit codes 0/1/2/3/69), where state/config/cache live, how to read logs (`journalctl --user -u 'gpuix-shell-*' -f`), the doctor, and a pointer to each synthesis. `docs/gpuix-shell/RUNBOOK.md`: the developer loop (toolchain paths, `npm ci --ignore-scripts`, `bun test`, `tsc`, `bun build.ts`, running one surface from the checkout **only** inside the wrapper's headless Sway with `GPUIX_SHELL_DEV=1`, the smoke commands, the D-Bus test command, `nix build .#gpuix-shell`, `nix flake check --offline --no-build`), the runtime-test rules (private `/run/user`, no live session, no herdr restart, no core-dump suppression), the fake `herdr`/fake Sway usage, how to add a registry command (spec + handler + test), how to add a rail item or a launcher provider (the seam files), how to add a dependency (P-19 procedure), and a troubleshooting table from ARCHITECTURE §17 (bus name held by mako → exit 69; core down → exit 3; fontconfig empty → panic; pixman → surface lost). `docs/gpuix-shell/MORNING.md` skeleton for Tom: status line placeholder, "what is built / what is not" table placeholder keyed by SCOPE P0 ids, the deploy procedure to the Zenbook only (from wave1/21 §5.7: `nix build …client…toplevel`, `deploy /home/tom/.wt/dotfiles/gpuix-shell#client`, never the strix, rollback = `programs.gpuixShell.enable = false`), the one-minute hand checks per P0 surface (SCOPE acceptance column), the decisions Tom must rule on (ASSUMPTIONS highlights: square vs rounded corners, toast anchor, `$mod+m`, music rekey), and the list of unverified items (ARCHITECTURE §23). Plain prose, sentence case, no emojis, no marketing. Acceptance: the three files exist, every command in them names an absolute path or runs from the worktree root, and nothing claims a measurement that was not made (mark placeholders `TODO(P-48)`).

### P-22 — Test harness completion: driver.mjs, smoke skeletons per surface, fakes, fixtures index, hermetic contract tests
- **stage**: `build`  
- **depends_on**: P-00  
- **owner_paths**:
  - `tests/gpuix-shell/**`
  - `!tests/gpuix-shell/harness.py`
  - `!tests/gpuix-shell/smoke_hello.py`
  - `!tests/gpuix-shell/hello/**`
  - `!tests/gpuix-shell/fixtures/**`
  - `!tests/gpuix-shell/bin/herdr`
  - `!tests/gpuix-shell/music/**`
  - `!tests/gpuix-shell/dbus-session.conf`
  - `!tests/gpuix-shell/test_binds.py`
  - `!tests/gpuix-shell/test_scripts.py`
- **brief** (349 words):

Build ARCHITECTURE §15.3–§15.4 and SCOPE S-011 on top of P-00's `harness.py` (which you may import but not edit; request changes in BUILD-LOG). Deliver: `tests/gpuix-shell/driver.mjs` (ESM, run with `$BUN`): wraps `@gpuix/native/automation` from `pkgs/gpuix-shell/node_modules` — `launch({command, args, env})`, `waitReady`, `byTestId(id).{fill,press,click,textContent,waitFor}`, `tree()`, `grimPixel(output, x, y)` via the harness-provided `grim`, JSON results on stdout; `smoke_common.py` (helpers: start core + notifications daemons from the dev tree with fake `herdr`/fake `swaymsg` on PATH under the harness env, `ui_tree(surface)` over `<name>.sock`, `invoke(verb)` via `bun src/main.ts …`, `assert_pixel`, `write_results(name, dict)` into `docs/gpuix-shell/evidence/<smoke>/`); `bin/swaymsg` and `bin/fakes/*` where a script expects a binary (`wl-copy`, `wl-paste`, `notify-send` argv loggers; `gio` logger); one **skeleton** per P0/P1 surface with the assertions written as named steps and `pytest`-free plain functions: `smoke_rail.py` (rect x==56 then x==220 after `rail expand`; nine `rail.slot.N` nodes; blocked glyph pixel; theme symlink flip repaints ≤300 ms), `smoke_launcher.py` (toggle maps ≤0.6 s; `fill("chrome")` lists Google Chrome first from a fixture apps dir; Enter on a command row produces an echo; Escape exits; second toggle closes; `--view clipboard`), `smoke_notifications.py` (notify-send → toast pixels at top-centre; `-r` replace; automation click → `ActionInvoked`; `osd` script → OSD card at bottom 96, no toast; 5 toasts → 4 + "(1 more)"), `smoke_switcher.py` (two outputs, eDP-2 focused → maps on HEADLESS-1; focus restored after Escape), `smoke_clipboard.py` (`wl-copy` text and PNG → rows; password-hint offer skipped), `smoke_controls.py`, `smoke_power.py` (hold `r` 1.2 s on a fake logind fires once; Enter alone nothing), `smoke_osd.py`, `smoke_center.py`, `smoke_files.py` (temp tree, rows, trash then restore), `smoke_cheatsheet.py`, `smoke_theme.py`, `smoke_two_outputs.py` (rail on the named output at scale 2). Each skeleton must run end-to-end against the stubs and **fail with a clear "not built: <step>" message**, never error out, and write `results.json`. Also `tests/gpuix-shell/test_contract.py` (hermetic: every `smoke_*.py` imports, every fixture JSON parses, no `test_*.py` opens a socket, the fixture index `fixtures/INDEX.md` lists every file with provenance) and `tests/gpuix-shell/README.md` (how to run one smoke, where evidence goes, the renderer rule gles2, the wtype first-key rule, the `XDG_CURRENT_DESKTOP=sway-physical` rule). Acceptance: `python3 -m unittest tests/gpuix-shell/test_contract.py` green; `smoke_hello.py` still passes; at least `smoke_rail.py` run once under the wrapper against P-00's stub reporting `not built` cleanly (paste the output).

### P-23 — Music lane (Navidrome): Subsonic client, library, player, provider, CLI, service, demo (MUSIC.md M1–M7)
- **stage**: `build`  
- **depends_on**: P-00  
- **owner_paths**:
  - `pkgs/gpuix-shell/src/music/**`
  - `pkgs/gpuix-shell/src/surfaces/launcher/providers/music.ts`
  - `pkgs/gpuix-shell/src/core/registry/specs/music.ts`
  - `tests/gpuix-shell/music/**`
  - `docs/gpuix-shell/music/**`
- **brief** (348 words):

Execute `docs/gpuix-shell/MUSIC.md` §5–§8 and §11 (the seven packets M1–M7 collapsed into one owner because the music build jobs did not land; split your work in that order and write one BUILD-LOG block per M-step). Read MUSIC.md fully first; it overrides anything here. Frozen contracts you implement, never change (append only): `src/music/{types,errors,config,format}.ts`, `src/music/subsonic/{types,api,map}.ts`, `src/launcher/provider.ts`. Deliver, in order: M1 `subsonic/{auth,client,redact,schema,record-fixtures}.ts` (`createSubsonicClient`, `formPost` bodies, fresh salt + md5 token, LRU, retry on reads only, canary-password `secrets.test.ts`); M2 `library/**` (cache at `$XDG_CACHE_HOME/gpuix-shell/music/library.json`, index <8 ms on 30k names, `rank` table, `searchMusic` partial → final with a 60 ms debounce, pages, art cache of local files only, recents); M3 `player/**` (mpv over an inherited socketpair `--input-ipc-client=fd://3`, the production argv of MUSIC.md §3 incl. `--ytdl=no --no-terminal --msg-level=all=error --gapless-audio=yes --audio-samplerate=48000`, queue model, state projection with `positionAt` epoch ms, persistence without URLs, scrobble at min(50 %, 240 s), MPRIS `org.mpris.MediaPlayer2.gpuix_music` over dbus-next); M4 `provider/**`, `ipc/**` (`serveBackend`/`connectBackend` on `$XDG_RUNTIME_DIR/gpuix-shell/music/ctl.sock`, 0600), `cli.ts` (`runMusicCli`: `play|pause|toggle|next|prev|stop|seek|volume|now|queue|like|shuffle|repeat|search|serve [--start]`; never starts audio implicitly, exit 3 + the fix); `surfaces/launcher/providers/music.ts` (`createProvider` → `createMusicProvider({backend: () => connectBackend(...), renderView})`, prefix `m `, sections Top result · Songs · Artists · Albums · Playlists); M5 `ui/**` (`MusicRoot`, views, keymap per MUSIC.md keymap, reducer, embedded mode for the launcher); M6 `service/**`, `testing/**` (fake catalogue/api/backend, lavfi tones), `demo/**` (`bun src/music/demo/main.tsx` window + `run.sh` + `on-client.sh`), the GUI smoke under runtime-test with screenshots to `docs/gpuix-shell/music/evidence/gui/`; M7 `integration/**` (now-playing chip component for the rail `src/items/media` consumer — export `NowPlayingChip` from `src/music/integration/chip.tsx`; P-08's `media` item imports it), OSD sender, `specs/music.ts` (owner `music`, forwarded to `ctl.sock` by core), the `gpuix-shell-music.service` proposal text, `DEMO.md`, `ABOVE-RAYCAST.md`, `src/music/index.ts` barrel. Safety rules from MUSIC.md §4 are non-negotiable: tokens never on argv, logs, disk or in the automation tree; `NAVIDROME_LIVE=1` tests skipped by default; no write endpoints from tests; credentials only from `NAVIDROME_CREDENTIALS_FILE` / `/run/agenix/navidrome-credentials`. Tests: the MUSIC.md §7 table per packet (bun), plus `tests/gpuix-shell/music/smoke_music.py`. Acceptance: `$BUN test src/music` green in the sandbox (no network); the demo window runs under the wrapper with the fake catalogue (paste `results.json`); the live path is reported as unverified unless you ran it from the strix with the credential file present.

## 6.3 Stage integrate (runs alone)

### P-30 — Integrate wave 2: seams wired, typecheck + bun test green, bundle split, ping end-to-end
- **stage**: `integrate`  
- **depends_on**: P-01, P-02, P-03, P-04, P-05, P-06, P-07, P-08, P-09, P-10, P-11, P-12, P-13, P-14, P-15, P-16, P-17, P-18, P-19, P-20, P-21, P-22, P-23  
- **owner_paths**:
  - `pkgs/gpuix-shell/package.json`
  - `pkgs/gpuix-shell/package-lock.json`
  - `pkgs/gpuix-shell/tsconfig.json`
  - `pkgs/gpuix-shell/build.ts`
  - `pkgs/gpuix-shell/src/main.ts`
  - `pkgs/gpuix-shell/src/fence.test.ts`
  - `pkgs/gpuix-shell/src/surfaces/index.ts`
  - `pkgs/gpuix-shell/src/daemons/index.ts`
  - `pkgs/gpuix-shell/src/core/registry/specs/index.ts`
  - `pkgs/gpuix-shell/src/daemons/core/handlers/index.ts`
  - `pkgs/gpuix-shell/src/surfaces/launcher/providers/index.ts`
  - `pkgs/gpuix-shell/src/items/index.ts`
  - `docs/gpuix-shell/ASSUMPTIONS.md`
  - `docs/gpuix-shell/BUILD-LOG.md`
  - `docs/gpuix-shell/INTEGRATION.md`
  - `pkgs/gpuix-shell/src/**/*.ts`
  - `pkgs/gpuix-shell/src/**/*.tsx`
- **brief** (325 words):

Runs alone after every build packet. You are the only agent allowed to edit any file in this stage, but you edit other packets' files only to make seams fit (import names, types, missing exports), never to add features; every such edit is listed in `docs/gpuix-shell/INTEGRATION.md` with the packet it belongs to. Steps, in order, each logged with its command and result: 1. Read every `## P-nn` block in BUILD-LOG and apply the `### Requests for P-mm` items that are seam fixes; the rest become `GAPS` candidates for P-51. 2. `$BUN x tsc --noEmit -p pkgs/gpuix-shell` → zero errors (fix seams; where a packet left a stub, keep the stub and note it). 3. `$BUN test` from `pkgs/gpuix-shell` → green; quarantine a failing test only by `test.skip` with a `// P-30: reason` comment and a GAPS line, never by deletion. 4. The fence and design-lint tests pass. 5. `$BUN build.ts` succeeds and `grep -c '^import .*@gpuix' pkgs/gpuix-shell/dist/main.js` is 0 (else fix `build.ts`/`main.ts` splitting; record the measured `time bun dist/main.js ping` with no socket → expect exit 3 in ≤ 100 ms). 6. Under the wrapper: start `bun src/main.ts daemon core` on a temp `XDG_RUNTIME_DIR` with P-01's fake Sway and P-02's fake `herdr` on PATH; `bun src/main.ts ping` → 0; `status --json` lists the core; `subscribe`-style check via `bun src/main.ts snapshot --json` shows nine slots; start `daemon notifications` under `dbus-run-session` and run `notify-send hello` with `GPUIX_SHELL_FAKE_CHILD=1` → `notifications list --json` contains it. 7. Run `smoke_hello.py` once more to prove the toolchain still opens a layer surface. 8. Write `docs/gpuix-shell/INTEGRATION.md`: what was wired, what is stubbed (table per seam entry: built / stub / broken), measured numbers, the exact command lines, and the list of packets whose work is unverified. 9. Append `ASSUMPTIONS` lines for every integration choice. Do not run surface smokes beyond step 7 (the complete packets do). Do not commit. Acceptance: steps 2–6 green or each failure named with its owner packet in INTEGRATION.md.

## 6.4 Stage complete (parallel)

### P-31 — Core daemon end-to-end under the harness: fake Sway + fake herdr → topics, supervisor, focus guard, attention
- **stage**: `complete`  
- **depends_on**: P-30  
- **owner_paths**:
  - `pkgs/gpuix-shell/src/daemons/core/**`
  - `!pkgs/gpuix-shell/src/daemons/core/handlers/*.ts`
  - `pkgs/gpuix-shell/src/daemons/core/handlers/supervisor.ts`
  - `pkgs/gpuix-shell/src/core/sway-ipc/**`
  - `pkgs/gpuix-shell/src/platform/sway/**`
  - `pkgs/gpuix-shell/src/core/herdr/**`
  - `pkgs/gpuix-shell/src/platform/herdr/**`
  - `tests/gpuix-shell/smoke_core.py`
  - `tests/gpuix-shell/test_core.py`
  - `docs/gpuix-shell/evidence/core/**`
- **brief** (303 words):

Prove and complete the headless core (ARCHITECTURE §3, §6.1, §6.2) with a real isolated Sway. `tests/gpuix-shell/smoke_core.py` under the harness (two outputs): start `daemon core` with `GPUIX_SHELL_DEV=1`, the fake `herdr` (`HERDR_FAKE_SNAPSHOT=blocked`) and the real headless `swaymsg`; assert over `shell.sock` (use P-05's client from `driver.mjs` or a 20-line Python NDJSON client): `core/hello` returns the session token of this `$SWAYSOCK`; `subscribe slots` yields ten slots with the fixture's names and glyph words; `swaymsg workspace number 3` → a `state slots` update with `focused` on 3 within 100 ms; `sway.focus-slot 4` → `confirmed`; an invalid name through `herdr.rename` → refused with `INVALID_PARAMS`; `launcher/toggle` spawns `surface launcher` (the real one if built, else the stub exits 69 → `surface.failed` event is published and the CLI exits 1 with the fix); `supervisor` closes the overlay when `swaymsg workspace number 5` fires while it is open (focus guard); a snapshot switch to `HERDR_FAKE_SNAPSHOT=blocked` (restart the fake with a different file) raises exactly one `Notify` with actions `default=Go`/`dismiss=Dismiss` on the daemon's D-Bus (run the notifications daemon under `dbus-run-session` with `GPUIX_SHELL_FAKE_CHILD=1` and read `notifications list --json`); herdr unavailable → `herdr.status unavailable` and ○ glyphs after two failures (point the fake at a missing file); the rail output-pin dance: with HEADLESS-2 focused, `rail.reload` restarts the rail on HEADLESS-1 and restores focus to HEADLESS-2 (skip with a clear message if the rail is still a stub). Hermetic `test_core.py`: the NDJSON client against the fake Sway only (no compositor), asserting the same message shapes. Fix what you find inside your owned paths; anything else is a BUILD-LOG request. Also complete S-038 (fullscreen → rail unit stop/restart) and S-016 `listen` streaming if missing. Evidence: `results.json`, `core.log`, `sway.log` under `docs/gpuix-shell/evidence/core/`. Acceptance: the smoke writes `ok:true` for every step it could run and names the steps it skipped; RSS of core measured (`/proc/<pid>/status VmRSS`) and written to BUILD-LOG.

### P-32 — Notifications conformance: the 14 notify-send cases on a private bus + toast pixels
- **stage**: `complete`  
- **depends_on**: P-30  
- **owner_paths**:
  - `pkgs/gpuix-shell/src/core/notifications/**`
  - `pkgs/gpuix-shell/src/platform/dbus/notifications-server.ts`
  - `pkgs/gpuix-shell/src/daemons/notifications/**`
  - `pkgs/gpuix-shell/src/surfaces/toasts/**`
  - `pkgs/gpuix-shell/src/core/registry/specs/notifications.ts`
  - `tests/gpuix-shell/smoke_notifications.py`
  - `tests/gpuix-shell/test_notifications.py`
  - `docs/gpuix-shell/evidence/notifications/**`
- **brief** (304 words):

Make ARCHITECTURE §7.4 true, case by case, and fix the daemon where it is not. `tests/gpuix-shell/test_notifications.py` (hermetic but under the wrapper because it needs a bus): `dbus-run-session` + the daemon with `GPUIX_SHELL_FAKE_CHILD=1`; drive with the real `notify-send` (libnotify from PATH; find it with `which`, skip with a message if absent) and `gdbus call`: cases 1–6, 12–14 of §7.4 (default expiry 5000 → reason 1 observed by `dbus-monitor`-free means: subscribe to the daemon's `notifications` topic or `notifications list --json` before/after; `-p` + `-r` same id and newest position; stale `-r` → new id; critical never expires without `-t`; `-t 2000` wins; `--action=default=Open --wait` + `notifications invoke <id>` → `ActionInvoked` then `NotificationClosed(2)` and `--wait` prints `default`; `-e` transient absent from `history --json`; 50 identical calls in 1 s → one card with ×N and ≤20 accepted; `dismiss`/`--all`/`restore`/`invoke`/`list`/`history`/`count`/`dnd` parity; a stub holding the name first → exit 69). `smoke_notifications.py` under the harness with a real Sway: start core + daemon; `notify-send a b` → the toasts child maps; grim pixels prove a raised card at top-centre x≈525..915, y≥12 (and at top-right with `config.toast.anchor=top-right`); `-u critical` → `line.urgent` edge pixel; `-h int:value:42` → a bar of `selection.bg`; `image-path` → 48 px thumbnail region non-background; 6 notifications → 4 cards + "(2 more)" in `ui-tree`; automation click on `toasts.card.<id>` → `ActionInvoked(default)`; right-click → dismissed reason 2; `osd` script contract (`notify-send -a osd -r 1 -h int:value:40 Volume`) → OSD child maps at bottom (margin 96) and no toast card; respawn-not-resize when the set changes shows no window taller than its cards (`ui-tree` + a pixel below the stack is wallpaper). Fix card-height estimation against real text (ARCHITECTURE §23 item 6) by comparing `ui-tree` bounds with the estimate; update the golden. Evidence under `docs/gpuix-shell/evidence/notifications/`. Acceptance: `test_notifications.py` green under the wrapper; the smoke's `results.json` lists each case with ok/skip and why.

### P-33 — Rail smoke + theme live-reload + fonts weights + per-output rail
- **stage**: `complete`  
- **depends_on**: P-30  
- **owner_paths**:
  - `pkgs/gpuix-shell/src/surfaces/rail/**`
  - `pkgs/gpuix-shell/src/items/{clock,battery,network,bluetooth,audio,bell,tailscale,media,pomodoro,recording,privacy,touchpad,custom}/**`
  - `pkgs/gpuix-shell/src/core/registry/specs/rail.ts`
  - `pkgs/gpuix-shell/src/daemons/core/handlers/rail.ts`
  - `pkgs/gpuix-shell/src/core/theme/**`
  - `pkgs/gpuix-shell/src/core/fonts/**`
  - `pkgs/gpuix-shell/src/platform/theme/**`
  - `pkgs/gpuix-shell/src/platform/fonts/**`
  - `home/themes/default.nix`
  - `tests/gpuix-shell/smoke_rail.py`
  - `tests/gpuix-shell/smoke_theme.py`
  - `tests/gpuix-shell/smoke_two_outputs.py`
  - `docs/gpuix-shell/evidence/rail/**`
  - `docs/gpuix-shell/evidence/theme/**`
- **brief** (330 words):

Prove SCOPE S-007, S-015, S-020–S-030, S-037, S-041 on a real isolated Sway and complete the P1 rail rows that are cheap (S-023 "+", S-040 launcher mark, S-045 agent marks as monochrome glyph/initial, S-042 focused-window line in expanded mode). `smoke_rail.py` (harness, one output 1440×900): start core (fake Sway is **not** used here; the real headless Sway is) + fake `herdr` + `daemon rail --output HEADLESS-1`; assert `get_workspaces` rect x==56; `ui-tree` of `rail.sock` lists `rail.slot.1..9` and `rail.ws10`; `HERDR_FAKE_SNAPSHOT=blocked` → the row's dot pixel equals `color.dot.waiting` of the running theme (read the fragment, compare within ±2 per channel); `swaymsg workspace number 3` → `rail.slot.3` carries the current bar (accent pixel at x=0..2); automation click on `rail.slot.5` → focused workspace 5; `rail expand` → the unit restarts (in dev mode core respawns) and the rect is x==220 with the title text in `ui-tree`; `rail collapse` → x==56; `rail hide` → rect x==0; the cluster shows `rail.item.clock` with `HH:MM` text; `notify-send` two notifications → bell badge "2". `smoke_theme.py`: with the three fragments in a temp `~/.config/themes/*/gpuix-shell.json` and a `~/.config/theme` symlink, flip the symlink noir → claude-light and assert the rail background pixel changes to `#F0EFEC` within 300 ms; `gpuix-shell theme reload` path too; an invalid fragment keeps the last good tokens and `notifications list` has one warning. Fonts: with `GPUIX_SHELL_FONT_DIR` pointing at static instances you generate into the evidence dir with fontTools from the installed variable face (never committed; `python3 -c 'import fontTools'` must exist, else skip and say so), prove a 600-weight numeral renders more ink than 400 (grim crop ink count, the wave1/15 P4 method). `smoke_two_outputs.py` (`outputs=2`, scale 2 variant): rail on HEADLESS-1 only; the reduced rail on HEADLESS-2 when `config.rail.perOutput` says so; Duo logical 1440×900 at scale 2 still yields x==56. Fix defects in your owned paths; log the rest as requests. Evidence under `docs/gpuix-shell/evidence/{rail,theme}/` incl. one PNG per state. Acceptance: `results.json` per smoke with ok/skip per step; the P0 steps (rect, nine rows, click, dot colour, theme flip) must be ok.

### P-34 — Launcher smoke + P1 launcher features (prefixes, detail pane, HUD, contextual root, scripts, snippets, screenshots, deeplinks)
- **stage**: `complete`  
- **depends_on**: P-30  
- **owner_paths**:
  - `pkgs/gpuix-shell/src/surfaces/launcher/**`
  - `!pkgs/gpuix-shell/src/surfaces/launcher/providers/{clipboard,files,tabs,emoji,wifi,bluetooth,audio,music}.ts`
  - `!pkgs/gpuix-shell/src/surfaces/launcher/providers/index.ts`
  - `pkgs/gpuix-shell/src/core/launcher/**`
  - `pkgs/gpuix-shell/src/core/apps/**`
  - `pkgs/gpuix-shell/src/platform/apps/**`
  - `pkgs/gpuix-shell/src/core/scripts/**`
  - `pkgs/gpuix-shell/src/core/registry/specs/launcher.ts`
  - `pkgs/gpuix-shell/src/core/registry/specs/dmenu.ts`
  - `pkgs/gpuix-shell/src/daemons/core/handlers/launcher.ts`
  - `tests/gpuix-shell/smoke_launcher.py`
  - `tests/gpuix-shell/smoke_dmenu.py`
  - `docs/gpuix-shell/evidence/launcher/**`
- **brief** (320 words):

Prove SCOPE §2.1 P0 rows on a real isolated Sway, then complete the P1 rows in this order: S-053 prefix modes end-to-end, S-057 detail pane + markdown, S-058 toasts-in-launcher + HUD via `osd/show`, S-088 contextual root section, S-071 script commands (scan `~/.local/share/gpuix-shell/scripts`, modes fullOutput/compact/silent/terminal/inline), S-075 snippets & shortcuts (JSON in state, `{clipboard}`/`{date}`/`{query}` placeholders), S-076 `>` shell mode with live output, S-077 media commands, S-080 screenshots browse, S-087 deeplinks (`gpuix-shell://` and `vicinae://` parser + `x-scheme-handler` entry request to P-47), S-090–S-093 script wrappers, S-094 shell services/doctor view (`;`). `smoke_launcher.py` (harness; core + fake herdr + a fixture `applications/` dir on `XDG_DATA_DIRS` with Google Chrome, Nautilus, a `NoDisplay` entry and an `OnlyShowIn=GNOME` entry): `launcher toggle` → the overlay maps in ≤0.6 s (measure spawn→`surface/ready` from the core log), `ui-tree` has `launcher.input`; `fill("chrome")` → first row is Google Chrome, the NoDisplay/OnlyShowIn entries absent; `press("enter")` on a command row (`Toggle do not disturb`) → `notifications dnd status` flips and the echo appears in the footer node; `press("escape")` → the process is gone within 200 ms; second `launcher toggle` while open closes it; `launcher open --view herdr` → ten workspace rows with glyph words, `fill("@")` lists windows (open two `kitty`-free test clients: use `swaymsg exec` of a tiny `bun` script that opens an xdg toplevel through `@gpuix/react`, or skip with a message); `=2+2` → "4" row and Enter copies via the fake `wl-copy` logger; `Ctrl+K` opens the action panel node; `t ` lists three themes. `smoke_dmenu.py`: `printf 'a\nb\n' | gpuix-shell dmenu -p Pick` → select `b` by automation → stdout `b` exit 0; Escape → exit 1; `-f index`; the compat framing path by running P-20's edited `herdr-picker --workspace rename` against the socket with the fake herdr (skip if the script needs a live herdr). Fix what you find in your paths; request elsewhere. Evidence under `docs/gpuix-shell/evidence/launcher/`. Acceptance: the P0 smoke steps ok; each P1 feature has a `bun test` and a one-line status in BUILD-LOG.

### P-35 — Clipboard end-to-end + paste path + cliphist import + emoji smoke
- **stage**: `complete`  
- **depends_on**: P-30  
- **owner_paths**:
  - `pkgs/gpuix-shell/src/surfaces/launcher/providers/{clipboard,emoji}.ts`
  - `pkgs/gpuix-shell/src/core/clipboard/**`
  - `pkgs/gpuix-shell/src/platform/clipboard/**`
  - `pkgs/gpuix-shell/data/glyphs.json`
  - `pkgs/gpuix-shell/data/README.md`
  - `pkgs/gpuix-shell/data/gen-glyphs.ts`
  - `pkgs/gpuix-shell/src/core/registry/specs/clipboard.ts`
  - `pkgs/gpuix-shell/src/daemons/core/handlers/clipboard.ts`
  - `tests/gpuix-shell/smoke_clipboard.py`
  - `docs/gpuix-shell/evidence/clipboard/**`
- **brief** (318 words):

Prove SCOPE S-064, S-145–S-147 and S-068 against real `wl-clipboard` on an isolated Sway, and complete the P1 paste path and the cliphist import. `smoke_clipboard.py` (harness; core started with the two real `wl-paste --watch gpuix-shell clipboard ingest …` children; `wl-copy` from PATH): `wl-copy hello` → within 1 s `clipboard list --json` has one text row with preview `hello` and `kind text`; `wl-copy https://example.org` → kind `link`; `wl-copy '#D97757'` → kind `colour`; `wl-copy < fixture.png` (`--type image/png`) → kind `image`, a blob under `clipboard/blobs/<sha>` 0600 and a thumbnail; the same text copied twice → one row (dedupe); a copy offered with `x-kde-passwordManagerHint` (use `wl-copy --type x-kde-passwordManagerHint secret` alongside, or set `CLIPBOARD_STATE=sensitive` on a direct `clipboard ingest` call) → no row; `clipboard pin <id>` then eviction with a fake clock (call the store's evict with `now + 2 days` through a `--now` test flag) keeps the pinned row; `launcher open --view clipboard` → rows 56 with `launcher.row.clipboard:<id>` and the image row's thumbnail node; Enter → the fake `wl-copy` logger receives the bytes on stdin with the stored mime and no argv payload; `clipboard clear --yes` → empty; kill one watcher child → core restarts it (check the process list after 2 s). Paste path S-147: if `wtype` is on PATH, Enter also runs `wtype` prefixed by the no-op key, else copy + HUD (assert the `osd/show hud` call in the core log). `clipboard import-cliphist`: read a `cliphist list`-style fixture plus `cliphist decode`-style blobs via a fake `cliphist` on PATH → rows imported with their kinds. Emoji: `launcher open --view emoji` + `fill("shrug")` → the 🤷 row first; Enter copies; grid layout 8 columns in `ui-tree`. Also verify FTS5 is available in bun's SQLite (`SELECT fts5(?)`) and record which path the store uses (ARCHITECTURE §23 item 9). Fix in your paths; request elsewhere. Evidence under `docs/gpuix-shell/evidence/clipboard/`. Acceptance: P0 steps ok in `results.json`; the import and paste paths each have a `bun test`.

### P-36 — Switcher smoke on two outputs (pin dance) + Alt-Tab cycle + row actions
- **stage**: `complete`  
- **depends_on**: P-30  
- **owner_paths**:
  - `pkgs/gpuix-shell/src/surfaces/switcher/**`
  - `pkgs/gpuix-shell/src/core/registry/specs/switcher.ts`
  - `pkgs/gpuix-shell/src/core/registry/specs/sway.ts`
  - `pkgs/gpuix-shell/src/daemons/core/handlers/sway.ts`
  - `pkgs/gpuix-shell/src/platform/sway/output-pin.ts`
  - `tests/gpuix-shell/smoke_switcher.py`
  - `docs/gpuix-shell/evidence/switcher/**`
- **brief** (294 words):

Prove SCOPE S-121 and S-015 with two headless outputs, then complete S-122 (Mod-held cycle seam) and S-123 (row actions). `smoke_switcher.py` (harness `outputs=2`: HEADLESS-1 1440×900 at (0,0) with workspaces 1–9, HEADLESS-2 at (0,900) with workspace 10; core + fake herdr `live` snapshot; `config.rail.output = HEADLESS-1` and the switcher pinned to it): `swaymsg focus output HEADLESS-2`; `switcher toggle` → the overlay maps on HEADLESS-1 (prove it: `grim -o HEADLESS-1` shows the raised panel at x≈440..1000, y≥108 while `grim -o HEADLESS-2` at the same spot is wallpaper) and after `press("escape")` the focused output is HEADLESS-2 again (`get_outputs` focused), i.e. the pin dance restored focus and the focus guard did not close the surface during the dance; `ui-tree` lists ten rows `switcher.row.<n>` with the fixture's names and words, the current workspace is not first, a `blocked` slot shows "Needs input"; `press("3")` → focused workspace 3 and the process exits; `switcher toggle` twice fast (≤150 ms apart) → nothing stays mapped; `fill("!")` → only blocked rows; Ctrl+B → the actions node with Rename/Restore/Close/Move here/Sidebar; "Close" needs the two-step (first Enter arms, second runs the `herdr.close` exec with the fake `sway-workspace` logger on PATH); Enter while `HERDR_FAKE_SNAPSHOT` is missing → the row says "herdr unavailable" and focus still switches (Sway-only). If `keyboardInteractivity` or the dance misbehaves, fix `output-pin.ts`/the supervisor's use of it (you own `output-pin.ts` in this stage; coordinate nothing else) and log the measured timings (spawn→ready, dance total). S-122: implement the "Mod held + repeated i cycles, release commits" as a seam: `switcher cycle` verb moving the selection in the open instance, documented as not bound tonight (Sway cannot report Mod release). Evidence: two PNGs per step under `docs/gpuix-shell/evidence/switcher/`. Acceptance: `results.json` ok for mapping-on-eDP-1, focus restore, ten rows, digit jump, double-toggle; everything else ok or skipped with a reason.

### P-37 — Controls smoke + bluetooth pairing agent + battery/PPD + tailscale + input + brightness + media + keyboard mode decision
- **stage**: `complete`  
- **depends_on**: P-30  
- **owner_paths**:
  - `pkgs/gpuix-shell/src/surfaces/controls/**`
  - `pkgs/gpuix-shell/src/surfaces/launcher/providers/{wifi,bluetooth,audio}.ts`
  - `pkgs/gpuix-shell/src/core/registry/specs/controls.ts`
  - `pkgs/gpuix-shell/src/daemons/core/handlers/controls.ts`
  - `pkgs/gpuix-shell/src/core/dbus/**`
  - `pkgs/gpuix-shell/src/platform/dbus/**`
  - `!pkgs/gpuix-shell/src/platform/dbus/notifications-server.ts`
  - `pkgs/gpuix-shell/src/platform/audio/**`
  - `pkgs/gpuix-shell/src/platform/tailscale/**`
  - `tests/gpuix-shell/smoke_controls.py`
  - `tests/gpuix-shell/fakes/dbus/**`
  - `docs/gpuix-shell/evidence/controls/**`
- **brief** (374 words):

Prove SCOPE S-126 and S-128 with fake D-Bus services, decide the keyboard mode (ARCHITECTURE §23 item 5), and complete the P1 domains S-127 (BlueZ Agent1 wired to the pairing card), S-129, S-130, S-131, S-133, S-134, S-135, S-136. Write `tests/gpuix-shell/fakes/dbus/{nm,bluez,upower,ppd,mpris}.ts` — `bun` scripts using the package's own `dbus-next` (Python `dbus` bindings are not guaranteed on this box) — that own the real bus names on a private `dbus-run-session` **system** bus (`DBUS_SYSTEM_BUS_ADDRESS` pointed at the session address) and expose the interfaces/members of P-03's tables with fixture state and mutation methods (`AddAndActivateConnection` records the settings dict and flips the active AP; `Pair` calls back `RequestConfirmation` on the registered agent). `smoke_controls.py` (harness with `dbus=True` and the fakes; core + the controls surface): `controls open wifi` → the panel maps top-right (grim at x≈1008..1428, y≥12); rows list the fake APs by strength with the connected SSID first; Enter on a secured unknown SSID → the inline password node `controls.wifi.password`; `fill("hunter2")` + Enter → the fake NM received a settings dict with `psk hunter2` and **the core log contains no `hunter2`** (grep the whole evidence dir); a wrong password (fake rejects) → the danger word in `ui-tree`; `f` on a saved network → two-step forget; Ctrl+R → `RequestScan` called; `controls open audio` → sinks from a fake `wpctl` on PATH, Enter → the fake `audio-route` logger receives the sink; `controls open bluetooth` → power switch toggles the fake `Powered`, "Pair a new device" lists discovered devices, Enter → the fake calls `RequestConfirmation` → the confirm card with the passkey figures; Enter before 600 ms is ignored, after it the fake sees the confirmation; Esc → `Rejected`; `controls open battery` → UPower detail and the PPD selector flips the fake profile; `controls open tailscale` → peers from a recorded `tailscale status --json` fixture via a fake `tailscale` on PATH; `controls open dnd` → `notifications dnd status` flips; Left/Right switches domains; Esc backs out then closes. Keyboard mode: run the wifi page twice, once with `on-demand` and once with `exclusive`; record whether typing reaches the password field under `on-demand`; set the default accordingly in `window-options` for controls (log the ASSUMPTION). Evidence under `docs/gpuix-shell/evidence/controls/`. Acceptance: wifi and audio steps ok; bluetooth/battery/tailscale ok or skipped with the reason; the secret-never-logged assertion must be ok.

### P-38 — Power + OSD smokes, observed-service OSD (volume/brightness changes), audio-route and media OSD, osd CLI
- **stage**: `complete`  
- **depends_on**: P-30  
- **owner_paths**:
  - `pkgs/gpuix-shell/src/surfaces/power/**`
  - `pkgs/gpuix-shell/src/core/registry/specs/power.ts`
  - `pkgs/gpuix-shell/src/daemons/core/handlers/power.ts`
  - `pkgs/gpuix-shell/src/surfaces/osd/**`
  - `pkgs/gpuix-shell/src/core/registry/specs/osd.ts`
  - `tests/gpuix-shell/smoke_power.py`
  - `tests/gpuix-shell/smoke_osd.py`
  - `tests/gpuix-shell/fakes/logind/**`
  - `docs/gpuix-shell/evidence/power/**`
  - `docs/gpuix-shell/evidence/osd/**`
- **brief** (393 words):

Prove SCOPE S-140 and S-115–S-117 on an isolated Sway, then complete S-118, S-119, S-120 (anchor config) and the P1 half of S-115 ("observe the service, not the key"). `tests/gpuix-shell/fakes/logind/` = a fake `org.freedesktop.login1` on the private bus (bun + dbus-next, or reuse P-37's fake shape if it exists at run time; otherwise your own) recording `PowerOff`/`Reboot`/`Suspend` calls, plus fake `systemctl`/`loginctl`/`monitors-off`/`sleep-monitors`/`brightness` loggers on PATH. `smoke_power.py` (harness, `dbus=True`): `power toggle` → the centred 360-wide panel maps; `ui-tree` rows in the DESIGN A-23 order, no Hibernate (no swap in the sandbox), no Suspend (config off), no Lock; cursor on Monitors off; `press("enter")` on Monitors off → the logger ran `monitors-off` and the process exited; reopen, move to Reboot, `press("enter")` once → **nothing** called after 500 ms; automation `keyDown("r")` held 1600 ms (use `app.keyboard`-style down/up or `mouse.down` on the row and `mouse.up` after 1.6 s) → the fake logind saw exactly one `Reboot(true)`; held 1200 ms then released → zero calls and the fill snapped back (`ui-tree` progress node 0); footer shows "2 slots need input" with the `blocked` fixture; `gpuix-shell power reboot` from a non-TTY without `--yes` → exit 1 and no call; with `--yes` → one call; `gpuix-shell lock` → exit 69; `inhibit toggle` → a `systemd-inhibit` logger child appears and disappears. `smoke_osd.py` (harness): via the `osd` script contract (`notify-send -p -a osd -r 1 -t 1500 -h int:value:40 Volume`) → the 280×56 card at bottom margin 96 (grim: raised pixels around y≈748..804, x≈580..860) with the bar at 40 % (pixel at the fill's end), no toast; a second call with `int:value:60` updates in place (same pid); the card is gone 1.5 s + 0.2 s after the last call; `gpuix-shell osd brightness 70` and `osd show --icon volume --label Speakers --value 20` work; `osd mic off` draws a word and no bar; while the launcher is open an OSD call is suppressed (no card; `ui-tree` of osd.sock absent); the observed-service path: with a fake `pw-dump --monitor` on PATH emitting a volume change → an OSD card appears without any notify-send (P1); `audio-route` changes → the route card; `media next` with a fake MPRIS player → the media card; `config.osd.anchor` alternatives (8 anchors) each map where expected (pixel probe per anchor, at least top-center and bottom-center). Evidence under `docs/gpuix-shell/evidence/{power,osd}/`. Acceptance: hold-fires-once, Enter-does-nothing, lock-69, OSD-card-no-toast, suppression must be ok; the rest ok or skipped with reasons.

### P-39 — Notification centre smoke + hints overlay + grouping + rules + sounds/privacy seams
- **stage**: `complete`  
- **depends_on**: P-30  
- **owner_paths**:
  - `pkgs/gpuix-shell/src/surfaces/center/**`
  - `pkgs/gpuix-shell/src/core/notifications/rules.ts`
  - `pkgs/gpuix-shell/src/core/notifications/grouping.ts`
  - `pkgs/gpuix-shell/src/core/notifications/hints.ts`
  - `pkgs/gpuix-shell/src/daemons/notifications/handlers.ts`
  - `tests/gpuix-shell/smoke_center.py`
  - `docs/gpuix-shell/evidence/center/**`
- **brief** (331 words):

Complete and prove SCOPE S-107, S-114, S-103, S-108, S-111, S-112, S-113 (the P1/P2 notification rows that are not the daemon's core path; P-32 owns the server and toasts). You own only the files listed; coordinate with P-32 through BUILD-LOG requests if `store.ts` needs a hook (ask for a named hook, do not edit it). `smoke_center.py` (harness, `dbus=True`; core + notifications daemon + a seeded history of 12 notifications across three apps via `notify-send` loops, two of them transient): `notifications toggle` → the 500×650 overlay maps top-right; `ui-tree` has the Current/History tabs, groups per app with counts, rows 56 with the hint letters `[a]`…; `press("b")` → the second row's default action is invoked (`ActionInvoked`) and the row leaves Current; `Tab` → History shows the dismissed one; `d` dismisses the selected, `Shift+D` dismisses all (history kept: count unchanged), `u` restores the last dismissed, `n` toggles DND (bell state in the rail topic flips), `Ctrl+Shift+X` twice clears history (once does nothing), `Esc` closes; a group of 4 from one app collapses after 3 with a "+1" row and Enter expands it; the hints overlay on toasts: `notifications hints` → letters drawn on the visible toast cards (toasts `ui-tree` has `toasts.hint.a`), a letter invokes, Shift+letter dismisses, Esc clears; rules from config (`{match:{app:"kitty", summary:"^OSC"}, action:"silent"}`) → a matching notify-send produces no toast but is in history; `{action:"drop"}` → nowhere; `route-to-osd` → the OSD; `notifications privacy on` → toast bodies hidden (the body text absent from the toasts `ui-tree`, present in the centre); S-113 focused-app suppression with `transient` and a matching `desktop-entry` of the focused window (skip if no window can be focused in the harness); S-111 sounds: config per urgency → a `pw-play` logger on PATH is called with the configured file (off by default: assert no call without config). Pure tests for grouping, hints letter assignment (a–z then aa), rules precedence, privacy masking. Evidence under `docs/gpuix-shell/evidence/center/`. Acceptance: toggle, tabs, letters, dismiss/restore, DND, clear-history two-step must be ok; the rest ok or skipped with a reason.

### P-40 — Files explorer smoke + preview + jobs/undo/trash + send to agent + grid/gallery + picker seam
- **stage**: `complete`  
- **depends_on**: P-30  
- **owner_paths**:
  - `pkgs/gpuix-shell/src/surfaces/files/**`
  - `pkgs/gpuix-shell/src/core/files/**`
  - `pkgs/gpuix-shell/src/core/registry/specs/files.ts`
  - `tests/gpuix-shell/smoke_files.py`
  - `tests/gpuix-shell/fixtures/files/**`
  - `docs/gpuix-shell/evidence/files/**`
- **brief** (337 words):

Prove and complete SCOPE S-155–S-158 (P1) and S-159/S-160 as far as time allows, on an isolated Sway with a generated temp tree (`fixtures/files/make-tree.py`: `Downloads/` with 30 files of mixed kinds and dates incl. a 2 MB file, hidden files, a nested `Paper/inbox`, a markdown note, a PNG, a PDF if `pdftoppm` exists). `smoke_files.py` (harness; `HOME` and XDG dirs redirected to the temp tree; `gio` real if present else a logger): `files open <tree>/Downloads` → an xdg toplevel with `app_id gpuix-shell-files` appears in `swaymsg -t get_tree` (this one is a real window) and Sway tiles it; `ui-tree` has the places rail (`files.place.downloads` current), header crumbs, list rows `files.row.<name>` sorted by name with age/size figures; `Ctrl+H` shows hidden; `Ctrl+L` + `fill("~/Paper/inbox")` + Enter navigates; type-to-jump `s` moves the cursor to the first `s` file; `fill` into the filter `kind:image` leaves only the PNG; `>1M` leaves the 2 MB file; `Space` opens the preview column at a window ≥1240 wide (run a second window at 1280×800 through `swaymsg resize` or accept the default and assert the preview is absent below 1240 and present after `Ctrl+Shift+F`-free resize; record which); `Delete` on a file → `gio trash` ran (or the logger), the Undo pill node appears, `Ctrl+Z` within 60 s → the file is back; `F2` → inline rename then Enter renames on disk; `Ctrl+Shift+N` creates a folder; `Ctrl+C` then `Ctrl+V` in another folder copies with the job progress node; `Shift+Delete` → the sheet with the 1500 ms hold, Enter alone = the safe button; "Send to slot 3" → the fake `wl-copy` logger receives the path and `sway.focus-slot 3` ran; `Ctrl+1/2/3` switch list/grid/gallery (`ui-tree` kind); `Ctrl+=` zoom changes the row height in `ui-tree` bounds; `Ctrl+W` closes the window and the process exits; two `files open` calls → two windows, two processes. Picker seam S-160: `files pick --multiple` prints selected paths on Enter (implement if time; else skip and say so). Fix in your paths; evidence PNGs under `docs/gpuix-shell/evidence/files/`. Acceptance: open/list/navigate/filter/trash+undo/rename/close must be ok; the rest ok or skipped with the reason.

### P-41 — Nix build to green: package, checks, home-profiles, client toplevel, static fonts, D-Bus activation
- **stage**: `complete`  
- **depends_on**: P-30  
- **owner_paths**:
  - `pkgs/gpuix-shell/default.nix`
  - `pkgs/anthropic-ui-static.nix`
  - `home/gpuix-shell.nix`
  - `flake.nix`
  - `overlays/default.nix`
  - `home/home.nix`
  - `home/vicinae.nix`
  - `hosts/client/default.nix`
  - `tests/gpuix-shell/smoke_nix_rail.py`
  - `docs/gpuix-shell/evidence/nix/**`
- **brief** (346 words):

Take P-19's recipe to a green build against the integrated tree and prepare the (not executed) switch. In order, logging each command and its result in BUILD-LOG: 1. `git add -N` the new paths (idempotent). 2. `nix shell --inputs-from . nixpkgs#prefetch-npm-deps -c prefetch-npm-deps pkgs/gpuix-shell/package-lock.json` → paste `npmDepsHash`. 3. `nix build .#gpuix-shell -L` until green; expected log order tsc → `bun test` → `auto-patchelf: 0 dependencies could not be satisfied` → installCheck; tests that need a bus, a compositor, mpv or the network must be `skipIf`-guarded or live under `tests/gpuix-shell/` — fix by **requests** to the owners if a test is wrong, by `nativeCheckInputs` if a tool is merely missing (`mpv`, `dbus`, `wl-clipboard`, `libnotify`). 4. `nix build .#checks.x86_64-linux.gpuix-shell-themes -L` (the three fragments pass `--check-theme`) and `.#checks.x86_64-linux.gpuix-shell-contract`. 5. `nix flake check --offline --no-build` and `nix build .#checks.x86_64-linux.home-profiles -L` with the revised asserts (XOR vicinae/mako on the client; never on the strix; units; package; `themes/noir/gpuix-shell.json` present). 6. `nix eval .#nixosConfigurations.client.config.home-manager.users.tom.programs.gpuixShell.enable` → `true`, strix → `false`. 7. `nix build .#nixosConfigurations.client.config.system.build.toplevel --no-link -L` (slow; run in the background with `run_in_background` and poll). 8. `pkgs/anthropic-ui-static.nix`: build it (`nix build .#anthropic-ui-static`), verify with `fc-scan` that each instance's family is exactly "Anthropic Sans"/"Anthropic Serif" and the weights 400/500/600 differ; if the NAS `requireFile` tarball is missing on this box, document the exact `nix-store --add-fixed` command and mark unverified. 9. `tests/gpuix-shell/smoke_nix_rail.py` (the wave1/21 §5.6 template): the **Nix-built** `result/bin/gpuix-shell daemon rail --output HEADLESS-1` under the harness with no `LD_LIBRARY_PATH` and no `VK_ICD_FILENAMES` → rect x==56 (this proves the RUNPATH and the nixpkgs Vulkan loader); also `result/bin/gpuix-shell ping` exits 3 in ≤100 ms with no core, and `--check-native`/`--check-dbus` print ok. 10. Verify the D-Bus activation file lands in `$out/share/dbus-1/services/` and the HM module puts the package in `home.packages` (so the user bus sees it; whether the bus honours it is unverified, say so). 11. `nix build .#checks.x86_64-linux.deadnix` and `nix fmt` on the new `.nix` files. Evidence (store paths, closure size via `nix path-info -Sh`, log tails) under `docs/gpuix-shell/evidence/nix/`. Acceptance: steps 3–5 green and step 9 ok; everything else green or named as a gap with the owner.

### P-42 — Chrome tabs bridge end-to-end with a fake extension + files provider smoke + deeplink handler
- **stage**: `complete`  
- **depends_on**: P-30  
- **owner_paths**:
  - `pkgs/gpuix-shell/src/surfaces/launcher/providers/{tabs,files}.ts`
  - `pkgs/gpuix-shell/src/platform/chrome/**`
  - `pkgs/gpuix-shell/src/daemons/native-host/**`
  - `tests/gpuix-shell/smoke_tabs.py`
  - `tests/gpuix-shell/fakes/chrome-extension.mjs`
  - `docs/gpuix-shell/evidence/tabs/**`
- **brief** (304 words):

Prove SCOPE S-067 and S-065 end-to-end without Chrome, and leave the real-extension check for Tom. `tests/gpuix-shell/fakes/chrome-extension.mjs`: a `bun` script that launches `gpuix-shell-native-host` the way Chrome does (`bun src/main.ts native-host` with argv `chrome-extension://kcmipingpfbohfjckomimmahknoddnke/` and a stdio pipe), speaks the uint32-LE-length JSON framing, sends `browser/init` then a `browser/tabs-changed` payload (12 tabs across two windows, one audible, one pinned, duplicate titles), answers `browser/focus-tab` and `browser/close-tab` by echoing them to a log file. `smoke_tabs.py` (harness; core + the fake extension): `gpuix-shell status --json` shows `browser.lastInit` within 2 s; `launcher open --view tabs` → 12 rows `launcher.row.tabs:<id>` with title/url/window and the audible/pinned marks; `fill("example")` ranks url matches above title matches (fuzzy url 1.0 / title 0.6); Enter → the fake received `browser/focus-tab {id}` **and** core ran `sway.focus-slot 10` (the fake Sway or real headless Sway shows workspace 10 focused); Ctrl+B → close tab and copy url actions; "Create shortcut from active tab" writes a quicklink into state; kill the fake → the Tabs scope is listed disabled with "needs the browser bridge" and core logs the disconnect; restart → rows return. Also the files provider on a temp tree: `launcher open --view files` + `fill("scan")` → `fd` rows with kind glyphs; Enter → `gio launch`/`xdg-open` logger; "Reveal in explorer" → `files open --select <path>` invoked; trash → `gio trash` logger. Deeplinks: `gpuix-shell deeplink 'gpuix-shell://launch/clipboard:history?toggle=1'` and the `vicinae://` alias → the same view opens; an `x-scheme-handler` desktop entry is a request to P-47 (do not register `vicinae` while Vicinae is installed). Verify the HM manifest text (P-19's `com.vicinae.vicinae.json`) names `gpuix-shell-native-host` and the extension origin, by `nix eval` of the client's `xdg.configFile."google-chrome/NativeMessagingHosts/com.vicinae.vicinae.json".text`. Write the one-minute hand check for MORNING.md (open Mod+d, type `tabs `, expect Chrome tabs; if "needs the browser bridge" shows, run `gpuix-shell doctor` check 11). Evidence under `docs/gpuix-shell/evidence/tabs/`. Acceptance: init, 12 rows, ranking, focus+workspace-10, disconnect-state must be ok.

### P-43 — Music integration: launcher `m ` view, rail chip, MPRIS media item, music unit, CLI through core, demo under the wrapper
- **stage**: `complete`  
- **depends_on**: P-30  
- **owner_paths**:
  - `pkgs/gpuix-shell/src/music/**`
  - `pkgs/gpuix-shell/src/surfaces/launcher/providers/music.ts`
  - `pkgs/gpuix-shell/src/core/registry/specs/music.ts`
  - `tests/gpuix-shell/music/**`
  - `docs/gpuix-shell/music/**`
- **brief** (319 words):

Finish MUSIC.md §10 (hooks into the rest of the shell) and the M-steps P-23 left undone, in P-23's order, then prove the lane under the wrapper with the fake catalogue. Deliver: `gpuix-shell music serve` as a headless daemon registering with core (`service/register {name:"music", methods: music/*}` + `service/publish {topic:"music"}`) so `gpuix-shell music play|pause|…` from the CLI reaches `ctl.sock` through core or directly (both must work; the CLI never loads the addon); the launcher provider `music` embedded (`launcher open --view music`, prefix `m `, Top result · Songs · Artists · Albums · Playlists, Enter plays and keeps the launcher open, Shift+Enter plays and closes, the MUSIC.md keymap incl. Ctrl+Right/Left next/prev, Alt+P/S/R/N/L, Ctrl+L like, Ctrl+I detail, a 3 px progress bar under the current track, art as local cache paths only); the `media` rail item consuming `NowPlayingChip` (click → `launcher open --view music/now-playing`, middle = toggle, wheel = music volume, hidden when idle/daemon down); MPRIS `org.mpris.MediaPlayer2.gpuix_music` visible to `playerctl -l` under `dbus-run-session`; OSD on transport outside the launcher via `osd/show media`; `src/music/integration/unit.ts` text for `gpuix-shell-music.service` matches ARCHITECTURE §11 (P-19 already emits it behind `music.enable`); `DEMO.md` with the exact morning commands (strix only while the credential is strix-only; `on-client.sh` documented with its `--fake` refusal). `tests/gpuix-shell/music/smoke_music.py` (harness, `dbus=True`, `NAVIDROME_FAKE=1`, mpv `--ao=null` from PATH): start `music serve` with the fake catalogue; `gpuix-shell music search "daft"` → JSON rows; `music play <id>` → `music now` shows playing and `positionAt` advancing; `playerctl status` → Playing; `launcher open --view music` + `fill("tal")` → the `tal` case ordering from MUSIC.md; Enter → `now` changes; the rail chip node appears in the rail `ui-tree` and disappears after `music stop`; a token never appears in any log, `ui-tree`, `results.json` or state file (grep the evidence dir for the fake token string). Secrets tests from MUSIC.md §4 all green. Evidence under `docs/gpuix-shell/music/evidence/gui/`. Acceptance: `$BUN test src/music` green in the sandbox; the smoke's P0 steps (search, play, playerctl, launcher view, token-never-leaks) ok.

### P-44 — Extension host core (Vicinae/Raycast grammar): Bun worker, @gpuix-shell/api, reconciler, List/Detail/ActionPanel/Form/Storage
- **stage**: `complete`  
- **depends_on**: P-30  
- **owner_paths**:
  - `pkgs/gpuix-shell/src/extensions/**`
  - `pkgs/gpuix-shell/src/surfaces/launcher/providers/extensions.ts`
  - `tests/gpuix-shell/fixtures/extensions/**`
  - `docs/gpuix-shell/EXTENSIONS.md`
- **brief** (341 words):

Build SCOPE S-096 (the P1 core) and S-097 as a new area `src/extensions/` that plugs into the launcher as one more `LauncherProvider` (`providers/extensions.ts`, new file; request P-30/P-52 to add it to `providers/index.ts` — do not edit the seam yourself). Study `/home/tom/Downloads/vicinae` (`api/`, `extension-manager/`, the boilerplate's 23 sample commands) and wave1/36 §3.1–§3.5, §4.2–§4.8. Deliver: `manifest.ts` (zod schema of the Vicinae `package.json` manifest: commands with `mode view|no-view` (`menu-bar` dropped, `interval` parsed and gated off), preferences, arguments), `scan.ts` (`~/.local/share/gpuix-shell/extensions/*` + `programs.gpuixShell.extensions` dirs from config), `wire.ts` (the view-tree wire vocabulary: intrinsics `list list-item list-section accessory detail metadata grid form-* action-panel action-*`, handlers → ids, 60/s debounce), `worker.ts` (one Bun `Worker` per launched command, `@gpuix-shell/api` resolved via an import map/alias to `api/index.ts`), `api/` (`List`, `List.Item`, `List.Section`, `Detail`, `Detail.Metadata`, `Grid` (P2 stub), `Form` fields, `ActionPanel`, `Action.*` (Push, CopyToClipboard via wl-copy through the host, Open, OpenInBrowser, Trash via gio, ShowInFinder → `files open --select`, Paste = copy + HUD), `useNavigation`, `LocalStorage` (per-extension JSON under state), `Cache` (pure TS), `getPreferenceValues`, `environment` (appearance from the theme topic), `LaunchProps`, `launchCommand`, `Clipboard`, `showToast`, `showHUD`, `confirmAlert`, `open`, `getApplications` (core apps topic), `runInTerminal` (kitty), `WindowManagement` (Sway topic), `BrowserExtension` (tabs topic), `AI` and `Wallpaper` `canAccess=false`), `reconciler.ts` (a `react-reconciler` host inside the worker serialising the tree; `react-reconciler` is a new dependency → BUILD-LOG request to P-41 with the exact pinned version, and until it lands use the worker-side mini-renderer that walks the element tree each render), `render.tsx` (host side: wire tree → `ui/kit` rows/sections/detail/form/action panel inside the launcher's view stack), `@raycast/api` alias with throwing stubs for unsupported symbols. Conformance: `tests/gpuix-shell/fixtures/extensions/` holds the boilerplate's list, list-detail, form, nested-form, paginated, controlled-list and window-switcher commands (copied with their ISC licence note); `bun test` renders each to a wire tree and acts (Enter, push, pop, submit) asserting the tree shape. `docs/gpuix-shell/EXTENSIONS.md`: how to install an extension by Nix, what is supported, what reports unavailable. Acceptance: `$BUN test src/extensions` green; a launcher smoke step (if the launcher smoke infrastructure is reusable without editing P-34's file: a separate `tests/gpuix-shell/smoke_extensions.py` you own) shows the list sample's rows in `ui-tree`; everything unverified is named.

### P-45 — Gallery + ask surface under the wrapper, OpenUI replay, design-lint sweep, ui/kit completion and empty states
- **stage**: `complete`  
- **depends_on**: P-30  
- **owner_paths**:
  - `pkgs/gpuix-shell/src/ui/**`
  - `pkgs/gpuix-shell/src/openui/**`
  - `pkgs/gpuix-shell/src/surfaces/ask/**`
  - `pkgs/gpuix-shell/src/surfaces/gallery/**`
  - `pkgs/gpuix-shell/src/core/registry/specs/ask.ts`
  - `tests/gpuix-shell/smoke_gallery.py`
  - `tests/gpuix-shell/smoke_ask.py`
  - `docs/gpuix-shell/evidence/gallery/**`
  - `docs/gpuix-shell/evidence/ask/**`
- **brief** (343 words):

Make the component library whole and prove it visually (DESIGN U-19, §10 checklist). `smoke_gallery.py` (harness): `gallery open` → the 1200×800 toplevel; `ui-tree` contains one node per token group and per `ui/kit` component, the five run-state rows, a toast card, an OSD card, a power row mid-hold; grim crops prove: no pixel outside the panel radius is drawn on transparent overlays (sample the four corner pixels of a rounded card = wallpaper), the hairline between rows is exactly 1 px, the focus ring appears only after a key event (click a row → no ring pixel; `press("down")` → ring pixel), the working dot steps between 1 and 0.55 opacity (two samples 300 ms apart differ), `motion.scale=0` in a temp fragment → identical frames; run the gallery under all three fragments and store one PNG each; the Nerd glyphs (󰁹 󰤨 󰂯 󰕾 󰂚) render (ink present in their cells; DESIGN §7.3 says this is the first check). Design-lint sweep: run `ui/design-lint.test.ts` over the whole `src/surfaces` tree now that every surface exists; fix violations inside `src/ui` and report the others as requests with file:line. Complete `ui/kit` gaps found by other packets' BUILD-LOG requests (new components they asked for), the `Empty` states vocabulary (DESIGN §7.3 words), the `Keycap` armed style, the Echo + Undo timing, and `ScaleProvider` for the files window. Ask: `smoke_ask.py` (harness; a fake OpenAI-compatible server on 127.0.0.1 serving the recorded SSE fixtures; `~/.config/gpuix-shell/model.json` pointing at it; **never** `strix:8731`): `ask toggle` → the panel with the clay mark; `fill("which workspace needs input")` + Enter → streamed prose then a validated `WorkspaceRow` whose status word is host-filled from the `blocked` fixture; the one `ShellAction` button is disabled until validation and then `Ctrl+Enter` invokes `sway.focus-slot` through core (`source:"surface"`); the invalid fixture (literal status) → the danger row "program rejected"; `discover()` failure → "model unavailable" within 2 s; `Esc` mid-stream cancels and closes; replay from `panels/*.openui` renders without the server. Evidence PNGs under `docs/gpuix-shell/evidence/{gallery,ask}/`. Acceptance: the gallery renders in three themes with the corner/hairline/ring checks ok; ask's validated-action and rejection paths ok; design-lint findings listed with owners.

### P-46 — Cheatsheet smoke + lint + calendar view + capacity/sysmon items + keyed status from scripts
- **stage**: `complete`  
- **depends_on**: P-30  
- **owner_paths**:
  - `pkgs/gpuix-shell/src/surfaces/cheatsheet/**`
  - `pkgs/gpuix-shell/src/core/cheatsheet/**`
  - `pkgs/gpuix-shell/src/items/{sysmon,capacity,calendar}/**`
  - `pkgs/gpuix-shell/src/core/registry/specs/cheatsheet.ts`
  - `pkgs/gpuix-shell/src/core/registry/specs/status.ts`
  - `pkgs/gpuix-shell/src/daemons/core/handlers/status.ts`
  - `tests/gpuix-shell/smoke_cheatsheet.py`
  - `docs/gpuix-shell/evidence/cheatsheet/**`
- **brief** (328 words):

Prove and complete SCOPE S-165, S-166, S-018, S-170, S-175, S-176 (P2 minimal). `smoke_cheatsheet.py` (harness; core started with the real headless Sway configured from the fixture `binds.conf` + P-20's generated block so `swaymsg -t get_config` returns them): `cheatsheet toggle` → the 700×580 overlay; `ui-tree` has the groups Launch/Workspaces/Windows/Layout/Media/Shell/Session with every `bindsym` of the fixture as a row showing the chord and the comment-derived label (count equals the parser's); `fill("notif")` filters to the Mod+o family; the in-surface shell keys (KEYS §4.2/§5) appear under their surface headings; `Esc` closes; `gpuix-shell cheatsheet lint` → exit 0 on the fixture + generated block, exit 1 with a named chord when a bind without a KEYS row is appended to a temp config; `launcher open --view cheatsheet` (`?`) shows the same rows. Keyed status: `gpuix-shell status set pomodoro "18:42" --ttl 2` → the rail `ui-tree` shows `rail.item.pomodoro` with the text, gone after 2.5 s; `status set recording on` → the recording dot; `status set touchpad off` → the touchpad mark; `status list --json`; two keys never clobber each other. Calendar: `launcher open --view calendar` → date, ISO week, the configured timezones (fixture config with `Europe/Paris`, `America/New_York`) with their clock times; the expanded rail shows the date line; no month grid node exists (assert). Capacity: with a sample meters file under a temp `~/.local/state/tally-rewrite/meters` (hand-made in the format `claude-capacity` prints — read the script to copy the shape) the `capacity` item shows per-seat percentages after `status set capacity refresh`; sysmon off by default, on with config → cpu/mem/disk figures present. Also implement `gpuix-shell validate` (S-017) end-to-end if P-05 left it partial: config + fragments schema, binds lint, fonts present (`fc-match`), `herdr`/`fd`/`wl-paste` on PATH; and `gpuix-shell doctor` checks 1–14 of ARCHITECTURE §16.2 as far as the harness can exercise (bus owner, units absent in the sandbox → warn, not fail). Evidence under `docs/gpuix-shell/evidence/cheatsheet/`. Acceptance: cheatsheet rows count, filter, lint exit codes, keyed status ttl and calendar must be ok; `validate` exit 0 on the integrated tree.

### P-47 — Binds, scripts and desktop entries verified: generated block vs KEYS, herdr-picker compat, osd/theme/gpuix-notify shims, x-scheme-handler
- **stage**: `complete`  
- **depends_on**: P-30  
- **owner_paths**:
  - `home/gpuix-shell-binds.nix`
  - `home/gpuix-shell-entries.nix`
  - `home/dot_local/bin/osd`
  - `home/dot_local/bin/theme`
  - `home/dot_local/bin/herdr-picker`
  - `home/dot_local/bin/gpuix-notify`
  - `home/dot_local/bin/pomodoro`
  - `home/dot_local/bin/recording-toggle`
  - `home/dot_local/bin/touchpad-toggle`
  - `home/dot_config/sway/startup.conf`
  - `tests/gpuix-shell/test_binds.py`
  - `tests/gpuix-shell/test_scripts.py`
  - `tests/gpuix-shell/smoke_scripts.py`
  - `docs/gpuix-shell/evidence/scripts/**`
- **brief** (350 words):

Close the loop between KEYS.md, the generated bind block, the registry and the scripts, on the integrated tree. 1. Extend `test_binds.py`: render the block (with and without `binds.proposed`), parse every `exec gpuix-shell …` line with the real `core/registry/grammar` (run `bun src/main.ts --parse-only <argv…>` — add that flag to the CLI through a request to P-48 if absent, or drive `parseArgv` from a `bun` one-liner you own under `tests/gpuix-shell/`), assert each resolves to a registered id; assert KEYS §3's twelve activated binds are present and the three proposed are absent by default; assert no line touches `$mod+k`, `$mod+Return`, `$mod+Shift+n`, the herdr chords or `Alt+h/j/k/l`; assert `--no-repeat` on every toggle. 2. `smoke_scripts.py` (harness; core + notifications daemon on a private bus): the real `osd` script (`osd volume 40` or its actual argv — read it) → the OSD card via the socket path, and again with the socket removed → the notify-send path still produces the OSD card (the daemon routes `app_name osd`); the real `theme noir` with a temp `~/.config/themes` tree → the symlink moves and the `theme reload` verb ran (core log); `herdr-picker --workspace rename` against the fake herdr → core's compat sniff accepted the length-framed `Ipc/dmenu` and the launcher's dmenu view mapped (skip if the script needs more of herdr than the fake provides; say exactly what); `gpuix-notify -a test -u critical hello` → a critical toast; with the socket absent → `notify-send` logger called with the same argv. 3. Scripts that set keyed status (S-018): edit `pomodoro`, `recording-toggle`, `touchpad-toggle` to call `gpuix-shell status set <key> <text> [--ttl]` / `status clear` when the socket exists (never failing when it does not), and test with the fake `gpuix-shell` logger; keep their current behaviour byte-for-byte otherwise. 4. `home/gpuix-shell-entries.nix`: add the `x-scheme-handler/gpuix-shell` desktop entry (`gpuix-shell deeplink %u`), never `vicinae`; the `gpuix-shell-files` and `gpuix-shell-gallery` entries; verify with `nix eval` of the client's `xdg.desktopEntries`. 5. Write the "morning diff" table for MORNING.md (request to P-48): which `binds.conf` lines the block overrides, which scripts changed, rollback = `programs.gpuixShell.enable = false`. Evidence under `docs/gpuix-shell/evidence/scripts/`. Acceptance: `test_binds.py` and `test_scripts.py` green; the osd-both-paths and gpuix-notify-fallback smoke steps ok.

### P-48 — Docs and diagnostics to truth: README/RUNBOOK updated with measurements, doctor/validate/status/listen/snapshot end-to-end, CLI usage text, MORNING.md body
- **stage**: `complete`  
- **depends_on**: P-30  
- **owner_paths**:
  - `docs/gpuix-shell/README.md`
  - `docs/gpuix-shell/RUNBOOK.md`
  - `docs/gpuix-shell/MORNING.md`
  - `pkgs/gpuix-shell/src/cli/**`
  - `pkgs/gpuix-shell/src/core/registry/**`
  - `!pkgs/gpuix-shell/src/core/registry/specs/*.ts`
  - `pkgs/gpuix-shell/src/core/registry/specs/core.ts`
  - `pkgs/gpuix-shell/src/core/registry/specs/index.ts`
  - `pkgs/gpuix-shell/src/core/socket/**`
  - `pkgs/gpuix-shell/src/core/config/**`
  - `pkgs/gpuix-shell/src/core/logging/**`
  - `pkgs/gpuix-shell/src/core/state/**`
  - `pkgs/gpuix-shell/src/platform/socket/**`
  - `pkgs/gpuix-shell/src/platform/fs/**`
  - `pkgs/gpuix-shell/src/platform/exec/**`
  - `pkgs/gpuix-shell/src/platform/state/**`
  - `pkgs/gpuix-shell/src/daemons/core/handlers/core.ts`
  - `tests/gpuix-shell/test_cli.py`
  - `docs/gpuix-shell/evidence/cli/**`
- **brief** (337 words):

Two jobs: make the diagnostics verbs real and make the documents true. Diagnostics (you own the CLI and the core domain): finish `gpuix-shell doctor [--json]` (ARCHITECTURE §16.2 checks 1–15 with ok/warn/fail and a `fix` string each; the addon check as a child; exit 0/1), `validate [config]` (config + fragments schema with the zod path, binds lint via `cheatsheet.lint`, fonts via `fc-match "Anthropic Sans"`, PATH tools `herdr fd wl-paste wl-copy gio notify-send`), `status --json` (units via `systemctl --user is-active` when available else "no systemd", sockets, theme name, output map, RSS per known pid), `snapshot --json [--surface]`, `listen [--json] [--filter]` (streams `event`/`state` lines, back-pressure safe, EOF on daemon exit), `registry ls --json`, `wait <surface-open|surface-closed|notification>` (S-wait verb from KEYS §7.4, used by smokes), `version`, generated `--help` for every verb from the specs (sentence case, one line per flag), `--parse-only` (prints the resolved id/args for P-47's bind test), the `--hud` echo path. `tests/gpuix-shell/test_cli.py` (hermetic: a tiny Python NDJSON server standing in for core): exit codes 0/1/2/3/69 for ok/failed/usage/not-running/unavailable, `--json` on every READ verb, `listen` EOF, `dmenu` stdin cap, the `toggle <surface>` and Vicinae aliases, `ping` ≤ 100 ms wall time (measure 20 runs, report p50/p90). Documents: replace every `TODO(P-48)` in README/RUNBOOK with measured facts from BUILD-LOG and INTEGRATION.md (store path, closure size, spawn→ready ms, RSS per surface, CLI ping ms, which smokes passed); add the "morning diff" table from P-47's request and the hand checks from P-42; write the MORNING.md body: status in three lines, the built/not-built table keyed by SCOPE P0 ids (69 rows: ok / partial / not built, each with the evidence path), the deploy procedure (Zenbook only; `deploy /home/tom/.wt/dotfiles/gpuix-shell#client` from the strix; rollback), the rulings Tom must make (from ASSUMPTIONS: corners, toast anchor, `$mod+m`, music rekey, controls keyboard mode, `on-demand`), the unverified list (ARCHITECTURE §23 updated with what wave 3 measured), and the one-minute checks per surface. No claim without an evidence path. Acceptance: `test_cli.py` green; `gpuix-shell doctor` runs in the harness and prints every check; README/RUNBOOK/MORNING have no `TODO(` left (P-52 adds the final commit list).

### P-49 — Performance and budgets: CLI cold start, spawn→ready, RSS per process, warm spare measurement, frame-loop sanity
- **stage**: `complete`  
- **depends_on**: P-30  
- **owner_paths**:
  - `docs/gpuix-shell/PERF.md`
  - `tests/gpuix-shell/perf_budgets.py`
  - `docs/gpuix-shell/evidence/perf/**`
- **brief** (316 words):

Measure, do not build. Under the harness with core + notifications + rail + fake herdr running from the dev tree (and again from the Nix result if P-41 has one by the time you run — check `ls result/bin/gpuix-shell`), record in `docs/gpuix-shell/PERF.md` with the exact commands: (1) `gpuix-shell ping` wall time, 20 runs, p50/p90, dev tree vs `dist/main.js` vs Nix wrapper; confirm `dist/main.js` has no top-level `@gpuix` import (`grep -c`); (2) spawn→`surface/ready` for launcher, switcher, controls, power, center from the core log `spawn_ms`, 10 shows each, p50/p90; first-paint `paint_ms` where logged; (3) RSS (`VmRSS`) of core, notifications, rail, one launcher, the toasts child, the osd child, music serve if present — after 60 s idle and after 2 minutes of a notify-send loop at 5/s; compare to the SCOPE S-014 budget 250 MiB per surface and ARCHITECTURE §3.1 targets (core ≤ 100 MiB); (4) the frame loop: with the rail idle for 60 s, count JS wakeups (`strace -c -e trace=epoll_wait`-free: use `/proc/<pid>/sched` `nr_switches` deltas or `perf`-free `top -b -n 2` CPU %), expecting ≈ 4 Hz for daemons (frameMs 250) and no busy loop; (5) herdr snapshot read time `herdr_ms` and Sway batch `sway_batch_ms` from the log; (6) the warm spare: turn on `config.supervisor.warmSpare` if implemented and remeasure (2); if not implemented, say so; (7) clipboard ingest cost per copy (`wl-copy` 100 times, time per ingest process from the log); (8) a GPU-loss rehearsal is out of scope (say so). Write `tests/gpuix-shell/perf_budgets.py` that re-runs (1)–(3) and compares to thresholds (ping ≤ 100 ms p90, spawn ≤ 600 ms p90, RSS ≤ 250 MiB per surface) printing a table and exit 1 on breach; wire nothing into Nix. Add one `ASSUMPTIONS` line per budget you set that no document fixed. Evidence (raw timings, `ps` dumps) under `docs/gpuix-shell/evidence/perf/`. Acceptance: PERF.md has every row filled with a number or "not measured: reason"; `perf_budgets.py` runs under the wrapper.

### P-50 — Security and secrets review: socket, argv, logs, automation tree, fence, permissions; SECURITY.md
- **stage**: `complete`  
- **depends_on**: P-30  
- **owner_paths**:
  - `docs/gpuix-shell/SECURITY.md`
  - `tests/gpuix-shell/test_security.py`
  - `pkgs/gpuix-shell/src/security.test.ts`
  - `docs/gpuix-shell/evidence/security/**`
- **brief** (334 words):

One light pass (standing rule: single reviewer, no refute panels) over the integrated tree against BOUNDARY §2.2/§5 and ARCHITECTURE §4.1 security, G-6, §16.1 redaction. Write `src/security.test.ts` (bun, pure/static): (a) the registry contains no SECRET spec with a `cli.path`; no id named `unlock`; every ACTION spec has `confirm` set and `replaySafe:false` for logout/reboot/poweroff/suspend/hibernate; (b) grep `src/` for `nmcli … password`, `--password`, `psk=` on argv builders, `token` in log calls, `Subsonic` URLs in `console.`/`log(` calls → none; (c) `redact()` masks `password`, `psk`, `passkey`, `token`, `salt`, `u=`/`t=`/`s=` query params and clipboard/notification bodies at info level (table of 12 cases); (d) every `writeAtomic` call passes mode `0o600` and every runtime dir creation `0o700`; (e) the fence test still passes and `src/cli` and `src/daemons/core` import no `@gpuix/*`; (f) `platform/exec/runner` never uses `sh -c` for registry commands and strips `GPUIX_SHELL_SPAWN`, `GPUIX_SHELL_EXECUTABLE` and socket vars from children; (g) `validateAsk` refuses ACTION/SECRET ids and the forbidden OpenUI actions; (h) the Chrome native host accepts only the `kcmipingpfbohfjckomimmahknoddnke` origin argv and caps frames at 1 MiB. `tests/gpuix-shell/test_security.py` (hermetic + under the wrapper where a socket is needed): `$XDG_RUNTIME_DIR/gpuix-shell` is 0700 and every `*.sock` 0600 after core starts; a second uid cannot connect (skip if no second uid; say so); a `Notify` with a 9 KiB body is clamped to 8 KiB; a 20 KiB request line is rejected with `-32600` and the connection survives; the automation tree of the music view and the clipboard view contains no `token`/`salt` (reuse P-43/P-35 evidence `ui-tree` dumps if present, else run them); a `SECRET`-class method over the socket returns `-32001 refused`. Then `docs/gpuix-shell/SECURITY.md`: the trust boundaries (socket = same-uid local door; D-Bus roles; what the model can and cannot reach), the secret paths (wifi PSK, BT passkey, Navidrome credentials, model endpoint) and where each is read/handled/never written, the redaction rules, the exit-69 and never-both guarantees, findings with severity and owner packet (each also a BUILD-LOG request), and what was not reviewed. Acceptance: both test files green or each failure named with its owner; SECURITY.md lists every finding.

### P-51 — Completeness critic: SCOPE P0/P1 coverage audit → GAPS.md with ranked gap-fill packets
- **stage**: `complete`  
- **depends_on**: P-30  
- **owner_paths**:
  - `docs/gpuix-shell/GAPS.md`
  - `docs/gpuix-shell/GAPS.json`
- **brief** (318 words):

Read-only audit (you edit nothing but the two files you own). For every SCOPE row S-001…S-202 decide, from the tree as integrated by P-30 plus the BUILD-LOG blocks written so far (re-read BUILD-LOG at the end of your pass, since the complete packets append while you work), one of `built` (code + a test or smoke step that exercises it; cite the file and the test name), `partial` (code without a test, or a test without the behaviour; say which half), `stub` (a P-00 stub still in place), `missing` (nothing), `out` (ruled out by SCOPE §21). Method: grep for the registry ids, testIds, verbs and file names each row implies; open the file; do not trust a BUILD-LOG claim without a file. Also audit the cross-cutting rules: every surface answers `ui-tree`; every surface root sets family/colour; every ACTION verb gated; every KEYS §7 verb resolves (`registry ls --json` if the CLI runs, else the specs files); the nine seam files still import every entry; `providers/index.ts` has all 18 providers non-stub; `items/index.ts` all 16; the three fragments validate; the HM module imports both P-20 files. Output `docs/gpuix-shell/GAPS.md`: a table per SCOPE section with the status and evidence per row, P0 totals (built/partial/stub/missing out of 69), P1 totals out of 65, then the ranked gap list: each gap as a ready-to-run packet brief (id `G-nn`, title, owner_paths copied from §5 so they stay disjoint, depends_on `["P-52"]`, 100–250 words naming the exact files, functions and the acceptance test) ordered P0 stubs → P0 partials → P1 missing by Tom-impact (morning hand checks first), capped at 14. Also `GAPS.json` with the same packets as an array of `{id, title, owner_paths, depends_on, stage:"gapfill", brief}` for the runner. Mark every row you could not verify as `unverified` rather than guessing. Acceptance: every S-row has a status line with a file path or the word `missing`; the P0 counts add up to 69; GAPS.json parses.

## 6.5 Stage deliver (runs alone, last)

### P-52 — Final integrate + deliver: green tree, MORNING.md final, logical commits, push, draft PR
- **stage**: `deliver`  
- **depends_on**: P-31, P-32, P-33, P-34, P-35, P-36, P-37, P-38, P-39, P-40, P-41, P-42, P-43, P-44, P-45, P-46, P-47, P-48, P-49, P-50, P-51  
- **owner_paths**:
  - `**`
- **brief** (380 words):

Runs alone, last. 1. Re-read every BUILD-LOG block of wave 3 and INTEGRATION.md; apply the seam requests that remain (`providers/index.ts` additions such as P-44's `extensions`, `items/index.ts`, handler/spec index entries, the `--parse-only` flag if P-48 did not add it); keep every change minimal and list it in INTEGRATION.md under "P-52". 2. `$BUN x tsc --noEmit -p pkgs/gpuix-shell` clean; `$BUN test` green (quarantine only with a `GAPS` line); `$BUN build.ts` with zero top-level `@gpuix` imports; `python3 -m unittest discover -s tests/gpuix-shell -p 'test_*.py'` green; `nix build .#gpuix-shell -L` and `nix flake check --offline --no-build` green if P-41 got there (else record the last error verbatim). 3. Under the wrapper, run `smoke_hello.py`, `smoke_rail.py`, `smoke_launcher.py`, `smoke_notifications.py`, `smoke_switcher.py`, `smoke_clipboard.py` once each and paste their `results.json` summaries into MORNING.md; do not fix surfaces now, only record. 4. MORNING.md final: status, the built/partial/not-built table (from GAPS.md, reconciled with step 3), the deploy and rollback procedure, the rulings list, the unverified list, the gap-fill packets P-51 ranked (with the command to run them), and the commit list. 5. Commits: `git reset --soft dadb1426` is **not** used if checkpoint commits exist — instead squash the `wip: checkpoint` commits into logical commits in this order with `git reset --soft` to the branch point then staged groups: (a) `docs(gpuix-shell): wave-1 notes and syntheses`, (b) `gpuix-shell: scaffold, core, platform adapters`, (c) `gpuix-shell: surfaces (rail, launcher, notifications, osd, switcher, controls, power, files, cheatsheet, ask, gallery)`, (d) `gpuix-shell: music lane`, (e) `gpuix-shell: nix package, HM module, binds, scripts`, (f) `gpuix-shell: tests, evidence, docs`. Never commit `node_modules`, `dist`, `result`, `bun.lock`, fonts, credentials or anything under `/run/agenix`; check with `git status --porcelain | grep -v '^??'` and `git diff --cached --stat`; `git check-ignore` the evidence PNGs (keep PNGs under 2 MB total, delete the rest and say so). Commit messages end with the attribution line from the session's system reminder. 6. `git push -u origin experimental/gpuix-shell`; `gh pr create --draft --base main --title "gpuix-shell: Sway desktop shell on GPUIX (overnight build)" --body-file docs/gpuix-shell/MORNING.md` (body ends with the PR attribution line); paste the PR URL into MORNING.md and NIGHT-LOG.md. 7. Append the closing NIGHT-LOG line with the time, the PR URL, and the three most important things Tom must know. Acceptance: the PR exists as a draft; `git status` clean except ignored paths; MORNING.md names the PR.

## 7. Left unverified by this plan

- No packet brief was executed; file names under `src/` follow ARCHITECTURE §2.2 and may need renaming when the scaffold runs (P-00 decides and logs).
- Whether `splitting: true` keeps `@gpuix/native` out of the CLI chunk is P-30's measurement.
- The `on-demand` keyboard mode for controls, the output-pin dance, `ssh -L` unix-socket forwarding, FTS5 in bun's SQLite, static-instance fonts via fontTools, and live `GpuixTheme` re-application are ARCHITECTURE §23 items assigned to P-37, P-36, P-31, P-35, P-33/P-41 and P-33 respectively.
- Packet sizing is an estimate; a builder that cannot finish ships the P0 half, logs the rest, and P-51 turns it into a gap-fill packet.
- The structured packet list returned to the runner is this file's §6 verbatim (`PLAN.json`).
