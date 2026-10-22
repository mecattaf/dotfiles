# 02 — Codex "GPUIX pivot" session, part B (second half of Tom's turns)

Reader note for the overnight gpuix-shell build (2026-10-20/21). Read-only extraction; nothing was
run against the live session. Labels: **MEASURED** = I opened the file/line on disk tonight;
**REPORTED** = Codex or one of its subagents claimed it in the transcript (not re-verified);
**INFERRED** = my reading of Tom's intent. Tom's words are quoted verbatim, typos included.

## 1. What this source is

| | |
|---|---|
| File | `/home/tom/.codex/sessions/2026/10/13/rollout-2026-10-13T22-57-08-01a1370e-04d2-7c42-a3e8-7b0968ad155e.jsonl` (19.5 MB, 4,311 lines) |
| Codex thread id | `01a1370e-04d2-7c42-a3e8-7b0968ad155e` (Tom asked "thread id plz" at [197] L574; Codex answered at L582) |
| Span | 2026-10-13 21:04Z → 2026-10-14 01:12Z (23:04 → 03:12 CEST). 34 Tom turns, 90 assistant messages, 496 tool calls, 4 compactions. |
| cwd | `/home/tom/mecattaf/dotfiles`; the work itself landed in the worktree `/home/tom/.wt/hyprland-solid-shell` (branch of dotfiles, **uncommitted**, still present tonight — MEASURED `git status` shows ~30 modified/added files incl. `home/hyprland.nix`, `modules/hyprland.nix`, `pkgs/desktop-shell/`, `design/*`) |
| Format gotcha | This rollout uses the newer Codex schema: Tom's turns are `response_item/message/role=user` (input_text), not `event_msg/user_message`. The shared helper `transcript-text.py` prints **zero** user turns for this file. I wrote `/tmp/claude-1000/-home-tom-tuesday-oct20/94d008d7-4112-4bf7-92cd-2de4eab69681/scratchpad/codex2-text.py` (same flags, plus `--tools`); index numbers `[N]` below are from that tool, `L<n>` is the jsonl line. ~60 % of the second half is `encrypted_content` inter-agent payloads (unreadable); only FINAL_ANSWER payloads and root's own messages are plaintext. |
| My coverage | All 34 Tom turns read; assistant/tool context read in full for turns [637]→[1313] (the second half, 22:34Z onward) and skimmed for [0]→[636] so the first-half rulings that the second half depends on are in context. Part A (another reader) owns the first half in depth. |

What the session is, in one line: Tom's "sacred cows make the best burgers" night. It starts as a
history dig (Aura → Hyprland → GPUIX), becomes a 74-minute Hyprland build, is reverted to Sway at
22:25Z, and then turns into a design-and-mockup factory (Mail, CRM, Projects, Herdr, left rail,
desktop study, Mod+i switcher), a GPUIX-vs-Chrome side-by-side, and four "lineage" investigations
(session titles, Ctrl+K, keystroke memory, Vimium). It ends with a handoff to two Claude Design
sessions. **The desktop-shell package itself was built in the first half under Hyprland and never
reached Tom's screen; what Tom actually saw and loved was the Chrome/Primer preview.**

## 2. Verbatim Tom rulings relevant to the desktop shell

Chronological. UTC timestamps; add 2 h for Paris. Pointers are `[index] L<line>`.

### 2.1 Direction and compositor

- **[4] L9 21:04:11Z** — the opening order: "revisit the chromium aura entire epoch historiically,
  and understandh how it will now be done on hyprland ; and https://gpuix.dev/
  https://github.com/remorses/gpuix https://gpui-kit.com/docs/comparison/". Heuristic given:
  "sacred cows make the best burgers."
- **[54] L155 21:06:46Z** — "this supersedes the whole aura requirement. it even fucking
  correesponds to the solidjsidea i had!!!" → Aura (Chromium Views shell / CUBS) is **dead as a
  requirement**; GPUIX is the realisation of the March-2026 SolidJS shell idea. (INFERRED for the
  builder: the shell is a "SolidJS-style reactive shell with a native renderer"; tonight's React
  choice is a renderer-adapter decision, not a reversal of this.)
- **[142] L407 21:11:34Z** — "hyprland is just sway with animations and best in class blur. for
  terminal: herdr + kitty ; until superlogical releases their terminal. for browser, google chrome."
  → fixed roles: **terminal = herdr + kitty, browser = Google Chrome**; the shell never re-implements
  either.
- **[203] L601 21:52:29Z** — "work deploy massive amounts of compute for htis come on ! impress me!
  all the functionality. become a hyprland expert. and a dotfiles expert."
- **[552] L1802 22:25:30Z** — **the Sway ruling**: "i digress on the hyprland parts, i m sorry. let
  s tick to sway window manager. less effort.. but do list all the hyprland functionality that we're
  'missing out on' in a way so i can decide if i want hat added potentially later or not..." → Sway
  stays; the deferred list exists (§5, `SWAY-COMPARISON.md`). BRIEF.md's "74 minutes" = 21:11Z→22:25Z.

