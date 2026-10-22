# 13 — Prior GPUIX desktop shell (Hyprland + Solid, 0.10.0): what to reuse for the Sway + React port

Reader note for the overnight gpuix-shell build, 2026-10-20/21. Written read-only from
`/home/tom/.wt/hyprland-solid-shell` (branch `feat/hyprland-solid-shell`, HEAD 2ac87891, the
shell itself is **uncommitted** — `git log -- pkgs/desktop-shell` is empty, `git status` shows
every file as `A`/`??`). Labels: **MEASURED** = I read or counted it in the file; **REPORTED** =
a README/transcript claims it, I did not re-run it; **INFERRED** = my reading of what it means
for the port. Line numbers are from `cat -n` of the files as they are tonight.

Every path below is relative to `/home/tom/.wt/hyprland-solid-shell/` unless absolute.

---

## 1. What this source is

**MEASURED.** `pkgs/desktop-shell/` is a 2026-10-13/14 Codex build (file mtimes 2026-10-14
00:02–00:26) of a native desktop shell for **Hyprland**, written in TypeScript with **Solid 1.9.15**
on the published **`@gpuix/native` 0.10.0** + `@gpuix/solid` 0.10.0 Linux addon, bundled with Bun,
packaged with `buildNpmPackage`. It was never activated on the Zenbook (flake.nix asserts
`!(clientHome.systemd.user.services ? desktop-shell)` and `myDisplay.session == "sway"`,
`flake.nix` diff hunk at `@@ -1225`). Tom stopped the Hyprland direction after ~74 minutes
(see §2); the code stayed as the precedent the BRIEF names.

Source files and sizes (MEASURED, `wc -l`):

| File | Lines | Role |
|---|---|---|
| `pkgs/desktop-shell/ui.tsx` | 1338 | every surface: bar, launcher, controls, windows, notifications, toasts; layer-shell options; key handling |
| `pkgs/desktop-shell/controller.ts` | 238 | Hyprland state controller: event socket, snapshot via `hyprctl -j`, coalescing, reconnect, dispatch |
| `pkgs/desktop-shell/providers.ts` | 277 | launcher providers: command catalog, calculator, clipboard (cliphist), bounded file search, themes, activation |
| `pkgs/desktop-shell/applications.ts` | 102 | XDG `.desktop` index + `searchScore` |
| `pkgs/desktop-shell/notifications.ts` | 83 | `NotificationStore` (pure, tested) + command parser |
| `pkgs/desktop-shell/notifications-daemon.ts` | 79 | `org.freedesktop.Notifications` D-Bus server over `dbus-next`, JSON-lines Unix socket, toast child supervisor |
| `pkgs/desktop-shell/notifications-client.ts` | 43 | socket client: `followNotifications` (subscribe) and `notificationCommand` |
| `pkgs/desktop-shell/singleton.ts` | 73 | per-mode Unix-socket singleton with "present"/"close" toggle protocol |
| `pkgs/desktop-shell/theme.ts` | 149 | `Theme` roles, `parsePalette` (JSON fragment), `parseTheme` (kitty.conf fallback), `followTheme` (watch + SIGUSR1) |
| `pkgs/desktop-shell/main.ts` | 59 | CLI: `bar|launcher|controls|windows|notifications|toasts|daemon`, `notifications-clear/dismiss/dnd`, `--check-native`, `--provider` |
| `pkgs/desktop-shell/build.ts` | 28 | `Bun.build` with the Solid plugin; externalises only `@gpuix/native` and `dbus-next` |
| `pkgs/desktop-shell/default.nix` | 47 | Nix precedent: `buildNpmPackage`, `npmDepsHash`, autoPatchelf, wrapper with PATH + LD_LIBRARY_PATH |
| `pkgs/desktop-shell/README.md` | 67 | the build's own description and claims |
| `pkgs/desktop-shell/package.json` / `tsconfig.json` | 21 / 14 | deps `@gpuix/native 0.10.0`, `@gpuix/solid 0.10.0`, `dbus-next ^0.10.2` (installed 0.10.2), `solid-js 1.9.15`; dev `@types/bun 1.3.10`, `typescript 5.9.3` |
| `pkgs/desktop-shell/*.test.ts` | 175+131+45+30+37 | bun tests (see §5.9) |
| `pkgs/desktop-shell/patches/` | 66 + 277 | **unfinished** GPUI `ext-background-effect-v1` blur research; not applied; irrelevant on Sway |
| `pkgs/desktop-shell/dist/main.js` | 25832 | stale bundle, ignore |
| `pkgs/desktop-shell/node_modules/@gpuix/{native,native-linux-x64-gnu,solid}` | — | the only installed 0.10.0 binary on this machine (BRIEF row) |

Sibling material in the same worktree that is directly reusable for Sway (MEASURED):

| Path | Lines | Why it matters |
|---|---|---|
| `design/gpuix-comparison/platform.ts` | 54 | **framework-neutral Sway IPC capability adapter** (`swaymsg -r -t get_outputs/get_workspaces`, revalidate-then-focus) — the only Sway-side GPUIX code in the tree |
| `design/gpuix-comparison/platform.test.ts` | 27 | 13 `test()` calls incl. loops → README says 26 cases; mocks `swaymsg` by argv |
| `design/gpuix-comparison/desktop.tsx` | 67 | Solid desktop study (ordinary toplevel, not layer-shell) that *uses* the Sway adapter; inline-SVG icon set; palette→token mapping |
| `design/gpuix-comparison/main.ts`, `build.ts`, `smoke-native.py` | 10 / 2 / 56 | the minimal GPUIX mount, the Bun build, and a **headless-Sway + grim** compositor smoke that ran under `runtime-test --render-node` |
| `home/dot_local/bin/sway-workspace-switcher` | 267 (untracked) | Mod+i top-display switcher: `make_rows` (slot/status model), `Toggle` (SWAYSOCK-keyed socket+flock singleton), `fuzzel_command` (palette→argv), `activate` (stale-selection guards) |
| `tests/workspace-switcher/{test_switcher.py,smoke.py,README.md}` | 103 / 77 / 54 | 16 fixture tests + two-output headless Sway smoke with wtype/grim |
| `home/dot_local/bin/desktop-control` | 95 | Python adapter: `focused-output`, `focused-geometry`, `power-on/off`, `backend` for both compositors — the Sway branches are the keepers |
| `home/dot_local/bin/desktop-notifications` | 17 | makoctl ⇄ desktop-shell switch (shape only) |
| `home/dot_local/bin/desktop-workspace` | 8 | thin exec to `herdr-picker --workspace <new|close|detach|rename|restore>` |
| `home/dot_local/bin/herdr-picker` (diff vs main: +207/−) | — | the Sway tree/mark/slot model the shell must read (`walk`, `views`, `slot_of`, `projectors`, `available_slot`, `quote_sway`, `remote_snapshot`, `identity`, `assigned_identity`) |
| `home/dot_local/bin/runtime-test` (diff) | +31 | adds `--render-node /dev/dri/renderD<N>` (validates char device, major 0xe2, minor ≥128; unsets `HYPRLAND_*`) |
| `tests/runtime-test/test_render_node.py` | 50 | proves default isolation has no `/dev/dri`, rejects card/input nodes |
| `tests/hyprland/SWAY-COMPARISON.md` | 27 | the "what we give up by staying on Sway" list Tom asked for on 10-13 |
| `home/themes/default.nix` (diff) | +14 | **`"desktop-shell.json" = builtins.toJSON t;`** fragment already rendered per theme (line ~294) — this exact mechanism is what BRIEF §3.5 asks for under the name `gpuix-shell.json` |
| `home/dot_local/bin/theme` (diff) | +13 | `reload_hyprland` sends `SIGUSR1` to `desktop-shell.service` via `systemctl --user kill --kill-whom=main` |
| `home/hyprland.nix` | 103 | HM precedent: `desktop-shell-core` (`Type=dbus`, `BusName=org.freedesktop.Notifications`), two `wl-paste --watch cliphist store` units, `desktop-shell` bar unit, all `PartOf`/`WantedBy` the session target |
| `home/dot_config/hypr/binds.conf` | 125 | which chords were pointed at the shell (`$mod d/space` launcher, `$mod v` clipboard provider, `$mod Shift v` notifications, `$mod grave` windows, `$mod comma` controls) |
| `home/vicinae.nix` (diff) | +36/−? | how Vicinae/mako were conditionally disabled (`ConditionEnvironment = "!HYPRLAND_INSTANCE_SIGNATURE"`); desktop entries re-pointed to `desktop-workspace` / `desktop-notifications` |

