# 03 — Codex desktop-shell builds (2026-10-13 23:08 → 2026-10-14 01:38 CEST): engineering lessons

Reader: wave-1 transcript reader 03 (Claude, overnight gpuix-shell run, 2026-10-20).
Scope: four Codex rollouts. Read-only; nothing in `/home/tom/mecattaf/dotfiles`, live Sway, herdr or systemd was touched.
Labels: **MEASURED** = a command output, test result, file content or log line visible in the transcript or on disk today;
**REPORTED** = an agent's or a document's claim that I did not re-run; **INFERRED** = my reading, not stated anywhere.

---

## 1. What this source is

### 1.1 The four files

| Key | Rollout (all under `/home/tom/.codex/sessions/2026/10/`) | Agent (nickname, path) | Tasks it ran (CEST) |
|---|---|---|---|
| **[S]** | `13/rollout-2026-10-13T23-08-44-01a13718-a43b-7c12-95ff-efa554c312aa.jsonl` | Bernoulli, `/root/gpuix_solidjs` | 23:08 GPUIX/Solid research note → **23:53 built `pkgs/desktop-shell`** → 00:16 Claude/Primer restyle + launcher providers + notification centre + toasts → 00:25 notification review → 00:31 Mail web mockup (`design/claude-mail`) |
| **[M]** | `14/rollout-2026-10-14T01-01-43-01a13780-13dc-78e2-aa44-067ec692480b.jsonl` | Ramanujan, `/root/mail_worker` | 01:01 live Mail web reader → 01:07 `DESKTOP-REQUIREMENTS.md` (41 reqs) → 01:13 mail browser actions + **native `email.tsx`** + **Sway adapter `platform.ts`** → 01:22 native mail connected reads |
| **[C]** | `14/rollout-2026-10-14T01-01-49-01a13780-2ee4-7a31-b3ab-754355937678.jsonl` | Gauss, `/root/crm_worker` | 01:01 live CRM web reader → 01:07 `COMPONENT-COVERAGE.md` → 01:13 CRM writes + **native `desktop.tsx`** (rail/launcher/notifications/controls on GPUIX, eDP-1 workspace adapter) → 01:33 code-mode MCP survey |
| **[P]** | `14/rollout-2026-10-14T01-02-00-01a13780-5686-7812-8974-8a178f4c4b21.jsonl` | Carver, `/root/projects_worker` | 01:02 live Projects web reader → 01:07 bridge audit → 01:13 React/Solid portability proof + **native harness** (`main.ts`, `smoke-native.py`, `automation-native.ts`, `package-native.py`, `smoke-live.py`) → **01:34 launched the native Mail+Desktop windows on the Zenbook's live Sway** |

All four are **subagents forked from the root Codex session `01a1370e-04d2-7c42-a3e8-7b0968ad155e`** (the "GPUIx pivot" session in the BRIEF, not read by me).
Their first record is a `compacted` replacement history that replays Tom's root-session messages verbatim, which is where the rulings in §2 come from.
Every `/root → worker` task payload and every `send_message` body is **encrypted** in the rollouts; what each worker was asked to do is reconstructed from its tool calls and final answers (INFERRED where noted).
Model `gpt-6-astra`, effort high, `approval_policy: never`, sandbox `danger-full-access`, Codex CLI 0.160.0 (MEASURED, `session_meta`/`turn_context` records).

Pointer syntax used below: **`[S:L253]`** = line 253 of the [S] rollout jsonl (each line is one record; the line number is stable). I extracted readable dumps with a helper; the jsonl line is the authority.

### 1.2 What got built, and where it lives today

Everything is **uncommitted** in the worktree `/home/tom/.wt/hyprland-solid-shell` (branch at `2ac87891`; `git status` shows the pkgs/design dirs untracked, MEASURED today).

- `pkgs/desktop-shell/` — Solid 1 + `@gpuix/native`/`@gpuix/solid` **0.10.0**, Bun-bundled, Nix `buildNpmPackage`; **Hyprland-only** (hyprctl + socket2); 6 modes (`bar|launcher|controls|windows|notifications|toasts`) + `daemon` (org.freedesktop.Notifications). Built to `/nix/store/pwp11p3rnmwygrykblk3rr3331mw4k4h-desktop-shell-0.1.0` and later store paths (MEASURED [S:L332], [P:L643]). **Never rendered in any compositor** in these transcripts (REPORTED [S:L503] "Actual rendered UI acceptance remains outstanding"; [S:L763] "Actual compositor verification remains with the renderer agent").
- `design/gpuix-comparison/` — the **Sway proof**: native Solid/GPUIX `email.tsx` + `desktop.tsx` as **ordinary toplevel windows (no layer-shell)**, a framework-free Sway adapter `platform.ts`, and an isolated headless-Sway smoke harness. This one **did render and receive input** under `runtime-test --render-node` (MEASURED [P:L604], [P:L779-784], [P:L869-887]).
- `design/claude-suite/DESKTOP-REQUIREMENTS.md` (41 requirement IDs, [M:L180-L190]) and `REQUIREMENTS.md`/`COMPONENT-COVERAGE.md` — the language-independent product contract.
- `design/claude-mail`, `design/claude-crm`, `design/claude-projects` web readers and `design/claude-portability` (React vs Solid on one core model) — **out of shell scope** per BRIEF §3.8, listed only for reusable patterns.
- `/home/tom/mecattaf/dotfiles/research_notes/From Aura to Hyprland/gpuix_solidjs.md` — [S]'s research note (72 lines) with the clearest list of GPUIX API limits ([S:L121]).

### 1.3 Timeline (CEST, from record timestamps)

| Time | Event | Pointer |
|---|---|---|
| 10-13 23:04–23:06 | Tom: notes deep-dive, "supersedes the whole aura requirement … solidjs idea" | §2 |
| 23:08–23:12 | [S] researches GPUIX; finds public `LayerShellOptions`; writes research note | [S:L21-L146] |
| 23:53 | [S] starts `pkgs/desktop-shell` (Hyprland target) | [S:L147] |
| 23:54 | npm tarballs of `@gpuix/{native,solid,native-linux-x64-gnu}@0.10.0` pulled; `layerShell` confirmed in shipped `index.d.ts:625/731` | [S:L181-L199] |
| 23:59 | first Nix build + `--check-native` under `runtime-test` passes; Solid-bundling fix | [S:L332-L336] |
| 00:01 | custom 500 ms tick loop replaces stock 8 ms frame loop | [S:L421] |
| 00:03:41 | Tom: "first step is finalizing the look and aesthetic" → [S] "Stopped feature expansion as instructed" | §2, [S:L503] |
| 00:16 | Tom: "whatever you just opened: i love it … functional replacement to waybar, vicinae and mako" → [S] restyles to Claude/Primer, adds providers/notifications/toasts | [S:L504-L763] |
| 00:23 | Bun "undefined `host`" bundle failure fixed with an exact-match external | [S:L688-L696] |
| 00:24 | toast surface sized to row count because no resize/input-region API | [S:L726] |
| 00:24 | `bun test` under runtime-test: 30 pass, 1 D-Bus integration skipped | [S:L733-L736] |
| 00:25:30 | Tom: "let s tick to sway window manager" | §2 |
| 00:27 | [S] notification fixes; lists what Sway needs | [S:L829] |
| 01:13–01:22 | [M] native `email.tsx`, [C] native `desktop.tsx`, [P] harness | [M:L373], [C:L445], [P:L485-L549] |
| 01:23 | first isolated headless-Sway run fails (`--render-node` unknown to live `runtime-test`), then passes with worktree `runtime-test` | [P:L552-L559] |
| 01:26–01:27 | [M] `platform.ts` Sway adapter + real read-only probe of the client's Sway over ssh | [M:L561], [M:L592] |
| 01:32 | dark-palette pixel assertion added (automation tree has no styles) | [P:L833-L869] |
| 01:34 | [P] launches both native windows on the **live** client Sway, workspace 6 on eDP-1, restores focus | [P:L924-L953] |
| 01:37 | Mail window replaced with connected mode; journal shows GPUI URL errors and 869.4 M memory peak | [P:L1045-L1058] |
| 01:38 | [P] done | [P:L1106] |