### 2.2 Look, fonts, theme kit

- **[353] L1122 22:03:41Z** — "the first task is to introspect into my existing claude ui, i tried
  replicating the claude managed agents ui , and tyhe claude calendar implementation. first step is
  finailzing the look and aesthetic. i want to use the claude anthropic font, the color scheme and
  selector, and the github primer react theme kit" → aesthetics **before** functionality;
  **Anthropic font + the existing Claude Light/Dark/Noir palettes + their selector + GitHub Primer
  React** are the four named ingredients.
- **[456] L1487 22:16:03Z** — **the acceptance ruling** (what BRIEF.md quotes): "whatever you just
  opened: i love it. this is good enough to also become a functional remplacement to waybar, vicinae
  and mako notifications. drawing insporation from omarchy's implemetnatipn of wayshell in fact."
  What was open (MEASURED, [455] L1480): the **Chrome** preview
  `/home/tom/.wt/hyprland-solid-shell/design/claude-primer/dist/index.html` — managed-agents
  transcript layout + calendar week view + appearance page, real Anthropic Sans/Serif/Mono, real
  Primer React controls, persistent Light/Dark/Noir selector. Codex noted one correction Tom did not
  contest: the managed-agents reference uses **sans headings**; the old kit's serif-heading rule was
  an interpretation ([455]). So: **UI headings = Anthropic Sans**; Serif only for document/prose
  display (the native desktop study uses Serif for the one 26 px hero line, MEASURED desktop.tsx:54).
- **[472] L1536 22:16:59Z** — "we re doing functionality pull from quickshell NOT visuals or
  aesthetics whatsoever" (said while asking for a blur ultracode workflow, which died with Hyprland).
- **[589] L1927 22:30:51Z** — "keep producing clickable things, even if mockups, just making sure
  htat we keep true to the anthropic (colors on github i think? ) theme kit, show me what a menu and
  sidebar etc etc could look. impress me visually. mockups are king here."
- **[837] L2784 23:01:43Z** — the next step after integration: "fully fork github primer (react) and
  have claude design prepare a comprehensive 1:1 kit with everything from anthropic 'as if it was
  designed by anthropic claude 1st party native implementations - bar the font' using those
  technologies that we hvaew proven are good".
- **[913] L3013 23:07:03Z** — "i am expecitng it to be a react (solidjs compat) superset of github
  primer, cloudaflare kumo + cloudflare-os. that can do all the way from my desktop shell to the
  functional desktop that exists. the idea is to keep 'grinding' at a unified set of requirements
  that can outlast any coding language of framework, with react being the real world implementation
  of it" → **React is the real-world implementation; requirements must be framework-independent.**
  This is the strongest pre-tonight support for BRIEF.md decision 1 (React via @gpuix/react).
- **[1117] L3676 23:32:42Z** — "i want a design kit (set of constraints) that is a good enough set in
  order for us to have a claude anthropic-maximalist look 'as if it was done by anthropic claude'
  but for desktop os ; in a way that we can use it in gpuix." Two parallel Claude Design sessions:
  A with Primer React named, B without.

### 2.3 Rail, switcher, herdr

- **[621] L2026 22:33:25Z** — "one more agent: herdr-web-ui with the existing implemetnation.
  similarly, one sway-wired workspace switcher that can be toggled with mod i ; with herdr-provided
  status indicators. only for the top display (consult kanshi config to know which one i m talking
  about, and existing vicinae herdr wrkspaces item as well if needed. sidequest: resurface from notes
  the 'small agents from owui openwebui create session titles for arbitrary')" → **Mod+i = top
  display (eDP-1) only, herdr status glyphs, toggle semantics.** Codex confirmed from kanshi: top =
  eDP-1, bottom = eDP-2 with workspace 10 ([632] L2068).
- **[637] L2081 22:34:24Z** — "one mroe subagent: for ht left bar, i want you to copy the same
  proportions as the views c++ left tab bar that we saw from google chrome." → **the rail geometry
  is Tom's Chrome Views port: 220 / 30 / 12 / 2 / 8** (see §4). This is the origin of the
  "220/30/12/2/8" numbers BRIEF.md attributes to herdr-web-ui.

### 2.4 GPUIX vs Chrome, renderer, data access

- **[957] L3150 23:12:58Z** — "are those demos gpui or google chrome btw?" (Codex: all Chrome; only
  Mod+i was native, via fuzzel). "it s important that you keep working yourself on the high level
  orchestarton while subagents or yours work on the coding implemetnation. keep asssigning work"
- **[1005] L3303 23:17:17Z** — "get 3 subagents to give me side by side implementations in gpuix so
  that i can see them side by side. let s do email app and 'desktop'"