What it is **not** (MEASURED from README.md:21-24 and code): no left rail (the bar is a 32 px top
bar), no OSD, no Wi-Fi/Bluetooth UI (opens `nmtui` in kitty / `blueman-manager`), no power menu,
no icons (text only), no lock, no clipboard watcher of its own (cliphist units), no file explorer
(a bounded filename search of `~/Downloads` and `~/Documents`), no React.

---

## 2. Verbatim Tom rulings relevant to the desktop shell (with timestamps)

All from the Codex pivot session `~/.codex/sessions/2026/10/13/rollout-2026-10-13T22-57-08-01a1370e-….jsonl`
and its 10-14 forks, extracted with the scratchpad's `codex2-text.py --user-only`. Timestamps are
UTC as logged (CEST = +2 h). Tom's spelling is kept.

- **2026-10-13T21:11:34Z** — "hyprland is just sway with animations and best in class blur. for terminal: herdr + kitty ; until superlogical releases their terminal. for browser, google chrome."
- **2026-10-13T21:52:29Z** — "work deploy massive amounts of compute for htis come on ! impress me! all the functionality. become a hyprland expert. and a dotfiles expert."
- **2026-10-13T22:03:41Z** — "first step is finailzing the look and aesthetic. i want to use the claude anthropic font, the color scheme and selector, and the github primer react theme kit"
- **2026-10-13T22:16:03Z** — "whatever you just opened: i love it. this is good enough to also become a functional remplacement to waybar, vicinae and mako notifications. drawing insporation from omarchy's implemetnatipn of wayshell in fact." *(INFERRED: "what you just opened" was the Claude/Primer browser study in `design/claude-primer`, not this GPUIX shell; BRIEF §1 already treats this as the look baseline.)*
- **2026-10-13T22:16:59Z** — "we re doing functionality pull from quickshell NOT visuals or aesthetics whatsoever"
- **2026-10-13T22:25:30Z** — "i digress on the hyprland parts, i m sorry. let s tick to sway window manager. less effort.. but do list all the hyprland functionality that we're "missing out on" in a way so i can decide if i want hat added potentially later or not..." *(→ `tests/hyprland/SWAY-COMPARISON.md` is that list.)*
- **2026-10-13T22:33:25Z** — "one sway-wired workspace switcher that can be toggled with mod i ; with herdr-provided status indicators. only for the top display (consult kanshi config to know which one i m talking about, and existing vicinae herdr wrkspaces item as well if needed."
- **2026-10-13T22:34:24Z** — "for ht left bar, i want you to copy the same proportions as the views c++ left tab bar that we saw from google chrome."
- **2026-10-13T23:21:38Z** — "i m not intersted in "native advantage" . performance is not really the thing i m looking for here. "supplies another renderer" is fine for something that' react plus generic compositor functionlaity... vicinae (raycast clone) proves this theoretically ; we hae the sway ipc and omarchy's quickshell which you investigated a while back did exactly that."
- **2026-10-13T23:45:17Z** — "one quick note on gpuix that is unfortunate is that it's not registering ctrl +\- for zooming ; was that explicitly disabled or what?"
- **2026-10-13T23:46:43Z** — "one more introspection in ~/notes on the ctrl k contextual menu idea i would have had perhaps going up to years ago... this is something that is interesting now that it may all be gpuix-controlled ; potentially giving control of my desktop to the ai"
- **2026-10-14T01:08:44Z** — "we can design a linear-style unified shortcut based ui, with mneumonics, in a way that the claude ai can drive at equivalence, sending in instructins that get passed on to a hci implementor ... the same way the user can do ctrl k and see a contextual menu of sorts.."
- **2026-10-14T02:39:47Z** — "generally how we can "interleave" between several window types on sway without the user feeling the differnce and without that taking sway tabbed space. i dnt want to "see" the tabs however.. would be itnersting. would need some sort of "contextality" here"
- **2026-10-14T02:40:22Z** — "a herdr workspace is ONE kitty terimnal correpondance. this is something i m hapy to enfordce"
- **2026-10-14T02:40:31Z** — "in fact i m trying to do one hedr workspace is one sway wm workspace to reduce cognitive load even further"
- **2026-10-14T02:41:02Z** — "and having a deep sense of integation between them. and that way herdr "watiing for input" becomes sway workspace wayland urgency . and we can integarte notify-send just as easily aswell"
- **2026-10-14T13:10:30Z** — "increase brightness on my asus zenbook to the max. this should become a shortcut like f1 f2 perpahs ; and a vicinae-remplacement-launcher"

Rulings quoted inside the code/config of this worktree (REPORTED by whoever wrote the comment, date as written):

- `home/vicinae.nix:21` — Tom, 2026-10-12: "make the font larger than 11 (12 or 14, need to decide, start at 12)" (Vicinae `font.normal.size = 12`, family "Anthropic Sans").
- `home/vicinae.nix:57` — Tom, 2026-10-11: "top and center not top right" (mako `anchor = "top-center"`). **Note the conflict with BRIEF §3.3 ("toasts = overlay top-right 390 wide max 4") — see §6.**
- `home/themes/default.nix` mako fragment comment — Tom, 2026-10-12: "the blue color is not the same as the vicinae launcher. i prefer the latter's" (mako progress bar uses `selection.bg`).
- `home/themes/default.nix` kitty fragment comment — Tom 2026-07-15: a kitty split reads as "a quiet divider" (divider = `border.inactive`).
- `tests/hyprland/SWAY-COMPARISON.md:3` — "Decision, 2026-10-14: Tom keeps Sway. Hyprland work stops; native Solid/GPUIX shell work remains useful on Sway."

---

## 3. Feature / behaviour inventory

Legend for "keep/replace/new": **keep** = port the logic nearly verbatim (Solid→React is mechanical); **adapt** = keep the shape, swap the compositor/transport; **replace** = BRIEF decided differently; **drop** = Hyprland-only; **new** = BRIEF needs it and nothing exists here.