---

## 2. Verbatim Tom rulings relevant to the desktop shell

Source: the `compacted` replacement history at the top of [M], [C], [P] (e.g. `[M:L3]`, `[C:L519]`, `[P:L742]`) and the user records of [S] (`[S:L8]`, `[S:L12]`). Typos kept. Times are the `create_time` of each message, converted to CEST.

| When (CEST) | Tom, verbatim | Bearing on gpuix-shell |
|---|---|---|
| 10-13 23:04:11 | "in ~/notes i have all my historical analysis of hte last few projects … heuristic: sacred cows make the best burgers. revisit the chromium aura entire epoch historiically, and understandh how it will now be done on hyprland ; and https://gpuix.dev/ https://github.com/remorses/gpuix https://gpui-kit.com/docs/comparison/" | Origin of the GPUIX direction. |
| 10-13 23:06:46 | "this supersedes the whole aura requirement. it even fucking correesponds to the solidjsidea i had!!!" | GPUIX replaces Aura/Views. (Solid was the 10-13 choice; BRIEF §3.1 now picks React.) |
| 10-13 23:11:34 | "hyprland is just sway with animations and best in class blur. for terminal: herdr + kitty ; until superlogical releases their terminal. for browser, google chrome." | Shell does not replace terminal or browser. |
| 10-13 23:52:29 | "work deploy massive amounts of compute for htis come on ! impress me! all the functionality. become a hyprland expert. and a dotfiles expert. this is the next" | — |
| 10-14 00:03:41 | "the first task is to introspect into my existing claude ui, i tried replicating the claude managed agents ui , and tyhe claude calendar implementation. first step is finailzing the look and aesthetic. i want to use the claude anthropic font, the color scheme and selector, and the github primer react theme kit" | Look first; Anthropic fonts; palette selector; Primer. |
| 10-14 00:16:03 | "whatever you just opened: i love it. this is good enough to also become a functional remplacement to waybar, vicinae and mako notifications. drawing insporation from omarchy's implemetnatipn of wayshell in fact." | The acceptance of the Claude/Primer look; scope = Waybar + Vicinae + Mako replacement. |
| 10-14 00:16:59 | "massive ultracode workflow into the blur implementation (since hyprland has full wayland blur protocol resolved / we re doing functionality pull from quickshell NOT visuals or aesthetics whatsoever" | Quickshell = functional reference only. (Blur work then dropped, next row.) |
| 10-14 00:25:30 | "i digress on the hyprland parts, i m sorry. let s tick to sway window manager. less effort.. but do list all the hyprland functionality that we're "missing out on" in a way so i can decide if i want hat added potentially later or not..." | **Sway only.** Everything Hyprland-specific in `pkgs/desktop-shell` is to be replaced. |
| 10-14 00:30:51 | "have subagents: keep producing clickable things, even if mockups, just making sure htat we keep true to the anthropic (colors on github i think? ) theme kit, show me what a menu and sidebar etc etc could look. impress me visually. mockups are king here." | Clickable over perfect. |
| 10-14 00:30:51 | "specifically one for my email one for my crm. git clone this https://github.com/hieunc229/mailflare into Downloads and analyze it / for the crm make it a pure functional replica of https://github.com/twentyhq/twenty …" | Mail/CRM are apps, not shell (BRIEF §3.8). |
| 10-14 00:33:25 | "one more agent: herdr-web-ui with the existing implemetnation / similarly, one sway-wired workspace switcher that can be toggled with mod i ; with herdr-provided status indicators. only for the top display (consult kanshi config to know which one i m talking about, and existing vicinae herdr wrkspaces item as well if needed. sidequest: resurface from notes the "small agents from owui openwebui create session titles for arbitrary")" | **Mod+i switcher, top display only (eDP-1), herdr status.** Output pinning is the GPUIX gap in §3.2 row L2. |
| 10-14 00:34:24 | "one mroe subagent: for ht left bar, i want you to copy the same proportions as the views c++ left tab bar that we saw from google chrome." | **Left rail = Chrome Views tab-strip proportions** (220/196×30/12/2/8, §4). |
| 10-14 00:58:12 | "are you still working? i hvae lots of cloudflare workers that are my own, that you can literally use instead of email ; crm and projects backends !" | Existing Workers are the backends; shell never re-implements them. |
| 10-14 01:01:43 | "confirm you have access to my cloudflare utilities, i did scoping on those just today. the next step after we're done doing that implementation is to fully fork github primer (react) and have claude design prepare a comprehensive 1:1 kit with everything from anthropic "as if it was designed by anthropic claude 1st party native implementations - bar the font" using those technologies that we hvaew proven are good" | Primer (React) fork + Claude-first-party look; "technologies we have proven" = the GPUIX/React/Solid results of that night. |

Tom quotes carried inside documents the workers read (REPORTED, exact time not in my transcripts):