- **[1013] L3323 23:17:51Z** — "you don't expect it to be different looking right? talk to me about
  that a little, i am curious" → the native shell must be **visually indistinguishable** from the
  Chrome/Primer studies; renderer drift is a bug.
- **[1034] L3389 23:19:41Z** — "explain more about why prier react components don't directly become
  native gpuix controls. what that means, and how that changes things for us. gpuix is a cool
  project but we can use it as stylistic inspiration if it's not adapted. talk to me about that
  yourself, it needs steering."
- **[1054] L3454 23:21:38Z** — **the criterion ruling**: "i m not intersted in 'native advantage' .
  performance is not really the thing i m looking for here. 'supplies another renderer' is fine for
  something that' react plus generic compositor functionlaity... vicinae (raycast clone) proves this
  theoretically ; we hae the sway ipc and omarchy's quickshell which you investigated a while back
  did exactly that." → **React + a generic compositor-capability layer, rendered by GPUIX.
  Performance is not an adoption gate.** Codex re-steered accordingly ([1057] L3470): "The shared
  kit is the product. Desktop capabilities sit behind explicit adapters."
- **[1105] L3628 23:27:51Z** — "it should be the 'same complexity' accessing cf-hosted data for gpuix
  'native' windows as it is for chrome --app ones like what you showed me, right:?" → yes; same
  reader modules, same local bridge ([1107], [1204]).
