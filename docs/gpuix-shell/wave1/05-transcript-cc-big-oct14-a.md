# 05 · Transcript read: Claude `cc` session 56e498e4 (2026-10-14/15), FIRST HALF

**Reader** one wave-1 reader of the overnight gpuix-shell build, 2026-10-20/21. Read-only; this file is the only thing written.
**Source** `/home/tom/.claude/projects/-home-tom-today/56e498e4-f44d-40bd-8caa-6f3f54587411.jsonl` (12,484,280 bytes, 4,026 jsonl lines, cwd `/home/tom/today`, `permissionMode: bypassPermissions`). 105 Tom turns in all; this note covers turns [0]–[52] (jsonl L5–L2440, 2026-10-14 08:52Z to 20:28Z, i.e. 10:52 to 22:28 CEST). The second half ([53]–[104], L2503–L4026, 20:30Z to 03:58Z next day) belongs to the sibling reader (05-…-b).
**Labels** MEASURED = I read it in the jsonl or the file tonight (pointer given). REPORTED = a workflow output written during this session says so (path given); those agents' claims were not re-checked by me. TOM = Tom's own words, verbatim, typos kept; timestamps are the jsonl `timestamp` (UTC) with CEST in brackets. INFERRED = my reading.
**Pointer format** `jsonl:L<n>` = line number in the 56e498e4 jsonl. `turn [n]` = index from the `--user-only` helper. Other files: `path:line`.
**Helper used** a timestamped variant of `transcript-text.py` (adds jsonl line + timestamp) kept at `/tmp/claude-1000/-home-tom-tuesday-oct20/94d008d7-4112-4bf7-92cd-2de4eab69681/scratchpad/r05/tt.py`; its outputs `users.txt` and `all.txt` sit beside it.

---

## 1. What this source is

**Shape of the session (MEASURED).** One long `cc`-seat Claude Code session on the strix, Opus, ultracode workflows on. It has three distinct chapters in its first half:

| Turns | jsonl | Time (UTC) | Chapter | Shell relevance |
|---|---|---|---|---|
| [0]–[24] | L5–L830 | 08:52–11:14 | Sodimo close-out: NAS flash through the Asus, two emails, D1 fixes, handoff packets, then the archive-and-leave-the-org workflow | **None.** No desktop, font, theme or shell content. A builder can skip L1–L1500 entirely. |
| [25]–[27] | L885–L1097 | 12:12–12:50 | Context compaction summary; Sodimo archive result; password masking (`SODIMOPWDPLACEHOLDER…`) | None (only "clipboard history is clean" at L1365, about the scrub, not the desktop feature). |
| [28]–[52] | L1512–L2440 | 13:37–20:28 | Tom's pivot to agency.agency: "the major breakthrough is the recent gpuix react products plus terminal"; five then three more planning workflows (vision, agency thread, Carol showcase, launch plan, two add-ons); the Sway-shell vs macOS-overlay separation; design-session prompts; then two hours on how to spend $250 of cloud credits | **This is where the shell material is.** Four Tom turns carry rulings ([28], [35], [36], [37]); the workflow outputs they triggered are the richest desktop-shell inventory produced that day. |

**Why it matters to the gpuix-shell build (INFERRED).** This is the session in which Tom first spelled out, in one breath, the list of things the Sway seat has that nothing else has: "a contextual launcher, a herdr leftbar that is disjinted and contol sway workspaces, clipboard history", plus the kitty/chat swap. It is also the session whose workflows wrote `SWAY-ONLY.md` (15 feature groups, every one with a Sway key, its script, and its state), `LAYERS.md` (the platform contract and the "Shell only" list), and the design track (`BASELINE.md` tokens, 18 design constraints, two Claude Design prompts). Those files are the nearest thing to a ready-made feature inventory for the shell, and this note indexes them.

**What it is not.** Tom's actual words about the shell in this half are short (four turns, ~500 words). The long lists below are mostly the agents' measured inventories from that day, labelled REPORTED. The rulings that bind tonight's build (Sway only, Claude/Primer look, Anthropic fonts, noir default, no top bar, "functionality from quickshell NOT visuals") were made in *other* sessions (dotfiles 7af325ec on 10-13/14, desk T-14/T-31) and are only *quoted* here; `BRIEF.md` already carries them.

---

## 2. Verbatim Tom rulings relevant to the desktop shell (with dates)

### 2.1 Spoken in this session (MEASURED, jsonl)

**turn [28] · jsonl:L1512 · 2026-10-14T13:37:43Z (15:37 CEST)** — the pivot. Shell-relevant fragments:

> "we just closed the sodimo story, which had lots of iterations including a leger buildout then a
> the major breakthrough is the recent gpuix react products plus terminal that can be "mirrored to a front end""

> "basically the entire ~/notes and enoki and leger chapters are fair game for this because we classify things between:
> - how the computer is being used; direct functinality skills or sway shortcuts or commands
> - inspiration : owui pipelines era , leger thoughts and back and forth ; cloudflare-os implementation."

> "for that you need full visibility over every single agents that is run (like how it s done w rene at ramp) ; yoo need shared artifacts and shared databases and utilities ; behind an mcp codemode ; without being limited to claude native functionality like the projects , docs , chat history , skills , projects , scheduled and routine ; and many more items. this is something that we have started doing inm y local dotfiles all the way to the hold space for dictation functionality (omarchy voice style)"

Reading (INFERRED): "gpuix react products plus terminal mirrored to a front end" = the GPUIX Mail/Desktop windows plus herdr-web-ui. "Sway shortcuts or commands" are explicitly a class of "how the computer is used". Hold-Space dictation is named as something "we have started doing", although dotfiles `AGENTS.md` says speech input is OUT since 2026-09-30 (see §6).

**turn [35] · jsonl:L1739 · 2026-10-14T15:38:31Z (17:38 CEST)** — scope correction, Marwan's starter kit from Tom's desktop:

> "agency.agency internal devices iswhat i share with marwan. he has to supply gh cf google account and claude subscription via herdr on his mac and we handle the rest entirely. this is about preparing starter kits for him based on what is currently on my own desktiop"

**turn [36] · jsonl:L1802 · 2026-10-14T16:00:22Z (18:00 CEST)** — ruling on GPUIX apps and the macOS build:

