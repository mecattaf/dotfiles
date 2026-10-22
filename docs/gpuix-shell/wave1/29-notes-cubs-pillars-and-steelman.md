# 29 — Notes repo: CUBS pillars, shell-shape decision, the steelman, and Tom's annotated priorities list

Reader: Claude (Opus 5.5), wave 1b of the overnight gpuix-shell build, 2026-10-20/21. Read-only pass.
This file is the only thing I wrote.

Labels: **MEASURED** = I read it in the named file at the named line tonight. **REPORTED** = a file
says so and I did not check it independently. **INFERRED** = my own mapping or judgement.

Path aliases. Unless a path is absolute, note paths are relative to `/home/tom/notes/references/devlogs/1h26/`:

| Alias | File |
|---|---|
| **M** | `april-webshell-refs/ANNOTATED-feature-matrix.md` (701 lines; byte-identical copies at `may26/cade/cowl-{first,second}pass/docs/history/`, md5 `01cc4f85…`) |
| **K** | `annotated-kmux-feature-list-v0.md` (507 lines) |
| **CP** | `CUBS/CONCEPTUAL-PILLARS.md` · **SSD** `CUBS/SHELL-SHAPE-DECISION.md` · **SH** `CUBS/SESSION-HANDOFF.md` |
| **S01…S06** | `cubs-steelman/0N-*.md` · **CL** `cubs-steelman/CHAT-LOG.md` |
| **U** | `CADE/cade-june11-idealized/research/ultimate-shell-feature-set.md` (407 lines) |
| **MA** | `june27-cowl-nextsteps/noctalia-deep-analysis/00-MASTER.md` (455 lines) |
| **LIN** | `LINEAGE.md` · **ADD** `LINEAGE-ADDENDUM-jun30.md` · **LL** `LANDING-LEDGER.md` |

Dotfiles paths (`home/…`, `docs/…`) are relative to this worktree.

---

## 0. Bottom line

1. **MEASURED.** The "deeply annotated priorities list" Tom remembers is **M**. It covers 280
   features surveyed across 16 Quickshell shells, plus 16 gap rows. Tom marked every row
   MUST/SHOULD/COULD/WONT and added free-text reasons in `>` lines. **When:** the annotations are dated
   **2026-03-24**: `april-webshell-refs/TIMELINE.md:32` says "the exhaustive 16-shell feature matrix gets
   Tom's `>` annotations", and `PREVIOUS-SESSION-handoff.md:102` says "Tom annotated all 280 features …
   with MUST/SHOULD/COULD/WONT". That is about seven months before tonight.
2. **MEASURED.** A second annotated list followed two days later: **K** (2026-03-26). It holds Tom's
   rulings on the stack, architecture and agent sidebar. This is the closest pre-herdr design. Its
   "kmux"/"ccd" agent sidebar is what herdr plus the rail now covers.
3. **MEASURED.** The phrase "ultimate desktop shell" appears as the title of **U**, "The Ultimate Desktop
   Shell: Feature Taxonomy" (2026-06-11). It is agent-written: a DankMaterialShell-centred taxonomy of
   17 domains with a read/reversible/irreversible/secret classification for every control verb.
4. **REPORTED.** CUBS ("Chromium Unified Browser and Shell") is the June 28–30 landing of that lineage.
   It would have been a tier-2 Chromium fork whose browser process is the shell daemon, drawing
   native Views C++ on layer-shell surfaces under niri. CADE (be the compositor) was proven to boot and
   then parked. All of the C++/Chromium substrate is dead tonight; GPUIX replaces it (BRIEF §3.1). The
   **functionality list, design values and abandonment reasons are what carry over**.
5. **INFERRED, from MEASURED parts.** Most of Tom's March rulings still hold under BRIEF §1 almost
   word for word:
   - one compositor only (niri then, Sway now)
   - keybind-first toggles, with one IPC toggle per bar
   - a vertical left bar for workspaces
   - a Raycast-grade launcher that also holds the clipboard
   - the notification daemon is "non-negociable"
   - Tailscale status is "CRUCIAL"
   - a polkit agent is a MUST
   - a DMS-style power menu with scroll plus press-and-hold
   - no matugen/Material You, no i18n, no desktop widgets, no notes app
   - OLED `#000000` by default; config lives in dotfiles, never in the shell
6. **INFERRED.** Four March rulings were **reversed by later Tom rulings**. Later agents must not
   "restore" them:
   - dark-glass/compositor blur → flat and opaque
   - SF Pro/SF Mono → Anthropic fonts
   - "NO light/dark mode" → noir, claude-dark and claude-light, switched by hand
   - "niri ONLY" → Sway only
