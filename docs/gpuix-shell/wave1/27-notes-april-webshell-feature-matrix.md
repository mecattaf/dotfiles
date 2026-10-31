# 27 — Notes repo: the April 2026 webshell/kmux feature matrix, rulings and priorities (read for the GPUIX/Sway shell)

Reader: Claude (Fable 5.1), wave 1 of the gpuix-shell overnight run, 2026-10-21 ~00:30 CEST.
Read-only pass over `/home/tom/notes/references/devlogs/1h26/april-webshell-refs/` plus the two sibling
files that directory names as its own inputs (`../annotated-kmux-feature-list-v0.md`,
`../december-webshell-groundtruth.md`) and the `june16-cowl-revived.md` file the TIMELINE says the trail
resumes in. Every claim below is labelled:

- MEASURED = I ran a command (line counts, grep hits, file listings).
- REPORTED = what the document says; Tom's own words are quoted verbatim with the file date.
- INFERRED = my mapping onto BRIEF.md §3 surfaces; nothing Tom said tonight.

File pointers are `path:line` relative to `/home/tom/notes/references/devlogs/1h26/april-webshell-refs/`
unless they start with `../` (then relative to `/home/tom/notes/references/devlogs/1h26/`).

---

## 1. What the source is

### 1.1 The directory (MEASURED)

`april-webshell-refs/` is a frozen archive: the whole tree landed in one notes commit (`4adb7539`,
2026-07-03, "Migration step 5a", per `TIMELINE.md:9-11`), so file mtimes are all Jul 6 and git history is
useless; dates are content dates. Top level (MEASURED `find | wc`):

| Path | Lines | What |
|---|---|---|
| `ANNOTATED-feature-matrix.md` | 701 | 280 features from 16 Quickshell shells + 2 Rust daemons, every row followed by Tom's `>` annotation. **This is the "deeply annotated priorities list".** |
| `transient-outputs/feature-matrix-2026-03.md` | — | the same 280 rows before annotation (MEASURED: both files have 280 `| N |` rows; the ANNOTATED copy adds the `>` lines and nothing else) |
| `../annotated-kmux-feature-list-v0.md` | 507 | ~300 line items A1–U6 on the agent/kmux side, Tom's `>` annotations on sections A–C and selected items (J2, L4). **This is the "very detailed set of rulings".** |
| `architecture-decisions-2026-03-22.md` | 540 | the locked three-process architecture, design system, os.* namespace, plugin model |
| `KMUX-EVALUATION-CRITERIA.md` | 160 | 11-section checklist for reviewing agent-multiplexer references |
| `KMUX-INTEGRATION-SURFACE.md` | 624 | what the shell spec must stub for the agent sidebar (`os.claude`, `os.terminal`) |
| `TIMELINE.md` | 58 | 16 dated milestones 2026-03-14 → 2026-04-05, reconstructed 2026-07-03 |
| `thin-client.md` | 70 | desktop-as-server / stateless laptop design, with Tom's header note |
| `spec/` (25 files) | ~10,000 (`os.d.ts` alone 2131) | WebShell v0.1.0-draft spec suite dated 2026-03-24: `SPEC.md`, `surfaces.md`, `roadmap.md`, 21 `os.<ns>.md`, `os.d.ts` |
| `REVOLUTION/` (21 files) | ~15,000 | 2026-03-27 pivot: "redo Quickshell without the Qt" → purpose-built Chromium embedder (COWL) |
| `REVOLUTION-2/` (92 files) | ~200 K words (REPORTED) | 2026-04-04/05: roundtables, KMUX sidebar concept, extension architecture, agency.agency split |
| `friday-testing/` (265 files) | — | 2026-03-26 handoff; design-revamp tokens; integrated-shell bin scripts; DEFERRED/ design docs |
| `tuesday-validation/`, `wednesday-testing/`, `thursday-testing/`, `sunday-testing/` | 264 / 998 / 278 / 182 files | the SolidJS + quickshellX + Rust daemon builds, then the COWL C++ scaffold |
| `snippets/` (102 files) | — | ripped reference code: bridge/, daemon/, niri/, services/, ui/, web/ |
| `PREVIOUS-SESSION-handoff.md`, `NEXT-SESSION-handoff.md`, `kmux-next-session.md`, `LATER-postcleaning-prelaunch.md`, `implementation-learnings.md`, `DOCS-v0.5.0.md` | 200+ / 95 / 30 / 7 / ~400 / 828 | session logs; Tom's "thoughts for later"; 77 QML/WebEngine gotchas; COWL v0.5.0 protocol doc |

### 1.2 The lineage in one paragraph (REPORTED, `TIMELINE.md:25-43`)

2026-03-14 first spike (React inside a quickshellX `FloatingWindow` via QtWebEngine under niri) →
03-22 architecture locked (Rust daemon + quickshellX + SolidJS over QtWebChannel) → 03-23 16-shell survey →
**03-24 Tom annotates all 280 rows** and the kmux namespaces are stubbed → 03-25 shell validated end-to-end
(14 QML bridges, 7 surfaces) → **03-26 Tom annotates the kmux list A–C** → 03-27 REVOLUTION ("Redoing
quickshell but without the Qt") → 03-28 COWL named → 04-04 KMUX sidebar concept born ("tmux → cmux → KMUX")
→ 04-05 "Sunday Overall Mapping" closes the archive. Trail resumes 2026-06-16 (`../june16-cowl-revived.md`)
with CADE rolled back to CUBS; CUBS is the subject of wave1 note 10.

### 1.3 Why it matters tonight (INFERRED)

Tom's 2026-10-20 23:20 message: "as early as 6 months ago did i describe the 'ultimate desktop shell' with
at one time a very detailed set of rulings with deeply annotated priorities list ... the spirit was very
correct, even though i had not captured yet that i would be using the herdr project as centrally". The
exact phrase "ultimate desktop shell" does not occur in `april-webshell-refs/` (MEASURED: `grep -ril` → 0
hits); the only hit in the notes repo is a later June file,
`../CADE/cade-june11-idealized/research/ultimate-shell-feature-set.md:1` ("The Ultimate Desktop Shell:
Feature Taxonomy", 17 capability domains). The March matrix is the "deeply annotated priorities list"
(280 rows, each with a MUST/SHOULD/COULD/WONT and a reason); the kmux list is the "detailed set of rulings"
(A1–B15 all answered yes/no/must by Tom). Both predate herdr; everything they call CCD / KMUX sidebar /
os.claude / os.terminal / shpool / kitty remote control is the slot herdr now fills (§3.9, §6.2).

---

## 2. Verbatim Tom rulings about the desktop shell

All REPORTED. Date is the document date (Tom's annotations are undated inline; the session log
`PREVIOUS-SESSION-handoff.md:98-102` dates the matrix annotation to 2026-03-24 and
`friday-testing/00-HANDOFF.md:3` dates the kmux list feedback to 2026-03-26).

### 2.1 Framing rulings (2026-03-24, `ANNOTATED-feature-matrix.md`)

- `:7` "@claude i added my annotations with `>` lines"
- `:238` "GENERAL NOTE on 1.4 LAUNCHER: my shell's launcher in its ideal form will be visual equivalent to
  macos' RAYCAST. i found it to be the most powerful feature by far. there was a qt launcher called vicinae
  that tried to reproduce raycast; i could revisit it. but dankmaterialshell's launcher does a great job at
  getting close to it. we start with the dms implementation as reference and then decide if we want to go
  beyond" — this is the earliest mention of Vicinae in the archive; tonight Tom asked for "a full
  implementation of the linux wayland sway facing vicinae" in GPUIX (BRIEF §5).
- `:75` (workspaces indicator) "MUST, in fact in my concepts i had the workspace switcher as a separate
  left horizontal bar, whereas all the other modules exist in the top bar." — the left rail idea is six
  months old; tonight: "a left bar with workspace switcher that remplaces waybar" and "no top bar on the
  Linux head" (BRIEF §1).
- `:32` (vertical bar) "MUST, in fact i have a very specific use case in mind for that."
- `:40` (multiple bars) "MUST, i will in fact have multiple simultaneous bars in my config, and want to be
  able to toggle one but not the other"
- `:56` (IPC bar toggle) "MUST, and very important to have funcioning well with niri; in fact one ipc
  toggle should control only one bar (in case there are multiple bars)"
- `:34` (auto-hide) "MUST, could be useful but more important for me is that i want to toggle bars with a
  niri keybind (sigint)"
- `:24` (plugin widget system) "MUST, it is important to be able to 'turn any functionality' into a bar
  addition"
- `:452` (plugin config) "in my case it s a custom shell written for one person, so the utilities/plugins i
  need are configured from the dotfiles themselves. no need to 'enable' plugins or browse through them. to
  be precise, in my world, an ephemeral pomodoro widget has the same place as the main launcher (there is no
  hierarchy)"
- `:233` (i18n) "DONT i explicitly reject i18n support for now. this is MY shell i'm not trying to reinvent
  the linux shell for the entire world"
- `:139` (BongoCat) "WONT, we're building a serious shell"
- `:363` "WONT. We are building this shell for niri ONLY. No multi-compositor support." (superseded: Sway
  is the only compositor now, BRIEF §1)
- `:597` "WONT. i do not need a control center. this is not in scope for my project. this applies to
  268-280" (see §6.1: tonight's order names wifi and bluetooth menus and BRIEF §3.2 declares a `controls`
  surface; the March WONT was aimed at the DMS/noctalia tile grid)
- `:508` "COULD the entire idle management suite is not so important for me, i prefer to icebox for now.
  this applies to 225-232 inclusive"
- `:463` (lockscreen) "COULD this functionality is quite secondary. i bypass lockscreen by default on reboot
  (already implemented in my os with greetd automation); and when i need to rest my desktop i do `systemctl
  sleep`. might revisit this later ... but icebox for now"
- `:489` (polkit) "MUST. i do not like the classic gtk greeter (that gets used now in the current state of
  my dotfiles). we are writting a very nice, very well-done uniform design system. dms and others have
  proven to me that polkit is implemented and easy to do with regular quickshell. this is low-hanging
  fruit"
- `:493` (power menu) "MUST and in fact i want to mention that i like the new DMS powermenu the most with
  the ability to scroll/select through a list AND press and hold a given key to get the desired action"
- `:95` (power/session menu) "MUST, in fact i really like the DMS one which made you 'hold a key for x
  seconds with a visual progress bar'; in addition to being able to scroll through them."
- `:156` (notification daemon) "MUST this one is non-negociable"
- `:180` (notif keyboard nav) "MUST, dms hints overlay philosophy is very desirable"
- `:190` (flood protection) "MUST, to avoid dangerous or strange behavior on my system"
- `:203` (clipboard in launcher) "MUST, it's important for me to have the clipboard history shown in the
  same aesthetic as the launcher; also making sure that we are displaying images (i use cliphist, prefer
  not to create special rust functionality as i found DMS reinventing the wheel with their clipboard
  implementation)"
- `:526` (clipboard manager) "MUST the clipboard manager is very important to me. note however that i use
  cliphist currently. i discuss the specifics of my implementation separately"
- `:634` (native clipboard, gap) "COULD. discussed externally. to be revisited later. could convince me to
  move away from cliphist" (BRIEF §3.4 now says own store over `wl-paste --watch`)
- `:103` (VPN indicator) "MUST. it is CRUCIAL for me to know if i'm connected to tailscale, and possibly to
  know what other devices are connected on my tailscale network. i am aware that there are 2+ different
  tailscale DMS extensions, happy to bring them over in due time"
