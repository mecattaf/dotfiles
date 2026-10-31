# 30 — Notes repo: the frontend lineage, the annotated feature matrix, Omarchy webapps, DMS productivity

Reader note for the gpuix-shell overnight build (2026-10-20/21). Read-only pass over `/home/tom/notes`.
Nothing was built or run. Every Tom quote is verbatim (typos kept) with a date and a `file:line`
pointer. Labels: **MEASURED** (a first-party number run on Tom's hardware, method written down),
**REPORTED** (a document says so; not re-verified here), **INFERRED** (my reading). Paths are
relative to `/home/tom/notes/references/` unless absolute. `FE/` =
`continuity/2026-09-27-desk/2026-09-27/frontend/`. `AM` = the annotated feature matrix (§1.2).

Surface names used in the mapping columns are BRIEF §3.2's: **rail** (`gpuix-shell rail`),
**notifications** (daemon + toasts + OSD window), **launcher**, **switcher** (Mod+i), **controls**
(quick settings), **files** (Pinax-like), **power**, **ask** (OpenUI). "**herdr**" means the role is
now taken by herdr state read through `herdr api snapshot` / `herdr workspace list` (BRIEF §1, §3.4).
"**Sway**" means the compositor keeps the job (bind, IPC, scratchpad). "**script**" means an existing
`home/dot_local/bin/*` script keeps the backend and the shell only wraps it (BRIEF §2 row "Scripts
the shell replaces or wraps").

---

## 1. What the sources are

### 1.1 The "ultimate desktop shell" and the "deeply annotated priorities list": which files Tom means

Tom (BRIEF §5, 2026-10-20 23:20): "as early as 6 months ago did i describe the 'ultimate desktop
shell' with at one time a very detailed set of rulings with deeply annotated priorities list". Six
months before 2026-10-20 is late April 2026. Three artefacts fit, and they are different things:

| Candidate | Date | Author | What it is | Fit |
|---|---|---|---|---|
| `devlogs/1h26/april-webshell-refs/ANNOTATED-feature-matrix.md` (701 lines) | March 2026 (header: "Exhaustive Feature Matrix -- March 2026"; `:7` "@claude i added my annotations with `>` lines") | agent table, **Tom's `>` marks on every row** | 280 numbered features from 16 Quickshell shells (DMS, noctalia, Ambxst, caelestia, eqsh, nucleus, whisker, tpaau, sshell, ChromeX, dart, Kriti, HyprQuick, binarylinuxxdots, snes19xx, niri-panel) plus piri/nirvana; 16 gap rows; each row carries MUST / SHOULD / COULD / WONT / DONT and a sentence of Tom's reasoning | **This is the "deeply annotated priorities list"** (INFERRED, strongest fit: it is the only file in the repo where Tom marks priorities row by row; the Oct 1 resurface calls it "The backbone", `archive/2026-10-06-wm-scoping/notes3/resurface-noctalia-cade.md:11`). A byte-identical copy sits at `devlogs/1h26/may26/cade/cowl-secondpass/docs/history/ANNOTATED-feature-matrix.md` (REPORTED, same line). |
| `devlogs/1h26/annotated-kmux-feature-list-v0.md` (507 lines) | 2026-03-26 (`:3`) | agent list, **Tom's `>` answers** on the stack, principles and agent-runtime questions | "kmux + QuickShellX Feature List v0": locked stack A1–A15, architecture principles B1–B15, agent runtime C1–C8, v0.1 scope, session FSM, CCD daemon, sidebar UX L1–L5, bar widget M, the full design-token set N, Quickshell surfaces O, competitor patterns P/Q | The **rulings** half: this is where "No CSS blur ever `> yes`", "one accent", "50ms for everything", "dark-only" and the sidebar/agent-status design were ruled. The sidebar here is the ancestor of the herdr rail. |
| `devlogs/1h26/CADE/cade-june11-idealized/research/ultimate-shell-feature-set.md` (407 lines) + `design/00-IDEAL-TARGET.md` (186 lines) | 2026-06-11 | agent (Claude Fable 5 orchestrator), from Tom's reframe | Literally titled "The Ultimate Desktop Shell: Feature Taxonomy": 17 shell domains, each with the D-Bus/service it binds, READ/WRITE/secret class, and the DMS `dms ipc call` verb surface; the IDEAL-TARGET fixes 56 capabilities (38 WM + 17 shell + the JSONL spine) with a four-tag protocol taxonomy | The phrase "ultimate desktop shell" is this file's title. Tom's own words that produced it: "the world's most feature-complete window manager PLUS DankMaterialShell" (`00-VERDICT.md:3-5`, REPORTED as Tom's reframe). Its protocol-verb thinking is the direct ancestor of BRIEF §3.2's `gpuix-shell` CLI over a Unix socket. |

So: the **priorities list** is AM (March), the **rulings** are the kmux v0 answers (26 March) plus
AM's per-row sentences, and the **"ultimate desktop shell"** write-up is the June 11 taxonomy that
turned the same wish into protocol verbs. All three are reproduced in full fidelity in §2–§3 below.

### 1.2 The assigned files, with what each contributes

| File | Lines | Date | Voice | Contributes to this note |
|---|---|---|---|---|
| `FE/01-spring-2026-webshell-compositor-lineage.md` | 511 | 2026-09-27 | agent reader | Dec 2025–May 2026 timeline; Tom's March rulings (50ms, "no special coding language", "fastest shell in the world"); the Linear sync-engine lore; render-discipline checklist; dead ends (QtWebEngine bridge, WebKitGTK, SolidJS v2, OpenWork, CADE) |
| `FE/02-summer-2026-cade-cubs-lineage.md` | 124 | 2026-09-27 | agent reader | COWL/CADE/CUBS; the June 27 cowl benchmarks (MEASURED); the Raycast-style launcher that shipped; "kitty stays native" ruling; "shell is a webapp" reversed to Views |
| `FE/03-aug-sep-2026-cfos-kumo-lineage.md` | 209 | 2026-09-27 | agent reader | Tom's Sept 22–27 rulings (cfos is the front end for webapps; utilities on Workers); the Kumo 42/9/62/22 coverage; the 22 missing components |
| `FE/04-lit-chapter-cubs-chromium.md` | 119 | 2026-09-27 | agent reader | The Lit chapter (rejected April 4 as a shell kernel; reopened June 30 for CUBS config pages); the component-model mixins |
| `FE/10-LINEAGE-fastest-webapp-frontend.md` | 523 | 2026-09-27 | agent consolidator | **The best single chronology of Tom's own words** (§1, all re-grepped); the "what survives" tables; 19 testable principles; the reusable-artefact inventory |
| `FE/30-CURVEBALL-electron-osr-and-the-gpui-kit-class.md` | 324 | 2026-09-27 | agent | What "a kit of the gpui-kit class" is; the ownership ladder (rung 0 web page … rung 5 compositor); views-shell is content, not a kit |
| `FE/32-curveball-notes-osr-cowl-proof-gpui-views-shell.md` | 265 | 2026-09-27 | agent | The June 27 COWL workspace-switcher proof (MEASURED numbers); GPUI's history in the notes; Tom's June 30 "lego" quotes |
| `FE/00-RULING-2026-09-27-the-separation.md`, `FE/00b-RULING-2026-09-27-the-token-kernel.md` (siblings the chapters name) | 45 + 38 | 2026-09-27 | **Tom verbatim** | The separation (Views for OSD/notifications/bar/launcher/switcher/clipboard; webapps on cfos); "web components first, then Views"; the design-token kernel |
| `continuity/2026-09-07-sept7-working/sept7/scopes/agency-chromium.md` | 243 | 2026-09-06 | agent scope card | CUBS = "Chromium Unified Browser and Shell"; Tom's rank ("capstone", "the moonshot still"); the theming kit; "No CSS blur ever"; SF Pro superseded; the sequencing ruling |
| `continuity/2026-09-07-sept7-working/sept7/PROJECT-SCOPES-2026-09-06.md` | 4121 | 2026-09-06 | agent | Has **no desktop-shell card**; the shell appears only inside card 10 (agency-chromium, lines 2576–2900) and card 11 (omarchy-fleet, lines 2921–3120: the friends' laptops, Omarchy Quattro, the fonts ruling) |
| `continuity/2026-09-25-desk/2026-09-27/browser-tab-bankrupcy/cubs-alternatives.md` | 58 | 2026-09-25 | **Tom's own notes** | helium/cmux as a base; "the next frontier is the compositor"; "we can get by with just a 'workspace' concept"; clui-cc "made me want claude on the desktop"; starling/denial/frame shells |
| `…/browser-tab-bankrupcy/watchlist-unixporn.md` (sibling) | ~104 | 2026-09-25/26 | **Tom's own notes** | Tacit ("stunning… getting closer to exactly i want"), GPUI kit table, "building that ui kit for Views is exactly the missing part" |
| `…/browser-tab-bankrupcy/CUBS-performance.md` (sibling) | 78 | 2026-09-25 | Tom + pasted chat | Chromium vs Chrome PGO; ChatGPT desktop is 1.48 GB of Chromium |
| `devlogs/1h26/april-tmp/omarchy-manual-webapps.md` | 102 | April 2026 | **Tom's note + pasted Omarchy manual + DHH launch post** | Omarchy's web-app model (Super+Alt+Space install, frameless window, per-app hotkeys); Tom: "we use niri not hyprland, kitty term, and all the rest is cowl shell. more customizable. deeper ownership of webapps." |
| `devlogs/1h26/dms-productivity/final-shell-function.md` | 24 | ~2025-11 (Tom's "DMS productivity" era) | **Tom's list** | The eight-item wishlist (tailscale status bottom right, clipboard with pictures, emoji picker, pomodoro, OCR on select, OSK, hotkey visualisation, "mod k … new launcher: experimenting w vicinae"); Baikal/khal/khard as the calendar backend |
| `devlogs/1h26/dms-productivity/productivity-dms.md` | 2120 | same era | pasted Claude chat | Tom's DMS calendar plugin had no backend; Baikal (CalDAV) chosen over khal; a full Go CalDAV service + QML plugin handoff |
| `devlogs/1h26/dms-productivity/oldschool-cli-productivity.md` | 1003 | same era | pasted ChatGPT chat | taskwarrior/timewarrior/Baikal/khal/khard/vdirsyncer; Backlog.md MCP; **Tom's Sunsama paragraph** ("i count on the actual device's shell not the browser to capture those flows"); Doom Emacs "serves as a guiding light"; org-habit |

Sibling and grep-found files also read: `devlogs/1h26/CADE/cade-june11-idealized/00-VERDICT.md`,
`archive/2026-10-06-wm-scoping/{README.md,DECISION-MEMO.md}`,
`archive/2026-10-06-wm-scoping/notes3/{resurface-noctalia-cade.md,resurface-frontend-and-fleet.md,resurface-webshell-final-shape.md (head),omarchy-plugins.md}`,
`devlogs/1h26/april-webshell-refs/transient-outputs/RETRIEVED-previous-shell-scoping.md`,
`devlogs/1h26/CUBS/{intro.md,extra-functionality.md}`, `devlogs/1h26/june27-cowl-nextsteps/REPORT-2026-06-27.md` (head),
`devlogs/1h26/pre-sync/{SOLIDJS-THEME-SYSTEM.md (head),FINAL-LINUX-DESIGN.md}`,
`devlogs/1h26/CADE/cade-june11-reconciliation/02-DECISIONS.md` (grep), `journal/2026/10/06/README.md`.

`grep -ril "ultimate desktop shell\|deeply annotated\|priorit"` over the named directories returned
the files above plus noise (sodimo, yugioh, knowledge). The only literal "ultimate desktop shell"
hits are the June 11 taxonomy and `archive/2026-10-06-wm-scoping/notes3/resurface-noctalia-cade.md`;
"deeply annotated" matches nothing in the shell corpus (the phrase is Tom's from tonight).

### 1.3 The eras in one table (so the rulings below can be dated)

| Era | Dates | Shape Tom was building | Status now |
|---|---|---|---|
| E1 WebShell | Dec 2025 – Mar 2026 | QuickshellX (Qt + QtWebEngine) hosting SolidJS; niri; kitty; shpool | killed at the fork decision (`FE/02:13`) |
| E2 COWL | 27 Mar – Jun 2026 | purpose-built Chromium embedder; TS/HTML shell on wlr-layer-shell under niri; `os.*` Mojo bridge | measured 2026-06-27, then superseded |
| E3 CADE | May – 11 Jun 2026 | "the browser IS the compositor"; 22-domain SCP protocol | vetoed into CUBS; protocol dropped |
| E4 CUBS / views-shell | 28 Jun – Jul 2026 | Chromium Views C++ shell lifting ash; "Views outside, web inside" | frozen ("the moonshot still", 2026-08-31) |
| E5 cfos | Aug – Sep 2026 | every webapp front end on Cloudflare Workers (cloudflare-os) | live ruling for webapps (out of this shell's scope by BRIEF §3.8) |
| E6 scroll + Views | 27 Sep – 7 Oct 2026 | scroll (sway fork) + a Views layer-shell client; otto trial | scroll kept 10-07; otto dropped |
| E7 Hyprland → Sway + GPUIX | 13 – 20 Oct 2026 | GPUIX Solid shell on Hyprland (74 min), then Sway | **tonight's shape** (BRIEF §1) |

---

## 2. Verbatim Tom rulings about the desktop shell

Chronological. Only Tom's own words; agent paraphrases are marked. Each ends with where it stands
tonight (BRIEF).

### 2.1 November 2025 – the DMS productivity era

- Tom's wishlist, undated file (`devlogs/1h26/dms-productivity/final-shell-function.md:1-8`):
  > "- tailscale status in bottom right / - clipboard manager with picture support / - emoji picker / - augment current pomodoro / - ocr on text select / - on screen keyboard / - hotkeys visualizations / - mod k leads to something different, new launcher: experimenting w vicinae"
  and `:12-23`: "It is now clear that we want to achieve a more comprehensively integrated desktop environment that can interface with existing / Baikal provides: khal khard cardav; which is good enough for: calendar events (includes todo s), contact lists (leading to birthdays also), todo list items / also integrated with the pomodoro timer / investigate compatibility with taskwarrior and timewarrior / could also use backlog for the detailed task descriptions. goal is to arrive to a unified service"
  → Still the shape of tonight's launcher-provider list. Vicinae is the thing being replaced now (BRIEF §1). Calendar/contacts/todo are **not** this shell's (BRIEF §3.8 boundary) but the pomodoro script exists.
- On Sunsama (`oldschool-cli-productivity.md:161-162`, ChatGPT chat):
  > "i had previously used the productivity tool Sunsama and found it to be great. but it s a webapp; and i prefer local + llm-driven parts for information inputs. also, i count on the actual device's shell not the browser to capture those flows more full."
  and `:265`: "it would be amazing to have alll of this functinality wrapped into a better model, a more responsive desktop os that captures my todo list, makes time on my (local) calendar, sets pomodoro timers to track work; all the while many backend tools are working together. and the best part - i get a dedicated llm to take care of the logistics (like 'update that project' this issommething i say to my mcp enabled llm)"
  → the "ask" surface (OpenUI) and herdr are the 2026 answer to "a dedicated llm to take care of the logistics".
- On Emacs (`:132-133`): "So clearly emacs tried to remplace everything. But i m glad i didnt imvest in it. It does serve as a guiding light. / What can we learn from emacs in a llm tool enabled, local first agentic world"
- On DMS's calendar (`productivity-dms.md:123-124`): "thing is: enableCalendarEvents = true; # Calendar integration (khal) that s the only part that shows me that maybe it exists. but there is nothing more explained. perhaps a good solution would be to leverage a locally hosted baikal instance?"

### 2.2 16 March 2026 – the responsivity rulings (`devlogs/1h26/pre-sync/quickshellX-solidjs2-discussion.md`)

- `:1447`: "50ms? I remember that for some reason linear web app had the fastest reactivity to my clicks for some reason I'm really not sure why explore"
- `:1511`: "50ms is what it advertized on linear s landing page as of jan 2026. You got it wrong. Clarofy. You also pointed me to https://dasroot.net/posts/2025/12/local-first-software-offline-applications/ which corresponds to what we're doing here we are building offline web apps"
- `:1541-1542`: "So one more clarification that I would like to make here. I am trying to build the world's fastest most responsive desktop shell / That means I want snappiness everywhere. You deliberately introduced later slower ones for the animations, whereas actually that was exactly off. I want the most responsive"
- `:417`: "We definitely don't need figma as a tool or as a dependency. ... when I mention linear raycast and some others, it seems like you immediately get it."
  → Tonight BRIEF §1 says "performance is not really the thing i m looking for here". The *motion* rule survives (one 50 ms token, §4); the "fastest shell in the world" ambition does not bind the build.

### 2.3 23–30 March 2026 – web tech, references, the first shell baseline

- 2026-03-23 (`devlogs/1h26/pre-sync/sync-march30/frontends-reference-goldmine.md:157-158`): "This chat is a goldmine if high quality references. Amything else? Palot blew my mind. pi generative ui with glimpse is also incredible in its novelty. Also the ccui thing: github.com/lcoutodemos/clui-cc. This is approaching full Claude imagine"
- 2026-03-26 (`…/conv-chromium-fork-decision/chat.md:175`): "The whole thing here is that I do not want to be using a special coding language to build the front end."
- 2026-03-26 (`chat.md:402`): "Remember my goal is to get linear.app webapp level responsivity 50ms click all the way through and writing ny webapps supposedly on solidjs but for every part of the shell"
- 2026-03-26 (`devlogs/1h26/april-webshell-refs/REVOLUTION/first-chat.md:191`): "I arrived at the conclusion that solid JS was the best and fastest way to use web components to have a highly reactive layer shell 50 milliseconds something that feels like linear.app I guess with possibly even faster because it's done locally HTML cssjs. ... I might also eventually start rebuilding entire desktop web apps that I had previously used in the past, like superhuman for male and the calendar or let's say a custom Trello board that would somehow be very integrated with my system."
- `first-chat.md:194`: "Even the framework doesn't matter - I just need HTML/CSS/JS in a browser engine"
- `first-chat.md:227,229`: "I really really don't like that you went through with the gtk recommendation. It's really such an inferior alternative." / "I'm wanting to build the fastest shell in the world and it despite using web technologies"
- 2026-03-27 (`chat.md:735-736`): "I dont like the two-mode structure kf morphdom / Only ai generated code. Possibly even html css raw. But incorporate the linear learnings."
- 2026-03-30 (`devlogs/1h26/may26/root-archive/monday-claudeweb-chat.md:251`): "notion's generational moment is the slash operator. ... for years i used a minimal shell with fzf waybar mako nitifications. keyboad shortcuts also."
- `monday-claudeweb-chat.md:401`: "linear didn t win with one render, or one sentence they won because it was an incredible product all around. that listened to users. however, this is what the nucleus was."
  → "no special coding language" is why GPUI (Rust) was removed in March (`FE/32:20`); tonight GPUIX is TypeScript, so the ruling is satisfied, not violated. "fzf waybar mako" names exactly the three things BRIEF §1 replaces.

### 2.4 26 March 2026 – the kmux v0 answers (`devlogs/1h26/annotated-kmux-feature-list-v0.md`, every `>` line)

**A. Locked stack** (`:10-39`): A1 Kitty one window = one OS window "> must" · A2 Niri "> must" · A3 shpool "> must" · A4 QuickshellX "> must" · A5 SolidJS "> must, we will use v1" · A6 Kobalte "> this is a new addition that will require further work when we go down the line" · A7 bun+vite "> must" · A8 fgp-browser "> should, this is something that will be handled later entirely" · A9 QtWebEngine CDP bridge "> no this is wrong. discard this information" · A10 Neovim "> should, to be done later" · A11 Rust daemon "> this is already adopted decision" · A12 Python glue "> no python, thinking all rust" · A13 SQLite/FTS5 "> should, to be done later" · A14 SF Pro/SF Mono "> MUST and this is not implemented now" · A15 Phosphor or Lucide icons "> should, start with lucide".
  → A1 survives as "one herdr workspace = one kitty projector window = one Sway workspace" (BRIEF §1). A2 is dead (niri → Sway). A3 shpool is dead (herdr). A14 is superseded by the Anthropic fonts (`sept7/scopes/agency-chromium.md:143`: "SF Pro / SF Mono 'MUST' … → stock Views/Chromium UI font"; BRIEF: Anthropic Sans/Serif/Mono).

**B. Architecture principles** (`:41-72`):
- B1 "One kitty window = one OS window. No splits, no tabs, no multiplexer inside kitty." "> yes"
- B2 "No TUI anywhere." "> technically, no TUI except for pi-mono or pi-agent. but yes no dashboard in terminal"
- B3 "Status from structured data (JSONL + hooks), not screen scraping." "> yes, in fact must be discussed in depth becaues the way it is now with claude code, in the existing implementation of my focused window indicator of the bar of quickshellx webshell is sufficient, seems like claude code does output the needed titles"
- B4 always-shpool "> yes!" · B5 thin client/server "> should; but for now it s all in server mode (ie local is server) so no need for htis logic now."
- B6 "Composition over monolith. kitty remote control + niri msg + shpool > custom daemon." "> yes"
- B7 "The filesystem IS the API. JSONL + semaphore locks + inotify > RPC daemons." "> yes"
- B8 "All agents run in interactive mode. One mode. No headless RPC for agents." "> yes"
- B9 "No CSS blur anywhere ever. All blur is compositor-driven (niri blur 3 passes offset 3.7)." "> yes, niri implementation of blur to be noted somewhree externally to its own md file because we re still waiting on upstream for that (anyday now)"
- B10 "Dark-first: surfaces are solid hex fills, compositor sets window opacity 0.85 for wallpaper bleed." "> yes"
- B11 "One accent color: `#5B9DFF`. No secondary/tertiary. Monochrome discipline." "> yes for now"
- B12 "One animation duration: 50ms for everything. No tiered system. `cubic-bezier(0.16, 1, 0.3, 1)`." "> yes for now"
- B13 "Animate ONLY opacity and transform. Never background, border, shadow, layout." "> yes for nw"
- B14 "No light theme. No theme toggle. Dark-only single-accent." "> yes for now"
- B15 shpool as a systemd user service "> yes and this is already impelmented on my system"
  → B3, B6, B7, B8 are exactly herdr's model today (structured snapshots, composition over a custom daemon, interactive agents). B9/B10 become "flat and opaque, no blur, wallpaper #000000" (BRIEF §1): the blur half is gone, the solid-hex half stays. B11 is now the Claude accent per theme. B12/B13 stand. B14 is superseded by the three themes (noir, claude-dark, claude-light).

**C. Primary agent runtime** (`:74-91`): C1 Claude Code first "> yes" · C2 "> no" · C3 "> well technically both wil lbe installed on day one but we re startign w claude" · C4 "> os.claude as the prototype. os.agent is reserved to when we 'graduate' from claude code and then we move on to os.agent for pi" · C5 "> yes" · C6 "> ok so we start w claude specific" · C7 "> start w claude" · C8 "> start w claude."
  → the whole `os.claude` / CCD namespace is what herdr replaced (BRIEF §1 "herdr is 'the centerpiece of dotfiles'").

**J2 shpool fork** (`:200`): "> ABANDONED COMPLETELY". **L4 status-dot colours** (`:269`): "> acceptable for now, to be unified later of course" → unified tonight into herdr's five glyphs (◉ ◐ ● ✓ ○). **§3 Plugin Model** (AM `:660`): "> to be reevaluated later".

### 2.5 March 2026 – the general rulings inside the annotated matrix (per-row marks are in §3.1)

- Launcher north star (AM `:238`): ">>> GENERAL NOTE on 1.4 LAUNCHER: my shell's launcher in its ideal form will be visual equivalent to macos' RAYCAST. i found it to be the most powerful feature by far. there was a qt launcher called vicinae that tried to reproduce raycast; i could revisit it. but dankmaterialshell's launcher does a great job at getting close to it. we start with the dms implementation as reference and then decide if we want to go beyond"
- Workspace bar placement (#27, `:75`): "MUST, in fact in my concepts i had the workspace switcher as a separate left horizontal bar, whereas all the other modules exist in the top bar." → BRIEF: "a left bar with workspace switcher that remplaces waybar", "no top bar on the Linux head". The left bar won; the top bar died.
- One toggle, one bar (#20, `:56`): "MUST, and very important to have funcioning well with niri; in fact one ipc toggle should control only one bar (in case there are multiple bars)"
- i18n (#101, `:233`): "DONT i explicitly reject i18n support for now. this is MY shell i'm not trying to reinvent the linux shell for the entire world"
- Compositor (#158, `:104`): "WONT. We are building this shell for niri ONLY. No multi-compositor support." → inverted: Sway only (BRIEF §1). The *principle* "one compositor only" survives.
- Theming (#181, `:155`; #186, `:165`): "WONT whatsoever: no material or material you (i don't like it); no matugen whatsoever as I explained we do not have a strict colorscheme we follow a standard minimal css token" / "WONT. this is also a clear design decision that i take from the start: i do not need help managing my gtk or qt theme etc. that is what dotfiles are for. this also complements my 'NO MATUGEN' decision"
- OLED (#185, `:163`): "MUST. OLED mode ie make the black colors #000000 is something that i do by default. so you could say i do oled compatible color mgmt by default. however if by oled you mean something like 'a special setting that reduces oled monitor burn-in somehow' then WONT. i can manage my oled screens myself" → noir default, wallpaper #000000 (BRIEF).
- Plugins and hierarchy (#200, `:193`): "COULD but we will do that much later down the line. … in my case it s a custom shell written for one person, so the utilities/plugins i need are configured from the dotfiles themselves. no need to 'enable' plugins or browse through them. to be precise, in my world, an ephemeral pomodoro widget has the same place as the main launcher (there is no hierarchy)"
- Quick settings (`:597`): ">> WONT. i do not need a control center. this is not in scope for my project. this applies to 268-280" → **superseded**: BRIEF §3.2 names `gpuix-shell controls` (quick settings) and Tom asked for "wifi menu, or bluetooth pairing menu; etc." The Oct 1 resurface already records "CADE/CUBS later lifted it anyway … The March WONT was never re-ratified" (`resurface-noctalia-cade.md:294`).
- Idle suite (`:508`): "> COULD the entire idle management suite is not so important for me, i prefer to icebox for now. this applies to 225-232 inclusive"
- Lockscreen (#203, `:463`): "COULD this functionality is quite secondary. i bypass lockscreen by default on reboot (already implemented in my os with greetd automation); and when i need to rest my desktop i do `systemctl sleep`. … icebox for now"
- Polkit (#216, `:230`): "MUST. i do not like the classic gtk greeter (that gets used now in the current state of my dotfiles). we are writting a very nice, very well-done uniform design system. dms and others have proven to me that polkit is implemented and easy to do with regular quickshell. this is low-hanging fruit"
- Power menu (#218, `:234`): "MUST and in fact i want to mention that i like the new DMS powermenu the most with the ability to scroll/select through a list AND press and hold a given key to get the desired action"
- Clipboard (#233, `:526`): "MUST the clipboard manager is very important to me. note however that i use cliphist currently. i discuss the specifics of my implementation separately"; (#86, `:203`): "MUST, it's important for me to have the clipboard history shown in the same aesthetic as the launcher; also making sure that we are displaying images (i use cliphist, prefer not to create special rust functionality as i found DMS reinventing the wheel with their clipboard implementation)" → BRIEF §3.4 says "clipboard history via `wl-paste --watch` + own store (Vicinae's goes away)": that is the "could convince me to move away from cliphist" case (AM `:634`); note the tension.
- OCR (#238, `:536`): "SHOULD but with a twist. first off i want to use the existing niri functionality to clip screen … the second twist is that i do NOT want the ocr to be handled by tesseract: it will be handled with qwen 3.5 opensource multimodal llm model … Backend: HTTP call to llama.cpp server running in a local toolbox container." → today `screen-ocr-area` → Halogen (dotfiles) does exactly this.
- Calendar grid (#240, `:540`): "WONT. the calendar month grid display will be handled by a bespoke, fullscreen, on-brand calendar app FAR later down the line. i do not need such utility in my shell. they're hacky anyway, calendar grids ar not straightforward in qml.. but trivial with web technologies"
- Terminal sessions (#241, `:544`): "MUST but i use shpool for terminal sessions, not tmux nor zellij. … requires further specialized scoping" → herdr.
- Pomodoro (#250, `:562`): "SHOULD the pomodoro timer concept is very valuable and i have my own approach for it. so we use the existing references and build on top of it. this will be the first feature i release AFTER base webshell"
- Containers (#251, `:564`): "SHOULD Container management is very desirable on my system"; (#263, `:588`): "this reminds me that there was a good DMS plugin for viewing dockerfiles, which i considered extending to see running systemd services and quadlets"
- KDE Connect (#252, `:566`): "SHOULD; this doesn't have to be done right away but the KDE connect is extremely desirable. … i wish to make it clear that 'android phone notification' is extremely desirable"
- Tailscale (#41, `:103`): "MUST. it is CRUCIAL for me to know if i'm connected to tailscale, and possibly to know what other devices are connected on my tailscale network. i am aware that there are 2+ different tailscale DMS extensions, happy to bring them over in due time"; (#144, `:330`): "MUST with special focus on tailscale"
- Privacy indicators (#39, `:99`): "MUST, and i'll likely develop a specific widget around it"; (#60, `:141`): "MUST, i will use that"
- Notifications (#65, `:156`): "MUST this one is non-negociable"; (#77, `:180`): "MUST, dms hints overlay philosophy is very desirable"; (#82, `:190`): "MUST, to avoid dangerous or strange behavior on my system"
- OSD (#122, `:281`): "MUST. an OSD is very imprtant to have. I found the eqsh one to be very nice (which i m using right now)"; brightness (#123, `:283`): "MUST but with a small caveat: i really don't care if the brightness is managed by my shell. … doesn't really have to be fully integrated with the shell if it adds work"
- AI (#247, `:556`): "COULD but much later down the line. i do not need an ai integration the way it is done in the reference qml shells. i have some ideas here so not marking this as won't" → herdr + ask.
- Screenshots (#234, `:528`): "WONT because existing niri window manager is sufficient"; colour picker (#237, `:534`): "MUST but Color picker currently since i use niri window manager the screenshot tool exists and is sufficient"
- Fonts (#187, `:167`): "SHOULD but the default font, like eqsh, is sanfrancisco mono." (superseded: Anthropic fonts)
- Transparency (#189, `:171`): "SHOULD. Compositor (niri) owns blur via ext-background-effect-v1; CSS just sets background-color alpha. … Trivial once design tokens exist." (superseded: no blur, opaque)
- Wallpaper (#191, `:175`): "SHOULD because we are indeed controlling the monitor from quickshell side of things (not niri config)"; parallax (#194, `:181`): "WONT i explicltly don't need parallax because it makes me dizzy" (superseded: wallpaper is #000000 solid)
- Animations (#188, `:169`): "WONT. not sure if the shell has anything to do with animation speeds at all, and even if it does i would make it none/short for snappiest experience"
- Settings GUI (#174, `:141`) "MUST"; search (#176) "MUST"; validation (#178, `:149`): "SHOULD, but has to be something that is not hardcoded - it has to validate the config schema programaticaly"; onboarding (#265, `:594`): "MUST but this one will require specific scoping work before i configure it"
- Scratchpads (#168/#169, `:384-387`): "SHOULD this is piri functionality so would like to have it baked in" → Sway scratchpad is native (piri retired).
- Niri config (#160, `:365`): "COULD, … prefer that the niri kdl config remain in chezmoi-backed dotfiles and not in the purview of the shell" → same for Sway config tonight (the shell reads, dotfiles write).

### 2.6 April 2026 – Omarchy

- `devlogs/1h26/april-tmp/omarchy-manual-webapps.md:1-2`: "omarchy is an oss project, that is an arch linux with all preistalled wayland suite. it runs hyprland and many shell tools. customizabiilty is world class. the ONLY piece of marketing is that two shortcuts defualt to the DHHs hosted service hey.com for email and calendar. specifically things we could offer for agency. / and by the way, we use niri not hyprland, kitty term, and all the rest is cowl shell. more customizable. deeper ownership of webapps."
  → "deeper ownership of webapps" is the thread that became the 11 PWA desktop entries and the Chrome-on-workspace-10 rule.

### 2.7 June 2026 – CADE / CUBS

- 2026-06-09 (`devlogs/1h26/CADE/june9-cade-stuff/main-chat.md:88`): "This must be handled entirely by CADE. The end user never writes c++, only linear-style webapps that are localhosted"
- 2026-06-10 veto (REPORTED, `…/cade-june10/07-corpus/00-KNOWLEDGE-LEDGER.md:780-783`): "Tom VETOED this 2026-06-10 (keep-Ash compositor LOCKED)" — against shipping a layer-shell client first.
- 2026-06-11 (`cade-june11-reconciliation/02-DECISIONS.md:269-270`, REPORTED): "D20. Network + Bluetooth: v1 scope — TOM RULED: critical to v1"; `:299-303` "D24 … TOM RATIFIED (//dbus; 1000 LOC not a concern)".
- 2026-06-16 (`devlogs/1h26/CUBS/intro.md:1`): "on june 16 i made the decision to 'revive' cowl rather than build cade."
- CUBS extra wishes (`devlogs/1h26/CUBS/extra-functionality.md:1-15`): "we will indeed be bringing over all the functionality we can from previous cade investigation (including the full annotation chapter) / … inspiration for connecting to android phone: …noctalia-shell-androidconnect-plugin / inspiration for an events/reminders/calendar cli: …dankcalendar / could also have something for emails / sasori-style smtp is interesting. / the pattern here is that we can have our own, somewhat native, format for scheduling tasks and supervising them."
- 2026-06-28 (`devlogs/1h26/cubs-steelman/CHAT-LOG.md:130-138`): "a more views-native (c++) approach to the shell building, making this project much closer conceptually to what noctalia-shell did; we actually experimented with that yesterday as well in ~/mecattaf/views-shell. this is a real split in the road" / "in my world i have a feeling that we can 'make views c++ into the swift that macos gives'"
- 2026-06-30 (`devlogs/1h26/june30/noon-chat.md`): `:131` "i really loved how we reused chrome's ui toolkit... find me some web references that explain it, or at leas give some visual examples of it. we're playing lego here, i need to understand what are the sets/bricks that are availabe to me and how they behave" · `:150` "also who me the view_examples_with_content, i guess this will be the equivalent to a storybook js" · `:184` "yes indeed we must fight the instinct to write everything in views either. but there is clearly somehting that we can win from having the mix." · `:187` "another aesthetic point of interest is the lit/polymer story, and understanding if we could perhaps have our own instantiation of that somehow.." · `:193` "my vision for a wayland+cubs is that, like chrome is 'Chrome is a hybrid: Views on the outside, web on the inside', it will be views for the shell instead of noctalia v5; and web (chromium web pages) on the 'inside'" · `:203` "having that utility for 'arbitrary views shell composition on the desktop' perhaps driven by dot config files or similar are still worth an investigation. the 'quickshell is fast to render' part is not so important, honestly with linux shell you build them once and then sort of use them as-is. so i m fine with the recompilation parts, just want to understand what's available to me." · `:221-222` "you went a little overboard. i never asked for a toml config, not even sure that's the best way to configure things here.. same with solid js i m no longer sure thath is the urdace that i want to use for the browser parts... i spoke about lit/polymer and you never tuoched that. i could in fact have my own mechanism here to make it happen, solidjs or something else.." · `:270` "keep in mind the shape of what cubs IS or ISN'T has not been determined yet. we did some exploration conceptually sure.. but never finalized any decision and i want to be cognizant of that"
  → "built once and used as-is" is why BRIEF says performance is not the thing; "lego / storybook" is the component-gallery wish (a GPUIX gallery surface would honour it); "i never asked for a toml config" cautions against inventing a config format tonight (theme JSON fragment is the only config, BRIEF §3.5).

### 2.8 July – September 2026

- 2026-07-29 (`devlogs/2h26/july28-perfecting-tally/july29-compression-talk.md:171-175`, quoted in `sept7/scopes/agency-chromium.md:106-107`): "start with the session management (the invisible stuff), then window management, then implement the shell and finally the terminal" / "this is not 'building an mvp' or 'agile'. i need my engineering to actually compound"
- 2026-08-19 (`continuity/2026-08-19-inbox/inspiration-agency-browser.md:17`, via `FE/32:93`): "this project uses gpui (from zed). it has phenomenal components, which i am inclined to steal wholesale. if i had such a functional interface for my ai models i would consider not using TUIs anymore."
- 2026-08-31 (`sept7/scopes/agency-chromium.md:28`): "low hanging fruits that actually pay my rent are arguably more important than building chromium, which is the moonshot still"; `:27` "i truely consider Agency linux projec to be my 'capstone', the phd of my technical journey"
- 2026-09-01 omarchy-fleet (`PROJECT-SCOPES-2026-09-06.md:2969-2970`): fonts "NEVER EVER shared on the internet"; `:2960` "ghostty and Herdr are IN, kitty terminal is OUT for these users as default"; "no no . herdr is IN. bad."; `:2938-2942` "only ONE nixos build and it s LIVE ON THE DEVICE … NOTHING ELSE. code must be fully written." / "there are no half measures, meaning that nothing after this code buildup should be left for a subsequent v one or v two. We are doing everything up front."
- 2026-09-14 (`continuity/2026-09-15-sept14-working/soak/RULINGS-2026-09-14-afternoon.md:22`, via `FE/32:94`): views-shell is "just a prototype for the CUBS browser when that project is ready for primetime. i really want to get started building this one! then we can delete this repo as fully superseded."
- 2026-09-25 (`browser-tab-bankrupcy/cubs-alternatives.md`): `:2` helium "this is what is being used in the cmux (cmux.com) project. a very good base indeed" · `:13` "that's because chatgpt for linux is built on chromium. yet another sign that the next frontier is the compositor" · `:24` "notes that t3 is very vs-code like in how it has a nice 'tree'. we can get by with just a 'workspace' concept" · `:29-30` "not forgetting the implementation that made me want 'claude on the desktop' https://github.com/lcoutodemos/clui-cc" · `:37-48` desktop shells: starling (swift), denial ("made in rust and flutter; very nice. getting close"), frame ("user citing exactly the same needs as mine")
- 2026-09-25/26 (`browser-tab-bankrupcy/watchlist-unixporn.md`): `:30-35` "amazing qt work: browser, file explorer, jsonl-thread converter and what is seemingly a coding editor; … we keep looking for htis. the looks of these dotfiles are stunning. getting closer to exactly i want in views and chromium. i will work on porting the screenshots as well" (about Tacit) · `:39,48` "on the topic of creating desktop environments, seeing more and more excitement around GPUI" / "i have a feeling that building that ui kit for Views is exactly the missing part that i already started to do with github.com/mecattaf/views-shell"
- 2026-09-27 the separation (`FE/00-RULING-2026-09-27-the-separation.md:5-8`):
  > "i can create a clear separation now: views for OSD: 'anything that goes through fzf launcher for me today' plus notifications, bar, launcher with icons, workspace switcher, clipboard menu. on the CUBS side we control wifi, bluetooth etc. (in a lit-style default interface that can be controlled). 'tabs' are upgraded to workspaces (like cmux v2 exactly) and can have window-managed chromium tabs: web tabs (native), and a terminal that rides libghostty but specifically built and optimized for chromium. all shortcuts are controlled there (since it spans browser, terminal and system shortcuts as it is the window manager as well) / it was 'gpui-kit-shaped kit for views' by the way. / but crucially ANYTHING THAT's a webapp goes on cloudflare deployments: specifically the personal cloudflare-os paradigm; and this is where it all ties together."
  → Tonight's surfaces are this list with "views" replaced by GPUIX: OSD, notifications, bar (rail), launcher, workspace switcher, clipboard menu. Wifi/bluetooth moved from "CUBS side" into `controls`. The webapp half stays on cfos (BRIEF §3.8).
- 2026-09-27 the token kernel (`FE/00b-RULING-2026-09-27-the-token-kernel.md:52-58`):
  > "so we can now start with a 'kernel of design' token, that i know will be interpreted into chromium lit ; views c++ components ; AND since anything that's an actual interactive front-end is on cloudflare workers we benefit from the primer-react inspired claude-anthropic brand kit where we can in a way that subsumes kumo's components library. / that way we can start building this piece-wise."
  > "1) i understand that not everything will be implemented at once. we start with web components, and only then will we get to chromium views. … 2) every and all front-ends i deploy will be done on cloudflare workers."
  → the theme JSON fragment (BRIEF §3.5) is this "kernel of design token"; GPUIX is now the third emitter in place of Views.
- 2026-10-07 (`journal/2026/10/06/README.md:20-22`): "Not switching. 'Frosting, animations and the otto file manager was just not enough'; the aesthetic items do not matter to him, and it was not about the monitor. Scroll stays."
- 2026-10-14 (BRIEF §1): "let s stick to sway window manager. less effort" — Hyprland dropped after 74 minutes; scroll is also gone.

### 2.9 What herdr now holds that an older design gave to something else (summary; details in §3.3)

| Older design (date) | Gave the role to | Now |
|---|---|---|
| kmux L1–L5 CCD sidebar: "Workspace list: grouped Active / Completed / Detached", status dots, "click → `niri msg action focus-workspace`" (2026-03-26, `annotated-kmux:243-291`) | QuickshellX WebEngine plugin at `/ccd`, fed by hook scripts → `~/.local/share/ccd/status/<session>.json` (D1) | **rail**: `herdr workspace list` + agent status glyphs; click → `swaymsg workspace N` |
| Session FSM E1 `spawning → working → waiting_for_approval → waiting_for_input → idle → error → completed`; L4 colours green/blue/amber/red/gray | CCD daemon (F, ~1250 lines Rust) | herdr states blocked ◉ / working ◐ / done ● / idle ✓ / unknown ○ (BRIEF §1) |
| S1 "Workspace-to-session binding mechanism: how does shpool session ID map to niri workspace ID? (prerequisite for everything)" | open question | one herdr workspace = one kitty projector = one Sway workspace, nine-slot cap |
| G agent spawning (`ccd new --parent`, MCP `ccd_spawn_agent`), G4 parent drives children via `kitty @ send-text` | kitty remote control + semaphores | `herdr workspace create/focus/close`; the shell never spawns, it reads |
| I4 "Sidebar 'approve' button → routes to appropriate permission mechanism" | hook HTTP response | `herdr-attention` → Sway urgency + mako actions (branch c1a49b99, BRIEF §2) |
| clui native surface (cowl, 2026-06-27: permission broker, NDJSON streaming, sessions, slash menu) | a layer-shell web surface | herdr-web-ui desk in Chrome on workspace 10 (Mod+0); out of this shell |
| AM #241 "Terminal session management … i use shpool" MUST | shpool + a Rust daemon | herdr server on the strix, `herdr --remote strix` |
| AM #36 Active/focused window MUST; kmux B3 "claude code does output the needed titles" | window-title scraping | herdr snapshot; titles are no longer the signal |
| os.claude / os.agent / os.terminal namespaces (kmux O3) | stubbed Mojo namespaces | the herdr API (`herdr api schema`) |
| KMUX "everything multiplexer" sidebar (2026-04-04, `FE/10:331`) | a layer-shell web sidebar | rail + herdr-web-ui |

---

## 3. Feature inventory

### 3.1 The annotated feature matrix, every row (AM = `devlogs/1h26/april-webshell-refs/ANNOTATED-feature-matrix.md`; `L` = line of the row, Tom's mark is on `L+1`)

Columns: feature as AM names it (with AM's "best impl" where it names one) | Tom's mark, verbatim | disposition tonight | surface and notes. Disposition legend: **keep** (build as marked), **Sway** (compositor owns it), **herdr**, **script** (existing dotfiles script is the backend), **later** (Tom's SHOULD/COULD, not tonight), **drop** (Tom's WONT/DONT), **superseded** (a later Tom ruling or BRIEF overrides the March mark; the newer rule is named).

**1.1 Bar / status bar (AM `:17-68`)**

| # (L) | Feature | Tom's mark (verbatim) | Disposition | Surface / notes |
|---|---|---|---|---|
| 1 (17) | Three-zone layout L/C/R | "MUST, this is basic bar config" | keep, recast | rail is vertical: top / middle / bottom zones (SHELLS-DIGEST §4 geometry) |
| 2 (19) | Configurable widget arrays per zone (DMS JSON) | "MUST" | keep | rail config = a JSON fragment next to the theme fragment (BRIEF §3.5 pattern); no settings GUI |
| 3 (21) | Widget drag-reorder in settings | "COULD, happy to keep it 'deterministic' from config" | drop | config only |
| 4 (23) | Plugin widget system (noctalia BarWidgetRegistry) | "MUST, it is important to be able to 'turn any functionality' into a bar addition" | keep | `src/registry.ts` (BRIEF §4) is this registry; a rail item = a React component + a data source |
| 5 (25) | Multi-monitor via Variants | "MUST" | keep | one rail process, one layer surface per output; eDP-1 top / eDP-2 bottom (BRIEF §1) |
| 6 (27) | Per-screen widget configuration | "MUST" | keep | eDP-2 (Chrome) may show a reduced rail |
| 7 (29) | 4-way position | "MUST" | keep (left only) | BRIEF: "no top bar on the Linux head"; anchor left/top/bottom |
| 8 (31) | Vertical bar layout | "MUST, in fact i have a very specific use case in mind for that." | keep | the use case was #27: the workspace switcher as its own left bar |
| 9 (33) | Auto-hide with hover reveal | "MUST, could be useful but more important for me is that i want to toggle bars with a niri keybind (sigint)" | keep, Sway bind | `gpuix-shell rail toggle` from a Sway bind; hover reveal optional |
| 10 (35) | Fullscreen detection auto-hide | "MUST" | keep | Sway IPC `window` events carry `fullscreen_mode`; hide the rail when the focused container is fullscreen |
| 11 (37) | Click-through mode (region mask) | "COULD" | later | GPUIX layerShell has no input-region API in 0.11 (unknown; check `index.d.ts`) |
| 12 (39) | Multiple simultaneous bars | "MUST, i will in fact have multiple simultaneous bars in my config, and want to be able to toggle one but not the other" | keep | `gpuix-shell rail toggle --output eDP-1`; one verb, one bar |
| 13 (41) | Integrated dock in bar | "COULD" | drop | |
| 14 (43) | Bar style variants | "COULD" | drop | one style (noir flat) |
| 15 (45) | Goth/outer corners | "COULD, but this is less difficult because i use web components" | drop | hairlines, no corners (BRIEF §1 look) |
| 16 (47) | Per-screen density | "COULD, since we have per-screen settings anyway" | later | collapsed 56 / expanded 220 (BRIEF §3.3) is the only density pair |
| 17 (49) | Scroll to switch workspace | "COULD, quite secondary for me" | later | |
| 18 (51) | Scroll to adjust volume on bar | "COULD, secondary" | later | |
| 19 (53) | Scroll to adjust brightness on bar | "COULD, secondary" | later | |
| 20 (55) | IPC bar toggle | "MUST, and very important to have funcioning well with niri; in fact one ipc toggle should control only one bar (in case there are multiple bars)" | keep | the `gpuix-shell` CLI over `$XDG_RUNTIME_DIR/gpuix-shell/shell.sock` (BRIEF §3.2) is this door |
| 21 (57) | Shadow/elevation system | "COULD, quite secondary. conceptually an elevation system is interesting but this should be minimal layershell logic, nothing more" | drop | BRIEF: "hairlines not shadows" |
| 22 (59) | DPI-aware snapping | "SHOULD because dpi-aware anything is important" | keep | Duo is scale 2 on eDP-1/eDP-2; test under runtime-test at scale 2 |
| 23 (61) | Configurable animation duration | "COULD, i really do not care about animations whatsoever" | drop | one 50 ms token (§4) |
| 24 (63) | Content window separation from background | "COULD" | drop | |
| 25 (65) | Screen frame integration | "COULD" | drop | |
| 26 (67) | Hot corners on bar edges | "SHOULD, niri itself also has hot corner but this one clearly has more potential" | later | Sway has no hot corners; a rail-edge hover → launcher is cheap |

**1.2 Bar widgets (AM `:74-149`)**

| # (L) | Feature | Tom's mark (verbatim) | Disposition | Surface / notes |
|---|---|---|---|---|
| 27 (74) | Workspaces indicator | "MUST, in fact in my concepts i had the workspace switcher as a separate left horizontal bar, whereas all the other modules exist in the top bar." | keep | **rail**: Sway workspaces 1–9 (eDP-1) + 10 (eDP-2); herdr workspace names and agent glyphs per slot |
| 28 (76) | Clock | "MUST, but no need to do anything fancier than configurable time and date. the minimal eqsh one was sufficient." | keep | rail bottom zone, mono figures |
| 29 (78) | System tray (SNI) | "SHOULD, very nice to have but i won't be using it personally" | later | SNI host is "Hard" (RETRIEVED `:623`); not tonight |
| 30 (80) | Battery indicator | "MUST" | keep | UPower over dbus-next; Zenbook only |
| 31 (82) | Network/WiFi indicator | "MUST" | keep | NetworkManager D-Bus; click → controls |
| 32 (84) | Bluetooth indicator | "MUST" | keep | BlueZ; click → controls pairing |
| 33 (86) | Volume/Audio indicator | "MUST" | keep | `wpctl`; click → controls audio route |
| 34 (88) | Media/MPRIS widget | "MUST" | keep | MPRIS via dbus-next; the Navidrome/mpv demo (BRIEF §5) is an MPRIS player if mpv runs with `--input-ipc` or mpv-mpris |
| 35 (90) | Notification indicator | "MUST" | keep | unread count from the notifications daemon; click opens the centre |
| 36 (92) | Active/Focused window | "MUST" | herdr | the focused Sway container's app_id; herdr workspace title preferred |
| 37 (94) | Power/Session menu | "MUST, in fact i really like the DMS one which made you 'hold a key for x seconds with a visual progress bar'; in addition to being able to scroll through them." | keep | **power**: list + press-and-hold radial confirm |
| 38 (96) | Launcher button | "SHOUlD, trivial to add but i won't use it personally" | later | rail top glyph → `gpuix-shell launcher toggle` |
| 39 (98) | Privacy indicators (mic/cam/screen) | "MUST, and i'll likely develop a specific widget around it" | keep | PipeWire node graph; `call-record` lights it (fleet ledger A8) |
| 40 (100) | CPU/Memory/System monitor | "SHOULD, good to have but i don't intend to use it myself" | later | |
| 41 (102) | VPN indicator | "MUST. it is CRUCIAL for me to know if i'm connected to tailscale, and possibly to know what other devices are connected on my tailscale network. i am aware that there are 2+ different tailscale DMS extensions, happy to bring them over in due time" | keep | **rail** item + **controls** peer list; `vpn-status` script already "Outputs JSON for bar widget" (fleet ledger A7); **not named in BRIEF §3: gap G1** |
| 42 (104) | Keyboard layout | "COULD, nice to have but i won't be using it" | drop | |
| 43 (106) | Weather widget | "COULD, nice to have but i won't be using it" | drop | |
| 44 (108) | Clipboard button | "COULD, nice to have but i won't use it" | drop | Mod+V bind instead |
| 45 (110) | Idle inhibitor toggle | "COULD" | later | controls tile (caffeine) |
| 46 (112) | Color picker button | "COULD, i intend to use colorpicker but with a niri shortcut" | script | Mod+C → `colorpicker` |
| 47 (114) | System updates count | "SHOULD, this would be interesting and i would have to build functionality specifically for my fedora atomic system. still, a nice touch" | superseded | NixOS now; `fwupd-refresh` exists; not a shell concern |
| 48 (116) | Audio visualizer | "SHOULD, i loved dms' popup for music and its associated 'scroll through to skip parts of the song'." | later | the scroll-to-seek progress bar belongs to the MPRIS popover, not a spectrum |
| 49 (118) | Caps/Lock key indicator | "SHOULD, trivial but i won t use it" | later | Caps Lock now toggles the touchpad (commit 7e082fbb) with an OSD: the OSD part is the notifications window |
| 50 (120) | Global menu bar | "COULD, i did have it but i'm not really using it" | drop | |
| 51 (122) | AI button | "COULD, same as 50 equora has it but i never use it" | superseded | **ask** (OpenUI) is a bound surface, not a bar button |
| 52 (124) | Dark mode toggle | "COULD but as you know my shell has NO light/dark mode: it's all Dark Glass aesthetic" | superseded | three themes via `~/.local/bin/theme`; the shell follows the symlink (BRIEF §3.5) |
| 53 (126) | Night light toggle | "COULD, i won't use it myself, but do it keeping in mind that this will require special functionality as i use a specific gamma tool wl-gammarelay-rs which is the only one that does per-monitor to my knowledge" | later | controls tile over wl-gammarelay-rs D-Bus (fleet ledger S1/G12) |
| 54 (128) | Power profile selector | "COULD, very secondary" | later | controls tile (power-profiles-daemon) |
| 55 (130) | Brightness widget | "COULD" | script | `brightness` keeps the floor/mirroring logic; OSD shows it |
| 56 (132) | Microphone widget | "COULD" | keep (OSD) | mic mute OSD = same slider type |
| 57 (134) | Wallpaper selector | "COULD, i m not too big on wallpaper changing and other cosmetic trivialities" | drop | wallpaper is #000000 |
| 58 (136) | Custom IPC button (five bindings) | "SHOULD" | keep | a rail item kind `command` {click, right, middle, scroll-up, scroll-down → shell verb} |
| 59 (138) | BongoCat | "WONT, we're building a serious shell" | drop | |
| 60 (140) | Recording indicator | "MUST, i will use that" | keep | `recording-toggle` already "signals the shell" (fleet ledger A8) |
| 61 (142) | Network speed monitor | "SHOULD, nice to have, possibly cool to have it toggled when we press the wifi/network button or as standalone" | later | in the controls network detail |
| 62 (144) | Apps dock in bar | "COULD, wouldn't use it directly" | drop | |
| 63 (146) | Notepad button | "COULD" | drop | (#249 WONT) |
| 64 (148) | Pin button (auto-hide toggle) | "COULD, i prefer toggling things with keybinds" | drop | |

**1.3 Notifications (AM `:155-190`)**

| # (L) | Feature | Tom's mark (verbatim) | Disposition | Surface / notes |
|---|---|---|---|---|
| 65 (155) | Notification daemon (server) | "MUST this one is non-negociable" | keep | **notifications**: own `org.freedesktop.Notifications` over dbus-next; replaces mako (BRIEF §1) |
| 66 (157) | Configurable popup position (6+) | "MUST" | keep | toasts top-right 390 wide max 4 (BRIEF §3.3); position is a theme/config value |
| 67 (159) | Notification center / history panel | "MUST, although the specific aesthetic of it is not clear in my mind." | keep | a toggleable panel in the notifications process; Tacit's notificationPopup for the look |
| 68 (161) | App-name grouping | "MUST, seems trivial to implement like how DMS did it" | keep | |
| 69 (163) | Inline action buttons | "COULD, not necessary to have in the first implementation but hapy to revisit the importance of that functionality once this level of detail becomes in discussion" | keep anyway | `herdr-attention` → mako *actions* (branch c1a49b99) depends on actions; keep actions |
| 70 (165) | JSON-file history persistence | "MUST, useful" | keep | `$XDG_STATE_HOME/gpuix-shell/notifications.jsonl` |
| 71 (167) | Do Not Disturb toggle | "SHOULD, likely something i toggle with a keybind or a button on bar" | keep | `gpuix-shell notify dnd toggle`; controls tile |
| 72 (169) | Rules engine (pattern match) | "MUST, nice to have from DMS" | later | config-driven per-app rules; v2 |
| 73 (171) | Swipe-to-dismiss | "COULD, not too urgent, possibly nice ot have as cosmetic later" | drop | |
| 74 (173) | Per-urgency timeouts/colors | "MUST" | keep | low/normal/critical timeouts + hairline colour |
| 75 (175) | Notification sounds | "SHOULD, dms phenomenal reference" | later | |
| 76 (177) | Progress indicator (hints.value) | "COULD, revisit after" | later | cheap: render `value` hint as a bar |
| 77 (179) | Keyboard navigation in notif center | "MUST, dms hints overlay philosophy is very desirable" | keep | hint letters on each toast; Mod+o dismiss exists (PR #571) |
| 78 (181) | Lock screen notification display | "COULD, to be revisited later, i rarely to never lock my screen" | drop | |
| 79 (183) | Privacy mode (hide body) | "SHOULD, since we re relying mostly on dms implementation as inspiraton" | later | |
| 80 (185) | Cross-generation restoration | "COULD, to be revisited in a second pass" | later | reload the JSONL on restart |
| 81 (187) | Image caching for history | "SHOULD" | later | |
| 82 (189) | Flood protection / rate limiting | "MUST, to avoid dangerous or strange behavior on my system" | keep | 20/s cap + 1 s duplicate coalescing |

**1.4 Launcher / app drawer (AM `:196-238`)** — Tom's general note at `:238` is in §2.5; "RAYCAST" is the north star, Vicinae the reference now being replaced.

| # (L) | Feature | Tom's mark (verbatim) | Disposition | Surface / notes |
|---|---|---|---|---|
| 83 (196) | App search (fuzzy) | "MUST" | keep | **launcher** provider `apps`: XDG .desktop incl. the 11 PWA entries |
| 84 (198) | Calculator | "COULD, nice to have" | keep (cheap) | `=` prefix, pure JS |
| 85 (200) | File search (fd) | "MUST, and fd plugin seems sufficiend, dms' dsearch was overkill and having a separate package for that is not desirable" | keep | provider `files` via `fd`; also the **files** surface |
| 86 (202) | Clipboard mode in launcher | "MUST, it's important for me to have the clipboard history shown in the same aesthetic as the launcher; also making sure that we are displaying images (i use cliphist, prefer not to create special rust functionality as i found DMS reinventing the wheel with their clipboard implementation)" | keep, tension | provider `clipboard` with image previews; BRIEF §3.4 chooses an own store over cliphist: record in ASSUMPTIONS |
| 87 (204) | Emoji picker | "SHOULD, emoji is somehting i have had for years, previously in a handrolled fzf menu, but now we have so many of those emoji pickers it should be trivial to create our own or rip the most performant one" | keep | provider `emoji` (`:` prefix) |
| 88 (206) | Plugin/provider system | "MUST, dms provider concept is powerful" | keep | the provider registry is the launcher's spine; Vicinae's extension API inventory (BRIEF §5) maps onto it |
| 89 (208) | Categories/tabs | "SHOULD, noctalia 12 categories is good enough" | later | |
| 90 (210) | Favourites/pinned apps | "MUST, and caelestia's sqlite frequency is very cool" | keep | pin store + frecency in `bun:sqlite` or JSON |
| 91 (212) | Usage tracking / frecency | "SHOULD, same as above" | keep | same store |
| 92 (214) | App overrides | "COULD, but i like to control my .desktop apps from my local share applications in dotfiles so this is a little redundant" | drop | |
| 93 (216) | dGPU launch option | "WONT" | drop | |
| 94 (218) | Grid/List/Tile view modes | "SHOULD: see my general notes on launcher below" | keep (list) | Raycast list only |
| 95 (220) | Preview panel | "COULD, extremely secondary" | drop | |
| 96 (222) | Action panel (Ctrl+Tab) | "SHOULD, this is a nice addition that makes our launcher raycast-like" | keep | per-item actions (open, open-in-workspace, copy path) |
| 97 (224) | Wallpaper picker mode | "COULD, very secondary" | drop | |
| 98 (226) | Web search | "COULD, explore implementation later if at all (seems redundant with opening a new google chrome tab and doing my search directly from there, little added value in search results in launcher)" | drop | |
| 99 (228) | Shell command execution | "SHOULD, makes us raycast-like" | keep | `>` prefix with live output |
| 100 (230) | Prefix search modes | "SHOULD, explore in second iteration" | keep | prefixes: `=` calc, `>` cmd, `:` emoji, `/` files, `@` herdr workspaces, `♪` navidrome (BRIEF §5) |
| 101 (232) | RTL/i18n | "DONT i explicitly reject i18n support for now. this is MY shell i'm not trying to reinvent the linux shell for the entire world" | drop | English only |
| 102 (234) | App blacklist/hide | "SHOULD because easy" | keep | config list |
| 103 (236) | HyprlandFocusGrab dismiss | "DONT because we're niri wm-exclusive. if there exists a niri alterantive would consider that as COULD" | Sway | layer-shell `keyboardInteractivity: exclusive` + Esc; Sway focus events close it |

**1.5 Audio / media / OSD (AM `:244-300`)**

| # (L) | Feature | Tom's mark (verbatim) | Disposition | Surface / notes |
|---|---|---|---|---|
| 104 (244) | PipeWire native audio | "MUST" | script | `wpctl` + `volume` script; subscribe via `pw-mon` or poll |
| 105 (246) | Per-app volume mixer | "COULD, to be explored later" | later | |
| 106 (248) | Output/input device picker | "MUST" | keep | **controls** audio route; `audio-route` script (F9) is the backend, incl. the near-silent volume lift (commit 97ef81a9) |
| 107 (250) | Output device cycling via IPC | "COULD" | script | `audio-route` already cycles |
| 108 (252) | Device alias/rename (WirePlumber) | "SHOULD, could revisit that, doesnt have to be a part of the first launch" | later | |
| 109 (254) | Volume overdrive >100 % | "DONT explicitly i like to have volume going from 0 to 100; only situation where that's not the case is in vlc media player" | drop | clamp 0–100 |
| 110 (256) | Volume jump protection | "COULD, can add later" | later | |
| 111 (258) | Per-device max volume cap | "COULD, add later" | later | |
| 112 (260) | Volume feedback sounds | "COULD, disabled by default" | drop | |
| 113 (262) | Audio spectrum (Cava) | "DONT i don't care about that" | drop | |
| 114 (264) | Audio spectrum (native C++) | "DONT i don't care about that" | drop | |
| 115 (266) | MPRIS play/pause/next/prev | "MUST, universal anyway" | keep | `media` script (F3/F4/F5) + MPRIS D-Bus |
| 116 (268) | MPRIS seek/position | "MUST, love the progress bar" | keep | rail media popover with scrub |
| 117 (270) | MPRIS shuffle/loop | "MUST" | keep | |
| 118 (272) | Multi-player management | "SHOULD, explore later" | keep (basic) | active-player cascade; Chrome + mpv coexist |
| 119 (274) | Synchronized lyrics | "COULD" | drop | |
| 120 (276) | Player blacklist | "COULD" | later | |
| 121 (278) | Track art caching | "SHOULD since dms does it" | later | Navidrome cover art comes over HTTP anyway |
| 122 (280) | Volume OSD | "MUST. an OSD is very imprtant to have. I found the eqsh one to be very nice (which i m using right now)" | keep | **notifications** OSD window, bottom margin 96 (BRIEF §3.3); replaces the `osd` script |
| 123 (282) | Brightness OSD | "MUST but with a small caveat: i really don't care if the brightness is managed by my shell. as you can see now from my scripts, eqsh is sufficient, and i would be happy to have that being a toggle i control from niri keybinds. doesn't really have to be fully integrated with the shell if it adds work" | script + OSD | `brightness` stays; it calls `gpuix-shell osd brightness <n>` |
| 124 (284) | Caps/Num/Scroll lock OSD | "COULD, revisit that, don't need it at launch" | keep (cheap) | Caps = touchpad toggle OSD already wanted (commit 7e082fbb) |
| 125 (286) | Media playback OSD (album art) | "SHOULD, since dms has it." | later | |
| 126 (288) | Audio output switch OSD | "SHOULD" | keep | `audio-route` → OSD "→ <sink>" |
| 127 (290) | Configurable OSD position | "SHOULD, like the dms 8 positions" | keep (config) | one value in the fragment |
| 128 (292) | Per-type OSD enable | "COULD but by default no need" | drop | |
| 129 (294) | OSD suppression when panel open | "SHOULD, since dms has it" | keep | gate OSD while controls is open |
| 130 (296) | Interactive slider in OSD | "COULD, since dms has it" | drop | |
| 131 (298) | Glass-morphism OSD | "COULD, if glassmorphism is easy to do with our setup" | superseded | no blur, flat (BRIEF §1) |
| 132 (300) | Toast-based OSD | "SHOULD, must learn more about what this does" | keep | the OSD **is** a toast in the same window (BRIEF §3.2 puts toasts + OSD in one daemon) |

**1.6 Network / Bluetooth (AM `:307-355`)** — all MUST rows feed **controls**; Tom June 2026 D20: "critical to v1".

| # (L) | Feature | Tom's mark | Disposition | Surface / notes |
|---|---|---|---|---|
| 133 (307) | WiFi scan/connect with password | "MUST" | keep | controls → wifi; `fzf-nmcli` (255-line Python NM menu in dotfiles) is the behaviour to port |
| 134 (309) | WPA-Enterprise auth | "SHOULD" | later | |
| 135–138 (311–317) | WiFi disconnect / radio toggle / forget / saved list | "MUST" ×4 | keep | NM D-Bus |
| 139 (319) | Hidden network connect | "MUST" | keep | |
| 140 (321) | Network info detail (band/channel/BSSID) | "MUST" | keep | |
| 141–142 (323–325) | Ethernet status + detail (IP/MAC/speed/DNS) | "MUST" ×2 | keep | strix is wired; client wifi |
| 143 (327) | VPN management | "MUST" | keep | Tailscale rows (not NM VPN) |
| 144 (329) | VPN multi-provider | "MUST with special focus on tailscale" | keep | `tailscale status --json` |
| 145 (331) | Network speed monitor | "MUST" | later | (#61 said SHOULD; later mark wins only inside the popover) |
| 146 (333) | Airplane mode | "MUST" | keep | rfkill |
| 147 (335) | NM SecretAgent | "MUST" | keep | password prompt inside controls (SECRET/AUTH class, §4.5) |
| 148–151 (337–343) | BT power / scan / connect / pair-forget | "MUST" ×4 | keep | controls → bluetooth; Huion + Magic Trackpad pairing (fleet ledger P6) |
| 152 (345) | BT pairing agent (PIN/passkey) | "SHOULD" | keep | needed for "bluetooth pairing menu" (BRIEF §1) |
| 153 (347) | BT battery | "SHOULD" | keep | UPower cross-ref |
| 154 (349) | BT codec detect/switch | "SHOULD" | later | |
| 155 (351) | BT device pinning | "SHOULD" | later | |
| 156 (353) | BT discoverable toggle | "SHOULD" | later | |
| 157 (355) | BT RSSI | "SHOULD" | later | |

**1.7 Compositor integration (AM `:362-392`)**

| # (L) | Feature | Tom's mark (verbatim) | Disposition | Surface / notes |
|---|---|---|---|---|
| 158 (362) | Multi-compositor facade | "WONT. We are building this shell for niri ONLY. No multi-compositor support." | superseded (Sway only) | principle kept: one compositor |
| 159 (364) | Niri IPC (dual socket) | "MUST. Confirmed: Rust daemon uses niri-ipc crate with typed bindings, not the 1500-line QML dual socket pattern." | Sway | i3-ipc in-process (`swaymsg -t subscribe` or socket), BRIEF §3.4 |
| 160 (366) | Niri config generation | "COULD, maybe later if there is justifiable functionality to be gained there but otherwise prefer that the niri kdl config remain in chezmoi-backed dotfiles and not in the purview of the shell" | drop | dotfiles own `sway/*.conf`; the shell never writes compositor config |
| 161 (368) | Hyprland native module | "WONT: we are niri only" | drop | Hyprland also dropped 10-14 |
| 162 (370) | Sway/I3 native module | "WONT: we are niri only" | **inverted** | the whole shell is the Sway module |
| 163 (372) | ext-workspace-v1 | "COULD, ext worspace is mostly implemmented in niri as well. i don't care about labwc" | Sway IPC | Sway 1.12 IPC `get_workspaces` suffices |
| 164 (374) | DWL/MangoWC | "WONT" | drop | |
| 165 (376) | Workspace overview with thumbnails | "COULD. Niri supports ext-image-copy-capture-v1, so thumbnails are technically feasible — but no existing shell has done it for niri. Not trivial." | later | **switcher** is text + herdr status, no thumbnails (PR #565 shape) |
| 166 (378) | Window drag between workspaces | "COULD. Same as #165 — requires niri screencopy, technically possible but uncharted territory." | drop | |
| 167 (380) | Window rules GUI editor | "WONT i don't care about editing window rules with gui" | drop | |
| 168 (384) | Scratchpads | "SHOULD this is piri functionality so would like to have it baked in" | Sway | native scratchpad (piri retired) |
| 169 (386) | Window swallow (PID) | "SHOULD this is piri functionality so would like to have it baked in" | drop | no Sway equivalent without a daemon |
| 170 (388) | Animated workspace indicator | "COULD. Not compositor-specific — purely frontend animation driven by workspace switch events. Works fine with niri. Low priority." | keep (50 ms) | the rail's active-slot move uses the single token |
| 171 (390) | Debounced event processing | "COULD, i like noctalia's 50ms but not sure we need it" | keep | batch Sway events per frame |
| 172 (392) | Output config generation | "COULD, for now i use `kanshi` to manage outputs and resolutions etc but happy to revisit this later down the line" | drop | kanshi stays |
| 173 (394) | Niri overview toggle | "MUST, but i think this is just something you feed through the niri config with keybind/ipc" | superseded | Sway has no overview; the **switcher** (Mod+i) is the overview |

**1.8 Settings / theming / config (AM `:399-455`)**

| # (L) | Feature | Tom's mark (verbatim) | Disposition | Surface / notes |
|---|---|---|---|---|
| 174 (399) | Dedicated settings GUI | "MUST" | superseded by #200 | single-user: config lives in dotfiles/Nix; no settings surface tonight (gap G8 records the contradiction) |
| 175 (401) | JSON persistence | "MUST" | keep | state JSON under `$XDG_STATE_HOME/gpuix-shell/` |
| 176 (403) | Settings search | "MUST" | drop (with 174) | |
| 177 (405) | Schema migration | "COULD, evenually and in case i do have a schema to migrate from. icebox for now" | drop | |
| 178 (407) | Config validation | "SHOULD, but has to be something that is not hardcoded - it has to validate the config schema programaticaly" | keep | zod/JSON-schema for the fragments; a `bun test` |
| 179 (409) | Presets/profiles | "COULD, much later down the line. icebox for now" | drop | |
| 180 (411) | First-run wizard | "SHOULD, in fact this is a" (sentence cut off in the file) | drop | Nix activation is the wizard |
| 181 (413) | Material You / matugen | "WONT whatsoever: no material or material you (i don't like it); no matugen whatsoever as I explained we do not have a strict colorscheme we follow a standard minimal css token" | drop | |
| 182 (415) | Predefined color schemes | "WONT in the sense that we have only one predefined colorscheme" | superseded | three (noir, claude-dark, claude-light), all from `home/themes` |
| 183 (417) | Dark/light toggle | "COULD far down the line support a single universal dark/light toggle. icebox for now" | superseded | `theme` script does it now; the shell reloads |
| 184 (419) | Auto dark/light | "WONT: even if i do eventually add a light mode this should only be toggled manually" | drop | manual only, still true |
| 185 (421) | OLED mode | "MUST. OLED mode ie make the black colors #000000 is something that i do by default. …" (full text §2.5) | keep | noir = OLED black |
| 186 (423) | Cross-app theming | "WONT. this is also a clear design decision that i take from the start: i do not need help managing my gtk or qt theme etc. that is what dotfiles are for. this also complements my 'NO MATUGEN' decision" | drop | `home/themes/default.nix` renders every app fragment already |
| 187 (425) | Configurable fonts | "SHOULD but the default font, like eqsh, is sanfrancisco mono." | superseded | Anthropic Sans 12 UI, mono figures (BRIEF §3.5); `registerFont(bytes)` in gpuix 0.11 |
| 188 (427) | Animation speed control | "WONT. not sure if the shell has anything to do with animation speeds at all, and even if it does i would make it none/short for snappiest experience" | drop | |
| 189 (429) | Transparency/opacity config | "SHOULD. Compositor (niri) owns blur via ext-background-effect-v1; CSS just sets background-color alpha. This reduces to configurable alpha on material levels — a CSS custom property. Trivial once design tokens exist." | superseded | opaque (BRIEF §1) |
| 190 (431) | Animated color transitions | "WONT. no need" | drop | |
| 191 (433) | Wallpaper picker | "SHOULD because we are indeed controlling the monitor from quickshell side of things (not niri config)" | superseded | wallpaper #000000 solid; `wallpaper` script + swaybg stay |
| 192 (435) | Per-monitor wallpaper | "SHOULD, if we have a wallpaper picker then might as well have it per-monitor (i mostly use dual monitor setup)" | drop | |
| 193 (437) | Wallpaper fill modes | "SHOULD" | drop | |
| 194 (439) | Parallax wallpaper | "WONT i explicltly don't need parallax because it makes me dizzy" | drop | |
| 195 (441) | Wallpaper slideshow | "COULD much later down the line since we have the wallpaper utility anyway" | drop | |
| 196 (443) | Procedural sky | "WONT too fancy" | drop | |
| 197 (445) | i18n / translations | "WONT no i18n whatsoever, shell is always in english." | drop | |
| 198 (447) | Per-monitor config overrides | "COULD but again we manage config with kanshi preferably so might revisit that later" | keep (rail only) | per-output rail variant (eDP-2 reduced) |
| 199 (449) | IPC config changes | "SHOULD" | keep | `gpuix-shell reload` / watch the fragment |
| 200 (451) | Plugin config support | "COULD but we will do that much later down the line. … in my world, an ephemeral pomodoro widget has the same place as the main launcher (there is no hierarchy)" | principle | registry entries are peers; no enable/browse UI |
| 201 (453) | Config versioning | "COULD in the future in case i need to migrate a lot. but since it's a single user project we don't need to do a lot of versioning in public." | drop | |
| 202 (455) | Gradient/halftone | "WONT" | drop | (CUBS T2 "gradient vocabulary DROPPED … not deferred, ruled out", `agency-chromium.md:125`) |

**1.9 Session / security (AM `:462-504`)**

| # (L) | Feature | Tom's mark (verbatim) | Disposition | Surface / notes |
|---|---|---|---|---|
| 203 (462) | Lockscreen | "COULD this functionality is quite secondary. i bypass lockscreen by default on reboot (already implemented in my os with greetd automation); and when i need to rest my desktop i do `systemctl sleep`. might revisit this later because the functionality is already documented and we have good references for it. but icebox for now" | drop | ext-session-lock is not layer-shell; keep an external locker if ever (`resurface-frontend-and-fleet.md:30`) |
| 204–211 (464–478) | PAM, fingerprint, U2F, OSK on lock, media on lock, notifications on lock, weather on lock, shake | "COULD, icebox for now, like above" ×8 | drop | |
| 212 (480) | Video screensaver | "WONT, too fancy" | drop | |
| 213–215 (482–486) | Greetd greeter, user select, session select | "COULD, icebox for now, like above" ×3 | drop | greetd autologin stays (`modules/common.nix`) |
| 216 (488) | Polkit agent | "MUST. i do not like the classic gtk greeter (that gets used now in the current state of my dotfiles). we are writting a very nice, very well-done uniform design system. dms and others have proven to me that polkit is implemented and easy to do with regular quickshell. this is low-hanging fruit" | keep | **not in BRIEF §3.2: gap G2**; fleet still has "polkit enabled, no agent" (fleet ledger P4) |
| 217 (490) | Polkit fingerprint | "SHOULD, not vital for now but might as well" | later | fprintd exists on the client |
| 218 (492) | Power menu | "MUST and in fact i want to mention that i like the new DMS powermenu the most with the ability to scroll/select through a list AND press and hold a given key to get the desired action" | keep | **power** |
| 219 (494) | Hibernate detection | "SHOULD, low hanging fruit" | keep | power menu entry if `/sys/power/state` has `disk` |
| 220 (496) | Suspend-then-hibernate | "SHOULD, low hanging fruit" | keep | |
| 221 (498) | Userspace reboot | "COULD, icebox for now, have to explore this more to understand if i would even benefit from it" | drop | |
| 222 (500) | Session action confirmation dialog | "COULD if i find this to be useful later down the line. for now icebox" | superseded by 218 | the hold-to-confirm *is* the confirmation |
| 223 (502) | Compositor-agnostic logout | "WONT. the webshell project is exclusive to niri window manager" | Sway | `swaymsg exit` |
| 224 (504) | Multi-compositor session detection | "WONT unless we find that we need something else but know that i m using niri standard" | drop | |

**1.10 Idle management (AM `:508-519`)** — one blanket mark at `:508`: "> COULD the entire idle management suite is not so important for me, i prefer to icebox for now. this applies to 225-232 inclusive". Rows 225 idle inhibitor, 226 idle monitor, 227 per-AC/battery timeouts, 228 fade-to-lock, 229 custom idle commands, 230 inhibit-when-audio, 231 lock-before-sleep, 232 caffeine → all **drop**, except a caffeine tile in **controls** (cheap, AM #45/#232; `monitors-off` script exists).

**1.11 Utilities (AM `:525-593`)**

| # (L) | Feature | Tom's mark (verbatim) | Disposition | Surface / notes |
|---|---|---|---|---|
| 233 (525) | Clipboard manager | "MUST the clipboard manager is very important to me. note however that i use cliphist currently. i discuss the specifics of my implementation separately" | keep | launcher provider + Mod+V; store choice is ASSUMPTIONS material (cliphist vs own) |
| 234 (527) | Screenshots | "WONT because existing niri window manager is sufficient" | script | `screenshot` (grim/slurp/satty) stays |
| 235 (529) | Screen recording | "COULD look into what this entails but my first instinct is that i already use OBS Studio (as flatpak) to record screen, making this implmementation quite redundant" | script | `record`/`recording-toggle`; indicator only |
| 236 (531) | Screenshot annotation | "WONT the builtin niri screenshot functionality is sufficient for me" | script | satty |
| 237 (533) | Color picker | "MUST but Color picker currently since i use niri window manager the screenshot tool exists and is sufficient" | script | `colorpicker`; its toast becomes a real notification |
| 238 (535) | OCR | "SHOULD but with a twist. …" (full text §2.5) | script | `screen-ocr-area` → Halogen Flash; a launcher action "OCR selection" |
| 239 (537) | Calendar with events | "SHOULD keep this idea for later" | cfos | BRIEF §3.8: mail/calendar utilities are not built here |
| 240 (539) | Calendar month grid | "WONT. the calendar month grid display will be handled by a bespoke, fullscreen, on-brand calendar app FAR later down the line. …" | drop | clock popover shows date only |
| 241 (541) | Terminal session management | "MUST but i use shpool for terminal sessions, not tmux nor zellij. that being said the dms implementation could be very helpful in my preparation of that fucntionality. requires further specialized scoping" | herdr | |
| 242 (543) | Power menu | "MUST, i believe i already discussed this earlier" | keep | = #218 |
| 243 (545) | Night light / gamma | "WONT, my gamma control and night light is set once and not from the shell. skip entirely" | drop | kanshi + wl-gammarelay-rs |
| 244 (547) | Weather display | "COULD. very secondary given that i rarely check for this kind of information, but since it seems so common in shells happy to bring that feature over later" | drop | |
| 245 (549) | System monitoring | "COULD. very secondary given that i rarely check for this kind of information, but since it seems so common in shells happy to bring that feature over later" | later | `claude-capacity` script is the one monitor Tom reads: a rail item |
| 246 (551) | Desktop widgets | "WONT. i do not like widgets" | drop | |
| 247 (553) | AI assistant integration | "COULD but much later down the line. i do not need an ai integration the way it is done in the reference qml shells. i have some ideas here so not marking this as won't" | herdr + ask | |
| 248 (555) | Update checker | "COULD far later down the line, especially because this should be custom for my system" | drop | |
| 249 (557) | Notes/notepad | "WONT. i use github-backed md notes. see no value in having external notepad. drop that" | drop | |
| 250 (559) | Pomodoro/timer | "SHOULD the pomodoro timer concept is very valuable and i have my own approach for it. so we use the existing references and build on top of it. this will be the first feature i release AFTER base webshell" | script | `pomodoro` script exists; a rail item + launcher provider wrap it |
| 251 (561) | Docker/Podman management | "SHOULD Container management is very desirable on my system, i expand on thsi a little later" | later | systemd user units view (Tom's extension idea, #263) |
| 252 (563) | KDE Connect | "SHOULD; this doesn't have to be done right away but the KDE connect is extremely desirable. i believe that dankmaterialshell also has KDE connect. in the past i also considered Valent for the same. to be scoped out better but i wish to make it clear that 'android phone notification' is extremely desirable" | later | **gap G4**: not in BRIEF; Valent/kdeconnect notifications arrive through the daemon once it exists |
| 253 (565) | QR/Barcode scanner | "COULD because easy but not urgent, ocebox" | drop | |
| 254 (567) | Google Lens | "WONT, adds very little value over a google search in google chrome..." | drop | |
| 255 (569) | Greetd greeter | "COULD but icebox, until i decide what to do with the greeter situation on my device" | drop | |
| 256 (571) | Polkit agent | "MUST this one is important" | keep | = #216 |
| 257–259 (573–577) | Screen pin / measurement / palette extraction | "WONT" ×3 | drop | |
| 260 (579) | Webcam mirror | "COULD this is indeed desirable, a bit like an 'apple camera'; but icebox for now as for these purposes using OBS studio which i already have is sufficient" | drop | |
| 261 (581) | Shutdown timer | "WONT" | drop | |
| 262 (583) | Printer management | "COULD becaues it's 'free' (already have working implementation) but icebox for now because i don't use a printer at the moment" | superseded | paper-daemon prints now; not a shell surface |
| 263 (585) | Process manager | "COULD later down the line. this reminds me that there was a good DMS plugin for viewing dockerfiles, which i considered extending to see running systemd services and quadlets" | later | |
| 264 (587) | Changelog viewer | "WONT" | drop | |
| 265 (589) | Onboarding/setup wizard | "MUST but this one will require specific scoping work before i configure it" | superseded | Nix |
| 266 (591) | Dependency doctor | "COULD later on, don't see an immediate need right now" | drop | |
| 267 (593) | SDDM theme | "WONT i do not use SSDM whatsoever. i use a super minimal greetd implmmentation which means i have no use for sddm or similar" | drop | |

**1.12 Quick settings / control center (AM `:597-613`)** — blanket mark `:597` ">> WONT. i do not need a control center. this is not in scope for my project. this applies to 268-280". Rows: 268 QS panel, 269 volume slider, 270 brightness slider, 271 WiFi toggle+picker, 272 BT toggle, 273 DND, 274 dark mode, 275 power profile, 276 night light, 277 idle inhibitor/caffeine, 278 media player, 279 screen recording toggle, 280 screenshot button. **Superseded** by BRIEF §3.2 `gpuix-shell controls` and Tom's "wifi menu, or bluetooth pairing menu; etc." Keep the toggle grammar the June audit recommended: "left = toggle, right = detail, scroll = cycle" (`resurface-noctalia-cade.md:294`, REPORTED as C13). Tiles to ship: wifi, bluetooth, audio route, brightness (client), DND, caffeine, power profile, night light, tailscale. Not: dark mode (theme script), screenshot/recording buttons (binds).

**§2 Gap rows (AM `:623-654`)**: hotspot "WONT" · scheduled DND "WONT" · inline reply "WONT" · full-text search in history "WONT" · brightness without CLI "WONT" · native clipboard manager "COULD. discussed externally. to be revisited later. could convince me to move away from cliphist" · urgency grouping "WONT" · snooze "WONT" · per-app sounds "WONT; i barely expect nofitication sounds anyway" · calendar event creation "COULD but much much further down the line" · IME "WONT" · screen reader "WONT" · multi-user "WONT, i use single-user on my desktop" · spatial audio "WONT" · HDR "WONT, i do not care much for hdr and not even sure niri/my monitor has it" · touch/gestures "COULD but much later down the line. I have `lisgd` installed for touch support. niri also has something with touch support. for now no need to configure this at all. icebox maximally" (note: the Duo is a touch device; Sway `bindgesture` exists).

**Counts** (parsed by the Oct 1 resurface, `resurface-noctalia-cade.md:333`, REPORTED): 77 MUST, 55 SHOULD, 97 COULD/icebox, 51 WONT over 280 rows; gap rows 13 WONT, 3 COULD.

### 3.2 The June 11 "Ultimate Desktop Shell" taxonomy → `gpuix-shell` CLI verbs

`cade-june11-idealized/research/ultimate-shell-feature-set.md` names, per domain, the DMS `dms ipc call` verbs it treats as "the typed control protocol we are reverse-engineering" (`:15-17`). These are the verbs BRIEF §3.2's socket CLI should expose, with the four-tag class from `design/00-IDEAL-TARGET.md:13-18` (READ / WRITE-reversible / ACTION-irreversible / SECRET-AUTH):

| Domain (file §) | Verbs named | Tag | gpuix-shell process |
|---|---|---|---|
| Panels/bar (§1, `:34-38`) | `bar reveal/hide/toggle/toggleReveal`, `bar status`, `dock toggle/status`, `widget list`, `widget toggle <id>` | WRITE-rev / READ | rail |
| Launcher (§2, `:53-57`) | `spotlight open/close/toggle`, **`spotlight openQuery <q>` / `toggleQuery <q>`** ("the canonical 'open a foldable surface with parameters' verb"), `defaultApp browser\|fileManager\|…`, `file browse <type>` | WRITE-rev | launcher (`gpuix-shell launcher toggle --query "…"`) |
| Notifications (§3, `:75-79`) | `notifications open/close/toggle`, `getDoNotDisturb`, DND set/toggle, event stream, dismiss/invoke-action by id | READ / WRITE-rev / invoke = ACTION | notifications |
| OSD (§4) | none of its own; "appears as a side effect of volume/brightness verbs"; optional suppress/force | cosmetic | notifications (`gpuix-shell osd volume\|brightness\|mic\|caps <value>`) |
| MPRIS (§5, `:109-113`) | `mpris list`, `play/pause/playPause/previous/next/stop`, now-playing event stream | READ / WRITE-rev | rail (media item) |
| Tray/SNI (§6) | read item list; activate / open menu by id (opaque ACTION) | READ / ACTION | later |
| Audio (§7, `:149-153`) | `audio setvolume/increment/decrement/mute/setmic/micmute`, `audio status`, device enumeration + default-device-set | READ / WRITE-rev | controls (+ `volume`, `audio-route` scripts) |
| Network (§8, `:168-173`) | read state (SSID, signal, AP list); connect-to-network is **SECRET-AUTH** ("the secret flows through the agent … must treat … as auth/secret-bearing") | READ / SECRET | controls |
| Bluetooth (§9, `:186-189`) | read adapter/device list; power/scan/connect reversible; "a distinct confirm-pairing path" | READ / WRITE-rev / SECRET | controls |
| Power (§10, `:206-209`) | `powerprofile list/status`, `set/cycle`, `inhibit toggle/enable/disable`; battery telemetry = PUB/SUB | READ / WRITE-rev | rail + controls |
| Session (§11, `:227-239`) | `lock lock/demo/isLocked`, `powermenu open/…`, `sessions list/activate/switchTo`; **"Unlock — must never be a remote verb"**; suspend/poweroff/reboot/logout "gate behind explicit confirmation, never auto-fire" | ACTION / SECRET | power (hold-to-confirm is the gate) |
| System monitor (§12) | metrics stream; `processlist open/close/toggle`; kill = guarded ACTION | READ / ACTION | later |
| Clipboard (§13, `:269-272`) | `clipboard open/close/toggle`; read/search/re-copy by id; "potentially secret-laden (passwords land here)" | WRITE-rev / sensitive READ | launcher provider |
| Capture (§14) | trigger capture (ACTION, privacy-relevant), `color-picker open/openColor/toggle` | ACTION | scripts |
| Theming (§15, `:305-307`) | `theme toggle/light/dark/getMode` | READ / WRITE-rev | `theme` script; shell reloads on symlink change |
| Wallpaper (§16, `:320-323`) | `wallpaper get/set/clear/next/prev` + per-monitor `getFor/setFor/nextFor/prevFor`; "the protocol needs an output identifier parameter" | READ / WRITE-rev | `wallpaper` script (solid) |
| Calendar/dash (§17, `:338-339`) | `dash open/close/toggle [tab]`, `notepad …` | WRITE-rev | not built (cfos) |

The file's own "load-bearing 6–10" (`:356-375`): bar, launcher, notifications, audio, network, power/battery/profiles, session/lock/idle/auth (+ power menu), MPRIS, tray/SNI, control center + theming; "Bluetooth, clipboard, screenshot, wallpaper, calendar/weather round out the 'complete' set but a shell can ship without any one of them." The sharpest line (`:404-407`): "**`lock` is a safe one-way verb; `unlock` is not a verb at all.** … reads and reversible actions flow freely, irreversible ones are gated, and auth/secret paths are walled off from the wire entirely." → apply to `shell.sock`: no verb may approve a polkit/NM prompt; `power` verbs require the hold.

### 3.3 The kmux sidebar spec (2026-03-26) → the herdr rail, row by row

Source `annotated-kmux-feature-list-v0.md:241-297` (L and M sections). This is the most detailed design Tom ever accepted for the "left sidebar"; BRIEF §1 says "there is a lot of herdr-web-ui centricity here especially on the left sidebar idea".

| kmux item | Spec text (verbatim) | Tonight |
|---|---|---|
| L1a | "PanelWindow: 400px right, full height, WlrLayershell Overlay, transparent bg." | rail: left, layer top, exclusive 56 collapsed / 220 expanded (BRIEF §3.3). Side flipped by AM #27 and the separation ruling. |
| L1b | "Visible across all niri workspaces (layer-shell, not workspace-scoped)." | same on Sway |
| L1c | "Toggle: `shell ccd toggle` IPC command." | `gpuix-shell rail toggle` |
| L2a–e five zones | "Header: brand + clock + search input / Quick spawn: (v0.2+, deferred) / Workspace list: grouped Active / Completed / Detached / Entry detail: expanded view of selected entry / Summary bar: 32px, `N active * N waiting \| $total`" | rail collapsed: glyph column of slots 1–9 + status glyph; expanded (220): herdr workspace titles, agent state, a summary line "N blocked · N working"; "quick spawn" stays deferred (the shell reads herdr, never spawns) |
| L3a–c entry anatomy | "Row 1: status dot + title + model badge ('S4') + time ('12m') / Row 2: tags + diff stat ('+142 -38') / Row 3: context bar (3px, color-shifts blue 0-65% → amber 65-85% → red 85-100%)" | row 1 from `herdr workspace list` (title, state, age); row 3 = `claude-capacity` style context/usage bar if herdr exposes it (unknown; check `herdr api schema`) |
| L3d–f | "Active entry: 2px left border accent + 12% accent fill. / Primary interaction: click → `niri msg action focus-workspace`. / Subagent nesting: 16px indent, thin line connector." | accent hairline on the focused slot; click → `swaymsg workspace <n>` (`sway-workspace` script); nesting dropped (nine flat slots) |
| L4 colours | "Green #34D399 completed / Blue #60A5FA working / Amber #FBBF24 attention/waiting / Red #F87171 error / Gray rgba(255,255,255,0.25) detached" — Tom: "> acceptable for now, to be unified later of course" | unified into theme tokens per state; herdr glyphs blocked ◉ / working ◐ / done ● / idle ✓ / unknown ○ |
| L5a–l "Missing sidebar design (needs work)" | expanded entry layout, search behaviour, right-click menu, keyboard navigation, empty states, error/reconnection states, scrollbar, multi-monitor, section collapse + persistence, cost display, conversation timeline, permission card UI | still the open list for the rail; permission card = `herdr-attention` → notification with actions; reconnection state = "herdr unreachable" glyph (○ unknown) |
| M1–M4 bar widget | "CCD indicator in default bar widget set. / Small icon showing: any agents active? how many waiting? (badge count) / Click toggles CCD sidebar. / Consumes `os.claude.sessions`" | the collapsed rail *is* this indicator (badge = count of blocked) |
| E1 FSM | `spawning → working → waiting_for_approval → waiting_for_input → idle → error → completed` | herdr's five states; map waiting_* → blocked ◉ |
| E2 "Signal priority: hooks (highest) > JSONL logs > VT screen patterns > process CPU state (lowest)" | herdr snapshot is the single signal; no scraping |
| P1 cmux "keyed status model (`set-status <key> 'text'`) — multiple tools write sidebar state independently without clobbering" | if the rail shows per-workspace extra text (pomodoro, recording), key it per source |
| P3 cmux "no-focus-stealing principle — socket commands never activate app or move focus unless method is explicitly focus-intent" | `shell.sock` verbs never focus unless named `focus` |

### 3.4 Omarchy: the web-app model and what it maps to (April 2026 note + Oct 2026 plugin census)

Omarchy manual as pasted (`april-tmp/omarchy-manual-webapps.md:7-54`): "add your own web apps using Install > Web App in the Omarchy menu (Super + Alt + Space). It'll ask you for the app name, app URL, and the icon URL … They'll then be accessible through the app launcher (Super + Space), and use the beautiful frameless web-app window … All the keyboard hotkeys for these web apps can be changed in ~/.config/hypr/bindings.conf. When you're in a web app, you can copy the current URL to the clipboard using Shift + Alt + L." Defaults: HEY Email Super+Shift+E, HEY Calendar Super+Shift+C, ChatGPT Super+Shift+A, WhatsApp Super+Ctrl+G, X Super+Shift+X (+Alt for new post), YouTube Super+Shift+Y, Basecamp/Zoom via launcher.

| Omarchy behaviour | Tom's equivalent today (dotfiles, per fleet ledger W9) | gpuix-shell |
|---|---|---|
| Install > Web App menu entry | 11 PWA `.desktop` entries declared in Nix (`home/home.nix:320-333`, REPORTED) | launcher lists them via `apps`; no install verb (Nix owns the list) |
| frameless web-app window | `google-chrome --app=URL` | unchanged; Chrome lives on workspace 10 (Mod+0) |
| per-webapp hotkeys | Mod+Shift+C claude, Mod+Shift+W gmail, Mod+Shift+Period Notion calendar | Sway binds, untouched |
| Super+Space launcher | Mod+D (vicinae → gpuix-shell launcher) | launcher |
| Shift+Alt+L copy URL | none | a launcher action on the focused Chrome window is possible via CDP; not tonight |
| Omarchy menu (Super+Alt+Space) | none | the launcher's `>`/action panel covers it |
| Omarchy plugin manifest ("everything is a plugin, built-ins included", `kinds` → entry points, presence-is-enabled config, `clone <builtin>`, typed `schema`, IPC verbs `summon/hide/toggle/call`, Oct 1 census `notes3/omarchy-plugins.md:304-430`) | — | the registry (`src/registry.ts`): built-ins and Tom's items under one shape; verbs `toggle/show/hide/call <id>`; **no** marketplace, no enable UI (AM #200) |
| Omarchy built-in bar widgets (37 built-ins: active-window, agents (Claude/Codex usage), audio, bluetooth, clock, elsewhen, indicators, keyboard-layout, microphone, monitor, network, power, spacer, system-update, tailscale, tray, weather, workspaces; `omarchy-plugins.md:84-90`) | — | the rail's item catalogue should at least cover: workspaces, agents (herdr), audio, bluetooth, network, tailscale, power, clock, microphone, monitor(brightness), indicators(privacy) |

Tom's own Omarchy verdict (April): "customizabiilty is world class … and by the way, we use niri not hyprland, kitty term, and all the rest is cowl shell. more customizable. deeper ownership of webapps." The fleet card adds that Omarchy Quattro is the friends' desktop, not Tom's (`PROJECT-SCOPES:2960` "ghostty and Herdr are IN, kitty terminal is OUT for these users as default"); the Anthropic fonts are the one thing Tom wanted to give it ("the missing piece ot make their omarchy beautiful i think", `:2944`), and they must never be public (`:2969`; BRIEF §1 "The Anthropic fonts cannot go public").

### 3.5 DMS productivity notes → what is and is not this shell's

| Item (Tom's list, `final-shell-function.md`) | Where it is tonight |
|---|---|
| tailscale status bottom right | rail (bottom zone) + controls; `vpn-status` script |
| clipboard manager with picture support | launcher provider |
| emoji picker | launcher provider |
| augment current pomodoro | `pomodoro` script wrapped as rail item + provider |
| ocr on text select | `screen-ocr-area` script (Mod+Ctrl+S) |
| on screen keyboard | gap; Duo stylus/touch use case; not tonight |
| hotkeys visualizations | **switcher**-style overlay from `sway/binds.conf` (fleet ledger L11: "scroll has no overlay … built from bindings plus key chips"); Sway has none either |
| "mod k leads to something different, new launcher: experimenting w vicinae" | launcher replaces Vicinae (BRIEF §1, §5) |
| Baikal CalDAV / khal / khard / taskwarrior / backlog "unified service" | **not** this shell (BRIEF §3.8: calendar/CRM utilities are webapps on cfos or herdr-web-ui); the Go CalDAV service design in `productivity-dms.md:138-450` is a pattern, not code to port |
| Sunsama rituals (daily planning, focus timer, shutdown highlights, weekly review) | the "ask" surface + herdr are the LLM-logistics layer Tom wanted; the rituals themselves are cfos/herdr-web-ui territory |

---

## 4. Design values

Ordered from "still binding tonight" to "superseded, kept for the record".

### 4.1 Binding tonight (consistent with BRIEF §1 and §3.6)

1. **One motion duration, 50 ms, for everything; animate only opacity and transform.** Tom 2026-03-16 ("I want the most responsive", `quickshellX-solidjs2-discussion.md:1541-1542`); kmux B12/B13 "> yes for now"; the tiered 50/80/120/180 set was "superseded three minutes later" (`FE/10:184`, REPORTED); AM #23/#188 "i really do not care about animations whatsoever" / "none/short for snappiest experience". Token: `--sys-dur: 50ms`, easing `cubic-bezier(0.16, 1, 0.3, 1)` (kmux B12). Also the June 27 finding "The animation IS the latency" (`FE/02:51`, MEASURED context: niri's ~120 ms re-tile was the bottleneck).
2. **Solid hex surfaces, luminance steps, 1 px hairlines, no shadows on bars/panels, no blur.** kmux N1 "Surfaces (solid hex, not rgba)" M2 `#0a0a0a` bars, M3 `#111111` panels, M4 `#161616` inputs, M5 `#1c1c1c` overlays (`annotated-kmux:301-307`); N4 "Border: 1px solid rgba(255,255,255,0.10) … No shadows on M2/M3 ever"; N8a "No CSS blur/backdrop-filter"; Tom "No CSS blur ever: > yes" (B9, re-quoted `agency-chromium.md:110`). BRIEF: "flat and opaque, hairlines not shadows, no blur, no frost". The *values* come from `home/themes/*.nix` now, not from kmux N; the *rules* hold.
3. **OLED black by default.** AM #185; noir theme.
4. **Monochrome discipline, one accent.** kmux B11 "> yes for now"; N8d "No colored text except accent/semantic"; the FINAL-LINUX-DESIGN kitty palette is four greys (`#828282 #AAAAAA #CCCCCC #DDDDDD`) over `#030303`/`#000000` (`pre-sync/FINAL-LINUX-DESIGN.md:61-91`). Tonight the accent is the Claude accent of each theme.
5. **Keyboard-first; every surface summoned by a bind and self-dismissing.** AM launcher note; June 27 launcher "Summon-on-demand … self-dismisses (Raycast-style). No state desync — launcher owns its own visibility" (`REPORT-2026-06-27.md:53-55`, MEASURED as shipped); DMS hints overlay (AM #77 MUST); Tom 2026-03-30 "for years i used a minimal shell with fzf waybar mako nitifications. keyboad shortcuts also."
6. **Density.** kmux N6 "Shell chrome: 13px base, 28-36px row heights, 4px spacing unit, 16px max padding"; N7 radius sm 4 / md 6 / lg 10 / xl 14 / full; heights compact 28 / default 32 / bar 32 / row 36; z-order base 0 → dock 100 → bar 200 → dropdown 300 → overlay 400 → modal 500 → toast 600 → tooltip 700 (`annotated-kmux:336-347`). BRIEF §3.6 ("rounded 8/12 inner corners") and Anthropic Sans 12 override the numbers; the *ladder* (toast above modal above overlay above bar) is reusable as layer-shell layer choices.
7. **No hierarchy between utilities.** AM #200: "an ephemeral pomodoro widget has the same place as the main launcher (there is no hierarchy)"; registry entries are peers.
8. **The shell reads, dotfiles write.** AM #160/#172/#186 (config stays in dotfiles; no cross-app theming; kanshi owns outputs); June 30 "i never asked for a toml config". The only shell-owned config is the theme fragment + a rail items fragment.
9. **One compositor, typed IPC, no screen scraping.** AM #158/#159; kmux B3 "Status from structured data (JSONL + hooks), not screen scraping"; B6 "Composition over monolith"; B7 "The filesystem IS the API". herdr snapshot + Sway IPC are the two sources.
10. **The verb taxonomy and the firewall.** READ / WRITE-reversible / ACTION-irreversible / SECRET-AUTH; "`lock` is a verb, `unlock` never is"; "untrusted screen, clipboard and web content segregated from exec/window verbs" (the agent-RCE firewall, `resurface-noctalia-cade.md:312`, REPORTED as CM §5 KEEP). Matters tonight because `ask` renders model output next to a socket that can run Sway commands.
11. **No focus stealing from IPC.** kmux P3 (cmux).
12. **"Serious shell", "MY shell", single user, English only.** AM #59, #101, #197; gap rows (multi-user, IME, screen reader WONT).
13. **Build once, use as-is.** Tom 2026-06-30 `noon-chat.md:203`: "the 'quickshell is fast to render' part is not so important, honestly with linux shell you build them once and then sort of use them as-is." Tonight: "performance is not really the thing" (BRIEF).
14. **Lego / gallery.** Tom 2026-06-30 `:131,150`: "we're playing lego here … what are the sets/bricks that are availabe to me and how they behave" / "the equivalent to a storybook js". A GPUIX component gallery (every OpenUI component rendered natively) honours this and is also the OpenUI-coverage test BRIEF §5 asks for.
15. **Functionality from the Quickshell shells, not their visuals.** BRIEF §1; AM's "best impl" column is exactly a functionality map (DMS for notifications/launcher/power menu, noctalia for providers/categories, caelestia for frecency, Ambxst for grouping).

### 4.2 Design doctrine that survives as *method*

- **Render discipline** (`sync-march30/conv-chromium-fork-decision/files/12-performance-engineering-fastest-shell.md`, via `FE/01:247-257`): batch state updates into one pass per tick; `contain`/`content-visibility` (CSS-only, so for GPUIX: keep subtree memoisation and virtualise lists past ~100 rows); `will-change` only while animating; rAF coalescing; push not poll (cowl 36 ctxsw/s vs DMS 438, MEASURED `FE/02:73`).
- **Linear's sync-engine lore** (`files/18-linear-performance-lore.md`): bootstrap into memory, 0 ms reads, optimistic writes. For the shell the "server" really is local (Sway IPC, herdr socket), so the March simplification "you don't need a sync engine because your server is D-Bus" (`:113`) is *true again* tonight, unlike on cfos.
- **Framework-decision rubric** (`REVOLUTION-2/revisions-pt2/FRAMEWORK-DECISION-FINAL.md:111-130`): don't add a second reactive system beside the one you have; one generation target for the LLM. Tonight: React + OpenUI's lang-core, nothing else.
- **Fork-landscape method**: read shipped source, not marketing (`FE/03:84`). Applied tonight to Vicinae's source (BRIEF §5).
- **Surface-audit grading FREE / RESEAT / FORK / NEW / DROP** (`CUBS/SHELL-SHAPE-DECISION.md`, via `FE/02:107`) — the Oct 1 fleet ledger reused it as VIEWS / EXT / KEEP / DROP / GAP (`resurface-frontend-and-fleet.md:163-172`). The disposition column in §3.1 is the same instrument.

### 4.3 Superseded values (do not resurrect)

| Value | Where ruled | Superseded by |
|---|---|---|
| Dark Glass: compositor blur (niri 3 passes offset 3.7), window opacity 0.80–0.85, saturation 2.5–4.5 (`FINAL-LINUX-DESIGN.md:23-33,91`; SOLIDJS-THEME-SYSTEM §1) | Mar 2026 | flat, opaque, #000000 wallpaper (BRIEF); otto's frosting "was just not enough" (2026-10-07) |
| SF Pro Display/Text + SF Mono "MUST" (kmux A14; AM #187) | Mar 2026 | Anthropic Sans / Serif / AnthropicMono Nerd Font (`agency-chromium.md:143`; BRIEF) |
| Dark-only, no theme toggle (kmux B14; AM #52/#182/#183) | Mar 2026 | three themes, runtime switch (`docs/theme-switcher-2026-09-17.md`) |
| One accent `#5B9DFF` (kmux B11) | Mar 2026 | per-theme Claude accent |
| "world's fastest shell", <5 ms event-to-pixel, <2 % idle CPU, <300 MB (`FE/01:337-339`) | Mar 2026 | "performance is not really the thing i m looking for here" (BRIEF) |
| niri only (AM #158) → scroll (Oct 1–7) → Hyprland (Oct 13–14) | 2026 | Sway only ("less effort") |
| Stock Chromium/Ash look as the default (E6, `resurface-webshell-final-shape.md:701`) | Oct 2026 | Claude/Primer look + Tacit vanilla-ness (BRIEF) |
| Quick settings "WONT" (AM `:597`) | Mar 2026 | `gpuix-shell controls` |
| Views C++ / "gpui-kit-shaped kit for views" (2026-09-27) | Sep 2026 | GPUIX (TypeScript) + OpenUI; the kit idea survives as the OpenUI component set rendered natively |

---

## 5. Reusable code and data, with paths

Nothing below is GPUIX code; everything is specification, measured data, or a backend that already runs. Labelled by what to take.

| Artefact | Path | Take |
|---|---|---|
| **The annotated feature matrix** (280 rows + 16 gaps, Tom's marks) | `/home/tom/notes/references/devlogs/1h26/april-webshell-refs/ANNOTATED-feature-matrix.md` (copy: `…/may26/cade/cowl-secondpass/docs/history/`) | the acceptance checklist for every surface; §3.1 above is its re-reading |
| kmux v0 answers + the full token set + sidebar spec | `…/devlogs/1h26/annotated-kmux-feature-list-v0.md:8-72` (A/B rulings), `:241-297` (sidebar), `:299-365` (tokens N1–N8), `:427-458` (patterns to adopt/reject) | rail anatomy, z-ladder, anti-pattern list (14 prohibitions) |
| "Ultimate desktop shell" taxonomy + 56-capability ideal + verb tags | `…/devlogs/1h26/CADE/cade-june11-idealized/research/ultimate-shell-feature-set.md`, `…/design/00-IDEAL-TARGET.md:91-172` (B1–B17 shell domains) | the `shell.sock` verb list (§3.2) and the READ/WRITE/ACTION/SECRET classes |
| The deduplicated capability union U01–U188 with Tom's marks, nv5 coverage, and the June priorities (A1–A16 / B1–B19 / C1–C15, six primitive gaps) | `…/archive/2026-10-06-wm-scoping/notes3/resurface-noctalia-cade.md:46-335` | cross-check table; "MA's three highest-leverage actions: (A3) external IPC door with one-toggle-one-bar; (A4) the notification daemon; (A1+A8) extensibility contracts" (`:318`) |
| The fleet ledger (what each dotfiles bind/script becomes) | `…/notes3/resurface-frontend-and-fleet.md:163-320` | the script → surface mapping used in §3.1 (VIEWS rows = tonight's surfaces; EXT rows = scripts the shell wraps) |
| June 27 launcher spec (providers `.desktop` / `=` / `>`; fuzzy; Ctrl-P/N; summon/self-dismiss) | `…/devlogs/1h26/june27-cowl-nextsteps/REPORT-2026-06-27.md:49-55` | launcher behaviour contract |
| cowl workspace switcher: event-stream → store → re-render; click → focus | `…/devlogs/1h26/may26/cade/cowl-secondpass/surfaces/lib/services.js:639,677-699` (REPORTED via `FE/32:112-115`) | same shape with `swaymsg -t subscribe '["workspace","window"]'` |
| cowl benchmark method (PSS via smaps_rollup, ctxsw/s, CDP latency probes) and numbers | `…/devlogs/1h26/june27-cowl-nextsteps/AGENT1-benchmarks.md`, `AGENT1-perf-and-solidjs.md` | if anyone measures the GPUIX rail: 325 MB PSS / 1.88 % idle / 36 ctxsw/s are the cowl baselines (MEASURED 2026-06-27); Views bar 248 MB / 0.65 % (MEASURED 2026-06-30, `june30/SPIKE-COST-views-vs-web.md:21-22`) |
| Design system (dark-tint doctrine, Linear/Raycast/Taskade reference set, radius 10 px panels) | `…/devlogs/1h26/pre-sync/SOLIDJS-THEME-SYSTEM.md`; production version `…/april-webshell-refs/friday-testing/design-revamp/{DESIGN-SYSTEM.md,tokens.css,global.css}` | prose rules only; values come from `home/themes` |
| Monochrome kitty palette and the niri blur recipe | `…/devlogs/1h26/pre-sync/FINAL-LINUX-DESIGN.md:61-91` | the four-grey ladder if a noir mono palette is needed for figures |
| Component model mixins (Dismissable, FocusTrappable, ListNavigable, Virtualizable) | `…/april-webshell-refs/REVOLUTION-2/revisions-pt2/COMPONENT-MODEL-SPECIFICATION.md:211-260` | behaviour checklist for launcher/switcher lists |
| Aesthetic DNA + 30–40 headless primitives inventory (Raycast/Linear/Superhuman/Zen) | `…/devlogs/1h26/may26/agency-misc/design.md:230-262,327-328` | component checklist against OpenUI's default library |
| Views-shell parity matrix (59 MUST / 57 SHOULD / 38 DEFER) and unit designs (OSD, notifications, SNI, polkit, MPRIS) | `/home/tom/Downloads/wm-scoping/views-shell/docs/NOCTALIA-PARITY.md` (REPORTED path, `DECISION-MEMO.md:100`); GitHub `mecattaf/views-shell` | design input only; C++, ash-bound |
| agency-mvp producer band (Audio via PipeWire dlopen, Brightness via logind/sysfs+udev, MPRIS, OSD push) | `~/agency-agency/agency-mvp/src/agency/producers/` (REPORTED, `DECISION-MEMO.md:96`) | C++; the *list of producers* is the dbus-next/wpctl adapter list for tonight |
| `os.d.ts` typed capability surface (2,132 lines) | referenced in `CLAIMS-LEDGER.md:1997`; location not confirmed in notes (REPORTED) | naming for `shell.sock` verbs if found |
| `fzf-nmcli` (255-line Python NetworkManager menu) | `/home/tom/mecattaf/dotfiles/home/dot_local/bin/fzf-nmcli` (BRIEF §2 row) | the exact NM flows controls must reproduce |
| `vpn-status` ("Outputs JSON for bar widget"), `recording-toggle` ("signals the shell") | `/home/tom/mecattaf/dotfiles/home/dot_local/bin/` (fleet ledger A7/A8, REPORTED) | already shell-shaped data sources |
| herdr client/protocol seam | `penso/herdr-gpui` → `herdr-client`, `herdr-protocol` crates (`journal/2026/10/06/README.md:43-45`, REPORTED); tonight `herdr api snapshot` (BRIEF §2) | the snapshot pushes "full workspace and agent-state snapshots to any client" |
| Omarchy plugin manifest ideas (ranked) | `…/archive/2026-10-06-wm-scoping/notes3/omarchy-plugins.md:398-430`; built-in widget list `:84-90`; catalog TSV (4,537 rows) `notes3/omarchy-plugins-catalog.tsv` | registry shape; the built-in list as a rail-item checklist |
| Theming-kit bundles (anthropic-clay `#CC785C` vs anthropic-coral `#D97757`, m3-default, allblack-cws) | `~/agency/theming-kit/bundles/` (REPORTED, `agency-chromium.md:44,110`) | palette precedent for claude-dark/light; the clay-vs-coral choice is TOM LINE 4 there |
| Go CalDAV service + QML calendar plugin handoff | `…/devlogs/1h26/dms-productivity/productivity-dms.md:138-700` | pattern only (cache + sync engine + IPC); out of this shell's boundary |
| Tacit shell QML (the look to stay close to) | `/home/tom/saturday-tacit/iso-files/usr/share/tacit/shell/modules/ii/{bar,files,island,notificationPopup,onScreenDisplay,overview,sidebarRight,bluetooth}` (BRIEF §2) | Tom 2026-09-25: "the looks of these dotfiles are stunning. getting closer to exactly i want" |
| Sway IPC adapter already written for GPUIX | `/home/tom/.wt/hyprland-solid-shell/design/gpuix-comparison/` (BRIEF §2) | the one in-repo precedent |

---

## 6. Gaps, conflicts and unknowns

Numbered so ASSUMPTIONS.md can cite them.

**G1 Tailscale status is a MUST that BRIEF §3 does not name.** AM #41 "CRUCIAL", #144 "special focus on tailscale", the DMS-era list item 1, Omarchy's built-in `tailscale` widget. Recommend: a rail item (connected / exit node) and a controls detail listing peers from `tailscale status --json`; backend `vpn-status`.

**G2 Polkit agent is a MUST that BRIEF §3 does not name**, and the fleet has none (`resurface-frontend-and-fleet.md:182`, REPORTED: "polkit enabled, no agent"). It is a credential prompt: an overlay with exclusive keyboard, in the `power` or `notifications` process. Needs `org.freedesktop.PolicyKit1.AuthenticationAgent` over dbus-next and a PAM conversation (a helper binary; GPUIX cannot do PAM). Mark as a known hole if not built.

**G3 Privacy / recording indicators are MUST** (AM #39, #60) and not in BRIEF §3; cheap once the rail exists (PipeWire node graph or `recording-toggle`).

**G4 Android phone notifications (KDE Connect / Valent)** "extremely desirable" (AM #252) — arrive automatically through the new notification daemon if `kdeconnectd`/Valent runs; nothing to build in the shell, but the package is not in dotfiles (unknown; not checked).

**G5 Clipboard store: cliphist vs own.** Tom (AM #86, #233) prefers cliphist and "found DMS reinventing the wheel"; BRIEF §3.4 chooses `wl-paste --watch` + own store. Tom left the door open ("could convince me to move away from cliphist", AM `:634`). Either read cliphist's store (`cliphist list`, `cliphist decode`) or own one; record the choice in ASSUMPTIONS.

**G6 Settings GUI MUST (AM #174/#176) vs "configured from the dotfiles themselves … no hierarchy" (AM #200) vs "i never asked for a toml config" (June 30).** Tonight the Nix fragments win; no settings surface. Tom may re-ask.

**G7 Notification hints overlay (AM #77 MUST)** — Mod+o dismiss exists (PR #571); letter hints per toast are not in BRIEF; small.

**G8 "One IPC toggle controls exactly one bar" with multiple bars (AM #12/#20)** — tonight there is one rail per output in one process; the CLI must take `--output`.

**G9 Hotkey cheat sheet** (DMS-era "hotkeys visualizations"; fleet ledger L11) — Sway has no overlay; the switcher process could render `sway/binds.conf`. Not in BRIEF.

**G10 Lock screen** — Tom's icebox (AM #203) and ext-session-lock is not layer-shell; keep out. The `monitors-off` script covers "rest my desktop".

**G11 On-screen keyboard** (DMS-era list) — Duo stylus mode; no shell plan; `lisgd`/touch "icebox maximally" (AM gap rows).

**G12 Calendar, CRM, mail, Sunsama rituals** — explicitly outside (BRIEF §3.8; Tom 2026-09-27 "ANYTHING THAT's a webapp goes on cloudflare deployments"). The DMS Baikal design is history.

**G13 Thread C** (which stacks Linear/Figma/Raycast/Superhuman/Notion/Arc run) was never done as a single artefact (`FE/03:95`); Vicinae's source inventory tonight is the first such audit for a launcher.

**G14 Nothing GPUIX has been measured** except the rail probe (BRIEF, MEASURED 23:45: layer-shell rail on isolated Sway with exclusive zone 56). The March/June numbers are cowl/Views baselines only. The workspace-switch click-to-pixels was never timed in any era (`FE/32:131`).

**G15 The "extremely well scoped but less urgent" CUBS quote** could not be found by two readers (`FE/02:35`, `FE/10:374`); not used here.

**G16 PROJECT-SCOPES-2026-09-06.md has no desktop-shell card.** The shell is only inside agency-chromium (CUBS) and omarchy-fleet (friends). The "ultimate desktop shell" was never a scope card; it lived in AM (March) and the June 11 taxonomy.

**G17 Where this note disagrees with the Oct 1 resurface:** that pass ("scroll + Views, stock Chromium/Ash look") is itself superseded by Sway + GPUIX + Claude look; its ledger rows are reused for their *backend* facts only.

**G18 Dates in AM are approximate.** The file header says "March 2026"; the kmux list is dated 2026-03-26; the AM copy under `cowl-secondpass/docs/history/` implies ≤ late May. Tom's "6 months ago" (≈ April) matches either.

**What was not read:** `resurface-webshell-final-shape.md` beyond its head and the R1–R36 rulings ledger it summarises (E6, Views-as-compositor era, superseded); the `cubs-steelman/*` chapters beyond what `FE/30-32` quote; `CENSUS.md` / `SCOPE-v2.md` of the Oct scoping; the 28 noctalia SECTION appendices; `december-webshell-groundtruth.md` (the Dec 2025 63-MUST list, an earlier priorities list that might also be what Tom remembers); the omarchy-fleet card beyond `:2921-3030`; `productivity-dms.md:700-1510` (Go code) in full.
