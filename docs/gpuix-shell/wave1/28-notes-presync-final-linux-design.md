# 28. Notes repo, pre-sync: FINAL-LINUX-DESIGN, newos concept, the annotated kmux feature list, and the March 2026 "deeply annotated" 280-feature matrix

Reader: one wave-1 agent of the gpuix-shell overnight build (2026-10-20/21). Read-only over
`/home/tom/notes`; this file is the only output. Every claim is tagged MEASURED (I read the line),
REPORTED (the source says so, I did not verify), or INFERRED (my reading). Paths are relative to
`/home/tom/notes/references/devlogs/1h26/` unless absolute. Tom's words are quoted verbatim with his
spelling.

Short answer first. The "very detailed set of rulings with deeply annotated priorities list" Tom
remembers is not in `pre-sync/FINAL-LINUX-DESIGN.md` (that is a 107-line kitty/niri glass colour
note). It is two sibling artifacts the brief's list missed:

- `april-webshell-refs/ANNOTATED-feature-matrix.md` (2026-03-24, 702 lines): 280 features surveyed
  across 16 Quickshell shells, each with a `>` line by Tom reading `MUST` / `SHOULD` / `COULD` /
  `WONT` plus a reason. This is the priorities list. It is reproduced in full in section 3.
- `annotated-kmux-feature-list-v0.md` (2026-03-26, 508 lines, filed at the `1h26/` root, not in
  `pre-sync/`): the kmux stack and architecture list A1..U6, with Tom's `>` rulings on sections A, B,
  C, J2 and L4 (the rest was never annotated). Reproduced in full in section 2.3.

The `grep -ril "ultimate desktop shell|deeply annotated|priorit"` sweep also surfaced
`CADE/cade-june11-idealized/research/ultimate-shell-feature-set.md` and `design/00-IDEAL-TARGET.md`
(2026-06-11): a later, agent-written "ultimate desktop shell" taxonomy (17 domains, 56 capabilities)
with no Tom annotations. Covered in section 1.4 and folded into the table.

---

## 1. What the sources are

### 1.1 The nine assigned files (all MEASURED, read in full)

| File | Lines | Date (content) | What it actually is |
|---|---|---|---|
| `pre-sync/FINAL-LINUX-DESIGN.md` | 107 | undated; Discord chat with "Duncan Rose [niri]" (early 2026) | The "dark glass" recipe: niri `opacity 0.85`, `blur { passes 3; offset 3.7 }`, terminal background `#000000`, noctalia **Monochrome** predefined scheme (four grey levels `#828282 #AAAAAA #CCCCCC #DDDDDD`). First line: "We know exactly how to achieve the ideal dark glass aesthetic on linux. Specifically with niri window manager." (`:1`). Tom's note to self at `:45`: "TO BE ADDED to the long running conversation about the custom coding theme based on cattpuccin mocha that i will be using throughout". |
| `pre-sync/newos-concept.md` | 764 | undated, pre-March 2026 (Fedora Atomic era) | Three stitched chats: shpool-vs-tmux ("shpool does ONE thing: keep PTYs alive", `:22`); Claude Code session-manager patterns (aoe, agent-deck, "extract patterns, build native tooling", `:300`); hooks + SQLite FTS5 memory + Bun observability server. **The ancestor of what herdr now is**: "Filesystem as State" `~/.local/share/claude-sessions/<name>/metadata.json {status, started, worktree}` (`:271-281`). No shell UI content beyond "WebSocket Server (Observability) → Browser" (`:362`). |
| `annotated-kmux-feature-list-v0.md` | 508 | "Generated 2026-03-26. For line-by-line feedback." (`:3`) | Sections A..U of the kmux design, with Tom's `>` rulings on A1..A15, B1..B15, C1..C8, J2, L4. See 2.3. |
| `pre-sync/dotfiles-midapril.md` | 478 | mid-April 2026 (semaphore example dated 2026-04-19, `:279`) | The dotfiles backlog synthesized from the shpool/kmux/colour notes: shpool units, starship indicators, fish OSC 7/133, cliphist-over-SSH clipboard, "kmux as Justfile/Fish Functions" (`:257`), Claude-palette kitty remap, llm-observer.nvim, and a priority table (`:431-451`). |
| `pre-sync/kmux-sidebar-design-experiment.md` | 257 | March 2026 (example `started_at` 2026-03-08, `:66`) | The KMUX sidebar wireframe and the iterative-design playbook: five zones, three-row entry, five status states, data sources table, "purely observational" rule. QML target then (DMS plugin). |
| `pre-sync/NEW-kmux-inspiration.md` | 76 | "from march 16" and "March26" (`:2`, `:51`) | Tom's own link list: difit, arbor (cmux in GPUI), superset, conductor, overstory, manaflow ("likely the closest thing to what i m trying to achieve with a left sidebar", `:30`), DMS PR #1687, symphony SPEC, clui-cc, claude-squad, agent-deck, privacy-dots. |
| `pre-sync/FINAL-CLAUDECODE-COLORS.md` | 329 | March 2026 | The colour investigation: 12 claude.ai syntax colours extracted from DOM, tweakcc's 61 UI keys, the four target themes (`:171-176`), the two-tone diff pattern as a WM theming vocabulary (`:190-207`). |
| `pre-sync/KMUX-LINEAGE.md` | 215 | 2026-07-03 (index pass) | Dated index of the kmux lineage: Era 1 (Mar 1 origin thread, 19 files) vs Era 2 (June, kitty-harness fleet panel fed by pi). Records Tom's ruling "Q18 kmux: live with the ambiguity — dating resolves it" (`:144`). |
| `december-webshell-groundtruth.md` | 492 | consolidated 2026-03-21 from Dec-2025 chats | The QuickshellX + SolidJS + WebChannel "webshell" ground truth: `os.*` namespace, MaterialSurface M1..M5, performance budgets, "Agent workspace mapping: Workspace #0 = orchestrator stream, #1-9 = per-agent context, #F = human focus mode" (`:447-450`). |

### 1.2 Siblings read because they complete the picture (MEASURED unless noted)

| File | Lines | Date | Why it matters here |
|---|---|---|---|
| `april-webshell-refs/ANNOTATED-feature-matrix.md` | 702 | 2026-03-24 ("Session 3: Feature Matrix Annotation", `PREVIOUS-SESSION-handoff.md:109`) | **The deeply annotated priorities list.** 280 rows, each followed by Tom's `> MUST/SHOULD/COULD/WONT ...`. Line 7: "@claude i added my annotations with `>` lines". Its unannotated original is `transient-outputs/feature-matrix-2026-03.md` (diff: only the `@claude` line and one typo, MEASURED). |
| `april-webshell-refs/PREVIOUS-SESSION-handoff.md` | 404 | 2026-03-23..25 | Session 3 summary of the annotation's "Key decisions" (`:122-136`), quoted in 2.2. |
| `april-webshell-refs/TIMELINE.md` | 57 | reconstructed 2026-07-03 | Dated milestones Mar 14 → Apr 5 2026: first QuickshellX+React spike (Mar 14), architecture locked (Mar 22), annotations (Mar 24), REVOLUTION pivot to a Chromium embedder (Mar 27), "COWL" coined (Mar 28), **KMUX sidebar concept born (Apr 4)**. |
| `april-webshell-refs/REVOLUTION-2/revisions/KMUX-SIDEBAR-CONCEPT.md` | 118 | 2026-04-04 | "tmux → cmux → KMUX (everything multiplexer)": a **left-anchored layer-shell sidebar, 280 px**, grouping agent sessions, browser tabs, terminals, generated apps, mapped to niri workspaces. The direct ancestor of tonight's herdr rail. |
| `april-webshell-refs/architecture-decisions-2026-03-22.md` | 540 | 2026-03-22 | The three-process webshell architecture (Rust daemon + quickshellX + SolidJS) and the CCD module `os.claude.*` (`:150-170`). |
| `april-webshell-refs/transient-outputs/tom-repo-notes.md` | 60 | March 2026 | Tom's verbatim notes on every reference shell (DMS "THE BIG ONE", equora "nicest OSD by far", chromeX "aesthetically the closest", dart "lack of rounded borders ... more integrated") and two "Hard constraints" (no matugen, no Material UI). |
| `april-webshell-refs/KMUX-EVALUATION-CRITERIA.md` | 159 | 2026-03-24 | The 11-section checklist for judging agent-session tools; "The Three Questions Every Reference Must Answer" (`:151-159`). |
| `april-webshell-refs/transient-outputs/RETRIEVED-previous-shell-scoping.md` | 794 | recovered 2026-03-24 | The even earlier CEF + GameScope "browser-as-compositor" scoping, **rejected as overengineered** (`:5`); keeps Nyxt buffer/window model, `os.*` contract, "lock is a verb, unlock is not" lineage, launcher-as-HUD-modal. |
| `pre-sync/kmux/KMUX-QUESTIONNAIRE-2026-03-25.md` | 320 | 2026-03-25 | Locked stack and the 6 contradictions / 10 decisions "None of D1–D10 were ever answered on record" (`KMUX-LINEAGE.md:28`). |
| `pre-sync/kmux/kmux-intro-written-in-harness.md`, `pre-sync/kmux/beyond-cmux.md` | 156, 333 | Mar 18..23 | "KMUX is ... a Fedora-based distribution layer, not a single program" (`kmux-intro:7-9`); "The Quickshell sidebar as an intelligence layer" (`beyond-cmux:128`). |
| `pre-sync/SOLIDJS-THEME-SYSTEM.md` | 779 | March 2026 | The full token system behind section N of the kmux list (M2..M5 hex, four text tiers, edges, 50 ms motion, anti-patterns). |
| `CADE/cade-june11-idealized/research/ultimate-shell-feature-set.md`, `design/00-IDEAL-TARGET.md`, `00-VERDICT.md` | 407, 186, 198 | 2026-06-11 | "The Ultimate Desktop Shell: Feature Taxonomy" (agent-written): 17 shell domains + the 56-capability "ideal target" with READ / WRITE-reversible / ACTION-irreversible / SECRET-AUTH tags. No Tom rulings inside; Tom's reframe is reported at `00-VERDICT.md:3-6`. |

Skimmed only (headers / grep): `pre-sync/INTEL.md` (Fedora package manifest), `pre-sync/dotfile-shpool-indicator.md`, `pre-sync/quickshellX-solidjs2-discussion.md` (1568 lines; contains the same Duncan Rose chat at `:1276-1305`), `april-webshell-refs/KMUX-INTEGRATION-SURFACE.md` (the `os.claude`/`os.terminal` stub spec).

### 1.3 Where the two assigned notes Tom named sit in the lineage (INFERRED from TIMELINE + KMUX-LINEAGE)

```
Dec 2025  december-webshell-groundtruth: QuickshellX + SolidJS + WebChannel, os.* spec, workspace #0/#1-9/#F
Feb 2026  newos-concept: shpool, Claude Code hooks, filesystem-as-state (the proto-herdr)
Mar 1     kmux era 1: ccd daemon wrapping Claude Code (long-scoping 01..19)
Mar 22    architecture locked: Rust daemon + quickshellX + SolidJS; CCD module = os.claude
Mar 24    ANNOTATED-feature-matrix: 280 rows, MUST/SHOULD/COULD/WONT   <- the priorities list
Mar 26    annotated-kmux-feature-list-v0: A..U with > rulings           <- the rulings list
Mar 27-28 REVOLUTION: "Redoing quickshell but without the Qt" -> COWL (Chromium Ozone Wayland Layer)
Apr 4     KMUX-SIDEBAR-CONCEPT: left layer-shell sidebar that multiplexes everything
mid-Apr   dotfiles-midapril: "do not write a binary" (kmux = fish functions + semaphore JSON)
Jun 11    CADE idealized: "ultimate shell" 17 domains / 56 capabilities, derived backward
Jun       kitty-harness: "kmux" resurfaces as a fleet panel fed by pi subagents
Jul 3     Tom: "Q18 kmux: live with the ambiguity — dating resolves it"
Oct 2026  herdr is "the centerpiece of dotfiles"; the rail is herdr-fed; this build
```

### 1.4 What was abandoned, and why (MEASURED quotes)

