# 06-b: Claude session 56e498e4 (14 to 15 Oct), second half: what it holds for the desktop shell

Reader 06-b, wave 1 of the overnight gpuix-shell build, written 2026-10-20. Everything here was read only. Nothing was run against the live session, herdr, Sway or systemd.

**Labels.** MEASURED: I read or ran it tonight (path and line given). REPORTED: a document says so (path given). I did not re-check it against its own source unless the entry says so. INFERRED: my reading or proposal. TOM: Tom's words, verbatim, typos kept.

**Pointers.**
- `L2913` means line 2913 of `/home/tom/.claude/projects/-home-tom-today/56e498e4-f44d-40bd-8caa-6f3f54587411.jsonl`. To read one line: `sed -n 2913p FILE | python3 -m json.tool`.
- Timestamps come from the jsonl and are UTC. CEST is UTC+2.
- `WT` = `/home/tom/.wt/hyprland-solid-shell`.
- `UB` = `/home/tom/agency-agency/ultrabuild`. Its build output exists only on the remote-tracking branch, so read it with `git -C /home/tom/agency-agency/ultrabuild show origin/claude/ub1:<path>`. The checkout is on `main`, which has no `out/kit`.
- `AL` = `/home/tom/today/agency-launch-2026-10-14`.
- `DF` = the dotfiles (read in this worktree, `/home/tom/.wt/dotfiles/gpuix-shell`).

**Indexer used.** The shared helper prints neither timestamps nor jsonl line numbers. I wrote a small one at `/tmp/claude-1000/-home-tom-tuesday-oct20/94d008d7-4112-4bf7-92cd-2de4eab69681/scratchpad/tt6.py` (user turns) and `tt6all.py` (all turns, with line and timestamp). It numbers the same 74 user turns, U0 to U73.

---

## 1. What this source is

| Field | Value | Label |
|---|---|---|
| File | `/home/tom/.claude/projects/-home-tom-today/56e498e4-f44d-40bd-8caa-6f3f54587411.jsonl`: 12,484,280 bytes, 4,054 lines | MEASURED |
| Span | First line 2026-10-14T08:52:36Z, last 2026-10-15T04:00:25Z | MEASURED |
| Seat and cwd | `cc` (`~/.claude`, thomasmecattaf@gmail.com, Max 20x), cwd `~/today`. It also drove `cc2` (`~/.claude-work`) as a cloud session | REPORTED by the compaction summary at L2780 |
| Compactions | L885 (12:12:36Z) and L2780 (20:49:31Z) | MEASURED |
| User turns | 74 text turns (U0 to U73), plus 16 unique messages Tom typed while Claude was working (`attachment.type == queued_command`) | MEASURED |
| Second half (this note) | U37 to U73, L2663 to L4026 (2026-10-14T20:40Z to 2026-10-15T03:58Z), plus the queued messages at L2686 and L2913 | MEASURED |
| Who wrote the second half | 10 turns Tom typed (U37, U38, U39, U40 `/compact`, U42, U69 to U73) and 2 queued ones. The rest: 1 compaction summary written by Claude (U41, L2780), 4 subagent messages (U43 to U46, L3005 to L3057), and 22 automated heartbeat or cap-check prompts (U47 to U68, L3101 to L3818, `isMeta`) | MEASURED |
| Subject | Tom's overnight "ultrabuild" for a first macOS user (Marwan). A `cc2` cloud session, `session_01Wb7pNLKLfwGNdwkFUsvpSy`, built `@agency-agency/kit`: four native GPUIX apps (mail, chat, crm, projects) plus an `agency` CLI. The known-good commit is `a546266`: 62 of 63 checks green on a GitHub `macos-15` arm64 runner, at $160.73 of cloud credit | MEASURED in the transcript (L3813, L4018, L4024) and in the `UB` git branches |
| Tom's own shell content | Low. Two statements in the second half bear on the shell (L2913, L2841). The other Tom turns are about cloud credits, compute budgets and the handoff | MEASURED |
| Material content | High. The second half turned Tom's boundary ruling into a binding three-bucket file whose **bucket A** is the gpuix-shell scope list, with where each piece lives. It also produced the only multi-app GPUIX codebase on disk, with measured GPUIX engineering facts | MEASURED |

**Why a gpuix-shell builder should care** (INFERRED):
1. **L2913 is the source of the 10-20 "boundary" line** in BRIEF section 1: "the 'boundary' between personal desktop os shell versus common utilities ... should already be clear". On 10-14 it was ruled and written down as `UB/inputs/SEPARATION.md` (section 2.2).
2. **SEPARATION.md bucket A (A1 to A12)**, read inverted, is the gpuix-shell's responsibility list. Its "Never on the Mac" list (15 items) is the same thing: what the Linux shell owns.
3. **The kit is a working pattern library.** It is 276 files on `origin/claude/ub1` under `out/`: a theme/token module from Tom's palettes, a key map, an in-window Cmd+K palette, a window frame, a herdr wire-type file, a herdr client, a JavaScript mutation host for unit tests, a fence script, and a Bun build recipe. It is Solid, not React, so it must be ported, not imported.
4. **Measured GPUIX facts** (section 4.6 and section 6): Linux has no test renderer; there is a Bun 1.4.2 `export *` bug; the tick loop differs between Linux and macOS; Tab focus must be called by hand in 0.10.0; automation clicks are offset by padding; windows can be activated.
5. **The same-day planning docs** that the second half used as build inputs (`AL/additional/SWAY-ONLY.md`, `LAYERS.md`, `DOCK-APPS.md`) are, as of 10-14, the most complete catalogue of Tom's Sway seat: 15 feature groups S1 to S15, with keys, files, commits and states.

### 1.1 Second-half timeline

| UTC (CEST) | Line | Who | What | Shell relevance |
|---|---|---|---|---|
| 20:40:28 (22:40) | L2663 | TOM | "so cc2. you haev my full permission to use this ..." (cloud credit) | none |
| 20:41:32 | L2686 | TOM (queued) | "you seem close to understandng exactly how to use those 200 usd creditrs ..." | none |
| 20:43:11 | L2709 | TOM | "you couldn t check the official instruction from te start?? now proceed with the right way." | none (process) |
| 20:47:29 / 20:47:42 | L2757 / L2764 | TOM | "let me know when s a good time to slash-compact this then", then `/compact` | none |
| 20:49:31 | L2780 | Claude | Compaction summary. Its section 6 recaps Tom's first-half messages, including the L1861 Sway paragraph | context |
| 20:49:58 (22:49) | L2841 | TOM | Pastes the suggested compact "Next:" line, then: "...the design system is close to what was built in the local gpuix proof of concept on the linux desktop ; we port that functionality like email crm etc. there" | **yes** (design lineage) |
| 20:52:34 (22:52) | L2913 | TOM (queued) | "i m stepping off for tonight ... it s important to separate out my swaywm-only deskto shell versus the desktop appoications ..." | **yes** (the boundary) |
| 20:55 to 21:13 | L2961 to L3096 | Claude and subagent A2 | Prep workflow; vendoring herdr-web-ui demo fixtures; the input-lag, Solid-under-Node and Origin findings | GPUIX facts |
| 21:24 to 03:26 | L3101 to L3822 | heartbeats | Repo push; baseline Mac run (GPUIX 0.10.0 painted Mail on macos-15, L3264); rounds 1 to 3 | GPUIX facts |
| 03:27:53 (05:27) | L3824 | TOM | "how ready are we to do the handoff to marwan this morning?" | none |
| 03:40 to 03:58 | L3845, L3875, L3988, L4026 | TOM | Token budget: cc 250 USD cloud credit, cc2 reset expiring 22 Oct, 2 × 200 USD Console credits, Anthropic for Startups ≈1000 USD | none (budget context) |
| 04:00:25 | L4050 | Claude | Final: `~/claude-token-usage.md` rewritten | none |

---

## 2. Verbatim Tom rulings relevant to the desktop shell

### 2.1 Typed by Tom in the second half

**R-B1, the boundary ruling.** L2913, queued, 2026-10-14T20:52:34Z (22:52 CEST). TOM, full text:

> "i m stepping off for tonight, expecting fort his to run entirely unsupevised for tonight ; you know exactly waht to do. impress me , use all the tokens you need and also any remaining qwencloud and openrouter credits through pi agent for minor work. this should be considered auxiliary usage; my main goal is to get to the first user onboarding journey on macos. you can indeed
>
> if you need a recon run including git clones of the repos we ll use like gpuix etc doing so early with the
>
> it s important to separate out my swaywm-only deskto shell versus the desktop appoications like email ; herdr web ui chat ; crm and the other ones created. plus the cloudflare-side deployments ofthe agency-agency repos that need manual work and integrations on marwan's account"

