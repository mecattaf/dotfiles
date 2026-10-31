# gpuix-shell — closure synthesis of the overnight build (2026-10-20 → 21)

Written 2026-10-21 afternoon as the final "plan" step of the closure workflow Tom asked for. Audience:
Tom, reading once. Every number below is traceable to a file on the branch or to the runner log; where
a value is my own inference it is marked **INFERRED**. Sources: `BRIEF.md`, `NIGHT-LOG.md`, the five
syntheses (`SCOPE`, `DESIGN`, `ARCHITECTURE`, `KEYS`, `BOUNDARY`), `PLAN.md` + `PLAN.json`,
`ASSUMPTIONS.md`, `MUSIC.md` + `music/*`, the 32 wave-1 notes, the rail-probe evidence, the runner
scripts and `runner.log` under `/tmp/claude-1000/-home-tom-tuesday-oct20/94d008d7-4112-4bf7-92cd-2de4eab69681/scratchpad/runner/`,
and three closure digests (A: scope/keys/design; B: architecture/plan/boundary; C: night/assumptions/music).
All paths relative to the worktree `/home/tom/.wt/dotfiles/gpuix-shell` unless absolute. Times are CEST;
the runner log is UTC (+2 h) and is the authority where NIGHT-LOG's hand-written times disagree.

---

## 1. What happened and where things stand

Tom ordered the shell at ~22:50 and ~23:05 on 10-20 (BRIEF §1): a GPUIX + OpenUI desktop shell on Sway,
in `~/dotfiles` on an experimental branch, replacing waybar, mako and Vicinae, noir plus the two Claude
themes, the Anthropic fonts, the Tacit look, with a Navidrome music demo and a full Vicinae
reimplementation added at ~23:20 (BRIEF §5). He went offline at 23:25 and asked for no questions.

**Wave 1 and the planning completed.** The orchestrator (cc seat) created the worktree, wrote BRIEF.md,
gave `runtime-test` a `--render-node` flag (+25/−6 lines) and measured the rail probe at 23:10: the
published `@gpuix/native` 0.11.0 binary opens a 56 px layer-shell rail on an isolated headless Sway 1.12
and Sway reports workspace rect x=56 width=1384 on 1440×900 (`evidence/rail-probe/`). 26 readers on
the cc seat wrote notes 01–26 (23 of them by 23:22; the cc2 runner re-ran 21, 24 and 26, all rc=0 by
23:48). Wave 1b on cc2 wrote notes 27–30, 35, 36 (six jobs, all rc=0, chain complete 23:31). 32 notes,
2,281,785 bytes, exist under `wave1/`. The five syntheses (SCOPE, DESIGN, ARCHITECTURE, KEYS, BOUNDARY)
and the 47-packet PLAN were written by the daytime workflow on 10-21 between 12:31 and 13:11, after
seven notes (15, 18, 19, 21, 23, 24, 26) were revised 12:08–12:18. ASSUMPTIONS.md holds 196 lines.

**The build waves 2–4 never executed.** The cc2 seat hit its 5-hour session limit at 23:57:08 CEST
(`runner.log` 21:57:08Z, first `rc=1 bytes=62`). From that second on every headless `claude -p` job
returned the same 62-byte reply, "You've hit your session limit · resets 4:10am (Europe/Paris)", in
2–3 s: the five overnight synthesis jobs (which had run 9–15 minutes), the seven music builders, the
music completer, the planner (twice), the wave-3 integrator, the ten completion packets, the
completeness critic, the wave-4 final integrator and the deliverer. The cc seat was at 97 % of its
weekly window at 23:16Z and could not take over until 09:59Z on 10-21 (NIGHT-LOG handoff). Because
the planner died, `PLAN.json` did not exist, `gen-wave2.py` raised `FileNotFoundError`, wave 2 ran
"0 packets", and `night.sh`, which checks no return codes, logged "NIGHT COMPLETE" at 00:03:41 with
zero work done after 23:57. `checkpoint.sh` saw that line and stopped.

**The music lane produced a full spec and compiled contracts but no player.** Five all-Opus researchers
(rc=0, 23:18–23:36) measured Navidrome 0.63.2 and mpv 0.41 from the strix; the design pass wrote
MUSIC.md (102,515 bytes, 1,378 lines) and froze nine TypeScript contract files under
`pkgs/gpuix-shell/src/` that typecheck under `--strict` and pass 5 unit tests (re-measured today:
`bun x tsc --noEmit -p .` rc=0 in 0.54 s; `bun test src/music/format.test.ts` 5 pass, 0 fail,
24 expect calls). The seven builders M1–M7 died at 23:57:17–18, 2–3 s after launch. No Navidrome call,
mpv run or compositor test happened after the research phase. `music/BUILD-LOG.md` has only the M0
section; MUSIC.md:4 still reads "Build: **not started**".