| Abandoned | When | Why, in the source's words |
|---|---|---|
| CEF + GameScope "browser-as-compositor" | before Mar 2026 | "rejected as overengineered ... Building a compositor is a multi-year project" (`RETRIEVED-previous-shell-scoping.md:5,227`). |
| Catppuccin Mocha as palette source | Mar/Apr 2026 | "ditch Catppuccin Mocha as the palette source. Replace the kitty ANSI colors with the 12 extracted Claude.ai syntax colors" (`dotfiles-midapril.md:331`). |
| QtWebEngine as webview via Python bridge | Mar 26 | A9 "> no this is wrong. discard this information"; A12 "> no python, thinking all rust" (`annotated-kmux-feature-list-v0.md:28,33`). |
| The shpool fork (+500 lines) | Mar 26 | J2 "> ABANDONED COMPLETELY" (`:200`). Earlier: "parked — `claude --resume` provides semantic recall > visual scrollback" (D3b, `:115`). |
| ghostty-vt VT parser | Mar | "No ghostty-vt (dropped from scope entirely)" (D3c, `:116`). |
| A kmux binary / ccd daemon for v0.1 | Mar 1 (doc 18) and mid-April | "**do not write a binary.** Every command is a thin wrapper around tools that already have CLIs. The only thing kmux owns is the semaphore metadata format" (`dotfiles-midapril.md:261`). |
| Quickshell/QML itself | Mar 27 | REVOLUTION: "Redoing quickshell but without the Qt" → COWL; later COWL/CUBS/CADE in turn (TIMELINE rows Mar 27..Apr 5; CUBS covered by wave1 file 10). |
| Material You / matugen / cross-app theming | Mar 24 | #181 "> WONT whatsoever: no material or material you (i don't like it); no matugen whatsoever"; #186 "> WONT ... that is what dotfiles are for" (`ANNOTATED-feature-matrix.md:414,424`). |
| Control center / quick settings | Mar 24 | "1.12 ... >> WONT. i do not need a control center. this is not in scope for my project. this applies to 268-280" (`:597`). |
| Multi-compositor support, i18n, desktop widgets, animation speed | Mar 24 | #158 "> WONT. We are building this shell for niri ONLY."; #101 "> DONT i explicitly reject i18n support for now. this is MY shell"; #246 "> WONT. i do not like widgets"; #188 "> WONT ... i would make it none/short for snappiest experience" (`:363,233,552,428`). |
| niri (the compositor of every one of these notes) | Oct 2026 | Outside this corpus: Sway is the only compositor (BRIEF §1). Every niri-specific line below is re-read as Sway. |
| Pi as the agent runtime for the sidebar | Mar 26 | C2 "> no", C4 "> os.claude as the prototype. os.agent is reserved to when we "graduate" from claude code" (`:79,83`). (herdr now owns the agent-session model; see section 3 mapping.) |
| Glass / compositor blur as the aesthetic | Oct 2026 | Outside this corpus: "flat and opaque, hairlines not shadows, no blur, no frost, wallpaper is #000000 solid" (BRIEF §1). B9/B10 and FINAL-LINUX-DESIGN's whole recipe are therefore history, not spec. Noted per row below. |

---

## 2. Verbatim Tom rulings about the desktop shell

### 2.1 Chronological table of the strongest rulings (MEASURED)