| Feature | What exactly (MEASURED unless noted) | Where it lives today | keep/replace/new | Notes for the builder |
|---|---|---|---|---|
| CLI mode dispatch | `desktop-shell [bar\|launcher\|controls\|windows\|notifications\|toasts\|daemon]`, `--help`, `--version`, `--check-native` (loads addon, asserts `GpuixRenderer` is a function), `notifications-clear`, `notifications-dismiss`, `notifications-dnd on\|off`, `launcher --provider <all\|windows\|applications\|commands\|clipboard\|files>` | `main.ts:2-35, 51-53` | adapt | BRIEF §3.2 wants `gpuix-shell rail\|notifications\|launcher\|switcher\|controls\|files\|power` + one control socket `$XDG_RUNTIME_DIR/gpuix-shell/shell.sock`. The dynamic-`import()` per mode (`main.ts:24,37,50`) keeps startup cheap; keep that. |
| Singleton + toggle | One Unix socket per (instance, mode) at `$XDG_RUNTIME_DIR/desktop-shell/<sig[-32:]>-<mode>.sock`, mode 0700/0600. Second launch connects and sends `"present"` (bar, toasts) or `"close"` (popups) then exits 0; stale-socket unlink only if mtime > 2 s old; `EADDRINUSE` race handled with one 100 ms retry | `singleton.ts:4-73` | adapt | Replace `HYPRLAND_INSTANCE_SIGNATURE` (`singleton.ts:9-10`) with a token from `SWAYSOCK` — `sway-workspace-switcher:149` already does `sha256(SWAYSOCK)[:16]` and adds an `flock` (`:151,155-158`) which is more robust than mtime heuristics. BRIEF's single `shell.sock` CLI subsumes this; keep the "repeat the chord closes the popup" semantics (README.md:8-9). |
| Compositor state model | `DesktopState {connected,error,clients[],workspaces[],monitors[],activeAddress}`; `emptyState()` | `controller.ts:5-43` | adapt | Hyprland-shaped (`address`, `class`, `grouped`, `fullscreen:number`, `monitor`). Sway shape: `con_id`, `app_id`/`window`, `marks[]`, `urgent`, `output`, `num`. See §5.3 mapping. |
| Event-driven refresh with coalescing | Line-buffered event socket (1 MiB cap → destroy), regex on event names (`controller.ts:155`), 40 ms debounce (`:178-181`), single-flight `refresh()` with `dirty` re-run (`:182-215`), `epoch` guard so an in-flight snapshot cannot mark a closed connection healthy (`:197,204`), 2 s retry on snapshot failure (`:207`), reconnect backoff 250 ms ×2 → 10 s (`:174-175`) | `controller.ts:95-215` | keep (transport swap) | The whole class survives with `attach()` reading `swaymsg -t subscribe -m` (or raw i3-ipc) and `refresh()` running `swaymsg -r -t get_tree/get_workspaces/get_outputs`. Tests for it exist (§5.9). |
| Snapshot validation | `parseSnapshot(parts)` type-checks arrays and each client's `address/title/class/workspace.id` | `controller.ts:65-94` | adapt | Replace with the `object/array/string/bool/integer` validators from `design/gpuix-comparison/platform.ts:20-26`, which are already Sway-shaped. |
| Window actions | `focus(address)` → `hyprctl dispatch focuswindow address:0x…`; `workspace(id)`; `move(address,id)` → `movetoworkspacesilent`; `dispatch()` requires reply `ok` and refreshes | `controller.ts:216-237` | adapt | Sway: `[con_id=N] focus`, `workspace number N` / `workspace --no-auto-back-and-forth "name"`, `[con_id=N] move container to workspace number N`; success = `[{"success":true}]` JSON. Keep the "validate the identifier before building the command" discipline (`:224,229,234`). |
| Subprocess helper | `run(cmd,args)` execFile, 5 s timeout, 4 MiB buffer, stderr→Error | `controller.ts:44-56` | keep | Also `runBytes` (binary stdin/stdout, 16 MiB) `providers.ts:78-84` and `launchProviderCommand` (detached, unref, resolve on `spawn`) `providers.ts:89-95`. |
| XDG application index | Scans `$XDG_DATA_HOME/applications` + each `$XDG_DATA_DIRS/applications`, recursive with `sub-dir-` id prefix, first id wins, parses only `[Desktop Entry]`, honours `Hidden`, `NoDisplay`, `Type=Application`, `Exec`/`DBusActivatable`, `OnlyShowIn`/`NotShowIn` against `XDG_CURRENT_DESKTOP` (default `"Hyprland"`), unescapes `\s`/`\n`; sorted by name | `applications.ts:11-92` | keep | Change the default at `applications.ts:62` to `"sway"`. No icon field is read (`Icon=` ignored) — add if the rail/launcher wants icons. No `Actions` parsing. |
| Launch an app | `gio launch <path-to-.desktop>` (never parses `Exec` as shell) | `ui.tsx:241`; README.md:14-15 | keep | `glib` must be on the wrapper PATH (`default.nix:37`). |
| Search ranking | `searchScore(query, ...values)`: all whitespace-split terms must be substrings of the joined lowercase text, else −1; +10 per term if `values[0]` starts with it, else +1 | `applications.ts:93-102` | keep (or improve) | Deterministic and tested (`controller.test.ts:162-167`). No fuzzy matching, no usage frecency. |
| Launcher result model | `hits` memo merges: windows (score on title/class/workspace), applications (name/comment/keywords), 5 hard-coded commands (Desktop controls, Browse windows, New terminal → `herdr-projector`, Open Chrome, Notifications), `providerItems` (catalog + themes + calculator pinned at 10000), `extraItems` (clipboard/files); filter by provider tab; sort desc; `slice(0,60)`; visible window of 8 rows around `selected` | `ui.tsx:225-305` | keep | Pure enough to lift into a `launcher/model.ts` + test. |
| Launcher provider tabs | All / Windows / Applications / Commands / Clipboard / Files; clipboard & files are explicit (never searched from "All"), 120 ms debounce, files needs ≥ 2 chars | `ui.tsx:89-123, 645-667` | keep | Privacy stance is in the header comment `providers.ts:1-4`. |
| Command catalog | 20 fixed `argv` entries (`files`→nautilus, `network`→kitty nmtui, `audio`→audio-route, `accent`→theme-prompt, `herdr`→herdr-picker, `workspaceNew/Restore/Rename`→desktop-workspace, screenshot ×3, `color`, `ocr`, `record`, `monitors`, media ×3, `volumeMute`, `microphoneMute`) with title/subtitle/keywords | `providers.ts:11-67` | keep | Maps 1:1 onto the scripts BRIEF lists as "to wrap". Interactive ones are launched detached (`providers.ts:96-99`); `theme` gets a 30 s timeout (`:101-104`). |
| Calculator | Bounded recursive-descent arithmetic (`+ − × ÷ % ^`, parens, unary, sci-notation; 256-char cap; `toPrecision(14)`), result row copies via `wl-copy -- <number>` after a numeric regex | `providers.ts:176-225, 257-262` | keep | 10 positive + 12 negative tests (`providers.test.ts:9-19`). |
| Clipboard history provider | `cliphist list` rows `id\tpreview`, id regex `^[1-9]\d{0,19}$`, control chars stripped, 500-char preview, dedupe, limit ≤ 200; activation `cliphist decode` (id on stdin) → `wl-copy` (bytes on stdin), never argv | `providers.ts:108-129, 263-270` | replace | BRIEF §3.4 says own store via `wl-paste --watch`. The parse/activate hygiene is worth copying into the new store's UI. Known gaps listed at `providers.ts:70-76`. |
| File provider | BFS over `~/Downloads`, `~/Documents` depth ≤ 3, ≤ 2000 entries, skips dotfiles and symlinks, names only, mtime-desc, `gio open` | `providers.ts:133-163, 271-274` | replace | BRIEF wants a Pinax-like explorer (`gpuix-shell files`). This is a search, not a browser. |
| Theme list / apply | `theme list` filtered by `^[a-z][a-z0-9-]{0,63}$` minus helper verbs; `theme <name>` | `providers.ts:165-173, 253-256` | keep | |
| Theme loading | `Theme` with 16 roles; `fallback` = noir; `parsePalette(json)` requires `ground`, `border`, `selection`, `name ∈ {claude-light, claude-dark, noir}`; light uses `ground.base` for background, dark uses `ground.desktop`; `hover` = `border+"55"` on noir else `ground.dim`; `primary` = `#A74B2F` on light; fallback `parseTheme(kitty.conf)`; `followTheme` watches `$XDG_CONFIG_HOME` for the `theme` entry (50 ms debounce), reloads on `SIGUSR1`, revision guard | `theme.ts:7-149` | keep (rename file) | Reads `~/.config/theme/desktop-shell.json` (`theme.ts:122`); BRIEF §3.5 names it `gpuix-shell.json`. The Nix side is one line: `home/themes/default.nix` `render` already has `"desktop-shell.json" = builtins.toJSON t;` — add `"gpuix-shell.json"` the same way. Role mapping also exists in `design/gpuix-comparison/desktop.tsx:20`. |
| Theme reload signal | `theme` script's `reload_hyprland` sends `SIGUSR1` to `desktop-shell.service` | `home/dot_local/bin/theme` diff (+`reload_hyprland`) | adapt | Rename to the new unit(s) or drop (the fs watch already fires on symlink retarget). |
| Notifications daemon (D-Bus) | Owns `org.freedesktop.Notifications` with `DO_NOT_QUEUE`, refuses if not primary owner; `GetCapabilities → ['actions','body']`; `GetServerInformation → ['Desktop shell','Tom','0.1.0','1.2']`; `Notify(susssasa{sv}i)→u` reads hints `urgency`, `resident`, `transient`; `CloseNotification` reason 3; signals `NotificationClosed(uu)`, `ActionInvoked(us)` | `notifications-daemon.ts:9-13, 43-56` | keep | `dbus-next` 0.10.2 installed; the HM unit was `Type=dbus`, `BusName=org.freedesktop.Notifications` (`home/hyprland.nix:45-47`). Missing vs mako: icons/image hints, `body-markup`, `persistence`, `sound`, `x-canonical-private-synchronous`, `category`, progress `value` hint (mako's progress bar used it — Tom's 2026-10-12 ruling). |
| Notification store | IDs 1…2³²−1 wrap, replace-by-id keeps id and moves to newest, actions pairs ≤ 32 with 256-char key cap (keys never truncated), summary 1024 / body 8192 / app 256 caps, urgency clamp, bounded 100 active (oldest closed reason 4) and 100 history, transient never in history, timeout: critical never, −1 → 6000 ms, else min(timeout, 2³¹−1); `close(id, reason)` idempotent; commands `dismiss`, `dismiss-latest`, `action` (allow-listed key; non-resident closes with reason 2), `dnd`, `clear` | `notifications.ts:15-71` | keep | 11 tests `notifications.test.ts`. DND here only suppresses toasts (`notifications-daemon.ts:20,23`); the store still records. |
| Daemon ⇄ UI IPC | JSON lines over `$XDG_RUNTIME_DIR/desktop-shell/notifications.sock` (0700 dir, 0600 sock, refuses non-socket / foreign-uid path); `{"type":"subscribe"}` → stream of `{"type":"snapshot",snapshot}`; one-shot commands answered `{"ok":true}`/`{"ok":false,"error"}`; 16 KiB input cap, 4 MiB writable cap, 3 s idle timeout before subscribe | `notifications-daemon.ts:57-75`, `notifications-client.ts:5-43` | keep (fold into shell.sock) | Client reconnects with 250 ms→10 s backoff and times out a silent server after 3 s (`notifications-client.ts:16-18`), tested in `notifications-client.test.ts`. |
| Toast supervision | Daemon spawns `desktop-shell toasts` as a child when items > 0 and not DND; child exits whenever `min(4,items)` changes, on DND, on disconnect; daemon respawns after 30 ms (clean) or backoff 250 ms→10 s (crash); `DESKTOP_SHELL_DISABLE_TOASTS=1` for tests | `notifications-daemon.ts:16-37`, `ui.tsx:61-88, 1239-1259` | replace | Reason given at `ui.tsx:1239-1241`: GPUIX 0.10 has no layer-surface resize / input-region setter, so the toast surface is sized to `toastCount*148-8` and recreated. BRIEF §3.2 puts toasts + OSD in the notifications daemon's own window instead; check whether 0.11 can resize a layer surface (§6). |
| Toast ordering | urgency desc, then createdAt desc, max 4; history view merges active + history sorted by createdAt desc | `ui.tsx:991-1007` | keep | |
| Notifications view | DND toggle button, Clear all, scrolling list, footer "N active · M in history"; row shows app (mono, brand colour when urgent), HH:MM, Dismiss (active only), summary (600), body (clipped 100 px), action buttons | `ui.tsx:1008-1161` | keep (restyle) | |
| Bar | 32 px top bar, exclusive zone 32, `keyboardInteractivity none`: "Go to" button, workspace buttons (2 px brand underline on focused), active window title (click → windows view), error, battery (`/sys/class/power_supply/*/capacity,status`), clock HH:MM (→ controls), notifications count / DND / offline (→ notifications), Controls | `ui.tsx:511-605, 160-193, 1263-1301` | replace | BRIEF: **left rail**, 56 collapsed / 220 expanded, no top bar, herdr status glyphs. Keep the status sampling (15 s clock+volume+battery, `ui.tsx:187-193`) and `wpctl get-volume @DEFAULT_AUDIO_SINK@` parse (`:162,180-183`). |
| Launcher surface | 700×580 overlay, anchor top-right, margin `[40,12,0,0]`, keyboard exclusive, Esc closes, ↑/↓/Enter, Tab cycles focus (`renderer.focusNext/focusPrevious`), search input autofocus | `ui.tsx:606-781, 1260-1330` | adapt | BRIEF: overlay centred, top margin 108, 700×580 — same size. Keyboard handling at `ui.tsx:1303-1329` is reusable as-is. |
| Controls surface | 560×710: date + battery; Sound (volume down/mute/up, audio-route internal/speaker/inzone); Display (brightness down/up; **Effects animations/blur via `hyprctl keyword`**); Appearance (3 theme buttons, selected = current); Media prev/play/next; Connections (kitty nmtui, blueman-manager); Terminal/Chrome/Capture area | `ui.tsx:782-936, 202-212` | adapt | Drop Effects (`ui.tsx:848-880`). Everything else shells out to existing scripts — exactly BRIEF §3.4. Wi-Fi/Bluetooth menus are **new** (BRIEF wants NetworkManager/BlueZ over D-Bus). |
| Windows surface | 700×580: workspace lifecycle buttons (new/rename/detach/park/restore → `desktop-workspace`), per-workspace list with `WindowRow` (focus, move-to-workspace chips, group/ungroup) | `ui.tsx:937-990, 462-510` | adapt | `desktop-workspace` is a shim over `herdr-picker --workspace` (`bin/desktop-workspace:8`); the main branch's `sway-workspace` is the Sway name. Group/ungroup → `layout tabbed`/`layout toggle split`. |
| Top-display workspace switcher (Mod+i) | Rows for slots 1–9 ∪ workspaces actually on the target output; skips ambiguous numbers; status per projector from the herdr snapshot (`identity` by live title, `assigned_identity` by marks, "unavailable" when herdr is down, "multiple projectors" when > 1); markers `●` focused / `!` urgent; `activate` re-reads outputs+workspaces and refuses on any drift; parked projectors identity-checked (`id,pid,app_id`) before `focus_view` | `home/dot_local/bin/sway-workspace-switcher:38-104` | keep (port the model to TS) | This is the BRIEF's `gpuix-shell switcher`. The fuzzel rendering (`:106-137`) goes away; the row model and guards stay. 16 tests in `tests/workspace-switcher/test_switcher.py`. |
| Sway capability adapter | `createSwayCapabilities({output:'eDP-1', run})` → `snapshot()` (outputs + workspaces on the target output, `__`-prefixed names hidden, availability flag, never mutates) and `focusWorkspace(selection)` (single-flight, revalidate id/name/num/output, `workspace --no-auto-back-and-forth "<name>"`, verify after, name quoting rejects `"\\$;,` control chars, `--` prefix and reserved words) | `design/gpuix-comparison/platform.ts:43-54` | keep | Framework-neutral; 26 mocked tests. The natural seed for `src/sway/ipc.ts`. |
| Compositor-agnostic helpers | `desktop-control focused-output` (unique focused output or fail), `focused-geometry` (Sway: `rect + window_rect` of the unique focused node → `x,y wxh` for grim), `power-on/off` (`swaymsg -r -- 'output * power …'` checking every `success`) | `home/dot_local/bin/desktop-control:40-78` | keep (Sway branches) | 8 tests in `tests/desktop-control/test_helpers.py` with argv-logging mocks. |
| Nix packaging | `buildNpmPackage` with `npmDepsHash`, `npmFlags --ignore-scripts`, `dontNpmPrune`, `doCheck` runs `bun test`, buildPhase `npm run typecheck && bun run build`, installs `dist node_modules package.json`, `makeWrapper bun … --add-flags dist/main.js --set DESKTOP_SHELL_EXECUTABLE … --prefix PATH (hyprland glib wireplumber cliphist wl-clipboard) --prefix LD_LIBRARY_PATH (cc.lib libxkbcommon wayland vulkan-loader fontconfig freetype libGL libX11 libxcb openssl)`; `autoPatchelfHook` + `buildInputs = [cc.lib libxkbcommon]` for the napi binary; source filter drops `node_modules dist result` | `pkgs/desktop-shell/default.nix` | keep | Swap `hyprland`→`sway` on PATH; recompute `npmDepsHash` for `@gpuix/react` 0.11.0; `platforms = x86_64-linux`. Overlay line: `overlays/default.nix` `desktop-shell = final.callPackage ../pkgs/desktop-shell { };`. |
| Bun bundle | `Bun.build({entrypoints:['./main.ts'], target:'bun', outdir:'dist', plugins:[solidPlugin, native-addon-boundary], external:['dbus-next']})`; the boundary plugin marks exactly `^@gpuix/native$` external (a Bun 1.3 export-star bug note) | `build.ts:4-24` | adapt | For React: drop `solidPlugin`; keep the native boundary and `dbus-next` external. README.md:46-48 warns against externalising `solid-js`; the React analogue is just "bundle react". |
| HM units | `desktop-shell-core` (daemon, `Type=dbus`, `Restart=on-failure`, `RestartSec=2`, `Slice=app.slice`, `UMask=0077`, `ConditionEnvironment=HYPRLAND_INSTANCE_SIGNATURE`), `desktop-shell-clipboard-{text,image}` (`wl-paste --type … --watch cliphist store`), `desktop-shell` (bar, `Requires=desktop-shell-core`), all `After/PartOf/WantedBy = hyprland-physical-session.target` | `home/hyprland.nix:38-101` | adapt | Target → `sway-physical-session.target`; condition → `SWAYSOCK`; one unit per BRIEF surface family. |
| Mutual exclusion with Vicinae/mako | `ConditionEnvironment = "!HYPRLAND_INSTANCE_SIGNATURE"` on the vicinae and mako units when the native shell is on | `home/vicinae.nix` diff | replace | BRIEF: option `programs.gpuixShell.enable`, never both. An env condition cannot express that on the same Sway session; use the HM option. |
| Chord wiring | `$mod d`/`$mod space` → launcher; `$mod v` → launcher `--provider clipboard`; `$mod Shift v` → notifications; `$mod grave` → windows; `$mod comma` → controls; `$mod Ctrl d` → launcher | `home/dot_config/hypr/binds.conf:2,3,27,28,30-32` | adapt | Main-branch Sway chords that these replace: `binds.conf:6-7` (`vicinae toggle`), `:116` (`vicinae cmd launch clipboard:history`), `:10` (`sway-workspace-switcher --output eDP-1`). Note `herdr-sway-context` branch takes `$mod grave` for kitty/Chrome swap (BRIEF row) — conflict with "windows" view. |
| Compositor smoke | Headless Sway (`WLR_BACKENDS=headless`, pixman, no libinput), private non-activating D-Bus addresses, wait for `sway-ipc*.sock` and `wayland-*`, map check through `get_tree` `app_id`, `grim -o HEADLESS-1`, PIL pixel assert for the dark palette; two-output variant with `wtype` virtual keyboard for Mod+i | `design/gpuix-comparison/smoke-native.py`, `tests/workspace-switcher/smoke.py:26-68` | keep | These are the BRIEF's `tests/gpuix-shell/smoke_<surface>.py` template. Store paths are pinned (`SWAY='/nix/store/04g9x522…-sway-1.12/bin/sway'`, grim 1.5.0, fuzzel 1.14.1, wtype 0.4, bun 1.4.2). |
| Isolation wrapper | `runtime-test --render-node /dev/dri/renderD128 -- …` | `home/dot_local/bin/runtime-test` (diff), `tests/runtime-test/test_render_node.py` | keep | BRIEF §1 already says copy it. |
| Blur / effects research | GPUI patch for `ext-background-effect-v1`, never compiled | `pkgs/desktop-shell/patches/` | drop | Stock Sway has no blur (`SWAY-COMPARISON.md:7`); BRIEF: flat and opaque. |
| OSD (volume/brightness) | none here | — | new | Existing `volume`/`brightness` scripts "pop one OSD per press" (`sway/binds.conf:140`) via some current OSD path (`osd` script in BRIEF row); the notifications daemon window is the BRIEF's home for it. |
| Wi-Fi / Bluetooth menus | opens `nmtui` / `blueman-manager` | `ui.tsx:913-920`, `providers.ts:13` | new | NetworkManager / BlueZ via `dbus-next` — the daemon already has the bus handle pattern. |
| Power menu | none | — | new | `desktop-control power-off` exists for DPMS only. |
| File explorer | bounded name search only | `providers.ts:133-163` | new | Pinax-like per BRIEF; nothing here to lift beyond `gio open` and the symlink/dotfile skipping rules. |
| Left rail with herdr status | none (top bar only, no herdr read) | — | new | Status glyphs come from `herdr api snapshot` as `sway-workspace-switcher:216-218` + `herdr-picker:268-306` read it (`remote_snapshot`, `identity`, `assigned_identity`). |
| Icons | none in the shell; inline-SVG `<svg source=…>` 16×16 path set in the comparison study | `design/gpuix-comparison/desktop.tsx:12,33` | new | GPUIX renders `<svg source>`; the BRIEF names "Anthropicons" glyph font instead. |
| OpenUI `ask` surface | none | — | new | out of scope here. |