- Reading (INFERRED): there are three things. The first is "my swaywm-only deskto shell": Tom's, Sway-bound, personal. The second is the desktop applications (email, herdr web ui chat, crm, "the other ones created"): shared, portable, launched by the shell rather than part of it. The third is the Cloudflare deployments.
- This is the 10-14 form of the 10-20 BRIEF line about the boundary between "personal desktop os shell versus common utilities".

**R-B2, the design lineage.** L2841, 2026-10-14T20:49:58Z (22:49 CEST). TOM, the part after his paste of the compact "Next:" line:

> "ultracode workflows enabled ; you will be the overnight supervisor assigning allthe work to the 200 usd (with 20 usd of additional allowance so that we make sure that we get to something working that marwan can run on his computer tomorrow ; that is your /goal you never write code yourself since the work is done by the exact same model as you ; we use npx to install the apps on the mac os. the design system is close to what was built in the local gpuix proof of concept on the linux desktop ; we port that functionality like email crm etc. there"

- Reading (INFERRED): Tom treats the Linux GPUIX proof of concept (`WT/design/gpuix-comparison` with the `claude-primer` look) as **the** design system. The macOS apps inherit from it. The Linux shell should therefore stay visually continuous with those same apps: same palettes, density and rail metrics.

**R-B3, process, applies to how tonight's run reports.** L2709, 2026-10-14T20:43:11Z: "you couldn t check the official instruction from te start?? now proceed with the right way." Tom's irritation was at assuming instead of reading the official source first (INFERRED lesson: read the primary docs, such as GPUIX `index.d.ts` and CHANGELOG, before claiming an API exists).

**Not shell, recorded for completeness** (budget context for the overnight orchestrator):
- L3845, 03:40:36Z: "since i m stopping the leger email (eg. my secondary claude code account) at the end of the month, want to make sure that we really use all the available tokens that are available to us on thsi one".
- L3875, 03:47:29Z: "...i get basically an additional week's worth of subscription on one of the two accts . want to be deliberate about this ...".
- L4026, 03:58:41Z: "...anthropic generously giften me 200usd to this account additional ... i do qualify for nthropic for startups package ... this is a lot of credits total! we will use them wisely ."

### 2.2 What the second half did with R-B1 and R-B2 (REPORTED from the artifacts it produced)

- Claude restated R-B1 at L3001 (20:58:38Z): "your split between the Sway-only shell (not ported), the desktop apps (ported to macOS with GPUIX, installed with `npx`) and the Cloudflare steps that need manual work on Marwan's account".
- `UB/inputs/SEPARATION.md` line 9 quotes R-B1 and R-B2 verbatim, with "marwan" replaced by "[the first user]". Lines 15 to 21 set the three buckets. The one-line version is line 21: "**A stays home, B travels by `npx`, C is a manual runbook the first user follows on his own account.**"
- Bucket A, "Tom's Sway only desktop shell" (line 17): "Rail, launcher, notifications, bar, workspace switcher, Hyprland material, the GPUIX Desktop window, Tom's desk fork chrome". It is not ported, it is a "Visual reference only", and its owner is Tom.
- Rule A (line 44): B apps "may read A's study files to match a look or a proportion ... may not import `platform.ts`, `desktop.tsx`, anything under `pkgs/desktop-shell`, or anything from the desk fork". INFERRED consequence: the import direction is shell → shared core, never apps → shell. The gpuix-shell can import shared tokens and components, and the apps must never import the shell.

### 2.3 Context: same-day shell rulings from the first half (owned by reader 06-a; quoted here so this note stands alone)

**L1861, U27, 2026-10-14T16:08:40Z.** TOM, full text, the core statement on the Sway shell:

> "agency-agency is the shared github org. it has separate implementations for pure full desktop like wayland (sway for now) desktop shell and the shared with macos that overlays
>
> special features of sway: swap kitty terminla herdr and herdr web ui translated into my own implementation.
> sway has a contextual launcher, a herdr leftbar that is disjinted and contol sway workspaces, clipboard history.. all that stuff that macos version doesn't have. this creates a clean sepaeation layer which is much appreciated but it sits at the same library fundamentally.
>
> the design prompts for two claude design web sessions should be done at some point. read @~/wednesday-oct14-midday.md for some notes on that and the geist radix or react primer and so on and so forth implementations and variatipons until we iron out completely the entire set of possibles and distill a minimla set of design elements that can cerate a definite top tier interface. the starting point is yesterday's demo's of email. crm, chat that i m using today in https://strix.tail8dd1.ts.net:8443/?ws=wGK-client-slot-2-fc7de0&pane=wGK%3Ap1&view=chat already which is great and can t wait ti use it for the full suite of projects as well
>
> making marwan a nonmember makes it so that he can become a contributor to the project.
> macos has parity with the "tray/dock" items: crm, email, projects, files, the vesence ones (resurface from investigation); this is what we build as native apps. there is the massive backdrop that has the cloudflrae.
> resurface the leger labs "one time walktrough" with it being a script of sorts that cna be followed as they save their keys.
>
> for this, it would be advantageous to use nix with brew in the most minimal nonintrusive way. agency.agency gives them access to a "shared" controlled workspace.
>
> for marwan it s an exception bcz we already hafe a snapshot of his claude and the existing implemetantion for me."

**Queued right after it** (TOM, 2026-10-14):
- L1886, 16:09:37Z: "forthe macos commonality kernel and the agency.agency account setup on the lcoudflare side of thing (to a private team worker, this is the real dogfooding)".
- L1887, 16:09:51Z: "give two workspaces by default: the agency one and his personal one."
- L1888, 16:10:24Z: "without invading into his macos desktop. this is where the diffreece lies. i give him high performance cloduflare deployed webappsthat he can use with codemode from the chat interface as well."
  - INFERRED: the converse holds on Tom's Linux seat. There the shell is *supposed* to own and "invade" the desktop. That is the difference.

**L1802, 16:00:22Z** (TOM, excerpt): "yesterday we did attempts to use gpuix to materialize a herdr web ui chat , a crm , an email tool , a backlog projects tool... all those have agency oss repos".

**L1512, 13:37:43Z** (TOM, excerpts):
- "the major breakthrough is the recent gpuix react products plus terminal that can be "mirrored to a front end""
- "...you need full visibility over every single agents that is run (like how it s done w rene at ramp) ; yoo need shared artifacts and shared databases and utilities ; behind an mcp codemode ; ... this is something that we have started doing inm y local dotfiles all the way to the hold space for dictation functionality (omarchy voice style)"

**Tom's own notes file**, `/home/tom/wednesday-oct14-midday.md` (329 lines). He pointed the session at it at L1861. These are TOM notes, MEASURED read tonight:
- Line 274: "2x esign agents end to end then one attempt per: vercel radix gh react ; claude; pure react ; claude instinctive ; cf design systems; views-c++ and the other desktop shells ; ... identifying the minimum needed set of "design constraints" (even more abstract than components) that we can get satisfactory interfaces out of yet that remain well written and unified."
- Line 325: "the bottom macos tab bar: utilities like email etc can go below. herdr tabs on the left with sway and herdr control ;"
- Line 327: "desktop env we'll whiteglove go onto those files ; then ensure the learning-as-we-go algorithm is implemented. ha that be the whole desktop. te unified claude bot in gpuix that can "ru my life""
- Line 328: "i like the idea of interchangeability between terminal and herdr-web-ui"
- Line 329: "it's utilities and skills and things that get a shortcut to that. the idea is that we "puppetteer" the desktiop interface without consuming lots of effort from the claude controlling llm. the desktop interfaces are sortcut driven."
- Same file: "client: webui, clickacke unified desktiop that is shortcut driven", and "alwayson iuniversal claude sideagent. like browser extension".

### 2.4 Older rulings the second half's input docs carry (REPORTED, with their cited source)

All quoted in `AL/additional/SWAY-ONLY.md` unless noted. I did not re-open the original transcripts behind them.