- `:330` (VPN multi-provider) "MUST with special focus on tailscale"
- `:99` (privacy indicators) "MUST, and i'll likely develop a specific widget around it"
- `:141` (recording indicator) "MUST, i will use that"
- `:281` (volume OSD) "MUST. an OSD is very imprtant to have. I found the eqsh one to be very nice (which
  i m using right now)"
- `:283` (brightness OSD) "MUST but with a small caveat: i really don't care if the brightness is managed
  by my shell. as you can see now from my scripts, eqsh is sufficient, and i would be happy to have that
  being a toggle i control from niri keybinds. doesn't really have to be fully integrated with the shell if
  it adds work"
- `:255` (volume overdrive) "DONT explicitly i like to have volume going from 0 to 100; only situation
  where that's not the case is in vlc media player"
- `:263`, `:265` (spectrum visualizers) "DONT i don't care about that"
- `:117` (audio visualizer popup) "SHOULD, i loved dms' popup for music and its associated 'scroll through
  to skip parts of the song'."
- `:269` (MPRIS seek) "MUST, love the progress bar"
- `:77` (clock) "MUST, but no need to do anything fancier than configurable time and date. the minimal eqsh
  one was sufficient."
- `:79` (tray) "SHOULD, very nice to have but i won't be using it personally"
- `:201` (file search) "MUST, and fd plugin seems sufficiend, dms' dsearch was overkill and having a
  separate package for that is not desirable"
- `:207` (provider system) "MUST, dms provider concept is powerful"
- `:211` (favourites) "MUST, and caelestia's sqlite frequency is very cool"
- `:223` (action panel) "SHOULD, this is a nice addition that makes our launcher raycast-like"
- `:227` (web search) "COULD, explore implementation later if at all (seems redundant with opening a new
  google chrome tab and doing my search directly from there, little added value in search results in
  launcher)"
- `:229` (shell command exec) "SHOULD, makes us raycast-like"
- `:215` (app overrides) "COULD, but i like to control my .desktop apps from my local share applications in
  dotfiles so this is a little redundant"
- `:367` (niri config generation) "COULD, maybe later if there is justifiable functionality to be gained
  there but otherwise prefer that the niri kdl config remain in chezmoi-backed dotfiles and not in the
  purview of the shell"
- `:381` (window rules GUI) "WONT i don't care about editing window rules with gui"
- `:383`, `:385` (scratchpads, swallow) "SHOULD this is piri functionality so would like to have it baked
  in"
- `:391` (output config) "COULD, for now i use `kanshi` to manage outputs and resolutions etc but happy to
  revisit this later down the line"
- `:393` (overview toggle) "MUST, but i think this is just something you feed through the niri config with
  keybind/ipc"
- `:414` (Material You) "WONT whatsoever: no material or material you (i don't like it); no matugen
  whatsoever as I explained we do not have a strict colorscheme we follow a standard minimal css token"
- `:416` (predefined schemes) "WONT in the sense that we have only one predefined colorscheme"
- `:418` (dark/light toggle) "COULD far down the line support a single universal dark/light toggle. icebox
  for now" (superseded: claude-light and claude-dark are in scope now, BRIEF §1)
- `:420` (auto dark/light) "WONT: even if i do eventually add a light mode this should only be toggled
  manually" — still binding: the `theme` script is manual.
- `:422` (OLED mode) "MUST. OLED mode ie make the black colors #000000 is something that i do by default. so
  you could say i do oled compatible color mgmt by default. however if by oled you mean something like 'a
  special setting that reduces oled monitor burn-in somehow' then WONT. i can manage my oled screens
  myself" — the `noir` theme and `#000000` wallpaper tonight are this ruling.
- `:424` (cross-app theming) "WONT. this is also a clear design decision that i take from the start: i do
  not need help managing my gtk or qt theme etc. that is what dotfiles are for. this also complements my
  'NO MATUGEN' decision"
- `:426` (fonts) "SHOULD but the default font, like eqsh, is sanfrancisco mono." (superseded: Anthropic
  Sans / Serif / AnthropicMono Nerd Font, BRIEF §1)
- `:428` (animation speed) "WONT. not sure if the shell has anything to do with animation speeds at all,
  and even if it does i would make it none/short for snappiest experience"
- `:430` (opacity) "SHOULD. Compositor (niri) owns blur via ext-background-effect-v1; CSS just sets
  background-color alpha..." (superseded: "no blur, no frost", flat and opaque, BRIEF §1)
- `:434`-`:438` (wallpaper picker, per-monitor, fill modes) "SHOULD because we are indeed controlling the
  monitor from quickshell side of things (not niri config)"; "SHOULD, if we have a wallpaper picker then
  might as well have it per-monitor (i mostly use dual monitor setup)" (superseded: wallpaper is `#000000`
  solid tonight)
- `:440` (parallax) "WONT i explicltly don't need parallax because it makes me dizzy"
- `:446` (i18n) "WONT no i18n whatsoever, shell is always in english."
- `:536` (OCR) "SHOULD but with a twist. first off i want to use the existing niri functionality to clip
  screen ... the second twist is that i do NOT want the ocr to be handled by tesseract: it will be handled
  with qwen 3.5 opensource multimodal llm model which comes with phenomenal ocr from screenshots; and i
  confirmed it runs on my machine. Backend: HTTP call to llama.cpp server running in a local toolbox
  container." (today's equivalent: Halogen/Gufo Flash-Next at strix:8731, AGENTS.md)
- `:540` (calendar grid) "WONT. the calendar month grid display will be handled by a bespoke, fullscreen,
  on-brand calendar app FAR later down the line. i do not need such utility in my shell. they're hacky
  anyway, calendar grids ar not straightforward in qml.. but trivial with web technologies"
- `:542` (terminal sessions) "MUST but i use shpool for terminal sessions, not tmux nor zellij. that being
  said the dms implementation could be very helpful in my preparation of that fucntionality. requires
  further specialized scoping" — herdr is that scoping's answer (INFERRED).
- `:546` (night light) "WONT, my gamma control and night light is set once and not from the shell. skip
  entirely"
- `:552` (desktop widgets) "WONT. i do not like widgets"
- `:554` (AI assistant) "COULD but much later down the line. i do not need an ai integration the way it is
  done in the reference qml shells. i have some ideas here so not marking this as won't" — tonight's
  `gpuix-shell ask` OpenUI surface is the bounded version (INFERRED).
- `:558` (notepad) "WONT. i use github-backed md notes. see no value in having external notepad. drop
  that"
- `:560` (pomodoro) "SHOULD the pomodoro timer concept is very valuable and i have my own approach for it.
  so we use the existing references and build on top of it. this will be the first feature i release AFTER
  base webshell" — `~/.local/bin/pomodoro` exists in dotfiles today (BRIEF §2).
- `:562` (containers) "SHOULD Container management is very desirable on my system, i expand on thsi a
  little later"
- `:564` (KDE Connect) "SHOULD; this doesn't have to be done right away but the KDE connect is extremely
  desirable. i believe that dankmaterialshell also has KDE connect. in the past i also considered Valent for
  the same. to be scoped out better but i wish to make it clear that 'android phone notification' is
  extremely desirable"
- `:586` (process manager) "COULD later down the line. this reminds me that there was a good DMS plugin for
  viewing dockerfiles, which i considered extending to see running systemd services and quadlets"
- `:590` (onboarding wizard) "MUST but this one will require specific scoping work before i configure it"
- `:594` (SDDM) "WONT i do not use SSDM whatsoever. i use a super minimal greetd implmmentation which means
  i have no use for sddm or similar"
- `:530` (screen recording) "COULD look into what this entails but my first instinct is that i already use
  OBS Studio (as flatpak) to record screen, making this implmementation quite redundant"
- `:528`, `:532`, `:534` (screenshot, editor, color picker) "WONT because existing niri window manager is
  sufficient"; "WONT the builtin niri screenshot functionality is sufficient for me"; "MUST but Color
  picker currently since i use niri window manager the screenshot tool exists and is sufficient" — on
  Sway today these are `screenshot` and `colorpicker` scripts (BRIEF §2).
- `:659` "to be reevaluated later" (plugin model validation table)

### 2.2 Architecture and stack rulings (2026-03-26, `../annotated-kmux-feature-list-v0.md`)

Section A (locked stack), Tom's answers verbatim:
- A1 kitty one window = one OS window → "must"; A2 niri → "must"; A3 shpool → "must"; A4 QuickshellX →
  "must"; A5 SolidJS → "must, we will use v1"; A6 Kobalte → "this is a new addition that will require
  further work when we go down the line"; A7 bun+vite → "must"; A8 fgp-browser → "should, this is something
  that will be handled later entirely"; A9 QtWebEngine CDP + Python bridge → "no this is wrong. discard
  this information"; A10 Neovim → "should, to be done later"; A11 Rust daemon → "this is already adopted
  decision"; A12 Python glue → "no python, thinking all rust"; A13 SQLite/FTS5 → "should, to be done
  later"; A14 SF Pro / SF Mono → "MUST and this is not implemented now"; A15 Phosphor or Lucide icons →
  "should, start with lucide" (`:10-39`).

Section B (architecture principles), all answered (`:41-72`):
- B1 "One kitty window = one OS window. No splits, no tabs, no multiplexer inside kitty." → "yes"
- B2 "No TUI anywhere..." → "technically, no TUI except for pi-mono or pi-agent. but yes no dashboard in
  terminal"
- B3 "Status from structured data (JSONL + hooks), not screen scraping." → "yes, in fact must be
  discussed in depth becaues the way it is now with claude code, in the existing implementation of my
  focused window indicator of the bar of quickshellx webshell is sufficient, seems like claude code does
  output the needed titles"
- B4 "Always-shpool model." → "yes!"
- B5 "Thin client/server split..." → "should; but for now it s all in server mode (ie local is server) so
  no need for htis logic now."
- B6 "Composition over monolith. kitty remote control + niri msg + shpool > custom daemon." → "yes"
- B7 "The filesystem IS the API. JSONL + semaphore locks + inotify > RPC daemons." → "yes"
- B8 "All agents run in interactive mode. One mode. No headless RPC for agents." → "yes"
- B9 "No CSS blur anywhere ever. All blur is compositor-driven" → "yes, niri implementation of blur to
  be noted somewhree externally to its own md file because we re still waiting on upstream for that"
- B10 "Dark-first: surfaces are solid hex fills, compositor sets window opacity 0.85" → "yes"
- B11 "One accent color: `#5B9DFF`. No secondary/tertiary. Monochrome discipline." → "yes for now"
- B12 "One animation duration: 50ms for everything." → "yes for now"
- B13 "Animate ONLY opacity and transform." → "yes for nw"
- B14 "No light theme. No theme toggle. Dark-only single-accent." → "yes for now"
- B15 "shpool is systemd user service (socket activation)" → "yes and this is already impelmented on my
  system"

Section C (primary agent runtime) (`:74-91`): C1 Claude Code first → "yes"; C2 Pi first → "no"; C3 both
day one → "well technically both wil lbe installed on day one but we re startign w claude"; C4 namespace →
"os.claude as the prototype. os.agent is reserved to when we 'graduate' from claude code and then we move
on to os.agent for pi"; C5–C8 → "yes" / "ok so we start w claude specific" / "start w claude" / "start w
claude."

Later inline rulings: J2 shpool fork → "ABANDONED COMPLETELY" (`:200`); L4 status dot colours →
"acceptable for now, to be unified later of course" (`:269`).

`friday-testing/00-HANDOFF.md:35-51` condenses these as the "Resolved Decisions" table (SolidJS v1, all
Rust, QtWebEngine webview discarded, shpool fork abandoned, Claude Code first, `os.claude`, thin client
deferred, "Existing focused-window indicator may suffice", Kobalte later, status colours acceptable).