---

## 4. Design values found in the code (MEASURED)

These are what the Hyprland build actually used. BRIEF §3.3/§3.6 overrides several (left rail,
flat and opaque, Tacit spacing); they are listed so a builder knows what was tried and what the
other replaced surfaces (Vicinae, mako) look like today.

**Fonts** (`theme.ts:26-30`): `sans: "Anthropic Sans"`, `mono: "Anthropic Mono"` (note: the
installed mono family is "AnthropicMono Nerd Font" per BRIEF — `theme.ts:28` is probably a
silent fallback), `serif: "Anthropic Serif"`. Body 13 px (`ui.tsx:308`), mono 11 px (`:320`),
launcher input 15 px (`:626`), popup title 17/600 (`:1212`), subtitle 11–12 px. Vicinae today:
"Anthropic Sans" 12 (`vicinae.nix:19-22`). mako today: "Anthropic Sans 11" (`vicinae.nix:56`).
Comparison study: 13 body, 11 muted, 26 serif heading, `lineHeight 24` (`desktop.tsx:32,54`).

**Palette roles** (`theme.ts:31-49`, fallback = noir, matches `home/themes/noir.nix`):

| Role | noir | Source key in `desktop-shell.json` (`theme.ts:64-88`) |
|---|---|---|
| background | `#000000` | `ground.desktop` (dark) / `ground.base` (light) |
| surface | `#000000` | `ground.raised` |
| subtle | `#000000` | `ground.dim` |
| foreground | `#EAECF0` | `fg` |
| secondary | `#D3D7DE` | `fgDim` |
| muted | `#818898` | `comment` (dark) / `fgDim` (light) |
| border | `#373735` | `border.inactive` |
| selection / selectionText | `#264F78` / `#EAECF0` | `selection.bg` / `selection.fg` |
| error | `#F47B85` | `red` |
| accent | `#70B8FF` | `accent` |
| brand / primary | `#D97757` | `brand` (light primary hard-coded `#A74B2F`, text `#FFFFFF`; dark primary text `#131313`) |
| hover | `#37373555` | `border + "55"` on noir, else `ground.dim` |