- **[1118] L3678 23:32:42Z** — "i had in mind ... to have an mcp server in codemode that gives claude
  and codex access to allm y personal utiilties like email crm etc. all from one single place"
  (boundary: utilities are NOT the shell's job; matches BRIEF decision 8).
- **[1205] L3947 23:45:17Z** — "one quick note on gpuix that is unfortunate is that it's not
  registering ctrl +\- for zooming ; was that explicitly disabled or what?" → Codex: not disabled,
  just unimplemented in the preview; **Ctrl+= / Ctrl+- / Ctrl+0 interface zoom with reflow** is a
  kit requirement ([1211] L3964). **The gpuix-shell must implement zoom itself.**

### 2.5 Ctrl+K, memory, Vimium (the "AI drives the desktop" thread)

- **[1212] L3971 23:46:43Z** — "one more introspection in ~/notes on the ctrl k contextual menu idea
  i would have had perhaps going up to years ago... this is something that is interesting now that
  it may all be gpuix-controlled ; potentially giving control of my desktop to the ai"
- **[1232] L4041 23:50:16Z** — "recording every single keypress, compacted into one place. see the
  rise of the system1 models (like jev) with the https://github.com/Simen1331/ShowMe deepming
  embedgemma mechanism ; to create the dream desktop envoronment. plus sway window manager's
  multiseating"
- **[1267] L4161 2026-10-14 01:08:44Z** — pasted Gemini chat about agent-tui, then Tom's own
  sentence: "we can design a linear-style unified shortcut based ui, with mneumonics, in a way that
  the claude ai can drive at equivalence, sending in instructins that get passed on to a hci
  implementor, that feels basically as if claude code or grok bot with 'web browsre steering'
  abilities was context-aware. the same way the user can do ctrl k and see a contextual menu of
  sorts.."
- **[1279] L4195 01:09:46Z** — "resruface from notes w subagent in meantime: vimium-based navigation
  concept i had discussed, that must exist somewhere in there, perhpas as leger?" → found: June 9
  "We ll be making it sort of system-wide", June 12 "i love system-wide vimium concept. do what you
  can to do it justice" (REPORTED [1313] L4308, sources in `VIMIUM-LINEAGE.md`).

### 2.6 What the Codex built and what Tom thought of it

| Built (REPORTED unless noted) | Tom's reaction |
|---|---|
| Five-lane history report `reports/From Aura to Hyprland.md` + `research_notes/From Aura to Hyprland/*.md` in the **main** dotfiles checkout ([195]) | "this supersedes the whole aura requirement" [54]; "thread id plz"/"status lz?" — no further comment |
| Hyprland session (`home/hyprland.nix`, `modules/hyprland.nix`, `home/dot_config/hypr/*`) + **`pkgs/desktop-shell`** (Solid + @gpuix/native 0.10.0: bar w/ 32 px exclusive zone, launcher, windows, controls, notifications daemon, toasts, singleton, theme from kitty.conf; 30 tests pass; **never rendered on Tom's screen**, nested-Hyprland smoke crashed on an aquamarine protocol mismatch [339]) | Reverted: "let s tick to sway window manager. less effort" [552]. Codex: "native Solid/GPUIX shell work remains useful on Sway" (SWAY-COMPARISON.md, MEASURED) |
| `design/claude-primer` (Chrome; managed agents + calendar + appearance) | **"i love it"** [456] — this is the accepted baseline |
| `design/claude-mail`, `design/claude-crm`, `design/claude-shell-study`, `design/claude-herdr` (restyled upstream herdr-web-ui demo), `design/claude-rail` (Chrome-proportion rail), suite index served at client `http://127.0.0.1:4187/` then `:4188/?live=1` with a loopback bridge to the Mail/CRM/Projects Workers | No visual verdict in this transcript. Tom's follow-ups were about data ("i hvae lots of cloudflare workers ... use instead of email ; crm and projects backends !" [823]) and about whether they were GPUI ("are those demos gpui or google chrome btw?" [957]) |
| `home/dot_local/bin/sway-workspace-switcher` (fuzzel, Mod+i, eDP-1 only, herdr status) — **live-bound in Tom's running Sway via `swaymsg bindsym` without reload** ([789] L2611, [796]) and staged in `binds.conf` | No verdict in transcript. (Later history per BRIEF: PR #565 `morning-shell` carries this.) |
| `design/gpuix-comparison` — real GPUIX Solid 0.10.0 Mail + Desktop windows, launched side by side on eDP-1 at 720×880 as ordinary toplevels (`gpuix-comparison-mail-20261014.service`, `...-desktop-...`), Desktop reading real Sway workspaces via `platform.ts` | Only comment: **Ctrl+/- zoom missing** [1205]. No aesthetic complaint — consistent with "you don't expect it to be different looking right?" |
| `design/claude-suite/{REQUIREMENTS.md, DESKTOP-REQUIREMENTS.md (41 req.), COMPONENT-COVERAGE.md, CLAUDE-DESIGN-BRIEF.md, DESIGN-SESSION-{A,B}.md, RENDERER-DECISION.md, UTILITY-ACCESS.md, CTRL-K-LINEAGE.md, DESKTOP-MEMORY-PERSPECTIVE.md, VIMIUM-LINEAGE.md, TITLE-LINEAGE.md}` + zips in `~/Downloads/claude-design-session-{,A-,B-}2026-10-14.zip` | Tom asked for them ("mother of all design sessions" [957]); session ended before any verdict. The 10-17 "design-handoff" dig (BRIEF row "Design kit handoff") is the continuation. |

INFERRED for the builder: nothing Tom *saw* was GPUIX-rendered except the two 720×880 comparison
windows; his "i love it" is for the Chrome rendering of Primer + Anthropic fonts + Claude palettes.
The visual target is therefore "Primer controls as rendered by Chrome", reproduced in GPUIX.

## 3. Feature / behaviour inventory

"Where it lives today" = path in `/home/tom/.wt/hyprland-solid-shell` (WT) unless stated; all MEASURED
to exist tonight. Keep/replace/new is relative to the gpuix-shell being built.

| Feature | What exactly (Tom's words → behaviour) | Where it lives today | Keep / replace / new | Notes |
|---|---|---|---|---|
| Left rail (waybar replacement) | 220 px rail, 30 px rows, Chrome Views proportions [637]; workspace list for the top display; herdr status glyph per row; search; rename; add/close; sidebar show/hide (Ctrl+I in the mock) | WT `design/claude-rail/` (Chrome mock, React/Primer); geometry source `/home/tom/mecattaf/views-shell/shell/tabs/layout_constants.cc` | **new** in GPUIX, geometry **keep** | The old `pkgs/desktop-shell` bar is a **top** bar with 32 px exclusive zone (Hyprland era) — do not copy its geometry; BRIEF says "no top bar". |
| Mod+i top-display switcher | Toggle on Mod+i; eDP-1 only ("never falls back to another output"); rows = slots 1–9 ∪ existing top-output workspaces; marker `●` focused / `!` urgent; herdr identity "assigned" when parked projector can't be verified; second Mod+i closes (own socket+flock, no pkill); Esc cancels; typing filters; Enter selects; focus = `focus output` then workspace, with revalidation | WT `home/dot_local/bin/sway-workspace-switcher` (267 lines, imports `herdr-picker` as a module for `projectors/identity/assigned_identity/desktop_lock/quote_sway`) ; bind in WT `home/dot_config/sway/binds.conf` (+2 lines) ; fuzzel added in WT `home/home.nix` | **replace** fuzzel UI with GPUIX overlay; **keep** the row/identity/toggle logic | Mod+i verbatim ruling [621]. Live geometry gotcha: at the time ws 10 was on top and ws 4 on bottom ([712] L2338) → always read Sway, never assume slots. |
| Launcher (vicinae replacement) | "mod+d menu" per BRIEF; Ctrl+K inside owned surfaces; results: applications, workspaces/sessions, actions; ↑↓ Enter Esc; no fake success | WT `pkgs/desktop-shell/{ui.tsx,providers.ts,applications.ts}` (XDG apps via GIO, windows, clipboard history, file search, calculator, theme provider; 12 provider tests) ; native sample in WT `design/gpuix-comparison/desktop.tsx:42,61` | **keep** providers.ts logic (framework-free), **replace** UI | Providers' recorded parity gaps vs Vicinae: Chrome tabs, tray menus, indexed search, calculator conversions, clipboard retention/import ([519] L1687). |
| Notifications (mako replacement) | org.freedesktop.Notifications server; history; actions; replacement ids; expiry; DND; four top-centre toasts sized to content; dismiss vs clear-history vs DND distinguished (SH-08) | WT `pkgs/desktop-shell/{notifications.ts,notifications-daemon.ts,notifications-client.ts}` + 3 test files; `home/dot_local/bin/desktop-notifications` (17-line shim: Hyprland→desktop-shell, else makoctl) | **keep** daemon logic, **replace** toast placement (BRIEF: top-right 390 wide max 4) | Passed a "real private D-Bus test" ([549] L1797) REPORTED. |
| Quick controls | Wi-Fi, Bluetooth, volume, brightness (±10 steps), appearance (3 palettes), battery; "a slider's local movement alone never proves a system change" (SH-09) | WT `design/gpuix-comparison/desktop.tsx:63` (samples); old shell `controls` mode delegates to existing `volume/brightness/media/audio-route/screenshot` scripts | **new** UI, **keep** delegation to scripts | Tom asked tonight for wifi/bluetooth *menus*; this session only has toggles. |
| Calendar popover | Month grid, prev/next, day detail, "Google Calendar" entry; CAL-01: calendar is a **view of Google Calendar** | WT `design/gpuix-comparison/desktop.tsx:64`; `design/claude-primer` week view | **new** (shell shows the clock; the calendar app itself is a utility) | Boundary: BRIEF decision 8. |
| Desktop study window | Top strip 44 px (Desktop · workspaces · Search · clock · bell · Controls), 220 px sidebar, content tabs (Notes/Herdr/Chrome), status strip 30 px, right-anchored 430 px panels | WT `design/gpuix-comparison/desktop.tsx` (67 dense lines) | reference only | It is a *window*, not layer-shell; ignore its chrome, mine its spacing. |
| Sway capability adapter | `snapshot()` → outputs + workspaces on target output (filters `__*`), `focusWorkspace(sel)` with revalidate-before / verify-after, rejects names Sway would misparse, no move command, no auto-create | WT `design/gpuix-comparison/platform.ts` (54 lines) + `platform.test.ts` (26 mocked tests REPORTED) | **keep** verbatim (framework-free TS) | Uses `swaymsg -r -t get_outputs/get_workspaces/command` via execFile. |
| Compositor adapter for capture/brightness/power | fixed read ops + power commands, Sway or Hyprland backend | WT `home/dot_local/bin/desktop-control` (95 lines) | **keep**, drop Hyprland branch | |
| Workspace lifecycle | new/close/detach/rename/restore → `herdr-picker --workspace` ("projectors are parked, never terminated") | WT `home/dot_local/bin/desktop-workspace` (8 lines) | **keep** | |
| Theme following | Read `~/.config/theme/desktop-shell.json` if present, else parse `kitty.conf` colours; `SIGUSR1` reload; fallback = noir | WT `pkgs/desktop-shell/theme.ts` (149 lines; `parsePalette`, `fonts`), switcher `fuzzel_command()` | **keep** the role mapping; BRIEF renames the fragment `gpuix-shell.json` | Role map is in §4. |
| Session titles (OWUI task-model) | One cheap inference per session after first exchange → title + tags, keyed by durable session id, human override survives, shown in rail and herdr UI; **herdr stays the status authority, an LLM never guesses status** | WT `design/claude-suite/TITLE-LINEAGE.md`; origin `~/notes/references/devlogs/1h26/pre-sync/pi-kmux-smalltitlemodel.md:1` | **new** (later) | Requirement AG-06. |
| Ctrl+K contextual palette | Capture context before focus; stable command ids; shared invocation path for buttons/shortcuts/agents; NL composition; outcomes in-kit | WT `design/claude-suite/CTRL-K-LINEAGE.md`; `~/notes/.../december-webshell-groundtruth.md:445`, `june30/morning-thoughts.md:72`, `CUBS-DECISIONS-jun30.md:102` | **new** (phase 2) | "everything-is-a-named-command" registry is the kernel. |
| Vimium-style hints | Hints select visible targets; mnemonics invoke commands; Ctrl+K discovers; hint labels scoped to a view revision | WT `design/claude-suite/VIMIUM-LINEAGE.md` | **new** (phase 2) | Tom: "do what you can to do it justice" (June 12). |
| Activity memory | Keystroke/edit/selection history + ShowMe-style retrieval (EmbeddingGemma 2) + Jev-style ranking + Sway second seat for the agent | WT `design/claude-suite/DESKTOP-MEMORY-PERSPECTIVE.md` | research only | Nothing enabled; secret-field exclusion before persistence. |
| Interface zoom | Ctrl+= / Ctrl+- / Ctrl+0, reflow not just text scale | nowhere (missing in `gpuix-comparison/main.ts:7`) | **new** | Tom's only complaint about the native windows. |
| Hyprland-only features (deferred list) | blur, compositor animations/decorations, layer namespace rules, dwindle/master/scrolling layouts, special-workspace overlay, finger-following gestures, plugin API | WT `tests/hyprland/SWAY-COMPARISON.md` (25 lines) | n/a | Sway keeps tabs/stacks, scratchpad, gestures, VRR, HDR (1.12), layer-shell v5, screencopy. SwayFX noted, not selected. |
| Data bridge | Local gateway holding Worker creds; Chrome and GPUIX share `createMailReader`; future unified code-mode MCP above the services | WT `design/claude-suite/{server.mjs,actions.mjs,UTILITY-ACCESS.md}` | out of scope for the shell | Boundary ruling for BRIEF decision 8. |

## 4. Design values (MEASURED unless noted)

### 4.1 Rail geometry (Tom's Chrome Views port, `design/claude-rail/PROPORTIONS.md`)

| Dimension | Value (logical px) | Source line |
|---|---|---|
| Rail width | **220** | `/home/tom/mecattaf/views-shell/SPEC.md:114` |
| Strip inset | **12** per side, 12 top | `views-shell/shell/tabs/layout_constants.cc:42,44` |
| Row | **196 × 30** | `layout_constants.cc:38`, `unpinned_tab_container_view_layout.cc:31` |
| Row gap | **2** | `unpinned_tab_container_view_layout.cc:19` |
| Row corner radius | **8** | `layout_constants.cc:36` |
| Row content inset | 8 h / 6 v | `vertical_tab_style_views.cc:135`, `layout_constants.cc:30` |
| Icon slot | 16 | `tab_view_vertical_layout.cc:24` |
| Child spacing | 4 | `tab_view_vertical_layout.cc:26` |
| Close affordance | active, hovered or focused rows only | `tab_view_vertical_layout.cc:171` |

Smoke asserts "exact 220/196/30/12/2/8". Status glyphs sit in the 16 px icon slot (mock choice).

### 4.2 Palettes (`design/claude-suite/reference-palette.json`, identical to `design/claude-primer/src/palettes.json` minus ansi/gtk keys; both rendered from `home/themes/*.nix`)

| Token | claude-light | claude-dark | noir |
|---|---|---|---|
| ground.base | #F9F9F7 | #1A1A1A | #000000 |
| ground.raised | #FFFFFF | #20201F | #000000 |
| ground.dim | #F3F3F0 | #151515 | #000000 |
| ground.desktop | #F0EFEC | #20201F | #000000 |
| fg / fgDim | #131313 / #52514E | #EAECF0 / #D3D7DE | #EAECF0 / #D3D7DE |
| comment (dark "muted") | #6E7687 | #818898 | #818898 |
| border.inactive / active / urgent | #D2D1C7 / #A5A49A / #B80A18 | #373735 / #555451 / #F47B85 | same as dark |
| accent (= blue) | #0051C2 | #70B8FF | #70B8FF |
| brand | #D97757 | #D97757 | #D97757 |
| selection.bg / fg | #CDE2FB / #131313 | #264F78 / #EAECF0 | same |
| red / green / orange / yellow | #B80A18 / #008000 / #B24A00 / #A66A00 | #F47B85 / #9BE963 / #FBAD60 / #f9e2af | same |
| magenta / cyan | #8100C2 / #007F80 | #CC7BF4 / #5EEDED | same |

Noir is all-black grounds with the claude-dark ink set — the "hairlines not shadows" rule follows
(`border.inactive` #373735 is the only separator available on #000000).

### 4.3 Role mapping used by the native code (`pkgs/desktop-shell/theme.ts`, `design/gpuix-comparison/desktop.tsx:22`)

```
canvas/background = light ? ground.base : ground.desktop
surface           = ground.raised
subtle            = ground.dim
ink/foreground    = fg
secondary         = fgDim
muted             = light ? fgDim : comment
line/border       = border.inactive
accent            = accent          brand = brand
primary (button)  = light ? #A74B2F : brand ; primaryInk = light ? #FFFFFF : #131313
hover             = border + "55" alpha (old shell)  |  subtle (native study)
fonts             = { sans: "Anthropic Sans", mono: "Anthropic Mono", serif: "Anthropic Serif" }
```
Note the old shell's mono family string is "Anthropic Mono"; BRIEF says the installed family is
"AnthropicMono Nerd Font" — INFERRED: check fontconfig names before pinning.

### 4.4 Sizes used in the accepted-look native study (`design/gpuix-comparison/desktop.tsx`)

- Body text 13 px Anthropic Sans; muted labels 11–12 px; section labels 11 px with 22 px top / 8 px
  bottom padding; panel title 18 px semibold; hero 26 px Anthropic Serif; note body 14 px /
  line-height 24; mono 13 px / line-height 24.
- Control row height **30** (sidebar rows, buttons), launcher rows **40**, search input **40** with
  10 px padding; button padding 8 px h, gap 8, radius **8**, 1 px border (`line`), focus ring = 1 px
  `accent`; selected = `subtle` bg + weight 600; quiet = transparent.
- Top strip **44**, content tab strip **42**, status strip **30**, sidebar **220** with 12 px
  padding, sidebar header row 38; panel **430** wide, radius **10**, padding 20, gap 12, top 20 /
  right 24; dim scrim `#00000025`.
- App rows padding 12 radius 6; range track 5 px radius 3 in `brand`.
- Window: 1000×900 requested, min 500×400, `windowBackground:'opaque'`; narrow mode < 900 px.
- Old Hyprland bar (for contrast only, `pkgs/desktop-shell/ui.tsx`): exclusive zone 32, layer `top`
  for bar / `overlay` for popups, namespace `desktop-shell-<mode>`, buttons 26/32 high radius 6,
  list rows 42/48, body 13, small 11, titles 15/17, panel padding 16 radius 8.

### 4.5 Mod+i switcher rendering (fuzzel; `sway-workspace-switcher:126-135`)

`--anchor=center --output=eDP-1 --font='Anthropic Sans:size=12' --width=56 (chars)
--horizontal-pad=16 --vertical-pad=14 --inner-pad=12 --border-width=1 --border-radius=8
--selection-radius=4 --layer=overlay --keyboard-focus=exclusive --prompt='Workspaces  '
--placeholder='Top display · Herdr status at open'`; colours: bg=ground.raised, text/input/prompt=fg,
placeholder=fgDim, selection=selection.bg/fg, match=brand, border=border.inactive. Rows: `●` focused,
`!` urgent, else space; herdr "assigned" qualifier on unverifiable parked projectors.

### 4.6 Timings (old shell, REPORTED in `pkgs/desktop-shell/README.md`)

Event coalescing 40 ms; reconnect backoff to 10 s; system status refresh 15 s; native-loop liveness
tick 500 ms. No animation durations anywhere (Tom: animations were a Hyprland thing).

## 5. Reusable code and data (exact paths; all MEASURED present tonight)

Worktree root `W = /home/tom/.wt/hyprland-solid-shell` (uncommitted; copy, do not depend on it).

- `W/design/gpuix-comparison/platform.ts` — framework-free Sway capability adapter (54 lines). Lift as-is into `pkgs/gpuix-shell/src/sway/`.
- `W/design/gpuix-comparison/{desktop.tsx,email.tsx,main.ts,build.ts,package-native.py,smoke-native.py,smoke-live.py,README.md}` — the only GPUIX code Tom has seen; `main.ts:7` is the window-options + key-dispatch pattern; `smoke-native.py` is a private-Sway + grim screenshot harness that already honours `runtime-test --render-node`.
- `W/home/dot_local/bin/sway-workspace-switcher` — row building, slot eligibility, identity revalidation, single-instance toggle (lines 38–100, 139–196). Reuse logic, drop fuzzel.
- `W/home/dot_local/bin/{desktop-control,desktop-notifications,desktop-workspace}` — thin adapters.
- `W/pkgs/desktop-shell/{providers.ts,applications.ts,notifications*.ts,singleton.ts,theme.ts,controller.ts}` — launcher providers (XDG via GIO, clipboard, file search, calculator), notifications daemon over dbus-next, singleton socket, theme loader. `controller.ts` is Hyprland-event-socket specific: replace with Sway IPC subscribe.
- `W/pkgs/desktop-shell/default.nix` — buildNpmPackage precedent (npmDepsHash, bun build, autoPatchelf, wrapper LD_LIBRARY_PATH wayland/vulkan/xkbcommon/fontconfig). BRIEF decision 9 points here.
- `W/pkgs/desktop-shell/patches/{gpui-ext-background-effect.patch,README.md}` — unfinished blur patch; irrelevant on stock Sway, keep for the "later" list.
- `W/design/claude-rail/{PROPORTIONS.md,src/,smoke.mjs}` — geometry table + a Playwright smoke that asserts it.
- `W/design/claude-suite/reference-palette.json`, `W/design/claude-primer/src/palettes.json` — palette JSON already in the shape `theme.ts` parses (same shape BRIEF wants for `gpuix-shell.json`).
- `W/design/claude-suite/DESKTOP-REQUIREMENTS.md` — 41 ids: DES-01..07 (appearance/states/keyboard/narrow/fixture-vs-live), **SH-01..10 (shell: menu+launcher+rail+notifications+clock+controls; rail geometry; Mod+i semantics; actual-output membership; revalidation; launcher result classes; notification semantics; quick-control honesty; "usable on stock Sway without blur")**, AG-01..07 (herdr authority, status freshness, titles, speech), MAIL/CRM/PRJ/CAL, CF-01..06. Use SH-* as the acceptance list.
- `W/design/claude-suite/{RENDERER-DECISION.md,CTRL-K-LINEAGE.md,VIMIUM-LINEAGE.md,TITLE-LINEAGE.md,DESKTOP-MEMORY-PERSPECTIVE.md,UTILITY-ACCESS.md}` — steering texts; the Ctrl+K "GPUIX-era contract" (5 points) is directly usable as the launcher spec.
- `W/design/claude-suite/{DESIGN-SESSION-A.md,DESIGN-SESSION-B.md,CLAUDE-DESIGN-BRIEF.md}` and `~/Downloads/claude-design-session-{A,B}-2026-10-14.zip` — the design-kit prompts (A/B differ in exactly one paragraph, B has no "primer").
- `W/tests/hyprland/SWAY-COMPARISON.md` — the deferred-features list Tom asked for.
- `W/design/claude-herdr/` — upstream herdr-web-ui demo restyled (220 px rail, 30 px rows, 2 px gaps, 8 px corners, REPORTED [794]); and the fork at `/home/tom/mecattaf/herdr-web-ui` per BRIEF.
- History: `/home/tom/mecattaf/dotfiles/reports/From Aura to Hyprland.md`, `research_notes/From Aura to Hyprland/{concept_history,chromium_aura,later_transitions,hyprland_architecture,gpuix_solidjs}.md` (written by this session into the **main** checkout — read-only for us).
- Notes lineage pointers (for the Ctrl+K/Vimium phase): `~/notes/references/devlogs/1h26/december-webshell-groundtruth.md:445`; `.../CADE/jun6-cade-deliberation/02-llm-maximalist.md:99`; `.../june30/morning-thoughts.md:72`; `.../june30/CUBS-DECISIONS-jun30.md:102`; `.../june30/noon-chat.md:79,189` ("magnificent" launcher); `.../CADE/june9-cade-stuff/main-chat.md:228`; `.../CADE/cade-june12/morning-work/human-annotation-packet.md:396`; `~/notes/references/knowledge/cloudflare-os/mykonos-2026-08/seance-artifacts/parallel-chat.md:172`; `.../pre-sync/quickshellX-solidjs2-discussion.md:579` (the original SolidJS shell + Linear/Superhuman scope).

## 6. Gaps and unknowns

1. **No Tom verdict on any mockup except [456].** Mail/CRM/rail/desktop-study/herdr/native comparison
   drew no aesthetic comment; "mockups are king" was the brief, not an approval. Treat
   `claude-primer` as accepted and everything else as "in the same language".
2. **GPUIX version drift.** Everything here is `@gpuix/{native,solid}` 0.10.0 + Solid. BRIEF picks
   `@gpuix/react` 0.11.0. The React adapter was "supported upstream, not implemented or tested
   locally" (RENDERER-DECISION.md evidence matrix). No layer-shell surface was ever rendered on Sway
   in this session (the comparison windows were ordinary toplevels; the layer-shell bar only ran in
   the crashed nested-Hyprland test).
3. **Font family name mismatch** ("Anthropic Mono" vs "AnthropicMono Nerd Font") — unverified.
4. **Zoom** is not implemented anywhere; Tom noticed within minutes.
5. **Mod+i live bind** was injected into Tom's running Sway on 10-14 via `swaymsg bindsym` pointing at
   `/home/tom/Downloads/claude-design-review-2026-10-14/switcher/run`; whether it survived later
   reloads/PR #565 is outside this transcript.
6. **Encrypted payloads**: all spawn/followup prompts and most subagent progress are unreadable, so
   subagent-claimed test counts (30 shell tests, 26 adapter tests, 16 switcher fixtures, 12 herdr
   browser checks) are REPORTED only.
7. **Chrome Views port** (`/home/tom/mecattaf/views-shell`) is the geometry authority but is itself
   "title and close only"; icon/alert slots are mock inventions.
8. **Wifi / Bluetooth menus** (tonight's ask) have no precedent here beyond on/off toggles and
   "open their installed controls" in the old shell.
9. **Hyprland worktree is dirty and shared**: `W/home/dot_local/bin/runtime-test` (the `--render-node`
   version BRIEF tells us to copy) shows `MM` in git status — both staged and unstaged edits; copy the
   working-tree version and diff it against main's before trusting it.
10. Session titles, Ctrl+K registry, Vimium hints, activity memory, second seat: all research, zero
    code. Tom framed them as "the dream desktop environment"; they are phase-2 material for the
    launcher, not for tonight's rail/notifications.

---
Unverified by me: anything marked REPORTED; I did not run any test or binary. Written 2026-10-20 by
the wave-1 reader (Fable), read-only except this file.