### 2.3 Other Tom-authored lines in the archive

- `thin-client.md:1` "NOTE: @claude the below description is extremely detailed and the decisions made
  are not irrevocable (eg what clipboard tool we use is not determined 100%)."; `:55` "NOTE: thisis
  important because it means that the thin client user would not even realize that they're controlling
  the DESKTOP's wifi connection; whereas the thin client laptop remains connected to the desktop with the
  trusty BE550 router connection" (2026-03-24). Today the Zenbook is the physical seat and strix is
  headless (AGENTS.md); the thin-client intuition survives as `herdr --remote strix`.
- `REVOLUTION/ARCHITECTURAL-BOUNDARY.md:116` "PS: THOMAS ADDITIONAL NOTE: the `harness.*` boundary is
  WRONG. we do not use it. harness is the name of the fedora distribution, nothing more. The correct naming
  is `os.*`" (2026-03-27).
- `REVOLUTION/first-chat.md:8-15` (2026-03-26, pasted chat): "i m not scared by the compexity of 'redoing
  quickshell but without the qt' anymore. inform yoruself first: has anybody done this before?"; `:60-65`
  "if we extend the concept that neovim is currently used by its plugins 'to its max' ... i think we are
  similarly position to write the 'flattened' surface rather than it being a quickshellx ... but somehow ALL
  in javascript or typescript? i would still use niri windowm anage,r kitty term, flatpak chrome and the
  nautilus file explorer but all therest is up for discussion."; `:113` "problem with astal is that the
  author is a little all over the place"; `:135-145` "what about electron? the elephant in the room? ...
  additionally one new wildcard: GAMESCOPE!"
- `transient-outputs/tom-repo-notes.md` (2026-03-23) — Tom's verbatim notes per reference shell, e.g.
  `:9` "DankMaterialShell: this is THE BIG ONE."; `:11` equora "fancy qsb and fragment shaders for
  vibrancy etc (something that i explicitly reject in my approach) ... certainly has nicest OSD (volume,
  brightness) by far"; `:15` Ambxst "TMUX SESSION MANAGER!!! (i'll do the same but with shpool in my
  case)"; `:21` chromeX "aesthetically the closest to what i'm trying to achieve ... wonderful default dark
  aesthetic across the launcher, dock, notification, left bar and action center menu"; `:23` dart "the
  lack of rounded borders especially on the left dashboard/clipboard/notification unified pane makes it
  feel much more.. 'integrated' with the wayland system"; `:31` privacy-dots "i want in my case to have the
  'mic is recording' button to be red-ish"; `:45` tpaau-shell "hyprland is not good software (i agree w
  that)"; `:59-60` "I DO NOT want to use matugen or any other colorscheme manipulation cli tool. This is a
  final decision." / "Disregard anything that has to do with Material UI (M3 and any extension)."
- `LATER-postcleaning-prelaunch.md` (undated, ~2026-03-26): "before launching this project, i want to be
  doing several rounds of intense code revision. this codebase shold be rewritten several times by multiple
  claude code agents, analyzing the coding style from the many different projects whose shoulders we are
  standing on. beyond the qml quckshell shells, i want to lean more into the coding style of rust-written
  utilities (piri, niri-ipc, niri itself)."
- `REVOLUTION-2/CONVERSATION-NUGGETS.md:9` (2026-04-04) "where specifically did i say that i was stripping
  out the browser parts?"; `:36-41` the Tailscale analogy (Chromium = WireGuard, COWL = protocol layer,
  agency.agency = Tailscale).
- `REVOLUTION-2/revisions/SURFACE-PROMOTION.md:3` Tom "asked about this several times ('it's just
  different levels of abstraction, we could wrap one into the other')".
- Tom's hard floor as recorded by the audit (`transient-outputs/phase1-notes.md:143`): "13 features define
  Tom's hard floor (bar, dock, search, notifications, OSD, brightness, clipboard, control center, lock
  screen, screenshot, wallpaper, power menu, keybinds)" — INFERRED by the agent from Tom's then-current
  eqsh config, not a Tom quote.
- Tom's aesthetic as recorded (`transient-outputs/INDEX-webshell-audit.md:628`): "Vercel OLED Minimal
  (pure black #000000, neutral gray #525252 primary, SF Pro + Fira Code, square corners, no dock, 12px
  radius for popups)" — from his DMS theme file `catppuccin-noir.json` (REPORTED,
  `wave7-dms-config.md:10-12`). Note "no dock" and "square corners".

---

## 3. Feature inventory

Columns: `#` = matrix row; **Feature / exact behaviour** = the matrix "Feature" + "Best impl" cell
(REPORTED); **Tom's priority** = his `>` line verbatim (REPORTED, 2026-03-24); **Disposition** =
INFERRED for gpuix-shell: KEEP (priority stands, build it), REPLACE (role now taken by herdr / Sway /
an existing script), NEW (not in the matrix but tonight's order needs it), DROP (WONT stands or
overtaken), DEFER (icebox stands); **Surface** = BRIEF §3.2 surface or data seam.

Surface keys: `rail` (left bar), `notif` (toasts + daemon), `osd`, `launcher` (Mod+d), `switcher`
(Mod+i), `controls` (quick settings), `files`, `power`, `ask` (OpenUI), `cli` (gpuix-shell socket + Sway
binds), `herdr`, `sway` (IPC), `theme`, `script` (existing ~/.local/bin).

### 3.1 Bar / status bar (rows 1–26)