The JSON fragment is the **raw palette attrset** (`builtins.toJSON t`), so every key in
`noir.nix` is available: `ground.{base,dim,raised,desktop}`, `fg`, `fgDim`, `comment`, `muted`
(`#45475a`), `red green yellow blue magenta cyan orange`, `accent`, `brand`, `ansi.*`,
`selection.{bg,fg}`, `cursor`, `cursorText`, `border.{active #555451, inactive #373735, urgent
#F47B85}`, `tabIndicator.{active,inactive}`, `insertHint`, `gtk.*`, `name`, `polarity`.

**Alpha / translucency used (to be removed under "flat and opaque")**: bar `background+"d9"`
(85 %) and `border+"b3"` (`ui.tsx:521-523`); popups and toasts `background+"e6"` (90 %)
(`:1019,1181,1203`); `transparent: true` on every window (`:1283`); Hyprland `layerrule`
`desktop-shell-blur` with `ignore_alpha = 0.2` (`hypr/rules.conf:33-38`).

**Geometry per surface** (`ui.tsx:1260-1302`):

| Surface | Size | layer | anchor | exclusiveZone | keyboard | margin [t,r,b,l] |
|---|---|---|---|---|---|---|
| bar | 1×32 (stretched) | top | top,left,right | 32 | none | 0,0,0,0 |
| launcher | 700×580 | overlay | top,right | −1 | exclusive | 40,12,0,0 |
| windows | 700×580 | overlay | top,right | −1 | exclusive | 40,12,0,0 |
| controls | 560×710 | overlay | top,right | −1 | exclusive | 40,12,0,0 |
| notifications | 500×650 | overlay | top,right | −1 | exclusive | 40,12,0,0 |
| toasts | 390×(n·148−8), n ≤ 4 | overlay | top | −1 | none | 40,0,0,0 |