> "ruling: we are using the claude cc that has 250 usd of credits to builds this out entirely. for macos. yesterday we did attempts to use gpuix to materialize a herdr web ui chat , a crm , an email tool , a backlog projects tool... all those have agency oss repos"
> "… then we build the macos native gpuix version based on what happened yesterday. … it s to be read by his claude desktop that installs cladue code, herdr. gpui to the usage."

**turn [37] · jsonl:L1861 · 2026-10-14T16:08:40Z (18:08 CEST)** — THE shell ruling of this session, in full:

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

What this fixes for the gpuix-shell build (INFERRED):
1. The Sway shell is a *separate implementation* from any macOS overlay, but both sit "at the same library fundamentally" → shared tokens/components/clients, shell-specific surfaces.
2. The named Sway-only features are: **(a)** kitty ⇄ herdr-web-ui chat swap "translated into my own implementation", **(b)** a **contextual launcher**, **(c)** a **herdr leftbar** that is **"disjointed"** (its own surface, not inside an app) and **controls Sway workspaces**, **(d)** clipboard history.
3. The "tray/dock" item list for parity is: CRM, email, projects, files, "the vesence ones" (Chats, Files, Mail, Messages, Calendar, Library, Settings per the Vesence repro).
4. The visual starting point is the live desk chat at `strix.tail8dd1.ts.net:8443` (the herdr-web-ui fork) and "yesterday's demos of email, crm".
5. The design method is: many variations across design systems (Geist, Radix, Primer React, …) → distill "a minimal set of design elements".

**turn [39] · jsonl:L1874 · 2026-10-14T16:09:11Z** — process ruling, generalisable to tonight:

> "stop changing the plan. add ADDITOINAL plans on top of the currerntly runnign oner. we can be very genrous with the compute"

**turn [41] · jsonl:L1932 · 17:51:48Z** and **[50] · L2357 · 20:24:12Z** — cloud credits: "i m willing to go all-out on the ultrabuild ; from this non-macos desktop"; "we said we would use up to 200 usd credits from one ofhte account. prefer the cc for tis one." Not shell content; noted because the second half of the session continues on it.

### 2.2 Tom's own notes file that he pointed at (MEASURED: `/home/tom/wednesday-oct14-midday.md`, 40,455 bytes, Tom-authored, mtime 2026-10-14 16:04)

Tom's lines (outside the pasted article/code fences), with the file's line numbers:

- L7: "it would be useful to start working on a unified version, given that we hvae now completed the backlog functionlity at least. and how deep and intricate control we have over the dotfiles functionality."
- L266: "it bouils down to how i now have maximal ctrl over my interface. tarts wht estate, otes (including resources) and dotfiles"
- L268: "no more adhd-fixating on new shiny objects or things we cdon't need. less is more. … the right implementation is the one that gets done."
- L274: "2x esign agents end to end then one attempt per: vercel radix gh react ; claude; pure react ; claude instinctive ; cf design systems; views-c++ and the other desktop shells ; the whole thing end to end individually with the same ystsem prompts and identifying the minimum needed set of "design constraints" (even more abstract than components) that we can get satisfactory interfaces out of yet that remain well written and unified."
- L275: "1x claude "if i were a desktop" essay written by claude opus"
- L291: "the jev + embedding on all history + literally keylogging screen clicking keep reinfiorcing turing the scripts iinto shortcuts and fucntionality that ppears wit he menu plus clipboard plus something."
- L302: "client: webui, clickacke unified desktiop that is shortcut driven"
- L304: "alwayson iuniversal claude sideagent. like browser extension. so skill distillation is a DEFINTE thing that we can do! and "bumlp things to dofiles""
- L318: "like vesence the chat interface is the master controller so we have to build the intereace control and creation have to start distilling workflows the first thing we do it on. my onw copmputer usage"
- **L325: "the bottom macos tab bar: utilities like email etc can go below. herdr tabs on the left with sway and herdr control ;"**
- L327: "desktop env we'll whiteglove go onto those files ; then ensure the learning-as-we-go algorithm is implemented. ha that be the whole desktop. te unified claude bot in gpuix that can "ru my life""
- **L328: "i like the idea of interchangeability between terminal and herdr-web-ui"**
- **L329: "it's utilities and skills and things that get a shortcut to that. the idea is that we "puppetteer" the desktiop interface without consuming lots of effort from the claude controlling llm. the desktop interfaces are sortcut driven."**

Reading (INFERRED): L325 is the clearest layout statement of the day: **herdr/workspace rail on the LEFT (Sway + herdr control), utilities (mail, CRM, projects…) along the BOTTOM**, macOS-dock style. Together with "no top bar on the Linux head" (BRIEF) this gives left rail + bottom utilities dock, no top bar. L329 says every shell surface must be reachable by a shortcut and drivable by an agent cheaply ("puppeteer").

### 2.3 Tom's words relayed inside this session's workflow outputs (REPORTED; the agent read a transcript or thread, I did not)

From `/home/tom/today/crepuscule-2026-10-14/sessions/codex-dotfiles-branch.md:27-36` (Codex session 01a13843, 2026-10-14 04:36–04:42 CEST):
- "see how i use herdr-webui right now? what if i want to change between kitty terminal (herdr session) and web-ui chat window (rathern than the xterm js termianl)? can use some sway tabbing trickery perhaps?"
- "generally how we can "interleave" between several window types on sway without the user feeling the differnce and without that taking sway tabbed space. i dnt want to "see" the tabs however.. would be itnersting. would need some sort of "contextality" here"
- "a herdr workspace is ONE kitty terimnal correpondance. this is something i m hapy to enfordce"
- "in fact i m trying to do one hedr workspace is one sway wm workspace to reduce cognitive load even further"
- "and having a deep sense of integation between them. and that way herdr "watiing for input" becomes sway workspace wayland urgency . and we can integarte notify-send just as easily aswell"
- "i have custom shortcut ctrl M on google chroem that "isolates" the tab into a new one that gets tiled by swaywm regular"