| # | Feature / exact behaviour | Tom's priority (verbatim) | Disposition | Surface / notes |
|---|---|---|---|---|
| 1 | Three-zone layout (L/C/R); DMS, noctalia | MUST, this is basic bar config | KEEP as top/middle/bottom zones of a vertical rail | rail |
| 2 | Configurable widget arrays per zone; DMS JSON | MUST | KEEP, from `gpuix-shell.json` theme/config fragment, not a settings GUI | rail, theme |
| 3 | Widget drag-reorder in settings; noctalia | COULD, happy to keep it "deterministic" from config | DROP | — |
| 4 | Plugin widget system; noctalia BarWidgetRegistry | MUST, it is important to be able to "turn any functionality" into a bar addition | KEEP as a registry of rail modules (TS modules, no manifest ceremony) | rail |
| 5 | Multi-monitor via Variants; all | MUST | KEEP: one rail per output (eDP-1 top, eDP-2 bottom) | rail, sway |
| 6 | Per-screen widget configuration; DMS screenPreferences | MUST | KEEP: the bottom display (Chrome, ws 10) gets a different module set | rail |
| 7 | 4-way position; DMS, noctalia | MUST | KEEP but left is the only position tonight ("no top bar") | rail |
| 8 | Vertical bar layout; caelestia | MUST, in fact i have a very specific use case in mind for that. | KEEP: the rail IS the vertical bar | rail |
| 9 | Auto-hide with hover reveal; DMS | MUST, could be useful but more important for me is that i want to toggle bars with a niri keybind (sigint) | KEEP the keybind toggle (`gpuix-shell rail toggle` via socket); hover reveal optional | cli, rail |
| 10 | Fullscreen detection auto-hide; Ambxst | MUST | KEEP: Sway IPC `fullscreen_mode` on focused window → collapse rail / exclusive zone 0 | rail, sway |
| 11 | Click-through mode (region mask); DMS | COULD | DEFER | — |
| 12 | Multiple simultaneous bars; DMS | MUST, i will in fact have multiple simultaneous bars in my config, and want to be able to toggle one but not the other | KEEP: rail per output, each addressable by id | rail, cli |
| 13 | Integrated dock in bar; Ambxst | COULD | DROP (Tom's own aesthetic note says "no dock") | — |
| 14 | Bar style variants; sshell | COULD | DROP | — |
| 15 | Goth/outer corners; DMS | COULD, but this is less difficult because i use web components | DROP (flat, hairlines) | — |
| 16 | Per-screen density; noctalia | COULD, since we have per-screen settings anyway | DEFER | — |
| 17 | Scroll to switch workspace; DMS | COULD, quite secondary for me | DEFER | rail |
| 18 | Scroll volume on bar; caelestia | COULD, secondary | DEFER | — |
| 19 | Scroll brightness on bar; caelestia | COULD, secondary | DEFER | — |
| 20 | IPC bar toggle; DMS | MUST, and very important to have funcioning well with niri; in fact one ipc toggle should control only one bar (in case there are multiple bars) | KEEP: `gpuix-shell rail toggle --output eDP-1` | cli |
| 21 | Shadow/elevation; DMS | COULD, quite secondary. conceptually an elevation system is interesting but this should be minimal layershell logic, nothing more | DROP ("hairlines not shadows") | — |
| 22 | DPI-aware snapping; DMS Theme.px | SHOULD because dpi-aware anything is important | KEEP: GPUIX px vs output scale from Sway `get_outputs` | rail |
| 23 | Configurable animation duration; DMS | COULD, i really do not care about animations whatsoever | DROP | — |
| 24 | Content window separation; noctalia | COULD | DROP | — |
| 25 | Screen frame integration; Ambxst | COULD | DROP | — |
| 26 | Hot corners on bar edges; noctalia | SHOULD, niri itself also has hot corner but this one clearly has more potential | DEFER (Sway has no hot corners; a 1 px rail edge zone could do it later) | rail |

### 3.2 Bar widgets (rows 27–64)

| # | Feature / exact behaviour | Tom's priority (verbatim) | Disposition | Surface / notes |
|---|---|---|---|---|
| 27 | Workspaces indicator; noctalia compositor-agnostic | MUST, in fact in my concepts i had the workspace switcher as a separate left horizontal bar, whereas all the other modules exist in the top bar. | KEEP: the rail's 1…9 (+10) slots fed by Sway IPC, decorated with herdr agent status (◉ ◐ ● ✓ ○) | rail, sway, herdr |
| 28 | Clock; caelestia/tpaau | MUST, but no need to do anything fancier than configurable time and date. the minimal eqsh one was sufficient. | KEEP: vertical clock at rail bottom | rail |
| 29 | System tray; DMS TrayMenuManager | SHOULD, very nice to have but i won't be using it personally | DEFER (StatusNotifier + DBusMenu over dbus-next is the second-hardest D-Bus piece, `REVOLUTION/HARDEST-PARTS.md:68-74`) | rail |
| 30 | Battery indicator; tpaau UPower | MUST | KEEP: UPower via dbus-next | rail |
| 31 | Network/WiFi indicator; caelestia ethernet fallback | MUST | KEEP: NetworkManager via dbus-next; click → wifi menu | rail, controls |
| 32 | Bluetooth indicator; tpaau popup | MUST | KEEP: BlueZ; click → bluetooth menu | rail, controls |
| 33 | Volume/audio indicator; caelestia | MUST | KEEP: `wpctl` poll/`pw-dump --monitor` | rail |
| 34 | Media/MPRIS widget; DMS dynamic show/hide | MUST | KEEP: MPRIS over dbus-next; Navidrome demo (BRIEF §5) sits beside it | rail, launcher |
| 35 | Notification indicator; tpaau DND + count | MUST | KEEP: unread count from own daemon | rail, notif |
| 36 | Active/focused window; caelestia popout | MUST | KEEP: Sway focused container title (Tom's 03-26 B3 note: Claude Code titles alone were "sufficient" as agent status) | rail, sway |
| 37 | Power/session menu; equora Apple menu, Ambxst | MUST, in fact i really like the DMS one which made you "hold a key for x seconds with a visual progress bar"; in addition to being able to scroll through them. | KEEP → `gpuix-shell power` | power |
| 38 | Launcher button; DMS | SHOUlD, trivial to add but i won't use it personally | DEFER | rail |
| 39 | Privacy indicators (mic/cam/screen); DMS PrivacyService | MUST, and i'll likely develop a specific widget around it | KEEP: PipeWire link-group scan (`spec/os.shell.md:454-462` gives the regex filter `/cava|monitor|system/i` and `lsof /dev/video*` fallback) | rail |
| 40 | CPU/memory monitor; DMS | SHOULD, good to have but i don't intend to use it myself | DEFER | — |
| 41 | VPN indicator; DMS | MUST. it is CRUCIAL for me to know if i'm connected to tailscale, and possibly to know what other devices are connected on my tailscale network. i am aware that there are 2+ different tailscale DMS extensions, happy to bring them over in due time | KEEP: `tailscale status --json` (script `friday-testing/integrated-shell/integration/bin/vpn-status` already emits JSON) | rail |
| 42 | Keyboard layout; caelestia | COULD, nice to have but i won't be using it | DROP | — |
| 43 | Weather; sshell | COULD, nice to have but i won't be using it | DROP | — |
| 44 | Clipboard button; DMS | COULD, nice to have but i won't use it | DROP (clipboard is a launcher mode) | — |
| 45 | Idle inhibitor toggle; DMS | COULD | DEFER | — |
| 46 | Color picker button; DMS | COULD, i intend to use colorpicker but with a niri shortcut | REPLACE: `colorpicker` script + Sway bind already exist | script |
| 47 | System updates count; DMS | SHOULD, this would be interesting and i would have to build functionality specifically for my fedora atomic system. still, a nice touch | DROP (NixOS now; no equivalent) | — |
| 48 | Audio visualizer; noctalia | SHOULD, i loved dms' popup for music and its associated "scroll through to skip parts of the song". | KEEP the scroll-to-seek media popout, not the FFT | rail, launcher |
| 49 | Caps/Lock indicator; DMS | SHOULD, trivial but i won t use it | REPLACE: Caps Lock now toggles the touchpad with an OSD (commit 7e082fbb) | osd |
| 50 | Global menu bar (macOS); equora | COULD, i did have it but i'm not really using it | DROP | — |
| 51 | AI button; equora | COULD, same as 50 equora has it but i never use it | DROP (ask surface is keybind-driven) | — |
| 52 | Dark mode toggle; noctalia | COULD but as you know my shell has NO light/dark mode: it's all Dark Glass aesthetic | REPLACE: `theme` script + `theme-prompt` (noir / claude-dark / claude-light) | theme |
| 53 | Night light toggle; noctalia | COULD, i won't use it myself, but do it keeping in mind that this will require special functionality as i use a specific gamma tool wl-gammarelay-rs which is the only one that does per-monitor to my knowledge | DROP | — |
| 54 | Power profile selector; noctalia | COULD, very secondary | DEFER (could be a `controls` row) | controls |
| 55 | Brightness widget; noctalia | COULD | REPLACE: `brightness` script + OSD | osd |
| 56 | Microphone widget; noctalia | COULD | DEFER | controls |
| 57 | Wallpaper selector; noctalia | COULD, i m not too big on wallpaper changing and other cosmetic trivialities | DROP (wallpaper is solid #000000) | — |
| 58 | Custom IPC button; noctalia | SHOULD | KEEP cheaply: a rail module that runs a command | rail |
| 59 | BongoCat | WONT, we're building a serious shell | DROP | — |
| 60 | Recording indicator; equora privacy dots | MUST, i will use that | KEEP (same PipeWire scan as #39) | rail |
| 61 | Network speed monitor; DMS | SHOULD, nice to have, possibly cool to have it toggled when we press the wifi/network button or as standalone | DEFER into the wifi menu detail | controls |
| 62 | Apps dock in bar; Ambxst | COULD, wouldn't use it directly | DROP | — |
| 63 | Notepad button; DMS | COULD | DROP | — |
| 64 | Pin button (auto-hide toggle); Ambxst | COULD, i prefer toggling things with keybinds | DROP | — |

### 3.3 Notifications (rows 65–82)

| # | Feature / exact behaviour | Tom's priority (verbatim) | Disposition | Surface / notes |
|---|---|---|---|---|
| 65 | Notification daemon (owns `org.freedesktop.Notifications`); DMS | MUST this one is non-negociable | KEEP → `gpuix-shell notifications` D-Bus server (replaces mako) | notif |
| 66 | Configurable popup position (6+); DMS | MUST | KEEP (default top-right 390 wide, BRIEF §3.3) | notif |
| 67 | Notification center / history panel; DMS Current/History tabs | MUST, although the specific aesthetic of it is not clear in my mind. | KEEP as a launcher mode or a rail popout; Tacit `notificationPopup` for the look | notif, launcher |
| 68 | App-name grouping; DMS collapsible | MUST, seems trivial to implement like how DMS did it | KEEP | notif |
| 69 | Inline action buttons; DMS, noctalia | COULD, not necessary to have in the first implementation but hapy to revisit the importance of that functionality once this level of detail becomes in discussion | KEEP anyway: the `herdr-sway-context` branch already routes `herdr-attention` → mako actions (BRIEF §2), so actions are needed day one | notif, herdr |
| 70 | JSON-file history persistence; DMS | MUST, useful | KEEP | notif |
| 71 | Do Not Disturb toggle; DMS rules | SHOULD, likely something i toggle with a keybind or a button on bar | KEEP (`gpuix-shell notifications dnd`), PR #571 Mod+o dismiss is the sibling bind | notif, cli |
| 72 | Rules engine (regex, 5 actions); DMS | MUST, nice to have from DMS | KEEP, config-driven | notif |
| 73 | Swipe-to-dismiss; noctalia | COULD, not too urgent, possibly nice ot have as cosmetic later | DROP | — |
| 74 | Per-urgency timeouts/colours; noctalia | MUST | KEEP | notif |
| 75 | Notification sounds; DMS | SHOULD, dms phenomenal reference | DEFER (Tom: "i barely expect nofitication sounds anyway", `:640`) | — |
| 76 | Progress indicator (hints.value); caelestia | COULD, revisit after | DEFER | — |
| 77 | Keyboard navigation in centre; DMS hints overlay | MUST, dms hints overlay philosophy is very desirable | KEEP (vim-style hints in the launcher's notification mode) | notif, launcher |
| 78 | Lockscreen notification display; DMS | COULD, to be revisited later, i rarely to never lock my screen | DROP | — |
| 79 | Privacy mode (hide body); DMS | SHOULD, since we re relying mostly on dms implementation as inspiraton | DEFER | notif |
| 80 | Cross-generation restoration; nucleus | COULD, to be revisited in a second pass | DEFER | — |
| 81 | Image caching for history; caelestia | SHOULD | KEEP small | notif |
| 82 | Flood protection (20/s); DMS | MUST, to avoid dangerous or strange behavior on my system | KEEP | notif |

### 3.4 Launcher / app drawer (rows 83–103)

| # | Feature / exact behaviour | Tom's priority (verbatim) | Disposition | Surface / notes |
|---|---|---|---|---|
| 83 | App search (fuzzy); caelestia dual engine, DMS fzf+plugins | MUST | KEEP (Vicinae parity is tonight's bar) | launcher |
| 84 | Calculator; caelestia Qalculator | COULD, nice to have | KEEP cheaply (Vicinae ships one) | launcher |
| 85 | File search; DMS dsearch, noctalia fd | MUST, and fd plugin seems sufficiend, dms' dsearch was overkill and having a separate package for that is not desirable | KEEP: `fd` provider | launcher, files |
| 86 | Clipboard mode in launcher; noctalia ClipboardProvider | MUST, it's important for me to have the clipboard history shown in the same aesthetic as the launcher; also making sure that we are displaying images (i use cliphist, prefer not to create special rust functionality...) | KEEP: `@` mode with image thumbnails; store per BRIEF §3.4 (own `wl-paste --watch` store, a change from cliphist — see §6.1) | launcher |
| 87 | Emoji picker; noctalia | SHOULD, emoji is somehting i have had for years, previously in a handrolled fzf menu, but now we have so many of those emoji pickers it should be trivial to create our own or rip the most performant one | KEEP: `:` mode | launcher |
| 88 | Plugin/provider system; noctalia 8 built-in + 12 plugins | MUST, dms provider concept is powerful | KEEP: provider interface (`spec/os.shell.md:133-166` LauncherProvider/Result/Action types are reusable) | launcher |
| 89 | Categories/tabs; noctalia 12 | SHOULD, noctalia 12 categories is good enough | DEFER | launcher |
| 90 | Favourites/pinned; caelestia SQLite frequency | MUST, and caelestia's sqlite frequency is very cool | KEEP: frecency in bun:sqlite | launcher |
| 91 | Usage tracking / frecency | SHOULD, same as above | KEEP (same store) | launcher |
| 92 | App overrides; DMS | COULD, but i like to control my .desktop apps from my local share applications in dotfiles so this is a little redundant | DROP (desktop entries stay in `home/vicinae.nix` → move to the new module) | — |
| 93 | dGPU launch option | WONT | DROP | — |
| 94 | Grid/List/Tile views; DMS | SHOULD: see my general notes on launcher below | KEEP list only (Raycast) | launcher |
| 95 | Preview panel; noctalia | COULD, extremely secondary | DEFER (Vicinae has detail panes; cheap once providers exist) | launcher |
| 96 | Action panel (Ctrl+Tab); DMS | SHOULD, this is a nice addition that makes our launcher raycast-like | KEEP (Raycast ⌘K actions) | launcher |
| 97 | Wallpaper picker mode | COULD, very secondary | DROP | — |
| 98 | Web search; whisker | COULD, explore implementation later if at all (seems redundant with opening a new google chrome tab...) | DEFER (Vicinae has it; low cost) | launcher |
| 99 | Shell command execution; noctalia `>cmd` | SHOULD, makes us raycast-like | KEEP: `>` mode | launcher |
| 100 | Prefix search modes; caelestia 8 prefixes | SHOULD, explore in second iteration | KEEP (prefix dispatch is the provider model) | launcher |
| 101 | RTL/i18n | DONT i explicitly reject i18n support for now. this is MY shell i'm not trying to reinvent the linux shell for the entire world | DROP | — |
| 102 | App blacklist/hide; caelestia regex | SHOULD because easy | KEEP | launcher |
| 103 | HyprlandFocusGrab dismiss | DONT because we're niri wm-exclusive. if there exists a niri alterantive would consider that as COULD | REPLACE: layer-shell `keyboardInteractivity: exclusive` + Escape + click-outside on Sway | launcher |

### 3.5 Audio / media / OSD (rows 104–132)

| # | Feature / exact behaviour | Tom's priority (verbatim) | Disposition | Surface / notes |
|---|---|---|---|---|
| 104 | PipeWire native audio; DMS, noctalia | MUST | KEEP via `wpctl`/`pw-dump` (no native binding in GPUIX; `REVOLUTION/ARCHITECTURAL-BOUNDARY.md:62-66` argues pw-dump gives ~95%) | rail, osd, controls |
| 105 | Per-app volume mixer; noctalia | COULD, to be explored later | DEFER | controls |
| 106 | Output/input device picker; DMS pin/sort/aliases | MUST | KEEP (the F9 `audio-route` picker already exists, commit 97ef81a9; wrap it) | controls, script |
| 107 | Output cycling via IPC; DMS | COULD | REPLACE: `audio-route` script | script |
| 108 | Device alias/rename (WirePlumber); DMS | SHOULD, could revisit that, doesnt have to be a part of the first launch | DEFER | — |
| 109 | Volume overdrive >100%; noctalia | DONT explicitly i like to have volume going from 0 to 100; only situation where that's not the case is in vlc media player | DROP (cap at 100) | osd |
| 110 | Volume jump protection; Ambxst 15% | COULD, can add later | DEFER | — |
| 111 | Per-device max cap; DMS | COULD, add later | DEFER | — |
| 112 | Volume feedback sounds; DMS | COULD, disabled by default | DROP | — |
| 113 | Spectrum visualizer (Cava) | DONT i don't care about that | DROP | — |
| 114 | Spectrum visualizer (native) | DONT i don't care about that | DROP | — |
| 115 | MPRIS play/pause/next/prev | MUST, universal anyway | KEEP (`media` script exists; MPRIS via dbus-next) | rail, launcher |
| 116 | MPRIS seek/position; DMS wave bar | MUST, love the progress bar | KEEP | rail, launcher |
| 117 | MPRIS shuffle/loop; DMS | MUST | KEEP | launcher |
| 118 | Multi-player management; noctalia dedup | SHOULD, explore later | KEEP minimal (Chrome vs mpv for Navidrome) | launcher |
| 119 | Synced lyrics; whisker | COULD | DROP | — |
| 120 | Player blacklist; noctalia | COULD | DEFER | — |
| 121 | Track art caching; DMS | SHOULD since dms does it | KEEP (Navidrome cover art) | launcher |
| 122 | Volume OSD; DMS 9 types 8 positions | MUST. an OSD is very imprtant to have. I found the eqsh one to be very nice (which i m using right now) | KEEP → OSD window in the notifications daemon (BRIEF §3.3 bottom margin 96); replaces `osd` script | osd |
| 123 | Brightness OSD; DMS | MUST but with a small caveat: i really don't care if the brightness is managed by my shell ... happy to have that being a toggle i control from niri keybinds | KEEP: `brightness` script keeps doing the work, then calls `gpuix-shell osd brightness N` | osd, script |
| 124 | Caps/Num/Scroll OSD; noctalia | COULD, revisit that, don't need it at launch | REPLACE: touchpad-toggle OSD already shipped (7e082fbb) | osd |
| 125 | Media playback OSD; DMS album art | SHOULD, since dms has it. | KEEP small (track-change toast) | osd |
| 126 | Audio output switch OSD; DMS | SHOULD | KEEP (F9 route change → OSD) | osd |
| 127 | Configurable OSD position; DMS 8 | SHOULD, like the dms 8 positions | KEEP one default + config key | osd |
| 128 | Per-type OSD enable | COULD but by default no need | DROP | — |
| 129 | OSD suppression when panel open; noctalia | SHOULD, since dms has it | KEEP | osd |
| 130 | Interactive slider in OSD; DMS | COULD, since dms has it | DEFER | — |
| 131 | Glass-morphism OSD; equora | COULD, if glassmorphism is easy to do with our setup | DROP (no frost tonight) | — |
| 132 | Toast-based OSD; tpaau | SHOULD, must learn more about what this does | KEEP by construction: OSD and toasts share one daemon and one visual language | osd, notif |

### 3.6 Network / Bluetooth (rows 133–157)

| # | Feature / exact behaviour | Tom's priority (verbatim) | Disposition | Surface / notes |
|---|---|---|---|---|
| 133 | WiFi scan/connect with password; DMS Go D-Bus | MUST | KEEP → wifi menu (NetworkManager over dbus-next; `fzf-nmcli` script is the interim) | controls, launcher |
| 134 | WPA-Enterprise auth; DMS SecretAgent | SHOULD | DEFER | — |
| 135 | WiFi disconnect | MUST | KEEP | controls |
| 136 | WiFi radio toggle; noctalia | MUST | KEEP | controls |
| 137 | Forget saved network; DMS | MUST | KEEP | controls |
| 138 | Saved network list; DMS | MUST | KEEP | controls |
| 139 | Hidden network connect; DMS | MUST | KEEP | controls |
| 140 | Network info (band/channel/BSSID); DMS | MUST | KEEP (detail row) | controls |
| 141 | Ethernet status; DMS | MUST | KEEP | rail, controls |
| 142 | Ethernet detail (IP/MAC/speed/DNS); DMS | MUST | KEEP | controls |
| 143 | VPN management; DMS | MUST | KEEP minimal: NM VPN list + Tailscale | controls |
| 144 | VPN multi-provider (WireGuard/Warp/Tailscale); caelestia | MUST with special focus on tailscale | KEEP: `tailscale status --json` peers list (Tom wants "what other devices are connected") | rail, controls |
| 145 | Network speed monitor; DMS | MUST | KEEP in detail view only (`/proc/net/dev`) | controls |
| 146 | Airplane mode; noctalia rfkill | MUST | KEEP (`rfkill`) | controls |
| 147 | NM SecretAgent; DMS Go | MUST | DEFER: nmcli's own agent prompts suffice; only needed for 802.1x (INFERRED) | — |
| 148 | Bluetooth power toggle | MUST | KEEP → bluetooth menu | controls |
| 149 | BT discovery/scan; DMS | MUST | KEEP | controls |
| 150 | BT connect/disconnect; DMS | MUST | KEEP | controls |
| 151 | BT pair/forget; DMS | MUST | KEEP | controls |
| 152 | BT pairing agent (PIN/passkey); DMS Agent1 | SHOULD | KEEP: Magic Trackpad and headphones need it; dbus-next can export `org.bluez.Agent1` (`REVOLUTION/HARDEST-PARTS.md:80-86` sizes it at 250-350 lines TS) | controls |
| 153 | BT battery display; DMS + UPower | SHOULD | KEEP cheaply | controls |
| 154 | BT codec detect/switch; DMS pactl | SHOULD | DEFER | — |
| 155 | BT device pinning; DMS top 3 | SHOULD | KEEP cheaply | controls |
| 156 | BT discoverable toggle; whisker | SHOULD | KEEP cheaply | controls |
| 157 | BT RSSI; DMS | SHOULD | KEEP cheaply | controls |

### 3.7 Compositor integration (rows 158–173)

| # | Feature / exact behaviour | Tom's priority (verbatim) | Disposition | Surface / notes |
|---|---|---|---|---|
| 158 | Multi-compositor facade; DMS 7 compositors | WONT. We are building this shell for niri ONLY. No multi-compositor support. | KEEP the spirit: Sway-only, no facade | sway |
| 159 | Niri IPC (dual socket); DMS/noctalia | MUST. Confirmed: Rust daemon uses niri-ipc crate with typed bindings, not the 1500-line QML dual socket pattern. | REPLACE: i3-ipc socket in-process (`swaymsg -t subscribe`) | sway |
| 160 | Niri config generation (KDL); DMS | COULD, maybe later if there is justifiable functionality to be gained there but otherwise prefer that the niri kdl config remain in chezmoi-backed dotfiles and not in the purview of the shell | DROP: Sway config stays in `home/dot_config/sway/` | — |
| 161 | Hyprland native module | WONT: we are niri only | DROP | — |
| 162 | Sway/i3 native module; DMS | WONT: we are niri only | REPLACE: now the only module | sway |
| 163 | ext-workspace-v1 (LabWC) | COULD, ext worspace is mostly implemmented in niri as well. i don't care about labwc | DROP (Sway IPC gives workspaces) | — |
| 164 | DWL/MangoWC | WONT | DROP | — |
| 165 | Workspace overview with thumbnails; Ambxst | COULD. Niri supports ext-image-copy-capture-v1, so thumbnails are technically feasible — but no existing shell has done it for niri. Not trivial. | DEFER: the Mod+i switcher (PR #565) lists names + herdr status, no thumbnails | switcher |
| 166 | Window drag between workspaces | COULD. Same as #165 ... uncharted territory. | DROP | — |
| 167 | Window rules GUI | WONT i don't care about editing window rules with gui | DROP | — |
| 168 | Scratchpads; piri | SHOULD this is piri functionality so would like to have it baked in | REPLACE: Sway has native scratchpad (`move scratchpad` / `scratchpad show`); expose as launcher commands | sway, launcher |
| 169 | Window swallow (PID); piri | SHOULD this is piri functionality so would like to have it baked in | DEFER (no Sway native; herdr projector windows make it moot, INFERRED) | — |
| 170 | Animated workspace indicator; HyprQuick | COULD. Not compositor-specific ... Low priority. | DROP | — |
| 171 | Debounced event processing; noctalia 50 ms | COULD, i like noctalia's 50ms but not sure we need it | KEEP 50 ms debounce on Sway events (cheap) | sway |
| 172 | Output config generation; DMS | COULD, for now i use `kanshi` to manage outputs and resolutions etc but happy to revisit this later down the line | DROP (`monitors-off` script + Sway output config) | script |
| 173 | Niri overview toggle; tpaau | MUST, but i think this is just something you feed through the niri config with keybind/ipc | REPLACE: Mod+i switcher is the Sway analogue | switcher |

### 3.8 Settings / theming / config (rows 174–202)

| # | Feature / exact behaviour | Tom's priority (verbatim) | Disposition | Surface / notes |
|---|---|---|---|---|
| 174 | Dedicated settings GUI; DMS 25 tabs, noctalia 20 | MUST | REPLACE: Nix options + `gpuix-shell.json` fragment; a read-only "settings" launcher mode at most (Tom `:452`: one-person shell, "no hierarchy") | theme, launcher |
| 175 | JSON FileView persistence; all | MUST | KEEP: the theme fragment is JSON, watched live (BRIEF §3.5) | theme |
| 176 | Settings search; noctalia | MUST | REPLACE: launcher searches settings commands (Vicinae pattern) | launcher |
| 177 | Schema migration; noctalia | COULD, evenually and in case i do have a schema to migrate from. icebox for now | DROP | — |
| 178 | Config validation; Ambxst | SHOULD, but has to be something that is not hardcoded - it has to validate the config schema programaticaly | KEEP: validate `gpuix-shell.json` against a TS schema at load | theme |
| 179 | Presets/profiles; Ambxst | COULD, much later down the line. icebox for now | DROP | — |
| 180 | First-run wizard; noctalia 5-step | SHOULD, in fact this is a | DROP (Nix deploy; see also #265 MUST—contradiction left as is) | — |
| 181 | Material You / matugen | WONT whatsoever: no material or material you (i don't like it); no matugen whatsoever ... | DROP | — |
| 182 | Predefined colour schemes | WONT in the sense that we have only one predefined colorscheme | SUPERSEDED: three schemes now (noir, claude-dark, claude-light) | theme |
| 183 | Dark/light toggle | COULD far down the line support a single universal dark/light toggle. icebox for now | SUPERSEDED: `theme` script switches at runtime | theme |
| 184 | Auto dark/light | WONT: even if i do eventually add a light mode this should only be toggled manually | KEEP (manual only) | theme |
| 185 | OLED mode; Ambxst | MUST. OLED mode ie make the black colors #000000 is something that i do by default ... | KEEP: noir default | theme |
| 186 | Cross-app theming | WONT. this is also a clear design decision that i take from the start: i do not need help managing my gtk or qt theme etc. that is what dotfiles are for. | KEEP as a boundary: the shell reads `~/.config/theme`, never writes GTK/Qt | theme |
| 187 | Configurable fonts; DMS | SHOULD but the default font, like eqsh, is sanfrancisco mono. | SUPERSEDED: Anthropic Sans 12 UI, mono for figures (BRIEF §3.5); fonts via `registerFont` | theme |
| 188 | Animation speed control | WONT. ... i would make it none/short for snappiest experience | KEEP: one 50 ms duration, opacity/transform only (B12/B13) | theme |
| 189 | Transparency/opacity config | SHOULD. Compositor (niri) owns blur ... CSS just sets background-color alpha. | SUPERSEDED: flat and opaque, no blur | theme |
| 190 | Animated colour transitions | WONT. no need | DROP | — |
| 191 | Wallpaper picker; noctalia | SHOULD because we are indeed controlling the monitor from quickshell side of things (not niri config) | DROP (wallpaper `#000000`) | — |
| 192 | Per-monitor wallpaper | SHOULD, if we have a wallpaper picker then might as well have it per-monitor (i mostly use dual monitor setup) | DROP | — |
| 193 | Wallpaper fill modes | SHOULD | DROP | — |
| 194 | Parallax wallpaper | WONT i explicltly don't need parallax because it makes me dizzy | DROP | — |
| 195 | Wallpaper slideshow | COULD much later down the line since we have the wallpaper utility anyway | DROP | — |
| 196 | Procedural sky | WONT too fancy | DROP | — |
| 197 | i18n | WONT no i18n whatsoever, shell is always in english. | DROP | — |
| 198 | Per-monitor config overrides | COULD but again we manage config with kanshi preferably so might revisit that later | KEEP minimal: per-output rail module list (#6) | rail |
| 199 | IPC config changes; DMS | SHOULD | KEEP: `gpuix-shell set key value` on the socket for ephemeral state | cli |
| 200 | Plugin config support | COULD but we will do that much later down the line ... an ephemeral pomodoro widget has the same place as the main launcher (there is no hierarchy) | KEEP as a value: no plugin browser; modules are code in dotfiles | — |
| 201 | Config versioning | COULD in the future in case i need to migrate a lot. but since it's a single user project we don't need to do a lot of versioning in public. | DROP | — |
| 202 | Gradient/halftone | WONT | DROP | — |

### 3.9 Session / security (rows 203–224)

| # | Feature / exact behaviour | Tom's priority (verbatim) | Disposition | Surface / notes |
|---|---|---|---|---|
| 203 | Lockscreen (WlSessionLock); DMS | COULD this functionality is quite secondary. i bypass lockscreen by default on reboot (already implemented in my os with greetd automation); and when i need to rest my desktop i do `systemctl sleep`. ... icebox for now | DEFER (GPUIX has no ext-session-lock; swaylock if ever) | — |
| 204–215 | PAM, fingerprint, U2F, virtual keyboard, media/notifs/weather on lock, shake, video screensaver, greetd greeter, user/session selection | COULD, icebox for now, like above (×11); #212 WONT, too fancy | DEFER / DROP | — |
| 216 | Polkit agent; DMS | MUST. i do not like the classic gtk greeter ... this is low-hanging fruit | KEEP: export `org.freedesktop.PolicyKit1.AuthenticationAgent` via dbus-next and spawn `polkit-agent-helper-1` (`REVOLUTION/HARDEST-PARTS.md:88-94`, 150-200 lines) → prompt rendered by the notifications daemon window | notif, NEW process? |
| 217 | Polkit fingerprint | SHOULD, not vital for now but might as well | DEFER | — |
| 218 | Power menu (shutdown/reboot/suspend); DMS hold-to-confirm | MUST and in fact i want to mention that i like the new DMS powermenu the most with the ability to scroll/select through a list AND press and hold a given key to get the desired action | KEEP → `gpuix-shell power` with hold-to-confirm 1500 ms for shutdown/reboot/logout, instant suspend (`spec/os.session.md:210-226`) | power |
| 219 | Hibernate detection; DMS /sys/power/state | SHOULD, low hanging fruit | KEEP | power |
| 220 | Suspend-then-hibernate; DMS | SHOULD, low hanging fruit | KEEP | power |
| 221 | Userspace reboot; noctalia | COULD, icebox for now, have to explore this more | DROP | — |
| 222 | Session action confirmation dialog | COULD if i find this to be useful later down the line. for now icebox | REPLACE: hold-to-confirm is the confirmation | power |
| 223 | Compositor-agnostic logout | WONT. the webshell project is exclusive to niri window manager | REPLACE: `swaymsg exit` only | power |
| 224 | Multi-compositor session detection | WONT unless we find that we need something else but know that i m using niri standard | DROP | — |

### 3.10 Idle management (rows 225–232)

| # | Feature | Tom's priority (verbatim) | Disposition | Surface / notes |
|---|---|---|---|---|
| 225–232 | Idle inhibitor, idle monitor, per-AC timeouts, fade-to-lock, custom idle commands, inhibit-when-audio, lock-before-sleep, caffeine | COULD the entire idle management suite is not so important for me, i prefer to icebox for now. this applies to 225-232 inclusive | DEFER; `monitors-off` script covers the one daily need | script |

### 3.11 Utilities (rows 233–267)

| # | Feature / exact behaviour | Tom's priority (verbatim) | Disposition | Surface / notes |
|---|---|---|---|---|
| 233 | Clipboard manager; noctalia clipper | MUST the clipboard manager is very important to me. note however that i use cliphist currently. i discuss the specifics of my implementation separately | KEEP → launcher `@` mode over own store (BRIEF §3.4) | launcher |
| 234 | Screenshots; DMS Go screencopy | WONT because existing niri window manager is sufficient | REPLACE: `screenshot` script (grim/slurp) + Sway bind | script |
| 235 | Screen recording; Ambxst | COULD look into what this entails but my first instinct is that i already use OBS Studio (as flatpak) to record screen, making this implmementation quite redundant | DROP | — |
| 236 | Screenshot editor; noctalia | WONT the builtin niri screenshot functionality is sufficient for me | DROP | — |
| 237 | Color picker; DMS | MUST but Color picker currently since i use niri window manager the screenshot tool exists and is sufficient | REPLACE: `colorpicker` script | script |
| 238 | OCR; Ambxst tesseract | SHOULD but with a twist ... handled with qwen 3.5 opensource multimodal llm ... Backend: HTTP call to llama.cpp server | KEEP later: region grab → strix:8731 multimodal (Flash-Next has a vision projector per AGENTS.md) → clipboard; a launcher command | launcher, ask |
| 239 | Calendar with events (khal); noctalia | SHOULD keep this idea for later | DEFER (Google Calendar is a shared utility, BRIEF §3.8 boundary) | — |
| 240 | Calendar month grid | WONT. the calendar month grid display will be handled by a bespoke, fullscreen, on-brand calendar app FAR later down the line ... | DROP | — |
| 241 | Terminal session management (tmux/zellij); DMS | MUST but i use shpool for terminal sessions, not tmux nor zellij ... requires further specialized scoping | REPLACE: **herdr** (workspace = kitty projector = Sway workspace); the rail reads `herdr workspace list` | herdr, rail |
| 242 | Power menu; noctalia | MUST, i believe i already discussed this earlier | KEEP (= #218) | power |
| 243 | Night light / gamma; DMS | WONT, my gamma control and night light is set once and not from the shell. skip entirely | DROP | — |
| 244 | Weather; caelestia | COULD. very secondary ... happy to bring that feature over later | DROP | — |
| 245 | System monitoring; DMS | COULD. very secondary ... | DEFER (`claude-capacity` script is the one monitor Tom runs) | script |
| 246 | Desktop widgets | WONT. i do not like widgets | DROP | — |
| 247 | AI assistant integration; Ambxst 5 providers | COULD but much later down the line. i do not need an ai integration the way it is done in the reference qml shells. i have some ideas here so not marking this as won't | NEW shape: `gpuix-shell ask` (OpenUI → GPUIX) is the bounded answer | ask |
| 248 | Update checker; DMS | COULD far later down the line, especially because this should be custom for my system | DROP | — |
| 249 | Notes/notepad; DMS | WONT. i use github-backed md notes. see no value in having external notepad. drop that | DROP | — |
| 250 | Pomodoro; noctalia | SHOULD the pomodoro timer concept is very valuable and i have my own approach for it ... this will be the first feature i release AFTER base webshell | KEEP: wrap `~/.local/bin/pomodoro` as a rail module + launcher commands | rail, launcher, script |
| 251 | Docker/Podman; noctalia | SHOULD Container management is very desirable on my system, i expand on thsi a little later | DEFER (strix-side; a launcher provider over `herdr`/`systemctl --user` later) | launcher |
| 252 | KDE Connect; noctalia | SHOULD; ... "android phone notification" is extremely desirable | DEFER (kdeconnect D-Bus → own notifications daemon; cheap once the daemon exists) | notif |
| 253 | QR scanner | COULD because easy but not urgent, ocebox | DROP | — |
| 254 | Google Lens | WONT, adds very little value over a google search in google chrome... | DROP | — |
| 255 | Greetd greeter | COULD but icebox, until i decide what to do with the greeter situation on my device | DROP | — |
| 256 | Polkit agent | MUST this one is important | KEEP (= #216) | notif |
| 257–259 | Screen pin, measurement, palette extraction | WONT (×3) | DROP | — |
| 260 | Webcam mirror | COULD this is indeed desirable, a bit like an "apple camera"; but icebox for now ... OBS studio ... is sufficient | DROP | — |
| 261 | Shutdown timer | WONT | DROP | — |
| 262 | Printer management; DMS IPP | COULD becaues it's "free" ... icebox for now because i don't use a printer at the moment | DROP (paper-daemon owns printing now, AGENTS.md) | — |
| 263 | Process manager; DMS | COULD later down the line ... extending to see running systemd services and quadlets | DEFER (launcher provider over `systemctl --user list-units` is cheap) | launcher |
| 264 | Changelog viewer | WONT | DROP | — |
| 265 | Onboarding wizard | MUST but this one will require specific scoping work before i configure it | REPLACE: `MORNING.md` + Nix deploy is the onboarding | — |
| 266 | Dependency doctor; DMS | COULD later on, don't see an immediate need right now | DROP | — |
| 267 | SDDM theme | WONT i do not use SSDM whatsoever ... | DROP | — |

### 3.12 Quick settings / control center (rows 268–280)

Header ruling `:597`: "WONT. i do not need a control center. this is not in scope for my project. this
applies to 268-280". Rows: 268 quick settings panel, 269 volume slider, 270 brightness slider, 271 WiFi
toggle+picker, 272 BT toggle, 273 DND toggle, 274 dark-mode toggle, 275 power profile, 276 night light,
277 idle inhibitor, 278 media player, 279 recording toggle, 280 screenshot button (no per-row
annotations).

Disposition (INFERRED): the DMS-style tile **grid** stays dropped; but tonight's order ("for wifi menu,
or bluetooth pairing menu; etc.") and BRIEF §3.2's `gpuix-shell controls` revive rows 271, 272, 273, 269
as **list-style menus** reachable from the rail icons and as launcher modes (Vicinae-style), which is how
Tom's own eqsh "Wifi tile ... expands to full NetworkManager panel" worked
(`transient-outputs/quickshell-shell-investigation/wave7-current-dotfiles.md:43-52`). See §6.1.

### 3.13 Gap rows (`ANNOTATED-feature-matrix.md:617-654`)

| Gap | Tom's priority (verbatim) | Disposition |
|---|---|---|
| Hotspot creation | WONT | DROP |
| Scheduled DND | WONT | DROP |
| Inline reply in notifications | WONT | DROP |
| Full-text search in notification history | WONT | DROP (though a launcher mode makes it free) |
| Brightness without CLI | WONT | DROP (`brightness` script) |
| Native clipboard manager | COULD. discussed externally. to be revisited later. could convince me to move away from cliphist | SUPERSEDED: BRIEF §3.4 takes the own-store path |
| Notification grouping by urgency | WONT | DROP |
| Notification snooze | WONT | DROP |
| Per-app notification sounds | WONT; i barely expect nofitication sounds anyway | DROP |
| Calendar event creation | COULD but much much further down the line | DROP (shared utility) |
| IME | WONT | DROP |
| Screen reader | WONT | DROP |
| Multi-user switch | WONT, i use single-user on my desktop | DROP |
| Spatial audio routing | WONT | DROP |
| HDR | WONT, i do not care much for hdr and not even sure niri/my monitor has it | DROP |
| Touch/gesture | COULD but much later down the line. I have `lisgd` installed for touch support. niri also has something with touch support. for now no need to configure this at all. icebox maximally | DEFER |

### 3.14 The agent-side list (`../annotated-kmux-feature-list-v0.md`, sections D–U) mapped to herdr

These were never shell features; they described the CCD/KMUX machinery. REPORTED items, INFERRED mapping:

| Item | 2026-03-26 design | Where it lives now |
|---|---|---|
| D1 status via hook scripts → JSON files, polled over SSH, `QFileSystemWatcher` | v0.1 "no daemon" | `herdr api snapshot` / `herdr agent list`; the rail polls (BRIEF §3.4) |
| D4g "Click entry → `niri msg action focus-workspace` jumps to agent" | sidebar entry click | rail slot click → `herdr workspace focus` / `swaymsg workspace N` |
| E1 FSM `spawning → working → waiting_for_approval → waiting_for_input → idle → error → completed` | locked | herdr's blocked ◉ / working ◐ / done ● / idle ✓ / unknown ○ (BRIEF §1) |
| G3 "Every agent is an interactive session in its own kitty window + shpool session + niri workspace" | topology | **herdr: one workspace = one kitty projector window = one Sway workspace**, nine-slot cap |
| G10 window title `kmux:<project>:<agent>` for auto-placement | niri window rules | herdr-projector + Sway `rules.conf` |
| H3/H4 TodoWrite parsed into per-agent task lists | sidebar | `herdr notification show` (read-only); not in the rail tonight |
| I1 `kitty @ send-text` input injection; I4 sidebar "approve" button | remote control | out of scope: the shell is read-only toward herdr and "acts through Sway" (BRIEF §1) |
| J1 shpool, J2 shpool fork "ABANDONED COMPLETELY", J3 kitty remote control | terminal layer | herdr server socket on strix + `herdr --remote strix` |
| K thin client (Strix server, XPS client) | "should; but for now it s all in server mode" | strix headless + Zenbook seat (AGENTS.md) |
| L1 sidebar 400 px right overlay; L2 five zones; L3 three-row entry; L4 status dots | CCD sidebar | herdr-web-ui rail 220/30/12/2/8 (BRIEF §2) is the design heir; the GPUIX rail is 56 collapsed / 220 expanded (BRIEF §3.3) |
| M ccd-indicator bar widget (active count, waiting badge, click toggles sidebar) | bar | rail workspace slots carry the status glyph; a summary badge at the rail top is cheap | 
| P1 cmux keyed status model; P3 no-focus-stealing; P4 env auto-injection | adopt | herdr's own; the shell inherits P3 (never steal focus from the rail) |
| Q1 "cmux: GPUI-based TUI rendering. We use web-over-compositor" | reject | inverted tonight: GPUIX (GPUI's TS port) is the renderer |

---

## 4. Design values found in this source

REPORTED unless marked; the "tonight" column is INFERRED from BRIEF §1/§3.

| Value | Where stated | Still binding tonight? |
|---|---|---|
| One-person shell, no plugin marketplace, "there is no hierarchy" between a pomodoro widget and the launcher | matrix `:452`, `:200` | Yes. Modules are code in dotfiles. |
| Everything toggled by compositor keybind, each surface addressable by one IPC verb | matrix `:34`, `:56`, `:149` | Yes: Sway binds → `gpuix-shell` CLI → socket (BRIEF §3.2) |
| Raycast is the launcher ideal; DMS as reference; Vicinae noted | matrix `:238` | Yes, with Vicinae now the parity target (BRIEF §5) |
| Workspace switcher as its own left bar; everything else elsewhere | matrix `:75` | Yes ("left bar ... replaces waybar", "no top bar") |
| Notification daemon non-negotiable; flood-protected; keyboard hints | matrix `:156`, `:180`, `:190` | Yes |
| Hold-to-confirm power menu with scroll | matrix `:95`, `:493` | Yes |
| Tailscale awareness is crucial | matrix `:103`, `:330` | Yes (closet LAN + Tailscale fallback, AGENTS.md) |
| Compositor-native tools for screenshot / colour / overview; the shell does not re-implement them | matrix `:528-534`, `:393` | Yes (scripts + Sway) |
| OLED black `#000000` by default | matrix `:422`; "Vercel OLED Minimal" (`INDEX-webshell-audit.md:628`) | Yes: noir |
| No matugen, no Material, no cross-app theming, no i18n, no animation knobs, no widgets, no parallax | matrix `:414`, `:424`, `:446`, `:428`, `:552`, `:440`; `tom-repo-notes.md:59-60` | Yes |
| Monochrome discipline, one accent | kmux B11; `spec/SPEC.md:270-320` | Changed: Claude palette accents per theme fragment |
| Dark-only, no light theme | kmux B14; `spec/SPEC.md:316` | Changed: claude-light in scope, manual switch only (`:420` still holds) |
| Compositor owns blur; web layer opaque fills | kmux B9/B10; `architecture-decisions:270` | Changed: no blur at all, flat and opaque ("hairlines not shadows") |
| 50 ms motion ceiling, `cubic-bezier(0.16,1,0.3,1)`, opacity+transform only | kmux B12/B13; `spec/SPEC.md:297-298` | Keep (consistent with "performance is not the thing", snappy by default) |
| Shell chrome 13 px base, 28-36 px rows, 4 px unit, ≤16 px padding, radius 4/6/10/14 | kmux N6/N7; `friday-testing/design-revamp/tokens.css` | Partly changed: Anthropic Sans 12, Tacit's generous padding and 8/12 corners (BRIEF §3.6) |
| SF Pro / SF Mono | kmux A14 "MUST and this is not implemented now" | Changed: Anthropic Sans/Serif/Mono |
| Lucide icons, stroke 1.5 px | kmux A15 "should, start with lucide" | Open: BRIEF names "Anthropicons" glyph font; Lucide is the fallback (INFERRED) |
| Status from structured data, never screen scraping | kmux B3 | Yes: herdr snapshot |
| Composition over monolith; the filesystem is the API | kmux B6/B7 | Yes in spirit: `herdr` CLI, `swaymsg`, `wpctl`, scripts; one socket, no Rust daemon |
| "the use-case precedes the surface" (anti-maximalism) | `../june16-cowl-revived.md:36-40` | Yes; build the eight named surfaces, not 280 rows |
| Code-style passes after function: lean on Rust-utility style (piri, niri-ipc, niri) | `LATER-postcleaning-prelaunch.md` | Carry forward as a MORNING.md note |
| Spec template "Goals/Non-Goals, Domain Model, Backend Routing, API, Behavioral Contracts, Test Assertions, Conformance" | `spec/SPEC.md:480-494` | Reusable structure for per-surface docs |

---

## 5. Reusable code and data (exact paths)

All under `/home/tom/notes/references/devlogs/1h26/april-webshell-refs/` unless `../`. MEASURED existence; usefulness INFERRED.

### 5.1 Directly reusable in `pkgs/gpuix-shell/`
- `spec/os.d.ts` (2131 lines): typed namespaces `os.audio`, `os.bluetooth`, `os.brightness`, `os.clipboard`,
  `os.command`, `os.db`, `os.input`, `os.media`, `os.network`, `os.notifications`, `os.outputs`,
  `os.polkit`, `os.power`, `os.session`, `os.settings`, `os.shell`, `os.tray`, `os.windows`,
  `os.workspaces`, `os.claude`, `os.terminal`. Rip the domain types (AudioSink, BluetoothDevice,
  Notification, NotificationRule, PowerActionInfo, LauncherProvider/Result/Action, Workspace with `meta`)
  into `src/model/`; drop the WebChannel method shapes.
- `spec/os.shell.md:133-166` LauncherProvider / LauncherResult / LauncherAction and `:434-452` the query
  state machine + ranking formula (`finalScore = fuzzyScore*0.7 + frecency*0.3`, prefix dispatch).
- `spec/os.notifications.md:297-405` lifecycle state machine, rules evaluation, flood protection (20/s,
  critical bypass), DND, history pruning, hover-pause, hints keyboard nav — the contract for
  `gpuix-shell notifications`.
- `spec/os.session.md:193-260` power action availability (`loginctl can-*` + `/sys/power/state`),
  hold durations, single-action guard, optimistic shutdown — the contract for `gpuix-shell power`.
- `spec/os.shell.md:454-462` privacy indicator derivation from PipeWire links (regex excludes
  `cava|monitor|system`; camera via `lsof /dev/video*` 2 s poll).
- `spec/os.clipboard.md` and `spec/os.workspaces.md` / `os.windows.md`: 50 ms debounce, 1 s reconnect
  backoff, sorting rules, error codes (`NOT_FOUND`, `NOT_SUPPORTED`, `TIMEOUT`, …, `spec/SPEC.md:203-233`).
- `REVOLUTION/HARDEST-PARTS.md` tiers with TS line estimates per D-Bus service (notifications 200-300,
  tray+DBusMenu 250-400, BlueZ+Agent1 250-350, polkit 150-200, MPRIS 100-150, UPower 60-80) and
  `REVOLUTION/DBUS-LIBRARY-ASSESSMENT.md` (dbus-next chosen; BRIEF §3.4 agrees).
- `REVOLUTION/ARCHITECTURAL-BOUNDARY.md:72-80` mechanism table (D-Bus proxy / D-Bus server / ObjectManager
  / NDJSON socket / subprocess / sysfs / HTTP) — the exact seam list the GPUIX process needs.

### 5.2 Scripts (bash; adapt to the `gpuix-shell` CLI)
- `friday-testing/integrated-shell/integration/bin/` (28 files): `vpn-status` (Tailscale → WireGuard →
  NM VPN JSON), `powermenu` (sysfs battery + acpi time), `pomodoro` (156 lines, file-mtime timer — same
  lineage as today's `~/.local/bin/pomodoro`), `battery`, `wifi-menu.sh` (iwmenu), `fzf-nmcli`,
  `dnd`, `recording-toggle`, `record`, `screenshot`, `colorpicker`, `media`, `volume`, `brightness`.
  Today's dotfiles already carry the modern versions (BRIEF §2); the old ones document the verb set.
- `wednesday-testing/rewrite/integration/FEATURE-PARITY.md` (220 lines): the MUST checklist with
  per-feature status and the IPC verb mapping (`shell toggleBar`, `toggleOverlay`, `toggleCcd`,
  `toggleNotifications`) — a ready template for `tests/gpuix-shell/` coverage lists.

### 5.3 Design tokens (for `home/themes/default.nix` → `gpuix-shell.json`)
- `friday-testing/design-revamp/tokens.css` (115 lines): materials m2–m5 `#0a0a0a/#111111/#161616/#1c1c1c`,
  text 0.92/0.56/0.36/0.18, hover 0.04 / active 0.02 / selected accent 0.10, borders 0.06/0.10/0.18,
  radius 4/6/10/14, spacing base-4, z-index ladder, 50 ms easing. The noir fragment can keep the
  luminance ladder and swap the accent for the Claude palette.
- `friday-testing/design-revamp/DESIGN-SYSTEM.md`, `surfaces/*.module.css` (bar, dock, lockscreen,
  notifications, osd, overlay, settings, ccd-sidebar): per-surface layout CSS worth reading for sizes.
- `friday-testing/pre-sync-originals/SOLIDJS-THEME-SYSTEM.md` "THE canonical design system" (3-tier
  tokens, 22-component material mapping, 14 anti-patterns) per `00-HANDOFF.md:26`.
- Agent status colours (two generations): `KMUX-INTEGRATION-SURFACE.md:579-587` (`#5B9DFF` working,
  `#F5A623` waiting, `#FF453A` error, `#30D158` done) and kmux L4 (`#60A5FA`, `#FBBF24`, `#F87171`,
  `#34D399`, detached 0.25) — herdr-web-ui DESIGN.md supersedes both (BRIEF §2).

### 5.4 Reference snippets (`snippets/`, 102 files)
- `snippets/bridge/dms-popout-manager.qml`, `dms-modal-manager.qml`, `dms-widget-host.qml`,
  `noctalia-plugin-api.qml`: popout/modal registries and the plugin API shape.
- `snippets/bridge/fabric-input-mask-observer.tsx`: ResizeObserver → input-region reporting (the GPUIX
  launcher overlay needs the same idea if it is ever a full-screen surface; BRIEF §3.3 sizes it 700×580
  instead, which avoids masking).
- `snippets/daemon/dms-brightness-sysfs.go`, `dms-dpms-wayland.go`, `snippets/services/network-detect.go`.
- `transient-outputs/quickshell-shell-investigation/wave6-snippet-catalog.md`: 170 snippet candidates by
  domain, with P0/P1 ratings.

### 5.5 Not reusable (abandoned lineages, keep as history)
- `REVOLUTION/SURFACE-MATRIX.md`, `EMBEDDER-RIP-MATRIX.md`, `rip-matrix-electron-cef.md`,
  `TS-RIP-MATRIX.md`, `sunday-testing/cowl/**`, `DOCS-v0.5.0.md`: Chromium Ozone layer-shell patching
  (COWL). GPUIX gives layer-shell natively (`render(node,{layerShell:…})`, BRIEF §2), so this entire
  problem class is gone.
- `tuesday-validation/`, `wednesday-testing/`, `thursday-testing/`: quickshellX + QtWebChannel + SolidJS
  builds and the Rust `webshell-daemon` (ipc, niri, brightness, clipboard, loginctl, cli, orchestrator,
  signals — `TIMELINE.md:32`). Sway + no daemon tonight.
- `REVOLUTION-2/` browser-unification (agency.agency, surface promotion/demotion, extension continuum
  `.agency.ts`): Chrome stays a separate app (BRIEF §3.8 boundary).

---

## 6. Gaps, conflicts and what herdr now owns

### 6.1 Rulings that changed between March and tonight (flag for MORNING.md / ASSUMPTIONS.md)

| March ruling | Tonight | Resolution taken (INFERRED) |
|---|---|---|
| "niri ONLY" (`:363`), every niri reference | Sway only (BRIEF §1) | Sway IPC; drop niri-specific rows (#159-164, #173 overview) |
| "WONT ... control center ... 268-280" (`:597`) | "wifi menu, or bluetooth pairing menu" + BRIEF §3.2 `controls` | Build **menus**, not a tile grid: list-style, launcher-mode and rail-popout; name the surface after what it is ("menus"), ASSUMPTIONS line recommended |
| "No light theme" (B14, `SPEC.md:316`), "only one predefined colorscheme" (`:416`) | noir + claude-dark + claude-light | Three themes via `~/.config/theme`; manual switch only (`:420` survives) |
| SF Pro / SF Mono MUST (A14) | Anthropic Sans/Serif/AnthropicMono | Anthropic fonts; never in git |
| Compositor blur, 0.85 opacity (B9/B10, `:430`) | no blur, flat, opaque, `#000000` wallpaper | Opaque fills on `#000000`; hairline borders |
| Accent `#5B9DFF` "yes for now" (B11) | Claude palette from `home/themes/*.nix` | Theme fragment supplies accent |
| cliphist, "prefer not to create special rust functionality" (`:203`) | BRIEF §3.4 own store over `wl-paste --watch` | Own store in TS (not Rust); Tom's gap note `:634` "could convince me to move away from cliphist" licences it; keep `cliphist` import path optional |
| Quickshell native singletons "irreplaceable" (`architecture-decisions:56-69`) | GPUIX has none of PipeWire/MPRIS/UPower/BlueZ/NM/Notifications/Polkit/Tray | All through dbus-next + `wpctl`/`pw-dump` + subprocesses, exactly the REVOLUTION boundary table (`ARCHITECTURAL-BOUNDARY.md:72-80`) |
| Rust daemon as entry point | one TS process per surface family + socket | No daemon; Sway binds call the CLI |
| Top bar + left workspace bar (`:75`) | left rail only, "no top bar" | Clock/battery/network/bluetooth/audio/privacy/tailscale all live in the rail's bottom zone |
| Dock surface in every spec (`spec/surfaces.md:81-113`) | Tom's recorded aesthetic "no dock" (`INDEX-webshell-audit.md:628`); BRIEF has no dock | No dock |
| 13-feature "hard floor" includes lock screen + wallpaper + control center (`phase1-notes.md:143`) | lockscreen iceboxed by Tom, wallpaper solid, control center WONT | Floor tonight = rail, launcher, notifications, OSD, power, wifi/bt menus, binds (INFERRED) |

### 6.2 Where herdr takes the role an older design gave to something else

| Older design element (2026-03/04) | Pointer | herdr today |
|---|---|---|
| CCD sidebar (right, 400 px, overlay, all workspaces) showing Claude sessions, status dots, permission cards | `KMUX-INTEGRATION-SURFACE.md:33-47`, `spec/surfaces.md:266-300` | herdr-web-ui is the chat/desk; the GPUIX **left** rail shows herdr workspace status per Sway slot; no right sidebar |
| KMUX sidebar multiplexing tabs + agents + terminals + apps per niri workspace | `REVOLUTION-2/revisions/KMUX-SIDEBAR-CONCEPT.md:16-71` | herdr workspace = Sway workspace = one kitty projector; the rail is the session list (Tom tonight: "lots of herdr-web-ui centricity here especially on the left sidebar idea") |
| `os.claude` (sessions, send, peek, search, FSM) and `os.terminal` (shpool sessions, kitty windows) | `architecture-decisions:136-158`, `spec/os.claude.md`, `spec/os.terminal.md` | `herdr api snapshot`, `herdr workspace list`, `herdr agent list`, `herdr notification show`; read-only from the shell |
| Hook scripts → status JSON → `QFileSystemWatcher` (kmux D1) | `../annotated-kmux-feature-list-v0.md:95-131` | herdr server owns status; shell polls the snapshot |
| shpool + kitty remote control as the terminal layer (A1/A3/B4/J1/J3) | kmux A, J | herdr server socket on strix; `herdr --remote strix` from the Zenbook |
| Agent workspace auto-routing via window-title rules (G10/G11) | kmux G | herdr-projector + Sway rules; Mod+1..9 / Mod+0 |
| ccd-indicator bar widget (active count, waiting badge, click → sidebar) | `KMUX-INTEGRATION-SURFACE.md:592-601` | status glyph on each rail slot; `herdr-attention` → Sway urgency + notification actions (branch `herdr-sway-context`) |
| "Existing focused-window indicator may suffice" for status (B3) | `00-HANDOFF.md:47` | superseded by herdr's typed status; keep the focused-title module anyway |
| Terminal session manager inspired by Ambxst's tmux manager (#241) | `tom-repo-notes.md:15` | herdr |
| Thin client over SSH + Tailscale (K) | `thin-client.md` | strix headless, Zenbook seat, ordinary OpenSSH (AGENTS.md) |

### 6.3 Open questions this source cannot settle (write to ASSUMPTIONS.md if a builder decides)

1. **Controls surface naming/shape.** March WONT on a control center vs tonight's menus. Default taken
   here: list menus (wifi, bluetooth, audio route, DND, power profile) as launcher modes + rail popouts;
   no grid.
2. **Polkit agent host.** Tom's MUST (`:489`) needs a D-Bus agent + a prompt window. Default: the
   notifications daemon process exports the agent and renders the prompt as a modal toast (keyboard
   exclusive). Unverified: whether GPUIX can give one process a second layer-shell window; BRIEF §2 says
   one window per renderer process, so it may need `gpuix-shell polkit` as its own process.
3. **System tray.** SHOULD, "won't be using it personally"; DBusMenu is the hard part. Default: not tonight.
4. **BlueZ pairing agent.** SHOULD in March; practically MUST for the Magic Trackpad on the Zenbook.
   Default: implement `Agent1` (`RequestConfirmation`, `RequestPasskey`) in the controls process.
5. **Clipboard store.** Own store vs cliphist (see §6.1). Default per BRIEF; keep images.
6. **Icons.** Lucide (A15) vs Anthropicons (BRIEF). Default: Anthropicons where a glyph exists, Lucide
   SVG otherwise.
7. **OCR via local model** (`:536`): Flash-Next has a vision projector, so the March plan is feasible
   today at strix:8731; not tonight.
8. **Pomodoro, KDE Connect, containers, systemd-unit browser** (`:560-586`): all "after base shell";
   pomodoro is the first (Tom's words). Cheap as launcher providers once the provider interface exists.
9. **The "ultimate desktop shell" phrase** lives in the June CADE taxonomy
   (`../CADE/cade-june11-idealized/research/ultimate-shell-feature-set.md`, 17 domains, "load-bearing
   6-10": bar, launcher, notifications, audio, network, power, session/lock/auth, MPRIS, tray, control
   center+theming) — not in this archive. If another wave1 reader covers CADE, cross-check; otherwise its
   "lock is a safe one-way verb; unlock is not a verb at all" protocol asymmetry (`:405`) is the one line
   worth importing into the `gpuix-shell` CLI design.

### 6.4 What I did not read (honest scope)

- `REVOLUTION/first-chat.md` and `second-chat.md` beyond their openings (2116 + 1523 lines of pasted
  chat); `REVOLUTION/secondchat-creted-artifacts.md` (3314 lines); the 92 `REVOLUTION-2` files except
  `KMUX-SIDEBAR-CONCEPT.md`, `SURFACE-PROMOTION.md`, `compiled/SURFACE-MODEL.md` (first 160 lines),
  `compiled/EXTENSION-ARCHITECTURE.md` (first 70), `VISION-SYNTHESIS.md` (first 60),
  `CONVERSATION-NUGGETS.md` (first 80), `sunday-overall-mapping.md` (first 40).
- The 21 `spec/os.*.md` bodies beyond Goals and Conformance for `os.shell`, `os.notifications`,
  `os.clipboard`, `os.workspaces`, `os.windows`, `os.session`; the other 15 only via `os.d.ts` headers.
- The build trees (`tuesday-validation/`, `wednesday-testing/`, `thursday-testing/`, `sunday-testing/`)
  beyond `FEATURE-PARITY.md` and the handoffs.
- MEASURED grep for `priorit` hit 100+ files; the hits outside the files above are either build-tree copies
  of `ccd-indicator/index.tsx` / `os.d.ts` or wave reports; none carried additional Tom annotations
  (MEASURED: `grep -c "^>" spec/*.md` → 0 in every spec file; Tom's `>` lines exist only in
  `ANNOTATED-feature-matrix.md` and `../annotated-kmux-feature-list-v0.md`).