`namespace` and `appId` = `desktop-shell-<mode>` (`:1262,1285`). mako today: width 390, margin
12, padding 14, border 1, radius 0, anchor top-center, default-timeout 5000, max-visible 4, layer
overlay, high urgency never times out, border colours low=`border.inactive` / normal=
`border.active` / high=`red` (`vicinae.nix:56-66`, theme mako fragment). Vicinae today: opacity 1,
no material, rounding 0, CSD border 1, shadow 0, layer-shell on (`vicinae.nix:32-41`). Fuzzel
switcher today: width 56 ch, pads 16/14/12, border 1, radius 8, selection radius 4, Anthropic
Sans 12, overlay, exclusive keyboard, explicit `--output` (`sway-workspace-switcher:126-137`).

**Component metrics** (`ui.tsx`): Button height 32 (small 26), padding 10 (8), radius 6, border
1 (none when small/quiet), focus ring = accent border, selected = hover bg + foreground border,
weight 600 when selected (`:346-369`); Tab height 34, 2 px underline, marginRight 18 (`:396-405`);
Section gap 10, padding 14/16, hairline bottom (`:423-431`); launcher row height 48, radius 4,
padding 12, gap 12, 3×22 brand bar on the selected row (`:684-704`); search input height 42,
padding 10, radius 6 (`:626-633`); popup container padding 16, gap 12, radius 8, border 1
(`:1197-1209`); toast card padding 10, gap 6, height 140, radius 8, body clipped 28 px
(`:1013-1024,1072`). Comparison study (closer to the Tacit/Primer feel): top bar 44, sidebar 220,
button height 30, radius 8, panel 430 wide radius 10 padding 20, status strip 30, range track 5 px
(`desktop.tsx:50-63`).

**Timings**: event debounce 40 ms, reconnect 250 ms→10 s, snapshot retry 2 s, hyprctl timeout 5 s
(`controller.ts`); status poll 15 s, native tick 500 ms (`ui.tsx:189,1335`); provider debounce
120 ms (`:122`); theme watch debounce 50 ms (`theme.ts:137`); toast respawn 30 ms / crash backoff
250 ms→10 s, first-snapshot wait 3 s (`notifications-daemon.ts:30-32`, `ui.tsx:1243-1248`);
notification default timeout 6 s, critical never (`notifications.ts:45`); socket idle 3 s;
singleton contact 1 s, stale threshold 2 s (`singleton.ts:17,52`).

**Key handling** (`ui.tsx:1303-1329`): `tab`/`shift+tab` → `renderer.focusNext()/focusPrevious()`;
`escape` closes any popup; launcher `down/up/enter`. GPUIX key names are lowercase (`"enter"`,
`"space"`, `"escape"`, `"tab"`, `"down"`), modifiers in `e.modifiers.shift/ctrl/cmd`
(`desktop.tsx:43` adds `ctrl+k` toggle).

---

## 5. Reusable code and data, with exact paths

### 5.1 D-Bus notifications server — `pkgs/desktop-shell/notifications-daemon.ts`
- Bus ownership and refusal: lines 10-13.
- Interface class with `configureMembers` signatures: lines 43-55 (`Notify` in `susssasa{sv}i` out `u`; signals `NotificationClosed uu`, `ActionInvoked us`).
- Export at `/org/freedesktop/Notifications`: line 56.
- Store wiring (snapshot broadcast to subscribers + toast kick): lines 38-42.
- Socket server (subscribe vs one-shot command): lines 57-75; shutdown: 76-78.
- Pure store: `notifications.ts:15-71`; command parser `notifications.ts:72-83`; types 1-13.
- Client: `notifications-client.ts:10-33` (follow), `34-43` (command), socket path `5-9`.
- **INFERRED port**: keep daemon + store verbatim under `src/notifications/`; rename the socket to the BRIEF's `shell.sock` and add message types for OSD/launcher toggles; add hints `image-path`/`image-data`, `value` (progress), `category`, `desktop-entry` (for app icon lookup via the XDG index) before claiming mako parity.

### 5.2 XDG application index + GIO launch — `pkgs/desktop-shell/applications.ts`
- `parseDesktop(contents, path, id, desktops)` 11-55; `applications(env)` 56-92; `searchScore` 93-102.
- Launch: `run("gio", ["launch", a.path])` at `ui.tsx:241`.
- Change `"Hyprland"` → `"sway"` at line 62. Consider parsing `Icon=` and `Actions`.

### 5.3 Compositor controller — `pkgs/desktop-shell/controller.ts` + Sway mapping

Keep `DesktopController` (95-215) and replace three things:

| Hyprland today | Sway equivalent (INFERRED; names from sway-ipc(7)) | Already done in this tree |
|---|---|---|
| event socket `$XDG_RUNTIME_DIR/hypr/<sig>/.socket2.sock` (`controller.ts:57-64`), newline events `workspace>>…` | `swaymsg -t subscribe -m '["workspace","window","output","shutdown","binding"]'` (one JSON object per line) **or** in-process i3-ipc on `$SWAYSOCK`: header `"i3-ipc"` + u32 length + u32 type, `SUBSCRIBE=2`, replies carry `change` | — |
| `hyprctl -j clients` | `swaymsg -r -t get_tree` and walk `nodes`+`floating_nodes`; a view has `app_id` (or `window` for Xwayland), `id` (con_id), `pid`, `name`, `focused`, `urgent`, `marks[]`, `rect`, `window_rect` | `herdr-picker:154-163` (`walk`, `views`), `desktop-control:65-78`, `smoke-native.py:16-18` |
| `hyprctl -j workspaces` | `swaymsg -r -t get_workspaces` → `{id,num,name,output,focused,visible,urgent,rect}`; `num=-1` for named/scratch | `platform.ts:26`, `sway-workspace-switcher:28-30` |
| `hyprctl -j monitors` | `swaymsg -r -t get_outputs` → `{name,active,focused,scale,rect,current_workspace}` | `platform.ts:25`, `desktop-control:57-61` |
| `hyprctl -j activewindow` | the unique `focused:true` view in the tree (`desktop-control:67-75`) | — |
| `dispatch focuswindow address:0x…` reply `ok` | `[con_id=N] focus` reply `[{"success":true}]` | `herdr-picker:260-263` |
| `dispatch workspace N` | `workspace number N`, or `workspace --no-auto-back-and-forth "name"` with name quoting | `platform.ts:29,50`, `herdr-picker:94-101,204-209` |
| `movetoworkspacesilent N,address:…` | `[con_id=N] move container to workspace number N` | `herdr-picker:256` |
| `togglegroup` / `changegroup` events | `layout tabbed` / `layout toggle split`; Sway's tabbed containers are the group model (`SWAY-COMPARISON.md:12`) | — |
| `special:herdr-parked` | scratchpad `__i3_scratch` + `herdr-slot-N` / `herdr-closed-<ns>` / `herdr-name-<hex>` marks | `herdr-picker:24-29,166-171,541-576` |
| `hyprctl keyword animations/decoration:blur` | none — remove | — |
| `hyprctl dispatch dpms on/off` | `swaymsg -r -- 'output * power on\|off'` | `desktop-control:52-53` |
| `HYPRLAND_INSTANCE_SIGNATURE` guard (`singleton.ts:9`, `controller.ts:121`) | `SWAYSOCK` presence; token `sha256(SWAYSOCK)[:16]` | `sway-workspace-switcher:149` |
| `XDG_CURRENT_DESKTOP` default `Hyprland` | `sway` | — |
| Window identity `address` hex (`controller.ts:224`) | `con_id` safe integer > 0 (`platform.ts:24,26`) | — |

Event regex to subscribe to for the rail: Sway `workspace` (`init/empty/focus/move/rename/urgent/reload`), `window` (`new/close/focus/title/move/urgent/mark`), `output`. The herdr-urgency ruling (Tom 2026-10-14T02:41Z) maps to `workspace.urgent` / `window.urgent` in those payloads and to `client.urgent` colour `border.urgent` in the theme.

### 5.4 Sway capability adapter (framework-neutral) — `design/gpuix-comparison/platform.ts`
- Types 4-15; validators 19-26; `quotedName` 29; `createSwayCapabilities` 43-54 (`readState` 45 reads outputs + workspaces in parallel and rejects duplicate identities; `snapshot` 46; `focusWorkspace` 47-52 with before/after verification).
- Tests `platform.test.ts` 13-26 — copy the fixture pattern (`run` mock switching on `args[2]`).
- Used from Solid in `desktop.tsx:21-28` (`refreshWorkspaces`, `focusWorkspace` with `mounted` guard).

### 5.5 Launcher providers — `pkgs/desktop-shell/providers.ts`
- Command table + catalog 11-67; `providerGaps` 70-76 (honest migration gaps vs Vicinae: Chrome tab search needs the extension bridge, tray needs a StatusNotifier host, file search is bounded, calculator has no units, cliphist ≠ Vicinae history).
- `calculate` 176-225; `providerItems` 227-243; `activateProvider` 245-277 (validates each action kind before executing).
- `launchProviderCommand` 89-95 (detached spawn for interactive helpers) and `executeAction` 96-106 (which commands are interactive).

### 5.6 Theme loader — `pkgs/desktop-shell/theme.ts`
- `Theme` 7-25, `fallback` 31-49, `parsePalette` 52-89, `parseTheme` 91-110, `followTheme` 111-149.
- Nix side: `home/themes/default.nix` diff adds `"desktop-shell.json" = builtins.toJSON t;` in `render` and a `hyprland` fragment (drop the latter). `flake.nix` asserts `clientHome.xdg.configFile ? "themes/noir/desktop-shell.json"` — mirror that assert for `gpuix-shell.json`.
- Consumers that already parse the same JSON outside the shell: `sway-workspace-switcher:106-137` (Python, with a kitty.conf fallback at 110-121), `tests/workspace-switcher/smoke.py:30` writes one from `design/claude-primer/src/palettes.json`.

### 5.7 Layer-shell option sets and the GPUIX API
- Per-surface options object: `ui.tsx:1260-1330` (table in §4). `LayerShellOptions` = `{namespace, layer, anchor[], exclusiveZone, exclusiveEdge, margin[4], keyboardInteractivity}` — identical in 0.10.0 (`pkgs/desktop-shell/node_modules/@gpuix/native/index.d.ts:625-661`) and in the upstream clone (`/home/tom/Downloads/gpuix/packages/native/index.d.ts:678-714`); `WindowOptions.layerShell` at `:731` / `:784`; `appId` "required in practice for a layerShell surface a compositor is meant to target by rule" (`:722-726`).
- `registerFont(data: Buffer)` exists in the upstream d.ts (`index.d.ts:178,386`) — BRIEF says 0.11.0 ships it; the upstream clone's package.json still says 0.10.0, so this is REPORTED by BRIEF, not measured here.
- Mount pattern without a JS tick loop: `createRenderer(); native.init(options); render(<App/>, {...options, renderer: native}); setInterval(() => { if (!native.tick()) close() }, 500)` — `ui.tsx:1331-1337`, `design/gpuix-comparison/main.ts:8,10`. README.md:30-31 explains why (Linux GPUI owns its UI thread). The React equivalent in `@gpuix/react` is **unverified** here (§6).
- Native-binding guard: `__napiBindingTarget === 'native'` refusal of WASI (`gpuix-comparison/main.ts:2,6`).
- Known GPUIX 0.10 limits noted in code: no layer-surface resize or input-region setter (`ui.tsx:1239-1241`), no output selector (README.md:64-65 — the bar lands on the compositor-chosen output; the BRIEF wants eDP-1), stock screenshot renderer unavailable on Linux (README.md:66; use grim), Ctrl+/− zoom not registered (Tom 2026-10-13T23:45Z, unanswered in what I read).

### 5.8 Singleton and toggle protocol
- `singleton.ts:4-73` (described in §3). Alternative with flock: `sway-workspace-switcher:140-195` (`Toggle` class: dir 0700 + symlink/uid check, `sha256(SWAYSOCK)` token, `LOCK_EX|LOCK_NB`, 20×25 ms contact loop, `b"close\n"`), tested at `test_switcher.py:76-92`.