| Date | TOM, verbatim | Cited source | Bears on |
|---|---|---|---|
| 2026-10-07 | "settling for a unified interface - all through a google chroem browser, no native shell whatsoever. this is the boundary where i stand now." | `~/today/agency-thread-2026-10-14/TAXONOMY.md` B.5 (SWAY-ONLY.md:53) | Superseded by the GPUIX return on 10-13/14 and by the 10-20 order |
| 2026-10-07 | "the concept of a spotlight menu sort of thing, along with all of the contextual information that it can hold at any given moment is probably the most underused item on the modern desktop and it should be really strengthened given that we're on swaywm (with its ipc) on linux, and the vicinae product is a great foundation to start" | `~/today/2026-10-14-computer-use-study/longrun/ambient-computer.md` line 113 (SWAY-ONLY.md:113) | The launcher must be contextual |
| 2026-10-11 | mako anchored top-center | `DF/docs/client-sway-vicinae.md` (SWAY-ONLY.md:151) | Toast position (BRIEF puts toasts top-right; see gaps) |
| 2026-10-12 | "we keep vicinae actually.. i was getting a little carried away there when i said let's delete it. it's good fucntionality." | dotfiles T-2 (SWAY-ONLY.md:113) | **Conflicts with** the 10-20 "mod+d menu (vicinae remplacement)". The 10-20 order is newer and wins (INFERRED) |
| 2026-10-12 | mako progress bar in Vicinae's blue | SWAY-ONLY.md:151 | Notification styling |
| 2026-10-13 | "functional remplacement to waybar, vicinae and mako notifications" (BRIEF quotes it as "a functional remplacement to waybar, vicinae and mako") | dotfiles T-14 (SWAY-ONLY.md:152) | Scope of the shell |
| 2026-10-13 | "the way we control brightness and volume should be keypress>sway>script execution, no need to tie in vicinae if we don't have to" | `~/today/crepuscule-2026-10-14/sessions/dotfiles-rulings.md` line 56 (SWAY-ONLY.md:186) | OSD: the binds stay in Sway; the shell only displays |
| 2026-10-13 | "i digress on the hyprland parts, i m sorry. let s tick to sway window manager. less effort.." | dotfiles T-14 (SWAY-ONLY.md:200) | Sway only |
| 2026-10-14 | "in fact i m trying to do one hedr workspace is one sway wm workspace to reduce cognitive load even further" | `~/today/crepuscule-2026-10-14/sessions/codex-dotfiles-branch.md` line 36 (SWAY-ONLY.md:22) | Slot model |
| 2026-10-14 | "and having a deep sense of integation between them. and that way herdr "watiing for input" becomes sway workspace wayland urgency . and we can integarte notify-send just as easily aswell" | same file, line 37 | Attention → urgency and notification |
| 2026-10-14 | "a herdr workspace is ONE kitty terimnal correpondance. this is something i m hapy to enfordce" | `TAXONOMY.md` B.9 | Slot model |
| 2026-10-14 | "for the launcher, feature parity at least with vicinae (already enjoyed on my setup) including how it interacts w google chrome tabs is very desirable" | `~/today/2026-10-14-computer-use-study/BRIEF.md` line 43 (SWAY-ONLY.md:113) | **Launcher acceptance bar, including Chrome tab search** |
| 2026-10-14 | "exposing selected functionality tot he user and watching my behavior and selfimproving from there can onyl happen bcz we have a tight grip on the actual keypresses: sway to gpuix shortcuts and fast typing." | `~/today/agency-thread-2026-10-14/VISIBILITY-ARCHITECTURE.md` line 334 (SWAY-ONLY.md:208) | Keypress capture (S15) |
| 2026-10-14 | "i have custom shortcut ctrl M on google chroem that "isolates" the tab into a new one that gets tiled by swaywm regular" | `codex-dotfiles-branch.md` line 32 (SWAY-ONLY.md:214) | Chrome tab tear-off |
| 2026-10-14 | "whatever you just opened: i love it." (the claude-primer look) | `AL/ground/GPUIX-APPS.md`:36 step 3 | The look |
| 2026-10-14 | "i m not intersted in "native advantage" . performance is not really the thing i m looking for here." | `AL/ground/GPUIX-APPS.md`:43 step 10 | Renderer choice |
| 2026-10-14 | "it should be the "same complexity" accessing cf-hosted data for gpuix "native" windows as it is for chrome --app ones like what you showed me, right:?" (answered yes) | same | Data seam |
| 2026-10-14 | "it's not registering ctrl +\- for zooming ; was that explicitly disabled or what?" | `AL/ground/GPUIX-APPS.md`:44 step 11 | **Zoom must work in every GPUIX window** |
| 2026-10-14 | "get 3 subagents to give me side by side implementations in gpuix so that i can see them side by side. let s do email app and "desktop"" | `AL/ground/GPUIX-APPS.md`:41 step 8 | Origin of `desktop.tsx` |

---

## 3. Feature and behaviour inventory

"Keep/replace/new" is from the gpuix-shell's point of view under BRIEF section 3 (INFERRED unless a ruling is cited):
- **keep**: the script or bind stays; the shell may read it or call it.
- **replace**: a GPUIX surface takes over.
- **new**: nothing exists to replace.

"S#" refers to `AL/additional/SWAY-ONLY.md` (section 2, lines 58 to 80; details at the line given). "A#" refers to `UB/inputs/SEPARATION.md` lines 29 to 42.