| Date | Tom, verbatim | Source |
|---|---|---|
| early 2026 (Discord) | "much appreciated! and i m guessing your terminal has color #000000 ?" ... Duncan: "yep" | `FINAL-LINUX-DESIGN.md:35-39` |
| Mar 2026 | "**DankMaterialShell:** this is THE BIG ONE. likely to be the most feature-rich shell out there and by far." | `tom-repo-notes.md:9` |
| Mar 2026 | "**equora:** ... fancy qsb and fragment shaders for vibrancy etc (something that i explicitly reject in my approach). ... certainly has nicest OSD (volume, brightness) by far" | `tom-repo-notes.md:11` |
| Mar 2026 | "**chromeX:** aesthetically the closest to what i'm trying to achieve: ... a wonderful default dark aesthetic across the launcher, dock, notification, left bar and action center menu + notification." | `tom-repo-notes.md:17` |
| Mar 2026 | "**dart:** ... the lack of rounded borders especially on the left dashboard/clipboard/notification unified pane makes it feel much more.. "integrated" with the wayland system." | `tom-repo-notes.md:19` |
| Mar 2026 | "**Ambxst:** ... TMUX SESSION MANAGER!!! (i'll do the same but with shpool in my case but phenomenal inspiration nonetheless); ocr (... i have my own, local vllm implementation in mind)" | `tom-repo-notes.md:15` |
| Mar 2026 | "**privacy-dots:** ... i want in my case to have the "mic is recording" button to be red-ish" | `tom-repo-notes.md:29` |
| Mar 2026 | "I DO NOT want to use matugen or any other colorscheme manipulation cli tool. This is a final decision." / "Disregard anything that has to do with Material UI (M3 and any extension)." | `tom-repo-notes.md:57-59` |
| Mar 2026 | "**current-dotfiles:** worth looking at so you understand the minimum acceptable shell i'm willing to live with ... i can't get the top bar to behave as layer-shell and free up my main tiled window space when disabled" | `tom-repo-notes.md:45` |
| 2026-03-24 | "MUST, in fact in my concepts i had the workspace switcher as a separate left horizontal bar, whereas all the other modules exist in the top bar." (#27 Workspaces indicator) | `ANNOTATED-feature-matrix.md:75` |
| 2026-03-24 | "MUST, i will in fact have multiple simultaneous bars in my config, and want to be able to toggle one but not the other" (#12) | `:40` |
| 2026-03-24 | "MUST, and very important to have funcioning well with niri; in fact one ipc toggle should control only one bar (in case there are multiple bars)" (#20 IPC bar toggle) | `:56` |
| 2026-03-24 | "MUST, could be useful but more important for me is that i want to toggle bars with a niri keybind (sigint)" (#9 auto-hide) | `:34` |
| 2026-03-24 | "COULD, i really do not care about animations whatsoever" (#23) | `:62` |
| 2026-03-24 | "MUST this one is non-negociable" (#65 Notification daemon) | `:156` |
| 2026-03-24 | "MUST, dms hints overlay philosophy is very desirable" (#77 keyboard nav in notif center) | `:180` |
| 2026-03-24 | "GENERAL NOTE on 1.4 LAUNCHER: my shell's launcher in its ideal form will be visual equivalent to macos' RAYCAST. i found it to be the most powerful feature by far. there was a qt launcher called vicinae that tried to reproduce raycast; i could revisit it. but dankmaterialshell's launcher does a great job at getting close to it. we start with the dms implementation as reference and then decide if we want to go beyond" | `:238` |
| 2026-03-24 | "MUST, it's important for me to have the clipboard history shown in the same aesthetic as the launcher; also making sure that we are displaying images (i use cliphist, prefer not to create special rust functionality as i found DMS reinventing the wheel with their clipboard implementation)" (#86) | `:203` |
| 2026-03-24 | "MUST. an OSD is very imprtant to have. I found the eqsh one to be very nice (which i m using right now)" (#122 Volume OSD) | `:281` |
| 2026-03-24 | "MUST but with a small caveat: i really don't care if the brightness is managed by my shell. ... i would be happy to have that being a toggle i control from niri keybinds. doesn't really have to be fully integrated with the shell if it adds work" (#123) | `:283` |
| 2026-03-24 | "MUST. it is CRUCIAL for me to know if i'm connected to tailscale, and possibly to know what other devices are connected on my tailscale network." (#41 VPN indicator) | `:103` |
| 2026-03-24 | "MUST, in fact i really like the DMS one which made you "hold a key for x seconds with a visual progress bar"; in addition to being able to scroll through them." (#37 Power/Session menu) | `:95` |
| 2026-03-24 | "MUST. i do not like the classic gtk greeter ... we are writting a very nice, very well-done uniform design system. dms and others have proven to me that polkit is implemented and easy to do with regular quickshell. this is low-hanging fruit" (#216 Polkit agent) | `:489` |
| 2026-03-24 | "MUST. OLED mode ie make the black colors #000000 is something that i do by default. ... if by oled you mean something like "a special setting that reduces oled monitor burn-in somehow" then WONT." (#185) | `:422` |
| 2026-03-24 | "COULD but as you know my shell has NO light/dark mode: it's all Dark Glass aesthetic" (#52) | `:125` |
| 2026-03-24 | "COULD far down the line support a single universal dark/light toggle. icebox for now" (#183); "WONT: even if i do eventually add a light mode this should only be toggled manually" (#184) | `:418,420` |
| 2026-03-24 | "SHOULD but the default font, like eqsh, is sanfrancisco mono." (#187 Configurable fonts) | `:426` |
| 2026-03-24 | "COULD but we will do that much later down the line. ... in my case it s a custom shell written for one person, so the utilities/plugins i need are configured from the dotfiles themselves. no need to "enable" plugins or browse through them. to be precise, in my world, an ephemeral pomodoro widget has the same place as the main launcher (there is no hierarchy)" (#200 Plugin config support) | `:452` |
| 2026-03-24 | "SHOULD the pomodoro timer concept is very valuable and i have my own approach for it. ... this will be the first feature i release AFTER base webshell" (#250) | `:560` |
| 2026-03-24 | "SHOULD but with a twist. ... i do NOT want the ocr to be handled by tesseract: it will be handled with qwen 3.5 opensource multimodal llm model ... Backend: HTTP call to llama.cpp server running in a local toolbox container." (#238 OCR) | `:536` |
| 2026-03-24 | "MUST but i use shpool for terminal sessions, not tmux nor zellij. ... requires further specialized scoping" (#241 Terminal session management) | `:542` |
| 2026-03-24 | "WONT. the calendar month grid display will be handled by a bespoke, fullscreen, on-brand calendar app FAR later down the line. ... calendar grids ar not straightforward in qml.. but trivial with web technologies" (#240) | `:540` |
| 2026-03-24 | "WONT. i use github-backed md notes. see no value in having external notepad." (#249) | `:558` |
| 2026-03-24 | "SHOULD; ... the KDE connect is extremely desirable. ... "android phone notification" is extremely desirable" (#252) | `:564` |
| 2026-03-24 | "COULD this functionality is quite secondary. i bypass lockscreen by default on reboot (already implemented in my os with greetd automation); and when i need to rest my desktop i do `systemctl sleep`." (#203 Lockscreen) | `:463` |
| 2026-03-24 | "WONT, we're building a serious shell" (#59 BongoCat) | `:139` |
| 2026-03-26 | A14 Typeface SF Pro: "> MUST and this is not implemented now"; A15 icons: "> should, start with lucide" | `annotated-kmux-feature-list-v0.md:37,39` |
| 2026-03-26 | B1 "One kitty window = one OS window. No splits, no tabs, no multiplexer inside kitty." "> yes" | `:43-44` |
| 2026-03-26 | B2 No TUI: "> technically, no TUI except for pi-mono or pi-agent. but yes no dashboard in terminal" | `:46` |
| 2026-03-26 | B3 Status from structured data: "> yes, in fact must be discussed in depth becaues the way it is now with claude code, in the existing implementation of my focused window indicator of the bar of quickshellx webshell is sufficient, seems like claude code does output the needed titles" | `:48` |
| 2026-03-26 | B6 "Composition over monolith. kitty remote control + niri msg + shpool > custom daemon." "> yes"; B7 "The filesystem IS the API." "> yes" | `:53-56` |
| 2026-03-26 | B9 No CSS blur: "> yes, niri implementation of blur to be noted somewhree externally ..."; B11 one accent `#5B9DFF`: "> yes for now"; B12 50 ms: "> yes for now"; B14 no light theme: "> yes for now" | `:60-70` |
| 2026-03-26 | C1 Claude Code first: "> yes"; C4: "> os.claude as the prototype. os.agent is reserved to when we "graduate" from claude code and then we move on to os.agent for pi" | `:77,83` |
| 2026-03-26 | L4 status dot colours: "> acceptable for now, to be unified later of course" | `:269` |
| 2026-03-26 | B5 thin client: "> should; but for now it s all in server mode (ie local is server) so no need for htis logic now." | `:52` |
| 2026-03-16 | "manaflow ... by the same makers of cmux; likely the closest thing to what i m trying to achieve with a left sidebar" | `NEW-kmux-inspiration.md:29-30` |
| 2026-07-03 | "Q18 kmux: live with the ambiguity — dating resolves it." | `KMUX-LINEAGE.md:144` |

### 2.2 The annotation session's own summary of Tom's decisions (MEASURED, `PREVIOUS-SESSION-handoff.md:122-136`, agent-written, each line traceable to a `>` above)

- "**No control center** (entire section 1.12 = WONT)"
- "**Lockscreen/greeter/idle all iceboxed** (COULD) — greetd automation + systemctl sleep sufficient"
- "**Network/Bluetooth near-100% MUST** — driven by thin-client architecture"
- "**Launcher = Raycast philosophy** — DMS as starting reference, provider/plugin system"
- "**Niri-exclusive** — all multi-compositor features WONT"
- "**No i18n, no matugen, no cross-app theming, no desktop widgets, no animation speed control**"
- "**Polkit agent = MUST** (replaces ugly GTK greeter)"
- "**Power menu = MUST** (DMS hold-to-confirm style)"
- "**Terminal = shpool** (not tmux/zellij)"
- "**Clipboard = cliphist** (not reinventing like DMS)"
- "**OCR = qwen 3.5 multimodal LLM** (not tesseract)"
- "**Tailscale VPN indicator = MUST** (crucial for thin-client awareness)"

### 2.3 The annotated kmux feature list v0, in full (MEASURED, `annotated-kmux-feature-list-v0.md`)

Items with a `>` line carry Tom's ruling verbatim. Items without one were never annotated (the file says "Pending: (1) your line-by-line feedback", `:507`). Line numbers in brackets.

**A. LOCKED STACK (confirm or override)** [`:8-39`]
- A1 Terminal emulator: Kitty (`--single-instance=no`, one window = one OS window, niri tiles) — `> must`
- A2 Compositor: Niri — `> must`
- A3 Session persistence: shpool — `> must`
- A4 Shell UI host: QuickshellX (QML scripting, wlr-layer-shell, WebEngineView) — `> must`
- A5 Frontend framework: SolidJS (v1 stable or v2 beta) — `> must, we will use v1`
- A6 Component primitives: Kobalte — `> this is a new addition that will require further work when we go down the line`
- A7 Build toolchain: bun + vite + vite-plugin-solid — `> must`
- A8 Browser automation: fgp-browser — `> should, this is something that will be handled later entirely`
- A9 Webview: QtWebEngine (CDP at localhost:9222, ~60 lines Python bridge) — `> no this is wrong. discard this information`
- A10 Editor: Neovim (octo.nvim, neogit, diffview.nvim) — `> should, to be done later`
- A11 Daemon language: Rust — `> this is already adopted decision`
- A12 Glue language: Python — `> no python, thinking all rust`
- A13 Database: SQLite via rusqlite with FTS5 / bun:sqlite — `> should, to be done later`
- A14 Typeface: SF Pro Display/Text primary, SF Mono code — `> MUST and this is not implemented now`
- A15 Icons: Phosphor or Lucide, stroke-only, 1.5px weight, 16/18/24px — `> should, start with lucide`

**B. ARCHITECTURE PRINCIPLES** [`:41-72`]
- B1 One kitty window = one OS window. No splits, no tabs, no multiplexer inside kitty. — `> yes`
- B2 No TUI anywhere. — `> technically, no TUI except for pi-mono or pi-agent. but yes no dashboard in terminal`
- B3 Status from structured data (JSONL + hooks), not screen scraping. — `> yes, in fact must be discussed in depth becaues the way it is now with claude code, in the existing implementation of my focused window indicator of the bar of quickshellx webshell is sufficient, seems like claude code does output the needed titles`
- B4 Always-shpool model. — `> yes!`
- B5 Thin client/server split. Server = Strix Halo. Client = Dell XPS. — `> should; but for now it s all in server mode (ie local is server) so no need for htis logic now.`
- B6 Composition over monolith. — `> yes`
- B7 The filesystem IS the API. JSONL + semaphore locks + inotify > RPC daemons. — `> yes`
- B8 All agents run in interactive mode. — `> yes`
- B9 No CSS blur anywhere ever. All blur is compositor-driven. — `> yes, niri implementation of blur to be noted somewhree externally to its own md file because we re still waiting on upstream for that (anyday now)`
- B10 Dark-first: surfaces are solid hex fills, compositor sets window opacity 0.85. — `> yes`
- B11 One accent color: `#5B9DFF`. Monochrome discipline. — `> yes for now`
- B12 One animation duration: 50ms. `cubic-bezier(0.16, 1, 0.3, 1)`. — `> yes for now`
- B13 Animate ONLY opacity and transform. — `> yes for nw`
- B14 No light theme. No theme toggle. — `> yes for now`
- B15 shpool is systemd user service (socket activation). — `> yes and this is already impelmented on my system`

**C. PRIMARY AGENT RUNTIME** [`:74-91`]
- C1 Claude Code first, Pi later — `> yes`
- C2 Pi first — `> no`
- C3 Both from day one — `> well technically both wil lbe installed on day one but we re startign w claude`
- C4 Namespace — `> os.claude as the prototype. os.agent is reserved to when we "graduate" from claude code and then we move on to os.agent for pi`
- C5 CCD speaks one protocol first — `> yes`
- C6 Sidebar data sources differ — `> ok so we start w claude specific`
- C7 Permission models differ — `> start w claude`
- C8 Pi steer/fork/compact vs CC Agent Teams — `> start w claude.`

**D. v0.1 SCOPE** [`:93-131`] (unannotated)
- D1 v0.1 architecture: hook scripts + status files + Python bridge (no daemon). D1a status JSON at `~/.local/share/ccd/status/<session>.json`; D1b `{"status":"working","last_tool":"Edit","ts":...}`; D1e Quickshell reads `sessions.json` via QFileSystemWatcher.
- D2 hook scripts: PreToolUse / PostToolUse / Notification(idle_prompt → `waiting_for_approval` + OSC 99) / Stop.
- D3 NOT in scope: no ccd daemon, no shpool fork, no ghostty-vt, "No agent spawning from sidebar (observe only)", no FTS5, no Pi, no auto-titling, no workspace auto-routing.
- D4 acceptance: sidebar shows name + status dot + last tool; amber on permission request; green on completion; "Click entry → `niri msg action focus-workspace` jumps to agent".

**E. SESSION FSM** [`:133-139`] states `spawning → working → waiting_for_approval → waiting_for_input → idle → error → completed`; signal priority hooks > JSONL > VT > process CPU; env `CCD_SESSION, CCD_SESSION_TYPE, CCD_PARENT, CCD_SOCKET, CCD_VERSION`.

**F. CCD DAEMON (v0.2+)** [`:141-154`] Unix socket `$XDG_RUNTIME_DIR/ccd.sock`, NDJSON; commands `create, list, status, send, peek, kill, subscribe, attach`; ~1250 lines Rust. (unannotated)

**G. AGENT SPAWNING & TOPOLOGY** [`:156-168`] three spawn channels; "Topology is metadata, not architecture"; every agent = own kitty window + shpool session + niri workspace; parent drives children via `kitty @ send-text`; guardrails max_children 5 / 3 per min / depth 2; window title `kmux:<project>:<agent>`. (unannotated)

**H. INTROSPECTION** [`:170-177`] `ccd peek`, `ccd status`, TodoWrite parsing into expandable task lists (Warp pattern), per-workspace fields `workspace_id, cwd, git_branch, claude_state, claude_model, claude_tool, claude_tokens, claude_last_msg, notification_count`. (unannotated)

**I. INPUT INJECTION** [`:179-186`] `kitty @ send-text --match title:`; sidebar "approve" button; 0.3 s delay between send-text and send-key enter. (unannotated)

**J. TERMINAL INFRASTRUCTURE** [`:188-226`]
- J1 shpool (no fork): `WAYLAND_DISPLAY` in config, socket activation, "Cannot create detached sessions", "No concurrent clients per session", protocol passthrough incl. OSC 99.
- J2 shpool fork — `> ABANDONED COMPLETELY`
- J3 Kitty: `scrollback_lines 100000`, `allow_remote_control socket-only`, `listen_on unix:/tmp/kitty.sock`, kitty-scrollback.nvim, "OSC 99 passthrough → kitty desktop notification → niri displays via mako/dunst/swaync".
- J4 untested edge cases.

**K. THIN CLIENT MODEL** [`:228-239`] server Strix Halo; client XPS; "Clipboard: server-side cliphist as authority"; "Shell history: server-side atuin only". (unannotated)

**L. SIDEBAR UX** [`:241-290`]
- L1 Surface: "PanelWindow: 400px right, full height, WlrLayershell Overlay, transparent bg"; visible across all workspaces; toggle `shell ccd toggle`; SolidJS plugin at `/ccd`.
- L2 Five zones: Header (brand + clock + search); Quick spawn (deferred); Workspace list grouped Active / Completed / Detached; Entry detail; Summary bar 32px `N active * N waiting | $total`.
- L3 Entry anatomy: Row 1 status dot + title + model badge ("S4") + time ("12m"); Row 2 tags + diff stat ("+142 -38"); Row 3 context bar 3px blue 0-65% → amber 65-85% → red 85-100%; active entry 2px left border accent + 12% accent fill; click → focus-workspace; subagent nesting 16px indent.
- L4 Status dot colours — `> acceptable for now, to be unified later of course`: Green `#34D399` completed; Blue `#60A5FA` working (pulse 2.5s); Amber `#FBBF24` waiting (border glow 3s); Red `#F87171` error; Gray `rgba(255,255,255,0.25)` detached (entry 50% dimmed).
- L5 Missing sidebar design: expanded entry, search, right-click menu, keyboard nav, empty states, error/reconnection, scrollbar, multi-monitor, collapse persistence, cost format, timeline rendering, permission card UI.

**M. BAR WIDGET** [`:292-297`] CCD indicator in bar: "any agents active? how many waiting? (badge count)"; click toggles sidebar.

**N. DESIGN SYSTEM** [`:299-364`] N1 surfaces M1 transparent / M2 `#0a0a0a` / M3 `#111111` / M4 `#161616` / M5 `#1c1c1c`; N2 text 0.92 / 0.56 / 0.36 / 0.18 / inverse `rgba(0,0,0,0.85)`; N3 accent `#5B9DFF` hover `#74ADFF`, destructive `#F06565`, success `#4ADE80`, warning `#FBBF24`, info `#60A5FA`; N4 border `1px solid rgba(255,255,255,0.10)` + `inset 0 0.5px 0 rgba(255,255,255,0.06)`, shadows only M4+ floating; N5 hover 0.04 / active 0.02 / selected `rgba(91,157,255,0.10)`; N6 shell 13px base, rows 28-36px, 4px unit, 16px max padding; apps 14px; N7 radius 4/6/10/14/9999, heights 28/32/36/44, z base 0 dock 100 bar 200 dropdown 300 overlay 400 modal 500 toast 600 tooltip 700; N8 fourteen anti-patterns ("No CSS blur", "No rgba surfaces", "No white-additive overlays", "No colored text except accent/semantic", "No card-in-card nesting", "No bounce/elastic/spring easing", "No decorative gradients", "No shadows on M2/M3", "No padding over 16px", "No font below 10px or above 28px", "No Inter/Roboto as conscious typeface choice", "No animation over 50ms", "No animating background/border/shadow/layout", "No light theme/theme toggle"). (unannotated; B9..B14 above are the rulings on it)

**O. QUICKSHELLX SHELL FEATURES** [`:366-425`] O1 seven surfaces: Bar (Top, exclusive 40px), Dock, Overlay (launcher, keyboard focus), Notifications (per-screen), OSD (auto-dismiss), Lockscreen (iceboxed), CCD Sidebar (400px right). O2 17 `os.*` namespaces. O6 niri porting of eqsh. O7 firstboot wizard (surface-dots reference). O8 privacy notch (camera/mic via PipeWire; eqsh notch + privacy-dots). (unannotated)

**P. COMPETITOR PATTERNS TO ADOPT** [`:427-445`] cmux keyed status model `set-status <key>`; cmux no-focus-stealing ("socket commands never activate app or move focus unless method is explicitly focus-intent"); cmux env auto-injection `CMUX_WORKSPACE_ID`; dmux worktrees + 11 lifecycle hooks + autopilot; clui-cc EventNormalizer, 3-tier auto-approval, 1.5 s health poll, currentActivity (thinking / executing_tool / writing), virtual scroll; Warp TodoWrite lists + autonomy profiles; Cursor Active/Completed/Detached grouping. (unannotated)

**Q. REJECT** [`:447-457`] cmux GPUI TUI rendering ("We use web-over-compositor"); dmux tmux; LLM-based status detection; clui-cc Electron; HTTP permission server; OpenWebUI as UI; PocketFlow; Homebrew/npm distribution. (unannotated. Note Q1 is reversed tonight: GPUI-class rendering via GPUIX is now the chosen frontend.)

**R. PI AGENT SPECIFICS**, **S. FORCED DECISIONS** (S1 workspace-to-session binding "prerequisite for everything"; S7 "kmux as a dedicated CLI binary is unnecessary"; S11 naming), **T. NVIM INTEGRATION**, **U. PACKAGING** [`:459-503`] unannotated.

---

## 3. Feature inventory table

Legend. **Priority** is Tom's `>` marker verbatim from `ANNOTATED-feature-matrix.md` (row # = that file's row number; line = where the `>` sits). **Surface** names BRIEF §3.2 processes: `rail`, `notifications` (daemon + toasts + OSD), `launcher`, `switcher`, `controls`, `files`, `power`, plus `ask` (OpenUI) and `scripts` (Sway bind → `~/.local/bin/*`). **K/R/N** = keep (exists today in dotfiles, shell wraps it) / replace (shell takes it over) / new / out (Tom's WONT or superseded). Rows are grouped as in the source; "herdr" notes where herdr now holds what the 2026 design gave to CCD / semaphores / niri.

### 3.1 Bar (matrix rows 1..26)

| # | Feature | Exact behaviour (source) | Priority Tom gave | Surface | K/R/N | Notes |
|---|---|---|---|---|---|---|
| 1 | Three-zone bar layout | L/C/R zones | `MUST, this is basic bar config` (:18) | none | out | BRIEF: "no top bar on the Linux head". The rail footer carries clock and status instead (wave1 file 11, §3.1). |
| 2 | Configurable widget arrays per zone | JSON config | `MUST` (:20) | rail | replace | Rail rows come from the theme fragment + herdr, not a widget array. |
| 3 | Widget drag-reorder | settings UI | `COULD, happy to keep it "deterministic" from config` (:22) | — | out | Deterministic from config: matches Nix. |
| 4 | Plugin widget system | BarWidgetRegistry | `MUST, it is important to be able to "turn any functionality" into a bar addition` (:24) | rail | new | INFERRED: a rail "slot" API (status rows under the workspace rows) is the modern form. |
| 5 | Multi-monitor via Variants | per output | `MUST` (:26) | rail, notifications | new | Two heads: rail on eDP-1 only; toasts/OSD on focused output (BRIEF §3.3). |
| 6 | Per-screen widget config | screenPreferences | `MUST` (:28) | rail | new | eDP-1 vs eDP-2 is the only per-screen rule tonight. |
| 7 | 4-way position | T/B/L/R | `MUST` (:30) | rail | keep | Left only; see #27. |
| 8 | Vertical bar layout | purpose-built | `MUST, in fact i have a very specific use case in mind for that.` (:32) | rail | new | The use case is the workspace rail (#27). |
| 9 | Auto-hide with hover reveal | show/hide delays | `MUST, could be useful but more important for me is that i want to toggle bars with a niri keybind (sigint)` (:34) | rail + CLI | new | `gpuix-shell rail toggle` over the socket; Sway bind. Collapsed 56 vs expanded 220 is a separate launch (file 11 §3.1), not an animated hide. |
| 10 | Fullscreen detection auto-hide | hide when a window is fullscreen | `MUST` (:36) | rail | new | Sway IPC `fullscreen_mode` on the focused container. |
| 11 | Click-through mode | region mask | `COULD` (:38) | — | out | |
| 12 | Multiple simultaneous bars | toggle one not the other | `MUST, i will in fact have multiple simultaneous bars in my config, and want to be able to toggle one but not the other` (:40) | rail, task strip | new | One process per surface family already gives independent toggles (BRIEF §3.2). |
| 13 | Integrated dock in bar | | `COULD` (:42) | — | out | App bar is "board only" (file 11 P-01). |
| 14 | Bar style variants | floating/full/islands | `COULD` (:44) | — | out | |
| 15 | Goth/outer corners | | `COULD, but this is less difficult because i use web components` (:46) | — | out | |
| 16 | Per-screen density | compact/normal/comfortable | `COULD, since we have per-screen settings anyway` (:48) | — | out | |
| 17 | Scroll to switch workspace | | `COULD, quite secondary for me` (:50) | rail | new (cheap) | Scroll on rail cycles Mod+1..9; optional. |
| 18 | Scroll to adjust volume on bar | | `COULD, secondary` (:52) | — | out | |
| 19 | Scroll brightness on bar | | `COULD, secondary` (:54) | — | out | |
| 20 | IPC bar toggle | one toggle per bar | `MUST, and very important to have funcioning well with niri; in fact one ipc toggle should control only one bar (in case there are multiple bars)` (:56) | CLI | new | `gpuix-shell rail toggle` / `strip toggle` as distinct verbs. |
| 21 | Shadow/elevation system | | `COULD, quite secondary. conceptually an elevation system is interesting but this should be minimal layershell logic, nothing more` (:58) | all | keep rule | Matches U-05 "no shadows at rest" (file 11). |
| 22 | DPI-aware snapping | Theme.px | `SHOULD because dpi-aware anything is important` (:60) | all | new | GPUIX scale factor; eDP-1/eDP-2 scales differ. Check in smoke tests. |
| 23 | Configurable animation duration | | `COULD, i really do not care about animations whatsoever` (:62) | all | out | Matches U-08: durations times a scale "that can be 0". |
| 24 | Content window separation | | `COULD` (:64) | — | out | |
| 25 | Screen frame integration | | `COULD` (:66) | — | out | |
| 26 | Hot corners | | `SHOULD, niri itself also has hot corner but this one clearly has more potential` (:68) | — | later | Sway has no hot corners; a rail-edge hover could stand in. Not tonight. |

### 3.2 Bar widgets (rows 27..64)

| # | Feature | Exact behaviour | Priority | Surface | K/R/N | Notes |
|---|---|---|---|---|---|---|
| 27 | Workspaces indicator | compositor-agnostic | `MUST, in fact in my concepts i had the workspace switcher as a separate left horizontal bar, whereas all the other modules exist in the top bar.` (:75) | **rail** | new | **This March line is the rail.** Then: niri workspaces + semaphore files. Now: Sway workspaces 1..9 on eDP-1 with herdr workspace names and agent state (BRIEF §1). |
| 28 | Clock | configurable time/date | `MUST, but no need to do anything fancier than configurable time and date. the minimal eqsh one was sufficient.` (:77) | rail footer | new | Footer carries clock and status (file 11 §3.1). |
| 29 | System tray | SNI | `SHOULD, very nice to have but i won't be using it personally` (:79) | — | later | GPUIX has no SNI host; defer. |
| 30 | Battery indicator | UPower, colour change | `MUST` (:81) | rail footer | new | UPower over dbus-next (BRIEF §3.4). |
| 31 | Network/WiFi indicator | ethernet fallback, popup | `MUST` (:83) | rail footer + controls | new | |
| 32 | Bluetooth indicator | | `MUST` (:85) | rail footer + controls | new | |
| 33 | Volume/Audio indicator | | `MUST` (:87) | rail footer + OSD | new | `wpctl`. |
| 34 | Media/MPRIS widget | dynamic show/hide | `MUST` (:89) | rail footer, launcher (music) | new | Navidrome demo via mpv/MPRIS (BRIEF §5). |
| 35 | Notification indicator | unread count, DND | `MUST` (:91) | rail footer | new | Count from the shell's own daemon. |
| 36 | Active/Focused window | title | `MUST` (:93) | rail | new | Sway focused container; B3 above: Claude Code window titles were "sufficient" in March. herdr now gives real state. |
| 37 | Power/Session menu | hold-key with progress bar + scroll list | `MUST, in fact i really like the DMS one which made you "hold a key for x seconds with a visual progress bar"; in addition to being able to scroll through them.` (:95) | **power** | new | Exact behaviour: list you can scroll, plus press-and-hold a letter with a progress bar to confirm. |
| 38 | Launcher button | | `SHOUlD, trivial to add but i won't use it personally` (:97) | rail | new (cheap) | |
| 39 | Privacy indicators (mic/cam/screen) | PipeWire nodes | `MUST, and i'll likely develop a specific widget around it` (:99) | rail footer | new | Tom (tom-repo-notes:29): mic "red-ish". `pw-dump`/`wpctl status` for active capture nodes. |
| 40 | CPU/Memory monitor | | `SHOULD, good to have but i don't intend to use it myself` (:101) | — | later | |
| 41 | VPN indicator | tailscale state + peers | `MUST. it is CRUCIAL for me to know if i'm connected to tailscale, and possibly to know what other devices are connected on my tailscale network. ...` (:103) | rail footer + controls | new | `tailscale status --json`; NAS/strix reachability tripwires exist (AGENTS.md D42). |
| 42 | Keyboard layout | | `COULD, nice to have but i won't be using it` (:105) | — | out | |
| 43 | Weather | | `COULD, nice to have but i won't be using it` (:107) | — | out | |
| 44 | Clipboard button | | `COULD, nice to have but i won't use it` (:109) | — | out | Clipboard lives in the launcher (#86). |
| 45 | Idle inhibitor toggle | | `COULD` (:111) | — | out | |
| 46 | Color picker button | | `COULD, i intend to use colorpicker but with a niri shortcut` (:113) | scripts | keep | `~/.local/bin/colorpicker` exists (BRIEF §2). |
| 47 | System updates count | | `SHOULD, this would be interesting and i would have to build functionality specifically for my fedora atomic system. still, a nice touch` (:115) | — | later | NixOS now; meaning changes (flake input age?). |
| 48 | Audio visualizer | music popup, scroll to seek | `SHOULD, i loved dms' popup for music and its associated "scroll through to skip parts of the song".` (:117) | launcher (music) | new | Seek-by-scroll belongs in the Navidrome demo; visualizer itself is #113/#114 "DONT". |
| 49 | Caps/Lock indicator | | `SHOULD, trivial but i won t use it` (:119) | OSD | keep | `touchpad-toggle` already lights the Duo Caps LED (recent commits). |
| 50 | Global menu bar | macOS-style | `COULD, i did have it but i'm not really using it` (:121) | — | out | |
| 51 | AI button | | `COULD, same as 50 equora has it but i never use it` (:123) | ask | new (bounded) | `gpuix-shell ask` is the OpenUI surface, not a bar button. |
| 52 | Dark mode toggle | | `COULD but as you know my shell has NO light/dark mode: it's all Dark Glass aesthetic` (:125) | theme script | keep | Superseded: noir / claude-dark / claude-light exist and `theme` switches them (BRIEF §1). |
| 53 | Night light toggle | per-monitor gamma | `COULD, i won't use it myself, but do it keeping in mind that this will require special functionality as i use a specific gamma tool wl-gammarelay-rs ...` (:127) | — | out | |
| 54 | Power profile selector | | `COULD, very secondary` (:129) | — | out | |
| 55 | Brightness widget | | `COULD` (:131) | scripts + OSD | keep | `brightness` script. |
| 56 | Microphone widget | | `COULD` (:133) | — | out | |
| 57 | Wallpaper selector | | `COULD, i m not too big on wallpaper changing and other cosmetic trivialities` (:135) | — | out | Wallpaper is `#000000` solid (BRIEF). |
| 58 | Custom IPC button | | `SHOULD` (:137) | rail | new (cheap) | A rail row bound to a shell command. |
| 59 | BongoCat | | `WONT, we're building a serious shell` (:139) | — | out | |
| 60 | Recording indicator | privacy dots | `MUST, i will use that` (:141) | rail footer | new | Same source as #39. |
| 61 | Network speed monitor | | `SHOULD, nice to have, possibly cool to have it toggled when we press the wifi/network button or as standalone` (:143) | controls | later | |
| 62 | Apps dock in bar | | `COULD, wouldn't use it directly` (:145) | — | out | |
| 63 | Notepad button | | `COULD` (:147) | — | out | |
| 64 | Pin button | | `COULD, i prefer toggling things with keybinds` (:149) | — | out | |

### 3.3 Notifications (rows 65..82)

| # | Feature | Exact behaviour | Priority | Surface | K/R/N | Notes |
|---|---|---|---|---|---|---|
| 65 | Notification daemon | own `org.freedesktop.Notifications` | `MUST this one is non-negociable` (:156) | **notifications** | replace (mako) | BRIEF §2: never both mako and the shell daemon. |
| 66 | Configurable popup position | 6 positions, focused-monitor-only | `MUST` (:158) | notifications | new | BRIEF: top-right, 390 wide, max 4. |
| 67 | Notification center / history | Current/History tabs, keyboard nav | `MUST, although the specific aesthetic of it is not clear in my mind.` (:160) | notifications | new | File 11: centre 500 x 650, keyboard exclusive. |
| 68 | App-name grouping | collapsible | `MUST, seems trivial to implement like how DMS did it` (:162) | notifications | new | |
| 69 | Inline action buttons | | `COULD, not necessary to have in the first implementation but hapy to revisit ...` (:164) | notifications | new anyway | The `herdr-sway-context` branch already maps `herdr-attention` to mako actions (BRIEF §2); the daemon must support actions to keep that. |
| 70 | JSON-file history persistence | retention, max count, per urgency | `MUST, useful` (:166) | notifications | new | `$XDG_STATE_HOME/gpuix-shell/notifications.jsonl` (INFERRED path). |
| 71 | Do Not Disturb toggle | | `SHOULD, likely something i toggle with a keybind or a button on bar` (:168) | notifications + CLI | new | PR #571's Mod+o "dismiss notifications" is the nearest live bind. |
| 72 | Rules engine (pattern match) | regex, 5 action types | `MUST, nice to have from DMS` (:170) | notifications | new | Keep tiny: app/summary regex → {hide, silent, urgent, timeout}. |
| 73 | Swipe-to-dismiss | | `COULD, not too urgent, possibly nice ot have as cosmetic later` (:172) | — | out | |
| 74 | Per-urgency timeouts/colours | | `MUST` (:174) | notifications | new | mako theme fragment in `home/themes/default.nix` has the current values to port. |
| 75 | Notification sounds | system sound themes | `SHOULD, dms phenomenal reference` (:176) | notifications | later | Tom at gap table: "i barely expect nofitication sounds anyway" (:640). |
| 76 | Progress indicator (hints.value) | | `COULD, revisit after` (:178) | OSD | new | The `osd` script already sends `notify-send -r` with a progress hint (file 11 §3.2); the daemon must honour `value` to replace it. |
| 77 | Keyboard navigation in centre | hints overlay | `MUST, dms hints overlay philosophy is very desirable` (:180) | notifications | new | Letter hints on rows (Vimium-style, also in RETRIEVED:713). |
| 78 | Lockscreen notification display | | `COULD, to be revisited later, i rarely to never lock my screen` (:182) | — | out | |
| 79 | Privacy mode (hide body) | | `SHOULD, since we re relying mostly on dms implementation as inspiraton` (:184) | notifications | later | |
| 80 | Cross-generation restoration | | `COULD, to be revisited in a second pass` (:186) | — | out | |
| 81 | Image caching for history | | `SHOULD` (:188) | notifications | later | |
| 82 | Flood protection | 20/sec | `MUST, to avoid dangerous or strange behavior on my system` (:190) | notifications | new | Rate-limit per sender. |

### 3.4 Launcher (rows 83..103)

| # | Feature | Exact behaviour | Priority | Surface | K/R/N | Notes |
|---|---|---|---|---|---|---|
| 83 | App search (fuzzy) | fzf/fuzzysort | `MUST` (:197) | **launcher** | replace (vicinae) | |
| 84 | Calculator | qalc | `COULD, nice to have` (:199) | launcher | later | Vicinae has one; parity list (wave 1 vicinae reader) decides. |
| 85 | File search | fd | `MUST, and fd plugin seems sufficiend, dms' dsearch was overkill and having a separate package for that is not desirable` (:201) | launcher | new | `fd` provider, no index daemon. |
| 86 | Clipboard mode in launcher | same aesthetic, images | `MUST, it's important for me to have the clipboard history shown in the same aesthetic as the launcher; also making sure that we are displaying images (i use cliphist, prefer not to create special rust functionality ...)` (:203) | launcher | replace | BRIEF §3.4 says own store via `wl-paste --watch`; Tom's 2026-03 preference was cliphist. Either way: images shown, same rows as launcher, "opening it never pastes" (file 11). |
| 87 | Emoji picker | | `SHOULD, emoji is somehting i have had for years, previously in a handrolled fzf menu, ... trivial to create our own or rip the most performant one` (:205) | launcher | new | |
| 88 | Plugin/provider system | getItems/executeItem | `MUST, dms provider concept is powerful` (:207) | launcher | new | Maps to U-10 "one registry" (file 11). |
| 89 | Categories/tabs | | `SHOULD, noctalia 12 categories is good enough` (:209) | launcher | later | Note Tom 2026-09-11 "i really do not like Tabs" (file 11). Sections, not tabs. |
| 90 | Favourites/pinned | SQLite frequency | `MUST, and caelestia's sqlite frequency is very cool` (:211) | launcher | new | bun:sqlite frecency store. |
| 91 | Usage tracking / frecency | | `SHOULD, same as above` (:213) | launcher | new | |
| 92 | App overrides | | `COULD, but i like to control my .desktop apps from my local share applications in dotfiles so this is a little redundant` (:215) | — | out | Desktop entries live in `home/vicinae.nix` today. |
| 93 | dGPU launch option | | `WONT` (:217) | — | out | |
| 94 | Grid/List/Tile views | | `SHOULD: see my general notes on launcher below` (:219) | launcher | later | |
| 95 | Preview panel | | `COULD, extremely secondary` (:221) | — | out | |
| 96 | Action panel (Ctrl+Tab) | per-item actions | `SHOULD, this is a nice addition that makes our launcher raycast-like` (:223) | launcher | new | Raycast "actions" menu. |
| 97 | Wallpaper picker mode | | `COULD, very secondary` (:225) | — | out | |
| 98 | Web search | | `COULD, explore implementation later if at all (seems redundant with opening a new google chrome tab ...)` (:227) | — | out | |
| 99 | Shell command execution | `>cmd` | `SHOULD, makes us raycast-like` (:229) | launcher | new | |
| 100 | Prefix search modes | | `SHOULD, explore in second iteration` (:231) | launcher | later | |
| 101 | RTL/i18n | | `DONT i explicitly reject i18n support for now. this is MY shell i'm not trying to reinvent the linux shell for the entire world` (:233) | — | out | |
| 102 | App blacklist/hide | | `SHOULD because easy` (:235) | launcher | new (cheap) | |
| 103 | HyprlandFocusGrab dismiss | | `DONT because we're niri wm-exclusive. if there exists a niri alterantive would consider that as COULD` (:237) | launcher | new | Sway: layer-shell `keyboardInteractivity: exclusive` + close on focus loss. |
| — | GENERAL NOTE | | `my shell's launcher in its ideal form will be visual equivalent to macos' RAYCAST. ... there was a qt launcher called vicinae ... we start with the dms implementation as reference and then decide if we want to go beyond` (:238) | launcher | — | Seven months later Vicinae became the installed launcher and tonight's order is to supersede it (BRIEF §5). The Raycast goal is unchanged. |

### 3.5 Audio / media / OSD (rows 104..132)

| # | Feature | Exact behaviour | Priority | Surface | K/R/N | Notes |
|---|---|---|---|---|---|---|
| 104 | PipeWire native audio | | `MUST` (:245) | controls, OSD | new | `wpctl` (BRIEF). |
| 105 | Per-app volume mixer | | `COULD, to be explored later` (:247) | controls | later | |
| 106 | Output/input device picker | pin/sort, aliases | `MUST` (:249) | controls / launcher | replace | `audio-route` script exists (F9 picker, recent commits); the shell draws the same list. |
| 107 | Output cycling via IPC | | `COULD` (:251) | scripts | keep | |
| 108 | Device alias/rename | | `SHOULD, could revisit that, doesnt have to be a part of the first launch` (:253) | — | later | |
| 109 | Volume overdrive >100% | | `DONT explicitly i like to have volume going from 0 to 100; only situation where that's not the case is in vlc media player` (:255) | OSD/controls | rule | Cap at 100. |
| 110 | Volume jump protection | 15% max jump | `COULD, can add later` (:257) | — | later | `volume`/`audio-route` already lift a near-silent stored volume (commit 97ef81a9). |
| 111 | Per-device max volume | | `COULD, add later` (:259) | — | out | |
| 112 | Volume feedback sounds | | `COULD, disabled by default` (:261) | — | out | |
| 113 | Audio spectrum (Cava) | | `DONT i don't care about that` (:263) | — | out | |
| 114 | Audio spectrum (native) | | `DONT i don't care about that` (:265) | — | out | |
| 115 | MPRIS play/pause/next/prev | | `MUST, universal anyway` (:267) | launcher (music), rail footer | new | `media` script exists. |
| 116 | MPRIS seek/position | wave progress bar | `MUST, love the progress bar` (:269) | launcher (music) | new | |
| 117 | MPRIS shuffle/loop | | `MUST` (:271) | launcher (music) | new | |
| 118 | Multi-player management | browser dedup | `SHOULD, explore later` (:273) | — | later | |
| 119 | Synchronized lyrics | lrclib | `COULD` (:275) | — | out | |
| 120 | Player blacklist | | `COULD` (:277) | — | out | |
| 121 | Track art caching | | `SHOULD since dms does it` (:279) | launcher (music) | new | Navidrome cover art cache. |
| 122 | Volume OSD | | `MUST. an OSD is very imprtant to have. I found the eqsh one to be very nice (which i m using right now)` (:281) | **OSD** | replace (`osd` script → mako) | eqsh OSD = the reference look (tom-repo-notes:11 "nicest OSD by far"). |
| 123 | Brightness OSD | | `MUST but with a small caveat: i really don't care if the brightness is managed by my shell. ... doesn't really have to be fully integrated with the shell if it adds work` (:283) | OSD + scripts | keep script, new OSD | "keypress>sway>script execution" (file 11 P-10). |
| 124 | Caps/Num/Scroll lock OSD | | `COULD, revisit that, don't need it at launch` (:285) | OSD | keep | touchpad-toggle OSD exists. |
| 125 | Media playback OSD (album art) | | `SHOULD, since dms has it.` (:287) | OSD | later | |
| 126 | Audio output switch OSD | device name + icon | `SHOULD` (:289) | OSD | new | `audio-route` already notifies; route through OSD slot. |
| 127 | Configurable OSD position | 8 positions | `SHOULD, like the dms 8 positions` (:291) | OSD | new | BRIEF: bottom, margin 96. |
| 128 | Per-type OSD enable/disable | | `COULD but by default no need` (:293) | — | out | |
| 129 | OSD suppression when panel open | | `SHOULD, since dms has it` (:295) | OSD | new | Suppress while launcher/switcher open. |
| 130 | Interactive slider in OSD | | `COULD, since dms has it` (:297) | — | out | |
| 131 | Glass-morphism OSD | | `COULD, if glassmorphism is easy to do with our setup` (:299) | — | out | No glass (BRIEF). |
| 132 | Toast-based OSD | unified with notifications | `SHOULD, must learn more about what this does` (:301) | OSD | new | BRIEF §3.2 puts OSD in the notifications daemon process: this is the tpaau pattern. |

### 3.6 Network / Bluetooth (rows 133..157)

| # | Feature | Priority | Surface | K/R/N | Notes |
|---|---|---|---|---|---|
| 133 | WiFi scan/connect with password | `MUST` (:308) | controls | replace (`fzf-nmcli`) | NetworkManager D-Bus; secrets stay local (CADE tag SECRET/AUTH). |
| 134 | WPA-Enterprise auth | `SHOULD` (:310) | controls | later | |
| 135 | WiFi disconnect | `MUST` (:312) | controls | new | |
| 136 | WiFi radio toggle | `MUST` (:314) | controls | new | |
| 137 | Forget saved network | `MUST` (:316) | controls | new | |
| 138 | Saved network list | `MUST` (:318) | controls | new | |
| 139 | Hidden network connect | `MUST` (:320) | controls | new | |
| 140 | Network info detail | `MUST` (:322) | controls | new | |
| 141 | Ethernet status | `MUST` (:324) | controls | new | |
| 142 | Ethernet detail | `MUST` (:326) | controls | new | |
| 143 | VPN management | `MUST` (:328) | controls | new | |
| 144 | VPN multi-provider | `MUST with special focus on tailscale` (:330) | controls | new | `tailscale up/down/status`. |
| 145 | Network speed monitor | `MUST` (:332) | controls | later | (SHOULD at #61.) |
| 146 | Airplane mode | `MUST` (:334) | controls | new | rfkill. |
| 147 | NM SecretAgent | `MUST` (:336) | controls | later | nm-applet-free secret agent is real work; defer behind nmcli `--ask`. |
| 148 | Bluetooth power toggle | `MUST` (:338) | controls | new | |
| 149 | BT discovery/scan | `MUST` (:340) | controls | new | |
| 150 | BT connect/disconnect | `MUST` (:342) | controls | new | |
| 151 | BT pair/forget | `MUST` (:344) | controls | new | |
| 152 | BT pairing agent (PIN) | `SHOULD` (:346) | controls | later | |
| 153 | BT battery | `SHOULD` (:348) | controls | later | |
| 154 | BT codec switch | `SHOULD` (:350) | — | later | |
| 155 | BT device pinning | `SHOULD` (:352) | controls | later | Magic Trackpad is the one device that matters (AGENTS.md). |
| 156 | BT discoverable toggle | `SHOULD` (:354) | controls | later | |
| 157 | BT RSSI | `SHOULD` (:356) | controls | later | |

Tom's reason for the near-100% MUST here, in the handoff's words: "driven by thin-client architecture" (`PREVIOUS-SESSION-handoff.md:125`). The Zenbook is still the physical seat today (AGENTS.md), so the reason holds.

### 3.7 Compositor integration (rows 158..173), re-read for Sway

| # | Feature | Priority | Surface | K/R/N | Notes |
|---|---|---|---|---|---|
| 158 | Multi-compositor facade | `WONT. We are building this shell for niri ONLY.` (:363) | — | rule | Now: Sway only. Same ruling, new compositor. |
| 159 | Niri IPC | `MUST. Confirmed: Rust daemon uses niri-ipc crate with typed bindings, not the 1500-line QML dual socket pattern.` (:365) | all | replace | Sway i3-ipc socket in-process (BRIEF §3.4). |
| 160 | Config generation (KDL) | `COULD, ... prefer that the niri kdl config remain in chezmoi-backed dotfiles and not in the purview of the shell` (:367) | — | rule | The shell never writes Sway config. |
| 161/162/164 | Hyprland / Sway-i3 / DWL modules | `WONT: we are niri only` (:369,371,375) | — | — | Ironically #162 "Sway/I3 native module" is now the one that exists. |
| 163 | ext-workspace-v1 | `COULD, ext worspace is mostly implemmented in niri as well. i don't care about labwc` (:373) | — | out | Sway IPC suffices. |
| 165 | Workspace overview with thumbnails | `COULD. ... technically feasible — but no existing shell has done it for niri. Not trivial.` (:377) | switcher | later | Mod+i switcher is rows, not thumbnails. |
| 166 | Window drag between workspaces | `COULD. Same as #165` (:379) | — | out | |
| 167 | Window rules GUI | `WONT i don't care about editing window rules with gui` (:381) | — | out | |
| 168 | Scratchpads | `SHOULD this is piri functionality so would like to have it baked in` (:383) | scripts | keep | Sway has native scratchpad. |
| 169 | Window swallow | `SHOULD this is piri functionality so would like to have it baked in` (:385) | — | later | |
| 170 | Animated workspace indicator | `COULD. ... Low priority.` (:387) | rail | out | |
| 171 | Debounced events | `COULD, i like noctalia's 50ms but not sure we need it` (:389) | rail | new | Debounce Sway `workspace`/`window` events 50 ms. |
| 172 | Output config generation | `COULD, for now i use `kanshi` ...` (:391) | — | out | |
| 173 | Niri overview toggle | `MUST, but i think this is just something you feed through the niri config with keybind/ipc` (:393) | switcher | new | Mod+i is the Sway-era equivalent (PR #565). |

### 3.8 Settings / theming / config (rows 174..202)

| # | Feature | Priority | Surface | K/R/N | Notes |
|---|---|---|---|---|---|
| 174 | Dedicated settings GUI | `MUST` (:400) | — | out tonight | INFERRED: superseded by Nix + the theme fragment; Tom's own #200 note says plugins are "configured from the dotfiles themselves". Flag as a gap (section 6). |
| 175 | JSON persistence | `MUST` (:402) | all | new | `~/.config/theme/gpuix-shell.json` (BRIEF §3.5) + XDG state. |
| 176 | Settings search | `MUST` (:404) | — | out | With #174. |
| 177 | Schema migration | `COULD, ... icebox for now` (:406) | — | out | |
| 178 | Config validation | `SHOULD, but has to be something that is not hardcoded - it has to validate the config schema programaticaly` (:408) | all | new | Zod/TS schema for the theme JSON; `bun test` it. |
| 179 | Presets/profiles | `COULD, much later ... icebox for now` (:410) | — | out | |
| 180 | First-run wizard | `SHOULD, in fact this is a` (:412, sentence cut off in source) | — | out | |
| 181 | Material You / matugen | `WONT whatsoever: no material or material you (i don't like it); no matugen whatsoever as I explained we do not have a strict colorscheme we follow a standard minimal css token` (:414) | — | rule | |
| 182 | Predefined colour schemes | `WONT in the sense that we have only one predefined colorscheme` (:416) | theme | superseded | Three now (noir, claude-dark, claude-light). |
| 183 | Dark/light toggle | `COULD far down the line ... icebox for now` (:418) | theme script | keep | Exists (`theme`). |
| 184 | Auto dark/light | `WONT: even if i do eventually add a light mode this should only be toggled manually` (:420) | — | rule | Manual only. |
| 185 | OLED mode | `MUST. OLED mode ie make the black colors #000000 is something that i do by default. ...` (:422) | theme | keep | noir = OLED black. |
| 186 | Cross-app theming | `WONT. ... i do not need help managing my gtk or qt theme etc. that is what dotfiles are for.` (:424) | — | rule | |
| 187 | Configurable fonts | `SHOULD but the default font, like eqsh, is sanfrancisco mono.` (:426) | theme | superseded | Anthropic Sans / Serif / Mono now (BRIEF). |
| 188 | Animation speed control | `WONT. ... i would make it none/short for snappiest experience` (:428) | — | rule | |
| 189 | Transparency/opacity | `SHOULD. Compositor (niri) owns blur ...; CSS just sets background-color alpha. ... Trivial once design tokens exist.` (:430) | — | superseded | Opaque now. |
| 190 | Animated colour transitions | `WONT. no need` (:432) | — | rule | Theme switch is a hard swap. |
| 191..193 | Wallpaper picker / per-monitor / fill | `SHOULD because we are indeed controlling the monitor from quickshell side of things`, `SHOULD`, `SHOULD` (:434-438) | — | out | Wallpaper `#000000`. |
| 194 | Parallax | `WONT i explicltly don't need parallax because it makes me dizzy` (:440) | — | rule | |
| 195 | Wallpaper slideshow | `COULD much later` (:442) | — | out | |
| 196 | Procedural sky | `WONT too fancy` (:444) | — | out | |
| 197 | i18n | `WONT no i18n whatsoever, shell is always in english.` (:446) | — | rule | |
| 198 | Per-monitor config overrides | `COULD but again we manage config with kanshi` (:448) | — | out | |
| 199 | IPC config changes | `SHOULD` (:450) | CLI | new | `gpuix-shell theme reload` etc. |
| 200 | Plugin config support | `COULD ... in my case it s a custom shell written for one person ... an ephemeral pomodoro widget has the same place as the main launcher (there is no hierarchy)` (:452) | — | rule | Flat registry of surfaces; no plugin store. |
| 201 | Config versioning | `COULD in the future` (:454) | — | out | |
| 202 | Gradient/halftone | `WONT` (:456) | — | out | |

### 3.9 Session / security / idle (rows 203..232)

| # | Feature | Priority | Surface | K/R/N |
|---|---|---|---|---|
| 203..215 | Lockscreen, PAM, fprintd, U2F, virtual keyboard, lock media/notifs/weather, shake, greeter, greeter user/session selection | `COULD this functionality is quite secondary. i bypass lockscreen by default on reboot (already implemented in my os with greetd automation); and when i need to rest my desktop i do `systemctl sleep`. ... icebox for now` (:463) and "COULD, icebox for now, like above" for each; #212 video screensaver `WONT, too fancy` | — | out |
| 216 | Polkit agent | `MUST. i do not like the classic gtk greeter ... this is low-hanging fruit` (:489) | **power** (INFERRED home) or own tiny surface | new | GPUIX has no polkit binding; a `polkit-agent` process speaking `org.freedesktop.PolicyKit1.AuthenticationAgent` over dbus-next plus a kit-styled prompt window. Real work; flag. |
| 217 | Polkit fingerprint | `SHOULD, not vital for now but might as well` (:491) | — | later |
| 218 | Power menu | `MUST and in fact i want to mention that i like the new DMS powermenu the most with the ability to scroll/select through a list AND press and hold a given key to get the desired action` (:493) | **power** | new |
| 219 | Hibernate detection | `SHOULD, low hanging fruit` (:495) | power | new |
| 220 | Suspend-then-hibernate | `SHOULD, low hanging fruit` (:497) | power | new |
| 221 | Userspace reboot | `COULD, icebox` (:499) | — | out |
| 222 | Confirmation dialog | `COULD if i find this to be useful ... icebox` (:501) | power | covered by hold-to-confirm |
| 223 | Compositor-agnostic logout | `WONT. the webshell project is exclusive to niri window manager` (:503) | power | rule (Sway `exit`) |
| 224 | Multi-compositor session detection | `WONT` (:505) | — | out |
| 225..232 | Idle inhibitor, idle monitor, per-AC timeouts, fade-to-lock, custom idle commands, inhibit-when-audio, lock-before-sleep, caffeine | `COULD the entire idle management suite is not so important for me, i prefer to icebox for now. this applies to 225-232 inclusive` (:508) | — | out |

### 3.10 Utilities (rows 233..267)

| # | Feature | Priority | Surface | K/R/N | Notes |
|---|---|---|---|---|---|
| 233 | Clipboard manager | `MUST the clipboard manager is very important to me. note however that i use cliphist currently. i discuss the specifics of my implementation separately` (:526) | launcher | replace | See #86; `dotfiles-midapril.md:164-220` is the separate discussion (server-side cliphist as authority). |
| 234 | Screenshots | `WONT because existing niri window manager is sufficient` (:528) | scripts | keep | `screenshot` script (grim/slurp). |
| 235 | Screen recording | `COULD ... i already use OBS Studio (as flatpak) to record screen` (:530) | — | out | |
| 236 | Screenshot editor | `WONT the builtin niri screenshot functionality is sufficient for me` (:532) | — | out | |
| 237 | Color picker | `MUST but Color picker currently since i use niri window manager the screenshot tool exists and is sufficient` (:534) | scripts | keep | `colorpicker` script. |
| 238 | OCR | `SHOULD but with a twist. ... qwen 3.5 opensource multimodal llm ... HTTP call to llama.cpp server running in a local toolbox container.` (:536) | scripts → `ask` | later | Today: Halogen Flash at strix:8731 (OpenAI-compatible, vision projector) is the OCR backend (AGENTS.md handwriting intake). A `screenshot → model → clipboard` script is cheap; not tonight. |
| 239 | Calendar with events | `SHOULD keep this idea for later` (:538) | — | out | Boundary: calendar is a shared utility, not shell (BRIEF §3.8). |
| 240 | Calendar grid | `WONT. ... bespoke, fullscreen, on-brand calendar app FAR later` (:540) | — | out | |
| 241 | Terminal session management | `MUST but i use shpool for terminal sessions, not tmux nor zellij. ... requires further specialized scoping` (:542) | **rail / switcher** | replace | **herdr is the specialized scoping's answer.** herdr workspaces are the sessions; the rail is the Ambxst "tmux session manager" Tom admired, with herdr instead of tmux/shpool. |
| 242 | Power menu | `MUST, i believe i already discussed this earlier` (:544) | power | new | |
| 243 | Night light / gamma | `WONT, my gamma control and night light is set once and not from the shell. skip entirely` (:546) | — | rule | |
| 244 | Weather | `COULD. very secondary ...` (:548) | — | out | |
| 245 | System monitoring | `COULD. very secondary ...` (:550) | — | out | |
| 246 | Desktop widgets | `WONT. i do not like widgets` (:552) | — | rule | |
| 247 | AI assistant integration | `COULD but much later down the line. i do not need an ai integration the way it is done in the reference qml shells. i have some ideas here so not marking this as won't` (:554) | ask | new (bounded) | The OpenUI `ask` surface is "some ideas", seven months later. |
| 248 | Update checker | `COULD far later ...` (:556) | — | out | |
| 249 | Notes/notepad | `WONT. i use github-backed md notes.` (:558) | — | rule | |
| 250 | Pomodoro/timer | `SHOULD the pomodoro timer concept is very valuable and i have my own approach for it. ... this will be the first feature i release AFTER base webshell` (:560) | OSD / rail footer | keep + new | `pomodoro` script exists (BRIEF §2); the shell shows its state. |
| 251 | Docker/Podman management | `SHOULD Container management is very desirable on my system, i expand on thsi a little later` (:562) | — | later | #263: "extending to see running systemd services and quadlets". Substrate/Gufo units are the modern target. |
| 252 | KDE Connect | `SHOULD; ... "android phone notification" is extremely desirable` (:564) | notifications | later | KDE Connect/Valent posts to the notification bus; the daemon gets it for free once it owns the bus. |
| 253 | QR scanner | `COULD because easy but not urgent, ocebox` (:566) | — | out | |
| 254 | Google Lens | `WONT` (:568) | — | out | |
| 255 | Greetd greeter | `COULD but icebox` (:570) | — | out | |
| 256 | Polkit agent | `MUST this one is important` (:572) | see #216 | new | |
| 257..259 | Screen pin / measurement / palette extraction | `WONT` ×3 (:574-578) | — | out | |
| 260 | Webcam mirror | `COULD ... icebox for now` (:580) | — | out | |
| 261 | Shutdown timer | `WONT` (:582) | — | out | |
| 262 | Printer management | `COULD becaues it's "free" ... icebox for now because i don't use a printer at the moment` (:584) | — | out | (Tom prints now via paper-daemon, a strix utility, not the shell.) |
| 263 | Process manager | `COULD later down the line. ... extending to see running systemd services and quadlets` (:586) | — | later | |
| 264 | Changelog viewer | `WONT` (:588) | — | out | |
| 265 | Onboarding wizard | `MUST but this one will require specific scoping work before i configure it` (:590) | — | out | Single-user Nix machine; no first-run. |
| 266 | Dependency doctor | `COULD later on` (:592) | — | out | |
| 267 | SDDM theme | `WONT i do not use SSDM whatsoever. i use a super minimal greetd implmmentation` (:594) | — | out | |

### 3.11 Quick settings / control center (rows 268..280)

Tom: "`>> WONT. i do not need a control center. this is not in scope for my project. this applies to 268-280`" (:597). Rows 268..280: quick settings panel, volume/brightness sliders, WiFi/BT/DND/dark/power-profile/night-light/caffeine toggles, media player, recording/screenshot buttons.

Tension with tonight's BRIEF §3.2 `gpuix-shell controls` (quick settings) and file 11 §3.1 `a.quick-controls` ("optional ... never required"). Resolution (INFERRED, consistent with both): WiFi and Bluetooth pickers (#133..#157, MUST) are *menus opened by a bind or from the launcher*, not a persistent control center panel. Keep `controls` as a launcher-reachable menu family, no toggle grid.

### 3.12 Gap analysis rows (`:617-654`)

| Gap | Priority | Notes |
|---|---|---|
| Hotspot creation, Scheduled DND, Inline reply, FTS notification history, Brightness without CLI, Notification grouping by urgency, Notification snooze, Per-app sounds, IME, Screen reader, Multi-user, Spatial audio, HDR | `WONT` each (:624-652) | "WONT; i barely expect nofitication sounds anyway" (:640); "WONT, i do not care much for hdr" (:652). |
| Native clipboard manager (no cliphist) | `COULD. discussed externally. to be revisited later. could convince me to move away from cliphist` (:634) | BRIEF §3.4's own `wl-paste --watch` store is exactly this. |
| Calendar event creation | `COULD but much much further down the line` (:642) | out (boundary) |
| Touch/gesture | `COULD but much later ... I have `lisgd` installed ... icebox maximally` (:654) | out |

Section 3 "Plugin Model Validation" (`:658-701`): `> to be reevaluated later`. Its summary ("~70% of features are pure frontend plugins ... ~20% need Rust daemon ... ~10% are Quickshell-native singletons", `:697-699`) maps tonight to: ~70% React in GPUIX, ~20% CLI/D-Bus adapters in the same TypeScript process (dbus-next, wpctl, nmcli, bluetoothctl), ~10% that had no GPUIX binding (SNI tray, polkit, session lock, screencopy) and are the real gaps (section 6).

### 3.13 The kmux sidebar rows (from `annotated-kmux-feature-list-v0.md` L, M and `kmux-sidebar-design-experiment.md`), mapped to the herdr rail

| Item | Exact behaviour then | Priority then | Surface now | K/R/N | herdr takes the role of |
|---|---|---|---|---|---|
| L1 surface | right, 400 px, overlay, transparent; visible on all workspaces; `shell ccd toggle` | locked | **rail** (left, 220/56, layer top, exclusive) | replace | Side flipped by Apr 4 (KMUX-SIDEBAR-CONCEPT: "left-anchored ... 280px") and by Tom 10-07 ("the only thing that would have been useful is a left sidebar"). |
| L2 zones | Header (brand+clock+search) / Quick spawn / grouped list / entry detail / summary bar `N active * N waiting \| $total` | locked | rail: rows 1..9 + footer (clock, status) | replace | Header search → launcher; summary bar → footer counts from `herdr agent list`. |
| L2c grouping | Active / Completed / Detached | locked ("Cursor pattern") | rail: fixed slots 1..9 | replace | Slots are Sway workspaces; grouping becomes the status glyph, not sections. |
| L3 entry rows | dot + title + model badge + time / tags + diff stat / 3 px context bar | locked | rail session-row (file 11 `a.session-row`) | replace | herdr workspace name + agent status; model badge and context bar are herdr snapshot fields if present (`herdr api schema`). |
| L3e click | `niri msg action focus-workspace` | locked | `swaymsg workspace N` / `herdr workspace focus` | replace | **sidebar never creates or destroys anything** ("purely observational", design-experiment:27) = BRIEF "read-only and acts through Sway". |
| L4 status dots | green `#34D399` done, blue `#60A5FA` working, amber `#FBBF24` waiting, red `#F87171` error, gray detached | `> acceptable for now, to be unified later of course` | rail | replace | **Unified now**: herdr's five glyphs blocked ◉ / working ◐ / done ● / idle ✓ / unknown ○ (BRIEF §1), colours from the theme fragment per U-03 (word + mark, status hue only beside a state word). |
| L3f subagents | 16 px indent + connector | locked | — | out | herdr has no parent/child in the rail today; D5 topology was never decided (questionnaire). |
| L5 missing | expanded entry, search, context menu, keyboard nav, empty/error states, multi-monitor, cost | open | switcher (Mod+i) | new | Mod+i switcher = "rename and reorder by keyboard" (file 11). Empty/disconnected states are U-04. |
| M bar widget | CCD indicator: active count + waiting badge; click toggles sidebar | locked | rail footer | replace | Waiting count = herdr blocked ◉ count. |
| Data sources (design-experiment:35-50) | niri event-stream, semaphore lock files, OSC 99, `.title` files, JSONL tail, `git diff --stat`, `shpool list` | locked | `swaymsg -t subscribe`, `herdr api snapshot`, `herdr workspace list`, `herdr notification show` | replace | **One source instead of seven.** herdr owns session identity, status, title, notification. |
| Title generation (design-experiment:72-80) | pi extension → cheap model → `.title` → `niri msg set-workspace-name` | locked | herdr workspace names | replace | herdr names workspaces; the rail shows them. |
| D4g / G3 | every agent = kitty window + shpool session + niri workspace | locked | one herdr workspace = one kitty projector = one Sway workspace | keep (as herdr) | The March triple is tonight's triple with herdr in shpool's seat (BRIEF §1). |
| B7 | "The filesystem IS the API" | `> yes` | `herdr api snapshot` | superseded | herdr's socket + CLI replace semaphore JSON; the *spirit* (structured state, no scraping, B3) is intact. |
| I4 | sidebar "approve" button | locked | — | gap | herdr `blocked ◉` is shown; answering happens in the kitty projector. `herdr-attention` → Sway urgency (branch c1a49b99) is the current bridge. |
| P3 cmux no-focus-stealing | socket commands never move focus unless focus-intent | adopt | all | keep rule | = U-09 "Looking is free, acting is declared". |

---

## 4. Design values (what the sources say the shell should feel like)

Ordered from most durable to superseded. Each line names its source.

1. **One person's shell, no hierarchy of utilities.** "this is MY shell i'm not trying to reinvent the linux shell for the entire world" (#101); "a custom shell written for one person ... an ephemeral pomodoro widget has the same place as the main launcher (there is no hierarchy)" (#200). Durable; matches BRIEF §3.8 boundary.
2. **Composition over monolith; the shell observes, keys act.** B6 "kitty remote control + niri msg + shpool > custom daemon" `> yes`; "do not write a binary" (`dotfiles-midapril.md:261`); sidebar "purely observational" (`kmux-sidebar-design-experiment.md:27`); cmux P3 no-focus-stealing. Today: "keypress>sway>script execution" and "reads herdr state read-only and acts through Sway" (BRIEF). Durable.
3. **Status from structured data, never screen scraping.** B3 `> yes`; E2 signal priority hooks > JSONL > VT > process. Today herdr is the structured source. Durable.
4. **Raycast is the launcher model.** "visual equivalent to macos' RAYCAST ... the most powerful feature by far" (#238 note); Action panel (#96) and `>cmd` (#99) "makes us raycast-like"; clipboard "in the same aesthetic as the launcher" (#86). Durable (Vicinae parity order tonight).
5. **Keyboard first, hints overlays.** "dms hints overlay philosophy is very desirable" (#77); "i prefer toggling things with keybinds" (#64); RETRIEVED:707-717 "Keyboard-Driven as First-Class Principle ... Hints mode: overlay letter hints on interactive elements (like Vimium)". Durable (U-11).
6. **Monochrome discipline, one accent, colour only for meaning.** B11 one accent `#5B9DFF` `> yes for now`; N8d "No colored text except accent/semantic"; the noctalia Monochrome scheme's "luminance hierarchy that replaces hue differentiation" (`FINAL-LINUX-DESIGN.md:89`). Durable as U-01; the accent value itself is now the theme's (Claude clay/terracotta `#D97757` per `FINAL-CLAUDECODE-COLORS.md:57,88`; file 11 P-04 forbids clay on the active rail icon on Light).
7. **Dark-first solid fills, luminance steps, hairlines, shadows only when floating.** N1/N4; SOLIDJS-THEME-SYSTEM §3-5 ("Depth comes from luminance differences between hex fills, not from varying transparency"; "Shadows are used only on floating elements ... Never on M2/M3"). Durable as U-05 and U-07. The *reason* given (compositor blur bleeding wallpaper through) is gone; the rule survives better without it.
8. **OLED black by default, `#000000`.** #185 MUST; FINAL-LINUX-DESIGN Discord; `FINAL-CLAUDECODE-COLORS.md:172` "Pure OLED Black `#000000` ... Have it, works". Durable (noir).
9. **No animation worth noticing.** B12 50 ms `> yes for now`; #23 "i really do not care about animations whatsoever"; #188 "none/short for snappiest experience"; N8f "No bounce/elastic/spring easing". Durable as U-08 (one curve, scale can be 0). Note the QML track's 150-500 ms OutBack animations (design-experiment:183) were the losing side of questionnaire C6.
10. **Density: 13 px shell chrome, 4 px grid, 28-36 px rows, 16 px max padding.** N6/N7; SOLIDJS-THEME-SYSTEM §9. Superseded in value by the design kit (chrome 13, body 14, reading 15, nothing under 11; rail 220/30/12/2/8), identical in spirit. Tom 10-12 raised the launcher font to 12.
11. **Four target themes.** `FINAL-CLAUDECODE-COLORS.md:169-176`: Pure OLED Black, Pure White ("MacTahoe"), Anthropic Dark (`#191919`-ish warm dark, "best home for Claude syntax colors"), Anthropic Light (Ivory). Three of the four exist as noir / claude-dark / claude-light; "Pure White" has no fragment. Light mode "should only be toggled manually" (#184).
12. **The two-tone semantic pattern for WM theming.** `FINAL-CLAUDECODE-COLORS.md:190-207`: "dark tint for context, medium for emphasis ... four stops per semantic color (bg-tint → bg-word → fg-muted → fg-bright)"; active border `#D97757`, inactive `#3a3a44`, urgent `#F47B85` (`dotfiles-midapril.md:398-410`). Reusable for rail row states (selected / current / urgent).
13. **Typeface.** Then: SF Pro / SF Mono (A14 "MUST and this is not implemented now"; #187). Now: Anthropic Sans / Serif / AnthropicMono Nerd Font, never in git (BRIEF). Icons: "start with lucide" (A15); now Anthropicons glyph font exists (BRIEF §2).
14. **No glass, no blur.** Superseded. B9/B10, FINAL-LINUX-DESIGN's entire recipe, #131, #189 and SOLIDJS-THEME-SYSTEM §2 all assume compositor blur + 0.85 opacity. Tonight: "flat and opaque, hairlines not shadows, no blur, no frost, wallpaper is #000000 solid". Tom's own "(something that i explicitly reject in my approach)" about equora's shaders (`tom-repo-notes.md:11`) shows the direction was already there in March.
15. **Reference looks Tom named.** chromeX "aesthetically the closest" dark default across "launcher, dock, notification, left bar and action center"; dart's square-cornered "integrated" left pane; eqsh's OSD "nicest ... by far" and minimal clock; DMS's hold-to-confirm power menu and hints overlay; snes19xx's onboarding "looks gorgeous"; privacy-dots' coloured mic/cam dots. These are *function* references now (BRIEF: "functionality pull from quickshell NOT visuals"); Tacit sets the look.
16. **Status vocabulary.** L4 five colours "acceptable for now, to be unified later" → unified on herdr's five glyphs (U-03: "keep the dot for agent run state, draw unknown as unknown").
17. **Workspace numerology.** `december-webshell-groundtruth.md:447-450`: "Workspace #0 = orchestrator stream (global log), #1-9 = per-agent context, #F = human focus mode". Today: Mod+1..9 herdr slots on eDP-1, Mod+0 = Chrome on eDP-2. The nine-slot cap predates herdr by ten months.

---

## 5. Reusable code and data, with paths

All MEASURED to exist at the stated path and lines.

| What | Path | Use tonight |
|---|---|---|
| The 280-row priorities list (source of section 3) | `/home/tom/notes/references/devlogs/1h26/april-webshell-refs/ANNOTATED-feature-matrix.md` | Cite row numbers in MORNING.md; do not re-ask Tom what he already ruled. |
| Unannotated matrix with "Best impl" column | `.../april-webshell-refs/transient-outputs/feature-matrix-2026-03.md` | Which reference shell to read for each feature (e.g. DMS TrayMenuManager, noctalia ClipboardProvider, caelestia SQLite frecency). |
| The A..U kmux list with Tom's rulings | `/home/tom/notes/references/devlogs/1h26/annotated-kmux-feature-list-v0.md` | Sections L, M, N, P for rail/launcher behaviour; N8 anti-patterns as lint rules. |
| Full token system (CSS variable names, three tiers, component inventory) | `.../pre-sync/SOLIDJS-THEME-SYSTEM.md` §7 (`:301-513`), §8 (`:515-623`) | Token *names* for `gpuix-shell.json`; values come from `home/themes/*.nix`. |
| Status dot spec with timings | `annotated-kmux-feature-list-v0.md:268-275`; `kmux-sidebar-design-experiment.md:109-118` | Replace colours with theme roles; keep "static dot, brief flash" on done, no pulse (U-08). |
| Sidebar entry anatomy and data-source table | `kmux-sidebar-design-experiment.md:35-50, 83-121` | Row grammar for `a.session-row`; map each source column to a `herdr api snapshot` field. |
| Semaphore JSON shape (the proto-herdr record) | `dotfiles-midapril.md:265-281`; `kmux-sidebar-design-experiment.md:56-68` | Compare to `herdr api schema` to see which fields (model, tags, worktree, notification, children) herdr lacks. |
| Session FSM | `annotated-kmux-feature-list-v0.md:135`; `KMUX-INTEGRATION-SURFACE.md:122-134` | `spawning → working → waiting_for_approval → waiting_for_input → idle → error → completed` vs herdr's five; document the mapping in the rail's `status.ts`. |
| `os.*` TypeScript namespace (notifications, media, audio, windows, workspaces, shell surfaces) | `december-webshell-groundtruth.md:173-316`; `april-webshell-refs/spec/os.d.ts` (listed in grep, not read) | Shape for `pkgs/gpuix-shell/src/adapters/*.ts` interfaces; `os.shell.SurfaceId = 'bar' \| 'launcher' \| 'control-center' \| 'notifications' \| 'osd' \| 'lockscreen'` (`:257`). |
| Claude.ai 12 syntax colours + tweakcc UI keys | `FINAL-CLAUDECODE-COLORS.md:26-39, 86-97`; kitty remap `dotfiles-midapril.md:335-361` | Already the basis of `home/themes/claude-*.nix` (REPORTED by BRIEF; not re-measured). |
| Sidebar design-extraction protocol (YAML schema for measuring screenshots) | `.../pre-sync/kmux-screenshot-protocol.md` (466 lines, not read) | If a Tacit screenshot pass is wanted. |
| Tom's reference-shell notes | `.../april-webshell-refs/transient-outputs/tom-repo-notes.md` | Which shell to open for which function. |
| Repo link list | `.../pre-sync/NEW-kmux-inspiration.md` | manaflow, arbor (GPUI), superset, symphony SPEC, clui-cc, privacy-dots. Note: `/home/tom/Downloads/gpui-shell` tonight is a different repo (andre-brandao, BRIEF §2). |
| CADE 56-capability manifest with READ/WRITE/ACTION/SECRET tags | `.../CADE/cade-june11-idealized/design/00-IDEAL-TARGET.md` §B (`:91-166`) | Tag every `gpuix-shell` CLI verb the same way; "`lock` is a verb; `unlock` never is" (`:18`). |
| Fish OSC 7 / OSC 133 snippets, starship shpool/ssh/network modules, nvim lualine | `dotfiles-midapril.md:41-69, 76-86, 130-154` | Not shell; may already be in dotfiles (not checked). |
| Hook → status-file scripts (kmux-hook pre-tool/post-tool/idle/stop) | `annotated-kmux-feature-list-v0.md:106-110` | Historical; herdr supersedes. |

No runnable code for the shell itself survives in these notes (the March SolidJS/QML tree is under `april-webshell-refs/{tuesday,wednesday,thursday}-testing/`, not read; it targets QtWebEngine and is not portable to GPUIX).

---

## 6. Gaps

Things the sources leave open, or where tonight's BRIEF and the 2026-03 rulings disagree.

1. **Polkit agent (#216/#256 MUST, "low-hanging fruit" in Quickshell) has no GPUIX path.** Needs a D-Bus `AuthenticationAgent` registration via dbus-next and a prompt window. Not in BRIEF §3.2's process list. INFERRED effort: a day, not a night.
2. **System tray (#29 SHOULD) and session lock (#203 COULD) have no GPUIX binding** at 0.11.0 (SNI host, `ext-session-lock`). Leave absent; say so in MORNING.md.
3. **Control center: WONT (Mar 24) vs `gpuix-shell controls` (BRIEF §3.2).** Proposed reading in 3.11: WiFi/Bluetooth are menus, not a toggle grid. Needs Tom's nod; recorded here, not in ASSUMPTIONS.md (read-only brief).
4. **Clipboard store: cliphist (Mar 24, "prefer not to create special rust functionality") vs own `wl-paste --watch` store (BRIEF §3.4).** Tom left the door open ("could convince me to move away from cliphist", :634). Either is defensible; images must display.
5. **Settings GUI (#174/#176 MUST) is nowhere in tonight's plan.** Nix + the theme JSON cover config; a settings *surface* contradicts Tom's own #200 note. Flag, do not build.
6. **Sidebar side and width.** Mar 26: right, 400 px. Apr 4: left, 280 px. Oct: left, 220 (or 56 collapsed), with file 11 §3.1 noting the BRIEF's "56 default" vs HB's "220 default" conflict and the eDP-1 width worry. Unresolved which is default.
7. **Agent topology (D5), permission routing (D7), approve-from-sidebar (I4).** Never decided in March ("None of D1–D10 were ever answered on record"); still undecided. herdr shows `blocked ◉`; answering stays in the projector. The rail should not grow an approve button without Tom.
8. **herdr fields vs the semaphore record.** The 2026 sidebar wanted model badge, tags, diff stat, context %, cost, worktree, children. Whether `herdr api snapshot` carries any of these was not measured tonight (herdr not queried by this reader). The rail should render only what the schema proves.
9. **Multi-monitor behaviour of the rail (L5h, G8)** was listed as missing in March and is only partly settled now (rail eDP-1 only; toasts/OSD on which output is INFERRED "focused").
10. **Mapping the March FSM (seven states) onto herdr's five glyphs.** `waiting_for_approval` and `waiting_for_input` both become blocked ◉; `completed` vs `idle` both exist (done ●, idle ✓); `spawning` has no glyph (unknown ○?). Decide in code and write it down.
11. **OCR via local model (#238 SHOULD)** is a two-line script now (grim → strix:8731 vision) but lives at the boundary between shell and utilities; not placed.
12. **Pomodoro (#250 "first feature i release AFTER base webshell")** has a script but no surface. A rail-footer countdown + OSD is the cheapest honour of that ruling.
13. **The "Pure White (MacTahoe)" fourth theme** (`FINAL-CLAUDECODE-COLORS.md:173`) has no `home/themes/*.nix` fragment; claude-light is Ivory-based. Not a tonight item.
14. **Sources not read in full** that might still hold Tom rulings: `pre-sync/quickshellX-solidjs2-discussion.md` (1568 lines; grep found only the Duncan chat), `pre-sync/INTEL.md`, `april-webshell-refs/KMUX-INTEGRATION-SURFACE.md`, `pre-sync/kmux/long-scoping/README.md` (1826 lines, the Mar 1 origin thread), the REVOLUTION-2 `compiled/*` set. The grep for "priorit" over `1h26/` returned nothing in those beyond what is cited here.

---

## 7. What this reader did and did not do

Did: read the nine assigned files end to end; read the sibling files listed in 1.2 (the annotated matrix in two pages, the kmux questionnaire, lineage, timeline, sidebar concept, architecture decisions, Tom's repo notes, CADE ideal target and verdict, the SolidJS token sections); ran the requested grep plus a targeted grep for "ultimate"; diffed the annotated matrix against its unannotated original; checked git dates (all files landed in the 2026-07-03 migration commit, so content dates are from headers and the TIMELINE reconstruction).

Did not: query herdr, Sway, or any live process; read the March SolidJS/QML source trees; run anything under `runtime-test`; touch `/home/tom/mecattaf/dotfiles` or ASSUMPTIONS.md. Nothing here was verified against a running shell. Line numbers are from `cat -n` at read time.

RESULT: {"file": "/home/tom/.wt/dotfiles/gpuix-shell/docs/gpuix-shell/wave1/28-notes-presync-final-linux-design.md", "summary": "The 'deeply annotated priorities list' is april-webshell-refs/ANNOTATED-feature-matrix.md (2026-03-24, 280 rows with Tom's MUST/SHOULD/COULD/WONT) plus annotated-kmux-feature-list-v0.md (2026-03-26, A..U with > rulings), not FINAL-LINUX-DESIGN.md; both are reproduced verbatim and mapped row by row to the rail/launcher/notifications/OSD/power/controls surfaces. herdr now replaces the whole 2026 stack of semaphore files, niri event-stream, OSC 99 and .title files as the single session source, the sidebar moved from right/400 to left/220, and glass/blur, niri, SF Pro, control center, matugen and the shpool fork are recorded as abandoned with Tom's reasons."}