### 5.9 Test shapes to copy
- `controller.test.ts`: `harness()` injects a fake `execute` keyed on `args[1]` and a fake `createConnection` returning an `EventEmitter` with `destroy()`; proves split-line buffering (94-108), 40 ms coalescing (105: exactly 4 `hyprctl` calls per burst), reconnect after `close` (110-125), epoch guard (127-142). 9 tests, all pure.
- `providers.test.ts`: 12 tests; filesystem fixture via `mkdtemp` for the file provider (105-126); argv-capturing executors; `__proto__` and injection strings as negative cases.
- `notifications.test.ts`: 11 tests on the store with injected `now`; flood bound (26-28); opaque-key aliasing (39-45).
- `notifications-client.test.ts`: real Unix socket in a temp `XDG_RUNTIME_DIR`, proves the 3 s "accepting but silent" timeout and reconnect (6 s budget).
- `notifications-integration.test.ts`: opt-in `DESKTOP_SHELL_DBUS_TEST=1`, spawns the daemon under `bun main.ts daemon` on a private `dbus-run-session`, exercises `Notify`/replace/`ActionInvoked`/`NotificationClosed`/DND/`CloseNotification` and the second-instance refusal (10 s budget).
- Python side: `tests/desktop-control/test_helpers.py` (mock binaries written to a temp PATH that log argv as JSON lines, `FAIL_COMMAND` env to inject failure), `tests/workspace-switcher/test_switcher.py` (loads the script as a module via `SourceFileLoader`, `patch.object(b,'ipc')` asserts no mutation on refusal), `tests/workspace-switcher/smoke.py` + `design/gpuix-comparison/smoke-native.py` (headless Sway, evidence dir under `/tmp`, `results.json`).
- Nix: `default.nix:17-23` runs `bun test` in `checkPhase` with no compositor; `flake.nix` diff wires `tests/herdr/test_hyprland_picker.py` and passes `desktop-control` to `tests/screenshot/test-spool.sh`.

### 5.10 Scripts and config to re-point
- `home/dot_local/bin/desktop-notifications` (17 lines): `dismiss|history` chooses `desktop-shell notifications-dismiss|notifications` when `HYPRLAND_INSTANCE_SIGNATURE` else `makoctl dismiss|restore`. Shape for a `gpuix-shell notify …` shim; condition should become "is the shell socket present".
- `home/dot_local/bin/desktop-workspace` (8 lines): `exec herdr-picker --workspace $1`.
- `home/vicinae.nix` diff: desktop entries `sway-workspace-new/restore/rename`, `notifications-dismiss/history`, `network-settings` → these are the launcher commands Vicinae exposes today and the catalog in `providers.ts:46-67` already mirrors them.
- `home/dot_config/sway/binds.conf` (main branch + this worktree's `$mod+i` line): the chords the new shell takes over are 6, 7, 10, 116; everything else stays a script.

### 5.11 "What we give up on Sway" — `tests/hyprland/SWAY-COMPARISON.md`
Blur, compositor animation, compositor decoration (rounded clipping, shadows, dim), layer-specific
rules (blur/ignore-alpha/dim-around per namespace), dwindle/master/scrolling layouts, special
workspaces, continuous gestures, in-process plugins. Retained: tabbed/stacked groups, layer-shell
v5 with anchors/exclusive zones/keyboard modes, screencopy/ext-image-copy, output management,
HDR/10-bit per sway 1.12 docs. SwayFX noted as optional, not selected. All consistent with BRIEF
"flat and opaque, hairlines not shadows".

---

## 6. Gaps, unknowns, conflicts

1. **Solid → React**: nothing in this tree uses `@gpuix/react`. The Solid specifics are small (`createSignal/createMemo/For/Show`, `render(() => <App/>, {renderer})`, the `bun-plugin`), but the React package's mount API, event payload names and `focusNext/focusPrevious` availability are **unverified**. Check `/home/tom/Downloads/gpuix` `packages/react` before copying `ui.tsx:1331-1337`.
2. **GPUIX 0.11 layer-surface resize**: the whole toast respawn dance (`notifications-daemon.ts:19-37`) exists because 0.10 could not resize a layer surface. If 0.11 still cannot, the BRIEF's "toasts + OSD in one daemon window" needs a fixed-size always-mapped surface with transparent regions — which the 0.10 code explicitly avoided because a transparent rectangle swallows clicks (`ui.tsx:1241`). Unknown; measure under runtime-test.
3. **Output targeting**: README.md:64-65 says GPUIX exposes no output selector; the rail must sit on eDP-1 (BRIEF). Sway can move a layer surface only by namespace rules? (No — Sway has no `layerrule`; placement is the client's `wl_output` choice at surface creation.) Needs a GPUIX API check (`WindowOptions` has no output field in either d.ts I read).
4. **Toast anchor conflict**: Tom 2026-10-11 "top and center not top right" (mako) vs BRIEF §3.3 "toasts = overlay top-right". The Hyprland build used anchor `["top"]` with margin 40 (centred). Flag in ASSUMPTIONS.md; I did not write there (read-only brief).
5. **Mono font name**: `theme.ts:28` says `"Anthropic Mono"`; the installed family is `"AnthropicMono Nerd Font"`. Nothing here proves which name GPUI resolved.
6. **`$mod+grave` collision**: this worktree binds it to `desktop-shell windows`; the unmerged `herdr-sway-context` branch binds it to the kitty/Chrome swap (BRIEF row). The windows view is the least essential surface; probably yield the chord.
7. **DND semantics**: here DND only stops toasts; mako's `makoctl mode` is similar. The store still fires `NotificationClosed` on expiry — fine, but the rail badge logic (`ui.tsx:593-599`) shows a count only when `items.length > 0`, which with DND means nothing is surfaced at all.
8. **Notification hints not handled**: icons/images, `value`, `category`, `desktop-entry`, `body-markup`, `urgency` as byte variant only (`hints.urgency?.value`, `:48`). `GetCapabilities` honestly returns only `actions, body`.
9. **Clipboard**: cliphist units are the only store; BRIEF wants an own store. Nothing here implements `wl-paste --watch` consumption in-process.
10. **Herdr read in the shell**: the GPUIX code never reads herdr; only the Python switcher does (`sway-workspace-switcher:216-218` via `herdr-picker.remote_snapshot`, which SSHes to strix when `HERDR_SWAY_LOCAL=0`, 6 s timeout, `-o ConnectTimeout=3`). The rail must poll this; the BRIEF says "polled". Latency and the SSH path on the client are the unknowns.
11. **npmDepsHash** in `default.nix:12` is for the 0.10.0 lockfile; any dependency change needs a fresh hash (`lib.fakeHash` round-trip).
12. **dbus-next**: 0.10.2 installed; it is an old, lightly maintained package (REPORTED knowledge, not measured here). It worked for the D-Bus integration test the README claims (REPORTED: README.md:41, "nine controller tests" — the file now has 9 + 12 + 11 + 1 + 1 opt-in; I did not run them tonight).
13. **No evidence the GPUIX layer-shell path ever rendered on Sway**: the Sway proof (`design/gpuix-comparison`) used ordinary toplevels (`windowBackground:'opaque'`, `resizable:true`, `main.ts:7`); the layer-shell surfaces were only exercised on nested Hyprland, and `SWAY-COMPARISON.md:26` says the shell hit a bundling bug before mapping there. **First compositor smoke of the night should be: one GPUIX layer surface on headless Sway, under `runtime-test --render-node`.**
14. **Tom's Ctrl+/− zoom question** (2026-10-13T23:45Z) and the **Ctrl+K contextual menu / agent-driven HCI** idea (23:46Z, 2026-10-14T01:08Z) have no code here; the comparison study has a `ctrl+k` toggle (`desktop.tsx:43`) only.
15. **Untracked/uncommitted**: `pkgs/desktop-shell/README.md`, `.gitignore`, `notifications-client.test.ts`, `patches/`, `design/`, `sway-workspace-switcher`, `tests/{desktop-control,hyprland,workspace-switcher}` are untracked in that worktree — copy from the filesystem, not from git.

### What I did not do
- Did not run any test, build, or compositor; every "passed" above is REPORTED from READMEs.
- Did not read `tests/herdr/test_hyprland_picker.py`, `tests/hyprland/smoke.py`, `aquamarine-nested.nix`, the `claude-*` design studies, or the full `herdr-picker` beyond the functions named.
- Did not write to ASSUMPTIONS.md or any file other than this note.