- `design/claude-suite/REQUIREMENTS.md:9` — "the idea is to keep "grinding" at a unified set of requirements that can outlast any coding language of framework, with react being the real world implementation of it"
- `design/claude-suite/REQUIREMENTS.md:11` — "i am expecitng it to be a react (solidjs compat) superset of github primer, cloudaflare kumo + cloudflare-os. that can do all the way from my desktop shell to the functional desktop that exists." (This is the strongest support for BRIEF §3.1's React choice.)
- `/home/tom/today/UTILITIES-INDEX-2026-10-13.md:9` (quoted at [M:L136]) — "you could say 'post-cfos' since i moved on from wanting my personal cloudflare os mechanism, to the herdr-web-ui era where i fork and customize the existing herdr-web-ui plugin"; same file reports (10-10) "no frontend gets built until the funcitonality is all green." (superseded in practice by the 10-13/14 night).
- `/home/tom/mecattaf/workerd.nix/DECISIONS.md:19` (W11, 2026-08-19, quoted at [M:L148]) — "we'll build that toolkit as we go. no need to start attempting to build this before we encounter a situation where our learnings fully compound. but eventually, i aspire to be able to call a component library that is so powerful that it can rebuild cloudflare-os as a specialization (not a generalization). this will come with time."

Agent-authored constraints that later docs treat as binding (REPORTED, not Tom's words): `DESKTOP-REQUIREMENTS.md:11-16` (Sway selected; Chrome + Herdr/kitty kept; eDP-1 is the top display in the Kanshi Duo profile; no new timers/resident models/speech input).

---

## 3. Feature / behaviour inventory, GPUIX limits, harness and failures

### 3.1 Feature inventory

"Keep/replace/new" is relative to the new `pkgs/gpuix-shell` (React, Sway, BRIEF §3). Paths are under `/home/tom/.wt/hyprland-solid-shell/` unless absolute.

| Feature | What exactly | Where it lives today | Keep / replace / new | Notes |
|---|---|---|---|---|
| Process-per-surface CLI | `desktop-shell [bar\|launcher\|controls\|windows\|notifications\|toasts\|daemon]`, `--provider <p>`, `notifications-clear`, `notifications-dnd on\|off`, `notifications-dismiss`, `--check-native`, `--version`, `--help` | `pkgs/desktop-shell/main.ts:1-59` | **Keep the shape**, rename to `gpuix-shell <surface>` | One GPUIX window per process was forced (§3.2 L6). `--check-native` (loads the addon, opens nothing) is a cheap Nix/CI smoke (MEASURED passes under runtime-test [S:L336]). |
| Toggle singleton | Per-mode Unix socket `$XDG_RUNTIME_DIR/desktop-shell/<sig>-<mode>.sock`; a second invocation sends `close` (popups) or `present` (bar/toasts) and exits; EADDRINUSE → contact → 2 s stale-socket rule, never unlinks a fresh peer | `pkgs/desktop-shell/singleton.ts:1-73` | **Replace** with BRIEF's single `shell.sock` CLI | Keyed on `HYPRLAND_INSTANCE_SIGNATURE` (line 9) — breaks on Sway. Stale-socket handling ([S:L466]) is worth copying. |
| Top bar | Layer `top`, anchor top/left/right, height 32, exclusive zone 32, keyboard none; workspaces, focused window, clock, `wpctl` volume, `/sys/class/power_supply` battery, notification count; 15 s status poll | `pkgs/desktop-shell/ui.tsx:511-605` (Bar), `:155-192` (status), `:1259-1300` (options) | **Replace** with the left rail | Tom: "no top bar on the Linux head" (BRIEF). Status readers (wpctl, power_supply) are reusable. |
| Launcher | Overlay 700×580, anchor top/right, margin `[40,12,0,0]`, keyboard exclusive; providers `all\|windows\|applications\|commands\|clipboard\|files`; fuzzy `searchScore` (all terms required, name-prefix preferred); 8-row window around selection; Up/Down/Enter, Tab/Shift-Tab, Escape closes; `<input onSubmit>` | `ui.tsx:606-781`, `applications.ts:1-102`, `providers.ts:1-277` | **Keep logic, port to React** | BRIEF wants 700×580 at top margin 108 centred, not top-right. Visible-row windowing was a workaround for list scrolling ([S:L389]); 0.10 has `<virtual-list>` and `scrollIntoView` — re-test. |
| App launching | XDG desktop entries parsed (NoDisplay/Hidden/OnlyShowIn/NotShowIn vs `XDG_CURRENT_DESKTOP`), launched with `gio launch <desktop-file>` (path as one argv, never a parsed Exec line) | `applications.ts:11-90`, README `pkgs/desktop-shell/README.md:13-16` | **Keep** | Safe pattern; tests in `controller.test.ts` ("desktop-entry visibility…"). |
| Command catalogue | 20 commands mapped to existing scripts: files→nautilus, network→`kitty nmtui`, audio→`audio-route`, accent→`theme-prompt accent`, herdr→`herdr-picker`, workspace new/restore/rename→`desktop-workspace`, screenshot screen/area/window, colorpicker, `screen-ocr-area`, `recording-toggle`, `monitors-off`, media play/prev/next, volume mute/micmute | `providers.ts:11-68` | **Keep** (rewire workspace verbs to Sway/herdr) | `desktop-workspace` is a Hyprland-era helper. `providerGaps` (`providers.ts:70-76`) lists honest gaps: Chrome tab search, tray menus, bounded file search, no unit conversion, no Vicinae clipboard import. |
| Calculator | Arithmetic with precedence, unary ops, powers, scientific notation | `providers.ts:176-226` | **Keep** | Tested in `providers.test.ts`. |
| Theme switch from launcher | `theme list` → items "Theme: <name>", activation runs `theme <name>` | `providers.ts:165-175, 227-256` | **Keep** | Uses Tom's existing `~/.local/bin/theme`. |
| Clipboard history | `cliphist list` provider; restore = `cliphist decode` (id on stdin) piped to `wl-copy` as bytes; two user units `wl-paste --type text\|image --watch cliphist store` | `providers.ts:108-131, 258-270`; units `home/hyprland.nix:56-85` | **Keep or replace** | BRIEF §3.4 says "own store"; cliphist is the proven, smaller choice (INFERRED). Clipboard/file enumeration only on explicit provider request (privacy, `providers.ts:1-4`). |
| File search | Bounded filename walk under `$HOME`, `gio open` | `providers.ts:133-163, 271-273` | **Replace** with the Pinax-like explorer (new) for browsing; keep as launcher provider | Not an index. |
| Quick controls | 560×710 overlay: volume (`volume`), brightness (`brightness`), media, audio route, screenshot, battery; **network = `kitty -- nmtui`, bluetooth = `blueman-manager`**; Hyprland animations/blur toggles via `hyprctl getoption/keyword` | `ui.tsx:782-936` | **Keep delegations; new native Wi-Fi/Bluetooth menus; drop effects toggles** | Effects toggles are Hyprland-only (`ui.tsx:202-212`). Tom asked for wifi/bluetooth menus in GPUIX (BRIEF). |
| Windows/workspaces panel | 700×580: workspace focus, move window to workspace, Hyprland groups, `desktop-workspace new/rename/detach/close(park)/restore` | `ui.tsx:937-990`, `controller.ts:95-238` | **Replace** with Sway adapter + herdr | `controller.ts` is hyprctl + `.socket2.sock`; its reconnect/epoch logic is the reusable part (§5). |
| Hyprland controller | `hyprctl -j clients/workspaces/monitors/activewindow`, event socket, 40 ms coalescing, 250 ms→10 s reconnect backoff, epoch guard so an in-flight snapshot cannot resurrect a dead connection, 2 s refresh retry, strict argv validation | `controller.ts:1-238` | **Replace** (Sway `subscribe`) — **keep the state-machine design** | 9 controller tests ([S:L284-L297]). |
| Sway capability adapter | Framework-free `createSwayCapabilities({output:'eDP-1'})`: `swaymsg -r -t get_outputs/get_workspaces`, strict JSON validation, only workspaces on the target output, explicit `focusWorkspace` with **revalidate before + verify after** (Sway has no compare-and-switch), safe name quoting, no `move`, races reported not compensated | `design/gpuix-comparison/platform.ts:1-54`, tests `platform.test.ts` (26 mocked tests, REPORTED in README:23) | **Keep, extend** with `subscribe` events | Real read-only probe on the client via `ssh client systemd-run --user --wait --pipe --collect swaymsg …` (MEASURED [M:L592-L595]: outputs eDP-1 1440×900 @0,0 and eDP-2 1440×900 @0,900; top workspaces 1,2,3,8,9,10 at that moment). |
| Notification daemon | `org.freedesktop.Notifications` via **dbus-next** under Bun: caps `actions,body`; server info `Desktop shell/Tom/0.1.0/1.2`; Notify/CloseNotification/NotificationClosed/ActionInvoked; replaces-id; urgency 0/1/2; resident/transient hints; expiry closes with reason 1, CloseNotification reason 3; refuses to replace an existing owner (`DO_NOT_QUEUE`) | `notifications-daemon.ts:1-79`, store `notifications.ts:1-83` | **Keep, port** | systemd `Type=dbus`, `BusName=org.freedesktop.Notifications` (`home/hyprland.nix:38-55`). Real D-Bus test exists but is opt-in and was **never reported run** (§3.3). |
| Notification IPC | JSON-lines Unix socket `$XDG_RUNTIME_DIR/desktop-shell/notifications.sock` (0600, uid-checked): `{"type":"subscribe"}` → snapshot stream; commands `dismiss`, `dismiss-latest`, `action`, `dnd`, `clear`; 16 KiB request cap; 4 MiB per-client backpressure drop | `notifications-daemon.ts:57-75`, client `notifications-client.ts:1-43` | **Merge into `shell.sock`** | Client times out an accepting-but-silent socket and reconnects (test 3.3 s, MEASURED [S:L804-L807]). |
| Notification centre | 500×650 overlay: active + history merged newest-first, DND toggle, clear, per-item actions, mono app/time header, urgent tinted brand | `ui.tsx:991-1160` | **Keep** (rail-attached panel per BRIEF) | — |
| Toasts | Separate `toasts` process spawned by the daemon when items>0 and DND off; anchor `top` (centre), margin top 40, width 390, height `rows*148-8`, max 4, sorted urgency desc then newest; keyboard none; surface bg = background + `e6` alpha; process **exits when visible count changes and daemon respawns it** (150 ms spawn delay, 30 ms after clean exit, 250 ms→10 s crash backoff) | `ui.tsx:1003-1007, 1162-1190, 1236-1258`, daemon `notifications-daemon.ts:18-36` | **Keep pattern until 0.11 proves resize** | This is the main workaround for "no layer resize / no input region" (§3.2 L1). BRIEF wants top-right 390 wide max 4. |
| Theme follow | Reads `~/.config/theme/desktop-shell.json` (whole palette as JSON from `home/themes/default.nix:294`), falls back to `kitty.conf` parsing, then to the built-in noir; `fs.watch` on `~/.config` for the `theme` symlink name, 50 ms debounce, revision counter, `SIGUSR1` reload | `theme.ts:111-149`, palette mapping `theme.ts:52-89` | **Keep**; rename fragment to `gpuix-shell.json` | README still says kitty.conf only (doc drift, MEASURED `README.md:33` vs `theme.ts:122`). Symlink retarget fires no event on the target files, so watching the parent dir is load-bearing. |
| HM wiring | `desktop-shell-core` (daemon, Type=dbus), `desktop-shell` (bar, Requires core), two clipboard units; all `PartOf`/`WantedBy` the session target with `ConditionEnvironment=HYPRLAND_INSTANCE_SIGNATURE`; `Slice=app.slice`, `UMask=0077` | `home/hyprland.nix:30-110` | **Replace** target/condition with `sway-physical-session.target` + `SWAYSOCK` | Flake asserts the client does **not** get these units and **does** get `themes/noir/desktop-shell.json` (`flake.nix:1233-1240`) — a precedent for gpuix-shell flake checks. |
| Native desktop proof | Solid/GPUIX `desktop.tsx`: 220 px sidebar, top-display workspace list from `platform.ts`, launcher search, notifications panel (DND/Clear all/Dismiss/Reset), calendar panel, quick controls with Range sliders, palette switcher (3), notes/terminal/browser tabs, `createWindowSize()` narrow mode (<900 px labels shrink), panel focus trap with `focusNextWithin` + focus return | `design/gpuix-comparison/desktop.tsx:1-67`, entry `main.ts:1-10` | **Reference** for React port | Rendered + automated under headless Sway at 1080×900 and 720×900 (MEASURED [P:L604], [P:L784]). Controls other than workspaces are labelled samples. |
| Native mail proof | `email.tsx` fixtures + `GPUIX_MAIL_LIVE=1` read-only connected mode via client bridge `http://127.0.0.1:4188/api/mail`, sharing `createMailReader` with the web app | `design/gpuix-comparison/email.tsx`, `design/claude-mail/src/mail-reader.ts` | **Out of shell scope** (launch only) | Proves fetch/abort/pagination from a GPUIX process; useful if the shell later hosts app panes. |
| Requirements contract | 41 IDs: DES-01..07, SH-01..10, AG-01..07, MAIL/CRM/PRJ/CAL, CF-01..06 with Existing/Reader/Prototype/Desired states | `design/claude-suite/DESKTOP-REQUIREMENTS.md:32-100` | **Keep as acceptance source** | SH-02 (rail geometry), SH-04 (Mod+i on eDP-1, "If eDP-1 is absent, fail visibly"), SH-08 (notification semantics), SH-09 (quick controls show real state), SH-10 (no blur needed). |
| Blur research patch | GPUI `ext_background_effect_v1` patch for the `remorses/zed` fork | `pkgs/desktop-shell/patches/{README.md,gpui-ext-background-effect.patch}` | **Drop** | Stopped when Tom chose Sway; never compiled (REPORTED in its README). Not produced in these four transcripts (found on disk, listed at [M:L330]). |

### 3.2 GPUIX 0.10.0 limits hit, and the workaround used

| # | Area | Limit (0.10.0) | Evidence | Workaround used | Status for the new build |
|---|---|---|---|---|---|
| L1 | Layer-shell lifecycle | **No setter to resize a layer surface, change its options after creation, or set an input region.** A transparent oversized overlay would swallow clicks on the desktop below. | Code comment `ui.tsx:1239-1241` (MEASURED); research note `gpuix_solidjs.md:49` "No output/display selector, changing layer options after creation, or surface input-region controls were found"; `index.d.ts` says namespace "Cannot be changed after the surface is created" ([S:L57] output) | Size the toast surface to `rows*148-8` at creation; the toasts process exits when the count changes and the daemon respawns it ([S:L726]) | Upstream `/home/tom/Downloads/gpuix` at `515df19`: `packages/native/index.d.ts` still has no input-region/output/resize symbol (MEASURED grep today). Plan for respawn-on-size-change, or one fixed-size surface per toast. |
| L2 | Output selection | **No output/display selector** in `WindowOptions`/`LayerShellOptions`; placement is whatever output the compositor picks for a layer surface with no output (normally the focused one). | `pkgs/desktop-shell/README.md:64-65` "GPUIX currently does not expose an output selector here; placement follows its compositor-selected output" (REPORTED); research note line 49 | None. The Mod+i top-display switcher shipped on fuzzel instead (`tests/workspace-switcher`, `home/dot_local/bin/sway-workspace-switcher`) | **Open.** Mod+i must appear on eDP-1 even when eDP-2 is focused (SH-04). INFERRED options: `swaymsg focus output eDP-1` before mapping then restore focus; or keep a persistent per-output surface and show/hide content. Must be proven in the harness with two headless outputs. |
| L3 | Event loop | On Linux GPUI runs its own `gpuix-ui` thread; `tick()` only reports whether that loop is alive. The stock JS frame loop polls every 8 ms for nothing. | `renderer.rs` excerpt read at [S:L454-L457]; runtime `DEFAULT_FRAME_MS = 8` at [S:L413-L416] (MEASURED) | `createRenderer(); native.init(options); render(..., {renderer: native}); setInterval(() => { if (!native.tick()) close() }, 500)` (`ui.tsx:1331-1337`, `gpuix-comparison/main.ts:8-10`) | Re-check with `@gpuix/react` 0.11: whether `render()` starts the 8 ms loop and whether injecting the renderer is still supported. |
| L4 | Bundling (Solid) | Externalising `solid-js` in `Bun.build` silently loads Node's **server** build → no reactivity. | `build.ts:2-3` comment; bun-plugin `onLoad` filter for `solid-js/dist/server.js` (MEASURED [S:L674]) | Bundle solid-js with `@gpuix/solid/bun-plugin` | Solid-specific; React has no such conditional export (INFERRED). |
| L5 | Bundling (Bun 1.3) | Externalising `@gpuix/native` as a prefix also externalised `@gpuix/native/host`; Bun 1.3 lost the namespace binding of `export * from "@gpuix/native/host"` when `@gpuix/solid` loaded via dynamic import → "undefined host" at runtime. | `build.ts:13-15` comment; [S:L688-L696] (REPORTED cause; the failing run's text was in an encrypted message) | `onResolve({filter: /^@gpuix\/native$/}, …external)` — externalise **only the exact binary loader**; keep `dbus-next` external | **Carry forward** for `@gpuix/react` with Bun 1.4.2 until proven unnecessary (INFERRED). |
| L6 | Windows per process | `@gpuix/solid` `render()` keeps one global render slot; later calls remount. No multi-window shell manager. | Research note `gpuix_solidjs.md:41` (REPORTED from source) | One process per surface; daemon spawns toasts | Matches BRIEF §3.2. Memory cost per process is real (L14). |
| L7 | Fonts | No `registerFont` in 0.10.0; families come from fontconfig. `fonts.mono = "Anthropic Mono"` is not the installed family: `fc-match 'Anthropic Mono'` → `AnthropicMono Nerd Font` (fontconfig fallback). | MEASURED [S:L550-L553]; client `fc-match "Anthropic Sans"` → `AnthropicSans-Roman.ttf`, Serif likewise ([P:L615-L618]) | Used the family names as-is; not checked whether GPUI's own font lookup follows the fontconfig alias | Use exact families **"Anthropic Sans"**, **"Anthropic Serif"**, **"AnthropicMono Nerd Font"** (BRIEF). 0.11 adds `registerFont(bytes)` (upstream `index.d.ts:178,386`), but fonts must never enter git. |
| L8 | Keyboard | Key names are lowercase strings (`tab`, `escape`, `enter`, `space`, `up`, `down`); `EventModifiers` is `{shift, ctrl, alt, cmd}` — code written with `control`/`platform` silently never matched. Window-level `onKeyDown(event, renderer)` returns `true` to consume; Tab is **not** automatic — call `renderer.focusNext/focusPrevious`. `getFocusedElementId()` returns `number \| null`. `<input>` needs `autoFocus` to take focus at mount. | [C:L452-L464] (modifiers fix), `index.d.ts:468-473` shown at [C:L455]; [S:L389] (tab); host.d.ts `autoFocus` "Required for `<input>`" ([S:L394]); TS error at [C:L509] | Explicit Tab handling in every root `onKeyDown`; panel focus trap with `focusNextWithin(panelId)` and focus restore to the opener ([C:L485]) | Same API family exists in React 0.11 (CHANGELOG line 209). |
| L9 | Style subset | `StyleDesc` has no per-side border colour (`borderLeftColor`), numeric `gridTemplateColumns` only, `hover:{…}` style object instead of `:hover`, `whiteSpace`/`textOverflow` for ellipsis, `overflowY:'scroll'`, `position:'absolute'`. | [M:L406] fix; style list at [C:L420] | Selection bar = absolutely positioned 3 px `div` inside a `position:'relative'` row | Design tokens must be expressed as numbers; hairlines = `borderWidth:1` + `borderColor`. |
| L10 | Text nodes | Mixing JSX expressions and literal text inside one `<text>` (e.g. `{n}%`, `{a} · {b}`) produced separate runs that wrapped/laid out badly. | [C:L742] fix, reported as "text wrapping corrected" [C:L934] (REPORTED) | Always pass one template-literal string: ``{`${p.value}%`}`` | INFERRED to apply to React too (separate text children). |
| L11 | SVG icons | `<svg source="…">` renders raw markup, but icon colour must be given explicitly (`style.color`) or icons render untinted. | [C:L595] fix ("Icon tint … corrected" [C:L934]) | `color: t().ink` on the svg style; Primer octicon 16 px path data extracted from `@primer/octicons-react/dist/icons/*.mjs` into a name→path map ([M:L623-L630]) | Reuse the extraction for Anthropicons or octicons. |
| L12 | Colour alpha | 8-digit hex (`#RRGGBBAA`, e.g. `background + "e6"`, `border + "55"`, `#00000000`) used for translucent toasts/hover/quiet buttons. | `ui.tsx:1019,1180,1203`; `theme.ts:87` | — | Accepted by typecheck; **toasts never rendered**, so the paint is UNVERIFIED. BRIEF says flat and opaque anyway. |
| L13 | Screenshots / test renderer | Linux GPU screenshot/test support disabled upstream in 0.10.0 (pending image readback); SDK screenshot is macOS/Windows. | Research note line 40; `pkgs/desktop-shell/README.md:65-66`; gpuix-comparison README:21 | Compositor screenshots: `grim -o HEADLESS-1` inside the isolated Sway | Keep grim. |
| L14 | Automation | `@gpuix/native/automation` `launch({command,args,env})` → `getByTestId`, `getByType('input')`, `getByText`, `fill`, `click`, `press('escape')`, `call('getAllText')`, `call('getTree')`. **`getTree` nodes carry no style values** (`style` was `None` for every node). `getByText` on a composite label failed. Automation is switched on by `createNativeRenderer` whenever `process.stdin` is **not a TTY**. | [P:L587-L604] (getByText failure → getByType/getAllText), [P:L833-L848] (style None), runtime.js at [S:L413-L416] | Pixel probe of the grim capture (`(32,32,31)` = claude-dark `#20201F`) to prove the palette painted ([P:L859-L869]); `testId` props on every actionable element | INFERRED risk: under systemd, stdin is `/dev/null` (not a TTY), so the stdio automation server is enabled in production too — check and disable in 0.11. |
| L15 | Wayland client noise | GPUI logged `Failed turn Url { … 127.0.0.1:4188/?live=1#shell } into a file path` and `relative URL without a base` from `gpui_linux::linux::wayland::client` on the live client. | Client journal, MEASURED [P:L1055-L1058]; README:31 | Left in the journal, not suppressed | Origin unknown (drag/drop or activation URI, INFERRED). URL/drop handling never validated. |
| L16 | Memory | A single native Mail window on the client: **"Consumed 4.619s CPU time over 3min 11.468s wall clock time, 869.4M memory peak."** | systemd journal, MEASURED [P:L1058] | — | cgroup peak includes page cache and the Bun runtime (INFERRED), but seven always-on processes could cost GBs. Measure RSS per surface early; prefer few resident processes (rail + daemon) and short-lived popups. |
| L17 | D-Bus | GPUIX has no D-Bus. dbus-next 0.10.2 under Bun was used for the notification server; no Unix-FD negotiation. | `notifications-daemon.ts:10`, `package.json` | — | The only real-bus test is opt-in and not reported run (§3.3). UPower/NM/BlueZ/MPRIS clients are untried under Bun. |
| L18 | Nix packaging | Published `.node` links `libxkbcommon.so.0` (unresolved on NixOS) and needs `libgcc`; nixpkgs on that date had removed `nodePackages` and renamed `xorg.libX11/libxcb` → `libx11/libxcb` (warnings). | `ldd` at [P:L452-L459] (MEASURED "libxkbcommon.so.0 => not found"); [S:L405-L409]; warnings at [S:L271] | `autoPatchelfHook` + `buildInputs=[stdenv.cc.cc.lib libxkbcommon]`; wrapper `LD_LIBRARY_PATH` of libxkbcommon, wayland, vulkan-loader, fontconfig, freetype, libGL, libX11, libxcb, openssl; `prettier` from top-level | `pkgs/desktop-shell/default.nix:1-47` is the template; swap `hyprland` for `sway` in PATH and use non-deprecated names. |
| L19 | Typecheck outside the package | A `.tsx` outside `pkgs/desktop-shell` failed with TS2875 "requires the module path '@gpuix/solid/jsx-runtime'". `createComponent(Email,{})` typed `HostElement\|HostText\|HostRoot` vs `JSX.Element` mismatch. | [M:L451], [C:L509], [P:L498] | `paths` mapping in a temporary tsconfig; later a `node_modules` symlink to the package's; call `Email()` directly instead of `createComponent` | One package root with its own `node_modules` avoids this. |

### 3.3 Test harness decisions

1. **Two tiers, exactly as BRIEF §4 now requires.** Pure `bun test` (no compositor) inside the Nix build (`default.nix:17-23`, `doCheck`, "no compositor, socket or service is launched"), and a compositor smoke that runs only under `runtime-test --render-node`. Results: 9 controller tests (REPORTED [S:L503]; first 5 seen passing at [S:L288]); 30 pass + 1 skip ([S:L736]); notifications 11→12 incl. replacement ordering and opaque action keys ([S:L797-L800]); client reconnect test ([S:L807]); `platform.test.ts` 26 mocked (REPORTED README:23).
2. **Native smoke = private stock Sway, headless** (`design/gpuix-comparison/smoke-native.py:1-56`): `sway --unsupported-gpu -c <tmp>/sway.conf` with `output HEADLESS-1 mode {W}x900 bg #F9F9F7 solid_color`, `xwayland disable`, `seat seat0 fallback true`, `default_border none`; env `WLR_BACKENDS=headless WLR_HEADLESS_OUTPUTS=1 WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1 SWAY_DISABLE_SD_NOTIFY=1 XDG_CURRENT_DESKTOP=sway`, D-Bus addresses pointed at non-existent sockets, `VK_ICD_FILENAMES=/run/opengl-driver/share/vulkan/icd.d/radeon_icd.x86_64.json`; wait for `sway-ipc*.sock` and `wayland-*` in the private runtime dir; assert **no** `$XDG_RUNTIME_DIR/bus` and **no** `/dev/input`; detect mapping via `swaymsg -r -t get_tree` app_id; `grim -o HEADLESS-1`; then a Bun automation script; `TEST_WIDTH=720` for narrow. Compositor renders with pixman while the GPUIX client renders with Vulkan on `renderD128` — this combination worked (MEASURED [P:L556-L559]).
3. **`runtime-test` version matters.** The live `~/.local/bin/runtime-test` rejected `--render-node` (`bwrap: execvp --render-node: No such file or directory`, MEASURED [P:L552]); the worktree copy `/home/tom/.wt/hyprland-solid-shell/home/dot_local/bin/runtime-test` supports it ("--render-node exposes one validated DRM render node … never exposes a modesetting/card or input device", [P:L969-L972]). BRIEF already says copy it.
4. **Layer-shell was never exercised.** The proof deliberately opened ordinary toplevels ("No layer-shell request", README:11). `pkgs/desktop-shell`'s layer surfaces were only typechecked and `--check-native`-loaded. **First job for the new harness: map a layer surface (rail with exclusive zone, overlay launcher with exclusive keyboard) on headless Sway and read it back with `swaymsg -t get_outputs`/layer-shell listing or grim** (INFERRED plan).
5. **Assertions that survived:** app_id/title/rect from the Sway tree; automation clicks/fill/Escape; `getAllText` contents; a post-paint pixel at (5,5). Automation tree has bounds but no styles, so colour/theme checks need pixels.
6. **D-Bus integration test is opt-in:** `DESKTOP_SHELL_DBUS_TEST=1` inside `runtime-test` + private `dbus-run-session` (`notifications-integration.test.ts:7-9`). No run with it set appears in these transcripts (UNVERIFIED end-to-end D-Bus).
7. **Live-mode test without live data:** `smoke-live.py` + `mock-mail-preload.ts` uses `bun --preload` to replace `globalThis.fetch`, refuses anything but mocked GETs, logs every request (13 requests, all mocked GET; MEASURED [P:L1024-L1026]). Good pattern for herdr/NM/BlueZ adapters: inject a runner, never touch the real service in tests.
8. **Packaging for a client without a checkout:** `package-native.py` copies `dist/` plus the already-patched `.node` from a built store path, writes `bundle/run` with an absolute `LD_LIBRARY_PATH` and Bun 1.4.2, lists 11 Nix closure roots for `nix copy --to ssh-ng://client`; bundle 69 MB (MEASURED [P:L727]). `shutil.copytree` from the read-only store failed until `copy_function=shutil.copyfile` + chmod ([P:L676-L685]).

### 3.4 What failed (chronological)

| When | What | Pointer | Resolution |
|---|---|---|---|
| 23:54 | `cat > pkgs/desktop-shell/package.json` with `workdir` already inside the package → "No such file or directory" | [S:L209] | re-run with relative paths |
| 23:54 | `file` command not on PATH | [S:L199] | used `readelf`/`ldd` |
| 23:58 | Bun test: `.map(JSON.stringify)` passes the index as `replacer` | [S:L288-L301] | `.map(v => JSON.stringify(v))` |
| 23:59 | Bundle with `solid-js` external → non-reactive server build | [S:L332-L336] | bundle solid (L4) |
| 00:01 | `nix-build -A nodePackages.prettier` → "nodePackages has been removed" | [S:L405-L409] | `-A prettier` |
| 00:23 | Bun 1.3 "undefined host" | [S:L688-L696] | exact-match external (L5) |
| 01:15 | `exec_command` "Failed to create unified exec process: No such file or directory" (workdir not yet created) | [P:L292] | mkdir first |
| 01:21 | TS2875 / createComponent typing | [M:L451], [P:L498] | L19 |
| 01:21 | `e.modifiers?.control`/`platform` never true | [C:L464] | `ctrl`/`cmd` (L8) |
| 01:23 | `runtime-test --render-node` unknown to live wrapper | [P:L552] | worktree wrapper |
| 01:24 | `getByText('All mailboxes ⌄')` not found in native tree | [P:L594-L604] | `getByType('input').fill` + `getAllText` |
| 01:26 | `copytree` of read-only store files | [P:L676] | copyfile + chmod |
| 01:31 | `sha256sum …/gpuix.node` — wrong filename (it is `gpuix-native.linux-x64-gnu.node`) | [P:L779-L784] | corrected |
| 01:32 | automation tree has no style → cannot assert theme | [P:L848] | pixel assertion |
| 01:35 | GPUI Wayland URL→file-path errors on the client | [P:L1058] | logged only |
| 01:36 | live-mode error text mismatch in automation | [P:L1003-L1012] | aligned to UI copy |

Not failures but stops: [S] "Stopped feature expansion as instructed" at 00:04 ([S:L503]); blur patch abandoned at Sway decision (patch README).

### 3.5 Process lessons for tonight

- **These workers acted on the live client session.** [P] launched `gpuix-comparison-{mail,desktop}-20261014.service` via `systemd-run --user` on the Zenbook, read `SWAYSOCK`/`WAYLAND_DISPLAY` from `systemctl --user show-environment`, moved them onto visible workspace 6 of eDP-1 at 720×880, grim-captured only that geometry, restored focus, and later **replaced** the mail unit ([P:L924-L1058]). Tonight's BRIEF forbids touching live Sway; the read-only probe pattern ([M:L592]) is the most that is allowed, and only if a task explicitly needs it.
- **Doc drift appeared within hours** (README "kitty.conf" vs code reading `desktop-shell.json`; "nine controller tests" vs 30). Write the README last or generate its facts from tests.
- **Honest gap lists worked**: `providerGaps`, README "Known boundaries", DESKTOP-REQUIREMENTS state codes. Keep that style.

---

## 4. Design values

### 4.1 Rail geometry (Tom 00:34:24; `DESKTOP-REQUIREMENTS.md:49` SH-02; `design/claude-rail/PROPORTIONS.md:3-18`)

Logical px at 100 %: **rail 220**; **12** side/top inset; row **196 × 30**; **2** gap; **8** corner radius; content inset **8** horizontal / **6** vertical; **16** icon slot; **4** child spacing. Source: Tom's C++ Views port (`/home/tom/mecattaf/views-shell/shell/tabs/layout_constants.cc:38`, `SPEC.md:114`, cited by PROPORTIONS.md). Multiline agent rows may be taller as a distinct row type. Same numbers as herdr-web-ui "220/30/12/2/8" (BRIEF). BRIEF adds a 56 px collapsed state, not in these transcripts.

### 4.2 `pkgs/desktop-shell` (Hyprland build, Claude/Primer restyle, 00:16–00:25)

| Element | Value | Where |
|---|---|---|
| Body text | Anthropic Sans **13**, colour fg / muted | `ui.tsx:306-310` |
| Mono text | "Anthropic Mono" **11**, muted | `ui.tsx:317-321` (family name wrong, L7) |
| Button | height **32** (small **26**), radius **6**, hover = theme.hover, primary = brand | `ui.tsx:322-384` |
| Tab | height **34**, 2 px underline in fg when selected, marginRight **18**, weight 600 selected / 400 | `ui.tsx:385-415` |
| Section | gap **10**, padding **14/16**, bottom hairline 1 px border | `ui.tsx:416-442` |
| Launcher input | fontSize **15**, height **42**, padding **10**, radius **6** | `ui.tsx:620-636` |
| Launcher row | height **48**, radius **4**, gap **12**, selection marker **3 × 22** radius 1 | `ui.tsx:685-705` |
| Popup container | padding **16**, gap **12**, radius **8**, bg = background + `e6` | `ui.tsx:1198-1210` |
| Popup title | **17** / 600 | `ui.tsx:1212` |
| Toast | padding **10**, gap **6**, height **140** (+8 gap → 148 pitch), radius **8**, bg + `e6`, 1 px border | `ui.tsx:1008-1030` |
| Surfaces | bar 1×**32** (stretched), launcher **700×580**, controls **560×710**, notifications **500×650**, toasts **390 × (n·148−8)**; popup margin `[40,12,0,0]`, toast margin `[40,0,0,0]` | `ui.tsx:1259-1302` |

### 4.3 `design/gpuix-comparison/desktop.tsx` (native Sway proof)

Text 13 default, 12/11 muted secondary sizes; sidebar width **220**, padding **12**, header row **38**; side rows height **30** quiet buttons; buttons radius **8**, height 30, padding-x 8, 1 px border, focused border = accent; app rows padding 12 radius 6; section labels 11 muted with paddingTop 22; ranges padding 18 with bottom hairline; documents/notes heading **Anthropic Serif 26**; terminal sample **Anthropic Mono 13 / lineHeight 24**; panels padding 28–32; narrow breakpoint **< 900 px** (`desktop.tsx:20-60`, counts by grep today).

### 4.4 Palettes (from `design/claude-primer/src/palettes.json` → `theme.ts:52-89`; values MEASURED by `parsePalette` run at [S:L747-L750])

| Role | noir | claude-dark | claude-light |
|---|---|---|---|
| background (`ground.desktop`, light uses `ground.base`) | `#000000` | `#20201F` | `#F9F9F7` |
| surface (`ground.raised`) | `#000000` | `#20201F` | `#FFFFFF` |
| foreground | `#EAECF0` | `#EAECF0` | `#131313` |
| secondary (`fgDim`) | `#D3D7DE` | `#D3D7DE` | — |
| muted (`comment`; light uses `fgDim`) | `#818898` | `#818898` | — |
| border (`border.inactive`) | `#373735` | `#373735` (active `#555451`) | — |
| selection bg | `#264F78` | — | — |
| error (`red`) / accent / brand | `#F47B85` / `#70B8FF` / `#D97757` | same | — |
| primary / primary text | `#D97757` / `#131313` | same | **`#A74B2F` / `#FFFFFF`** (contrast fix) |
| hover | border + `55` | `ground.dim` (`#151515`) | `ground.dim` |

claude-dark also: `ground.base #1A1A1A`, `ground.dim #151515`, green `#9BE963`, cyan `#5EEDED`, magenta `#CC7BF4`, orange `#FBAD60` ([C:L389]). Calendar study hues (dark/light): rose `#452D38`/`#F0D9E3`, mint `#263C34`/`#BCD1CA`, violet `#363445`/`#CBCADB`, blue `#293847`/`#D9E4F0`; inks `#E4ABC3`/`#773452`, `#B8D5C9`/`#284F42`, `#CBC5E9`/`#4C456C`, `#B1CEE8`/`#355C82` ([S:L516]). Dashes = not visible in what I read; take from `home/themes/claude-light.nix`.

### 4.5 Timings and bounds

Event coalescing 40 ms; reconnect 250 ms ×2 → 10 s; refresh retry 2 s; status poll 15 s; tick 500 ms; theme reload debounce 50 ms; toast spawn 150 ms, respawn 30 ms after clean exit, crash backoff 250 ms → 10 s; toast first-snapshot timeout 3 s; singleton contact timeout 1 s, fresh-socket grace 2 s; execFile timeouts 5 s (controller) / 4 s (Sway adapter); notification caps: ≤32 action entries, key ≤256 (over-long keys dropped, never truncated), label ≤256, app ≤256, summary ≤1024, body ≤8192; IPC request ≤16 KiB; client backlog ≤4 MiB; Hyprland event buffer ≤1 MiB (`controller.ts`, `notifications*.ts`, `ui.tsx` lines cited in §3.1).

---

## 5. Reusable code and data (exact paths)

Absolute root `R=/home/tom/.wt/hyprland-solid-shell`.

| What | Path | Why reuse |
|---|---|---|
| Nix package template | `R/pkgs/desktop-shell/default.nix:1-47` | buildNpmPackage + autoPatchelf + wrapper LD_LIBRARY_PATH + `doCheck` bun test. Replace `hyprland` with `sway`, `xorg.*` with new names. |
| Bun build with native boundary | `R/pkgs/desktop-shell/build.ts:1-28`; minimal form `R/design/gpuix-comparison/build.ts:1-2` | exact-match `@gpuix/native` external (L5). |
| Entry with refusal of WASI fallback | `R/design/gpuix-comparison/main.ts:2,6` | `if (__napiBindingTarget !== 'native') throw` — keep in gpuix-shell. |
| Renderer bootstrap + 500 ms tick | `R/pkgs/desktop-shell/ui.tsx:1331-1337` | L3. |
| Layer-shell options per surface | `R/pkgs/desktop-shell/ui.tsx:1259-1302` | shape of `layerShell` objects. |
| Root key handling (Tab/Escape/arrows) | `R/pkgs/desktop-shell/ui.tsx:1303-1330`; `R/design/gpuix-comparison/main.ts:7` | L8. |
| Panel focus trap + focus return | `R/design/gpuix-comparison/desktop.tsx` (search `focusNextWithin`, `closePanel`) | DES-03 requirement. |
| Sway adapter | `R/design/gpuix-comparison/platform.ts:1-54` + `platform.test.ts` | output-filtered workspaces, revalidate/verify focus, quoting rules. |
| Herdr/Sway quoting precedent | `R/home/dot_local/bin/sway-workspace-switcher`, `R/home/dot_local/bin/herdr-picker` (`quote_sway`) | read by [M:L506]; Mod+i semantics. |
| Reconnect/epoch controller pattern | `R/pkgs/desktop-shell/controller.ts:95-215` | port to Sway `subscribe` stream. |
| Notification store + daemon + client | `R/pkgs/desktop-shell/notifications.ts`, `notifications-daemon.ts`, `notifications-client.ts`, tests `notifications*.test.ts` | spec-correct behaviour already tested. |
| Launcher providers + calculator + clipboard + files | `R/pkgs/desktop-shell/providers.ts`, `applications.ts`, tests `providers.test.ts`, `controller.test.ts` | pure logic, framework-free. |
| Theme follower | `R/pkgs/desktop-shell/theme.ts:52-149`; fragment renderer `R/home/themes/default.nix:294` (`"desktop-shell.json" = builtins.toJSON t;`) | rename to `gpuix-shell.json`. |
| HM unit precedent | `R/home/hyprland.nix:30-110` | Type=dbus daemon, Requires, clipboard watchers. |
| Flake assertions precedent | `R/flake.nix:1233-1240` | assert services absent/present per host. |
| Headless Sway smoke | `R/design/gpuix-comparison/smoke-native.py:1-56` | copy into `tests/gpuix-shell/`. |
| Native automation script | `R/design/gpuix-comparison/automation-native.ts` | launch/getByTestId/fill/getAllText/getTree. |
| Mocked live-mode test | `R/design/gpuix-comparison/smoke-live.py`, `mock-mail-preload.ts`, `automation-live.ts` | `bun --preload` fetch interception. |
| Client packaging without checkout | `R/design/gpuix-comparison/package-native.py` | only if a pre-merge preview is ever wanted; not for tonight (no deploy). |
| Two-output headless Sway precedent | `R/tests/workspace-switcher/smoke.py`, `README.md` | the place to prove eDP-1 pinning (L2). |
| `runtime-test` with `--render-node` | `R/home/dot_local/bin/runtime-test` | BRIEF: copy into the branch. |
| Requirements contract | `R/design/claude-suite/DESKTOP-REQUIREMENTS.md`, `REQUIREMENTS.md`, `COMPONENT-COVERAGE.md` | acceptance IDs. |
| Rail proportions + web mock | `R/design/claude-rail/PROPORTIONS.md`, `R/design/claude-rail/src/` | exact geometry with source citations. |
| Palettes JSON | `R/design/claude-primer/src/palettes.json` (also copied in claude-shell-study, claude-mail, claude-portability) | Same roles as `home/themes/*.nix`; prefer the Nix fragment at runtime. |
| Octicon path extraction | [M:L630] script; output in `R/design/gpuix-comparison/email.tsx` icon map | SVG icon source for native. |
| GPUIX research note | `/home/tom/mecattaf/dotfiles/research_notes/From Aura to Hyprland/gpuix_solidjs.md:33-51` | API limits list (read-only; do not edit). |
| Built native addon 0.10.0 | `/nix/store/pwp11p3rnmwygrykblk3rr3331mw4k4h-desktop-shell-0.1.0/lib/desktop-shell/node_modules/@gpuix/native-linux-x64-gnu/gpuix-native.linux-x64-gnu.node` (sha256 `8fd95415…857fd`, MEASURED [P:L807]) | only for comparison; tonight pins 0.11.0. |

Carry-forward rules distilled for gpuix-shell builders (INFERRED from the above):

1. Exact-match external for `@gpuix/native`; keep pure-JS subpaths bundled.
2. Own the renderer: create, `init(options)`, render with it, poll `tick()` slowly; confirm with `@gpuix/react` 0.11 before relying on it.
3. Handle Tab, Escape and Enter yourself at the root; lowercase key names; modifiers `{shift,ctrl,alt,cmd}`.
4. One template string per `<text>`; explicit `color` on every `<svg>`; numeric styles only; no per-side border colours.
5. Size layer surfaces at creation; anything that must change size is a respawn.
6. Never trust "it typechecked": every surface needs the headless-Sway smoke with a grim pixel or `getAllText` assertion, and a **layer-shell** case, which nobody ran on 10-14.
7. Fonts by exact installed family; measure fallback with `fc-match` in the test.
8. Measure memory per surface process before committing to seven daemons.

---

## 6. Gaps and unknowns

- **Layer-shell never rendered** (rail exclusive zone, overlay keyboard exclusivity, anchor/margin behaviour on Sway 1.12) — UNVERIFIED. Highest-priority harness case.
- **Output pinning (eDP-1)** — no GPUIX API in 0.10.0 or upstream `515df19` (grep); workaround untested. Conflicts with SH-04 "fail visibly rather than choose another output".
- **Resize/input region** — none; toast respawn pattern only typechecked.
- **Real D-Bus** — `org.freedesktop.Notifications` under Bun/dbus-next never exercised on a bus in these transcripts; UPower/NetworkManager/BlueZ/MPRIS/logind clients not attempted.
- **Wi-Fi and Bluetooth** — only delegated to `kitty nmtui` and `blueman-manager`; no native menus exist.
- **Tray (StatusNotifierItem)** — [S] fetched the freedesktop SNI/Watcher specs ([S:L777]) and reported "Native tray support remains incomplete" ([S:L829]); nothing built.
- **Herdr status in the shell** — not wired in these builds (the fuzzel switcher samples it on open); continuous updates Desired (AG-03).
- **IME, screen reader, clipboard inside GPUIX inputs, fractional scale, hotplug, sleep/resume** — none validated (README:33, research note:46-50).
- **Automation channel in production** — enabled when stdin is not a TTY (L14); whether systemd-launched surfaces expose it is UNVERIFIED.
- **GPUI URL errors** (L15) — origin unknown.
- **Memory** — one 869.4 M peak measurement only; no per-surface RSS.
- **React path** — everything here is Solid. `@gpuix/react` 0.11.0 build/runtime differences (frame loop, renderer injection, bundling) are untested by these sources.
- **Encrypted payloads** — every root→worker task text and inter-worker message is encrypted; "as instructed" stops and the exact asks are INFERRED from tool calls.
- **Not read by me**: the root session `01a1370e-…` (other readers cover it), screenshots under `/tmp/gpuix-native-*` (images viewed by the agents, not by me; those tmp dirs may be gone), `design/claude-suite/COMPONENT-COVERAGE.md` contents, the sibling agents `/root/hyprland_architecture` and `/root/later_transitions`.
- **Palette cells marked "—"** in §4.4 were not visible in what I read; take them from `home/themes/*.nix` on the branch.
- **Light pass**: nothing in this note was re-run by me except reading files and two greps (upstream `index.d.ts`, on-disk sources). Every MEASURED item is measured in the transcript or on disk, not re-executed tonight.