**Nothing was committed, pushed or PR'd.** `git status` shows 96 staged paths (`A` plus
`M home/dot_local/bin/runtime-test`); `git log main..HEAD` is empty (HEAD = dadb1426); `git ls-remote
--heads origin experimental/gpuix-shell` returns nothing. Both 20-minute checkpoint commits (23:37,
23:57) aborted with "secret pattern staged": the grep `NAVIDROME_PASSWORD=[^ ]` matches four staged
lines, two in MUSIC.md (prose naming the credential file's keys) and two in the read-only probe
`music/probe/subsonic-get` (a comment and `sed -n 's/^NAVIDROME_PASSWORD=//p'`). None is a credential.

**Where things stand.** The branch holds research and specification, not a shell: no `src/main.ts`,
no `default.nix`, no `home/gpuix-shell.nix`, no `tests/gpuix-shell/`, no MORNING.md, REPORT.md,
GAPS.json, INTEGRATION.md or STATUS.md. The specification is complete enough to build from: 171
feature rows with ids and acceptance (69 P0), pixel geometry for every surface, a process model and
wire protocol, a bind-by-bind rewire of the 108 `bindsym` lines, a boundary ruling with 47 of Tom's
own quotes, and 47 build packets with disjoint file ownership. The runner that would execute them is
intact and, with three mechanical fixes (§6.4), can be relaunched on the cc2 seat, which was at 8 %
weekly at 11:30Z. The decisions that need Tom's word before or during that run are in §7.

---

## 2. What exists on the branch

Sizes measured today with `wc -c` / `wc -l`; status is my reading of the file's own preamble.

| File | Size | What it is | Status |
|---|---|---|---|
| `docs/gpuix-shell/BRIEF.md` | 19,258 B / 183 l | The order verbatim, standing rulings, path map, 10 architecture decisions, 23:20 addendum, measured toolchain facts | final (23:10) |
| `docs/gpuix-shell/NIGHT-LOG.md` | 5,956 B / 48 l | Orchestrator log, night.sh progress lines, handoff, morning reading | final (13:32) |
| `docs/gpuix-shell/ASSUMPTIONS.md` | 43,358 B / 196 l | Append-only: A1–A3, 46 `music:`, 17 `BOUNDARY:`, 32 `SCOPE:`, 21 `KEYS.md:`, 40 `DESIGN.md:` (A-01…A-40), 35 `ARCHITECTURE:` | open for Tom's rulings |
| `docs/gpuix-shell/SCOPE.md` | 83,419 B / 635 l | 171 feature rows `S-001`…`S-202`, trigger / replaces / priority / acceptance, out-list §21, bind rewire §22, unverified §23 | revision 2 (12:32) |
| `docs/gpuix-shell/DESIGN.md` | 104,236 B / 1,282 l | 19 rules, colour ladders per theme, type ladder, space, motion, pixel geometry per surface, what is not drawn, A-01…A-40 | revision 2 (12:33) |
| `docs/gpuix-shell/ARCHITECTURE.md` | 140,048 B / 2,214 l | Process model, NDJSON JSON-RPC on `shell.sock`, package layering + import fence, data flows, units, Nix recipe, tests; §22 departures, §23 unverified | revision 2 (12:49) |
| `docs/gpuix-shell/KEYS.md` | 67,433 B / 700 l | Every one of the 108 `bindsym` lines mapped; new binds; launcher grammar; surface keymaps; CLI verbs; retirements; 21 INFERRED rows | revision 2 (12:32) |
| `docs/gpuix-shell/BOUNDARY.md` | 67,685 B / 450 l | Personal shell vs shared utilities vs the three heads; one-line test; 47 rulings R1–R47; 62 component rows; extraction list F1–F16 | revision 2 (12:31) |
| `docs/gpuix-shell/PLAN.md` | 173,977 B / 953 l | Standing rules, stages, seam contract §4, ownership table §5, 47 packets §6 with acceptance, §7 unverified | final (13:11) |
| `docs/gpuix-shell/PLAN.json` | 158,828 B / 930 l | The same 47 packets as data (`id, stage, title, brief, owner_paths, depends_on`) for `gen-wave2.py` | final (13:11); never consumed |
| `docs/gpuix-shell/MUSIC.md` | 102,515 B / 1,378 l | Music spec: P0/P1/P2, architecture, measured facts, 9 secret rules, behaviour, exact interfaces §6, packets M1–M7 §7, test plan, demo runbook, open questions §12 | v1 (23:56); "Build: not started" |
| `docs/gpuix-shell/SYNTHESIS.md` | this file | Closure | — |
| `docs/gpuix-shell/evidence/rail-probe/rail.tsx` | 1,151 B | 56 px rail, nine slots, slot 3 highlighted, hard-coded "23:41" clock | MEASURED 23:10 |
| `docs/gpuix-shell/evidence/rail-probe/smoke.py` | 2,831 B | Headless Sway 1.12 + bun + grim + workspace-rect assert | MEASURED 23:10 |
| `docs/gpuix-shell/evidence/rail-probe/shot.png` | 9,051 B | 1440×900 screenshot of the probe | MEASURED 23:10 |
| `docs/gpuix-shell/music/01-raycast-spotify-model.md` | 57,582 B / 735 l | What "Spotify-level" means; Raycast keymap translated; parity list | research, rc=0 |
| `docs/gpuix-shell/music/02-navidrome-ext-and-cliamp.md` | 35,513 B / 550 l | Raycast Navidrome extension (c33bf4cb) and cliamp (5656a55e); endpoint matrix; one live run | research, rc=0 |
| `docs/gpuix-shell/music/03-subsonic-api-live.md` | 54,446 B / 876 l | Measured Subsonic/OpenSubsonic reference against Navidrome 0.63.2 | research, MEASURED |
| `docs/gpuix-shell/music/04-playback-engine.md` | 54,237 B / 706 l | Measured mpv engine: fd IPC, two-entry window, queue, reporting, MPRIS | research, MEASURED |
| `docs/gpuix-shell/music/05-ux-spec.md` | 102,936 B / 1,547 l | Views, wireframes, geometry, keys, provider contract | research, rc=0 |
| `docs/gpuix-shell/music/BUILD-LOG.md` | 1,137 B / 18 l | Only `## M0 Design pass` filled | M1–M7 absent |
| `docs/gpuix-shell/music/probe/subsonic-get` | 2,608 B / 38 l | Read-only Subsonic probe; refuses write endpoints; credentials on curl stdin | tool; the checkpoint false positive |
| `docs/gpuix-shell/music/evidence/04-playback/` | 29 files, 42,371 B | mjs probes with `.out`/`.json`: nav-yes/no/errors, fd-ipc, orphan, rate48, events, lavfi, mono, loadfile-start, final-argv, queue-read, mpris-probe/run, socat-probe, subsonic | MEASURED on the strix |
| `docs/gpuix-shell/wave1/*.md` | 32 files, 2,281,785 B | Reader notes 01–30, 35, 36 (31–34 never numbered); each labels MEASURED / REPORTED / INFERRED | final; 7 revised 12:08–12:18 |
| `pkgs/gpuix-shell/package.json` | 429 B | deps `@gpuix/native` 0.11.0, `@gpuix/react` 0.11.0, `dbus-next` 0.10.2, `react` 19.2.0, `zod ^4`; dev `@types/bun latest`, `@types/react` 19.2.0, `typescript` 5.9.3; scripts `typecheck`, `test` only | music M0 shape; P-00 replaces it |
| `pkgs/gpuix-shell/tsconfig.json` | 408 B | strict TS config | M0 |
| `pkgs/gpuix-shell/.gitignore` | 56 B | ignores node_modules etc. | M0 |
| `pkgs/gpuix-shell/bun.lock` | 28,117 B | 135 packages; staged although ARCHITECTURE wants `package-lock.json` committed and `bun.lock` ignored | conflicts with §14 of ARCHITECTURE |
| `pkgs/gpuix-shell/src/launcher/provider.ts` | 9,332 B | FROZEN `LauncherProvider` contract (from music 05 §9.1) | compiles |
| `pkgs/gpuix-shell/src/music/types.ts` | 15,046 B | `MusicBackend`, state and command types | frozen, compiles |
| `pkgs/gpuix-shell/src/music/config.ts` | 4,667 B | config shape and defaults | frozen, compiles |
| `pkgs/gpuix-shell/src/music/errors.ts` | 2,439 B | error kinds | frozen, compiles |
| `pkgs/gpuix-shell/src/music/format.ts` + `format.test.ts` | 6,149 + 2,148 B | formatting helpers; 5 tests pass | frozen, tested |
| `pkgs/gpuix-shell/src/music/subsonic/{types,api,map}.ts` | 8,715 + 5,241 + 2,156 B | Subsonic types, `SubsonicApi` interface, DTO mapping | frozen, compile |
| `pkgs/gpuix-shell/node_modules/` | 128 entries (not staged) | one `bun install` (140 packages; one optional `node-gyp` postinstall blocked) | local only |
| `home/dot_local/bin/runtime-test` | +25/−6 | `--render-node` flag: validates a DRM render node, never a card/input device; unsets Hyprland env | MEASURED (`test_render_node.py` 4/4 per w1-21) |

Absent, and expected by the plan: `pkgs/gpuix-shell/{src/main.ts,build.ts,default.nix,package-lock.json}`,
`pkgs/anthropic-ui-static.nix`, `home/gpuix-shell.nix`, `home/gpuix-shell-{binds,entries}.nix`,
`tests/gpuix-shell/`, `docs/gpuix-shell/{BUILD-LOG,INTEGRATION,GAPS,MORNING,README,RUNBOOK,PERF,SECURITY,EXTENSIONS}.md`,
`docs/gpuix-shell/music/{STATUS,DEMO,ABOVE-RAYCAST}.md`.

---

## 3. The shell as specified

### 3.1 Surfaces (SCOPE.md §0–§20; totals SCOPE:633 "171 feature rows; P0 69, P1 65, P2 37")

| § | Surface | S-ids | Rows | P0 | P1 | P2 |
|---|---|---|---|---|---|---|
| 0 | Foundations (process model, CLI/socket, Sway IPC, herdr reader, D-Bus, theme, config, ui-tree, smoke harness, Nix, output pinning, validate/status, command runner) | S-001–S-019 | 19 | 16 | 3 | 0 |
| 1 | Rail (left bar) | S-020–S-046 | 27 | 10 | 12 | 5 |
| 2.1 | Launcher: root, grammar, navigation | S-050–S-059 | 10 | 7 | 3 | 0 |
| 2.2 | Launcher: builtin providers | S-060–S-094 | 35 | 14 | 14 | 7 |
| 2.3 | Launcher: extension host | S-095–S-097 | 3 | 1 | 1 | 1 |
| 3 | Notifications (daemon, toasts, centre) | S-100–S-114 | 15 | 7 | 4 | 4 |
| 4 | OSD | S-115–S-120 | 6 | 3 | 2 | 1 |
| 5 | Workspace switcher (Mod+i) | S-121–S-125 | 5 | 1 | 2 | 2 |
| 6 | Quick controls (per-domain menus) | S-126–S-136 | 11 | 2 | 8 | 1 |
| 7 | Power / session | S-140–S-142 | 3 | 1 | 1 | 1 |
| 8 | Clipboard | S-145–S-147 | 3 | 2 | 1 | 0 |
| 9 | Screenshot / record / colour picker / OCR | S-148–S-151 | 4 | 1 | 3 | 0 |
| 10 | File explorer (Pinax-inspired) | S-155–S-160 | 6 | 0 | 4 | 2 |
| 11 | Keybinding cheatsheet | S-165–S-166 | 2 | 0 | 1 | 1 |
| 12 | Tray (SNI) | S-168 | 1 | 0 | 0 | 1 |
| 13 | Calendar / clock | S-170–S-171 | 2 | 0 | 1 | 1 |
| 14 | System monitor | S-175–S-176 | 2 | 0 | 1 | 1 |
| 15 | Updates | S-178 | 1 | 0 | 0 | 1 |
| 16 | Theme switching | S-180–S-181 | 2 | 1 | 0 | 1 |
| 17 | Wallpaper | S-185 | 1 | 1 | 0 | 0 |
| 18 | Lock screen / auth | S-188–S-189 | 2 | 0 | 0 | 2 |
| 19 | Agent / herdr surfaces | S-190–S-197 | 8 | 2 | 4 | 2 |
| 20 | OpenUI "ask" (exploratory, bounded) | S-200–S-202 | 3 | 0 | 0 | 3 |
| | **Total** | | **171** | **69** | **65** | **37** |

Ruled out (SCOPE §21): Hyprland/niri, blur/frost/shadows, Material You, wallpaper pickers, i18n, lock
screen tonight, settings GUI, TOML, any timer/OnCalendar, herdr focus calls, approve-from-rail, writing
Sway config, Vicinae/mako/waybar beside the shell.

### 3.2 The P0 list (SCOPE.md "P0 — must be on the Zenbook in the morning", 69 ids, titles shortened)

| | | |
|---|---|---|
| S-001 process model (daemons as user units, overlays per show) | S-002 CLI + socket, per-connection routing | S-003 binds call the CLI |
| S-004 Sway IPC client | S-005 herdr reader (read-only, nine slots, both seats) | S-006 D-Bus layer + `--check-dbus` |
| S-007 theme fragment, three themes, symlink watch, static font instances | S-008 flat opaque look rules | S-009 config JSON + schema |
| S-010 `ui-tree` seam | S-011 compositor smoke harness under `runtime-test` | S-012 Nix package, HM module, vicinae/mako exclusivity, flake asserts |
| S-014 GPUIX engineering rules in the kit | S-015 output pinning dance | S-017 `validate` + `status --json` |
| S-019 command runner | S-020 rail slot rows 1–9 (+10) | S-021 click slot → workspace |
| S-022 run-state marks (blocked orange, done green) | S-024 status cluster registry | S-025 clock |
| S-026 battery | S-027 network glyph | S-029 audio glyph |
| S-030 notifications bell | S-037 rail toggle/collapse/expand verbs | S-050 launcher toggle + escape/backspace/pop-to-root |
| S-051 root search: sections, fallbacks, hidden list | S-052 favourites + frecency | S-054 action panel + keymap |
| S-055 header/footer chrome | S-056 navigation stack | S-059 confirm dialog for irreversible commands |
| S-060 apps provider (+PWA, dotfiles entries) | S-061 command registry + `cmd ls/launch` | S-062 windows provider on Sway IPC |
| S-063 herdr workspaces picker | S-064 clipboard history view | S-065 files provider over `fd` |
| S-066 calculator | S-069 theme provider | S-070 power provider |
| S-072 wifi view in launcher | S-074 audio route view in launcher | S-078 notifications commands |
| S-086 `select` / dmenu bridge | S-092 sleep-monitors / monitors-off entries | S-095 `LauncherProvider` contract |
| S-100 fd.o Notifications server (notify-send parity) | S-101 toast card (urgency, timeouts, progress, actions, max 4) | S-102 toast interaction + dismiss-all/restore-last |
| S-104 flood protection | S-105 DND | S-106 JSONL history restored on restart |
| S-109 herdr attention notification with "Go" | S-115 volume OSD | S-116 brightness OSD |
| S-117 mic/touchpad OSD | S-121 Mod+i switcher | S-126 wifi menu (controls) |
| S-128 audio menu (controls) | S-140 power menu with hold-to-confirm | S-145 clipboard store + watcher |
| S-146 clipboard CLI | S-148 screenshot result toast with preview | S-180 theme follow + `theme` script edit |
| S-185 wallpaper stays solid black (assert only) | S-190 attention routing | S-191 pickers replace `herdr-picker` |

### 3.3 Geometry (DESIGN.md §8, A-08…A-39; ARCHITECTURE §5.1 layer options; margins `[top,right,bottom,left]`)

| Surface | Layer / anchor | Size | Margin | Exclusive | Keyboard | Rows / notes |
|---|---|---|---|---|---|---|
| Rail collapsed (boot) | top / left,top,bottom | 56 × stretch | 0 | 56 | none | 12 + 32 + 12; cell 32×30, radius 8, gap 2; hairline x=55; workspace x=56 w=1384 (MEASURED) |
| Rail expanded | top / left,top,bottom | 220 × stretch | 0 | 220 | none | rows 196×30, inset 12, gap 2, radius 8, current bar 2×22 accent at x=0; workspace x=220 w=1220 |
| Launcher, ask, cheatsheet | overlay / top | 700 × 580 | [108,0,0,0] | 0 | exclusive | input row 48 (16 px), list 495 = 11 × 44, headers 30, footer 36, action panel 300 (rows 40), scope dropdown 240; clipboard rows 56 + 40×40 thumbs; emoji grid 8 × 76×76; music rows 56 + 3 px bar |
| Switcher | overlay / top | 560 × (48 + rows×44 + 36), ≤ 580 | [108,0,0,0] | 0 | exclusive | rows 44; pinned to eDP-1 |
| Notification centre | overlay / top,right | 500 × 650 | [12,12,0,0] | 0 | exclusive | A-28 |
| Controls | overlay / top,right | 420 × content ≤ 640 | [12,12,0,0] | 0 | on-demand (UNVERIFIED; fallback exclusive) | rows 40; list menus per domain |
| Power | overlay / centred | 360 × (46 + rows×44 + 36) | 0 | 0 | exclusive | rows 44; hold 1500 ms (DESIGN) |
| Toasts | overlay / top (centre; `layout.toast.anchor` → top,right) | 390 × Σ cards | [12,0,0,0] | 0 | none | card 72–140, radius 12, pad 14, header 20, image 48, actions 24, gap 8, max 4 + "(N more)" 24; timeouts low 5000 · normal 5000 · critical never |
| OSD | overlay / bottom | 280 × 56 | [0,0,96,0] | 0 | none | icon 18 @16, label 12 @46, figures 12 right @264, 3 px track y=42; hold 1500 ms |
| Files | xdg toplevel | 1000 × 640 (min 640×400) | — | — | — | rail 248/60, rows 34/48, preview 300 at ≥ 1240, zoom 0.8–1.6 |
| Gallery | xdg toplevel | 1200 × 800 | — | — | — | — |
| Music (standalone) | xdg toplevel | 900 × 640 | — | — | — | MUSIC §1.1 A1; `--layer` = launcher geometry |

Grid: 4 px, rail exception 220/30/12/2/8 (U-07). Focus ring 2 px `line.focus`, keyboard only (U-11).

### 3.4 Tokens (DESIGN.md §2, §4, §5)

| Token | noir | claude-dark | claude-light |
|---|---|---|---|
| surface canvas / base / raised | `#000000` / `#000000` / `#101111` | `#1A1A1A` / `#20201F` / `#262625` | `#F9F9F7` / `#F0EFEC` / `#FFFFFF` |
| ink strong / default / muted | `#EAECF0` / `#D3D7DE` / `#818898` | same as noir | `#131313` / `#131313` / `#52514E` |
| line hairline / default / strong | `#DEDCD126` / `#DEDCD14D` / `#DEDCD170` | strong `#DEDCD16B` | strong `#1F1E1D80` |
| accent / selection.bg | `#70B8FF` / `#264F78` | same | `#0051C2` / `#CDE2FB` |
| state hover / selected | `#161615` / `#242321` | `#2E2D2C` / `#393937` | `#E3E3E1` / `#D6D6D4` |
| run blocked / working / done / idle+unknown | `#FBAD60` ◉ / `#70B8FF` ◐ / `#9BE963` ● / `#818898` ✓ ○ | same | `#9A3F00` / `#0051C2` / `#006B00` / `#52514E` |
| dot waiting / error / working / done (rail, switcher) | `#D29922` / `#F85149` / `#70B8FF` / `#3FB950` | same | `#9A6700` / `#CF222E` / `#0051C2` / `#1A7F37` |
| clay (mark only) / light primary fill | `#D97757` | `#D97757` | `#D97757` / `#A74B2F` (clay text never on light: 2.96:1) |
| wallpaper | `#000000` | `#000000` | `#000000` |

Radius: `outer` 12, `row` 8, `sm` 6 (caps/chips), `full` 999, rail surface 0; concentric inner = outer −
inset, floor 4 (DESIGN §1.1, A-30; see §7 #8 for the open conflict with SCOPE S-007). Motion: one curve
`cubic-bezier(0.2, 0, 0, 1)`; durations 0 / 120 / 180 / 240; toast and OSD fade 120, everything else 0;
working-dot pulse 600 ms stepped 1 ↔ 0.55; destructive hold fill 1500 ms; ceiling 240, no overshoot.
Status families danger/warning/success/info/neutral with bg = fg at 0.14 dark / 0.12 light. No blur,
frost, gradient, shadow or scrim; floating = `surface.raised` + 1 px `line.strong`.

### 3.5 Fonts (DESIGN.md §2.4, §3; A-26, A-29, A-31)

| Role | Family (fontconfig name) | Sizes (px / line) | Weights |
|---|---|---|---|
| UI | `Anthropic Sans` | caption 11/16 · meta 12/18 · chrome 12/18 (500) · row 13/20 · body 14/21 · input 16/22 · title 16/20 (600) · display 20/24 (600) | 400 / 500 / 600 |
| Prose (ask replies only) | `Anthropic Serif` | 15/25 | 400 |
| Figures, code, glyphs | `AnthropicMono Nerd Font` | figures 12/18, small 11/16, code 13/21, rail glyph 13 | 400 |
| Icons | `Anthropicons` | per surface | — |

Weight is never the only cue: the variable Anthropic Sans renders every weight alike in GPUIX 0.11
without a registered static instance (w1-15, A-31). No italic, no letter-spacing, floor 11. Launcher
input 16 derives from Tom's "Vicinae font 12" = 12 pt (A-29).

### 3.6 The keybinding rewire (KEYS.md §2, §3, §8, §9; KEYS rules where SCOPE §22 differs)

Baseline `binds.conf`: 108 `bindsym` + 10 `workspace … output` + 2 gestures; 102 keep / 6 changed.
Never violated: `$mod+k` stays `focus up`; the three herdr chord lines and the four `Alt+h/j/k/l` lines
stay verbatim; `Ctrl+n`/`Ctrl+Shift+n` stay Chrome's; media/brightness/screenshot/pomodoro keys keep
their scripts; no verb approves a polkit/NM/BlueZ prompt; power needs the on-screen hold or `--yes`.

| Bind | Today | Tomorrow | Status |
|---|---|---|---|
| `$mod+d`, `$mod+space` | `vicinae toggle` | `gpuix-shell launcher toggle` | changed |
| `$mod+Ctrl+space` | `herdr-picker` (Vicinae dmenu) | line unchanged; script backend → `gpuix-shell dmenu`; after wave 3 `launcher open --view herdr` | changed (backend), INFERRED sequencing |
| `$mod+Shift+n` | `sway-workspace rename` | line unchanged; backend → `gpuix-shell dmenu --free-text` | changed (backend) |
| `$mod+v` | `vicinae cmd launch clipboard:history` | `gpuix-shell launcher open --view clipboard` | changed |
| `F9` | `$prompt audio-route-prompt` | `gpuix-shell controls open audio` once `audio-route` takes a sink argument | changed (wave 3) |
| F6–F8, XF86Audio*, XF86MonBrightness*, Menu, XF86AudioMicMute | scripts → `osd` → mako | no new bindsym; the `osd` script's `notify-send -a osd -r <id> -h int:value:N` is routed to the OSD window | script change |
| `$mod+i` | (PR #565, fuzzel) | `gpuix-shell switcher toggle` | new |
| `$mod+o` | (PR #571 `makoctl dismiss --all`) | `gpuix-shell notifications dismiss` (newest) | new |
| `$mod+Ctrl+o` | — | `gpuix-shell notifications dismiss --all` | new, INFERRED key |
| `$mod+Shift+o` | — | `gpuix-shell notifications toggle` (centre) | new |
| `$mod+x` | — | `gpuix-shell power toggle` | new |
| `$mod+Shift+e` | — | `gpuix-shell files open` (`$mod+e` keeps nautilus) | new |
| `$mod+Shift+slash` | — | `gpuix-shell cheatsheet toggle` | new |
| `$mod+grave` | — | `herdr-context toggle` (branch c1a49b99) | new |
| `$mod+Shift+grave` | — | `gpuix-shell rail toggle` | new, INFERRED key |
| `$mod+comma` | — | `gpuix-shell controls toggle` | new, INFERRED key |
| `$mod+Ctrl+w` / `$mod+Ctrl+b` | — | `controls open wifi` / `controls open bluetooth` | new |
| `$mod+m` / `$mod+Shift+m` | — | `launcher open --view music` / `music now` | proposed, not activated (MUSIC Q2) |
| `$mod+a` | — | `ask toggle` | reserved until S-200 |
| lock, DND | — | deliberately unbound; `gpuix-shell lock` exits 69 | — |

Counts (KEYS §9): 12 bindsym activated + 1 script change + 3 proposed/reserved + 2 unbound. Delivery is
an HM-generated block appended to `sway-local.conf` via `lib.mkAfter` with `--no-warn` overrides;
`binds.conf` is not edited (ARCHITECTURE §12). Launcher prefixes (KEYS §4.3): `>` commands · `=`
calculator · `:` files (alias `/`; `em ` emoji) · `@` windows · `#` / `h ` herdr workspaces · `w ` wifi
· `bt ` bluetooth · `m ` / `♪` music · `t ` theme · `n ` notifications · `tabs ` Chrome · `tray ` ·
`?` cheat sheet. Retired: `vicinae.service`, `services.mako`, the `makoctl reload` hook in `bin/theme:84-91`,
Vicinae theme TOML, mako fragment, seven desktop entries, Vicinae `global_shortcuts`, PR #565's fuzzel
switcher (absorbed, its 16 tests reused), PR #571's bind (re-targeted).

---

## 4. Architecture decided (ARCHITECTURE.md; PLAN.md §4; ARCHITECTURE §22 rules on engineering)

### 4.1 Process model

One headless core, one D-Bus daemon, one rail daemon, one process per shown overlay. GPUIX 0.11.0 is
one window per renderer with no close/hide/resize/output selector (w1-15 G1–G9), so closing a surface
is process exit. Nothing headless loads the 52 MB `@gpuix/native` addon.

| Process | Started by | Window | Owns |
|---|---|---|---|
| `gpuix-shell daemon core` | `gpuix-shell-core.service` | none | `shell.sock`, registry + router, Sway IPC session, herdr poller, status readers (UPower, NM, BlueZ, logind, MPRIS, PipeWire, Tailscale), clipboard watchers + store, apps index, frecency/MRU, Chrome tab list, the surface supervisor |
| `gpuix-shell daemon notifications` | `gpuix-shell-notifications.service` (`Type=dbus`, `BusName=org.freedesktop.Notifications`) | none | notification store, history, rules, DND, flood guard, OSD slot; spawns `toasts` and `osd` |
| `gpuix-shell daemon rail --output eDP-1` | `gpuix-shell-rail.service` | 1 layer surface | `rail.sock`; subscriber of core topics; exits to hide or change width |
| `gpuix-shell surface toasts` / `osd` | notifications daemon | 1 overlay each | toasts respawned on every set change; OSD exits 1500 ms after last value |
| `gpuix-shell surface <launcher\|switcher\|center\|controls\|power\|cheatsheet\|ask\|gallery>` | core supervisor | 1 overlay | one process per show; exits on Escape, second toggle, focus loss or act-and-close |
| `gpuix-shell surface files` | core supervisor | xdg toplevel | `files-<n>.sock` |
| `gpuix-shell music serve` | `gpuix-shell-music.service` (P1, off) | none | `music/ctl.sock`, MPRIS `org.mpris.MediaPlayer2.gpuix_music`, mpv |
| `gpuix-shell native-host` | Chrome native messaging | none | stdio relay to `shell.sock` (manifest `com.vicinae.vicinae`) |
| `gpuix-shell <verb …>` | binds, scripts, Tom | none | one request; never loads the addon |

Supervisor: `closed → spawning → open → closed`; one exclusive overlay at a time; 150 ms debounce;
spawn via `Bun.spawn([exe,"surface",name],{stdin:"ignore"})` with `GPUIX_SHELL_SPAWN=…/spawn/<nonce>.json`
carrying `{surface,args,nonce,session,output,theme,data}`. Rail and switcher pinned to eDP-1 by the
output-pin dance (record focus → `focus output eDP-1` → spawn → `surface/ready` → `[con_id] focus`,
`SEND_TICK` barrier `gpuix-shell:pin:<nonce>`). Singleton = bind is the lock, stale socket detected by
`session ≠ sha256($SWAYSOCK)[:16]`. Memory measured: one 0.11 surface 148.5 MiB, two in one process
163.4 MiB; headless daemons unmeasured (est. 60–90 MiB).

### 4.2 Socket and CLI

`$XDG_RUNTIME_DIR/gpuix-shell/shell.sock` (dir 0700, socket 0600), siblings `notifications.sock`,
`rail.sock`, `<surface>.sock`, `files-<n>.sock`, `music/ctl.sock`, `spawn/<nonce>.json`, `herdr.sock`.
NDJSON, one JSON-RPC 2.0 message per line; method `<domain>/<verb>` ↔ registry id `<domain>.<verb>`;
params `{args, source, tty, cwd, session}`; result `{outcome: confirmed|failed|unknown, echo?, data?, undo?}`;
`state {topic, rev, value}` snapshots and `event` notifications; replies keyed by (connection, id).
Vicinae compat framing (P1) accepted on the same socket via a 3-byte sniff. Exit codes: 0 ok, 1
failed/refused, 2 usage, 3 not-running, 69 unavailable (SCOPE S-002, KEYS §7.8). Limits: request line
16 KiB; `dmenu/select/clipboard/browser` 1 MiB; backlog 4 MiB; 32 actions, summary 1 KiB, body 8 KiB.
CLI (`src/cli/main.ts`): longest-match on `cli.path`, zod flags, 1 s connect timeout, `--json`,
`--source`, `--hud`, `--yes`; streaming `listen`, `dmenu`, `select`; pre-socket `--check-native`,
`--check-dbus`, `--check-theme`; cold-start target ≤ 100 ms. Verb catalogue in ARCHITECTURE §9.2
(KEYS §9 counts 12 surface + 15 notification/OSD + 4 clipboard/dmenu/select + 12 theme/state/diagnostics
+ 1 music family + 4 power/lock/inhibit + 7 compat aliases).

### 4.3 Seams (PLAN.md §4; ARCHITECTURE §2.2)

- Dispatch `src/main.ts` (P-00): `daemon core|notifications|rail`, `surface <name>`, `native-host`,
  `music …`, the three `--check-*`, else `cli/main.ts runCli`; entry modules export `default async
  function main(argv)`; `surfaces/index.ts` exports `SURFACES`.
- Layers and fence (`src/fence.test.ts`, also in Nix `checkPhase`): `core/**` pure (core + `zod` only);
  `platform/**` adds `node:*`, `bun:sqlite`, `dbus-next`; `daemons/**` no react/GPUIX; `cli/**` only
  `core/{socket,registry,logging}` + `platform/{socket,fs}`; `ui/kit/**` react + `@gpuix/react`
  intrinsics, never `@gpuix/native` or platform; surfaces never import each other; nobody imports
  herdr-web-ui `src/`, the kit's `apps/*` or shared-parity.
- Topics (`core/state`): `sway, slots, herdr, theme, overlays, notifications, clipboard, network,
  bluetooth, audio, battery, media, tailscale, status, apps, tabs, music`; full snapshots, hub bumps `rev`.
- Exports per area are listed in PLAN §4.4 by owner (P-01 sway-ipc, P-02 herdr, P-03 dbus, P-04
  theme/fonts, P-05 registry/socket/config/logging/state/CLI, P-06 daemons/core, P-07 ui/host + kit,
  P-11 notifications); providers in fixed order `apps, commands, windows, workspaces, calc, clipboard,
  files, tabs, emoji, wifi, bluetooth, audio, theme, notifications, music, cheatsheet, shell, dmenu`.
- Frozen: `src/launcher/provider.ts`, `src/music/{types,errors,config,format}.ts`, `src/music/subsonic/*`
  (P-23 append-only). Seam files written once by P-00, edited only by P-30 / P-52.

### 4.4 GPUIX limits measured (w1-15 P1–P7, w1-21, BRIEF, ARCHITECTURE §3, §23)

Exclusive zone 56 → workspace x=56 w=1384 (probe + Nix-built repeat); `exclusiveZone 0` = compositor
decides, `-1` = ignore; single anchor centres; every layer surface opens on the focused output; warm
first paint ~0.3 s, `init()` 92–177 ms; toast spawn ~150 ms, respawn ~30 ms; `--check-native` 102 ms,
`--check-dbus` 123 ms, bare bun 81 ms; static bundle ~0.1 s per CLI call; multi-renderer stable only
4–6 s measured; herdr local snapshot ~5 ms; Anthropic Sans advance 0.525 em at 24 px; variable
Sans/Serif weights 300/400/700 render identically; `hasTestGpuixRenderer() === false` on Linux;
automation `launch()`, Escape/Enter and clipboard copy work on Linux (P7, 12:10 today). Gaps G1–G9:
no window close/hide, no output selection, no layer reconfigure or input region, no popups outside
the surface, no JS clipboard API, no screenshot/test renderer, no zoom, no `display:none`/`zIndex`/
`fontStyle`/`letterSpacing`. Rules: `createRenderer()` + `render(..., {renderer, keyboardFocusDim:false,
tabNavigation:false, onKeyDown})`, never bare `render()`; never `root.unmount()`; register
`uncaughtException`/`unhandledRejection`/`SIGTERM` → `exitSurface`; numeric px only; flex or grid;
one template string per `<text>`; no hex in components; `<virtual-list>` wrapped once in `VirtualRows`.

### 4.5 Nix / Home Manager (ARCHITECTURE §12–§14; PLAN P-19, P-41)

`package.json` pins react 19.2.0, `@gpuix/react` and `@gpuix/native` 0.11.0, dbus-next 0.10.2, zod 4.6.7,
`@openuidev/lang-core` 1.0.1; `package-lock.json` the only lock Nix sees; `bun.lock` git-ignored;
`npmDepsHash` to be re-measured (the measured `sha256-PLas/KzhWF2NvFGTX5Z3OfINGIeGrrVSGse4kAJKI0k=`
predates lang-core). `build.ts` = `Bun.build` esm, `splitting:true`, externals `@gpuix/native*`,
`usocket`, `x11`. `default.nix` = `buildNpmPackage` + `nodejs_24`, `--ignore-scripts`, `autoPatchelfHook`,
`buildInputs [stdenv.cc.cc.lib libxkbcommon libxcb]`, runpaths wayland/vulkan-loader/libGL; build =
typecheck + bun build; check = `bun test`; install check runs `--check-native` and `--check-dbus`; D-Bus
activation file `org.freedesktop.Notifications.service` (`SystemdService=gpuix-shell-notifications.service`);
`license = unfree`. HM module `home/gpuix-shell.nix`: `programs.gpuixShell.{enable, package, fontPackage,
target, rail.{enable,output,boot}, toastAnchor, binds.{enable,proposed}, herdr.{transport,host},
chromeNativeHost, music.enable, settings, extraEnvironment}`; asserts `!services.mako.enable` and
`!programs.vicinae.enable`; units `gpuix-shell-{core,notifications,rail,music}` on
`sway-physical-session.target` (`Restart=on-failure`, `RestartPreventExitStatus=69`, `UMask=0077`,
never `Requires=sway-physical.service`). Theme fragment `gpuixShell = t: builtins.toJSON {...}` in
`home/themes/default.nix` → `~/.config/theme/gpuix-shell.json`, watched by two `fs.watch`es, 50 ms
debounce. Static weights 500/600 via `pkgs/anthropic-ui-static.nix` (fontTools instancer, store-only,
registered per renderer from `GPUIX_SHELL_FONT_DIR`). Migration = one switch: import module, gate
`home/vicinae.nix` on `!programs.gpuixShell.enable`, enable in `hosts/client/default.nix`; rollback =
flip the option; never on the strix. Nothing is activated by the build.

### 4.6 Tests (ARCHITECTURE §15–§16; PLAN §4.6)

Four levels, all under `home/dot_local/bin/runtime-test --render-node /dev/dri/renderD128 -- …` when a
compositor, bus, runtime socket or daemon is involved; never against live Sway, herdr, the user manager
or `strix:8731`: (1) `bun test` pure logic beside the code, in Nix `checkPhase`; (2) hermetic D-Bus under
`dbus-run-session --config-file=tests/gpuix-shell/dbus-session.conf` (14 mako-parity `notify-send` cases,
bus-name contention → 69, core against `fake-server.ts` + fake `herdr`); (3) Python smokes
`tests/gpuix-shell/smoke_<surface>.py` on headless Sway 1.12 gles2 (1440×900; 2880×1800 scale 2; two
outputs), driven by `driver.mjs` over `@gpuix/native/automation`, asserting geometry via
`swaymsg -t get_workspaces`, colours via `grim` pixels, content via `ui-tree`, each writing
`results.json` + `docs/gpuix-shell/evidence/<smoke>/`; (4) fixtures with provenance. Never automated:
the live seat, real keyboards (`on-demand`), multi-hour renderer stability, Chrome with the real extension.

---

## 5. Boundary (BOUNDARY.md; 47 rulings R1–R47; 62 component rows: 23 shell, 11 adapter, 19 shared core, 3 utility head, 4 not built, 2 launched-only)

1. One-line test: compositor-bound → Tom's shell (dotfiles); GPU window without a compositor → Marwan's kit; browser-only → Frank's web head; otherwise → shared core.
2. Founding split: A = the Sway shell stays home in private dotfiles; B = utilities travel by `npx @agency-agency/kit`; C = Cloudflare Workers plus the single MCP codemode door.
3. Personal shell owns: rail process, output policy and the nine-slot cap, launcher surface, `shell.sock` router + `dmenu`, switcher, OSD, controls, power, files window, `ask` and its vocabulary, model endpoint config, CLI verbs, theme fragments + watcher, fonts, keybinds, systemd units, Nix packaging and HM options, existing scripts as backends, music daemon/MPRIS/credentials/mpv, Chrome manifest link, toast anchor/timeouts/rules.
4. Platform adapter (Linux, reusable): herdr reader + Sway marks, Sway IPC client, `.desktop` parser + `gio launch`, files over `fd`, clipboard watcher + store, Chrome native host, fd.o notification server + history, NM/BlueZ/UPower/logind/PPD/MPRIS/PipeWire/gammarelay clients, Tailscale reader, layer-shell wrappers, smoke harness template.
5. Shared core (agency): rail row model, status vocabulary and herdr types, attention rule, `LauncherProvider` + registry + prefix router, fuzzy/frecency/MRU/pins, emoji data + calculator, Vicinae wire vocabulary and manifest schema, `Icon` ids, script-command parser, `MusicBackend` + Subsonic types, operations + receipts, OpenUI contract/validator/stream + MutationHost, theme token roles, config schema shape, design rules U-01..U-19, React components without layer-shell, toast/OSD components, `fakehost`.
6. The three heads: web (herdr-web-ui, Frank), macOS native (the kit, Marwan), Wayland native (this shell); mail, CRM, projects, chat and the "vesence ones" are launched by the shell, never built here.
7. The shell may: launch utilities, show their OpenUI programs through the adapter, read receipts, receive notifications, host Vicinae/Raycast extensions declaratively, read Chrome tabs, expose shortcuts, import shared contracts, "send to agent" by copy + slot switch.
8. The shell must not: own utility data, embed a WebView/CDP, require any utility, hold credentials, issue herdr writes or focus calls, inject keystrokes, approve prompts over the wire, write Sway/GTK/Qt config, speak for utilities to agents, ship fonts or brand names, import utility internals, register `x-scheme-handler/vicinae` while Vicinae is installed, schedule work.
9. Not built here, with seams kept: SNI tray, polkit agent, BlueZ Agent1, NM SecretAgent, lock, idle; herdr server, kitty, Chrome, GTK picker and `herdr-chord` are launched or read, never built.
10. Not built at all: calendar, notes, weather, KDE Connect, sysmon, settings GUI, onboarding, update checker, Material You, blur, wallpaper, i18n, multi-compositor, runtime extension store, telemetry, speech/dictation/NPU, the friends' Omarchy fleet.
11. "SEPARATE project" (Tom 10-20, R9) is read as separate from the agency kit repo, not from dotfiles (BOUNDARY assumption; §7 #2).
12. Extraction after the morning, F1–F16: tokens, OpenUI kernel, adapter, provider contract, fuzzy/frecency, status types, operations, extension vocabulary, components, design rules, fakehost, smoke template, Linux providers, file model, music types, Chrome protocol types.
13. Never extracted: palettes, fonts, Sway config, scripts, the Nix module, units, `shell.sock`, slot policy, binds, hostnames, the model endpoint, the launcher catalogue.
14. Licences (Vicinae GPL-3.0 root, ISC TypeScript packages, BSD-style `src/server/LICENSE`) were read by w1-36, not by BOUNDARY's author; F8 and rule 10 depend on that reading (BOUNDARY §8).
15. The owner column of BOUNDARY §3 is the author's judgement against the one-line test; rows absent from the FP/BOUNDARIES matrix (extension host, Chrome bridge, music lane, cheatsheet, GPUIX runtime facts, Omarchy fleet) are INFERRED placements (BOUNDARY §8).

---

## 6. The build plan ready to execute (PLAN.md §2, §6; PLAN.json: 47 packets)

### 6.1 Stage order (PLAN §2)

| Stage | Packets | Runs |
|---|---|---|
| `scaffold` | P-00 | alone, first |
| `build` | P-01 … P-23 (23) | in parallel after P-00, 16 at a time; suggested first 16: P-01…P-11, P-13, P-14, P-15, P-19, P-22; then P-12, P-16, P-17, P-18, P-20, P-21, P-23 |
| `integrate` | P-30 | alone, after every build packet |
| `complete` | P-31 … P-51 (21) | in parallel after P-30 |
| `deliver` | P-52 | alone, last: six logical commits, push, draft PR with MORNING.md as body |

Ids skip P-24…P-29; 1 + 23 + 1 + 21 + 1 = 47 (PLAN.json `Counter`: build 23, complete 21, scaffold 1,
integrate 1, deliver 1).

### 6.2 The 47 packets

| id | stage | title (short) | key owner paths |
|---|---|---|---|
| P-00 | scaffold | package, dispatcher, seams, stubs, harness, hello smoke | `pkgs/gpuix-shell/{package.json,package-lock.json,tsconfig.json,build.ts,default.nix}`, `src/main.ts`, `src/fence.test.ts`, every seam `index.ts` and stub, `tests/gpuix-shell/{harness.py,smoke_hello.py}`, `docs/gpuix-shell/BUILD-LOG.md` |
| P-01 | build | core/sway-ipc + platform/sway | `src/core/sway-ipc/**`, `src/platform/sway/**`, `fixtures/sway/**` |
| P-02 | build | core/herdr + platform/herdr | `src/core/herdr/**`, `src/platform/herdr/**`, `specs/herdr.ts`, `handlers/herdr.ts`, `tests/…/bin/herdr` |
| P-03 | build | core/dbus + platform/dbus readers, audio, tailscale | `src/core/dbus/**`, `src/platform/dbus/**` (not notifications-server), `src/platform/{audio,tailscale}/**`, `dbus-session.conf` |
| P-04 | build | core/theme + fonts + tokens | `src/core/{theme,fonts}/**`, `src/platform/{theme,fonts}/**`, `home/themes/default.nix` |
| P-05 | build | registry + socket + config + logging + state + platform/{socket,fs,exec,state} + CLI | `src/core/{registry,socket,config,logging,state}/**`, `src/platform/{socket,fs,exec,state}/**`, `src/cli/**` |
| P-06 | build | daemons/core: hub, supervisor, focus guard, pollers | `src/daemons/core/**`, `handlers/supervisor.ts` |
| P-07 | build | ui/host + ui/kit + design-lint | `src/ui/**` |
| P-08 | build | surfaces/rail + items | `src/surfaces/rail/**`, `src/items/{clock,battery,network,bluetooth,audio,bell,tailscale,media,pomodoro,recording,privacy,touchpad,custom}/**` |
| P-09 | build | launcher host + apps/commands/windows/workspaces/calc + fuzzy/frecency + dmenu | `src/surfaces/launcher/**` (minus listed providers), `src/core/{launcher,apps,scripts}/**`, `src/platform/apps/**` |
| P-10 | build | clipboard, files, tabs, emoji providers; clipboard store; Chrome native host | `providers/{clipboard,files,tabs,emoji}.ts`, `src/core/clipboard/**`, `src/platform/{clipboard,chrome}/**`, `src/daemons/native-host/**`, `data/glyphs.json` |
| P-11 | build | notifications daemon, toasts, centre | `src/core/notifications/**`, `src/platform/dbus/notifications-server.ts`, `src/daemons/notifications/**`, `src/surfaces/{toasts,center}/**` |
| P-12 | build | surfaces/osd | `src/surfaces/osd/**`, `specs/osd.ts` |
| P-13 | build | surfaces/switcher + sway specs/handlers | `src/surfaces/switcher/**`, `specs/{switcher,sway}.ts`, `handlers/sway.ts` |
| P-14 | build | surfaces/controls + wifi/bluetooth/audio providers | `src/surfaces/controls/**`, `providers/{wifi,bluetooth,audio}.ts` |
| P-15 | build | surfaces/power | `src/surfaces/power/**`, `specs/power.ts`, `handlers/power.ts` |
| P-16 | build | surfaces/files + file model | `src/surfaces/files/**`, `src/core/files/**` |
| P-17 | build | cheatsheet + keyed status + calendar/sysmon/capacity items | `src/surfaces/cheatsheet/**`, `src/core/cheatsheet/**`, `src/items/{sysmon,capacity,calendar}/**` |
| P-18 | build | openui contract, validator, stream, mapper; ask; gallery | `src/openui/**`, `src/surfaces/{ask,gallery}/**` |
| P-19 | build | Nix package, static fonts, HM module, flake wiring, vicinae/mako gate | `pkgs/gpuix-shell/default.nix`, `pkgs/anthropic-ui-static.nix`, `home/gpuix-shell.nix`, `flake.nix`, `overlays/default.nix`, `home/{home,vicinae}.nix`, `hosts/client/default.nix` |
| P-20 | build | Sway binds block, desktop entries, script edits | `home/gpuix-shell-{binds,entries}.nix`, `home/dot_local/bin/{osd,theme,herdr-picker,gpuix-notify}`, `startup.conf` |
| P-21 | build | README, RUNBOOK, MORNING skeleton | `docs/gpuix-shell/{README,RUNBOOK,MORNING}.md` |
| P-22 | build | harness completion: driver.mjs, smoke skeletons, fakes, hermetic tests | `tests/gpuix-shell/**` (minus P-00/P-02/P-20/P-23 files) |
| P-23 | build | Music lane M1–M7 | `src/music/**`, `providers/music.ts`, `specs/music.ts`, `tests/…/music/**`, `docs/gpuix-shell/music/**` |
| P-30 | integrate | seams wired, typecheck + bun test green, bundle split, ping e2e | all seam files, `src/**`, `docs/gpuix-shell/{ASSUMPTIONS,BUILD-LOG,INTEGRATION}.md` |
| P-31 | complete | core daemon e2e: fake Sway + fake herdr | P-01/02/06 paths, `smoke_core.py`, `evidence/core/**` |
| P-32 | complete | notifications conformance: 14 notify-send cases + toast pixels | P-11 paths, `smoke_notifications.py` |
| P-33 | complete | rail smoke + theme live-reload + font weights + per-output rail | P-08/P-04 paths, `smoke_{rail,theme,two_outputs}.py` |
| P-34 | complete | launcher smoke + P1 features | P-09 paths, `smoke_{launcher,dmenu}.py` |
| P-35 | complete | clipboard e2e + paste path + cliphist import + emoji smoke | clipboard/emoji paths, `smoke_clipboard.py` |
| P-36 | complete | switcher smoke on two outputs (pin dance) + Alt-Tab | P-13 paths, `output-pin.ts`, `smoke_switcher.py` |
| P-37 | complete | controls smoke + BT agent + battery/PPD + tailscale + keyboard-mode decision | P-14/P-03 paths, `smoke_controls.py`, `fakes/dbus/**` |
| P-38 | complete | power + OSD smokes, observed-service OSD, osd CLI | P-15/P-12 paths, `smoke_{power,osd}.py`, `fakes/logind/**` |
| P-39 | complete | notification centre smoke + hints + grouping + rules | `src/surfaces/center/**`, `smoke_center.py` |
| P-40 | complete | files explorer smoke + preview + jobs/undo/trash + send-to-agent | P-16 paths, `smoke_files.py` |
| P-41 | complete | Nix build to green: package, checks, home-profiles, client toplevel, static fonts, D-Bus activation | P-19 paths, `smoke_nix_rail.py`, `evidence/nix/**` |
| P-42 | complete | Chrome tabs bridge e2e with fake extension + files provider smoke | tabs/files/chrome/native-host paths, `smoke_tabs.py` |
| P-43 | complete | music integration: `m ` view, rail chip, MPRIS item, unit, CLI through core, demo | P-23 paths |
| P-44 | complete | extension host core (Vicinae/Raycast grammar) | `src/extensions/**`, `providers/extensions.ts`, `EXTENSIONS.md` |
| P-45 | complete | gallery + ask under the wrapper, OpenUI replay, design-lint sweep | `src/ui/**`, `src/openui/**`, `smoke_{gallery,ask}.py` |
| P-46 | complete | cheatsheet smoke + lint + calendar + capacity/sysmon | P-17 paths, `smoke_cheatsheet.py` |
| P-47 | complete | binds, scripts, desktop entries verified; herdr-picker compat; x-scheme-handler | P-20 paths + `{pomodoro,recording-toggle,touchpad-toggle}`, `smoke_scripts.py` |
| P-48 | complete | docs and diagnostics to truth: README/RUNBOOK, doctor/validate/status/listen, MORNING body | P-21/P-05 paths, `test_cli.py` |
| P-49 | complete | performance and budgets: CLI cold start, spawn→ready, RSS, frame loop | `PERF.md`, `perf_budgets.py` |
| P-50 | complete | security and secrets review | `SECURITY.md`, `test_security.py`, `src/security.test.ts` |
| P-51 | complete | completeness critic: SCOPE P0/P1 coverage → GAPS | `docs/gpuix-shell/GAPS.{md,json}` |
| P-52 | deliver | final integrate + deliver: green tree, MORNING final, logical commits, push, draft PR | `**` |

P-52's six commits: docs; scaffold/core/platform; surfaces; music; nix/HM/binds; tests/evidence/docs.
Never committed: `node_modules`, `dist`, `result`, `bun.lock`, fonts, `/run/agenix`.

### 6.3 The runner (`…/scratchpad/runner/`, intact; `wave2/` never generated)

`night.sh` is the driver. Its own guards already skip the completed wave-1 steps: step 1 breaks at once
because `count_notes` ≥ 26 (32 notes); step 2 finds no missing reader; step 3 skips synthesis because
`SCOPE.md`, `ARCHITECTURE.md` and `DESIGN.md` exist and skips the planner because `PLAN.json` exists.
It then runs `gen-wave2.py` (which reads `PLAN.json['packets']` and writes one job prompt per packet
under `wave2/`), the wave-2 phases, the wave-3 phases (`01-integrate`, `02-complete`, `02b-critic`,
`gen-gapfill.py` → `03-gapfill`), and wave 4 (`01-finish`, `02-deliver`). Each job is
`run-job.sh <job.md>`: `claude -p --model <fable|opus> --dangerously-skip-permissions --max-turns N`
with `CLAUDE_CONFIG_DIR=/home/tom/.claude-work` (the cc2 seat), cwd the worktree, transcript to
`<wave>/out/<phase>-<job>.txt`, one `start`/`end rc= bytes=` pair in `runner.log`. `model-policy.sh`
gives 2:1 fable:opus until cc2 Fable ≥ 90 %, then opus. `checkpoint.sh` commits `wip: checkpoint`
every 20 minutes until it sees "NIGHT COMPLETE" in `runner.log`.

The launch (after the fixes in §6.4):

```
R=/tmp/claude-1000/-home-tom-tuesday-oct20/94d008d7-4112-4bf7-92cd-2de4eab69681/scratchpad/runner
mv "$R/runner.log" "$R/runner.log.night1"          # the stale "NIGHT COMPLETE" line would stop checkpoint.sh
nohup "$R/checkpoint.sh" >> "$R/checkpoint.out" 2>&1 &
nohup "$R/night.sh"      >> "$R/night.out"      2>&1 &
tail -f "$R/runner.log"
```

### 6.4 Three mechanical fixes before launch (read from the scripts; the fixes are my recommendation, INFERRED)

1. `gen-wave2.py:8` maps every packet whose stage is not `scaffold` into `wave2/02-build`, so `night.sh`
   would run all 46 remaining packets (build, integrate, complete and deliver) in one `xargs -P 10`
   phase, ignoring PLAN §2's order (P-30 alone, then 21 complete, then P-52 alone). Fix: emit
   `03-integrate`, `04-complete`, `05-deliver` from `p['stage']` and run them in `night.sh` in that
   order (`-P 1`, `-P 10`, `-P 1`), and drop or retarget the pre-PLAN hand-written wave-3/wave-4 jobs
   (10 completion packets, integrator, critic, final integrator, deliverer, written 23:11–23:15 before
   PLAN existed) so they do not run a second, older plan over the same tree. Also lower `-P 10` to the
   plan's "16 at a time" or keep 10; either respects disjoint ownership.
2. `checkpoint.sh` greps the staged diff for `NAVIDROME_PASSWORD=[^ ]`, which matches two prose lines
   in MUSIC.md and two lines of `music/probe/subsonic-get`; every checkpoint will abort until the pattern
   matches a value (for example `NAVIDROME_PASSWORD=[A-Za-z0-9]{8,}` on `+` lines only) or excludes
   those two paths. Also rotate `runner.log` first (above), or `checkpoint.sh` exits on its first tick.
3. `night.sh` checks no return code; add `rc=$?; [ $rc -ne 0 ] && say "… rc=$rc"` after each phase and
   stop the chain when `grep -q "session limit" <out>` so a seat limit is logged as a halt, not as
   "NIGHT COMPLETE". The cc2 seat's 5-hour session cap is the hard constraint: at 11:30Z it was at 8 %
   weekly; budget the run so that the 23 build packets, P-30 and the 21 completion packets fit the
   window, or plan for a second launch after the next reset.

---

## 7. Assumptions that need Tom's word (ASSUMPTIONS.md, 196 lines; the 25 that a builder cannot resolve)

**Stack, repo, process model**

1. `A1` React via `@gpuix/react`, not Solid (BRIEF §3.1; the prior 1,300-line Hyprland shell is Solid).
2. `BOUNDARY:` "SEPARATE project" (R9) read as separate from the agency kit repo, not from dotfiles.
3. `ARCHITECTURE:` a headless `gpuix-shell-core` daemon owns `shell.sock`, Sway IPC, herdr poller, clipboard and the supervisor; overrides `SCOPE:` "the socket router lives in the rail process".
4. `ARCHITECTURE:` overlays are spawned by the core supervisor, not by the CLI; one process per show.
5. `ARCHITECTURE:` weights 500/600 come from `pkgs/anthropic-ui-static.nix` (fontTools instancer, store-only, registered per renderer); departs from `DESIGN:` "never registers font bytes" and from `SCOPE S-007` "registerFont from `~/.local/share/fonts`". Touches the fonts-never-in-git rule.
6. `ARCHITECTURE:` binds are an HM-generated block appended to `sway-local.conf` via `lib.mkAfter`; `binds.conf` untouched; concatenation unverified.
7. `ARCHITECTURE:` `package-lock.json` committed, `bun.lock` ignored, zod 4.6.7 and `@types/bun` 1.3.13 pinned; the tree today has the opposite (`bun.lock` staged, `zod ^4`, `@types/bun latest`).

**Look**

8. `DESIGN (A-30)` corners rounded, `radius.outer` 12 / `radius.row` 8, square one token away; **conflicts with** `SCOPE S-007` "outer surfaces 0 ('square corners'), inner rows 6"; KEYS §8.5 parks it for the morning.
9. Toast anchor top-centre (`DESIGN A-15`, SCOPE §3, KEYS §5.6; Tom 2026-10-11 "top and center not top right") versus BRIEF §3.3 top-right; config key `layout.toast.anchor`.
10. `DESIGN (A-29)` launcher input 16 px (Vicinae font 12 pt), rail chrome 13, rows 14.
11. `DESIGN (A-08)` rail boots collapsed at 56; **conflicts with** `SCOPE §1` "220 expanded (default)".
12. `DESIGN (A-38)` no bottom dock on the Linux head; Mail/CRM/Projects are launcher rows.
13. `DESIGN (A-10)` rail footer order now-playing → pomodoro → recording/privacy → capacity → notifications → Tailscale → network → Bluetooth → volume → battery → clock, inferred from the deleted waybar module set.

**Keys**

14. `KEYS:` `$mod+e` stays nautilus, files on `$mod+Shift+e`; **conflicts with** `SCOPE §22` "power on Mod+Shift+e" (KEYS puts power on `$mod+x`).
15. `KEYS:` `$mod+Shift+grave` rail toggle, `$mod+comma` controls, `$mod+Ctrl+w`/`$mod+Ctrl+b` wifi/bluetooth, `$mod+Ctrl+o` dismiss-all versus `$mod+o` newest (SCOPE §22 had `$mod+o` = dismiss-all). All "chosen by me".
16. `KEYS §4.3` prefix grammar `>` `=` `:` files `@` windows `#` workspaces, with SCOPE S-053's `:` emoji, `/` files, `@` herdr, `♪` demoted to aliases.
17. `KEYS:` `$mod+a` reserved for `ask`; `music:` `$mod+m` / `$mod+Shift+m` proposed, not activated (MUSIC Q2).
18. `KEYS:` `$mod+Ctrl+space` keeps `herdr-picker` with its dmenu swapped to `gpuix-shell dmenu` until the native herdr view is verified in wave 3.

**Behaviour and scope**

19. `SCOPE` / `DESIGN (A-20)` / `BOUNDARY`: controls are per-domain list menus (420 wide, rows 40), never a control-centre grid; page set differs (SCOPE §6 eleven domains, KEYS §5.4 nine, DESIGN §8.6 six).
20. `SCOPE` / `DESIGN (A-23)`: power rows Monitors off / Backlight off / Log out / Reboot / Power off; Suspend behind `power.allowSuspend` (off), no Lock, no Hibernate; `gpuix-shell lock` exits 69; hold duration SCOPE 1.2 s vs DESIGN 1500 ms vs KEYS "~1 s".
21. `SCOPE` / `BOUNDARY`: clipboard is an own store over `wl-paste --watch`, cliphist import later, `wtype` paste injection off.
22. `BOUNDARY` / `SCOPE`: Chrome tab search reuses the Vicinae extension id with an own native host named `com.vicinae.vicinae`; whether Chrome accepts the swap without re-pairing is unverified (S-067).
23. `SCOPE`: polkit agent stays P2 despite the annotated matrix's MUST; settings provider read-only; `ARCHITECTURE:` herdr attention raised by core replaces the unmerged `herdr-attention` script; cheat sheet is P1 in SCOPE and bound in KEYS while DESIGN §9 lists it "later".

**Music and secrets**

24. `music:` `navidrome-credentials.age` is strix-only, so the Zenbook cannot play; `on-client.sh` would stream the credential over SSH stdin into the client's tmpfs for the session (MUSIC Q1: rekey with `clientOnly` is Tom's step); in the demo the credential lives in the renderer process.
25. `music:` scrobbling on by default from the demo (Q5), plays count only via `scrobble submission=true` at min(50 %, 240 s); LRCLIB off (Q3); the account has `playlistRole:false` so "Add to playlist" fails until re-roled (Q4).

Open cross-document disagreements not already listed above (digest A §6): corners (#8), rail boot width
(#11), font bytes (#5), power hold (#20), power rows (#20), power bind (#14), `$mod+o` (#15), prefix
sigils (#16), controls page set (#19), cheat sheet (#23). Toast anchor is now consistent across the
three syntheses (top-centre with the config key) and only BRIEF §3.3 differs.

---

## 8. Measured facts and evidence paths

| Fact | Value | Evidence |
|---|---|---|
| Rail probe (published 0.11.0 binary, no patch, no Nix) | layer `top`, anchor left/top/bottom, exclusiveZone 56, keyboard none, opaque → workspace rect x=56 y=0 w=1384 h=900 on 1440×900; Anthropic Sans 13 renders; "23:41" in AnthropicMono Nerd Font 11 `#70B8FF` | `docs/gpuix-shell/evidence/rail-probe/{rail.tsx,smoke.py,shot.png}` (mtime 23:10:02); BRIEF:176–183 |
| Nix-built repeat of the probe | `{"ok": true, "workspace_rect": {"x": 56, "y": 0, "width": 1384, "height": 900}}` with `LD_LIBRARY_PATH` unset | `wave1/21-nix-packaging-and-checks.md` §5.9 run #8 |
| Nix `buildNpmPackage` probe | rc 0 with `withCheckLibs = true` (213.2 MiB; `bun test` 2 pass in sandbox; `--check-native` → `{"ok":true,"exports":7,"bun":"1.3.13"}`); fails on `libxcb.so.1` without the libs; `prefetch-npm-deps` `sha256-PLas/KzhWF2NvFGTX5Z3OfINGIeGrrVSGse4kAJKI0k=` (pre-lang-core lock) | `wave1/21` (17 runs) |
| GPUIX probes P1–P7 | two surfaces/two roots per process work; exclusiveZone −1 and height-0 stretch work; placement follows the focused output; wtype reaches the surface, Super = `cmd`; variable fonts lose weights without a static instance; transparent rounded overlays render; automation `launch()` works on Linux (P7, 12:10 10-21); `hasTestGpuixRenderer() === false` | `wave1/15-gpuix-0.11-api.md` |
| Load timings | bare bun 81 ms; `--check-native` 102 ms; `--check-dbus` 123 ms; `init()` 92–177 ms; warm first paint ~0.3 s; toast spawn ~150 ms, respawn ~30 ms | `wave1/15`, `wave1/21`, ARCHITECTURE §3 |
| Memory | one 0.11 surface 148.5 MiB; two in one process 163.4 MiB; headless daemons unmeasured | ARCHITECTURE §3.1 |
| Contract files | `bun x tsc --noEmit -p .` rc=0 (0.54 s wall); `bun test src/music/format.test.ts` 5 pass / 0 fail / 24 expect; `node_modules/@gpuix/{native,native-linux-x64-gnu,react}` present | re-run 10-21 by this closure; `music/BUILD-LOG.md` M0 |
| Navidrome (strix → `http://music.internal`, 23:10–23:25, read-only) | 0.63.2, Subsonic 1.16.1, OpenSubsonic (`transcodeOffset`, `formPost`, `songLyrics`, `indexBasedQueue`, `transcoding`, `playbackReport`; no `apiKeyAuthentication`); 38,524 songs, 16,208 albums, 11,118 album artists, 3,966 genres, 1,235 playlists (16,662 entries), 12,352 folders, ~6,000 h / 739 GB; mp3 17,590 / m4a 14,037 / opus 4,724 / flac 1,502 / wav 577; 20,416 in `[Unknown Album]`; 59 songs ever played, 0 starred | `music/03-subsonic-api-live.md`; `music/probe/subsonic-get`; `music/evidence/04-playback/subsonic.mjs` |
| Navidrome latency | `ping` 12 ms; `search3` 13–29 ms (word-prefix AND, diacritics folded, ≥ 2 chars, no infix/typo/rank); empty query 38,524 songs in 3.8 s / 45.8 MB; `getArtists` 0.93 s / 4.6 MB; `getAlbumList2` size cap 500 (33 pages ≈ 6.8 s); `getSimilarSongs2` 2.3–2.9 s; cover art 90–170 ms cold / ~5 ms cached, `max-age=315360000`; raw stream 206 + `Accept-Ranges`, first audio 87–103 ms, seek 4–5 ms; transcoded not seekable; streaming has no side effects | `music/03` |
| mpv engine (strix, `--ao=null`) | mpv 0.41 prints token URLs on stdout and passes them to yt-dlp unless `--ytdl=no --no-terminal --msg-level=all=error`; `--input-ipc-client=fd://3` exits ≤ 0.8 s after parent SIGKILL; `--gapless-audio=yes --audio-samplerate=48000` → 1 ms transitions (weak: 494 ms gap); `time-pos` ~10.3/s, median gap 99 ms, max 543 ms; error latency 486–679 ms; own MPRIS via dbus-next honoured by playerctl; Justice "Ohio" mp3 320k open-to-audio 87 ms, seek 4 ms | `music/04-playback-engine.md`; `music/evidence/04-playback/*` (29 files) |
| Toolchain | bun 1.4.2, node 24.18, npm 11.16 at `/home/tom/today/2026-10-14-convergence-soak/build/{bun,node}/bin`; Sway `/nix/store/04g9x522…-sway-1.12`; grim 1.5.0; 32 CPUs; `bun install` 140 packages, one blocked optional `node-gyp` postinstall | BRIEF:168–174; `music/BUILD-LOG.md` |
| `runtime-test --render-node` | validates a DRM render node, never a card or input device; `shellcheck` clean; `test_render_node.py` 4/4 | `home/dot_local/bin/runtime-test` (+25/−6); `wave1/21` |
| Local model for `ask` | strix `http://127.0.0.1:8731`, `halogen-qwen3.8-flash-next` (three `models-N.json` probes 12:01 10-21) | `wave1/24-local-model-and-openui-generation.md` |
| Seat limits | cc2 session limit 23:57:08 CEST, reply "You've hit your session limit · resets 4:10am (Europe/Paris)" (62 bytes) for 30 jobs; cc weekly 97 % at 23:16Z, reset 09:59Z; at 11:30Z cc 16 %, cc2 8 % | `runner.log` 21:57:08Z–22:03:41Z; `wave4/out/02-deliver-001-commit-push-pr.txt`; NIGHT-LOG |
| Checkpoint false positive | `git diff --cached \| grep "NAVIDROME_PASSWORD=[^ ]"` matches 4 lines (MUSIC.md ×2, `music/probe/subsonic-get` ×2); 0 commits on the branch | re-run by this closure; `runner.log` 21:37:12Z, 21:57:13Z |
| Branch state | 96 staged paths; HEAD dadb1426; `git log main..HEAD` empty; no `origin/experimental/gpuix-shell` | `git status`, `git ls-remote` run by this closure |

---

## 9. What was left unverified, and known risks

By the standing light-verification rule, no verifier pass ran over any synthesis, over the three
closure digests or over this file; each document's own "unverified" section is reproduced in substance.

**SCOPE §23**: SVG path rendering for agent marks (S-045) and whether `layerShell` takes an output
parameter (S-015), both read from notes; Chrome accepting a replacement native host under the Vicinae
name without re-pairing (S-067); `sway-workspace new N` taking a slot number (S-023); BlueZ Agent1
only under `dbus-run-session`, no real pairing (S-127); memory budget per process is a target; nothing
checked against the live Sway or `strix:8731`.

**DESIGN preamble, §2.3, §7.3, A-31**: nothing tested on a compositor except the rail probe and its
Nix repeat; Nerd-glyph rendering in GPUIX untested on this fleet; alpha paint unverified on the toasts
path (hence pre-blended state fills); the variable-weight limitation is read from w1-15.

**KEYS**: 21 INFERRED rows; the two wave-3-gated rewires (`$mod+Ctrl+space` native view, F9
non-interactive `audio-route`); the native-host assumption shared with S-067.

**ARCHITECTURE §23** (15 items, each with a smoke assigned): `splitting: true` keeping `@gpuix/native`
out of the CLI chunk (the bundled `dist/main.js` in w1-21 still had static top-level imports);
`Bun.spawn` with `stdin:"ignore"` plus the spawn-payload file and `surface/ready` timing; the output-pin
dance and its `SEND_TICK` suppression; focus-loss closing while an exclusive layer holds the keyboard;
`keyboardInteractivity: "on-demand"` for controls; swapping the toast window without flicker and the
card-height estimator; `ssh -L` Unix-socket forwarding of the herdr socket; `pw-dump --monitor` as the
audio/privacy source; FTS5 in bun's SQLite; `lib.mkAfter` concatenation of `sway-local.conf`; fontTools
instancing producing faces `registerFont` accepts as "Anthropic Sans"; live re-application of
`GpuixTheme`; memory of the headless daemons; the D-Bus activation file on the client's user bus; the
3-byte sniff (not yet written).

**PLAN §7**: no packet brief was executed; `src/` file names may need renaming by P-00; packet sizing
is an estimate; `PLAN.json` is §6 verbatim and was never consumed.

**BOUNDARY §8**: no independent verifier; quotes come from the notes' transcriptions, some marked
REPORTED; R6–R11 rest on w1-07/08/09 alone; owner placements for rows outside the FP matrix are
INFERRED; byte-compatibility of the three herdr type sources (kit, herdr-web-ui, `shared/herdr-api.generated.ts`)
unchecked; licences read by w1-36 only; no fence test, smoke or Chrome extension presence check ran.

**MUSIC §13**: no client, library, player, UI, demo or smoke beyond the frozen contracts; GPUIX `<img>`
local-path rendering, key delivery through `<input>` and wtype on headless Sway unverified until the
GUI smoke runs; the Zenbook over Tailscale was not measured (only the strix over the closet LAN).

**This closure**: read-only; nothing re-run except `tsc`, the 5-test file, `git status`, `git ls-remote`
and the secret grep. Not verified: whether the overnight revision-1 synthesis files (BOUNDARY 23:57,
KEYS) were complete before the limit (superseded by revision 2); the self-reported post-midnight
revision times of notes 19, 23, 27; the three digests' per-section tallies beyond their reconciliation
with SCOPE:633 and PLAN.json's counts.

**Known risks for the resumed run**

1. The runner's stage flattening (§6.4 #1) would run P-30 and P-52 concurrently with the builders and
   would then run the pre-PLAN wave-3/wave-4 jobs over the same tree. Without the fix the result is
   not the PLAN.
2. The cc2 5-hour session cap: 23 builders at up to 300 turns each, then 21 completion packets; a
   second limit hit mid-wave leaves a half-wired tree and `night.sh` again reports success.
3. `package.json` shape: P-00 must replace the music M0 `package.json` (`zod ^4`, `@types/bun latest`,
   no `build` script, no `package-lock.json`) or the Nix build in P-19/P-41 cannot start (w1-21).
4. The three cross-document conflicts that change what gets built on the first screen (corners, rail
   boot width, power rows/bind) will be resolved by builders from ASSUMPTIONS precedence (ARCHITECTURE
   on engineering, KEYS on keys, DESIGN on pixels, SCOPE on features) unless Tom rules first.
5. Secrets: the music demo on the Zenbook needs the credential streamed over SSH or a `clientOnly`
   rekey; the checkpoint grep as written will keep blocking autosave commits; no credential is in the
   tree today.
6. `@gpuix/native` 0.11.0 limits (no close/hide, no output selector, no input region) make every
   surface a process and the toast stack a respawn; multi-renderer stability was measured for 4–6 s
   only. Any one of these failing on the Zenbook changes the process model, not a packet.

---

## 10. Recommended next step

1. Rule on the ten conflicts in §7 (at least corners, rail boot width, power rows and bind, `$mod+o`, font bytes) by appending `TOM:` lines to ASSUMPTIONS.md; everything else can stay as assumed.
2. Apply the three runner fixes in §6.4 (stage-aware `gen-wave2.py`, value-matching secret grep plus `runner.log` rotation, return-code checks in `night.sh`), then launch with the command in §6.3 on the cc2 seat while its window is fresh.
3. Commit the branch as it is today, before the run, as the first logical commit ("docs(gpuix-shell): wave-1 notes and syntheses" per P-52's list) so the specification is safe regardless of what the build waves do; push `experimental/gpuix-shell`; the draft PR can wait for MORNING.md.
4. Watch `runner.log` for the first `rc=1 bytes=62`; if it appears, stop the chain and relaunch after the reset rather than letting the remaining phases burn through.
5. When P-52 lands, read MORNING.md and GAPS.md, deploy to the Zenbook by flipping `programs.gpuixShell.enable` (never the strix), and judge the rail, launcher, toasts, OSD and switcher smokes against the P0 list in §3.2 before anything else.