From `/home/tom/today/crepuscule-2026-10-14/sessions/dotfiles-rulings.md` (Claude session 7af325ec, 2026-10-13 20:41 CEST):
- :51 "1.6 sway and vicinae are indeed mainstay on the client (zenbook). however, on the strix , we will keep sway window manager: after all this is what is used by browser.internal"
- :56 "1.11 volume keys through viciane popup yes i roll back on that; the way we control brightness and volume should be keypress>sway>script execution, no need to tie in vicinae if we don't have to"
- :64 "scroll is just a fork of sway window manager.. so 99% of the scrollmsg functionality can just be re-done as swaymsg … anyway yes sure remove it"
- :47 "1.2 anthropic fonts are indeed saved on the NAS the way they are"

From `/home/tom/today/agency-launch-2026-10-14/additional/design/BASELINE.md` §1.6 (dotfiles T-14 and desk T-31, 2026-10-13/14):
- "i want to use the claude anthropic font, the color scheme and selector, and the github primer react theme kit"
- "whatever you just opened: i love it." (of the `claude-primer` study)
- "we re doing functionality pull from quickshell NOT visuals or aesthetics whatsoever"
- "for ht left bar, i want you to copy the same proportions as the views c++ left tab bar that we saw from google chrome."
- "as if it was designed by anthropic claude 1st party native implementations - bar the font"
- "i want a design kit (set of constraints) that is a good enough set in order for us to have a claude anthropic-maximalist look "as if it was done by anthropic claude" but for desktop os ; in a way that we can use it in gpuix."
- "the idea is to keep "grinding" at a unified set of requirements that can outlast any coding language of framework, with react being the real world implementation of it"
- "i m not intersted in "native advantage" . performance is not really the thing i m looking for here."

From `/home/tom/today/agency-launch-2026-10-14/additional/SWAY-ONLY.md`:
- :113 "we keep vicinae actually.. i was getting a little carried away there when i said let's delete it. it's good fucntionality." (2026-10-12, dotfiles T-2) — NB: superseded on 2026-10-20 by the BRIEF order to replace Vicinae; record as a reversal, not a conflict.
- :113 "for the launcher, feature parity at least with vicinae (already enjoyed on my setup) including how it interacts w google chrome tabs is very desirable" (2026-10-14, `CU/BRIEF.md:43`)
- :113 "the concept of a spotlight menu sort of thing, along with all of the contextual information that it can hold at any given moment is probably the most underused item on the modern desktop and it should be really strengthened given that we're on swaywm (with its ipc) on linux" (2026-10-07)
- :152 "a functional remplacement to waybar, vicinae and mako notifications" (2026-10-13, dotfiles T-14)
- :200 "i digress on the hyprland parts, i m sorry. let s tick to sway window manager. less effort.." (2026-10-13)
- :208 "exposing selected functionality tot he user and watching my behavior and selfimproving from there can onyl happen bcz we have a tight grip on the actual keypresses: sway to gpuix shortcuts and fast typing." (2026-10-14)

From `/home/tom/today/agency-thread-2026-10-14/TAXONOMY.md` A.9 (:257-277): "i made a ruling in dotfiles taht there should be no cron jobs" (2026-10-13); "i dnt think it s a g ood idea to have things like that tied to nixos dotfiles" (model ids, 2026-10-10); "i said let  move to gufo!! not halogen!!!!" (2026-10-13); "HEURISTIC: Anything that goes in dot files is simply a byproduct of me configuring things for the AI agent." (2026-09-10).

---

## 3. Feature / behaviour inventory

Sources: Tom's turn [37] (TOM), `SWAY-ONLY.md` §2–3 (REPORTED, written in this session at ~20:00 CEST, every row says MEASURED against `DF main 2ac87891`), `LAYERS.md` §6.3–6.6, `TAXONOMY.md` A.2, `DESKTOP-INVENTORY.md` §9, `CONSTRAINTS.md` §6.2. "Where it lives today" is as of 2026-10-14; `BRIEF.md` §2 is the authority for tonight's paths.