7. **CONFLICT, MEASURED.** Tom wrote "`>> WONT. i do not need a control center. this is not in scope for
   my project. this applies to 268-280`" (M:597). BRIEF §3.2 plans `gpuix-shell controls`, a quick-settings
   surface. Steelman 06 already flagged the same clash on 2026-06-30 (S06:494-497). Resolution proposed
   in §6 G1.
8. **CONFLICT, MEASURED.** Tom said "i use cliphist, prefer not to create special rust functionality"
   (M:203) and "note however that i use cliphist currently" (M:526). Steelman 06 §A#27 also says "reuse
   `wl-paste` + `cliphist`". BRIEF §3.4 instead says "own store". See §6 G2.
9. **MEASURED.** Directly reusable prior art exists:
   - `jun26-cowl-secondpass-surfaces/ccd/app.js` is a working left workspace sidebar from June 26. It
     collapses into a rail by resizing the layer surface and its exclusive zone. It is the ancestor of
     the gpuix rail.
   - The same tree holds JS implementations of an fd.o notification server, a polkit agent and an SNI
     tray (`lib/*.js`).
   - **MA** carries `file:line` pointers into a noctalia v5 clone for every algorithm worth porting.
   See §5.

---

## 1. What the source is

### 1.1 Files read, and what each is

| File | Content date | Lines | Kind | Era |
|---|---|---|---|---|
| `CUBS/intro.md` | refers to Jun 16 and "two days later" | 17 | **Tom's own first-person note** (lowercase, informal) | cowl revived |
| `CUBS/extra-functionality.md` | same | 15 | **Tom's own note**: "bringing over all the functionality… (including the full annotation chapter)" | cowl revived |
| **CP** | 2026-06-28 | 165 | agent anchor doc: 4 pillars, Mir/miracle-wm lineage, packaging north-star | CADE |
| **SSD** | 2026-06-29 | 210 | agent decision doc: master surface map (23 rows), FREE/RESEAT/FORK/NEW/DROP grades | CADE (superseded on axis 1 by the steelman, S04:136-138) |
| `CUBS/M0-BUILD-PLAN.md` | 2026-06-28 | 123 | spike plan (sodimo box, GN args) | CADE |
| `CUBS/M0-SPIKE-RESULT.md` (sibling) | 2026-06-28 | 114 | spike log: ash-chrome builds, boots on fakes, GBM fixed by system Mesa | CADE |
| **SH** | 2026-06-28/29 | 320 | agent handoff: proven/blocked table, sodimo state, cade-drafts index | CADE |
| `CUBS/HANDOFF-views-shell-to-cade-drafts.md` | 2026-06-29 | 80 | agent→agent handoff; carries "Tom's steer": pull M5 (session/auth) forward | CADE |
| **S01–S05** | 2026-06-29 | 117/156/147/139/152 | agent "steelman" explainers written at Tom's request (CL:244-246) | CUBS |
| **S06** | 2026-06-30 | 605 | 20-agent consolidation: producer roster, surface inventory, settled §A (28 items), open §B (13 items) | CUBS |
| **CL** | 2026-06-29 | 266 | chat log. "**Tom's prompts are verbatim**" (CL:4), with the log writer's `…` elisions | CUBS |
| **LIN** | 2026-06-29 | 442 | 52-agent excavation of the whole lineage; §IV gems and aesthetic | index |
| **ADD** | 2026-06-30 | 77 | second-pass addendum (design-token constants, antedated gems) | index |
| **LL** | 2026-07-03 | 61 | migration ledger; dates each landed folder | index |
| **M** (sibling, named by S06:495 and SH:104) | annotated 2026-03-24 | 701 | **Tom's annotated matrix**: 280 rows + 16 gap rows + plugin-model table | webshell / quickshellX |
| **K** (sibling, named by LL:17 and ADD:67) | 2026-03-26 | 507 | **Tom's annotated kmux + QuickShellX list** (stack, principles, sidebar) | webshell / kmux |
| **U** (grep hit) | 2026-06-11 | 407 | agent research: "The Ultimate Desktop Shell: Feature Taxonomy" | CADE-idealized |
| **MA** (sibling, named by SH:104-105) | 2026-06-27 | 455 (read §0, §2.a–§2.e) | 30-agent synthesis of M against noctalia v5: coverage, Tier A/B/C pull-ins, gap list | cowl |
| `…/CADE-AUDIT-TABLES.md` §4 | 2026-06-28 | 112 (read §4) | ChromeOS DROP list | CADE |
| `jun26-cowl-secondpass-surfaces/ccd/app.js` head | 2026-06-26 | 181 (read 1-30) | the web left workspace sidebar with layer-shell collapse | cowl |

Not read, though named by these files: `CUBS/cade-drafts/**` (28 C++ draft units),
`CUBS/build-flag-investigation/*`, the 28 `noctalia-deep-analysis/SECTION-*.md` appendices (17,613
lines in total), `CADE-MASTER.md`, `CADE-CONTEXT.md`. All are C++/ChromeOS mechanics or per-cluster
detail behind **MA**. None is a Tom ruling. I judged them out of scope for a functionality pass.

### 1.2 The lineage in one table (REPORTED, LIN:32-41)

| Era | When | What | Fate |
|---|---|---|---|
| Headwaters (pre-kmux, webshell) | Oct 2025 – Mar 2026 | typed `os.*` namespace; "the filesystem IS the API" | the `os.*` idea survived; the web shell was dropped |
| quickshellX / webshell | Mar 2026 | Quickshell fork plus QtWebEngine, SolidJS surfaces over niri blur; **M** and **K** were annotated here | hit its ceiling: "There is no escape hatch" (LIN:83) |
| REVOLUTION → COWL | late Mar – Apr 2026 | own Chromium Content-API embedder, TypeScript all the way; booted in April under niri | revived Jun 16, superseded Jun 29 |
| kharness | May 2026 | substrate-maximalism at terminal scale | HOLD, "~20% load-bearing" (LIN:97) |
| CADE | Jun 6 – 12, spike Jun 28 | lift ChromeOS ash onto DRM; be the compositor | proven, then **parked** |
| cowl patch campaign | Jun 26 – 27 | top bar + `ccd` left workspace sidebar rendered under niri | substrate later abandoned; the **design** is reusable |
| CUBS | Jun 28 – 30 | one tier-2 binary; Views shell under niri | the substrate is dead tonight (GPUIX); the functionality list is alive |

After the notes stop: the `~/mecattaf/cubs` repo (2026-10-01, see `wave1/10-cubs-functionality-list.md`),
then the GPUIX pivot (Oct 13), the Hyprland trial (Oct 14) and tonight's Sway + GPUIX order (BRIEF §1).

### 1.3 What Tom's 2026-10-20 sentence resolves to (INFERRED from the MEASURED dates above)

- "as early as 6 months ago did i describe the 'ultimate desktop shell'". The **content** is the March
  annotation pair, **M** (03-24) and **K** (03-26). The **phrase** itself is the title of **U** (06-11).
- "a very detailed set of rulings": **K**'s locked-stack and principle rulings (A1–A15, B1–B15), plus
  the per-row `>` reasons in **M**.
- "deeply annotated priorities list": **M**, as above.
- "the spirit was very correct, even though i had not captured yet that i would be using the herdr
  project as centrally as i am". In those designs the agent and session layer was
  kerdr/ccd/shpool/kmux plus a right-hand 400 px "CCD sidebar". herdr now holds that whole role
  (§3.8).

---

## 2. Verbatim Tom rulings about the desktop shell

### 2.1 From the annotated matrix (2026-03-24), grouped by theme

Each bullet gives the source line in **M**, the row number and feature, and Tom's `>` line exactly as
written (typos included). Section-level notes (`>>` / `>>>` lines) are quoted as they appear. The full
per-row list is in §3.1.

**Scope, compositor and who owns config**

- M:7 · file header: “@claude i added my annotations with `>` lines”
- M:363 · #158 Multi-compositor facade pattern: “> WONT. We are building this shell for niri ONLY. No multi-compositor support.”
- M:369 · #161 Hyprland native module: “> WONT: we are niri only”
- M:371 · #162 Sway/I3 native module: “> WONT: we are niri only”
- M:375 · #164 DWL/MangoWC support: “> WONT”
- M:503 · #223 Compositor-agnostic logout: “> WONT. the webshell project is exclusive to niri window manager”
- M:505 · #224 Multi-compositor session detection: “> WONT unless we find that we need something else but know that i m using niri standard”
- M:367 · #160 Niri config generation (KDL): “> COULD, maybe later if there is justifiable functionality to be gained there but otherwise prefer that the niri kdl config remain in chezmoi-backed dotfiles and not in the purview of the shell”
- M:391 · #172 Output config generation (resolution/scale/HDR): “> COULD, for now i use `kanshi` to manage outputs and resolutions etc but happy to revisit this later down the line”
- M:381 · #167 Window rules GUI editor: “> WONT i don't care about editing window rules with gui ”
- M:424 · #186 Cross-app theming (GTK/Qt/terminals/editors): “> WONT. this is also a clear design decision that i take from the start: i do not need help managing my gtk or qt theme etc. that is what dotfiles are for. this also complements my "NO MATUGEN" decision”

**The bars, and the left workspace bar**

- M:18 · #1 Three-zone layout (L/C/R): “> MUST, this is basic bar config”
- M:24 · #4 Plugin widget system: “> MUST, it is important to be able to "turn any functionality" into a bar addition”
- M:32 · #8 Vertical bar layout: “> MUST, in fact i have a very specific use case in mind for that.”
- M:34 · #9 Auto-hide with hover reveal: “> MUST, could be useful but more important for me is that i want to toggle bars with a niri keybind (sigint)”
- M:40 · #12 Multiple simultaneous bars: “> MUST, i will in fact have multiple simultaneous bars in my config, and want to be able to toggle one but not the other”
- M:56 · #20 IPC bar toggle: “> MUST, and very important to have funcioning well with niri; in fact one ipc toggle should control only one bar (in case there are multiple bars)”
- M:75 · #27 Workspaces indicator: “> MUST, in fact in my concepts i had the workspace switcher as a separate left horizontal bar, whereas all the other modules exist in the top bar.”
- M:77 · #28 Clock: “> MUST, but no need to do anything fancier than configurable time and date. the minimal eqsh one was sufficient. ”
- M:149 · #64 Pin button (auto-hide toggle): “> COULD, i prefer toggling things with keybinds ”
- M:68 · #26 Hot corners on bar edges: “> SHOULD, niri itself also has hot corner but this one clearly has more potential”

**Status widgets Tom will actually use**

- M:95 · #37 Power/Session menu: “> MUST, in fact i really like the DMS one which made you "hold a key for x seconds with a visual progress bar"; in addition to being able to scroll through them. ”
- M:99 · #39 Privacy indicators (mic/cam/screen): “> MUST, and i'll likely develop a specific widget around it”
- M:103 · #41 VPN indicator: “> MUST. it is CRUCIAL for me to know if i'm connected to tailscale, and possibly to know what other devices are connected on my tailscale network. i am aware that there are 2+ different tailscale DMS extensions, happy to bring them over in due time”
- M:141 · #60 Recording indicator: “> MUST, i will use that”
- M:117 · #48 Audio visualizer: “> SHOULD, i loved dms' popup for music and its associated "scroll through to skip parts of the song". ”
- M:125 · #52 Dark mode toggle: “> COULD but as you know my shell has NO light/dark mode: it's all Dark Glass aesthetic”
- M:135 · #57 Wallpaper selector (bar): “> COULD, i m not too big on wallpaper changing and other cosmetic trivialities”
- M:139 · #59 BongoCat (decorative): “> WONT, we're building a serious shell”
- M:79 · #29 System tray: “> SHOULD, very nice to have but i won't be using it personally”
- M:101 · #40 CPU/Memory/System monitor: “> SHOULD, good to have but i don't intend to use it myself”

**Notifications**

- M:156 · #65 Notification daemon (NotificationServer): “> MUST this one is non-negociable”
- M:158 · #66 Configurable popup position (6+ options): “> MUST”
- M:160 · #67 Notification center / history panel: “> MUST, although the specific aesthetic of it is not clear in my mind. ”
- M:162 · #68 App-name grouping: “> MUST, seems trivial to implement like how DMS did it”
- M:168 · #71 Do Not Disturb toggle: “> SHOULD, likely something i toggle with a keybind or a button on bar”
- M:170 · #72 Notification rules engine (pattern match): “> MUST, nice to have from DMS”
- M:180 · #77 Keyboard navigation in notif center: “> MUST, dms hints overlay philosophy is very desirable”
- M:190 · #82 Flood protection / rate limiting: “> MUST, to avoid dangerous or strange behavior on my system”

**Launcher and clipboard**

- M:238 · section note: “>>>    GENERAL NOTE on 1.4 LAUNCHER: my shell's launcher in its ideal form will be visual equivalent to macos' RAYCAST. i found it to be the most powerful feature by far. there was a qt launcher called vicinae that tried to reproduce raycast; i could revisit it. but dankmaterialshell's launcher does a great job at getting close to it. we start with the dms implementation as reference and then decide if we want to go beyond”
- M:197 · #83 App search (fuzzy): “> MUST”
- M:201 · #85 File search: “> MUST, and fd plugin seems sufficiend, dms' dsearch was overkill and having a separate package for that is not desirable”
- M:203 · #86 Clipboard mode in launcher: “> MUST, it's important for me to have the clipboard history shown in the same aesthetic as the launcher; also making sure that we are displaying images (i use cliphist, prefer not to create special rust functionality as i found DMS reinventing the wheel with their clipboard implementation)”
- M:205 · #87 Emoji picker: “> SHOULD, emoji is somehting i have had for years, previously in a handrolled fzf menu, but now we have so many of those emoji pickers it should be trivial to create our own or rip the most performant one”
- M:207 · #88 Plugin/provider system: “> MUST, dms provider concept is powerful”
- M:211 · #90 Favourites/pinned apps: “> MUST, and caelestia's sqlite frequency is very cool”
- M:223 · #96 Action panel (Ctrl+Tab): “> SHOULD, this is a nice addition that makes our launcher raycast-like”
- M:229 · #99 Shell command execution: “> SHOULD, makes us raycast-like”
- M:233 · #101 RTL/i18n support: “> DONT i explicitly reject i18n support for now. this is MY shell i'm not trying to reinvent the linux shell for the entire world”
- M:215 · #92 App overrides (name/icon/env/flags): “> COULD, but i like to control my .desktop apps from my local share applications in dotfiles so this is a little redundant”
- M:227 · #98 Web search: “> COULD, explore implementation later if at all (seems redundant with opening a new google chrome tab and doing my search directly from there, little added value in search results in launcher)”
- M:526 · #233 Clipboard manager: “> MUST the clipboard manager is very important to me. note however that i use cliphist currently. i discuss the specifics of my implementation separately”
- M:634 · section note: “> COULD. discussed externally. to be revisited later. could convince me to move away from cliphist”

**Audio, media and OSD**

- M:255 · #109 Volume overdrive (>100%): “> DONT explicitly i like to have volume going from 0 to 100; only situation where that's not the case is in vlc media player”
- M:263 · #113 Audio spectrum visualizer (Cava): “> DONT i don't care about that”
- M:269 · #116 MPRIS seek/position: “> MUST, love the progress bar”
- M:281 · #122 Volume OSD: “> MUST. an OSD is very imprtant to have. I found the eqsh one to be very nice (which i m using right now)”
- M:283 · #123 Brightness OSD: “> MUST but with a small caveat: i really don't care if the brightness is managed by my shell. as you can see now from my scripts, eqsh is sufficient, and i would be happy to have that being a toggle i control from niri keybinds. doesn't really have to be fully integrated with the shell if it adds work”

**Network and Bluetooth**

- M:330 · #144 VPN multi-provider (WireGuard/Warp/Tailscale): “> MUST with special focus on tailscale”
- M:334 · #146 Airplane mode (WiFi+BT): “> MUST”
- M:336 · #147 NM SecretAgent (credential agent): “> MUST”

**Theme and look**

- M:62 · #23 Configurable animation duration: “> COULD, i really do not care about animations whatsoever”
- M:414 · #181 Material You / matugen colors: “> WONT whatsoever: no material or material you (i don't like it); no matugen whatsoever as I explained we do not have a strict colorscheme we follow a standard minimal css token”
- M:416 · #182 Predefined color schemes: “> WONT in the sense that we have only one predefined colorscheme”
- M:418 · #183 Dark/light toggle: “> COULD far down the line support a single universal dark/light toggle. icebox for now”
- M:420 · #184 Auto dark/light (time/location): “> WONT: even if i do eventually add a light mode this should only be toggled manually”
- M:422 · #185 OLED mode: “> MUST. OLED mode ie make the black colors #000000 is something that i do by default. so you could say i do oled compatible color mgmt by default. however if by oled you mean something like "a special setting that reduces oled monitor burn-in somehow" then WONT. i can manage my oled screens myself”
- M:426 · #187 Configurable fonts: “> SHOULD but the default font, like eqsh, is sanfrancisco mono.”
- M:428 · #188 Animation speed control: “> WONT. not sure if the shell has anything to do with animation speeds at all, and even if it does i would make it none/short for snappiest experience”
- M:430 · #189 Transparency/opacity config: “> SHOULD. Compositor (niri) owns blur via ext-background-effect-v1; CSS just sets background-color alpha. This reduces to configurable alpha on material levels — a CSS custom property. Trivial once design tokens exist.”
- M:434 · #191 Wallpaper picker: “> SHOULD because we are indeed controlling the monitor from quickshell side of things (not niri config)”
- M:440 · #194 Parallax wallpaper effect: “> WONT i explicltly don't need parallax because it makes me dizzy”

**Session, security and the control centre**

- M:463 · #203 Lockscreen (WlSessionLock): “> COULD this functionality is quite secondary. i bypass lockscreen by default on reboot (already implemented in my os with greetd automation); and when i need to rest my desktop i do `systemctl sleep`. might revisit this later because the functionality is already documented and we have good references for it. but icebox for now ”
- M:489 · #216 Polkit agent: “> MUST. i do not like the classic gtk greeter (that gets used now in the current state of my dotfiles). we are writting a very nice, very well-done uniform design system. dms and others have proven to me that polkit is implemented and easy to do with regular quickshell. this is low-hanging fruit”
- M:493 · #218 Power menu (shutdown/reboot/suspend): “> MUST and in fact i want to mention that i like the new DMS powermenu the most with the ability to scroll/select through a list AND press and hold a given key to get the desired action”
- M:501 · #222 Session action confirmation dialog: “> COULD if i find this to be useful later down the line. for now icebox ”
- M:508 · section note: “> COULD the entire idle management suite is not so important for me, i prefer to icebox for now. this applies to 225-232 inclusive”
- M:597 · section note: “>> WONT. i do not need a control center. this is not in scope for my project. this applies to 268-280”

**Utilities**

- M:528 · #234 Screenshots (region/full/window): “> WONT because existing niri window manager is sufficient”
- M:530 · #235 Screen recording: “> COULD look into what this entails but my first instinct is that i already use OBS Studio (as flatpak) to record screen, making this implmementation quite redundant”
- M:534 · #237 Color picker: “> MUST but Color picker currently since i use niri window manager the screenshot tool exists and is sufficient”
- M:536 · #238 OCR (tesseract): “> SHOULD but with a twist. first off i want to use the existing niri functionality to clip screen (unless there are complications with that, in which case swappy/grim/regular wayland tool is fine). the second twist is that i do NOT want the ocr to be handled by tesseract: it will be handled with qwen 3.5 opensource multimodal llm model which comes with phenomenal ocr from screenshots; and i confirmed it runs on my machine. Backend: HTTP call to llama.cpp server running in a local toolbox container.”
- M:540 · #240 Calendar month grid display: “> WONT. the calendar month grid display will be handled by a bespoke, fullscreen, on-brand calendar app FAR later down the line. i do not need such utility in my shell. they're hacky anyway, calendar grids ar not straightforward in qml.. but trivial with web technologies”
- M:542 · #241 Terminal session management (tmux/zellij): “> MUST but i use shpool for terminal sessions, not tmux nor zellij. that being said the dms implementation could be very helpful in my preparation of that fucntionality. requires further specialized scoping”
- M:546 · #243 Night light / gamma control: “> WONT, my gamma control and night light is set once and not from the shell. skip entirely”
- M:552 · #246 Desktop widgets (draggable): “> WONT. i do not like widgets”
- M:554 · #247 AI assistant integration: “> COULD but much later down the line. i do not need an ai integration the way it is done in the reference qml shells. i have some ideas here so not marking this as won't”
- M:558 · #249 Notes/notepad: “> WONT. i use github-backed md notes. see no value in having external notepad. drop that”
- M:560 · #250 Pomodoro/timer: “> SHOULD the pomodoro timer concept is very valuable and i have my own approach for it. so we use the existing references and build on top of it. this will be the first feature i release AFTER base webshell”
- M:562 · #251 Docker/Podman management: “> SHOULD Container management is very desirable on my system, i expand on thsi a little later  ”
- M:564 · #252 mKDE Connect integration: “> SHOULD; this doesn't have to be done right away but the KDE connect is extremely desirable. i believe that dankmaterialshell also has KDE connect. in the past i also considered Valent for the same. to be scoped out better but i wish to make it clear that "android phone notification" is extremely desirable”
- M:590 · #265 Onboarding/setup wizard: “> MUST but this one will require specific scoping work before i configure it”

**Plugins, hierarchy, language, single user**

- M:452 · #200 Plugin config support: “> COULD but we will do that much later down the line. by "plugin config support" what i understood is that we can control the plugins from within the settings page. in my case it s a custom shell written for one person, so the utilities/plugins i need are configured from the dotfiles themselves. no need to "enable" plugins or browse through them. to be precise, in my world, an ephemeral pomodoro widget has the same place as the main launcher (there is no hierarchy)”
- M:446 · #197 i18n / translations: “> WONT no i18n whatsoever, shell is always in english.”
- M:648 · section note: “> WONT, i use single-user on my desktop”
- M:659 · section note: “> to be reevaluated later”


**Voice caveat (INFERRED, unverified).** A few `>` lines read differently from Tom's usual voice.
They use capitalised sentences, technical confirmations and em-dashes:

- M:363 (#158) and M:365 (#159)
- M:377 and M:379 (#165, #166)
- M:387 (#170)
- M:430 (#189)

For example, #159 reads "Confirmed: Rust daemon uses niri-ipc crate with typed bindings…". They may
have been added or normalised by an agent after Tom's pass. Steelman 02 still calls #189 "Tom's own
`#189` mark" (S02:117). Treat the priority marker as Tom's and the technical clause as possibly an
agent's.

### 2.2 From the kmux + QuickShellX list (2026-03-26)

Each row is a proposal followed by Tom's `>` reply, copied as written.

| Item (K line) | Proposal (K) | Tom's reply, verbatim |
|---|---|---|
| A1 (:10) | Terminal emulator: Kitty (`--single-instance=no`, one window = one OS window, niri tiles) | > must (:11) |
| A2 (:12) | Compositor: Niri (infinite horizontal scroll, named persistent workspaces, `niri msg` IPC) | > must (:13) |
| A3 (:14) | Session persistence: shpool (raw byte passthrough preserves all kitty protocols) | > must (:15) |
| A4 (:16) | Shell UI host: QuickshellX (QML scripting, wlr-layer-shell, WebEngineView) | > must (:17) |
| A5 (:18) | Frontend framework: SolidJS (v1 stable or v2 beta — needs decision) | > must, we will use v1 (:19) |
| A6 (:20) | Component primitives: Kobalte (@kobalte/core, unstyled, WAI-ARIA) | > this is a new addition that will require further work when we go down the line (:21) |
| A7 (:22) | Build toolchain: bun + vite + vite-plugin-solid | > must (:23) |
| A8 (:24) | Browser automation: fgp-browser (pure Rust, CDP-direct, Unix socket) | > should, this is something that will be handled later entirely (:25) |
| A9 (:26) | Webview: QtWebEngine (CDP at localhost:9222, ~60 lines Python bridge) | > no this is wrong. discard this information (:27) |
| A10 (:28) | Editor: Neovim (octo.nvim, neogit, diffview.nvim) | > should, to be done later (:29) |
| A11 (:30) | Daemon language: Rust (single static binary) | > this is already adopted decision (:31) |
| A12 (:32) | Glue language: Python (~200 lines bridge scripts) | > no python, thinking all rust (:33) |
| A13 (:34) | Database: SQLite via rusqlite with FTS5 (daemon), bun:sqlite (frontend reads) | > should, to be done later (:35) |
| A14 (:36) | Typeface: SF Pro Display/Text primary, SF Mono code (manual install on Linux) | > MUST and this is not implemented now (:37) |
| A15 (:38) | Icons: Phosphor or Lucide, stroke-only, 1.5px weight, 16/18/24px | > should, start with lucide (:39) |
| B1 (:43) | One kitty window = one OS window. No splits, no tabs, no multiplexer inside kitty. | > yes (:44) |
| B2 (:45) | No TUI anywhere. Not Agent Deck. Not cmux. Not any TUI dashboard. | > technically, no TUI except for pi-mono or pi-agent. but yes no dashboard in terminal (:46) |
| B3 (:47) | Status from structured data (JSONL + hooks), not screen scraping. | > yes, in fact must be discussed in depth becaues the way it is now with claude code, in the existing implementation of my focused window indicator of the bar of quickshellx webshell is sufficient, seems like claude code does output the needed titles (:48) |
| B4 (:49) | Always-shpool model. Every shell session runs inside shpool (local and remote). | > yes! (:50) |
| B5 (:51) | Thin client/server split. Server = Strix Halo. Client = Dell XPS. SSH + Tailscale. | > should; but for now it s all in server mode (ie local is server) so no need for htis logic now.  (:52) |
| B6 (:53) | Composition over monolith. kitty remote control + niri msg + shpool > custom daemon. | > yes (:54) |
| B7 (:55) | The filesystem IS the API. JSONL + semaphore locks + inotify > RPC daemons. | > yes (:56) |
| B8 (:57) | All agents run in interactive mode. One mode. No headless RPC for agents. | > yes (:58) |
| B9 (:59) | No CSS blur anywhere ever. All blur is compositor-driven (niri blur 3 passes offset 3.7). | > yes, niri implementation of blur to be noted somewhree externally to its own md file because we re still waiting on upstream for that (anyday now) (:60) |
| B10 (:61) | Dark-first: surfaces are solid hex fills, compositor sets window opacity 0.85 for wallpaper bleed. | > yes (:62) |
| B11 (:63) | One accent color: `#5B9DFF`. No secondary/tertiary. Monochrome discipline. | > yes for now (:64) |
| B12 (:65) | One animation duration: 50ms for everything. No tiered system. `cubic-bezier(0.16, 1, 0.3, 1)`. | > yes for now (:66) |
| B13 (:67) | Animate ONLY opacity and transform. Never background, border, shadow, layout. | > yes for nw (:68) |
| B14 (:69) | No light theme. No theme toggle. Dark-only single-accent. | > yes for now (:70) |
| B15 (:71) | shpool is systemd user service (socket activation), not niri spawn-at-startup. | > yes and this is already impelmented on my system (:72) |
| C1 (:76) | Option: Claude Code first, Pi later | > yes (:77) |
| C2 (:78) | Option: Pi first, Claude Code for Agent Teams only | > no (:79) |
| C3 (:80) | Option: Both from day one with normalized event layer | > well technically both wil lbe installed on day one but we re startign w claude (:81) |
| C4 (:82) | Namespace: `os.claude` (CC-first), `os.agent` (agent-agnostic), or `os.claude` + `os.pi` (dual) | > os.claude as the prototype. os.agent is reserved to when we "graduate" from claude code and then we move on to os.agent for pi (:83) |
| C5 (:84) | CCD daemon speaks one protocol first, adapter pattern for the second agent later | > yes (:85) |
| C6 (:86) | Sidebar data sources differ: CC uses hooks→status files; Pi uses semaphore locks + JSONL tailing | > ok so we start w claude specific (:87) |
| C7 (:88) | Permission models differ: CC has HTTP hooks with exit codes; Pi has extension_ui_request/response via damage-control (210 LOC TypeScript) | > start w claude (:89) |
| C8 (:90) | Pi has steer/fork/compact that CC lacks; CC has Agent Teams that Pi lacks | > start w claude.  (:91) |
| J2 (:199) | J2. shpool fork (+500 lines, parked for v0.2+) | > ABANDONED COMPLETELY (:200) |
| L4 (:268) | L4. Status dot colors (locked) | > acceptable for now, to be unified later of course (:269) |

### 2.3 From the CUBS steelman chat (2026-06-29), Tom's prompts as recorded

CL:4 says the prompts are verbatim. The `…` elisions belong to the log writer, not to Tom.

**CL:12-15 (T1)**

> yesterday we had a major breakthrough on the CADE side of things. we got it to boot on a linux
> box. this is not nothing, but it now shows that there's a fork in the road and that multiple
> options are actually viable. first off read through everything you can and inform yourself about
> the news

**CL:28-33 (T2)**

> so you seem to have understood what happened. find attached a thread i had with claude.ai that
> will give you some ideas about where i stand right now: [pasted a long claude.ai chat — see
> below] … basically i got to see firsthand how many problems and issues will come along if i
> choose to adopt CADE wholesale. sure, it's cool to have the native ash desktop environment fully
> functional but… this is stubbing the things that we faked back. something as trivial as mouse
> scrolling is not functional. starting nautilus from terminal crashed the entire session.

**CL:90-98 (T3)**

> right, so the CADE experiment was not wasted. i knocked something… now finally see the pixels on
> my laptop. and i know that the day the COWL approach becomes no-go for whatever reason, i can just
> go nuclear and start with cade (which at the very least gets me a chromiumOS booted now). read up
> on what already has been done on the cowl side. i had a functional top bar, and a functional left
> side bar (that manages workspaces). but this one was written using web technologies. can you
> identify those? and if you can, per that pasted claude.ai chat i gave you, we have decided to move
> away from this model, and to adopt (the ironically closer to chromium) model where one mojo gets
> three seems: including c++ views shell, and potentially the chrome:// or os:// or whatever format
> we decide to have that in.

**CL:106-107 (T4)**

> no sorry, i don't think you identified the right thing for the cowl. the files we're looking
> at/for are less than 72 hours old.

**CL:121-123 (T4, injected mid-turn)**

> if helpful, there was an attempt to pass some niri-side blur on them which worked. and the surfaces
> were transparent. yes the left sidebar is indeed for workspaces. there was a script to bring the
> two up on DP4

**CL:131-138 (T5)**

> so we have conceptually two ways to go with cowl (let's call this CADE instead): pure web app
> style, like the current cowl-secondpass you found; a more views-native (c++) approach to the shell
> building, making this project much closer conceptually to what noctalia-shell did; we actually
> experimented with that yesterday as well in ~/mecattaf/views-shell. this is a real split in the
> road, nested within the "cade vs cowl" deliberation (be the aura compositor as well or keep relying
> on niri or other wayland compositor). and finally you can git clone … ghostex and … cmux to
> ~/Downloads and read through it with 4 agents … they use swift ui; but in my world i have a feeling
> that we can "make views c++ into the swift that macos gives"

**CL:162-169 (T9)**

> Let's add one round of deliberation where you discuss how you will approach if this were a project
> that we were starting from scratch… from a first principle approach, part of me thinks and feels
> like the conclusion we're reaching now with the views part is logical. … there was a point at which
> i had arrived at a design decision … a material glass sort of thing, but that was coming from the
> world where every single item on the layer shell was a web app, whereas now we have the Views c++
> concept… stepping away from "we're rebuilding cmux but in niri" and acknowledging that what i'm
> trying to get to here is a more complete desktop environment shell that is at minimum on par with
> noctalia v5…

**CL:184-187 (T10)**

> point taken re: aesthetic. check if ~/mecattaf/views-shell contains some usable start to do a spike
> for "arbitrary wayland layer-shell-compatible shell in views c++"; that "half of noctalia that we
> take for granted". the goal is, on niri now, understand if the "chromium tier 2 level" app that
> would be a cousin to chrome and microsoft edge is a viable approach

**CL:203-211 (T11)**

> should we lift the views part of chrome as a separate binary or just make the whole thing a browser
> that could be the regular chrome browser as its base … niri still handles inputs, seats, greetd and
> shortcuts (well, unless we decide to go nuclear and go pure-aura as was proven on the drm path). the
> three-layer mojo ipc instinct remains anyway. … it enables me to build arbitrary "concepts" that
> get captured. say, like ghostex or cmux, how we map a niri workspace to a grouping of windows placed
> in a certain way (and accessory we capture the topic of the claude ai chat that started that
> workspace). you will find in ~/mecattaf several alleys where i'm trying to integrate a deeper
> concept: kerdr for recoverable sessions (this is nested in the new tally concept as well, that drain
> for local ai). or any cli that exposes the right signals that we design our shell around.

**CL:225-231 (T12)**

> this is CUBS: chromium unified browser and shell (notice how, unlike cade — chromium aura desktop
> environment — it doesn't have the pretense of being a DE, it works with your DE like noctalia v5).
> what remains is the mojo surface, "three layer" model. for wifi, network this gives me top bar in
> views, control center in views, chrome:// (or whatever) network-manager and we comprehensively copy
> the chromium chromeos ash stuff here as CADE found that they worked great. the build protocol must
> be like how brave or vivaldi or flow browser [Flow screenshot: vertical-tab sidebar, spaces, a
> cmdk-style command palette]

**CL:244-246 (T13)**

> write a new subdirectory in ~/mecattaf/notes about cubs-steelman that you work on now. i want 4
> markdown files that explain comprehensively the key parts of this discussion. also save the whole
> chat log in a single markdown file as well in that dir since it's so convergent and high quality

**Tom's lines inside the pasted claude.ai chat (CL:40-76; agent text around them omitted)**

- CL:44: “now perhaps there is a neat solution… chromium fork + views but with special consideration for layer-shell… then electron-like-flow vs views-like-edge becomes a matter of performance (snappiness, cost).”
- CL:53: “chrome tabs c++ interface but for the wayland desktop”
- CL:56 (network): “wifi settings… accessible in a views toggle on the top bar… AND a control center overlay… AND a chrome://network-manager page. all in one seam.”
- CL:60: “something about the uniformity of a mono interface is very appealing… we keep the bar in views and pay the price of being backed by chromium.”
- CL:66: “i want my tier-2 chromium program — chrome-cowl — to have the same uniform themability as the tabstrip… written from the get-go.”
- CL:74 (the close): “ironic that google chromiumOS has booted on my linux desktop. so path A that i had almost given up on has just proven to work.”

### 2.4 Tom's own notes in `CUBS/` (MEASURED)

- `CUBS/intro.md:1`: "on june 16 i made the decision to \"revive\" cowl rather than build cade."
- `CUBS/intro.md:2`: "two days later, i made a quick compilation of the different prjects that \"patch
  chromium\" as a core primitive." The list that follows: helium, zen browser ("a goat reference in this
  space"), CloakBrowser ("very strong \"privacy\" style benefits; very desirable"), Orion, vessel-browser.
- `CUBS/extra-functionality.md:1`: "we will indeed be bringing over all the functionality we can from
  previous cade investigation (including the full annotation chapter)"
- `CUBS/extra-functionality.md:5-6`: "inspiration for connecting to android phone:
  https://github.com/demencia89/noctalia-shell-androidconnect-plugin"
- `CUBS/extra-functionality.md:8-10`: "inspiration for an events/reminders/calendar cli:" (DankCalendar
  links)
- `CUBS/extra-functionality.md:12-13`: "could also have something for emails / sasori-style smtp is
  interesting."
- `CUBS/extra-functionality.md:15`: "the pattern here is that we can have our own, somewhat native,
  format for scheduling tasks and supervising them."

### 2.5 Steers that agents relayed as Tom's (REPORTED)

- "Pull M5 (session/auth) forward as the target (Tom's steer)". Both tracks had deferred session/auth
  to M5; "Tom wants M5 as the build target now" (`CUBS/HANDOFF-views-shell-to-cade-drafts.md:53-56`).
  This conflicts with Tom's own March "lockscreen … icebox for now" (M:463). It was steered for the
  CADE route, which is parked. INFERRED: tonight it does not bind, beyond keeping PAM out of everything
  except the polkit agent.
- "Tom: anti-matugen is a *load-bearing identity decision*" (S02:104). This agrees with M:414.
- "Tom's identity … **one** minimal token set, anti-Material-You, **OLED `#000000` surfaces by default**,
  SF Mono, near-zero animation, snappy" (S02:127-130). Agent paraphrase. The font is superseded (§2.6).

### 2.6 Which older rulings later Tom rulings overrode (MEASURED both sides)

| Topic | Older ruling (date, pointer) | Binding ruling now (BRIEF) | Effect on gpuix-shell |
|---|---|---|---|
| Compositor | "WONT. We are building this shell for niri ONLY." (03-24, M:363); K A2 niri "must" | "Sway is the only compositor … Hyprland … dropped" (BRIEF:34-35) | The rule (single compositor, no facade) holds; the compositor changed. #162 "Sway/I3 native module WONT" flips to the only module. |
| Blur / glass | B9 "No CSS blur… All blur is compositor-driven (niri blur 3 passes offset 3.7)" → "yes" (K:59-60); #189 "Compositor (niri) owns blur" (M:430); B10 "window opacity 0.85" → "yes" (K:61-62) | "flat and opaque, hairlines not shadows, no blur, no frost, wallpaper is #000000 solid" (BRIEF:43-44) | Every translucency/blur row → DROP. The steelman's "material-glass survives" (S02 §4) is void. |
| Light/dark | "my shell has NO light/dark mode: it's all Dark Glass aesthetic" (M:125); B14 "No light theme. No theme toggle." → "yes for now" (K:69-70); but #183 "COULD far down the line support a single universal dark/light toggle" (M:418) and #184 "should only be toggled manually" (M:420) | noir default + claude-dark + claude-light, switched at runtime by `~/.local/bin/theme` (BRIEF:45-47) | #183 is realised by hand-switching, consistent with #184. The shell follows `~/.config/theme`. |
| Fonts | #187 "the default font, like eqsh, is sanfrancisco mono" (M:426); A14 "SF Pro Display/Text primary, SF Mono code" → "MUST" (K:36-37) | Anthropic Sans (UI), Anthropic Serif (documents), AnthropicMono Nerd Font (BRIEF:44) | Font family stays configurable (#187 SHOULD); the default changes. |
| Accent | B11 "One accent color: `#5B9DFF`" → "yes for now" (K:63-64) | Claude/Primer look; noir palette (BRIEF:41-47) | Accent comes from the theme fragment. |
| Colour schemes | #182 "WONT in the sense that we have only one predefined colorscheme" (M:416) | three themes from `home/themes/*.nix` | Still one token **set**, now with three palettes; no scheme gallery. |
| Terminal sessions | #241 "i use shpool for terminal sessions" (M:542); B4 "Always-shpool model" → "yes!" (K:49-50) | herdr is "the centerpiece of dotfiles" (BRIEF:39-40) | herdr replaces shpool/kerdr; see §3.8. |
| Agent sidebar | ccd: "PanelWindow: 400px right, full height, WlrLayershell Overlay" (K:245) | left rail, 56 collapsed / 220 expanded, waybar-style 1→9 (BRIEF:48-49, :106-108) | The sidebar moves to the left and merges with the workspace switcher Tom wanted on the left (M:75). |
| Glue language | A12 "Glue language: Python" → "no python, thinking all rust" (K:33-34) | TypeScript + React 19 via GPUIX (BRIEF §3.1) | "No Python glue" still holds in spirit: scripts stay shell, the shell is TypeScript. INFERRED. |
| Distro / packaging | #47 "fedora atomic system" (M:115); Q9 "We use Fedora COPR / RPM" (K:457) | NixOS flake, `pkgs/gpuix-shell/default.nix` (BRIEF §3.9) | Update-count (#47/#248) needs a NixOS meaning; unscoped. |
| Substrate | CUBS: Views C++ in a tier-2 Chromium fork (S06 §A#1) | GPUIX (`@gpuix/react` + `@gpuix/native`) (BRIEF §3.1) | Only the functionality/design layer of CUBS transfers. |

---

## 3. Feature inventory

### 3.0 Legend

**Dispositions**

| Code | Meaning |
|---|---|
| **NEW** | Absent from dotfiles today; gpuix-shell builds it (tonight, or as foundation) |
| **REPLACE** | Exists today in vicinae, mako, waybar (deleted) or an fzf prompt; gpuix-shell takes it over |
| **KEEP** | An existing script or Sway bind stays authoritative; the shell may display it or call it |
| **LATER** | SHOULD/COULD-later; leave a seam, do not build tonight |
| **ICEBOX** | Tom's own word "icebox" |
| **DROP** | Tom's WONT/DONT, or a later Tom ruling removed it |
| **CONFLICT** | An older ruling contradicts BRIEF; see §6 |

**Surface names** (BRIEF §3.2)

| Name | What it is |
|---|---|
| `rail` | left layer-shell bar |
| `notif` | fd.o notification server + toasts |
| `osd` | the OSD window, in the notifications process |
| `launcher` | Mod+d overlay (vicinae replacement) |
| `switcher` | Mod+i |
| `controls` | quick settings |
| `files` | Pinax-like file explorer |
| `power` | power menu |
| `ask` | OpenUI prompt |
| `cli` | `gpuix-shell <verb>` over `$XDG_RUNTIME_DIR/gpuix-shell/shell.sock` |
| `theme` | the `gpuix-shell.json` theme fragment |
| `sway` | `home/dot_config/sway/*` |
| `script` | `home/dot_local/bin/*` |

**Priority (P) column:** Tom's marker, normalised to upper case. The annotation column keeps his exact
text.

### 3.1 The 280-row annotated matrix (M), with a disposition and surface for every row

Totals (computed from the table). Tom's markers per row: COULD 89, DONT 5, MUST 77, SECTION 21, SHOULD 55, WONT 33. Rows 225–232 take the section ruling COULD/icebox; rows 268–280 take the section ruling WONT.  
These MUST counts include qualified ones such as #237 "MUST but…". An April agent count says "63 MUST identified" (`april-webshell-refs/REVOLUTION/COMPREHENSIVE-ANALYSIS.md:487`), so its counting rule differed; I did not reconcile the two.  
Dispositions: CONFLICT 15, DROP 48, ICEBOX 28, KEEP 16, LATER 76, NEW 83, REPLACE 14.

#### 1.1 BAR / STATUS BAR (M:13)

| # | Feature | Best impl (count) | P | Tom's annotation, verbatim (`> ` stripped) | Disp. | gpuix-shell surface / notes |
|---|---|---|---|---|---|---|
| 1 | Three-zone layout (L/C/R) | DMS, noctalia (12) | MUST | MUST, this is basic bar config (M:18) | **NEW** | rail — vertical, so L/C/R becomes top/middle/bottom: slots 1–9 top, status cluster bottom (INFERRED) |
| 2 | Configurable widget arrays per zone | DMS (JSON), noctalia (settings UI) (5) | MUST | MUST (M:20) | **NEW** | rail — zone arrays in the nix-rendered shell config; no GUI editing |
| 3 | Widget drag-reorder in settings | noctalia (1) | COULD | COULD, happy to keep it "deterministic" from config (M:22) | **DROP** | rail — order fixed from config, exactly as the annotation asks ("deterministic") |
| 4 | Plugin widget system | noctalia (BarWidgetRegistry + incubation) (2) | MUST | MUST, it is important to be able to "turn any functionality" into a bar addition (M:24) | **NEW** | rail + launcher share one module registry: any script/CLI becomes a rail item or launcher command (MA A1) |
| 5 | Multi-monitor via Variants | Universal pattern (16) | MUST | MUST (M:26) | **NEW** | rail — one instance per Sway output that should carry it; which Duo outputs is open (§6 G4) |
| 6 | Per-screen widget configuration | DMS (screenPreferences) (3) | MUST | MUST (M:28) | **NEW** | rail — per-output override keyed by Sway output name (eDP-1 / eDP-2) |
| 7 | 4-way position (T/B/L/R) | DMS, noctalia (7) | MUST | MUST (M:30) | **NEW** | rail — anchor is a config key; default left (BRIEF §3.3) |
| 8 | Vertical bar layout | caelestia (purpose-built) (5) | MUST | MUST, in fact i have a very specific use case in mind for that. (M:32) | **NEW** | rail itself. The "very specific use case" is now the herdr 1–9 slot launcher (INFERRED from M:75 + BRIEF:48-49) |
| 9 | Auto-hide with hover reveal | DMS (most options), noctalia (show/hide delays) (7) | MUST | MUST, could be useful but more important for me is that i want to toggle bars with a niri keybind (sigint) (M:34) | **NEW** | cli `gpuix-shell rail toggle` bound in sway binds (keybind-first); hover-reveal LATER |
| 10 | Fullscreen detection auto-hide | Ambxst (3) | MUST | MUST (M:36) | **NEW** | rail — hide on the output whose focused container is fullscreen (Sway `window` event, `fullscreen_mode`) |
| 11 | Click-through mode (region mask) | DMS (1) | COULD | COULD (M:38) | **LATER** | rail — needs an input region on the layer surface; check the GPUIX API |
| 12 | Multiple simultaneous bars | DMS (1) | MUST | MUST, i will in fact have multiple simultaneous bars in my config, and want to be able to toggle one but not the other (M:40) | **NEW** | cli — every bar has an id; `rail toggle [--output X]` touches only that bar |
| 13 | Integrated dock in bar | Ambxst (2) | COULD | COULD (M:42) | **LATER** | — |
| 14 | Bar style variants (floating/full/modules/islands) | sshell (3) | COULD | COULD (M:44) | **LATER** | rail — one style tonight |
| 15 | Goth/outer corners | DMS (4) | COULD | COULD, but this is less difficult because i use web components (M:46) | **LATER** | —; the flat look ruling makes corner tricks low value |
| 16 | Per-screen density setting | noctalia (compact/normal/comfortable) (2) | COULD | COULD, since we have per-screen settings anyway (M:48) | **LATER** | rail collapsed 56 / expanded 220 already gives two densities |
| 17 | Scroll to switch workspace | DMS (configurable X/Y axis, touchpad vs mouse thresholds) (5) | COULD | COULD, quite secondary for me (M:50) | **KEEP** | sway `binds.conf:85-86` already switches workspaces on Mod+wheel; rail may forward wheel events |
| 18 | Scroll to adjust volume on bar | caelestia (zone-based) (2) | COULD | COULD, secondary (M:52) | **LATER** | rail volume glyph wheel → `volume up/down` |
| 19 | Scroll to adjust brightness on bar | caelestia (bottom half) (1) | COULD | COULD, secondary (M:54) | **LATER** | `brightness` script stays the owner |
| 20 | IPC bar toggle | DMS (4) | MUST | MUST, and very important to have funcioning well with niri; in fact one ipc toggle should control only one bar (in case there are multiple bars) (M:56) | **NEW** | cli over `$XDG_RUNTIME_DIR/gpuix-shell/shell.sock`; one verb per bar id |
| 21 | Shadow/elevation system | DMS (3) | COULD | COULD, quite secondary. conceptually an elevation system is interesting but this should be minimal layershell logic, nothing more (M:58) | **DROP** | superseded by BRIEF "hairlines not shadows" |
| 22 | DPI-aware snapping | DMS (Theme.snap/Theme.px) (1) | SHOULD | SHOULD because dpi-aware anything is important (M:60) | **NEW** | all surfaces honour output scale; verify GPUIX fractional-scale handling on the Duo panels |
| 23 | Configurable animation duration | DMS (None/Short/Medium/Long/Custom) (3) | COULD | COULD, i really do not care about animations whatsoever (M:62) | **DROP** | no animation-duration knob |
| 24 | Content window separation from background | noctalia (BarContentWindow) (1) | COULD | COULD (M:64) | **LATER** | — |
| 25 | Screen frame integration | Ambxst (ScreenFrame) (1) | COULD | COULD (M:66) | **LATER** | — |
| 26 | Hot corners on bar edges | noctalia (1) | SHOULD | SHOULD, niri itself also has hot corner but this one clearly has more potential (M:68) | **LATER** | Sway has no hot corners; would need 1 px overlay surfaces per corner (MA B1) |

#### 1.2 BAR WIDGETS (modules) (M:70)

| # | Feature | Best impl (count) | P | Tom's annotation, verbatim (`> ` stripped) | Disp. | gpuix-shell surface / notes |
|---|---|---|---|---|---|---|
| 27 | Workspaces indicator | noctalia (compositor-agnostic), DMS (6 compositors) (16) | MUST | MUST, in fact in my concepts i had the workspace switcher as a separate left horizontal bar, whereas all the other modules exist in the top bar. (M:75) | **NEW** | rail slots 1–9 + herdr status, and switcher (Mod+i, PR #565); REPLACES the waybar workspaces module deleted 2026-09-11 (BRIEF:78) |
| 28 | Clock | caelestia (clean popout), tpaau (orientation-aware) (16) | MUST | MUST, but no need to do anything fancier than configurable time and date. the minimal eqsh one was sufficient.  (M:77) | **NEW** | rail bottom clock; time + date, format from config only |
| 29 | System tray | DMS (TrayMenuManager), caelestia (compact/expandable) (15) | SHOULD | SHOULD, very nice to have but i won't be using it personally (M:79) | **LATER** | rail SNI host (`org.kde.StatusNotifierWatcher` + dbusmenu); Tom will not use it |
| 30 | Battery indicator | tpaau (UPower, color change), caelestia (charging anim) (14) | MUST | MUST (M:81) | **NEW** | rail battery glyph; UPower over dbus-next |
| 31 | Network/WiFi indicator | caelestia (ethernet fallback), HyprQuick (connection popup) (12) | MUST | MUST (M:83) | **NEW** | rail network glyph → wifi menu (controls / launcher) |
| 32 | Bluetooth indicator | caelestia (pulse animation), tpaau (popup menu) (11) | MUST | MUST (M:85) | **NEW** | rail bluetooth glyph → bluetooth menu |
| 33 | Volume/Audio indicator | caelestia (scroll-to-adjust), whisker (visual indicator) (12) | MUST | MUST (M:87) | **NEW** | rail volume glyph; state from `wpctl` |
| 34 | Media/MPRIS widget | DMS (dynamic show/hide), Kriti (dedicated widget) (11) | MUST | MUST (M:89) | **NEW** | rail now-playing glyph + media popover; `media` script keeps the keys |
| 35 | Notification indicator | tpaau (dynamic show/hide, DND), whisker (unread count) (10) | MUST | MUST (M:91) | **NEW** | rail bell: unread count + DND state from notif |
| 36 | Active/Focused window | caelestia (popout details) (9) | MUST | MUST (M:93) | **NEW** | rail expanded/tooltip: focused window title from Sway IPC; herdr workspace name is the slot label (INFERRED) |
| 37 | Power/Session menu | equora (macOS Apple menu), Ambxst (session popup) (10) | MUST | MUST, in fact i really like the DMS one which made you "hold a key for x seconds with a visual progress bar"; in addition to being able to scroll through them.  (M:95) | **NEW** | power — scrollable list + press-and-hold with a visible progress fill |
| 38 | Launcher button | DMS (8) | SHOULD | SHOUlD, trivial to add but i won't use it personally (M:97) | **LATER** | rail button → `gpuix-shell launcher toggle` |
| 39 | Privacy indicators (mic/cam/screen) | DMS (PrivacyService) (5) | MUST | MUST, and i'll likely develop a specific widget around it (M:99) | **NEW** | rail privacy dots from PipeWire nodes (`pw-dump`); Tom expects a dedicated widget |
| 40 | CPU/Memory/System monitor | DMS (5) | SHOULD | SHOULD, good to have but i don't intend to use it myself (M:101) | **LATER** | — |
| 41 | VPN indicator | DMS (4) | MUST | MUST. it is CRUCIAL for me to know if i'm connected to tailscale, and possibly to know what other devices are connected on my tailscale network. i am aware that there are 2+ different tailscale DMS extensions, happy to bring them over in due time (M:103) | **NEW** | rail Tailscale glyph + peer popover; backend `vpn-status` already emits JSON "for bar widget consumption" (MEASURED) |
| 42 | Keyboard layout | caelestia (popout selector) (4) | COULD | COULD, nice to have but i won't be using it (M:105) | **LATER** | — |
| 43 | Weather widget | sshell (WeatherPopup) (3) | COULD | COULD, nice to have but i won't be using it (M:107) | **LATER** | — |
| 44 | Clipboard button | DMS (3) | COULD | COULD, nice to have but i won't use it (M:109) | **LATER** | —; clipboard lives in the launcher (#86) |
| 45 | Idle inhibitor toggle | DMS (OSD indicator), noctalia (KeepAwake) (2) | COULD | COULD (M:111) | **LATER** | —; idle suite iceboxed (§1.10) |
| 46 | Color picker button | DMS (native Go) (2) | COULD | COULD, i intend to use colorpicker but with a niri shortcut (M:113) | **KEEP** | `colorpicker` script on Mod+c (`binds.conf:34`) |
| 47 | System updates count | DMS (multi-distro) (2) | SHOULD | SHOULD, this would be interesting and i would have to build functionality specifically for my fedora atomic system. still, a nice touch (M:115) | **LATER** | the Fedora Atomic premise is gone; a NixOS meaning is unscoped (§6 G15) |
| 48 | Audio visualizer | noctalia (C++ FFT plugin) (2) | SHOULD | SHOULD, i loved dms' popup for music and its associated "scroll through to skip parts of the song".  (M:117) | **NEW** | media popover: scrubbable progress, scroll to seek (Navidrome demo, BRIEF §5) |
| 49 | Caps/Lock key indicator | DMS (2) | SHOULD | SHOULD, trivial but i won t use it (M:119) | **LATER** | —; Caps now toggles the touchpad with an OSD (commit 7e082fbb) |
| 50 | Global menu bar (macOS-style) | equora (2) | COULD | COULD, i did have it but i'm not really using it (M:121) | **LATER** | — |
| 51 | AI button | equora (2) | COULD | COULD, same as 50 equora has it but i never use it (M:123) | **LATER** | —; `ask` is reached by keybind, not a button |
| 52 | Dark mode toggle | noctalia (1) | COULD | COULD but as you know my shell has NO light/dark mode: it's all Dark Glass aesthetic (M:125) | **DROP** | superseded: themes switch with `theme` on F2; no rail toggle needed |
| 53 | Night light toggle | noctalia (1) | COULD | COULD, i won't use it myself, but do it keeping in mind that this will require special functionality as i use a specific gamma tool wl-gammarelay-rs which is the only one that does per-monitor to my knowledge (M:127) | **LATER** | —; the shell never owns gamma (#243 WONT) |
| 54 | Power profile selector | noctalia (1) | COULD | COULD, very secondary (M:129) | **LATER** | controls (per-domain popover) |
| 55 | Brightness widget | noctalia (1) | COULD | COULD (M:131) | **LATER** | osd shows brightness; widget not needed |
| 56 | Microphone widget | noctalia (1) | COULD | COULD (M:133) | **LATER** | controls / audio picker (mic mute) |
| 57 | Wallpaper selector (bar) | noctalia (1) | COULD | COULD, i m not too big on wallpaper changing and other cosmetic trivialities (M:135) | **DROP** | wallpaper is solid #000000 (BRIEF:44) |
| 58 | Custom IPC button | noctalia (CustomButton) (1) | SHOULD | SHOULD (M:137) | **NEW** | rail custom button: left/right/middle/scroll each bound to a command (MA A12) |
| 59 | BongoCat (decorative) | nucleus (1) | WONT | WONT, we're building a serious shell (M:139) | **DROP** | — |
| 60 | Recording indicator | equora (privacy dots) (2) | MUST | MUST, i will use that (M:141) | **NEW** | rail recording dot: `recording-toggle`, `call-record`, PipeWire screencast nodes |
| 61 | Network speed monitor | DMS (reads /proc/net/dev) (2) | SHOULD | SHOULD, nice to have, possibly cool to have it toggled when we press the wifi/network button or as standalone (M:143) | **LATER** | wifi menu detail |
| 62 | Apps dock in bar | Ambxst (IntegratedDock) (2) | COULD | COULD, wouldn't use it directly (M:145) | **LATER** | — |
| 63 | Notepad button | DMS (1) | COULD | COULD (M:147) | **DROP** | notes app is WONT (#249) |
| 64 | Pin button (auto-hide toggle) | Ambxst (1) | COULD | COULD, i prefer toggling things with keybinds  (M:149) | **LATER** | —; keybind toggles preferred |

#### 1.3 NOTIFICATIONS (M:151)

| # | Feature | Best impl (count) | P | Tom's annotation, verbatim (`> ` stripped) | Disp. | gpuix-shell surface / notes |
|---|---|---|---|---|---|---|
| 65 | Notification daemon (NotificationServer) | DMS (most complete) (12) | MUST | MUST this one is non-negociable (M:156) | **REPLACE** | notif owns `org.freedesktop.Notifications`, replacing mako (`home/vicinae.nix` services.mako); never both |
| 66 | Configurable popup position (6+ options) | DMS (6 positions + focused-monitor-only) (3) | MUST | MUST (M:158) | **NEW** | notif toasts top-right by default (BRIEF §3.3), position configurable |
| 67 | Notification center / history panel | DMS (Current/History tabs, keyboard nav) (12) | MUST | MUST, although the specific aesthetic of it is not clear in my mind.  (M:160) | **NEW** | notif history panel, opened from the rail bell or `gpuix-shell notifications toggle` |
| 68 | App-name grouping | DMS (collapsible), Ambxst (sub-grouped by summary) (6) | MUST | MUST, seems trivial to implement like how DMS did it (M:162) | **NEW** | notif collapsible per-app groups (DMS) |
| 69 | Inline action buttons | DMS, noctalia (9) | COULD | COULD, not necessary to have in the first implementation but hapy to revisit the importance of that functionality once this level of detail becomes in discussion (M:164) | **NEW** | required for parity: the unmerged `herdr-attention` branch drives mako actions (§6 G8) |
| 70 | JSON-file history persistence | DMS (configurable retention, max count, per-urgency) (8) | MUST | MUST, useful (M:166) | **NEW** | notif JSON history in $XDG_STATE_HOME with retention |
| 71 | Do Not Disturb toggle | DMS (rules engine), caelestia (IPC + toast) (12) | SHOULD | SHOULD, likely something i toggle with a keybind or a button on bar (M:168) | **NEW** | cli `notifications dnd toggle` + rail state |
| 72 | Notification rules engine (pattern match) | DMS (regex, 5 action types, per-field) (2) | MUST | MUST, nice to have from DMS (M:170) | **NEW** | notif regex rules, first match wins (MA A4) |
| 73 | Swipe-to-dismiss | noctalia (H+V), whisker (drag expand) (6) | COULD | COULD, not too urgent, possibly nice ot have as cosmetic later (M:172) | **LATER** | — |
| 74 | Per-urgency timeouts/colors | noctalia (color-coded progress bar) (5) | MUST | MUST (M:174) | **NEW** | notif per-urgency timeout table + colour |
| 75 | Notification sounds | DMS (system sound themes), noctalia (per-urgency sounds) (3) | SHOULD | SHOULD, dms phenomenal reference (M:176) | **LATER** | — |
| 76 | Progress indicator (hints.value) | caelestia (circular progress on icon) (2) | COULD | COULD, revisit after (M:178) | **LATER** | — |
| 77 | Keyboard navigation in notif center | DMS (full hints overlay) (2) | MUST | MUST, dms hints overlay philosophy is very desirable (M:180) | **NEW** | notif history keyboard navigation + hints overlay |
| 78 | Lock screen notification display | DMS (Disabled/Count/Names/Full) (4) | COULD | COULD, to be revisited later, i rarely to never lock my screen (M:182) | **ICEBOX** | no lock screen |
| 79 | Privacy mode (hide body) | DMS (1) | SHOULD | SHOULD, since we re relying mostly on dms implementation as inspiraton (M:184) | **LATER** | notif |
| 80 | Cross-generation restoration | nucleus (tainted notification matching) (2) | COULD | COULD, to be revisited in a second pass (M:186) | **LATER** | notif |
| 81 | Image caching for history | caelestia (3) | SHOULD | SHOULD (M:188) | **NEW** | notif image cache for history entries |
| 82 | Flood protection / rate limiting | DMS (2) | MUST | MUST, to avoid dangerous or strange behavior on my system (M:190) | **NEW** | notif hard 20/s cap + 1 s duplicate coalescing (MA B6) |

#### 1.4 LAUNCHER / APP DRAWER (M:192)

| # | Feature | Best impl (count) | P | Tom's annotation, verbatim (`> ` stripped) | Disp. | gpuix-shell surface / notes |
|---|---|---|---|---|---|---|
| 83 | App search (fuzzy) | caelestia (dual engine fzf/fuzzysort), DMS (fzf + plugins) (14) | MUST | MUST (M:197) | **REPLACE** | launcher fuzzy app search, replacing vicinae (Mod+d / Mod+space, `binds.conf:6-7`) |
| 84 | Calculator | caelestia (async C++ Qalculator) (6) | COULD | COULD, nice to have (M:199) | **REPLACE** | launcher calculator (vicinae has one; BRIEF §5 asks for parity) |
| 85 | File search | DMS (type/ext/sort filters) (3) | MUST | MUST, and fd plugin seems sufficiend, dms' dsearch was overkill and having a separate package for that is not desirable (M:201) | **NEW** | launcher file provider over `fd`; no indexer daemon |
| 86 | Clipboard mode in launcher | noctalia (ClipboardProvider) (4) | MUST | MUST, it's important for me to have the clipboard history shown in the same aesthetic as the launcher; also making sure that we are displaying images (i use cliphist, prefer not to create special rust functionality as i found DMS reinventing the wheel with their clipboard implementation) (M:203) | **REPLACE** | launcher clipboard mode with image previews; replaces `vicinae cmd launch clipboard:history` (Mod+v, `binds.conf:114`); store = cliphist (§6 G2) |
| 87 | Emoji picker | noctalia (EmojiProvider) (6) | SHOULD | SHOULD, emoji is somehting i have had for years, previously in a handrolled fzf menu, but now we have so many of those emoji pickers it should be trivial to create our own or rip the most performant one (M:205) | **REPLACE** | launcher emoji provider (vicinae parity) |
| 88 | Plugin/provider system | noctalia (persistent instances, 8 built-in + 12+ plugins) (2) | MUST | MUST, dms provider concept is powerful (M:207) | **NEW** | launcher provider registry (DMS getItems/executeItem shape) |
| 89 | Categories/tabs | noctalia (2) | SHOULD | SHOULD, noctalia 12 categories is good enough (M:209) | **NEW** | launcher sections/categories |
| 90 | Favourites/pinned apps | caelestia (SQLite frequency) (4) | MUST | MUST, and caelestia's sqlite frequency is very cool (M:211) | **NEW** | launcher pins + frecency store (SQLite or JSON) |
| 91 | Usage tracking / frecency | caelestia (C++ SQLite) (5) | SHOULD | SHOULD, same as above (M:213) | **NEW** | launcher frecency |
| 92 | App overrides (name/icon/env/flags) | DMS (1) | COULD | COULD, but i like to control my .desktop apps from my local share applications in dotfiles so this is a little redundant (M:215) | **LATER** | —; .desktop entries already live in dotfiles (`home/vicinae.nix`) |
| 93 | dGPU launch option | DMS (1) | WONT | WONT (M:217) | **DROP** | — |
| 94 | Grid/List/Tile view modes | DMS (3) | SHOULD | SHOULD: see my general notes on launcher below (M:219) | **LATER** | list first (Raycast); grid later |
| 95 | Preview panel | noctalia (side panel tracks selection) (1) | COULD | COULD, extremely secondary (M:221) | **LATER** | detail pane (vicinae has detail views) |
| 96 | Action panel (Ctrl+Tab) | DMS (per-item context actions) (1) | SHOULD | SHOULD, this is a nice addition that makes our launcher raycast-like (M:223) | **NEW** | launcher action panel (Raycast / vicinae style) |
| 97 | Wallpaper picker mode | caelestia (Material You preview) (3) | COULD | COULD, very secondary (M:225) | **LATER** | — |
| 98 | Web search | whisker (2) | COULD | COULD, explore implementation later if at all (seems redundant with opening a new google chrome tab and doing my search directly from there, little added value in search results in launcher) (M:227) | **LATER** | vicinae parity may pull it in; Tom sees little value |
| 99 | Shell command execution | noctalia (4) | SHOULD | SHOULD, makes us raycast-like (M:229) | **NEW** | launcher `>` shell-command mode |
| 100 | Prefix search modes | caelestia (8 prefix modes) (2) | SHOULD | SHOULD, explore in second iteration (M:231) | **NEW** | launcher prefix modes |
| 101 | RTL/i18n support | DMS (4) | DONT | DONT i explicitly reject i18n support for now. this is MY shell i'm not trying to reinvent the linux shell for the entire world (M:233) | **DROP** | English only |
| 102 | App blacklist/hide | caelestia (2) | SHOULD | SHOULD because easy (M:235) | **NEW** | launcher hide-list in config |
| 103 | HyprlandFocusGrab dismiss | DMS (2) | DONT | DONT because we're niri wm-exclusive. if there exists a niri alterantive would consider that as COULD (M:237) | **NEW** | not a FocusGrab port (Tom: a WM analogue would only be COULD): the launcher simply closes on Escape or focus loss, as any keyboard-exclusive overlay does |

Section note, M:238: “>>>    GENERAL NOTE on 1.4 LAUNCHER: my shell's launcher in its ideal form will be visual equivalent to macos' RAYCAST. i found it to be the most powerful feature by far. there was a qt launcher called vicinae that tried to reproduce raycast; i could revisit it. but dankmaterialshell's launcher does a great job at getting close to it. we start with the dms implementation as reference and then decide if we want to go beyond”

#### 1.5 AUDIO / MEDIA / OSD (M:240)

| # | Feature | Best impl (count) | P | Tom's annotation, verbatim (`> ` stripped) | Disp. | gpuix-shell surface / notes |
|---|---|---|---|---|---|---|
| 104 | PipeWire native audio | DMS, noctalia (12) | MUST | MUST (M:245) | **KEEP** | `volume` script + `wpctl`; the shell reads state and calls the script |
| 105 | Per-app volume mixer | noctalia (persistent overrides, enforcement timer) (5) | COULD | COULD, to be explored later (M:247) | **LATER** | controls / audio picker |
| 106 | Output/input device picker | DMS (pin/sort, hidden list, device aliases) (7) | MUST | MUST (M:249) | **REPLACE** | audio device picker UI replacing the F9 `audio-route` prompt; routing logic stays in `audio-route` |
| 107 | Output device cycling via IPC | DMS (1) | COULD | COULD (M:251) | **LATER** | cli |
| 108 | Device alias/rename (WirePlumber) | DMS (writes wireplumber.conf.d) (1) | SHOULD | SHOULD, could revisit that, doesnt have to be a part of the first launch (M:253) | **LATER** | — |
| 109 | Volume overdrive (>100%) | noctalia (toggle, color coding) (3) | DONT | DONT explicitly i like to have volume going from 0 to 100; only situation where that's not the case is in vlc media player (M:255) | **DROP** | cap at 100 % |
| 110 | Volume jump protection | Ambxst (15% max jump, "ear-bang" protection) (1) | COULD | COULD, can add later (M:257) | **LATER** | —; `audio-route` already lifts a near-silent stored volume (commit 97ef81a9) |
| 111 | Per-device max volume cap | DMS (per-device via IPC) (2) | COULD | COULD, add later (M:259) | **LATER** | — |
| 112 | Volume feedback sounds | DMS (system sound themes) (2) | COULD | COULD, disabled by default (M:261) | **LATER** | off by default |
| 113 | Audio spectrum visualizer (Cava) | DMS (2) | DONT | DONT i don't care about that (M:263) | **DROP** | — |
| 114 | Audio spectrum visualizer (native C++) | noctalia (32/64 bands, noise reduction) (2) | DONT | DONT i don't care about that (M:265) | **DROP** | — |
| 115 | MPRIS play/pause/next/prev | Universal (13) | MUST | MUST, universal anyway (M:267) | **KEEP** | `media` script on F3–F5 / XF86 keys; rail and launcher add buttons (NEW) |
| 116 | MPRIS seek/position | DMS (wave progress bar) (5) | MUST | MUST, love the progress bar (M:269) | **NEW** | media popover + launcher music view: progress bar with seek |
| 117 | MPRIS shuffle/loop control | DMS (3) | MUST | MUST (M:271) | **NEW** | media popover |
| 118 | Multi-player management | noctalia (browser dedup, virtual merge) (8) | SHOULD | SHOULD, explore later (M:273) | **LATER** | — |
| 119 | Synchronized lyrics (lrclib.net) | whisker (Google Translate, configurable language) (4) | COULD | COULD (M:275) | **LATER** | — |
| 120 | Player blacklist/ignore | noctalia (2) | COULD | COULD (M:277) | **LATER** | — |
| 121 | Track art caching | DMS (TrackArtService) (1) | SHOULD | SHOULD since dms does it  (M:279) | **NEW** | media cover-art cache (Navidrome) |
| 122 | Volume OSD | DMS (9 types, 8 positions) (13) | MUST | MUST. an OSD is very imprtant to have. I found the eqsh one to be very nice (which i m using right now) (M:281) | **REPLACE** | osd window in the notif process; today `osd` sends `notify-send -r` to mako (MEASURED `osd`:8-12; §6 G9) |
| 123 | Brightness OSD | DMS (8) | MUST | MUST but with a small caveat: i really don't care if the brightness is managed by my shell. as you can see now from my scripts, eqsh is sufficient, and i would be happy to have that being a toggle i control from niri keybinds. doesn't really have to be fully integrated with the shell if it adds work (M:283) | **REPLACE** | osd shows the card only; the `brightness` script keeps owning the hardware (Tom's caveat) |
| 124 | Caps/Num/Scroll lock OSD | noctalia (ON/OFF text, vertical mode) (2) | COULD | COULD, revisit that, don't need it at launch (M:285) | **LATER** | —; Caps already pops a touchpad OSD |
| 125 | Media playback OSD (album art) | DMS (blurred art background) (1) | SHOULD | SHOULD, since dms has it.  (M:287) | **NEW** | osd media card with album art |
| 126 | Audio output switch OSD | DMS (device name + icon) (1) | SHOULD | SHOULD (M:289) | **NEW** | osd on output switch (hook in `audio-route`) |
| 127 | Configurable OSD position | DMS (3) | SHOULD | SHOULD, like the dms 8 positions (M:291) | **NEW** | osd placement config; default bottom margin 96 (BRIEF §3.3) |
| 128 | Per-type OSD enable/disable | DMS (2) | COULD | COULD but by default no need (M:293) | **LATER** | — |
| 129 | OSD suppression when panel open | noctalia (2) | SHOULD | SHOULD, since dms has it (M:295) | **NEW** | osd suppressed while launcher / controls are open |
| 130 | Interactive slider in OSD | DMS (3) | COULD | COULD, since dms has it (M:297) | **LATER** | — |
| 131 | Glass-morphism OSD | equora (BoxGlass) (1) | COULD | COULD, if glassmorphism is easy to do with our setup (M:299) | **DROP** | superseded: no blur, no frost |
| 132 | Toast-based OSD | tpaau (unified with notifications) (1) | SHOULD | SHOULD, must learn more about what this does (M:301) | **NEW** | partly realised: toasts and OSD share the notifications process (BRIEF §3.2) |

#### 1.6 NETWORK / BLUETOOTH (M:303)

| # | Feature | Best impl (count) | P | Tom's annotation, verbatim (`> ` stripped) | Disp. | gpuix-shell surface / notes |
|---|---|---|---|---|---|---|
| 133 | WiFi scan/connect with password | DMS (Go daemon D-Bus native) (11) | MUST | MUST (M:308) | **REPLACE** | wifi menu (controls/launcher) replacing `fzf-nmcli`; NM D-Bus or `nmcli` |
| 134 | WPA-Enterprise auth (username/anon identity) | DMS (NM SecretAgent in Go) (2) | SHOULD | SHOULD (M:310) | **LATER** | wifi menu |
| 135 | WiFi disconnect | All equivalent (11) | MUST | MUST (M:312) | **REPLACE** | wifi menu (controls/launcher) replacing `fzf-nmcli`; NM D-Bus or `nmcli` |
| 136 | WiFi radio toggle | noctalia (10) | MUST | MUST (M:314) | **REPLACE** | wifi menu (controls/launcher) replacing `fzf-nmcli`; NM D-Bus or `nmcli` |
| 137 | Forget saved network | DMS (3) | MUST | MUST (M:316) | **REPLACE** | wifi menu (controls/launcher) replacing `fzf-nmcli`; NM D-Bus or `nmcli` |
| 138 | Saved network list | DMS (8) | MUST | MUST (M:318) | **REPLACE** | wifi menu (controls/launcher) replacing `fzf-nmcli`; NM D-Bus or `nmcli` |
| 139 | Hidden network connect | DMS (1) | MUST | MUST (M:320) | **NEW** | wifi menu: manual SSID entry |
| 140 | Network info detail (band/channel/BSSID) | DMS (2) | MUST | MUST (M:322) | **NEW** | wifi menu detail |
| 141 | Ethernet status/management | DMS (multiple devices, full info) (9) | MUST | MUST (M:324) | **NEW** | network menu: wired section |
| 142 | Ethernet detail (IP/MAC/speed/DNS) | DMS (3) | MUST | MUST (M:326) | **NEW** | network menu detail |
| 143 | VPN management | DMS (import/export/edit/credential prompts) (4) | MUST | MUST (M:328) | **NEW** | network menu: NM VPN profiles |
| 144 | VPN multi-provider (WireGuard/Warp/Tailscale) | caelestia (custom provider commands) (1) | MUST | MUST with special focus on tailscale (M:330) | **NEW** | Tailscale provider (`tailscale status --json`) beside NM; reuse `vpn-status` |
| 145 | Network speed monitor | DMS (/proc/net/dev) (2) | MUST | MUST (M:332) | **NEW** | network menu (`/proc/net/dev` deltas) |
| 146 | Airplane mode (WiFi+BT) | noctalia (rfkill, persisted) (1) | MUST | MUST (M:334) | **NEW** | controls / rail: rfkill Wi-Fi + Bluetooth |
| 147 | NM SecretAgent (credential agent) | DMS (Go daemon) (1) | MUST | MUST (M:336) | **NEW** | NM SecretAgent in the shell, or an `nmcli` password prompt for v1 (§6 G6) |
| 148 | Bluetooth power toggle | Universal (11) | MUST | MUST (M:338) | **NEW** | bluetooth menu; no Bluetooth UI exists in dotfiles today (MEASURED: no script) |
| 149 | Bluetooth device discovery/scan | DMS (7) | MUST | MUST (M:340) | **NEW** | bluetooth menu |
| 150 | Bluetooth connect/disconnect per device | DMS (7) | MUST | MUST (M:342) | **NEW** | bluetooth menu |
| 151 | Bluetooth pair/forget | DMS (5) | MUST | MUST (M:344) | **NEW** | bluetooth menu |
| 152 | Bluetooth pairing agent (PIN/passkey) | DMS (full BlueZ Agent1) (2) | SHOULD | SHOULD (M:346) | **LATER** | BlueZ Agent1 in the shell (a D-Bus server role) |
| 153 | Bluetooth battery display | DMS (+ UPower cross-ref) (3) | SHOULD | SHOULD (M:348) | **LATER** | bluetooth menu |
| 154 | Bluetooth audio codec detect/switch | DMS (LDAC/aptX HD/aptX/AAC/SBC via pactl) (1) | SHOULD | SHOULD (M:350) | **LATER** | bluetooth menu |
| 155 | Bluetooth device pinning | DMS (top 3 favorites) (1) | SHOULD | SHOULD (M:352) | **LATER** | bluetooth menu |
| 156 | Bluetooth discoverable toggle | whisker (2) | SHOULD | SHOULD (M:354) | **LATER** | bluetooth menu |
| 157 | Bluetooth signal strength (RSSI) | DMS (2) | SHOULD | SHOULD (M:356) | **LATER** | bluetooth menu |

#### 1.7 COMPOSITOR INTEGRATION (M:358)

| # | Feature | Best impl (count) | P | Tom's annotation, verbatim (`> ` stripped) | Disp. | gpuix-shell surface / notes |
|---|---|---|---|---|---|---|
| 158 | Multi-compositor facade pattern | DMS (4) | WONT | WONT. We are building this shell for niri ONLY. No multi-compositor support. (M:363) | **DROP** | rule kept, compositor changed: Sway ONLY (BRIEF:34) |
| 159 | Niri IPC (dual socket) | DMS / noctalia (4) | MUST | MUST. Confirmed: Rust daemon uses niri-ipc crate with typed bindings, not the 1500-line QML dual socket pattern. (M:365) | **NEW** | Sway IPC in-process (i3-ipc socket, typed). The niri half of this ruling transfers to Sway |
| 160 | Niri config generation (KDL) | DMS (window rules, layout, blur) (2) | COULD | COULD, maybe later if there is justifiable functionality to be gained there but otherwise prefer that the niri kdl config remain in chezmoi-backed dotfiles and not in the purview of the shell (M:367) | **DROP** | Sway config stays in dotfiles (`home/dot_config/sway/*`); the shell never writes it |
| 161 | Hyprland native module | Universal (12) | WONT | WONT: we are niri only (M:369) | **DROP** | Hyprland tried for 74 min on 10-14 and dropped (BRIEF:34-35) |
| 162 | Sway/I3 native module | DMS (2) | WONT | WONT: we are niri only (M:371) | **NEW** | REVERSED by the compositor change: the Sway module is now the only one |
| 163 | ext-workspace-v1 (LabWC) | noctalia (LabwcService) (2) | COULD | COULD, ext worspace is mostly implemmented in niri as well. i don't care about labwc  (M:373) | **LATER** | n/a: Sway IPC is enough |
| 164 | DWL/MangoWC support | DMS (3) | WONT | WONT (M:375) | **DROP** | — |
| 165 | Workspace overview with thumbnails | Ambxst (drag-drop, search) (3) | COULD | COULD. Niri supports ext-image-copy-capture-v1, so thumbnails are technically feasible — but no existing shell has done it for niri. Not trivial. (M:377) | **LATER** | switcher thumbnails via screencopy |
| 166 | Window drag between workspaces | Ambxst (2) | COULD | COULD. Same as #165 — requires niri screencopy, technically possible but uncharted territory. (M:379) | **LATER** | — |
| 167 | Window rules GUI editor | DMS (WindowRuleModal, KDL/Hyprland generation) (1) | WONT | WONT i don't care about editing window rules with gui  (M:381) | **DROP** | — |
| 168 | Scratchpads | piri (directional, configurable) (1 (Rust)) | SHOULD | SHOULD this is piri functionality so would like to have it baked in (M:383) | **KEEP** | Sway has native scratchpads (`move scratchpad` / `scratchpad show`); a sway bind, not the shell |
| 169 | Window swallow (PID-based) | piri (1 (Rust)) | SHOULD | SHOULD this is piri functionality so would like to have it baked in (M:385) | **LATER** | Sway has no swallow; a Sway/herdr helper if ever |
| 170 | Animated workspace indicator (stepping highlight) | HyprQuick (3) | COULD | COULD. Not compositor-specific — purely frontend animation driven by workspace switch events. Works fine with niri. Low priority. (M:387) | **LATER** | —; near-zero animation |
| 171 | Debounced event processing | DMS (4) | COULD | COULD, i like noctalia's 50ms but not sure we need it  (M:389) | **NEW** | internal: coalesce Sway and herdr events (~50 ms) |
| 172 | Output config generation (resolution/scale/HDR) | DMS (1) | COULD | COULD, for now i use `kanshi` to manage outputs and resolutions etc but happy to revisit this later down the line (M:391) | **KEEP** | kanshi (`home/home.nix:72,454`) |
| 173 | Niri overview toggle | tpaau (1) | MUST | MUST, but i think this is just something you feed through the niri config with keybind/ipc (M:393) | **NEW** | Sway has no overview: the switcher (Mod+i) fills that slot |

#### 1.8 SETTINGS / THEMING / CONFIG (M:395)

| # | Feature | Best impl (count) | P | Tom's annotation, verbatim (`> ` stripped) | Disp. | gpuix-shell surface / notes |
|---|---|---|---|---|---|---|
| 174 | Dedicated settings GUI | noctalia (search index, migration), DMS (200+ properties) (10) | MUST | MUST (M:400) | **CONFLICT** | BRIEF §3 names no settings surface; config is nix-rendered (§6 G3) |
| 175 | JSON FileView persistence | Universal pattern (16) | MUST | MUST (M:402) | **NEW** | config JSON from nix + state JSON in $XDG_STATE_HOME |
| 176 | Settings search | noctalia (search index) (1) | MUST | MUST (M:404) | **CONFLICT** | no settings GUI in BRIEF; a launcher "settings" provider could cover search (§6 G3) |
| 177 | Schema migration system | noctalia (2) | COULD | COULD, evenually and in case i do have a schema to migrate from. icebox for now  (M:406) | **ICEBOX** | — |
| 178 | Config validation | Ambxst (5) | SHOULD | SHOULD, but has to be something that is not hardcoded - it has to validate the config schema programaticaly  (M:408) | **NEW** | one TS schema validates the config at start; no hand-coded checks |
| 179 | Presets/profiles system | Ambxst (2) | COULD | COULD, much later down the line. icebox for now (M:410) | **ICEBOX** | — |
| 180 | First-run wizard | noctalia (3) | SHOULD | SHOULD, in fact this is a  (M:412) | **LATER** | the annotation is cut off mid-sentence in the source |
| 181 | Material You / matugen colors | DMS (Go daemon generation) (9) | WONT | WONT whatsoever: no material or material you (i don't like it); no matugen whatsoever as I explained we do not have a strict colorscheme we follow a standard minimal css token (M:414) | **DROP** | — |
| 182 | Predefined color schemes | Ambxst (13 x dark/light = 26 files) (5) | WONT | WONT in the sense that we have only one predefined colorscheme (M:416) | **KEEP** | count superseded: three themes now (noir / claude-dark / claude-light, `home/themes/*.nix`); still one token set |
| 183 | Dark/light toggle | DMS (12) | COULD | COULD far down the line support a single universal dark/light toggle. icebox for now (M:418) | **KEEP** | realised: `theme` (F2) switches noir / claude-dark / claude-light by hand; the shell follows `~/.config/theme` |
| 184 | Auto dark/light (time/location) | DMS (4) | WONT | WONT: even if i do eventually add a light mode this should only be toggled manually (M:420) | **DROP** | — |
| 185 | OLED mode | Ambxst (1) | MUST | MUST. OLED mode ie make the black colors #000000 is something that i do by default. so you could say i do oled compatible color mgmt by default. however if by oled you mean something like "a special setting that reduces oled monitor burn-in somehow" then WONT. i can manage my oled screens myself (M:422) | **KEEP** | noir is the default; wallpaper #000000 |
| 186 | Cross-app theming (GTK/Qt/terminals/editors) | DMS (5) | WONT | WONT. this is also a clear design decision that i take from the start: i do not need help managing my gtk or qt theme etc. that is what dotfiles are for. this also complements my "NO MATUGEN" decision (M:424) | **DROP** | the shell consumes the dotfiles theme fragments; it never writes GTK/Qt themes |
| 187 | Configurable fonts | DMS (family + weight + scale) (8) | SHOULD | SHOULD but the default font, like eqsh, is sanfrancisco mono. (M:426) | **KEEP** | default superseded: Anthropic Sans UI / AnthropicMono Nerd Font (BRIEF:44); family stays configurable |
| 188 | Animation speed control | DMS (None/Short/Medium/Long/Custom) (7) | WONT | WONT. not sure if the shell has anything to do with animation speeds at all, and even if it does i would make it none/short for snappiest experience (M:428) | **DROP** | — |
| 189 | Transparency/opacity config | Ambxst (per-region) (6) | SHOULD | SHOULD. Compositor (niri) owns blur via ext-background-effect-v1; CSS just sets background-color alpha. This reduces to configurable alpha on material levels — a CSS custom property. Trivial once design tokens exist. (M:430) | **DROP** | superseded: flat, opaque, no blur (BRIEF:43-44) |
| 190 | Animated color transitions | DMS (2) | WONT | WONT. no need (M:432) | **DROP** | — |
| 191 | Wallpaper picker | noctalia (directory browser, slideshow) (10) | SHOULD | SHOULD because we are indeed controlling the monitor from quickshell side of things (not niri config) (M:434) | **DROP** | superseded: solid #000000 wallpaper; `wallpaper` script exists if Tom revisits |
| 192 | Per-monitor wallpaper | DMS (2) | SHOULD | SHOULD, if we have a wallpaper picker then might as well have it per-monitor (i mostly use dual monitor setup) (M:436) | **DROP** | same as #191 |
| 193 | Wallpaper fill modes | DMS (2) | SHOULD | SHOULD (M:438) | **DROP** | same as #191 |
| 194 | Parallax wallpaper effect | whisker (ray-marched) (2) | WONT | WONT i explicltly don't need parallax because it makes me dizzy (M:440) | **DROP** | — |
| 195 | Wallpaper slideshow/automation | noctalia (1) | COULD | COULD much later down the line since we have the wallpaper utility anyway (M:442) | **DROP** | — |
| 196 | Procedural sky backgrounds | sshell (weather-reactive) (1) | WONT | WONT too fancy (M:444) | **DROP** | — |
| 197 | i18n / translations | noctalia (21 translations) (4) | WONT | WONT no i18n whatsoever, shell is always in english. (M:446) | **DROP** | — |
| 198 | Per-monitor config overrides | DMS (2) | COULD | COULD but again we manage config with kanshi preferably so might revisit that later (M:448) | **LATER** | kanshi owns outputs |
| 199 | IPC config changes | DMS (7) | SHOULD | SHOULD (M:450) | **NEW** | cli `reload`; the theme symlink watch reloads live (BRIEF §3.5) |
| 200 | Plugin config support | DMS (4) | COULD | COULD but we will do that much later down the line. by "plugin config support" what i understood is that we can control the plugins from within the settings page. in my case it s a custom shell written for one person, so the utilities/plugins i need are configured from the dotfiles themselves. no need to "enable" plugins or browse through them. to be precise, in my world, an ephemeral pomodoro widget has the same place as the main launcher (there is no hierarchy) (M:452) | **DROP** | no plugin browser or enable UI; everything configured from dotfiles; "no hierarchy" |
| 201 | Config versioning | noctalia (2) | COULD | COULD in the future in case i need to migrate a lot. but since it's a single user project we don't need to do a lot of versioning in public.  (M:454) | **LATER** | — |
| 202 | Gradient/halftone theme customization | Ambxst (1) | WONT | WONT (M:456) | **DROP** | — |

#### 1.9 SESSION / SECURITY (M:458)

| # | Feature | Best impl (count) | P | Tom's annotation, verbatim (`> ` stripped) | Disp. | gpuix-shell surface / notes |
|---|---|---|---|---|---|---|
| 203 | Lockscreen (WlSessionLock) | DMS (most features) (10) | COULD | COULD this functionality is quite secondary. i bypass lockscreen by default on reboot (already implemented in my os with greetd automation); and when i need to rest my desktop i do `systemctl sleep`. might revisit this later because the functionality is already documented and we have good references for it. but icebox for now  (M:463) | **ICEBOX** | — |
| 204 | PAM authentication | DMS (custom + fallback), noctalia (auto-detect) (10) | COULD | COULD, icebox for now, like above (M:465) | **ICEBOX** | PAM enters only through the polkit agent (#216) |
| 205 | Fingerprint (fprintd) auth | DMS (separate PamContext + greeter) (4) | COULD | COULD, icebox for now, like above (M:467) | **ICEBOX** | — |
| 206 | U2F/FIDO2 auth | DMS (standalone or 2FA, 30s timeout) (1) | COULD | COULD, icebox for now, like above (M:469) | **ICEBOX** | — |
| 207 | Virtual keyboard on lockscreen | DMS (1) | COULD | COULD, icebox for now, like above (M:471) | **ICEBOX** | — |
| 208 | Media controls on lockscreen | whisker (+ lyrics + Cava visualizer) (8) | COULD | COULD, icebox for now, like above (M:473) | **ICEBOX** | — |
| 209 | Notifications on lockscreen | DMS (4 privacy levels) (4) | COULD | COULD, icebox for now, like above (M:475) | **ICEBOX** | — |
| 210 | Weather on lockscreen | DMS (3) | COULD | COULD, icebox for now, like above (M:477) | **ICEBOX** | — |
| 211 | Shake animation on wrong password | whisker (2) | COULD | COULD, icebox for now, like above (M:479) | **ICEBOX** | — |
| 212 | Video screensaver on lock | DMS (1) | WONT | WONT, too fancy (M:481) | **DROP** | — |
| 213 | Greetd greeter | DMS (weather, fprint, U2F, multi-session, multi-monitor) (2) | COULD | COULD, icebox for now, like above (M:483) | **ICEBOX** | greetd autologin stays |
| 214 | Greeter user selection | DMS (2) | COULD | COULD, icebox for now, like above (M:485) | **ICEBOX** | greetd autologin stays |
| 215 | Greeter session selection | DMS (remembered, .desktop parsing) (2) | COULD | COULD, icebox for now, like above (M:487) | **ICEBOX** | greetd autologin stays |
| 216 | Polkit agent | DMS (fprint detection in polkit PAM) (5) | MUST | MUST. i do not like the classic gtk greeter (that gets used now in the current state of my dotfiles). we are writting a very nice, very well-done uniform design system. dms and others have proven to me that polkit is implemented and easy to do with regular quickshell. this is low-hanging fruit (M:489) | **NEW** | polkit agent (`org.freedesktop.PolicyKit1.AuthenticationAgent`); no agent is configured in dotfiles today (MEASURED: no polkit match in `home/*.nix` or sway config) |
| 217 | Polkit fingerprint support | DMS (parses PAM chain for pam_fprintd) (1) | SHOULD | SHOULD, not vital for now but might as well (M:491) | **LATER** | — |
| 218 | Power menu (shutdown/reboot/suspend) | DMS (hold-to-confirm, keyboard shortcuts, grid/list) (15) | MUST | MUST and in fact i want to mention that i like the new DMS powermenu the most with the ability to scroll/select through a list AND press and hold a given key to get the desired action (M:493) | **NEW** | power |
| 219 | Hibernate detection/support | DMS (detects /sys/power/state) (5) | SHOULD | SHOULD, low hanging fruit (M:495) | **NEW** | power: offer Hibernate only when `/sys/power/state` lists disk |
| 220 | Suspend-then-hibernate | DMS (1) | SHOULD | SHOULD, low hanging fruit (M:497) | **NEW** | power |
| 221 | Userspace reboot | noctalia (1) | COULD | COULD, icebox for now, have to explore this more to understand if i would even benefit from it (M:499) | **ICEBOX** | — |
| 222 | Session action confirmation dialog | DMS (4) | COULD | COULD if i find this to be useful later down the line. for now icebox  (M:501) | **ICEBOX** | the hold-to-confirm of #218 is the confirmation |
| 223 | Compositor-agnostic logout | DMS (2) | WONT | WONT. the webshell project is exclusive to niri window manager (M:503) | **DROP** | Sway `exit` only |
| 224 | Multi-compositor session detection | DMS (2) | WONT | WONT unless we find that we need something else but know that i m using niri standard (M:505) | **DROP** | — |

#### 1.10 IDLE MANAGEMENT (M:507)

Section ruling, M:508: “> COULD the entire idle management suite is not so important for me, i prefer to icebox for now. this applies to 225-232 inclusive”

| # | Feature | Best impl (count) | P | Tom's annotation, verbatim (`> ` stripped) | Disp. | gpuix-shell surface / notes |
|---|---|---|---|---|---|---|
| 225 | Idle inhibitor (Wayland native) | DMS (+ systemd-inhibit fallback) (5) | (section) | — (covered by the section ruling above) | **ICEBOX** | section ruling; `sleep-monitors` (F10) and `monitors-off` stay |
| 226 | Idle monitor (ext-idle-notify) | DMS (3 monitors: screen-off, lock, suspend) (4) | (section) | — (covered by the section ruling above) | **ICEBOX** | section ruling; `sleep-monitors` (F10) and `monitors-off` stay |
| 227 | Per-AC/battery idle timeouts | DMS (1) | (section) | — (covered by the section ruling above) | **ICEBOX** | section ruling; `sleep-monitors` (F10) and `monitors-off` stay |
| 228 | Fade-to-lock/DPMS animations | DMS (1) | (section) | — (covered by the section ruling above) | **ICEBOX** | section ruling; `sleep-monitors` (F10) and `monitors-off` stay |
| 229 | Custom idle commands (JSON-configured) | noctalia (1) | (section) | — (covered by the section ruling above) | **ICEBOX** | section ruling; `sleep-monitors` (F10) and `monitors-off` stay |
| 230 | Inhibit-when-audio-playing | caelestia (1) | (section) | — (covered by the section ruling above) | **ICEBOX** | section ruling; `sleep-monitors` (F10) and `monitors-off` stay |
| 231 | Lock-before-sleep (logind integration) | DMS (daemon-based) (3) | (section) | — (covered by the section ruling above) | **ICEBOX** | section ruling; `sleep-monitors` (F10) and `monitors-off` stay |
| 232 | Caffeine mode (3 modes: sleep/idle/both) | tpaau (1) | (section) | — (covered by the section ruling above) | **ICEBOX** | section ruling; `sleep-monitors` (F10) and `monitors-off` stay |

#### 1.11 UTILITIES (M:521)

| # | Feature | Best impl (count) | P | Tom's annotation, verbatim (`> ` stripped) | Disp. | gpuix-shell surface / notes |
|---|---|---|---|---|---|---|
| 233 | Clipboard manager | noctalia clipper (unlimited, images, pins, type filters, NoteCards) (7) | MUST | MUST the clipboard manager is very important to me. note however that i use cliphist currently. i discuss the specifics of my implementation separately (M:526) | **REPLACE** | launcher clipboard (see #86) |
| 234 | Screenshots (region/full/window) | DMS (native Go wlr-screencopy) (13) | WONT | WONT because existing niri window manager is sufficient (M:528) | **KEEP** | `screenshot` script (Mod+s / Mod+Shift+s / Mod+Alt+s) |
| 235 | Screen recording | Ambxst (gpu-screen-recorder, elapsed time) (8) | COULD | COULD look into what this entails but my first instinct is that i already use OBS Studio (as flatpak) to record screen, making this implmementation quite redundant (M:530) | **KEEP** | OBS (Mod+Shift+;) and `recording-toggle` |
| 236 | Screenshot editor/annotation | noctalia (pencil, arrows, rectangles, text, blur) (2) | WONT | WONT the builtin niri screenshot functionality is sufficient for me (M:532) | **DROP** | — |
| 237 | Color picker | DMS (native Wayland, live magnifier) (4) | MUST | MUST but Color picker currently since i use niri window manager the screenshot tool exists and is sufficient (M:534) | **KEEP** | `colorpicker` script |
| 238 | OCR (tesseract) | Ambxst (multi-language) (2) | SHOULD | SHOULD but with a twist. first off i want to use the existing niri functionality to clip screen (unless there are complications with that, in which case swappy/grim/regular wayland tool is fine). the second twist is that i do NOT want the ocr to be handled by tesseract: it will be handled with qwen 3.5 opensource multimodal llm model which comes with phenomenal ocr from screenshots; and i confirmed it runs on my machine. Backend: HTTP call to llama.cpp server running in a local toolbox container. (M:536) | **KEEP** | realised: `screen-ocr` / `screen-ocr-area` (Mod+Ctrl+s) post to the local model at strix:8731 (MEASURED); notif may show the result |
| 239 | Calendar with events (khal/CalDAV) | noctalia (khal + EvolutionDataServer) (3) | SHOULD | SHOULD keep this idea for later  (M:538) | **LATER** | calendar is a utility outside the shell (BRIEF §3.8) |
| 240 | Calendar month grid display | noctalia (9) | WONT | WONT. the calendar month grid display will be handled by a bespoke, fullscreen, on-brand calendar app FAR later down the line. i do not need such utility in my shell. they're hacky anyway, calendar grids ar not straightforward in qml.. but trivial with web technologies (M:540) | **DROP** | — |
| 241 | Terminal session management (tmux/zellij) | DMS (dual tmux+zellij) (2) | MUST | MUST but i use shpool for terminal sessions, not tmux nor zellij. that being said the dms implementation could be very helpful in my preparation of that fucntionality. requires further specialized scoping (M:542) | **KEEP** | superseded by herdr: rail/switcher read `herdr api snapshot` read-only (§3.8) |
| 242 | Power menu | noctalia (configurable entries, countdown) (15) | MUST | MUST, i believe i already discussed this earlier (M:544) | **NEW** | power (duplicate of #218) |
| 243 | Night light / gamma control | DMS (native wlr-gamma-control) (10) | WONT | WONT, my gamma control and night light is set once and not from the shell. skip entirely (M:546) | **DROP** | — |
| 244 | Weather display | caelestia (auto-location, hourly forecast) (12) | COULD | COULD. very secondary given that i rarely check for this kind of information, but since it seems so common in shells happy to bring that feature over later (M:548) | **LATER** | — |
| 245 | System monitoring (CPU/RAM/disk/temp) | DMS (full process list, kill, GPU temp) (10) | COULD | COULD. very secondary given that i rarely check for this kind of information, but since it seems so common in shells happy to bring that feature over later (M:550) | **LATER** | — |
| 246 | Desktop widgets (draggable) | noctalia (snap-to-grid, scale, plugin-based) (4) | WONT | WONT. i do not like widgets (M:552) | **DROP** | — |
| 247 | AI assistant integration | Ambxst (strategy pattern, streaming, secure keys) (5) | COULD | COULD but much later down the line. i do not need an ai integration the way it is done in the reference qml shells. i have some ideas here so not marking this as won't (M:554) | **NEW** | ask: bounded OpenUI prompt against the local model (BRIEF §3.7); Tom: "i have some ideas here" |
| 248 | Update checker (shell + system) | DMS (multi-distro) (4) | COULD | COULD far later down the line, especially because this should be custom for my system (M:556) | **LATER** | — |
| 249 | Notes/notepad | DMS (3) | WONT | WONT. i use github-backed md notes. see no value in having external notepad. drop that (M:558) | **DROP** | — |
| 250 | Pomodoro/timer | noctalia (bar widget + panel + i18n) (2) | SHOULD | SHOULD the pomodoro timer concept is very valuable and i have my own approach for it. so we use the existing references and build on top of it. this will be the first feature i release AFTER base webshell (M:560) | **KEEP** | `pomodoro` script (Shift+F10); rail indicator + launcher command NEW |
| 251 | Docker/Podman management | noctalia (1) | SHOULD | SHOULD Container management is very desirable on my system, i expand on thsi a little later   (M:562) | **LATER** | systemd / podman unit view |
| 252 | mKDE Connect integration | noctalia (1) | SHOULD | SHOULD; this doesn't have to be done right away but the KDE connect is extremely desirable. i believe that dankmaterialshell also has KDE connect. in the past i also considered Valent for the same. to be scoped out better but i wish to make it clear that "android phone notification" is extremely desirable (M:564) | **LATER** | notif must accept phone notifications as an ordinary fd.o client (KDE Connect / Valent) |
| 253 | QR/Barcode scanner | noctalia (screen-toolkit) (2) | COULD | COULD because easy but not urgent, ocebox (M:566) | **LATER** | — |
| 254 | Google Lens (image search) | Ambxst (2) | WONT | WONT, adds very little value over a google search in google chrome... (M:568) | **DROP** | — |
| 255 | Greetd greeter | DMS (full multi-compositor, weather, fprint, U2F) (2) | COULD | COULD but icebox, until i decide what to do with the greeter situation on my device (M:570) | **ICEBOX** | — |
| 256 | Polkit agent | DMS (fprint detection) (5) | MUST | MUST this one is important (M:572) | **NEW** | same as #216 |
| 257 | Screen pin (floating capture) | noctalia (1) | WONT | WONT (M:574) | **DROP** | — |
| 258 | Screen measurement (pixel distances) | noctalia (1) | WONT | WONT (M:576) | **DROP** | — |
| 259 | Palette extraction from region | noctalia (1) | WONT | WONT (M:578) | **DROP** | — |
| 260 | Webcam mirror (floating preview) | noctalia (1) | COULD | COULD this is indeed desirable, a bit like an "apple camera"; but icebox for now as for these purposes using OBS studio which i already have is sufficient (M:580) | **ICEBOX** | — |
| 261 | Shutdown timer (auto-poweroff) | Kriti (1) | WONT | WONT (M:582) | **DROP** | — |
| 262 | Printer management (CUPS/IPP) | DMS (Go IPP client) (1) | COULD | COULD becaues it's "free" (already have working implementation) but icebox for now because i don't use a printer at the moment  (M:584) | **ICEBOX** | printing now goes through `/print` → paper-daemon (AGENTS.md) |
| 263 | Process manager (kill/signal) | DMS (1) | COULD | COULD later down the line. this reminds me that there was a good DMS plugin for viewing dockerfiles, which i considered extending to see running systemd services and quadlets (M:586) | **LATER** | systemd services / quadlets view |
| 264 | Changelog viewer | DMS (version diff, markdown) (2) | WONT | WONT (M:588) | **DROP** | — |
| 265 | Onboarding/setup wizard | noctalia (5-step) (3) | MUST | MUST but this one will require specific scoping work before i configure it (M:590) | **LATER** | MUST, but "will require specific scoping work"; not scoped in anything I read (§6 G3) |
| 266 | Dependency doctor/checker | DMS (FirstLaunchService) (1) | COULD | COULD later on, don't see an immediate need right now (M:592) | **LATER** | — |
| 267 | SDDM login theme | snes19xx (1) | WONT | WONT i do not use SSDM whatsoever. i use a super minimal greetd implmmentation which means i have no use for sddm or similar (M:594) | **DROP** | — |

#### 1.12 QUICK SETTINGS / CONTROL CENTER (M:596)

Section ruling, M:597: “>> WONT. i do not need a control center. this is not in scope for my project. this applies to 268-280”

| # | Feature | Best impl (count) | P | Tom's annotation, verbatim (`> ` stripped) | Disp. | gpuix-shell surface / notes |
|---|---|---|---|---|---|---|
| 268 | Quick settings panel | DMS (DankDash), noctalia (ControlCenter) (10) | (section) | — (covered by the section ruling above) | **CONFLICT** | section WONT vs BRIEF `controls` (§6 G1). Per-domain home: controls itself: build as per-domain popovers, no unified panel |
| 269 | Volume slider in QS | DMS (10) | (section) | — (covered by the section ruling above) | **CONFLICT** | section WONT vs BRIEF `controls` (§6 G1). Per-domain home: osd + audio picker |
| 270 | Brightness slider in QS | DMS (8) | (section) | — (covered by the section ruling above) | **CONFLICT** | section WONT vs BRIEF `controls` (§6 G1). Per-domain home: osd card; `brightness` script |
| 271 | WiFi toggle + picker in QS | DMS, noctalia (8) | (section) | — (covered by the section ruling above) | **CONFLICT** | section WONT vs BRIEF `controls` (§6 G1). Per-domain home: wifi menu |
| 272 | Bluetooth toggle in QS | DMS (8) | (section) | — (covered by the section ruling above) | **CONFLICT** | section WONT vs BRIEF `controls` (§6 G1). Per-domain home: bluetooth menu |
| 273 | DND toggle in QS | noctalia (8) | (section) | — (covered by the section ruling above) | **CONFLICT** | section WONT vs BRIEF `controls` (§6 G1). Per-domain home: rail bell / `cli dnd` |
| 274 | Dark mode toggle in QS | noctalia (4) | (section) | — (covered by the section ruling above) | **CONFLICT** | section WONT vs BRIEF `controls` (§6 G1). Per-domain home: `theme` (F2) |
| 275 | Power profile selector in QS | DMS (3) | (section) | — (covered by the section ruling above) | **CONFLICT** | section WONT vs BRIEF `controls` (§6 G1). Per-domain home: LATER |
| 276 | Night light toggle in QS | DMS (5) | (section) | — (covered by the section ruling above) | **CONFLICT** | section WONT vs BRIEF `controls` (§6 G1). Per-domain home: DROP (#243) |
| 277 | Idle inhibitor/caffeine in QS | noctalia (4) | (section) | — (covered by the section ruling above) | **CONFLICT** | section WONT vs BRIEF `controls` (§6 G1). Per-domain home: ICEBOX (§1.10) |
| 278 | Media player in QS | DMS (full seekbar) (8) | (section) | — (covered by the section ruling above) | **CONFLICT** | section WONT vs BRIEF `controls` (§6 G1). Per-domain home: media popover |
| 279 | Screen recording toggle in QS | Ambxst (3) | (section) | — (covered by the section ruling above) | **CONFLICT** | section WONT vs BRIEF `controls` (§6 G1). Per-domain home: KEEP `recording-toggle` |
| 280 | Screenshot button in QS | DMS (5) | (section) | — (covered by the section ruling above) | **CONFLICT** | section WONT vs BRIEF `controls` (§6 G1). Per-domain home: KEEP `screenshot` script |


**Section 3 of M, "Plugin Model Validation" (M:658-701).** Tom's whole annotation of it: "`> to be
reevaluated later`" (M:659). The agent summary underneath was written for a QML/SolidJS host and does
not apply. It says ~70% of features are pure frontend plugins, ~20% need a Rust daemon and ~10% are
Quickshell-native singletons (M:697-699).

### 3.2 The gap-analysis rows (M:617-654)

These are features "no shell does well". Every one carries Tom's mark.

| Gap | Description | P | Tom's annotation, verbatim | Disp. | gpuix-shell |
|---|---|---|---|---|---|
| Hotspot creation | No shell creates WiFi hotspots | WONT | WONT (M:624) | **DROP** | — |
| Scheduled DND | Time-based automatic Do Not Disturb | WONT | WONT (M:626) | **DROP** | — |
| Inline reply in notifications | Reply directly from notification popup | WONT | WONT (M:628) | **DROP** | —; notif still needs ordinary actions (§6 G8) |
| Full-text search in notification history | Search past notifications by content | WONT | WONT (M:630) | **DROP** | — |
| Brightness without CLI | Native sysfs/DDC-CI brightness control | WONT | WONT (M:632) | **DROP** | KEEP the `brightness` script |
| Native clipboard manager | Wayland-native clipboard without cliphist | COULD | COULD. discussed externally. to be revisited later. could convince me to move away from cliphist (M:634) | **LATER** | cliphist stays the store (§6 G2) |
| Notification grouping by urgency | Group notifications by urgency level | WONT | WONT (M:636) | **DROP** | — |
| Notification snooze | Dismiss temporarily, re-surface later | WONT | WONT (M:638) | **DROP** | — |
| Per-app notification sounds | Different sounds per app | WONT | WONT; i barely expect nofitication sounds anyway (M:640) | **DROP** | — |
| Calendar event creation | Create events from the shell, not just read | COULD | COULD but much much further down the line (M:642) | **LATER** | utility outside the shell |
| Input method editor (IME) | CJK/complex script input integration | WONT | WONT (M:644) | **DROP** | — |
| Accessibility screen reader | AT-SPI integration for screen reader users | WONT | WONT (M:646) | **DROP** | — |
| Multi-user quick switch | Switch Linux users without logout | WONT | WONT, i use single-user on my desktop (M:648) | **DROP** | — |
| Spatial audio routing | Per-window audio sink assignment | WONT | WONT (M:650) | **DROP** | — |
| HDR status/control | HDR toggle and status display | WONT | WONT, i do not care much for hdr and not even sure niri/my monitor has it (M:652) | **DROP** | — |
| Touch/gesture support | Swipe gestures for panels/workspaces | COULD | COULD but much later down the line. I have `lisgd` installed for touch support. niri also has something with touch support. for now no need to configure this at all. icebox maximally (M:654) | **LATER** | the Duo is the physical seat; touch may matter sooner (§6 G12) |

### 3.3 The kmux agent sidebar and bar widget (K §§D–M) → rail + herdr

| K item (line) | Exact behaviour (K) | Tom's mark | Disp. | gpuix-shell now |
|---|---|---|---|---|
| L1a (:245) | "PanelWindow: 400px right, full height, WlrLayershell Overlay, transparent bg." | (no mark) | REPLACE | `rail`: left, layer top, exclusive zone 56/220 (BRIEF §3.3); opaque |
| L1b (:246) | "Visible across all niri workspaces (layer-shell, not workspace-scoped)." | (no mark) | NEW | `rail` is output-wide, not per-workspace |
| L1c (:247) | "Toggle: `shell ccd toggle` IPC command." | (no mark) | NEW | `cli`: `gpuix-shell rail toggle` / `expand` |
| L2a–e (:253-257) | Header (brand + clock + search), quick spawn (deferred), workspace list grouped Active/Completed/Detached, entry detail, 32 px summary bar "`N active * N waiting \| $total`" | (no mark) | NEW / LATER | `rail` expanded: slots 1–9 in herdr order; aggregate "N working · N blocked" badge (INFERRED); cost display LATER (`claude-capacity` exists) |
| L3a–f (:261-266) | Entry rows: status dot + title + model badge + age; tags + diff stat; 3 px context bar blue→amber→red; active entry 2 px left accent; click → `niri msg action focus-workspace`; subagent indent 16 px | (no mark) | NEW / LATER | `rail` slot: herdr status glyph + workspace name; click → `swaymsg workspace number N`. Diff stat, context bar and subagents: LATER (herdr snapshot fields to be checked) |
| L4 (:268-275) | dots: green `#34D399` completed; blue `#60A5FA` working (2.5 s pulse); amber `#FBBF24` waiting; red `#F87171` error; gray detached | "> acceptable for now, to be unified later of course" (:269) | REPLACE | herdr glyphs: blocked ◉ / working ◐ / done ● / idle ✓ / unknown ○ (BRIEF:40). Colours come from the theme; no pulses (near-zero animation) |
| M1–M4 (:294-297) | CCD indicator in the bar: any agents active, how many waiting (badge); click toggles sidebar; reads `os.claude.sessions` | (no mark) | NEW | `rail` collapsed state shows per-slot glyphs; a blocked count badge; click expands |
| D4g (:131) | "Click entry → `niri msg action focus-workspace` jumps to agent" | part of the v0.1 acceptance test | NEW | rail click / Mod+1..9 → Sway workspace N (one herdr workspace = one Sway workspace) |
| E1 (:135) | FSM `spawning → working → waiting_for_approval → waiting_for_input → idle → error → completed` | "locked across all versions" (heading :133) | REPLACE | herdr's agent status owns this; the shell only reads it |
| E2 (:136) | "Signal priority: hooks (highest) > JSONL logs > VT screen patterns > process CPU state (lowest)" | locked | KEEP (value) | read herdr state; never scrape the screen |
| H6 (:177) | per-workspace fields: workspace_id, cwd, git_branch, claude_state, claude_model, claude_tool, claude_tokens, claude_last_msg, notification_count | (no mark) | LATER | rail tooltip / switcher detail, if `herdr api snapshot` exposes them (unverified) |
| P1 (:429) | cmux keyed status model (`set-status <key> "text"`): concurrent writers never clobber each other | (no mark; "adopt" list) | NEW (value) | `cli`: `gpuix-shell status set <key> <text>` for scripts (pomodoro, recording, OCR). INFERRED |
| P3 (:431) | "no-focus-stealing principle — socket commands never activate app or move focus unless method is explicitly focus-intent" | adopt | NEW (value) | `cli` verbs are non-focusing unless named `focus`/`open` |
| P4 (:432) | environment auto-injection so agents target their own workspace | adopt | KEEP | herdr already scopes agents to workspaces |
| P15/P17 (:443,:445) | TodoWrite as expandable lists; Active/Completed/Detached grouping | adopt | LATER | switcher detail |
| Q1 (:449) | "cmux: GPUI-based TUI rendering. We use web-over-compositor" | reject | **reversed** | GPUIX is a GPUI-family renderer; tonight's renderer choice overrides Q1 |
| J2 (:199-200) | shpool fork (+500 lines) | "> ABANDONED COMPLETELY" | DROP | — |

### 3.4 CUBS master surface map (SSD:73-96) → gpuix-shell

Grades are SSD's (ChromeOS-ash liftability). They are irrelevant now; the "Noctalia ref" and
"reseat target" columns are what carry over.

| Surface (SSD) | SSD reseat target (generic Linux) | gpuix-shell surface | Disp. | Note |
|---|---|---|---|---|
| Top bar / status area | — | `rail` (no top bar: BRIEF:48) | NEW | status cluster sits at the bottom of the rail |
| QS: Network | NetworkManager | wifi menu (launcher/controls) | REPLACE `fzf-nmcli` | M #133–147 |
| QS: Bluetooth | BlueZ | bluetooth menu | NEW | M #148–157 |
| QS: Volume | PipeWire | `osd` + audio picker | KEEP `volume`, REPLACE `audio-route` UI | M #104–106 |
| QS: Brightness | logind/sysfs (+ddcutil) | `osd` card only | KEEP `brightness` | M #123 caveat |
| QS: Power profile | power-profiles-daemon | `controls` | LATER | M #54/#275 |
| Notifications | fd.o Notifications **server** | `notif` | REPLACE mako | M #65 "non-negociable" |
| OSD sliders | reuses volume/brightness producers | `osd` | REPLACE `osd`→mako path | M #122 |
| Launcher | `.desktop` scan + providers | `launcher` | REPLACE vicinae | M #83–103, general note M:238 |
| Overview / desks / Alt-Tab | (CADE: lifted; CUBS: delegated to niri) | `switcher` (Mod+i) | NEW | Sway owns windows; the shell only reads |
| Lock / login / auth | PAM/fingerprint | — | ICEBOX | M #203–215 |
| Wallpaper | local file | — | DROP | wallpaper is solid `#000000` |
| Power menu | — | `power` | NEW | M #37/#218 |
| Session actions | logind | `power` | NEW | systemd/loginctl calls |
| Clipboard history | Ozone/Wayland clipboard | `launcher` clipboard mode | REPLACE vicinae | §6 G2 |
| Context menus | — | per-surface popovers | NEW | GPUIX popups over layer-shell: see §6 G7 |
| Calendar / date tray | CalDAV subset | `rail` clock only | DROP grid / LATER events | M #239/#240; calendar is a utility outside the shell |
| System tray (SNI) | `org.kde.StatusNotifierWatcher` + dbusmenu | `rail` | LATER | M #29 "won't be using it personally" |
| Media widget (MPRIS) | MPRIS2 client | `rail` + media popover + launcher music | NEW | M #34/#115-117; Navidrome demo |
| Polkit agent | `org.freedesktop.PolicyKit1` agent | `power`-family auth dialog | NEW | M #216/#256 MUST; none configured today (MEASURED) |
| Privacy indicators | PipeWire mic/cam/screen-share | `rail` dots | NEW | M #39/#60 MUST |
| Wayland app hosting (exo) | — | — | DROP | Sway hosts apps |

SSD §7 "Explicitly OUT of scope" (SSD:173-178) also stays out:

- Luau plugin runtime and plugin store
- the theme template engine and community palette fetch
- dmenu socket compat
- weather and IP geolocation
- screen-time tracking
- the setup wizard
- the desktop-widgets editor
- the audio visualizer

Exceptions: calculator and emoji are now in scope through vicinae parity (BRIEF §5).

### 3.5 CUBS producer roster (S06:55-80) → gpuix-shell data adapters (BRIEF §3.4)

| S06 producer | Daemon / interface (S06) | gpuix-shell adapter | Disp. |
|---|---|---|---|
| PowerProducer | UPower `org.freedesktop.UPower`, `/devices/DisplayDevice` | dbus-next client → `rail` battery | NEW |
| PowerProfilesProducer | `net.hadess.PowerProfiles` (S06 flags the bus name as open, S06:117) | dbus-next → `controls` | LATER |
| suspend/shutdown | logind `Inhibit`, `PrepareForSleep`, `PowerOff`, `Reboot` | `power` via `systemctl`/logind | NEW |
| BrightnessProducer | logind `Session.SetBrightness` or sysfs; "*NOT UPower*" | existing `brightness` script; `osd` reads % | KEEP |
| AudioProducer | libpipewire native socket | `wpctl` (BRIEF §3.4) | KEEP + NEW display |
| NetworkProducer + SecretAgent | NM D-Bus; the agent owns `…NetworkManager.SecretAgent` | NM D-Bus or `nmcli`; SecretAgent per §6 G6 | NEW |
| TailscaleProducer | `tailscale status --json` poll 5 s; "tun is invisible to NM" | reuse `vpn-status` (MEASURED: emits JSON "for bar widget consumption") | NEW surface |
| BluetoothProducer + Agent1 | BlueZ `org.bluez.Adapter1/Device1/Battery1/Agent1` | dbus-next BlueZ client; Agent1 LATER (#152 SHOULD) | NEW |
| ClockProducer | timedated | JS `Date`; NTP/timezone settings not wanted | DROP |
| LogindSession / SessionState / SessionController | logind Session `Lock/Unlock/SetLockedHint` | — (no lock screen) | ICEBOX |
| AuthProducer (PAM) | libpam | only inside the polkit agent helper | NEW (narrow) |
| NotificationServer | owns `org.freedesktop.Notifications`; "rules engine (RE2), 20/s cap, JSON history" | `notif` daemon (dbus-next server) | REPLACE mako |
| TrayProducer (SNI) | owns `org.kde.StatusNotifierWatcher` + dbusmenu | — | LATER |
| MediaProducer (MPRIS) | `org.mpris.MediaPlayer2*`; "position interpolation (1s) + 100ms track-change debounce" | dbus-next MPRIS client (+ mpv for Navidrome) | NEW |
| PolkitAgent | `org.freedesktop.PolicyKit1.AuthenticationAgent`; "90s wall-timer… 3-retry, must kill `polkit-gnome-*`" | `power`-family dialog + helper | NEW |
| CaptureDelegate | Viz capturer | `screenshot`, `screen-ocr-area`, `colorpicker` scripts | KEEP |
| UpdateProducer | rpm-ostree / Nix backend | — | LATER |
| LauncherProducer | XDG `.desktop` scan + SQLite frecency; one exec chokepoint | `launcher` providers + a single command runner | REPLACE vicinae |
| IdleInhibitProducer | logind `Inhibit("idle")`, ScreenSaver export | — | ICEBOX |
| WallpaperProducer | local file decode | — | DROP |
| (06 "SignalSources") niri / kerdr / tally / shpool | `$NIRI_SOCKET`; kerdr HTTP hooks; tally subprocess; shpool socket | Sway IPC socket; `herdr api snapshot` + `herdr workspace list`; tally removed 2026-09-30 (AGENTS.md); shpool superseded | REPLACE (see §3.8) |

Bus-name ownership rule (S06:82, :467; `HANDOFF-views-shell…:29-35`): exactly one process owns each of
`org.freedesktop.Notifications`, the polkit agent, the NM SecretAgent and `org.bluez.Agent1`. **For
gpuix-shell:** `notif` must never run beside mako (BRIEF:62 already says "never both"). The polkit
agent and any SecretAgent must also be single-owner.

### 3.6 The "Ultimate Desktop Shell" 17-domain taxonomy (U) → `cli` verbs

U records, for each domain, which verbs a controller needs (DMS's `dms ipc call` surface as ground truth).

| U domain (line) | Verbs U names | gpuix-shell verb (INFERRED proposal) | Class (U:379-407) |
|---|---|---|---|
| 1 Panels (U:21-40) | `bar reveal/hide/toggle/toggleReveal`, `bar status`, `widget list/toggle <id>` | `rail toggle\|expand\|collapse [--output]`, `rail status` | reversible |
| 2 Launcher (U:42-58) | `spotlight open/close/toggle`, **`spotlight openQuery <q>`**, `defaultApp …` | `launcher toggle`, `launcher open --query <q> [--provider clipboard\|files\|music]` | reversible |
| 3 Notifications (U:62-79) | `notifications open/close/toggle`, DND get/set, event stream, dismiss/invoke by id | `notifications toggle`, `dnd on\|off\|toggle`, `notify …` (BRIEF §3.2), `dismiss <id>`, `action <id> <key>` | reversible / mild-irreversible |
| 4 OSD (U:83-95) | none; side effect of volume/brightness | `osd show <kind> <value>` (BRIEF §3.2) | reversible |
| 5 MPRIS (U:99-113) | `mpris list`, `play/pause/playPause/previous/next/stop`, now-playing events | `media …` (or keep the `media` script) | reversible |
| 6 Tray (U:117-133) | list items; activate/open menu | LATER | irreversible (third-party) |
| 7 Audio (U:137-153) | `audio setvolume/increment/decrement/mute/setmic/micmute`, `audio status`, default-sink set | keep the `volume` / `audio-route` scripts; `audio picker` opens the UI | reversible |
| 8 Network (U:157-172) | status read; **connect is secret-laden** | `wifi menu`; passwords only in the local dialog | secret |
| 9 Bluetooth (U:176-189) | read; power/scan/connect; separate confirm-pairing path | `bluetooth menu` | reversible + secret |
| 10 Power (U:193-209) | `powerprofile list/status/set/cycle`, `inhibit …` | LATER | reversible |
| 11 Session (U:213-239) | `lock …`, `powermenu open`; "*Unlock* — must never be a remote verb" | `power toggle`; **no unlock verb**; suspend/reboot/poweroff only behind hold-to-confirm in the UI | irreversible / auth |
| 12 Monitoring (U:243-255) | metrics stream; `processlist toggle`; kill guarded | LATER | read / irreversible |
| 13 Clipboard (U:259-272) | `clipboard open/close/toggle`; "potentially secret-laden" | `launcher open --provider clipboard`; skip password-hinted MIME (MA C15) | secret-adjacent |
| 14 Capture (U:276-290) | capture trigger; `color-picker …` | keep the scripts | privacy |
| 15 Theming (U:294-307) | `theme toggle/light/dark/getMode` | keep the `theme` script; the shell watches the symlink | reversible |
| 16 Wallpaper (U:311-323) | `wallpaper get/set/…For` | DROP | — |
| 17 Calendar/dash (U:327-339) | `dash open/close/toggle [tab]`, notepad | DROP (no dashboard, no notepad) | — |

U's "load-bearing" ten (U:356-372), as they stand now:

| # | Domain | Status |
|---|---|---|
| 1 | bar | in scope |
| 2 | launcher | in scope |
| 3 | notifications | in scope |
| 4 | audio | in scope |
| 5 | network | in scope |
| 6 | power/battery | in scope |
| 7 | session/lock/auth | Tom iceboxed the lock; polkit and the power menu stay |
| 8 | MPRIS | in scope |
| 9 | tray | Tom: SHOULD, won't use |
| 10 | control center + theming | Tom: WONT CC, WONT matugen |

### 3.7 What was abandoned, and why

| Abandoned | When | Why (verbatim where Tom said it) | Pointer |
|---|---|---|---|
| QuickshellX / QtWebEngine web shell | Mar 2026 | "There is no escape hatch": a dropdown cannot leave a 40 px bar; allocator clash (jemalloc vs PartitionAlloc) | LIN:79-83 |
| `os.*` / Mojo web shell (COWL secondpass) | 2026-06-29 | "we have decided to move away from this model" (CL:95-96); a shell is "a system-state visualizer, not a document viewer" | CL:90-98; S02:9-43 |
| CADE (lift ChromeOS ash, be the compositor) | 2026-06-29 | "something as trivial as mouse scrolling is not functional. starting nautilus from terminal crashed the entire session." (CL:32-33); "the design doesn't use what CADE is *for*" | CL:28-33; S01:39-76 |
| noctalia-native engine | 2026-06-29 | "the measured 243 KLOC price of the path Chromium gives you for free" | S01:93-95 |
| miracle-wm / Mir / WASM policy | Apr 2026 | "No — stay on niri" (WASM programs the compositor, the wrong altitude) | CP:92-95 |
| Views C++ in a Chromium fork (CUBS itself) | after 2026-10-01 | not in these notes. INFERRED from BRIEF: the GPUIX pivot (Oct 13) replaced it; the iteration tax S02:148-152 warned about ("no hot reload… a real warning for a solo builder") is the likely reason | S02:148-152 |
| shpool fork | Mar 2026 | "> ABANDONED COMPLETELY" | K:199-200 |
| QtWebEngine as webview | Mar 2026 | "> no this is wrong. discard this information" | K:26-27 |
| Python glue | Mar 2026 | "> no python, thinking all rust" | K:33-34 |
| Multi-compositor support | Mar 2026 | "> WONT. We are building this shell for niri ONLY." | M:363 |
| Material You / matugen | Mar 2026 | "> WONT whatsoever: no material or material you (i don't like it)" | M:414 |
| Control center | Mar 2026 | "> WONT. i do not need a control center." | M:597 |
| i18n | Mar 2026 | "this is MY shell i'm not trying to reinvent the linux shell for the entire world" | M:233 |
| Desktop widgets, notes, BongoCat, parallax, procedural sky, Google Lens, screen-toolkit extras | Mar 2026 | "i do not like widgets"; "drop that"; "we're building a serious shell"; "makes me dizzy"; "too fancy" | M:552, :558, :139, :440, :444, :568, :574-578 |
| Tesseract OCR | Mar 2026 | "i do NOT want the ocr to be handled by tesseract" | M:536 |
| DMS dsearch | Mar 2026 | "dms' dsearch was overkill and having a separate package for that is not desirable" | M:201 |
| Shell-side screenshots / night light | Mar 2026 | "existing niri window manager is sufficient"; "set once and not from the shell" | M:528, :546 |
| Dark-glass / blur | Oct 2026 (BRIEF) | the Claude/Primer look adopted: "whatever you just opened: i love it" | BRIEF:41-44 |
| niri | by Oct 2026 | Sway chosen; Hyprland trial dropped "let s stick to sway window manager. less effort" | BRIEF:34-35 |
| tally (proof-of-work signal source) | 2026-09-30 | "Tally, which was removed on 2026-09-30" | AGENTS.md (Claude seats paragraph) |

### 3.8 Where herdr now takes the role an older design gave to something else

| Older role (source) | What it did | herdr today (BRIEF) | Consequence for gpuix-shell |
|---|---|---|---|
| **shpool** "Always-shpool model" (K:49-50, M:542) | PTY persistence, reattach | herdr server on the strix keeps sessions; the client projects with `herdr --remote strix` | no terminal-session code in the shell (#241 → KEEP herdr) |
| **kerdr** "uniform session primitive… list / attach / steer / kill… recoverable" (S04:84-87) | supervised recoverable sessions | herdr workspaces and agents (`herdr workspace list`, `herdr agent list`) | `rail`/`switcher` read them; never write them |
| **ccd daemon** / `os.claude` (K §F; S06:242, :255, :265) | hook-fed Claude session FSM, permission gating | herdr agent status: blocked ◉ / working ◐ / done ● / idle ✓ / unknown ○ | the shell reads status read-only; permission UI stays in herdr / Claude Code |
| **CCD sidebar** (K §L; S06:174) | right 400 px overlay listing agent sessions | **left rail**, merged with the workspace switcher Tom put on the left (M:75) | one surface, not two; herdr-web-ui rail metrics 220/30/12/2/8 (BRIEF:87) |
| **niri workspace as "captured concept"** = grouping + provenance (the Claude chat) + kerdr session + tally entry (S04:65-77) | workspace = recoverable concept | one herdr workspace = one kitty projector = one Sway workspace, 1–9 (BRIEF:36-38) | Mod+1..9 / rail click target the Sway workspace; provenance is herdr's name/metadata. Tally is gone |
| **SignalSource** "any CLI/daemon that emits a typed state/event stream" (S04:48-50) | a generic signal binding | herdr is the primary signal source; Sway IPC the second | keep the abstraction: a `sources/` module per signal (herdr, sway, dbus, scripts). INFERRED |
| **kmux** "pi-wrapped-in-kerdr" (LIN:193) | agent harness concept | herdr hosts Claude/Codex panes | nothing for the shell to own |
| **"COWL widget… ambient panel of every LLM running on the box"** (LIN:193) | visibility of all agents | rail collapsed glyphs + switcher | the rail **is** that ambient panel. INFERRED |
| **`niri msg action focus-workspace`** (K:131, :265) | jump to an agent | `swaymsg workspace number N` (and `herdr workspace focus`) | the rail acts through Sway (BRIEF:40) |
| **OSC 99 → kitty → mako** (K:110, :218) | agent notifications | herdr notifications + the `herdr-attention` branch → mako actions | `notif` must implement actions (§6 G8) |

---

## 4. Design values

Each value carries its evidence. Values that still bind tonight are marked ✔; those reversed later are marked ✘.

1. ✔ **A shell is a system-state visualizer, not a document viewer.** "A desktop shell renders **live
   system state**… and lets you act on it" (S02:9-13). This is why the core surfaces are native
   (GPUIX) and the web or LLM-authored canvas is a bounded carve-out: "Views (native): the
   launcher/command-palette first… Web (kept): the agent canvas" (S02:138-143). It maps to BRIEF §3.7:
   OpenUI `ask` is bounded and off the critical path. REPORTED, agent-authored, Tom-ratified by CL:60-61.
2. ✔ **Reuse maximally, build minimally, delegate the compositor.** "*reuse maximally (Chromium +
   freedesktop daemons), build minimally (a thin additive layer), and delegate the compositor to
   niri*" (LIN:429-432). Now Sway owns layout. The shell claims "**no** layout authority" (S06:192),
   reads Sway and herdr, and acts through Sway.
3. ✔ **One compositor, no facade.** M:363, :369, :371, :375, :503, :505. With Sway in place of niri:
   no multi-compositor abstraction layer in gpuix-shell.
4. ✔ **Keybind-first; every surface is toggleable from the WM; one IPC toggle per bar.** Sources:
   - "i want to toggle bars with a niri keybind" (M:34)
   - "one ipc toggle should control only one bar" (M:56)
   - "i prefer toggling things with keybinds" (M:149)
   - "a toggle i control from niri keybinds" (M:283)
   - "All keyboard shortcuts must be pre-configured niri KDL files. No runtime registration." (K:411)

   Sway binds call the `cli` (BRIEF §3.2); the shell registers no global shortcuts.
5. ✔ **Config lives in dotfiles, not in the shell; no plugin browser; no hierarchy.**
   - "prefer that the niri kdl config remain in chezmoi-backed dotfiles and not in the purview of the
     shell" (M:367)
   - "i do not need help managing my gtk or qt theme etc. that is what dotfiles are for" (M:424)
   - "the utilities/plugins i need are configured from the dotfiles themselves… an ephemeral pomodoro
     widget has the same place as the main launcher (there is no hierarchy)" (M:452)
   - "i like to control my .desktop apps from my local share applications in dotfiles" (M:215)
6. ✔ **"Turn any functionality into a bar addition" / one provider contract.** M:24 (#4 MUST) and
   M:207 (#88 "dms provider concept is powerful"). MA A1 makes both one registry (MA:171). INFERRED for
   gpuix-shell: one `registry.ts` where a script or CLI becomes a rail item, a launcher command, or both.
7. ✔ **Raycast is the launcher north star; the clipboard sits in the launcher.** M:238 (general note),
   M:203 ("clipboard history shown in the same aesthetic as the launcher"), M:223 and M:229 ("makes our
   launcher raycast-like"). BRIEF §5 raises the bar to full vicinae parity.
8. ✔ **Don't reinvent wheels Tom already uses:**
   - cliphist (M:203, :526)
   - fd rather than a separate indexer (M:201)
   - the WM's screenshot tool (M:528, :532)
   - OBS (M:530, :580)
   - kanshi (M:391, :448)
   - a local LLM for OCR (M:536)
   - "dms … reinventing the wheel with their clipboard implementation" (M:203)
9. ✔ **A serious shell; no cosmetics.** "we're building a serious shell" (M:139); "i m not too big on
   wallpaper changing and other cosmetic trivialities" (M:135); widgets, parallax and procedural sky are
   all WONT (M:552, :440, :444).
10. ✔ **Near-zero animation.** "i really do not care about animations whatsoever" (M:62); "none/short
    for snappiest experience" (M:428); B12 50 ms ceiling "yes for now" (K:65-66).
11. ✔ **One minimal token set; OLED black by default; anti-Material-You.** M:414, :416, :422; N8 anti-patterns
    (K:349-364): no card-in-card, no decorative gradients, no colored text except accent/semantic, no
    font below 10 px or above 28 px, no padding over 16 px in shell chrome. Now carried by the
    noir/claude palettes (BRIEF §3.5-6). ✘ The blur and glass parts were reversed (§2.6).
12. ✔ **Theme from semantic tokens only.** Tom: "i want my tier-2 chromium program — chrome-cowl — to
    have the same uniform themability as the tabstrip… written from the get-go" (CL:66-67). The
    agent's rule from that exchange: "color-IDs everywhere, raw colors nowhere" (CL:68). For
    gpuix-shell, every colour comes from `gpuix-shell.json`.
13. ✔ **Uniformity.** Tom: "something about the uniformity of a mono interface is very appealing… we keep
    the bar in views and pay the price of being backed by chromium" (CL:60-61). Also "we are writting a
    very nice, very well-done uniform design system" (M:489, said of the polkit dialog).
14. ✔ **Single user, English only.** M:233, :446, :648.
15. ✔ **Status from structured data, never screen scraping; the filesystem is the API; composition over
    monolith.** K B3, B6, B7 (K:47-56), each answered "yes". The rail reads herdr's structured snapshot.
16. ✔ **Security asymmetry for any control verb.** "`lock` is a safe one-way verb; `unlock` is not a
    verb at all" (U:404-407). Irreversible verbs are gated and secret paths stay local (U:394-402). Also
    "unlock is never a mojom method" (S06:262). For gpuix-shell: `power` actions only through the UI
    hold-to-confirm; Wi-Fi passwords and polkit passwords never travel through `cli`.
17. ✔ **One owner per bus name and per exec path.** S06:88-89 (single owner per domain), S06:185 ("every
    launch routes through the one `CubsCommandRunner`"). For gpuix-shell: one process owns
    `org.freedesktop.Notifications`, and one command-runner module spawns everything.
18. ✔ **No focus stealing.** K P3 (K:431).
19. ✔ **Render first.** "paint shape and skeleton immediately on `INITIAL_STATE`, fire services
    non-blocking (`.catch`), never `await` data before render" (LIN:396).
20. ✔ **Push full snapshots on change.** "L3 producers push **full vector snapshots** on every change"
    (S06:380). This suits React state: one snapshot per source.
21. ✔ **Don't z-stack chrome over content.** "shell chrome and content are **separate layer-shell
    surfaces**… never overlapping overlays" (S02:81-85). This supports the exclusive-zone rail;
    transient overlays (launcher, OSD, toasts) are the exceptions.
22. ✔ **Use case precedes surface; compounding test.** "scope is now PULLED by an experience, not
    PUSHED by own-the-stack" (LIN:350); "build ONLY what changes a repeated action that compounds"
    (LIN:362). This argues for ranking work by Tom's MUSTs (§3.1), not by feature counts.
23. ✔ **Evidence, not claims.** "the audit must RUN its checks, never assert them" (LIN:358); "Done is a
    claim… exit code are evidence" (LIN:178). Matches BRIEF §4 ("never claim a test ran if it did not").
24. ✘ **"Performance" as the objective function.** CUBS: "The objective function is
    **snappiness/solidity**" (SSD:20-22). Tom tonight: "performance is not really the thing i m looking
    for here" (BRIEF:48). Keep correctness and solidity; do not chase frame-time.

---

## 5. Reusable code and data, with paths

| What | Path | Size | How to use it tonight |
|---|---|---|---|
| **Left workspace sidebar with true layer-shell collapse**: groups workspaces by output; focused/active highlight; window count; click-to-focus; "collapse/expand toggle (claude.ai-web style)" that resizes the surface **and exclusive zone** so the WM re-tiles; expanded = output/8, rail = output/20 | `jun26-cowl-secondpass-surfaces/ccd/app.js` (header at :1-30) | 181 lines | behaviour reference for `rail` expand/collapse (BRIEF: 56 ↔ 220). INFERRED: check that GPUIX can change `exclusiveZone` on a live surface; if not, recreate the surface |
| fd.o notification server in JS (over `os.dbus`) | `jun26-cowl-secondpass-surfaces/lib/notification-service.js` | 954 lines | port the method/signal set and capability strings to dbus-next |
| polkit agent in JS | `…/lib/polkit-service.js` | 503 lines | reference for the PolicyKit1 AuthenticationAgent state machine |
| SNI tray host in JS | `…/lib/tray-service.js` | 998 lines | LATER (tray) |
| shared services (niri, dbus, audio…) | `…/lib/services.js`, `lib/kernel.js` | 1150 / 415 lines | data-shape reference; the morphdom kernel is not reusable |
| bar widgets, launcher, OSD, Claude session UI | `…/bar/widgets.js`, `launcher/app.js`, `osd/app.js`, `clui/{app,sessions,stream}.js` | 384 / 370 / 102 / 643+ lines | UI behaviour references |
| typed `os.*` API (22 namespace specs) + declarations | `april-webshell-refs/spec/{os.*.md,os.d.ts,surfaces.md,SPEC.md}` | `os.d.ts` 2131 lines | vocabulary for gpuix-shell source modules; `os.notifications.md`, `os.network.md`, `os.bluetooth.md`, `os.polkit.md`, `os.session.md` |
| SolidJS + QML shell implementing all MUST+SHOULD rows of **M** (2026-03-26), plus `check-features.sh` | `april-webshell-refs/friday-testing/integrated-shell/` (`THIRD-PASS-HANDOFF.md:3`, `DEVELOPER-GUIDE.md:278`) | not sized | the feature-coverage-checker idea: a test that parses **M** and fails if a MUST row has no owner. INFERRED |
| noctalia v5 source, the behavioural reference for every cluster | `june27-cowl-nextsteps/noctalia/` | 243,377 LOC (REPORTED, MA:5) | algorithm borrows via MA Tier A, below |
| Launcher fuzzy weights (MA A10) | MA:180 → noctalia `launcher/app_provider.cpp:22-55` | — | "name×5 + 500 prefix bonus, generic×2, keywords×0.8, categories×0.3, id×1.5, exec×1.0"; usage boost untyped ×0.1 unbounded, typed capped 0.5 |
| Notification daemon core (MA A4) | MA:174 → `dbus/notification/notification_service.cpp`, `notification_filter.cpp`, `notification_history_store.cpp` | — | rules taxonomy showToast/saveHistory/playSound/allowPermanent/allowedUrgencies, first-match-wins; atomic debounced JSON history |
| Hover-pause toast countdown + 1 s duplicate coalescing (MA B6) | MA:197 | — | `notif` toasts |
| MPRIS position projection + art-URL heuristics (MA A9) | MA:179 → `dbus/mpris/mpris_service.cpp:642-681,875-916` | — | media popover progress bar (#116, "love the progress bar") |
| Clipboard history model (MA A5) | MA:175 → `wayland/clipboard_service.cpp` | — | pins exempt from cap; dedup against pinned; skip password-hint MIME |
| Power-command fallback chain (MA A15) | MA:185 | — | "systemctl→loginctl→pm-suspend/zzz→pkexec→run0→sudo, caching the winner" |
| OSD shared host (MA B9) | MA:200 | — | "show OSD without owning the hardware" verb = `osd show` |
| Toggle grammar harvested from the WONT control centre (MA C13) | MA:228 | — | rail glyphs: left = toggle, right = open detail, scroll = cycle |
| Socket robustness (MA B15) | MA:206 | — | reconnect backoff 2 s→30 s, 1 MiB buffer guard; apply to the Sway IPC and herdr readers |
| `cubs msg` exec semantics | S06:376 | — | the command runner: `sh -c`, **reject on nonzero exit**, 30 s timeout, SIGTERM→SIGKILL 5 s grace, 10 MB output cap |
| Error vocabulary | S06:378 | — | NOT_FOUND / NOT_INITIALIZED / NOT_SUPPORTED / PERMISSION_DENIED / INVALID_PARAMS / TIMEOUT / BUSY / CANCELLED / INTERNAL for socket replies |
| `replaySafe` verb tagging | S06:263, :382 | — | tag `cli` verbs; suspend/poweroff/reboot/logout are not replay-safe |
| Session FSM + hook events (historic) | K:133-139; S06:265 | — | only to interpret herdr's states |
| Design-token scale (spacing 4, radii 4/6/10/14, heights 28/32/36/44, z-order dock<bar<dropdown<overlay<modal<toast<tooltip) + 14 anti-patterns | K:299-364; reproduction constants ADD:32 | — | check `theme` against the scale; ignore the superseded colours, opacity and blur |
| Idle-CPU benchmark of a Chromium shell vs DMS | LIN:374 | — | "bar+ccd = 325MB PSS / 1.9% idle CPU / 36 ctxsw/s vs DankMaterialShell-on-quickshell = 396MB / 6.6% / 438 ctxsw/s": an optional baseline to measure the GPUIX shell against |
| Producer D-Bus method signatures (NM, BlueZ, UPower, logind, timedated, PPD) | `CUBS/cade-drafts/m3/*` (REPORTED SH:286-320; not read) | 28 units | look up exact D-Bus methods if a dbus-next adapter needs them |
| Existing dotfiles scripts the shell calls or wraps (MEASURED `ls home/dot_local/bin`) | `volume`, `brightness`, `media`, `audio-route`, `osd`, `screenshot`, `screen-ocr(-area)`, `colorpicker`, `theme`, `theme-prompt`, `pomodoro`, `pomo`, `recording-toggle`, `vpn-status`, `wallpaper`, `sleep-monitors`, `monitors-off`, `touchpad-toggle`, `fzf-nmcli`, `herdr-*`, `sway-workspace`, `claude-capacity` | — | KEEP or REPLACE per §3.1 |

---

## 6. Gaps, conflicts and open questions

**G1. Control centre: CONFLICT.**
- Tom (03-24): "`>> WONT. i do not need a control center. this is not in scope for my project. this
  applies to 268-280`" (M:597).
- BRIEF §3.2 lists `gpuix-shell controls (quick settings)`.
- S06 §B.0 recommended: "keep the per-pod toggle + detail bubble… but DROP the unified control-center
  panel as a single surface — i.e. the 'detail' seam is per-domain bubbles, not one center. Confirm."
  (S06:494-497).

I found no answer from Tom in the files I read. **Recommendation (INFERRED):** build `controls` as
**per-domain popovers** (Wi-Fi, Bluetooth, audio devices, later power profile), opened from rail glyphs
and launcher commands, with no unified dashboard grid. The menus are themselves MUST rows (#133–157),
so this honours both. The orchestrator should record this in `ASSUMPTIONS.md`; I am read-only.

**G2. Clipboard store: CONFLICT.**
- BRIEF §3.4: `wl-paste --watch` + "own store (Vicinae's goes away)".
- Tom: cliphist, "prefer not to create special rust functionality" (M:203); "note however that i use
  cliphist currently" (M:526).
- Gap row (M:634): "COULD. discussed externally. to be revisited later. could convince me to move away
  from cliphist".
- S06 §A#27: "reuse `wl-paste` + `cliphist`; implementing `wl-data-control-v1` directly is
  **rejected**".
- MEASURED: `cliphist` is installed (`home/home.nix:452`), and `home/dot_config/sway/startup.conf:4`
  says "Vicinae owns clipboard history; do not start a second cliphist watcher."

**Recommendation:** when vicinae goes, start `wl-paste --watch cliphist store` (text and image) from
the shell's unit set. The launcher reads `cliphist list` / `cliphist decode`. No new store.

**G3. Settings GUI and onboarding are Tom MUSTs with no surface.** #174 "Dedicated settings GUI —
MUST", #176 "Settings search — MUST" and #265 "Onboarding/setup wizard — MUST but this one will require
specific scoping work". BRIEF §3 names neither. Config is nix-rendered. INFERRED minimum: a launcher
"settings" provider that searches and opens the config fragments and the theme switcher. A real
settings window is LATER, and onboarding still needs Tom's scoping.

**G4. Which outputs carry a rail.** MUST #5 (multi-monitor), #6 (per-screen config) and #12 ("toggle
one but not the other"). The Duo has eDP-1 (top, workspaces 1–9) and eDP-2 (bottom, workspace 10 =
Chrome) (BRIEF:36-38). The notes cannot say whether eDP-2 gets a rail. Default assumption (INFERRED):
rail on the output with workspaces 1–9 only; a per-output config key exists.

**G5. Tailscale "CRUCIAL" (#41, #144) has no named surface in BRIEF.** `vpn-status` exists. INFERRED:
a rail glyph plus a peer popover (`tailscale status --json`), per MA B3 (provider `{status,up,down}`).

**G6. NM SecretAgent (#147 MUST) vs nmcli.** A dbus-next SecretAgent makes the shell own a credential
role. `nmcli --ask` is simpler. Tom marked the agent MUST in March; WPA-Enterprise is only SHOULD
(#134). INFERRED v1: prompt in the wifi menu and pass to `nmcli … password`. Register a SecretAgent
LATER.

**G7. Popups from layer-shell surfaces.** S06:159 and :172: "layer-shell parents reject `xdg_toplevel`
popups, so all menus/tray-menus/CC-detail need" an xdg_positioner popup path. GPUIX has one window per
renderer process (BRIEF §3.2). Unverified whether GPUIX can create popups anchored to a layer surface.
If not, each popover becomes its own overlay process or window. Needs a probe.

**G8. Notification actions are needed even though #69 is COULD.** The unmerged `herdr-attention`
branch drives **mako actions** (BRIEF:79). Replacing mako without `ActionInvoked` support would regress
it.

**G9. The `osd` script talks to mako.** MEASURED: `osd` uses `notify-send -r` against mako's single
slot (`home/dot_local/bin/osd:8-12`). The gpuix `notif` daemon must either recognise those replaceable
OSD notifications and route them to the `osd` window, or `osd` must call `gpuix-shell osd show`.
Otherwise volume keys produce toasts.

**G10. Reversed rulings (§2.6).** Any agent reading **M** or **K** must not reintroduce blur, glass,
0.85 opacity, `#5B9DFF`, SF fonts, a "no light theme" rule or niri. BRIEF wins.

**G11. Annotation voice (§2.1 caveat).** Six rows may carry agent-written clauses. The #180 annotation
is cut off mid-sentence in the source ("`> SHOULD, in fact this is a `", M:412).

**G12. Touch.** Gap row "Touch/gesture support — COULD but much later… icebox maximally" (M:654). The
Zenbook Duo is the physical seat (AGENTS.md). INFERRED, unverified: its panels are touchscreens, so
touch on the rail may matter sooner than March assumed.

**G13. Things these notes do not contain.**
- herdr itself: the 9-slot cap, the eDP-1/eDP-2 split and the status glyphs come from BRIEF, not
  from the notes.
- Any Navidrome, music or OpenUI requirement: BRIEF §5 only.
- Any vicinae inventory beyond "a qt launcher called vicinae that tried to reproduce raycast; i could
  revisit it" (M:238).
- Phone integration has intent but no design: #252 "android phone notification is extremely
  desirable" and `CUBS/extra-functionality.md:5-6`.

**G14. Not read.** `CUBS/cade-drafts/**`, `CUBS/build-flag-investigation/*`, 28 `SECTION-*.md`
appendices, `CADE-MASTER.md`, `CADE-CONTEXT.md`, and the other BRIEF §5 candidates (`pre-sync/`,
`references/continuity/…/frontend/*`, `…/sept7/scopes/agency-chromium.md`). Other wave-1b readers may
cover those. No ruling quoted here depends on them.

**G15. Fedora-era items need NixOS meanings.**
- #47/#248 update count: rpm-ostree in March; on NixOS perhaps "flake.lock age" or "pending switch".
- #251/#263 Docker/Podman/quadlets: on NixOS, perhaps systemd units.

All unscoped.

---

## 7. What I did and did not do

- **Read in full:**
  - every file in the task list: `CUBS/{intro,extra-functionality,CONCEPTUAL-PILLARS,SHELL-SHAPE-DECISION,M0-BUILD-PLAN,SESSION-HANDOFF,HANDOFF-views-shell-to-cade-drafts}.md`, `cubs-steelman/*.md` (all 7, including the 605-line 06), `LINEAGE.md`, `LINEAGE-ADDENDUM-jun30.md`, `LANDING-LEDGER.md`
  - the siblings **M** (all 701 lines), **K** (all 507), `CUBS/M0-SPIKE-RESULT.md`
- **Read in part:**
  - **U**: :1-40 and :42-407
  - **MA**: :1-40 and :113-345
  - `CADE-AUDIT-TABLES.md` §4
  - the head of `ccd/app.js`
- **Ran the required grep:** `grep -ril "ultimate desktop shell\|deeply annotated\|priorit"` over
  `CUBS/`, `cubs-steelman/` and the 1h26 top-level files, plus a repo-wide search for "ultimate desktop
  shell / ultimate shell / deeply annotated":
  - CUBS hits are technical "priority" uses in the C++ drafts.
  - Top-level hits outside **K** and LINEAGE concern job scheduling.
  - The repo-wide search found **U** and its digest (`CADE/cade-june11-reconciliation/digests/substrate-research-digest.md:281`).
- **Checked in this worktree** (MEASURED): `home/dot_local/bin` listing, `home/dot_config/sway/binds.conf`
  binds, `vpn-status` header, `screen-ocr` endpoint, `osd` header, cliphist references, and the absence
  of any polkit agent.
- **Wrote:** this file only. The verbatim tables in §2.1, §2.2, §2.3, §3.1 and §3.2 were generated from
  the source files by a one-off script, to keep Tom's text byte-exact. The disposition and surface
  columns are my judgement (INFERRED).
- **Did not:** run any test, touch `/home/tom/mecattaf/dotfiles`, touch Sway, herdr or systemd, or edit
  `ASSUMPTIONS.md`.