| # | Feature | What exactly | Where it lives today | Keep/replace/new | Notes and sources |
|---|---|---|---|---|---|
| F01 | **Left rail: herdr workspaces drive Sway workspaces** | Persistent rail of herdr workspaces; click focuses the Sway slot; agent status per row. Tom (L1861): "a herdr leftbar that is disjinted and contol sway workspaces" | Pieces only, no persistent bar (S4, SWAY-ONLY.md:122-132): (1) Mod+I switcher, PR #565, `home/dot_local/bin/sway-workspace-switcher`, branch `feat/morning-shell`, head `7464298c`; (2) `herdr-picker`; (3) `WT/design/gpuix-comparison/platform.ts` (54 lines, the Sway adapter) and `desktop.tsx`; (4) `WT/design/claude-rail` mock; (5) views-shell C++ rail (`~/mecattaf/views-shell/SPEC.md` C25.1-C25.2) | **new** (layer-shell rail, BRIEF 3.3) | "Disjointed" = a surface apart from herdr's TUI that reads herdr and writes to Sway (SWAY-ONLY.md:130). Nobody has combined metrics, Sway adapter, herdr status and layer-shell on Sway (INFERRED there). In-app twin: fork commit `472dc0e` "rail: 220 px Chrome rail, agents first, shells folded, waiting-on-you groups, slot chip, rename guard" (MEASURED `git log` in `~/mecattaf/herdr-web-ui`) |
| F02 | Mod+I top-display workspace switcher | Fuzzel menu on eDP-1 listing that output's slots with herdr status sampled at open; second Mod+I closes only its own menu; "no Herdr focus verb, ever"; 28 tests | PR #565 (open), `~/.wt/dotfiles/morning-shell`; a runtime-only Mod4+i bind was live on the Zenbook (REPORTED T-14) | **replace** with `gpuix-shell switcher` (BRIEF 3.2) | SWAY-ONLY.md:125. Conflicts with herdr-sway-context in `binds.conf` and `flake.nix`, keep-both (SWAY-ONLY.md:96) |
| F03 | Launcher (Mod+D, Mod+Space) | Vicinae: apps, Chrome tabs via its extension, clipboard, files (Documents and Downloads only), Now Playing, Search Tray. Favourites include `applications:herdr-picker` and `clipboard:history`. Desktop entries: "Herdr workspaces", "New Herdr workspace", "Restore Herdr workspace", "Rename workspace", "Dismiss notification", "Restore notification", "Network settings" | `DF/home/vicinae.nix`, `binds.conf` | **replace** (BRIEF 1, 10-20) | Bar from 10-14: "feature parity at least with vicinae ... including how it interacts w google chrome tabs". `WT/pkgs/desktop-shell/providers.ts` gap list: "Chrome tab search still requires Vicinae's browser-extension bridge." (SWAY-ONLY.md:112). Losing Chrome-tab search is the main parity risk |
| F04 | herdr picker (Mod+Ctrl+Space) | herdr workspaces with agent status from a read-only snapshot, shown via Vicinae's dmenu protocol, focusing only Sway containers; 574 lines | `DF/home/dot_local/bin/herdr-picker` | **keep** the logic; **replace** the Vicinae dmenu front with a launcher provider (INFERRED) | SWAY-ONLY.md:111. Slot label grammar `client-slot-N-<6 hex>` lives here |
| F05 | **Contextual launcher** | "Every list knows the Sway workspace, the herdr pane and its `agent_status`, the Chrome host and the `kb` thread the screen belongs to" | Designed only: `~/today/2026-10-14-computer-use-study/DESIGN.md` line 240 and section 3; sample Ctrl+K in `WT/design/gpuix-comparison/desktop.tsx`; contract in `WT/design/claude-suite/CTRL-K-LINEAGE.md` | **new** | Tom: "sway has a contextual launcher" (L1861). CU/DESIGN.md 3.6 split: Vicinae for global summon, web UI palette in-window, a GPUIX layer-shell launcher on Sway later (SWAY-ONLY.md:276). The 10-20 order makes the GPUIX launcher the global one |
| F06 | One command catalogue (contract C4) | Stable command id, label, parameter schema, applicable context, platform tag | Vicinae desktop entries; the uncommitted GPUIX provider catalogue `WT/pkgs/desktop-shell/providers.ts` (277 lines); the fork palette rows `src/desk/shell/providers.ts` | **new** (shared registry) | SWAY-ONLY.md:248 and 5.3 step 6; LAYERS.md 6.2. The desk fork already lifted the calculator from desktop-shell `providers.ts` (commit `5c9a92a`, MEASURED) |
| F07 | Clipboard history (Mod+V) | `vicinae cmd launch clipboard:history`; policy `monitoring = true`, `ignorePasswords = true`, `preserveTagged = true`, `evictionThreshold`; the input helper is off, so no auto-paste | `DF/home/vicinae.nix`, `binds.conf`. cliphist is installed, but "Vicinae owns clipboard history; do not start a second cliphist watcher." (`DF/home/dot_config/sway/startup.conf` line 4) | **replace** (BRIEF 3.4: `wl-paste --watch` plus its own store) | S5, SWAY-ONLY.md:134-140. Vicinae's history and retention cannot be imported (desktop-shell `providerGaps`). Carry over: ignore passwords (concealed mime), tag-preserve, eviction. Stale comment: `screen-ocr-area` line 6 "cliphist keeps the result." |
| F08 | Notifications daemon | mako: started with the physical session target; anchored top-center (Tom, 10-11); Anthropic Sans; overlay layer; colours from `~/.config/theme/mako.conf`; progress bar in Vicinae's blue (Tom, 10-12); high urgency stays until dismissed; no do-not-disturb | `DF/home/vicinae.nix` `services.mako`; theme fragment in `home/themes/default.nix` | **replace** (`gpuix-shell notifications`, an `org.freedesktop.Notifications` server) | S7, SWAY-ONLY.md:149-154. Staged GPUIX daemon with DND: `WT/pkgs/desktop-shell/notifications-daemon.ts` (79 lines), `notifications.ts` (83), the client (43), plus tests |
| F09 | OSD (volume, brightness) | One replaceable popup per press, progress bar from the `value` hint | `DF/home/dot_local/bin/osd` (added `524c66f7`, 2026-10-11) | **replace** the display; **keep** "keypress>sway>script" (Tom 10-13) | The binds stay in Sway and call `volume` and `brightness`; those should call the shell CLI instead of notify-send (INFERRED) |
| F10 | Dismiss and restore notifications | Vicinae entries run `makoctl dismiss` and `makoctl restore`; Mod+o dismiss is in PR #571 (BRIEF) | `vicinae.nix`; `~/.wt/dotfiles-sway-mod-o` | **replace** with shell verbs (`gpuix-shell notify dismiss/restore`, INFERRED) | |
| F11 | Do-not-disturb | Not in the dotfiles (REPORTED DEMO-RUNBOOK.md line 310). The desktop-shell daemon has one; `desktop.tsx` line 62 has a "Do not disturb: On/Off" button and "Clear all" | `WT/pkgs/desktop-shell`; `WT/design/gpuix-comparison/desktop.tsx:62` | **new** on Sway | |
| F12 | **Attention: herdr `blocked` → Sway urgency plus one actionable notification** | User daemon polls the herdr snapshot. Only `blocked` counts; marks the visible companion urgent; one `notify-send` with an Open action back to the workspace and pane; dedups; quiet on reconnect; never switches workspace; a visit acknowledges without answering | `home/dot_local/bin/herdr-attention` (442 lines) and `home/herdr-context.nix` on branch `feat/herdr-sway-context` `c1a49b99` (unmerged; worktree `~/.wt/dotfiles/herdr-sway-context`) | **keep** the rule (contract C3); the shell's notification server receives it; the rail shows `blocked` | S2, SWAY-ONLY.md:98-107. LAYERS.md 6.2 proposes the pure rule in a shared `attention` package, with Sway urgency and the notification in the Shell |
| F13 | Mod+grave swap of kitty and web UI Chat in one tile | Hidden companion in the scratchpad; `swap container` plus focus; first swap opens Chrome on the `HerdrSwayContext` profile at the deep link with the sidebar hidden; `--choose-pane` chooser | `herdr-context` (657 lines), same branch; `rules.conf` `for_window` for `^chrome-.*-HerdrSwayContext$`; herdr `window_title = "{hostname}: {workspace}"`; 69 tests under runtime-test | **keep** (Sway script); the shell can show which view is front (INFERRED) | S1, SWAY-ONLY.md:86-96. Tom: "swap kitty terminla herdr and herdr web ui translated into my own implementation" (L1861); "i like the idea of interchangeability between terminal and herdr-web-ui" (notes:328) |
| F14 | Slot model | Mod+1..9 slots on the top panel; Mod+0 = ws 10 on the bottom panel; Mod+Return focus/create the projector; Mod+T first free slot; Mod+W parks the projector ("Chrome-like close"); Mod+Shift+T restores; Mod+Shift+N renames (`N: name`); Mod+Shift+Q detaches; Mod+Ctrl+Shift+Return herdr agents sidebar. Marks `herdr-slot-N`, `herdr-label-...`, `herdr-name-<hex>`, `herdr-closed-<n>` | `DF/home/dot_local/bin/{herdr-picker,herdr-chord,sway-workspace,herdr-projector,herdr-sway-projector}` | **keep**; the rail and switcher read the marks and labels | S8, SWAY-ONLY.md:156-162. The rail must agree with this identity grammar |
| F15 | Two-panel seat | eDP-1 top, eDP-2 bottom; kanshi `Duo`/`DuoDocked` with per-output colour temperature (`wl-gammarelay-rs`); touch on eDP-1; lid turns eDP-1 off; 3-finger swipe changes workspace; dock daemon turns eDP-2 off; Mod+Shift+P both panels off | `kanshi/config`, `input.conf`, `home.nix` `sway-local.conf`, `modules/zenbook-duo-daemon.nix` | **keep**; the shell must place surfaces per output (INFERRED: rail on eDP-1, where slots 1..9 live) | S9, SWAY-ONLY.md:164-168. Which output gets the rail, toasts and OSD is open (section 6) |
| F16 | Capture | Mod+S screen; Mod+Shift+S area plus Satty; Mod+Alt+S window (the file goes to the strix, none stays local); Mod+C colour under the cursor; `record` has no key | `screenshot`, `colorpicker` | **keep**; launcher entries (INFERRED) | S10 |
| F17 | Screen-area OCR (Mod+Ctrl+S) | slurp → grim → ssh `screen-ocr` on the strix → `http://strix:8731` model `halogen-qwen3.8-flash-next` → `wl-copy`; Esc leaves the clipboard untouched | `screen-ocr-area`, `screen-ocr` | **keep** | S6 |
| F18 | Speech from the clipboard (Mod+Ctrl+R) | `speak-clipboard` → strix speech queue | script | **keep** | S11 |
| F19 | Function row | F2/Shift+F2 theme and accent pickers (fzf in a floating kitty); F3-5 media; F6-8 volume with OSD; F9 audio route picker; Shift+F9 call recording (diarized on the strix); F10 sleep-monitors prompt; Shift+F10 pomodoro. PR #566 adds F1/F2 brightness and moves the theme pickers to Super+F2 | `binds.conf`; scripts `theme`, `theme-prompt`, `audio-route`, `media`, `volume`, `brightness`, `monitors-off`, `pomodoro` | **keep** the binds; **replace** the fzf-in-kitty prompts with launcher or menu surfaces where natural (INFERRED: theme picker, audio route) | S12, SWAY-ONLY.md:184-188 |
| F20 | Runtime theme switch | `theme` retargets `~/.config/theme` and reloads every consumer, "no rebuild" | `DF/home/dot_local/bin/theme` (added `2369f56b`, 2026-09-17), `home/themes/*.nix` | **keep**; the shell follows the pointer (BRIEF 3.5) | The desk fork and kit both carry the three palettes as data (section 4.3) |
| F21 | App chords and Chrome apps | Ctrl+N / Ctrl+Shift+N Chrome everywhere; Mod+N, Mod+Ctrl+N; Mod+E Nautilus; Mod+Shift+C claude.ai, Mod+Shift+W Gmail, Mod+Shift+Period Notion Calendar as Chrome app windows; Mod+Shift+Semicolon OBS; Mod+Escape inhibitor toggle; Mod+Shift+M desk page (PR #565) | `binds.conf`, `rules.conf` | **keep** | S13. Eleven Chrome app shortcuts were removed on 10-12 (REPORTED T-2) |
| F22 | **Strip and bell** (bar-like content) | Strip: clock plus two counts over every PC's roster (agents working, agents waiting on you); gone under 390 px; "No slot row" because "workspace switcher is Sway's". Bell: centre over an events feed (started, finished, needs your input), cap 500 | herdr-web-ui fork `identity/claude-primer`, commit `5c9a92a` (MEASURED message); `server/desk/events.ts` ("the desktop shell's notifications.ts store cut to a monotonic id") | **new** on Sway as the rail header or footer (INFERRED) | Code already flowed from the Linux shell into the fork (SWAY-ONLY.md:41). "No top bar on the Linux head" (BRIEF) puts this in the rail |
| F23 | **Bottom dock or tab bar of utilities** | Tom notes:325: "the bottom macos tab bar: utilities like email etc can go below. herdr tabs on the left with sway and herdr control". DOCK-APPS.md:30: each dock app is "one entry in the bottom bar on Sway" (INFERRED proposal). LAYERS.md 6.6 line 339: "The dock's surface is Shell only" | Nowhere on Sway | **open**: new or rejected | **Unresolved.** BRIEF has no bottom bar and says "no top bar". Section 6 G1 |
| F24 | **Files explorer** | Jobs: see a project's repos and library folder and agent output; open Markdown, code and images natively; Changes (working tree, staged, commit range); attachments from mail and CRM; hand a file to an agent as a chip. Screens: a rail with My files / Projects / Connections, list and grid, viewer (md, code, diff, image), Changes tab | Nothing native. Upstream herdr-web-ui `src/components/FilesDialog.tsx` (73 lines, per pane, read-only; `/api/fs/*`, `/api/pane/files`); GPUIX `disktree` (React on Node, treemap, `~/Downloads/gpuix/disktree/src/{app.tsx,core.ts,scan-worker.ts}`) | **new** (`gpuix-shell files`, BRIEF; Tacit Pinax look) | DOCK-APPS.md 5.5, lines 280-302. GPUIX has `<code>`, `<diff>`, `<markdown>`, `<img>`, `<virtual-list>`; no folder picker (issue #82); no PDF element (INFERRED). Tom named "files" at L1861 |
| F25 | Agents / herdr chat app | Rail: "Waiting on you" groups first, then agent workspaces as tasks with a state dot, shells folded; chat lens; prompt card replaces the composer | Desk fork (web); kit `out/kit/src/apps/chat/*` (GPUIX Solid, macOS-proven) | **launch, do not build** (bucket B) | DOCK-APPS.md 5.1, lines 167-188. The shell rail can link to it via the deep-link grammar (contract C2) |
| F26 | Mail, CRM, Projects apps | Native GPUIX windows over the Workers | `UB` `out/kit` (macOS); Chrome studies in `WT/design/claude-{mail,crm,projects}` | **launch, do not build** (bucket B; BRIEF 3.8) | SEPARATION.md B1-B4 |
| F27 | Calculator in the palette | No evaluation, no process | `WT/pkgs/desktop-shell/providers.ts`; fork `src/desk/shell/providers.ts` | **keep** as a launcher provider | Commit `5c9a92a` |
| F28 | **Zoom in GPUIX windows** | Ctrl/Cmd+= in, Cmd+- out, Cmd+0 reset; scale 0.8 to 1.6, step 0.1; reflows | Kit `out/kit/src/core/theme.ts`:146-160 | **new** for the shell's ordinary windows (files, controls) | Tom found it missing (10-14). GPUIX has no content-scale API, so this is at the application level (APPS.md:103) |
| F29 | Keypress and window-event capture | Interaction log; agents never hold the Sway socket | Designed: CU/DESIGN.md section 2 | **new** (later) | S15, SWAY-ONLY.md:208 |
| F30 | Sway and herdr rename join | Rename on either side reaches the other | CU/DESIGN.md 1.5 | **new** (later) | S15 |
| F31 | Stash | Three binds collecting the primary selection and screen regions for the next request | CU/DESIGN.md 3.1 | **new** (later) | S15 |
| F32 | "Ask Claude" quick entry | From the launcher into a new herdr workspace | CU/DESIGN.md 3.5 | **new**: a launcher action (INFERRED) | S15 |
| F33 | Hint layer on `f`; rare "challenge" | A commitment coming due, shown as one notification | CU/DESIGN.md 3.2 | **new** (later) | S15 |
| F34 | Floating notes / doc editor | Claude-Docs-style local editor with vim on owned Markdown | REPORTED `vesence-product.md` lines 94 and 139 | **new** (later) | S15 |
| F35 | Chrome Ctrl+M tab tear-off tiled by Sway | | Not in the dotfiles (MEASURED by SWAY-ONLY `git grep`) | **new** (Sway rule, not GPUIX) | S15 |
| F36 | Hold-space dictation (omarchy voice style) | Named by Tom at L1512 | Not located in this session | **new** or **keep** (check dotfiles) | Section 6 G9 |
| F37 | Network menu | Desktop entry "Network settings" (Vicinae) → `fzf-nmcli` | `DF/home/dot_local/bin/fzf-nmcli`, `vicinae.nix` | **replace** with a GPUIX wifi menu (BRIEF: "for wifi menu, or bluetooth pairing menu") | Nothing in this session beyond the entry name |
| F38 | Brightness keys | XF86 keys with 2% steps on Shift; F1/F2 in PR #566; three Vicinae brightness entries | `home.nix` `sway-local.conf`; PR #566 head `894b1cb4` | **keep** binds; OSD via the shell | S9, S12 |
| F39 | Capability table, "declared, never assumed" | Every capability probed; an unavailable one renders a visible unavailable state | LAYERS.md 6.3 (lines 265-299), rule R3 | **new**: the shell's controls should show unavailable states (e.g. no BlueZ) (INFERRED) | Views-shell lineage |
| F40 | Deep-link grammar (contract C2) | `?machine=<pc>&ws=<id>-<slug>&pane=<pane>&view=chat\|agents\|terminal&...&sidebar=hidden\|shown` | `~/mecattaf/herdr-web-ui/src/lib/deepLink.ts` lines 1-30 (REPORTED by SWAY-ONLY.md:93) | **keep**; rail and notification actions use it | Tom's daily link (L1861) has `ws=wGK-client-slot-2-fc7de0&pane=wGK%3Ap1&view=chat` |

**Shell-only scope as the second half's inputs wrote it** (`AL/additional/LAYERS.md` 6.4, lines 301 to 311, REPORTED):
- the contextual launcher;
- the herdr left rail, "disjinted" from windows, that drives Sway workspaces;
- clipboard history;
- the kitty and chat swap in one tile, with urgency and actionable notifications;
- the bar, the dock as a layer-shell surface, notifications and OSD;
- kitty projectors into a remote herdr;
- the Mod+I switcher, F-key brightness and seat-level binds;
- multiseat and anything that needs Sway IPC.

**What the Linux shell owns, read off the "never on the Mac" list** (`UB/inputs/SEPARATION.md` lines 110 to 128). Inverted, INFERRED:
- Sway IPC;
- the rail as a surface outside any app window;
- a global summon key and launcher;
- a notification daemon;
- layer-shell bars;
- keypress and window-event capture;
- clipboard history, the stash and the hint layer;
- the Anthropic fonts and the Claude-named palettes.

---

## 4. Design values

### 4.1 Rail geometry (MEASURED `WT/design/claude-rail/PROPORTIONS.md` lines 5-17; derived from the views-shell C++ rail)

| Dimension | Value (logical px) | C++ source cited there |
|---|---|---|
| Rail width | 220 | views-shell SPEC.md C25.1 |
| Strip horizontal inset | 12 per side | `layout_constants.cc:42` |
| Strip top inset | 12 | `layout_constants.cc:44` |
| Workspace row | 196 × 30 | `layout_constants.cc:38` |
| Row gap | 2 | `unpinned_tab_container_view_layout.cc:19` |
| Row corners | 8 | `layout_constants.cc:36` |
| Row content inset | 8 horizontal / 6 vertical | `vertical_tab_style_views.cc:135` |
| Icon design width | 16 (the herdr status glyph slot) | `tab_view_vertical_layout.cc:24` |
| Child spacing | 4 | `tab_view_vertical_layout.cc:26` |
| Close affordance | on active, hovered or focused rows | `tab_view_vertical_layout.cc:171` |
| Toggle | sidebar show/hide by Ctrl/Command+I in the mock; the real Mod+I is a separate compositor bind | PROPORTIONS.md:23 |

- The same numbers were adopted as kit tokens: `railWidth: 220, railRowHeight: 30, railInset: 12, railGap: 2, railRadius: 8` (MEASURED `UB` `out/kit/src/core/theme.ts`:124-134).
- SEPARATION.md A2 line 32 records them as "the rail metrics (220 px wide, 30 px rows, 12 px insets, 2 px gaps, 8 px corners)". They "survive only as shared tokens".
- Note: BRIEF section 3.3 says the rail's exclusive zone is 56 collapsed and 220 expanded. The 56 px collapsed width is not in this session's material (section 6, G2).

### 4.2 Density and controls (MEASURED, kit `out/kit/src/core/*` on `origin/claude/ub1`)

| Token | Value | File:line |
|---|---|---|
| bodySize | 13 | theme.ts:130 |
| monoSize | 11 | theme.ts:131 |
| lineHeight | 1.6 | theme.ts:132 |
| controlHeight | 32 | theme.ts:133 |
| Button | height 26, padding L/R 8, radius 6, border 1, label 12 px sans, `whiteSpace: nowrap`; hover = `hover` token | frame.tsx:28-66 |
| Mode badge | height 22, padding 8 | frame.tsx:69-80 |
| Narrow layout breakpoint | 900 px | frame.tsx:12 |
| Window default | 1200 × 800, min 720 × 500, `windowBackground: 'opaque'`, `appId: agency.agency.<app>` | window.ts:32-45 |
| Zoom | `SCALE_MIN 0.8`, `SCALE_MAX 1.6`, `SCALE_STEP 0.1`, every px through `px(n, scale)` | theme.ts:146-162 |
| Herdr chat sidebar look | Grouped by herdr workspace (bold label plus status dot and word), rows = agent task title plus `harness ● state`; selected row filled with selection blue, radius ≈8; filter field "Filter (/)" at top | MEASURED by eye: `/home/tom/marwan/zero-to-one-2026-10-14/ultrabuild/screens/chat.png` (native GPUIX on macOS, dark theme, system font). The closest existing native render of a herdr rail |

### 4.3 Palettes (MEASURED. The kit's `out/kit/src/core/theme/palettes.json` has the same values as `UB/design/claude-primer/src/palettes.json`, with `brand` renamed `warm`; I compared them field by field. The primer file also carries `ansi`, `gtk`, `claudeCode`, `cursor`, `cursorText`, `insertHint`, `tabIndicator` and `catppuccinFlavour` blocks that the kit dropped and the shell may want. I checked noir against `DF/home/themes/noir.nix` lines 16-57: identical)

| Role | noir (default) | dark (claude-dark) | light (claude-light) |
|---|---|---|---|
| ground.base / desktop / dim / raised | #000000 / #000000 / #000000 / #000000 | #1A1A1A / #20201F / #151515 / #20201F | #F9F9F7 / #F0EFEC / #F3F3F0 / #FFFFFF |
| fg / fgDim | #EAECF0 / #D3D7DE | #EAECF0 / #D3D7DE | #131313 / #52514E |
| comment / muted | #818898 / #45475a | #818898 / #52514E | #6E7687 / #A5A49A |
| border active / inactive / urgent | #555451 / #373735 / #F47B85 | #555451 / #373735 / #F47B85 | #A5A49A / #D2D1C7 / #B80A18 |
| accent | #70B8FF | #70B8FF | #0051C2 |
| selection bg / fg | #264F78 / #EAECF0 | #264F78 / #EAECF0 | #CDE2FB / #131313 |
| red / green / yellow / orange | #F47B85 / #9BE963 / #f9e2af / #FBAD60 | same | #B80A18 / #008000 / #A66A00 / #B24A00 |
| blue / cyan / magenta | #70B8FF / #5EEDED / #CC7BF4 | same | #0051C2 / #007F80 / #8100C2 |
| warm (= `brand` in noir.nix, "Anthropic clay") | #D97757 | #D97757 | #D97757 |

**Derived roles** (MEASURED `theme.ts`:85-120). A gpuix-shell token mapping can copy these:
- `canvas` = light ? base : desktop.
- `surface` = raised; `subtle`/`panel` = dim.
- `ink` = fg; `secondary` = fgDim; `muted` = light ? fgDim : comment.
- `border` = border.inactive; `borderStrong` = border.active.
- `focus`/`accent` = accent.
- `primary` = light ? #A74B2F : #D97757; `onPrimary` = light ? #FFFFFF : #131313.
- `hover` = noir ? border + '55' : subtle. On noir, hover is a translucent border tint, not a lighter surface.
- `positive` = light ? #284F42 : #B8D5C9; `danger` = light ? #A12F36 : #F47B85; `warning` = orange; `info` = blue.
- Agent states: `stateIdle` = comment, `stateWorking` = blue, `stateBlocked` = orange, `stateDone` = green.

### 4.4 Agent status vocabulary

- herdr protocol 22: `export type AgentStatus = "blocked" | "done" | "idle" | "unknown" | "working" | (string & {});`. Keep the open-ended member and never narrow it (MEASURED `UB` `out/kit/src/apps/chat/herdr-types.ts`:19-20, copied verbatim from `devswha/herdr-web-ui@42c6332` `shared/herdr-api.generated.ts`, MIT).
- BRIEF glyphs: blocked ◉, working ◐, done ●, idle ✓, unknown ○.
- Kit colours (above): blocked = orange #FBAD60, working = blue #70B8FF, done = green #9BE963, idle = comment #818898.
- The attention rule counts only `blocked` as "needs you" (S2).

### 4.5 Fonts

- Tom's: "Anthropic Sans", "Anthropic Serif", "AnthropicMono Nerd Font" (BRIEF); glyph font "Anthropicons".
- The PoC `WT/pkgs/desktop-shell/theme.ts` names "Anthropic Sans", "Anthropic Mono", "Anthropic Serif" (REPORTED `UB/inputs/RECON.md`:110). **Note the mono family name differs from BRIEF's "AnthropicMono Nerd Font"**. Check the real fontconfig family name before hard-coding (section 6, G6).
- GPUI resolves an unknown family through a stack ending in Helvetica and Arial; `.SystemUIFont` maps to `.AppleSystemUIFont` on macOS (REPORTED RECON.md:93, from `remorses/zed@81c99f8` `crates/gpui/src/text_system.rs`).
- 0.10.0 has no `registerFont`; 0.11.0 adds `registerFont(bytes)` (BRIEF; REPORTED RECON.md:42 as an unreleased changeset on 10-14).
- On Linux the Anthropic faces are installed system-wide (`modules/common.nix fonts.packages`, BRIEF), so family names should resolve without `registerFont` (INFERRED).
- The kit used `.SystemUIFont` / `Georgia` / `Menlo` because the Anthropic faces "are not licensed for a third party's Mac" (`UB/design/SOURCE.md`). That reason does not apply to Tom's own seat.

### 4.6 Timings and loop facts

| Item | Value | Source | Label |
|---|---|---|---|
| `render()` frame loop | 8 ms (`startFrameLoop()` from `@gpuix/native/runtime`) | `UB` `out/kit/src/core/window.ts`:1-5; RECON.md:18 | REPORTED |
| desktop-shell tick on Linux | `setInterval(() => { if (!native.tick()) void close(); }, 500)` after `createRenderer(); native.init(options)`, with the comment "Linux GPUI owns its UI thread; avoid the stock 8ms JS tick loop." | `WT/pkgs/desktop-shell/ui.tsx`:1331-1337 | MEASURED |
| gpuix-comparison tick | `setInterval(()=>{if(!native.tick())process.exit(0)},500)` | `WT/design/gpuix-comparison/main.ts`:10 | MEASURED |
| What the tick means per OS | "On macOS `tick()` is the AppKit event pump", so 500 ms means input lag there. On Linux GPUI runs its own UI thread (comment above) | RECON.md:18; `/tmp/claude-1000/-home-tom-today/56e498e4-f44d-40bd-8caa-6f3f54587411/scratchpad/RECONCILE-NOTES.md`:8 | REPORTED |
| macOS frame pacing | Issue #91: frames wait for the 8 ms JS tick instead of vsync (about 45 fps when scrolling) | RECON.md:43 | REPORTED |
| desktop-shell bar status refresh | clock plus status every 15000 ms | `WT/pkgs/desktop-shell/ui.tsx`:189-192 | MEASURED |
| Automation bounds query timeout | 2 s (fails headless) | `UB` `out/specs/spike.md`:128, 149 | MEASURED there |
| Chat live request timeout | `LIVE_TIMEOUT_MS = 10_000` | `out/kit/src/apps/chat/client.ts`:19 | MEASURED |
| Desk events feed cap | 500 | fork commit `5c9a92a` | MEASURED |
| Smoke hold (the kit's onboard check) | 8000 ms | `out/kit/src/core/launch.ts`:19 | MEASURED |

### 4.7 GPUIX 0.10.0 window options (REPORTED `UB/inputs/RECON.md`:88, from `index.d.ts` in the tarball)

- `title`, `appName`, `width`, `height`, `minWidth`, `minHeight`, `resizable`, `fullscreen`, `transparent`, `titlebarTransparent`;
- `windowBackground` (`opaque` | `transparent` | `blurred`);
- `trafficLightX/Y`;
- `focus` (false opens behind);
- `show` (false opens hidden, then `activateWindow()`);
- `appId` (Wayland/X11 only);
- `layerShell` (Wayland only).

BRIEF records the layerShell shape as `{namespace, layer, anchor, exclusiveZone, margin, keyboardInteractivity}`.

---

## 5. Reusable code and data with exact paths

### 5.1 From the second half's build (Solid on GPUIX 0.10.0, macOS-proven; port to React, do not import)

Read with `git -C /home/tom/agency-agency/ultrabuild show origin/claude/ub1:<path>`. The tip is `c742887` "ub1: final ledger". Known-good kit: `a546266`. Licence: package says MIT (`out/kit/package.json`). The chat wire types are MIT from devswha.

| Path | What | Reuse for gpuix-shell (INFERRED) |
|---|---|---|
| `out/kit/src/core/theme.ts` (162 lines) + `theme/palettes.json` | Palette → role tokens; metrics; fonts; zoom math | The shell's `tokens.ts`. Swap the source to `~/.config/theme/gpuix-shell.json` and the fonts to the Anthropic families |
| `out/kit/src/core/keys.ts` (136) | GPUI keystroke parser (`"cmd-k"`, `"cmd--"`), `matches()` with Cmd→Ctrl on non-darwin, `=`/`+` layout handling | Launcher and window key maps. On Sway, Super is the compositor's, so in-window keys use Ctrl |
| `out/kit/src/core/palette.tsx` (111) | In-window command palette: filter as typed, Enter runs the first match, Escape closes and **restores the previously focused element** via `renderer.getFocusedElementId()` / `focusElement()` | Launcher list behaviour and focus restore |
| `out/kit/src/core/frame.tsx` (257) | Window frame: mode badge, theme menu, refresh, zoom label, notice strip, error banner, narrow back control; every interactive element carries `role`, `aria-label`, `testId`, `aria-id` | Pattern for the shell's ordinary windows (files, controls) |
| `out/kit/src/core/window.ts` (129) | One window per process (`ONE_WINDOW_PER_PROCESS` guard); `__napiBindingTarget === 'native'` check; Tab → `focusNext`/`focusPrevious` (0.10.0 does not move focus by default); `onUncaughtError` to stderr; ready line after the first frame | Same guards in each `gpuix-shell <surface>` process |
| `out/kit/src/core/launch.ts` (50) | `activateWindow()` once after the first frame (macOS) | Not needed on Sway for layer-shell; possibly for the files window |
| `out/kit/src/core/testing/fakehost.ts` | **A JavaScript `MutationHost`** keeping the retained tree from `applyBatch` (createElement, appendChild, insertBefore, setStyle, setText, setEventListener, setRoot, setCustomProp, destroyElement); `root.dispatch({elementId, eventType, value})` | **The Linux unit-test surface** for `bun test` without a compositor (spike.md:130-140). It should work for `@gpuix/react` too, since both adapters go through `@gpuix/native/host` (spike.md:187, INFERRED for React) |
| `out/kit/src/apps/chat/herdr-types.ts` | herdr protocol-22 wire types (AgentInfo, AgentStatus, ...), MIT header kept | Typing `herdr api snapshot` reads in the rail (check field parity with `herdr api schema` first) |
| `out/kit/src/apps/chat/{model.ts 446, store.ts 482, Sessions.tsx 144, Lane.tsx 189}` | Session grouping, state dots, chat lane | Rail grouping logic ("Waiting on you" first, shells folded) |
| `out/kit/src/apps/chat/client.ts` (268), `loopback.ts`, `live-socket.ts` (325) | GET-only loopback client to the herdr web UI server `127.0.0.1:7317`: `/api/health`, `/api/session`, `/api/pane/conversation`; ETag; stale-answer drop; ignores env proxies | Only if the shell reads the web UI server instead of the herdr CLI (BRIEF says the CLI) |
| `out/kit/scripts/fence.mjs`, `test/fence/fence.test.mjs` | Import/footprint fence over a source tree | Invert it: a fence that apps never import `pkgs/gpuix-shell` (SEPARATION rule A) |
| `out/kit/scripts/build.mjs` | Bun build of Solid apps with `@gpuix/native` external | Compare with the React build. The spike recipe is below |
| `out/specs/spike.md` (207 lines) | Measured answers: Linux has no `TestGpuixRenderer` ("Linux builds have no test-support because wgpu cannot read a rendered image back yet", line 122); automation `getAllText` works but bounds/testId lookups time out headless (149-156); Bun 1.4.2 `export *` crash plus a plugin workaround (44-99); React vs Solid feature parity (183-192) | **Read before writing tests.** The headless findings were on a VM with no display. Under `runtime-test --render-node` with a real Wayland compositor, bounds may work (untested, section 6) |
| `out/DECISIONS.md` (21 lines) | Window-position finding: "GPUIX 0.10.0 centres new windows but has no screen size or resize API" (lines 18-21) | Irrelevant for anchored layer-shell surfaces; relevant only for the files window, which Sway tiles anyway |
| `ci/mac-results` branch, `runs/*/screenshots/*.png` (176 PNGs); `/home/tom/marwan/zero-to-one-2026-10-14/ultrabuild/screens/{chat,crm,mail,projects,r3-*}.png` | The only native GPUIX renders of the Claude look outside Linux | Visual reference only. Marwan containment: do not copy them into dotfiles |

### 5.2 Earlier code the second half pointed at (MEASURED line counts tonight)

- **`WT/pkgs/desktop-shell/`** (Solid, Hyprland-bound, uncommitted; 3,163 lines in all):
  - `ui.tsx` 1338;
  - `controller.ts` 238 + test 175;
  - `providers.ts` 277 + test 131;
  - `notifications-daemon.ts` 79, `notifications.ts` 83, `notifications-client.ts` 43 + three tests;
  - `singleton.ts` 73;
  - `theme.ts` 149 (with a theme-file watcher);
  - `applications.ts` 102;
  - `main.ts` 59;
  - `build.ts` 28.
- **`WT/design/gpuix-comparison/`**:
  - `platform.ts` 54 + `platform.test.ts` 27: the Sway capability adapter, top display `eDP-1` only, "Focus happens only after an explicit user click, with identity/output revalidation" (REPORTED README);
  - `desktop.tsx` 67: Ctrl+K sample, Applications panel, notifications with DND, "You're all caught up.";
  - `email.tsx` 94;
  - `main.ts` with the 500 ms tick.
  - The second half's copy at `UB/design/gpuix-comparison/` is identical in name (copied 10-14, per `UB/design/SOURCE.md`).
- **`WT/design/claude-rail/`**: the rail mock, React + Primer, `smoke.mjs` asserting 220/196/30/12/2/8; Session/Windows/Notes views; rename; filter. `WT/design/claude-shell-study/`: launcher, notifications, controls, workspace switcher studies (SOURCE.md labels it "the desktop shell").
- **`WT/design/claude-suite/`**: `REQUIREMENTS.md`, `DESKTOP-REQUIREMENTS.md` (IDs CORE, VIS, A11Y, PORT, DES, CAL), `CTRL-K-LINEAGE.md`, `VIMIUM-LINEAGE.md`, `TITLE-LINEAGE.md`, `DESKTOP-MEMORY-PERSPECTIVE.md`, `RENDERER-DECISION.md`, `reference-palette.json`, `server.mjs` (the loopback bridge, port 4188). The second half's copy is in `UB/design/claude-suite/`.
- **herdr-web-ui fork** `~/mecattaf/herdr-web-ui`, branch `identity/claude-primer`, no fork remote:
  - commit `472dc0e` (rail);
  - commit `5c9a92a` (palette providers, strip, bell, `/api/desk/events`);
  - `src/lib/deepLink.ts`;
  - `src/components/FilesDialog.tsx` (73 lines);
  - `src/desk/shell/providers.ts`, `paletteRows.tsx`, `useDeskPaletteKey.ts`;
  - `server/desk/events.ts`.
- **Unmerged dotfiles Sway work**: `feat/herdr-sway-context` `c1a49b99` (`herdr-context` 657 lines, `herdr-attention` 442 lines, `home/herdr-context.nix`, `docs/herdr/sway-context{,-validation}.md`, 69 tests); PR #565 `feat/morning-shell` `7464298c` (switcher, 28 tests); PR #566 `894b1cb4` (F1/F2 brightness).
- **GPUIX upstream** `~/Downloads/gpuix`:
  - `disktree/` (React-on-Node file treemap: the nearest native start for Files);
  - `examples/chat.tsx` (React chat, REPORTED DOCK-APPS.md:187);
  - `packages/native/src/renderer.rs` lines 7299-7300 and 7499-7504 (layer-shell is `#[cfg(target_os = "linux")]` only, REPORTED SWAY-ONLY.md:40, 132).

### 5.3 Planning documents the second half consumed (REPORTED unless noted; all exist, MEASURED `ls`)

| File | Lines | Use for the shell |
|---|---|---|
| `AL/additional/SWAY-ONLY.md` | 301 | S1-S15 catalogue (keys, files, commits, state); contracts C1-C6 (239-250); plan steps (258-269); unknowns with defaults (271-281) |
| `AL/additional/LAYERS.md` | 513 | Seven tiers (221-235); what lives where (237-263); **platform contract TS sketch** with the `Capabilities` interface (265-299); shell-only list (301-311); dock parity (323-339); boundary rules R1-R9 (341-355) |
| `AL/additional/DOCK-APPS.md` | 455 | Agents app spec (167-188); **Files app spec** (280-302); dock set of seven (30) |
| `AL/ground/DESKTOP-INVENTORY.md` | 429 | Section 3 command-line tools, 3.6 seat controls, 9 Sway shortcuts listed as excluded |
| `AL/ground/GPUIX-APPS.md` | 274 | 13/14 Oct history (28-60); renderer rulings; the Desktop window (162-166) |
| `AL/ground/MACOS.md` | 383 | 4.2 GPUIX capabilities and limits; 7.1 component map of Tom's dotfiles |
| `UB/inputs/SEPARATION.md` | 138 | The A/B/C split; "never on the Mac" (110-128); fences (132-138) |
| `UB/inputs/RECON.md` | 251 | GPUIX 0.10.0 facts, unreleased changesets (36-46), window options (86-93), PoC build notes (100-123) |
| `UB/inputs/APPS.md` | 503 | Common test ids and smoke pattern (153-170); keys and palette contract (133-150); event-loop rule (94) |
| `/tmp/claude-1000/-home-tom-today/56e498e4-f44d-40bd-8caa-6f3f54587411/scratchpad/RECONCILE-NOTES.md` | 15 | Four findings: input lag, Solid server build, read-only mail token, herdr-web-ui Origin handling. Scratch; may disappear |

### 5.4 Bun build recipe (MEASURED in the cloud VM, `UB` `out/specs/spike.md`:59-90)

- `Bun.build({ target: "node", format: "esm", external: ["@gpuix/native", "@gpuix/native/*"], define: { "process.env.NODE_ENV": "\"production\"" }, plugins: [expandExternalStar, solidPlugin] })`.
- `expandExternalStar` rewrites `export * from "@gpuix/native..."` inside `@gpuix/solid/dist/{index,testing,automation}.js` into named re-exports. Without it Bun 1.4.2 throws `ReferenceError: host is not defined` at run time.
- `define NODE_ENV` makes Bun pick the production universal renderer.
- For `@gpuix/react` 0.11.0 the same bug may or may not apply (untested). Run the built bundle once as a smoke test.

---

## 6. Gaps and unknowns

| Id | Gap | Default I would take (INFERRED) |
|---|---|---|
| G1 | **Bottom dock vs left rail only.** Tom's 10-14 notes say "the bottom macos tab bar: utilities like email etc can go below. herdr tabs on the left with sway and herdr control" (notes:325). LAYERS.md 6.6 puts a layer-shell dock on Sway. BRIEF (10-20) has a left rail and "no top bar", and no dock | Put utility launchers (Mail, CRM, Projects, Agents, Files) as a footer group of the left rail. Record a bottom dock as an X-option in ASSUMPTIONS.md |
| G2 | Rail collapsed width 56 (BRIEF 3.3) is not in any 10-14 material; the 10-14 geometry is 220 only | Keep 220 as the expanded geometry from PROPORTIONS.md. 56 = 12 + 32 + 12 (inset, control, inset) is a guess |
| G3 | **Vicinae: keep (10-12) vs replace (10-20).** Parity bar (10-14) includes Chrome tab search, which needs Vicinae's browser-extension bridge | Replace per 10-20, but list Chrome-tab search as unmet parity until a bridge exists. Do not delete `vicinae.nix`; gate it with the `programs.gpuixShell.enable` option (BRIEF says never both) |
| G4 | Toast position: mako is top-center by Tom's 10-11 choice; BRIEF says toasts overlay top-right, 390 wide | Follow BRIEF, but make the anchor a theme/config value; note Tom's top-center precedent in ASSUMPTIONS |
| G5 | **Linux headless testing.** `TestGpuixRenderer` is absent on Linux; automation bounds and testId lookups timed out on a no-display VM. Not tried under a real compositor (`runtime-test --render-node`) | Unit tests run on the JS mutation host (the fakehost pattern). Compositor smokes assert what the automation channel returns (`getAllText`, `getPaintedText`; try bounds and testId under a real compositor, since they may work there) plus a screenshot taken with `grim` inside the test compositor. Layer-shell surfaces do not appear in `swaymsg -t get_tree`, so check them by screenshot or by the process's own ready line. Claim pixel checks only if they really ran |
| G6 | Mono family name: BRIEF "AnthropicMono Nerd Font" vs PoC `theme.ts` "Anthropic Mono" | Check `fc-list : family` before hard-coding; keep the family in the theme JSON |
| G7 | **Tick loop on Linux.** desktop-shell deliberately ticks every 500 ms ("Linux GPUI owns its UI thread"). The kit uses the 8 ms `render()` loop. Whether 500 ms adds input lag or animation stutter on Linux is unmeasured | Start with `render()` owning the loop as @gpuix/react does by default; fall back to the 500 ms pattern only if CPU use is a problem; measure (`requiresTick()`) |
| G8 | Tab focus: 0.10.0 needs `renderer.focusNext()` by hand; a changeset makes it default "after 0.10.0" | Check 0.11.0's CHANGELOG; keep the manual handler if unsure (harmless) |
| G9 | Hold-space dictation "omarchy voice style" (L1512) | Not located in this session; another reader or the dotfiles may have it. Treat as a launcher or shell feature to list, not build tonight |
| G10 | Click-padding offset: in 0.10.0 automation clicks on padded elements land shifted by the padding (`bounds-include-padding` changeset) | Give `testId` to unpadded children or click centres; check 0.11.0 |
| G11 | herdr-web-ui Origin rule: RECONCILE-NOTES.md:11 says "The app must never send an `Origin` header"; APPS.md:283 says send `Origin: http://127.0.0.1:7317` on every request | Only matters if the shell calls the web UI server. Read `vendor/herdr-web-ui/server/access.ts` first. BRIEF uses the herdr CLI, so avoid the server |
| G12 | Clipboard security: a token copied from a console carries no concealed mark; Vicinae's macOS server skips only concealed/transient items (SWAY-ONLY.md:140). Same risk on Linux with `wl-paste --watch` | Honour `x-kde-passwordManagerHint` and similar mime hints; add a "pause history" toggle; keep Vicinae's `ignorePasswords` semantics |
| G13 | `herdr-attention` poll interval is "a short fixed poll" (value not in this session) | Read the branch script before wiring; do not double-notify if both it and the shell run |
| G14 | Which output gets the rail, toasts and OSD on the Duo (eDP-1 top with slots 1..9; eDP-2 bottom = ws 10 Chrome) | Rail and switcher on eDP-1 only (matches PR #565 "top display only"); toasts and OSD on the focused output |
| G15 | Second-half Tom quotes on design are thin; the compaction summary (L2780) paraphrases some first-half messages | Every TOM quote in 2.1 and 2.3 was read from the raw jsonl lines given (MEASURED). Section 2.4 rows are REPORTED from planning docs and not re-checked against their original transcripts |
| G16 | Solid vs React: every native app proven so far (PoC, kit) is Solid; BRIEF picks React | The spike found no React-only need (spike.md:192) and the same element set in both (187); the port is mechanical, but nothing React has been painted on Sway by Tom's tooling yet (INFERRED from this session) |
| G17 | `@gpuix/native` versions: the 10-14 material is 0.10.0 throughout; tonight's build pins 0.11.0 | Re-check `layerShell` option names and `registerFont` against `@gpuix/native@0.11.0/index.d.ts`, not this note |
| G18 | Contract C4 (one command registry with platform tags) is proposed, not built anywhere | gpuix-shell can define it (`src/registry.ts` in BRIEF) so the desk palette can later read it; keep ids stable |

**What I did not do.**
- I did not open the first half's turns beyond the context lines cited in 2.3; reader 06-a owns them.
- I did not re-read the original Codex transcripts behind the REPORTED rulings in 2.4.
- I did not run any GPUIX code.
- I checked palettes only for noir against `home/themes/noir.nix`; dark and light were not compared to their `.nix` files.