| # | Feature | What exactly | Where it lives today (10-14) | Keep / replace / new | Notes for the gpuix-shell builder |
|---|---|---|---|---|---|
| F1 | **herdr left rail that drives Sway workspaces** | A surface *outside* any app ("disjinted") listing herdr workspaces = Sway slots 1–9 (top display) with agent status; click → focus Sway workspace; "no Herdr focus verb, ever". Rows at 220 / 30 / 12 / 2 / 8 px (Views tab-strip proportions). | Not a persistent bar yet. Four pieces: PR #565 Mod+I fuzzel switcher (`sway-workspace-switcher`); `herdr-picker` on Mod+Ctrl+Space; GPUIX Desktop window's workspace panel (`WT/design/gpuix-comparison/platform.ts`); rail mockup `WT/design/claude-rail` (`PROPORTIONS.md`); in-app version in the web-ui fork (commit `472dc0e`, `--siderail-*` tokens). `SWAY-ONLY.md:122-132` | **NEW** (the centre of the shell) | Layer-shell left, exclusive zone; reads `herdr api snapshot` read-only; writes only `swaymsg workspace`; "command, then observed echo" (CONSTRAINTS DC-09). States: READY/RUN/INPUT/DONE/BG + unknown as a dash. Slot labels `client-slot-N-<6hex>` get a muted "made in slot N" chip. Tom: "herdr tabs on the left with sway and herdr control" (midday:325). |
| F2 | **Contextual launcher** (Mod+D / Mod+Space) | Vicinae today: apps, commands, Chrome tabs via its extension, clipboard, files (Documents/Downloads), Now Playing. "Contextual" = list knows the focused Sway workspace/output, the herdr pane and its `agent_status`, the Chrome host (`CU/DESIGN.md:240`). Designed, not built. | `DF/home/vicinae.nix`, `binds.conf`; desktop entries "Herdr workspaces", "New/Restore/Rename Herdr workspace", "Dismiss/Restore notification", "Network settings"; `herdr-picker` (574 lines) through Vicinae dmenu. GPUIX provider catalogue uncommitted at `WT/pkgs/desktop-shell/providers.ts` (Hyprland). `SWAY-ONLY.md:109-120` | **REPLACE** Vicinae (per BRIEF 10-20) with a GPUIX overlay | Parity bar Tom set on 10-14: "feature parity at least with vicinae … including how it interacts w google chrome tabs". Chrome tab search needs the Vicinae extension bridge (`providers.ts` gap list) — unknown for tonight. One command catalogue with stable ids + platform tags (contract C4, `SWAY-ONLY.md:248`). |
| F3 | **Clipboard history** (Mod+V) | `vicinae cmd launch clipboard:history`; `monitoring=true`, `ignorePasswords=true`, `preserveTagged=true`, eviction threshold; input helper off (no auto-paste). cliphist installed but **no watcher** since 2026-10-07 (`startup.conf:4`). | `DF/home/vicinae.nix`; `SWAY-ONLY.md:134-140` | **REPLACE** (Vicinae's store does not export) | BRIEF decision 4: `wl-paste --watch` + own store. Constraints: opening never pastes; sensitive values masked with explicit reveal (CONSTRAINTS §6.2); skip concealed/transient MIME. Stale comment in `screen-ocr-area:6` ("cliphist keeps the result"). |
| F4 | **Kitty ⇄ herdr-web-ui chat swap in one tile** (Mod+grave) | One Sway ws = one herdr ws = one kitty projector; Mod+grave swaps the kitty with a Chrome app window (profile `HerdrSwayContext`) at the deep link `?machine=&ws=&pane=&view=chat&sidebar=hidden`; hidden companion in scratchpad; `swap container` + focus; fullscreen carried; `--choose-pane` chooser. | `DF` branch `feat/herdr-sway-context` @ `c1a49b99`, worktree `/home/tom/.wt/dotfiles/herdr-sway-context`: `herdr-context` (657 lines), `herdr-context.nix`, rules for `app_id ^chrome-.*-HerdrSwayContext$`, herdr `window_title = "{hostname}: {workspace}"`; 69 tests under runtime-test. `SWAY-ONLY.md:86-96`, `codex-dotfiles-branch.md:40-60` | **KEEP** (script) — the shell exposes it as a launcher command and a rail action | Tom: "translated into my own implementation" → eventually a GPUIX chat lens instead of Chrome. GPUIX has no terminal element (issue #42) so the kitty half stays. Conflicts with PR #565 in `binds.conf`/`flake.nix` (keep-both). Needs `herdr server reload-config` on the strix for the title (in-process, not restart). |
| F5 | **Blocked agent → Sway urgency + one actionable notification** | `herdr-attention` daemon polls snapshot every 3 s; only `blocked` counts; marks the ws companion urgent; one `notify-send` with Open action (deep link); dedup, quiet on reconnect, visit = acknowledgement. | Same branch: `herdr-attention` (442 lines), `herdr-attention.service` `PartOf sway-physical-session.target`, `ConditionEnvironment=SWAYSOCK`. `SWAY-ONLY.md:98-107` | **KEEP** the rule; the shell's own notification daemon receives it | Contract C3 (`SWAY-ONLY.md:247`). Rail must render urgency (INPUT state) from the same source. |
| F6 | **Slot lifecycle**: create / park / restore / rename / close | Mod+Return focus-or-create projector; Mod+T first free slot; Mod+W park ("Chrome-like close"); Mod+Shift+T restore newest parked; Mod+Shift+N rename (Sway keeps `N: name`); Mod+Shift+Q close = detach only; Mod+Ctrl+Shift+Return agents board. Sway marks `herdr-slot-N`, `herdr-label-…`, `herdr-name-<hex>`, `herdr-closed-<n>`. | `DF main`: `sway-workspace`, `herdr-picker`, `herdr-chord`, `herdr-projector`, `herdr-sway-projector`. `SWAY-ONLY.md:156-162`, `TAXONOMY.md:76-83` | **KEEP** scripts; shell wraps them | Rail actions (+, rename, park) should call these scripts, not reimplement. Mod+0 = ws 10 on eDP-2 (Chrome). |
| F7 | **Notifications**: mako + OSD + dismiss/restore | mako top-center (10-11), Anthropic Sans, overlay layer, palette via `~/.config/theme/mako.conf`, progress bar in Vicinae blue; high urgency persists. `osd` = one replaceable popup for volume/brightness with `value` hint progress bar. `makoctl dismiss|restore` as Vicinae entries. **No do-not-disturb** in dotfiles (`DEMO-RUNBOOK.md:310`). | `DF/home/vicinae.nix` (services.mako), `home/themes/default.nix` mako fragment, `dot_local/bin/osd` (added `524c66f7`). `SWAY-ONLY.md:149-154` | **REPLACE** mako with the GPUIX notifications daemon | The Hyprland-era `WT/pkgs/desktop-shell/main.ts` already has a daemon with DND. Keep: top-center anchor, persistence for critical, actions (Open), `value` hint → OSD. Add DND. |
| F8 | **Screen area → text via local model** (Mod+Ctrl+S) | slurp → grim → ssh strix `screen-ocr` → `http://strix:8731` `halogen-qwen3.8-flash-next`, temp 0, result to `wl-copy`; Esc leaves clipboard untouched; zero cloud tokens. | `DF/home/dot_local/bin/{screen-ocr-area,screen-ocr}`; Gufo move = draft PR #559. `SWAY-ONLY.md:142-147` | **KEEP** script; launcher entry | Fits the "stash" idea (S15). |
| F9 | **Capture**: screenshots / colour picker / recorder | Mod+S screen, Mod+Shift+S area+Satty, Mod+Alt+S window → strix `~/Pictures/Screenshots`, none local; Mod+C colour under cursor; `record` (wf-recorder) has no key. | `screenshot`, `colorpicker` (last `724dc9f4`). `SWAY-ONLY.md:170-175` | **KEEP** | Launcher entries only. |
| F10 | **Speech out** (Mod+Ctrl+R) | `speak-clipboard` → strix speech queue → played on seat with receipt. | `speak-clipboard` (added `8d4d9e7e`). `SWAY-ONLY.md:177-182` | **KEEP** | Launcher entry. |
| F11 | **Function row** | F2/Shift+F2 theme & accent pickers (fzf in floating kitty; `theme` retargets `~/.config/theme`, "no rebuild"); F3–F5 media; F6–F8 mute/vol with OSD; F9 `audio-route`; Shift+F9 `call-record-menu`; F10 `sleep-monitors`; Shift+F10 pomodoro. Draft PR #566 moves theme pickers to Super+F2 and adds F1/F2 brightness. | `binds.conf`, `dot_local/bin/{theme,theme-prompt,media,volume,audio-route,monitors-off,pomodoro}`. `SWAY-ONLY.md:184-188`, `TAXONOMY.md:105-116` | **KEEP** keys → scripts; shell provides OSD + theme switch UI | Ruling: "keypress>sway>script execution, no need to tie in vicinae". Theme switch must keep following the `~/.config/theme` symlink. |
| F12 | **Two-panel seat** | eDP-1 top (ws 1–9), eDP-2 bottom (ws 10); kanshi `Duo`/`DuoDocked` + `wl-gammarelay-rs` colour temp; touch → eDP-1; lid turns eDP-1 off; three-finger swipe = workspace; dock daemon turns eDP-2 off when keyboard docks; Mod+Shift+P both panels off with one-shot swayidle resume. | `binds.conf`, `kanshi/config`, `sway-local.conf` (in `home.nix`), `hosts/client/default.nix`, `modules/zenbook-duo-daemon.nix`. `SWAY-ONLY.md:164-168` | **KEEP** | Rail lives on eDP-1 only; must survive eDP-2 toggling. |
| F13 | **App chords & Chrome app windows** | Ctrl+N / Ctrl+Shift+N global Chrome; Mod+E Nautilus; Mod+Shift+C claude.ai, Mod+Shift+W Gmail, Mod+Shift+Period Notion Calendar as app windows; Mod+Shift+Semicolon OBS; Mod+Escape shortcut-inhibitor toggle; PR #565 adds Mod+Shift+M desk page. | `binds.conf`, `rules.conf`. `SWAY-ONLY.md:190-194` | **KEEP** | Launcher should list them as commands (same ids). |
| F14 | **GPUIX shell surfaces (Linux)** | Desktop window (Solid): Ctrl+K launcher sample, Applications panel with real eDP-1 workspaces (`platform.ts`, 26 mocked tests), notification samples. Uncommitted `WT/pkgs/desktop-shell`: bar, launcher, controls, windows, notifications, toasts, daemon, DND — "for Hyprland", 2,887 lines TS, no Sway adapter. | `/home/tom/.wt/hyprland-solid-shell/{design/gpuix-comparison,pkgs/desktop-shell}`. `SWAY-ONLY.md:196-202` | **REPLACE** (React, Sway) but mine | BRIEF already names these as precedent. `platform.ts` is the Sway-adapter seam to copy. Automation: `testId` + `globalThis.gpuix` driving (VISIBILITY §6.4). |
| F15 | **Designed, not built** (all Sway-dependent) | Keypress/window-event capture (interaction log; agents never hold the Sway socket); Sway↔herdr join row (rename either side); the "stash" (3 binds collecting primary selection and screen regions for the next request); "Ask Claude" quick entry from the launcher into a new herdr ws; hint layer on `f`; floating Claude-Docs-style vim editor; Chrome Ctrl+M tab tear-off. | `CU/DESIGN.md` §1.5, 2, 3.1, 3.2, 3.5 (`/home/tom/today/2026-10-14-computer-use-study/DESIGN.md`); `SWAY-ONLY.md:204-216` | **NEW, optional** | Candidate "nice" features for the launcher after the core. Keep Sway-only by design. |
| F16 | **Bottom utilities dock** | "the bottom macos tab bar: utilities like email etc can go below" (midday:325). Dock items = Mail, CRM, Projects, Agents (herdr chat), Calendar, Files, Library, Settings (Vesence set). Shell renders a layer-shell dock from a shared app registry; counts hidden when unknown (CONSTRAINTS §6.2 "Bottom bar of apps"). | Nowhere. `LAYERS.md:323-339` dock parity table; `DOCK-APPS.md` §5 per-app. | **NEW** | Conflicts with nothing in BRIEF §3 (which lists rail, launcher, toasts, OSD, switcher but no dock). INFERRED: add as a surface or fold the items into the rail's footer; Tom's midday note favours a bottom bar. |
| F17 | **Files explorer** (Pinax-like) | "the herdr web UI's Files dialog, per pane" today; `DOCK-APPS.md` 5.5: project records' repositories + library folders on local disk + mail/CRM attachments in R2; read-only first. | none native. `LAYERS.md:333` | **NEW** (BRIEF: `gpuix-shell files`) | Ordinary window. |
| F18 | **Theme follow** | `theme` retargets `~/.config/theme` symlink; consumers reload "no rebuild"; herdr `[theme]="terminal"` so kitty paints herdr; Vicinae theme file follows the same pointer; web-ui fork has System/Claude Light/Claude Dark/Noir switch. | `dot_local/bin/theme` (added `2369f56b` 2026-09-17), `home/themes/*.nix`. `SWAY-ONLY.md:186-188` | **KEEP** mechanism; **NEW** fragment `gpuix-shell.json` (BRIEF) | Watch the symlink, reload live. |
| F19 | **Input: hold-Space dictation** | Removed on every host 2026-09-30 ("Speech input is OUT"); Tom lists it on 10-14 among what "we have started doing"; conference pack says "tell it as history". | gone. `DESKTOP-INVENTORY.md:326`, `SWAY-ONLY` n/a | **OUT** until Tom rules | Do not build tonight. |
| F20 | **Keyboard-first list grammar** | `/` search, `j`/`k`, `c` compose, Esc closes (Mail); palette `>` for actions; filter letters only when focus outside search; Left/Right between sections. | `BASELINE.md` §1.5 | **KEEP** as the shell's interaction grammar | Apply to launcher and switcher. |

Full Sway key map (107 `bindsym` lines as of 10-14, REPORTED): `/home/tom/today/agency-thread-2026-10-14/TAXONOMY.md:69-124`. Scripts the shell must not break: `herdr-picker`, `herdr-chord`, `sway-workspace`, `herdr-projector`, `herdr-sway-projector`, `theme`, `osd`, `screen-ocr-area`, `speak-clipboard`, `screenshot`, `colorpicker`, `audio-route`, `volume`, `brightness`, `media`, `pomodoro`, `monitors-off` (all `DF/home/dot_local/bin`).

---

## 4. Design values (sizes, colours, fonts, radii, timings)

All REPORTED from `/home/tom/today/agency-launch-2026-10-14/additional/design/BASELINE.md` §1.4 (which cites `FORK/DESIGN.md` = `/home/tom/mecattaf/herdr-web-ui/DESIGN.md`, 1,706 lines, and `DS/claude-suite/reference-palette.json`), unless marked. Tom accepted this look ("i love it") on 10-13/14; nothing in this session changes it.

**Palettes (three, from `home/themes/{noir,claude-dark,claude-light}.nix`)**

| Role | Noir (default) | Claude Dark | Claude Light |
|---|---|---|---|
| Canvas | `#000000` | `#1A1A1A` | `#F9F9F7` |
| Chrome / panel | `#000000` | `#20201F` | `#F0EFEC` |
| Raised | `#101111` (desk) / `#000000` (palette file) | `#262625` / `#20201F` | `#FFFFFF` |
| Ink strong | `#EAECF0` | `#EAECF0` | `#131313` |
| Ink body | `#D3D7DE` | `#D3D7DE` | `#131313` |
| Ink dim | `#818898` | `#8F96A5` | `#52514E` |
| Accent (focus, selection, chosen lens, cursor) | `#70B8FF` | `#70B8FF` | `#0051C2` |
| Primary (user's own action: Send/Compose/New) | `#D97757` | `#D97757` | `#A74B2F` (brand stays `#D97757`) |
| working / blocked / done | `#70B8FF` / `#FBAD60` / `#9BE963` | same | `#0051C2` / `#9A3F00` / `#006B00` |
| Danger text | `#F47B85` | `#F47B85` | `#B80A18` |
| Selection | `#264F78` | `#264F78` | `#CDE2FB` |
| Borders | ink @ 15% and 30% alpha | same | same (palette file uses opaque `#373735` / `#D2D1C7`) |

Known deviations the constraints flag (`CONSTRAINTS.md` §0 item 3): brand clay used for selection/checked/tab indicator is 2.96:1 on Claude Light base (under the 3:1 floor); "working" shares the accent hue with focus; the desk keeps a second GitHub-hue status set (`#3FB950`, `#D29922`, `#F85149`); rail selection wash is 1.03–1.08:1 (needs a second cue). Six of these need Tom's word (G-list in CONSTRAINTS §5).

**Typography.** Interface `"Anthropic Sans"`; chat prose / documents `"Anthropic Serif"`; code, times, counts `"AnthropicMono Nerd Font"`. Scale (comfortable): 11, 12, 13, 14 (body), 15 (chat reading), 16, 18, 22 (display), × one `--ui-scale`; compact = one step smaller. Weights 400/500/600/700. Line heights 1.2 titles, 1.5 body, 1.65 prose. The framework-neutral kernel (`DS/claude-portability/src/core/tokens.ts`) has only body 13 / mono 11. Native GPUIX prototypes had 9–10 px times/counts (flagged too small).

**Space & size.** 4 px base (4, 8, 12, 16, 20, 24, 32). Radii: 6 chips, 8 buttons/inputs/rows, 12 menus and chat surfaces, 16 modals, 24 composer card, pill. Control height 34 comfortable / 32 compact. Header 46 px (≥769 px window) / 52 px below. Content width 820 px (chat lane 820 min, 960 max); palette 640 px. **Rail: 220 wide, 30 px rows (196 × 30), 12 px insets, 2 px gaps, 8 px corners** (from the Chromium Views tab strip, `~/mecattaf/views-shell`; `DS/claude-rail/PROPORTIONS.md`). Compact rail = one glyph per state.

**Depth.** Tonal shift + hairline; no resting shadows; shadows only on overlays (menus, palette, modals) and the drawer; composer is the one resting card. Glass/blur optional, never load-bearing (and BRIEF says none).

**Motion.** Only state changes move. Micro `120ms`, standard `180ms` × user motion scale; desktop dialogs snap open; working dot breathes in steps; reduced motion removes all but the stepped RUN breath.

**State vocabulary.** READY, RUN, INPUT, DONE, BG; unknown = dash with dashed edge. Always a word *and* a mark. Compact: filled message glyph = waiting on you; dot = done-not-seen; breathing dot = working; nothing = ready. (herdr's own words per BRIEF: blocked ◉ / working ◐ / done ● / idle ✓ / unknown ○ — map them.)

**Desk shell layout (the accepted reference, BASELINE §1.3).** Top status strip ("3 working", "0 waiting on you", date); header with sidebar toggle, search, crumb `PC › workspace › folder`, segmented Chat/Agents/Terminal lens, bell with count; 220 px rail (PC head + status dot + `+`; "Waiting on you (projects)" group; workspace rows with brand mark, name, "made in slot N" chip; separate Agents list; footer Install app / Settings); palette `Mod+Shift+K` (Ctrl+K on desk pages) with chips ALL/INPUT/RUN/READY/DONE/BG, sections per PC/workspace, Recent first, Actions last, calculator row, footer hints.

**The 18 design constraints** (`CONSTRAINTS.md` §0, ids DC-01…DC-18): Colour spent on meaning; contrast measured where text sits; state is a word and a mark; every view says where its data comes from; flat/opaque/plain at rest; three voices on one type root; one grid, short ladders, density as a factor; motion only for change; looking is free, acting is declared; drivable at equivalence; one focus model, one layer stack; stable under change; one row grammar; one object many lenses; **the platform owns the frame (DC-14)**; agent work has one grammar; words are part of the design; identity is a skin over roles. §6.2 applies them to the Sway overlay (rail: DC-12/03/07/14; launcher: DC-10/11; clipboard: DC-09/04; bottom bar: DC-14/03; swap: DC-13).

**Notification/OSD values (REPORTED SWAY-ONLY S7).** mako anchored top-center; overlay layer; font Anthropic Sans; progress bar in Vicinae blue (= accent `#70B8FF`); high urgency persists. (BRIEF §3 puts toasts top-right 390 wide max 4 and OSD bottom margin 96 — a conflict with the 10-11 top-center ruling; see §6.)

---

## 5. Reusable code or data, with exact paths

**Written during this session's first half (planning files, REPORTED content, MEASURED existence/size):**

| Path | Lines | What the shell builder gets |
|---|---|---|
| `/home/tom/today/agency-launch-2026-10-14/additional/SWAY-ONLY.md` | 301 | The 15-group Sway feature catalogue (§2 table at :62-78; details :86-216; contracts C1–C6 at :243-250; dependency-ordered plan :258-267; sources :283-301) |
| `/home/tom/today/agency-launch-2026-10-14/additional/LAYERS.md` | 513 | Platform contract sketch (`Capabilities` interface) :265-284; capability table sway/macos/browser :286-297; **Shell only** list :301-311; dock parity table :323-339; boundary rules R1–R9 :341-355; naming (`agency.agency.<app>` app ids) :357-431 |
| `/home/tom/today/agency-launch-2026-10-14/additional/design/BASELINE.md` | 366 | Tokens in use (§1.4), screens in use (§1.3), interaction patterns (§1.5), Tom's taste quotes (§1.6), 13-constraint seed (§2.4) |
| `/home/tom/today/agency-launch-2026-10-14/additional/design/CONSTRAINTS.md` | 611 | The 18 constraints with tests (:98-366); Sway overlay application (:526-536); 17 disagreements with recommended choices (§5) |
| `/home/tom/today/agency-launch-2026-10-14/additional/design/CLAUDE-DESIGN-PROMPTS.md` | 1,401 | Two paste-ready Claude Design session prompts + rubric (§6); Session 1 "Variations", Session 2 "Definitive" |
| `/home/tom/today/agency-launch-2026-10-14/additional/design/systems/{geist,primer,pure-react,radix,claude,shells,cloudflare}.md` | 347–530 each | Per-system token/primitive studies; `shells.md` covers views-c++, views-shell, Vesence, Omarchy, macOS (§3–7) and GPUIX fit per system; `claude.md` §11 maps Claude's language onto GPUIX |
| `/home/tom/today/agency-launch-2026-10-14/additional/DOCK-APPS.md` | 455 | Seven dock apps (Agents, Mail, CRM, Projects, Files, Calendar, Library) with the shared frame (§4) and guards (§8) |
| `/home/tom/today/agency-launch-2026-10-14/ground/DESKTOP-INVENTORY.md` | 429 | Every CLI/skill/herdr piece/GPUIX app/Worker on Tom's desktop (§3–6); Sway keys as excluded list (§9 :342-355); speech/input (§8 :322-340) |
| `/home/tom/today/agency-launch-2026-10-14/ground/GPUIX-APPS.md` | 274 | What was built 13–14 Oct (§1), the four apps (§3), what they share (§5) |
| `/home/tom/today/agency-launch-2026-10-14/ground/MACOS.md` | 383 | §4.2 (:161-178) GPUIX capability table incl. `layer_shell` "Linux/Wayland only; ignored on every other platform" (`renderer.rs:7299-7368`, `#[cfg(target_os="linux")]` :7499-7504); §7.1 component map |
| `/home/tom/today/agency-launch-2026-10-14/additional-2/KERNEL.md` | ~640 | The framework-free "core" library spec: tokens bundle format with emitters for CSS, **GPUIX native styles**, kitty, Ghostty; headless state machines with React DOM + GPUIX React adapters; host-capability types |
| `/home/tom/today/agency-thread-2026-10-14/TAXONOMY.md` | — | A.2 full Sway key map :69-124; A.9 standing rules :257-277; B.9 GPUIX lineage :436-460 |
| `/home/tom/today/agency-thread-2026-10-14/VISIBILITY-ARCHITECTURE.md` | — | §6.3–6.4 (:325-336): GPUIX automation (`testId`, `globalThis.gpuix`, pausable clock) as the reason agents can drive/test the shell |
| `/home/tom/today/agency-thread-2026-10-14/conference/DEMO-RUNBOOK.md` | — | §8 (:209-232) how the GPUIX windows were launched on the Zenbook (`~/Downloads/gpuix-comparison-2026-10-14`, port 4187); known GPUIX gaps (no zoom, URL-drop error); `fallback/gpuix-0{1..4}.png` screenshots |
| `/home/tom/today/crepuscule-2026-10-14/sessions/codex-dotfiles-branch.md` | — | Line-by-line of the `feat/herdr-sway-context` branch (:40-60): every file, test, and the herdr `window_title` change |
| `/home/tom/today/crepuscule-2026-10-14/sessions/dotfiles-rulings.md` | — | The 10-13 rulings table (:47-64) |
| `/home/tom/wednesday-oct14-midday.md` | 329 | Tom's own design/layout notes (lines listed in §2.2); the rest is pasted reading |

**Code this half points at (pre-existing; paths as of 10-14, BRIEF §2 is current):**
- `/home/tom/.wt/dotfiles/herdr-sway-context/home/dot_local/bin/{herdr-context,herdr-attention}` + `home/herdr-context.nix` + `tests/herdr/{test_context.py,test_attention.py,smoke_context.py,smoke_titles.py}` — the swap and the attention rule, 69 tests.
- `/home/tom/.wt/hyprland-solid-shell/design/gpuix-comparison/platform.ts` — "framework-independent Sway capability adapter"; reads outputs/workspaces, shows only eDP-1 workspaces, focus only after explicit click with identity/output revalidation; 26 mocked tests.
- `/home/tom/.wt/hyprland-solid-shell/design/claude-rail/PROPORTIONS.md` — the 220/30/12/2/8 rail, cites views-shell C++ lines.
- `/home/tom/.wt/hyprland-solid-shell/design/claude-suite/{CTRL-K-LINEAGE.md,DESKTOP-REQUIREMENTS.md,RENDERER-DECISION.md}` — launcher command contract ("Stable command ID, label, parameter schema, applicable context").
- `/home/tom/.wt/hyprland-solid-shell/pkgs/desktop-shell/{main.ts,providers.ts,notifications.ts}` — provider catalogue (with `providerGaps`), notification store with monotonic id; the web-ui fork lifted both (commit `5c9a92a`).
- `/home/tom/mecattaf/herdr-web-ui` branch `identity/claude-primer` @ `e85ffd1`: `src/lib/deepLink.ts:1-30` (deep-link grammar `machine, ws, pane, view, sidebar, new`), `src/styles.css` `:root` tokens (`--siderail-*`), `DESIGN.md`, `docs/guide.md:103,195,493`.
- `/home/tom/mecattaf/views-shell/SPEC.md` @ `125d8bb` claims C25.1–C25.5 (rail with exclusive zone over i3 IPC; click = one `FocusWorkspace` "until the echo or a refusal").
- `/home/tom/today/2026-10-14-computer-use-study/{DESIGN.md,BRIEF.md,BRIEF-2.md,longrun/ambient-computer.md}` — contextual launcher design (§3), interaction log (§2), stash (§3.1), quick entry (§3.5).
- Vicinae pinned source `/nix/store/lpy7d11xvdqaim60calwv5hcfw04ynmz-source/src/server/src/services/{clipboard,desktop-notification,global-shortcuts,window-manager}/` — reference for what the launcher/clipboard replacement must match.
- herdr 0.9.4 source `/nix/store/rhf39pkryzrcpmc87sccqrbgwhshppnz-source/src/platform/{linux,macos}.rs` — clipboard-image staging, `show_desktop_notification`.

**Data contracts named in this half (REPORTED SWAY-ONLY §5.1):** C1 herdr read-only snapshot (`herdr api snapshot`; states incl. `blocked`); C2 web-ui deep-link grammar; C3 attention rule ("only blocked asks for a person; dedupe; quiet on reconnect; a visit acknowledges"); C4 one command catalogue with stable ids + platform tag; C5 window/workspace adapter seam (`platform.ts`); C6 palettes and fonts as data (`~/.config/theme` pointer).

---

## 6. Gaps, unknowns, conflicts

1. **The first half of this session contains no direct Tom statement about fonts, theme names, bar position, launcher geometry or notification placement.** Those come from dotfiles 7af325ec (10-13/14), desk T-14/T-31, and the 10-20 order in BRIEF. Everything in §4 is REPORTED through BASELINE/CONSTRAINTS; nobody tonight re-read `FORK/DESIGN.md` or the Nix theme files from this seat. A builder who needs an exact hex should read `home/themes/*.nix` in the worktree, not trust §4.
2. **Toast/OSD placement conflict.** mako was ruled top-center on 2026-10-11 (REPORTED SWAY-ONLY :151); BRIEF §3 says toasts top-right 390 wide, OSD bottom margin 96 (from SHELLS-DIGEST §4). Unresolved; neither is in this transcript. Assumption to record: follow BRIEF (newer), keep top-center as a config option.
3. **Bottom utilities dock vs BRIEF surface list.** Tom's midday note L325 wants utilities "below" (bottom bar); BRIEF §3 has no dock surface. Assumption: a bottom layer-shell dock is in scope as `gpuix-shell dock` or as the rail's footer; Tom decides.
4. **Vicinae: keep (10-12) → replace (10-20).** The replacement must meet "feature parity at least with vicinae … including how it interacts w google chrome tabs". Chrome-tab search depends on Vicinae's browser-extension bridge; no replacement path is documented. Unknown.
5. **Clipboard history store cannot import Vicinae's history or retention rules** (`providers.ts` gap). Accept a cold start.
6. **"Contextual launcher" is designed only** (`CU/DESIGN.md` §3); the context sources (focused Sway ws/output, herdr pane + `agent_status`, Chrome host, `kb` thread) exist separately. No code.
7. **The left rail has never been assembled on Sway**; GPUIX layer-shell on Linux + `platform.ts` + rail metrics + herdr status are each proven separately (SWAY-ONLY :130). Also the Solid→React move: "GPUIX React: Supported upstream; Not implemented or tested locally" (VISIBILITY :327). The React adapter is unproven on this fleet as of 10-14.
8. **GPUIX has no terminal element** (issue #42) → the kitty half of the swap stays kitty; a GPUIX chat lens would replace only the Chrome half. GPUIX zoom not implemented; a URL drop produced an unexplained Wayland error (DEMO-RUNBOOK :230).
9. **herdr `window_title = ""` live on the strix; the swap needs `"{hostname}: {workspace}"` plus `herdr server reload-config`** (in-process). Tonight's rules forbid touching herdr; the shell can read titles only if that lands.
10. **Two open Sway branches conflict** (`feat/herdr-sway-context` vs PR #565 in `binds.conf`/`flake.nix`). Tom never ruled on T-18 in this half. The shell's Mod+i switcher and Mod+grave swap must be merged by hand.
11. **Hold-Space dictation**: contradictory (OUT 09-30 vs "we have started doing" 10-14). Not for tonight.
12. **Fonts**: licence for any machine other than Tom's is open (MACOS §9); BRIEF already says private repo only. Nothing new.
13. **Design disagreements needing Tom** (CONSTRAINTS §5, G-list): may the brand clay mark selection; colour of "working" vs accent; mono vs sans for numbers/times; capitals for status words; **frame on Sway (top bar or not; utilities below or in the launcher)**; selected-row cue when the wash is too faint. All unanswered in this half.
14. **Second half not read here**: turns [53]–[104] (20:30Z onward) continue on cloud credits and may hold more; see the sibling note.
15. **Verification left undone (light pass, per the 10-20 workflow rule):** I did not open `SWAY-ONLY.md`'s cited files to confirm line numbers; I did not run any command against Sway, herdr or the worktree; `TAXONOMY.md` A.2's 107-bind count was not recounted. Everything labelled REPORTED is one agent's reading from 10-14.

---

## 7. What I did and did not do

- Read: BRIEF.md in full; all 105 Tom turns of the jsonl via the helper (index), turns [0]–[52] in full, assistant turns [264]–[460] with tool-result bodies trimmed; `SWAY-ONLY.md` in full; `LAYERS.md` :265-356; `BASELINE.md` :1-120; `CONSTRAINTS.md` :15-40, :526-544; `DESKTOP-INVENTORY.md` :205-228, :322-356; `MACOS.md` :161-197, :285-320; `TAXONOMY.md` :69-126, :257-277; `VISIBILITY-ARCHITECTURE.md` :325-340; `DEMO-RUNBOOK.md` grep lines; `codex-dotfiles-branch.md` :25-60; `dotfiles-rulings.md` grep lines; `wednesday-oct14-midday.md` Tom-authored lines; header listings of the other design/ground files.
- Wrote: only this file. Touched nothing under `/home/tom/mecattaf/dotfiles`, Sway, herdr or systemd.
- Not done: no re-verification of REPORTED claims; no reading of the second half; no reading of the Codex 10-13/10-14 rollouts (other readers).
