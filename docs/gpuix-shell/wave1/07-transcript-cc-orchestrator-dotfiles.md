# 07 — Transcript reading: the 10-20 cc orchestrator session (dotfiles) and the 10-18 spec-driven session (today)

Written 2026-10-20 night by one wave-1 reader of the gpuix-shell overnight build, read-only.
Labels: **TOM** = Tom's typed words, verbatim, typos kept. **MEASURED** = a command this reader
ran tonight, or a tool result inside the transcript whose output is quoted (named as such).
**REPORTED** = an agent's prose in the transcript or a file the transcript embeds (the MAP).
**INFERRED** = this reader's reading. Timestamps are the jsonl `timestamp` (UTC); Tom's clock
and file mtimes are CEST (+2h). `L<n>` = line number of the jsonl file named in the section.

Builder's one-line summary: these two sessions give the **nine-slot 1:1:1 mapping** in Tom's
own words, the **projector-collapse incident** measured to the second (which fixes what the rail
must and must not do with herdr focus), the **cull rule** for herdr workspaces, the **sister
project** ruling (gpuix shell, no quickshell, same kernel as agency.agency, shortcut-based) and
the **three heads** (Tom Sway, Marwan macOS native, Frank browser). They give almost no pixel
values; the design numbers quoted below are REPORTED from the embedded MAP.

---

## 1. What these sources are

### 1a. `/home/tom/.claude/projects/-home-tom-mecattaf-dotfiles/1a517fb2-dbee-4524-a95c-dd798bcc78b0.jsonl`

MEASURED tonight: 856 jsonl lines, 2,746,565 bytes, mtime 2026-10-20 22:49 CEST. Claude Code
2.1.287, seat `cc` (~/.claude), cwd `/home/tom/mecattaf/dotfiles`, branch `main` (dadb1426).
First Tom turn 2026-10-20T10:49:45Z (12:49 CEST), last activity 15:42Z. It is **the 10-20
orchestrator**: herdr workspace `wGG` = `client-slot-4-dfd7ae`, pane wGG:p1, Sway slot 4 on the
Zenbook (`~/tuesday-oct20/start.md` says so of itself, L373 Write).

What it did, in order (MEASURED from the turns):
1. 10:49–11:01Z: diagnosed the "all the 10 workspaces disappeared" report (the projector incident,
   §2.2), read the live Zenbook over Tailscale (`ssh tom@100.121.160.100`), wrote
   `~/tuesday-oct20/start.md` (L373).
2. 11:02Z: culled 222 idle herdr workspaces on the strix, 235 → 13 (L411–L437).
3. 11:03Z: filed Tom's words into the project tool (desk T-39, desk memory, dotfiles memory,
   dotfiles T-25 + decision D-16) (L467–L490).
4. 11:09Z: ran workflow `situate-2026-10-20` (15 Fable readers, 3 critics, 1 synthesizer; 19
   agents, 5,670,491 subagent tokens, 46 min) whose result is **the MAP**
   (`/home/tom/tuesday-oct20/MAP.md`, 12,500 words). The whole map is embedded in the transcript
   at L644 (`<task-notification>` wo30h0b1f) and in
   `/tmp/claude-1000/-home-tom-mecattaf-dotfiles/1a517fb2-dbee-4524-a95c-dd798bcc78b0/tasks/wo30h0b1f.output`
   (138,041 bytes). Section 5 of the MAP, "The unified GPUIX workspaces", is the summary of record
   the BRIEF points at; it is quoted in §2.5 below with its provenance kept.
5. 11:15–11:17Z: measured the herdr focus semantics on the live projectors (L604–L634), filed on
   dotfiles T-25.
6. 11:09Z and 12:04Z onward: two more workflows about Frank (`frank-today-prep`, 48 agents;
   `frank-next-days`, 23 agents). Not shell material except for what they say about the
   browser head.
7. 12:03Z: Tom's **sister-project ruling** (§2.4), filed on desk T-38, desk memory and dotfiles
   T-14 (L763–L779), plus the measured openui vs gpui-kit distinction.
8. 14:15Z–15:42Z: Frank's day plan; usage limit hit at 14:16Z, resumed 15:41Z.

**A trap for other readers (MEASURED).** Tom typed most of his words while the session was busy,
so they are stored as `{"type":"queue-operation","operation":"enqueue",...}` lines and surfaced
to the model as `attachment` lines of type `queued_command`, **not** as `type:"user"` turns. The
helper `transcript-text.py --user-only` skips every one of them (it handles only `user`/
`assistant`). The nine-slot quote, the sister-project ruling, the F10 messages and the "10 fable
agents, 25-30 opus" sizing all live only in queue-operation lines. Anyone re-reading this session
must grep `"type":"queue-operation"` (enqueue) as well. Lines: L69, L108, L203, L218, L243, L277,
L316, L400, L538, L539, L687, L724, L751 (plus L642, L650, L781, L839 which are harness
notifications, not Tom).

Tom's turns as `user` lines: L5, L283, L407, L493, L685, L825/L835 (the usage-limit repeat).

### 1b. `/home/tom/.claude/projects/-home-tom-today/683f84a0-9c5e-4684-9920-896f27db847b.jsonl`

MEASURED tonight: 369 lines, 1,415,909 bytes, mtime 10-20 22:06 CEST (touched by a herdr reattach,
not by new content: its last turn is L353 at 2026-10-18T12:48:34Z). Seat `cc`, cwd `/home/tom/today`,
model set to Fable 5.1 effort xhigh at the start (L6, L10). herdr workspace `wHF` =
`client-slot-8-fa2a21`, Sway slot 8 (newer). Titled by start.md "Spec-driven architecture and
edge-native systems". Tom's role order: "you are super high level assistant here, you will not
implement anything" (L13). It ran one workflow (3 Fable readers: the Codex first-mate session,
`~/notes`, the Frank/Marwan thesis), produced a high-level months plan (L340), and ended with a
context-continuation summary (L353) after which nothing was typed; start.md (12:58 CEST 10-20)
records "A prompt is typed but NOT sent: 'ok walk me through the 23 waiting items'".

Tom's turns: L13 (brief + two pasted Gemini chats), L248 queued / L251 (Frank steering), L318
(the herdr-web-ui "projects view" remark). Lines 354–363 are attachments, 364 system, 365–369
metadata; no assistant turn after L353 (MEASURED).

**Desktop-shell relevance is thin.** No Sway, waybar, mako, vicinae or gpuix-shell discussion. What
it adds: the herdr-web-ui "Waiting on you" rail as the acceptance pattern (§2.6), the three-node
group that becomes the three heads, the GCD/dogfooding heuristic, and the kit 0.1.0 status.

### 1c. Companion files Tom wrote himself on 10-20 morning (TOM, by mtime, before the session)

- `/home/tom/tuesday-oct20/desktop-ui.md` (10:45 CEST, 881 bytes) — the GPUIX/openui ruling, §2.3.
- `/home/tom/tuesday-oct20/tabs-client.md` (11:12 CEST) and `tabs-phone.md` (11:08 CEST) — the
  tabs he was keeping; several are shell feature wishes, §2.7.
- `/home/tom/tuesday-oct20/start.md` (orchestrator-written, 12:58–14:50 CEST) — the nine-session
  table, the incident timeline; its root-cause paragraph is the orchestrator's prose (REPORTED).

---

## 2. Verbatim Tom rulings relevant to the desktop shell (with dates)

### 2.1 The nine-slot mapping (2026-10-20)

TOM, L218, queued 2026-10-20T10:53:53.992Z (12:53 CEST):
> but recover the last sway workspaces > herdr workspaces > kitty terminals ( i typically hae a one ot one mapping, with a limit of 9 open workspaces at a time; this helps with my mental overload

Context for the builder: the chain is **Sway workspace N → herdr workspace (label `client-slot-N-xxxxxx`) → one kitty window `--class herdr-projector`**. The mapping is Tom's working shape and his stated reason is cognitive load, not a technical limit. The orchestrator filed it as dotfiles memory (L473): "On the Zenbook seat Tom keeps a one-to-one mapping Sway workspace > herdr workspace > kitty projector, with at most nine open at a time." The MAP (REPORTED, L644 / MAP.md:97) ties it to the older rulings it restates: 10-07 "one herdr per sway workspace" and 10-14 "a herdr workspace is ONE kitty terimnal correpondance ... one hedr workspace is one sway wm workspace", and to #538 (10-12): workspaces 1–9 on the top panel, 10 on the bottom.

TOM, L407, 2026-10-20T11:01:49Z (also queued at L400 11:01:37Z):
> in the meantime of course, hertdr and dotfiles improvements will be impolemented. for starters i have TONS of herdr workspaces that qre inactive and that we can kill. you identified the 9 important one.

TOM, L243, queued 10:54:58Z:
> i d like those listed in ~/ tuesday-oct20 in the start.md file i typically have to say "starting the day read up ion all otehh herdr sessions and tabs i just closed

TOM, L316, queued 10:57:27Z:
> so you are the high lvl orchestrator who will help me and understand where we arre now

INFERRED for the shell: "the 9 important ones" = the nine slots; the start-of-day read-up (which herdr session sits in which slot, what it concluded, what it waits on) is a recurring Tom need that today is a hand-written markdown table; a rail or switcher that shows slot → herdr workspace → agent status → last conclusion makes that table live.

### 2.2 The projector incident, as Tom saw it and as it was measured (2026-10-20)

TOM, L5, 2026-10-20T10:49:45Z (the session's first words):
> getting strange behavior on client (understand what is the dotfiles repo for my own fleet)

TOM, L69, queued 10:50:13Z:
> i did f10 to close and all the 10 workspaces disappreared along w the workspaces i was woprerking on it
> i m on the zenbook btw just so we re clear

TOM, L108, queued 10:50:58Z:
> i m not sure what clweared theworkspaces. maybe it was loss of interent connection. since this is not "sleep" it s just brithness zero on the device, basically nothing happened. i moved around w the laptop that s why

TOM, L203, queued 10:53:17Z:
> f10 is just a brightness modiofier; same as f5 f6 . the only thing is that since i mn oti mkplementing real sleep (which is good btw, very mininalsostic)

What was then MEASURED by the orchestrator (tool results inside the transcript; CEST times from the Zenbook journal):
- F10 on the client is `bindsym --no-warn F10 exec ~/.local/bin/brightness toggle` in the generated `~/.config/sway-local.conf:9` (L150 result, "---DEPLOYED-F10---"), from `home/home.nix:158`. The repo's `binds.conf:150` also binds F10 to the sleep-monitors prompt, but `sway/config` includes `sway-local.conf` after `binds.conf` (config:6 vs :9, L103 result), so the later bind wins on the client. F10 "only zeroed the backlight (11:31)" (start.md). Backlight at capture: intel_backlight 240/400, card1-eDP-2-backlight 240/400, asus_screenpad 130898/255 (L150).
- 11:37 CEST the Zenbook left `thomas-6ghz`, 11:39 joined `Freebox-64238A`; all nine `herdr --remote strix --remote-keybindings server` projectors reconnected at 11:39:24 (two surviving client processes 358516/358517 with that start time, L150; strix herdr-server.log clients 363–376, L473 brief).
- A reattached `herdr --remote` lands on the server's focused workspace. The projector script already says so: `home/dot_local/bin/herdr-projector:35-36` "After a reattach the window lands on the server's default target, not necessarily the workspace it was showing." So nine windows showed one pane (wGG).
- 12:48:56 → 12:49:07 seven kitty scopes ended one per second (kitty-5174, -54935, -134100, -138059, -133718, -342353, -55653; L194 result "---SCOPES-TODAY---"): slots 2, 4, 5, 6, 7, 8, 9 closed by hand on focus. Sway (pid 1946, up since Sat 10-17 19:51:05) never restarted; `swaymsg -t get_workspaces` showed only workspaces 1 and 3 on eDP-1, both with a projector (L150, L194 "---WS-NAMES---"). herdr.service on the strix: 0 restarts since 10-13 09:13.
- `herdr workspace focus <id>` **is server-global**: focusing wHH moved BOTH attached projectors (kitty 7251 and 54356) to the nvim pane at once; restored with a second focus to wGG (L605 result "===FOCUS-TEST===", filed at L633).
- herdr 0.9.3 has no attach-time workspace flag (`herdr --help`, L390/L404). prefix+w is a NAVIGATE mode, not a typed picker; prefix+b shows the sidebar with a ● marker on the selected workspace, readable through `kitten @ get-text` (L633, REPORTED measurement of 13:20–13:35 CEST).
- The client is reachable only over Tailscale 100.121.160.100 (LAN name fails; `HostKeyAlias=client` needed, L112 "Host key verification failed" then L124+ success). The client's uid is **1001** (`SWAYSOCK=/run/user/1001/sway-ipc.1001.1946.sock`, L150), the strix's is 1000: never hardcode `/run/user/1000`.

Orchestrator's filing (REPORTED, L473): dotfiles T-25 "herdr-projector reattach lands every window on the server's focused workspace; restore the slot views", with decision D-16 (reopen the seven slots now / later / by hand). Durable fix proposed: "remember the herdr workspace label the client is showing (the herdr-label-* Sway mark the picker sets, or the last title) and reselect it after every reattach … the reselect goes through the client UI."

**Rulings the builder should derive (INFERRED, each from a measured fact above):**
1. The rail must never call `herdr workspace focus` to steer one projector; it is global.
2. Slot identity comes from Sway marks (`herdr-slot-N`, `herdr-label-<label>`, `herdr-workspace-<id>`), never from the server's `focused_workspace_id` (herdr-picker docstring: "Never infer current identity from the server's global focus").
3. The rail should detect and show the collapsed state (several projectors showing the same herdr workspace) instead of hiding it; today nothing does.
4. "No real sleep" is a design choice Tom calls "very minimalistic": power menu = monitors off / backlight toggle / lock / logout / reboot / poweroff; do not add suspend by default.

### 2.3 GPUIX, OpenUI and the boundary (TOM, `~/tuesday-oct20/desktop-ui.md`, 10:45 CEST 2026-10-20)

Whole file, verbatim:
> https://github.com/remorses/gpuix#gpuix
> and not sure if related:
> https://github.com/khromov/gpuix-svelte
>
> the GPUIX project was analyzed in the past and i found that it was the best possible tool to base my project on when it comes to building front-ends.
> it would make us completely agnostic to building native linux wayland (thomas); macos (marwan); AND web (frank).
>
> the only boundary being of course the desktop shell, which would be exclusive to wayland-on-sway wm.
>
> the MASSIVE finding of the last few days:
> `https://github.com/thesysdev/openui` this openui project has the generative-ui philosophy that is exactly what i can use to have fully uniform deployments. extremely desirable, as i will have the same llm generate all the front-end tooling, starting from my desktop shell all the way to webapps like email etc.
>
> we build it once and it can be exported everywhere.

### 2.4 The sister project and the three heads (TOM, L751, queued 2026-10-20T12:03:43Z, 14:03 CEST)

> now orthogonally to that, the agency.agency prject becomes something i have concwptiaalized for uqite some time now:
> a unified gppuix to linux program ; macos program ; AND browser webapps tjhat work on chromium ALLL IN ONE
>
> openui https://github.com/thesysdev/openui as the toolking that grows with us (instead of a prefactirated https://gpui-kit.com/ )
> this is a shared project on the frontend; and building with the same root will be desirtable
>
> for my own personal usahgge, on swaywm, we havwe a saister project that is a gpuix shell that is no-quickshell (yhet we benefit from all the fresearech we had done in previous attempts at b uilding my personal ultimate shell from quckshell omarhcy; noctalia;l dankmaterialshell etc) this is a SEPARATE project that uses the same kernel and has its learnngs feed into this project
>
> being shortcut-vased (as one of the latest chats would have had given us) is also important to xconsider from the get go on this unifidd deskotp os.
>
> we have 3+ users (thomass , marwan, frank) at minimum so building a high quality polished product that s repeatable is highly desired)

Filed by the orchestrator (REPORTED, L763): desk T-38 reply, desk memory line, dotfiles T-14 reply (the sister-shell paragraph alone). Then MEASURED by the orchestrator (L769 result, `gh repo view` + README): thesysdev/openui = "The Open Standard for Generative UI", TypeScript, MIT, 12,405 stars, pushed 2026-10-19, "a framework-agnostic generative-UI framework built around a compact, streaming-first language" with first-party runtimes for React, Vue, Svelte and Android; gpui-kit.com = "a production-ready Rust UI framework with 75+ components and primitives" for GPUI. Orchestrator's INFERRED reading, filed for Tom to confirm (L774): OpenUI's language is the shared root; the project writes its own native runtime for the Linux and macOS programs; the stock web runtime serves the Chromium apps; gpui-kit at most a source of native primitives. (The BRIEF's decision 7 adopts exactly this: lang-core evaluator → GPUIX element mapping, bounded to `gpuix-shell ask`.)

The three heads, in Tom's words of 10-16/10-17 as the MAP quotes them (REPORTED, MAP.md:101): "we're building in a way that linux , macos native works AND in the browser there is an exact sister twin that is deployed on cloudflare worker or on 'local' …" (TOM 2026-10-16T23:43Z); "it s all gpuix but it s written in a way that it can also be selfhosted in a browser (that s in fact how i m doing it for frank)" (10-17). And on 10-18 (TOM, 683f L13): "a three-node group like that can 'share the secret sauce' over and over again" (Tom, Frank, Marwan).

### 2.5 What herdr-web-ui must do (the browser head), 2026-10-18 and 2026-10-20

TOM, 683f L318, 2026-10-18T11:51:40Z:
> on my strix (host) https://strix.tail8dd1.ts.net:8443/?ws=wHF-client-slot-8-fa2a21&pane=wHF%3Ap1&view=chat
>  i saw a rudimentary "projects" view that i m not sure what it  consists of.. "waititng on you"
>
> this shows me that we already have the mechanisms in place to dogfood this into completion.

What that view is (REPORTED, 683f L340, from `~/today/2026-10-14-convergence-soak/BUILD-SPEC.md`): "the rail from the Oct 14 convergence-soak fork. It has two 'Waiting on you' groups titled by source: herdr panes whose agent is blocked on a human, answerable in place through the prompt card (`POST /api/pane/prompt/answer`), and project decisions waiting on you read from the Worker's overview route (`GET /v1/overview`), which only link out and never answer in place. It deliberately never calls the show route because show marks posts read." The session's acceptance rule, in its own words: "a surface you can look at and drive, which is your own standing acceptance rule."

TOM, 1a51 L685, 2026-10-20T11:56:43Z:
> ffrank's state constraint is: everythig as a webapp. he wants herdr-chat0ui as is on mine; so i need to install it for him on his mac, so i need ssh ability through tailscsale and he must dfo that in perso onb his remote viewer.
> from there i will give him access to my created tools and utilities; and start step by step dematerializign his claude usage (artifacts, prompts, routines ,etc) away from claude desktop/web and onto his own dotfiles plus cloudflare-deployed items.

So: herdr-web-ui must (a) be installable as-is on a second owner's Mac and reachable in his browser over his tailnet ("the same chat in his browser", REPORTED L856), (b) carry the Waiting-on-you rail (blocked panes answerable in place; decisions linking out), (c) stay the browser twin of the same product; the Sway shell is NOT it, the shell only launches it (BRIEF decision 8). MEASURED facts about the fork from the MAP (REPORTED, MAP.md:99): `~/mecattaf/herdr-web-ui` at e85ffd1, 29 commits over upstream 42c6332 (v0.4.8; upstream now 0.4.11), Claude and Noir palettes, Anthropic faces, 220 px rail "with Chrome Views proportions (220/196/30/12/2/8 lifted from views-shell)", `/utilities` GET-only Worker counts, `/workspaces` ("made in slot N"), palette, strip, bell, fixture calendar, fixture-only agents lens; runs as transient unit `herdr-web-ui-morning` on 127.0.0.1:7318 behind an imperative `tailscale serve` on 8443; cannot go public with the Anthropic fonts ("DO NOT RELITIGATEON THATONE"). Open decisions desk T-30 D-12/D-13/D-14: merge #565; keep/declare the 8443 door; default lens chat vs `auto` (MAP.md:216).

### 2.6 The MAP's section 5, provenance kept (REPORTED: workflow output embedded at 1a51 L644; file MAP.md:93-111)

The older rulings below were NOT typed in either of my two sessions; they reach this source through the 15-reader map. Cite MAP.md, not the jsonl, for them.

- Compositor: "Sway is the only compositor (scroll, niri, piri removed 10-13; Hyprland tried 74 minutes and dropped by Tom at 00:25 CEST 10-14)." (MAP.md:95)
- Look: "whatever you just opened: i love it. this is good enough to also become a functional remplacement to waybar, vicinae and mako notifications." (TOM 10-14 00:16, via MAP.md:95). "That approval is a Chrome rendering; Primer's DOM components do not run inside GPUIX." Tom's bound: "gpuix is a cool project but we can use it as stylistic inspiration if it's not adapted"; "'supplies another renderer' is fine for something that' react plus generic compositor functionlaity" (TOM 10-13 23:19/23:21Z).
- GPUIX limits measured 10-14 (REPORTED): Linux not in CI, a layer surface cannot choose its output, no zoom, one renderer per window.
- herdr: "herdr stays central; with even more synergy with the sway workspaces now" (10-14 01:26); "for SURE herdr is mainstay in my setup and it s really the centerpiece of dotfiles" (10-17 01:09Z). herdr 0.9.4 (#563) adds a confirm-close prompt "that hits almost every close under the 1:1:1 mapping; T-18 must judge it before merge." (MAP.md:96)
- Sway slots code: PR #565 (Mod+i top-display switcher reading `get_workspaces` live with herdr status sampled read-only, fuzzel, Mod+Shift+m opens the desk; OPEN) and `feat/herdr-sway-context` c1a49b99 (Mod+grave swaps Kitty and a Chrome app window of the 8443 page in one tile; `herdr-attention` turns blocked agents into Sway urgency and mako actions; 69 tests; needs `config.toml` `window_title = "{hostname}: {workspace}"`). "Neither enforces the nine-slot cap or the 1:1:1 shape by construction." "The runtime Mod4+i and F1/F2 binds installed on the live Zenbook on 10-14 were lost at its ~10-17 19:51 reboot (INFERRED)." (MAP.md:97)
- Design kit defaults taken for Tom (REPORTED MAP.md:103): "clay never marks selection, working is blue, Source Serif 4, collapsed rail 56, task strip not drawn"; X1 board options waiting on him: "bottom app bar, rail inside the chat window, task strip, square corners". 93 component ids, X1–X14 compositions, DTCG tokens, brand #D97757; SHELLS-DIGEST U-01..U-19 "Mod+I kept; no top bar on the Linux head".
- Pixel ban: "the one thing i m avoiding is the screenshot mechanism" (MAP.md:105): no screenshot reaches an agent.
- Superseded chain (MAP.md:247, critic 1): "we keep vicinae" (10-12) → Primer shell replaces waybar/Vicinae/mako (10-14; retirement not yet ruled); Hyprland (21:52Z) → Sway (22:26Z); "swaywm integration is fluid" coexists with the 1:1:1 nine-slot shape (10-20).
- Earlier taste rulings in the MAP timeline (MAP.md:21-23): 10-07 "i never needed skia.. i never even needed blur (let alone frost). this means that we can do a deep pass into listing what we can remove altogether as no longer needed."; 10-07 Vicinae pivot "i am going all the way to returning to sway and waybar and mako".

### 2.7 Feature wishes in Tom's tab notes (TOM, `~/tuesday-oct20/tabs-client.md` 11:12 CEST, `tabs-phone.md` 11:08 CEST)

tabs-client.md:
> 3) … in parallel i saw a user build a raycast clone for omarchy https://github.com/typecraft-dev/oma-cast which is interesting to have
> 5) omarchy (linux) tooling that does the same or similar to what i m trying to achieve in my config
> https://github.com/jankeesvw/omarchy-meeting-recorder similar to my own meeting recorder
> voxtype ; similar to what i use already. would be split into herdr-compatible "hold to transcribe" and similarly this functionality in herdr-webui
> same with "speak"; both a button and a skill
> https://github.com/brogrammerMW/herdr-voice
> 7) … https://github.com/asgeirtj/system_prompts_leaks/blob/main/Anthropic/claude-in-chrome.md … i found that the instructions here could be useful to modify for my own usage; specifically to navigate my sway wm setup
> but also https://github.com/amontlabs/lcu which is the decoupled codex computer use ; but is unsupported for native wayland which is not great; so i would port it over
> 8) memory tool for all my previous clicks https://github.com/screenpipe/screenpipe/blob/main/docs/VISION.md … at minimum, it lets me query screen usage history. but in my case this goes beyond recall ; it may be what lets me to "memory" and understand how i use the device
> 9) screenshot annotation tool https://github.com/faetalize/waytator was found interestingly ; but in my case we will want to have that in gpuix for the desktop. can still re-use the functionality presented by this tool
> 10) full quickshell desktop suite example, looks very nice https://github.com/ciscobugger/tacit already extracted the dotfiles fro mthe iso ; this user finally released the dotfiles on github as well. great inspiration for writing the gpuix project for a linux wayland shell

tabs-phone.md:
> 2) ai-native desktop oprating sytem https://github.com/StuardAI/ada i really liked the "apps" that are provided for htis desktop. another less related window manager: https://nongio.github.io/otto/scripting/ could do the same "scripting" for my world
> 3) add to screenpipe maybe https://github.com/agent-sh/computer-use-linux https://github.com/snake-aabb-wtf/computer-use-agent this should let us do computer use on the sway wm? good to have, can stack them up
> 6) some gpui and herdr things https://github.com/penso/herdr-gpui in my case we just have to add swaywm in here and we're good
> https://github.com/devswha/herdr-web-ui being developed FAST! v0.5 will be big

### 2.8 Operating rulings that bind the night (TOM, 1a51)

- L493, 11:05:15Z: "ultracode worlflows enabled. do a full mapping of wqhat has happened in the last few days very important ly including the cologne items, the spec as prep; the unified gpuix workspaces." and "the last 14 days' worth of jsonl files must be saved at minimum" (saved: `/mnt/nas/documents/session-backups/2026-10-20-last14d/`, 3.4 GB, MEASURED L634).
- L539, 11:07:25Z: "use generous amounts of compute for this workflow. 10 fable agents, and 25-30 opous agents. maximum output"
- L724, 12:00:03Z: "NO WALL CLOCKS ESTIMATES ever." (said of Frank's plan; the orchestrator applied it to every plan it wrote after 14:35 CEST).
- L687, 11:57:01Z: "the cologne nick is NOT nick feller (canada)." (CRM, not shell.)
- 683f L13, 10-18 11:23Z: "heuristic is maximal dogfooding; and building for hte greatest common denominator"; "it's no longer a matter of 'can this be built' it becomes a matter of 'build me X' and it pulls the styletransfer from another existing implementation."

---

## 3. Feature and behaviour inventory

| # | Feature | What exactly | Where it lives today (path:line, worktree dadb1426) | Keep / replace / new | Notes |
|---|---|---|---|---|---|
| 1 | Nine Sway slots on the top panel | `workspace 1..9 output eDP-1`, `workspace 10 output eDP-2`; `$mod+1..9` / `$mod+0`; `$mod+Shift+N` moves | `home/dot_config/sway/binds.conf:49-80` | keep | TOM 10-20: limit of 9, "helps with my mental overload". Rail shows 1–9; slot 10 is Chrome on the bottom display (BRIEF). |
| 2 | One projector per slot | kitty `--class herdr-projector -e herdr-sway-projector` → `herdr --remote strix --remote-keybindings server` in a reconnect loop | `home/dot_local/bin/herdr-sway-projector` (18 lines), `herdr-projector` (213; backoff 1,2,5,10,30 s at :33 and :170-212; env `HERDR_PROJECTOR_TARGET/SSH/UNIT` :72-75) | keep (fix reattach) | After reattach the window lands on the server focus (:35-36). The durable fix is T-25; the rail must tolerate the collapsed state. |
| 3 | Slot identity marks | Sway marks `herdr-slot-N`, `herdr-label-<client\|strix>-slot-N-<hex6>`, `herdr-workspace-w…`, `herdr-closed-<n>`, `herdr-name-<hex>` | `home/dot_local/bin/herdr-picker:24-29`; `slot_of` :75, `projectors` :83, `available_slot` :99-105 | keep as the rail's identity source | Docstring :3-6 "Never infer current identity from the server's global focus." `available_slot` raises when all nine are taken: "All nine Herdr slots are occupied or parked." |
| 4 | Workspace chords | Mod+Return new projector (`herdr-chord new`), Mod+Ctrl+Shift+Return projector with agents sidebar, Mod+Ctrl+space picker; Mod+t/w/Shift+t/Shift+n via `sway-workspace new\|close\|restore\|rename` | `binds.conf:8-15`; `herdr-chord` (24 lines, all verbs → `herdr-picker --chord`); `sway-workspace` (8 lines → `herdr-picker --workspace`) | keep the verbs; the picker's Vicinae menu (`vicinae_menu` :211, `dmenu` :261) is what the launcher/switcher replaces | The menus are the only Vicinae dependency inside the slot logic. |
| 5 | Mod+i top-display switcher with herdr status | fuzzel list of `get_workspaces` with herdr status; Mod+Shift+m opens the desk | unmerged PR #565, `/home/tom/.wt/dotfiles/morning-shell` (REPORTED MAP.md:97) | replace by `gpuix-shell switcher` | Desk D-12 "hold #565" pending; runtime binds lost at the 10-17 reboot. |
| 6 | Mod+grave kitty/Chrome swap, blocked-agent urgency | `herdr-attention` → Sway urgency + mako actions; needs `window_title = "{hostname}: {workspace}"` | branch `feat/herdr-sway-context` c1a49b99 (69 tests; REPORTED) | fold into rail + notifications daemon | `config.toml:96` today has `window_title = ""`. |
| 7 | herdr read-only data | `herdr workspace list` → `{number,label,tab_count,pane_count,focused,agent_status,active_tab_id,workspace_id}`; `herdr api snapshot` → `.result.snapshot.{workspaces,agents[{workspace_id,agent,agent_status,cwd,terminal_title_stripped}],panes[].terminal_title_stripped,focused_workspace_id}`; statuses seen: unknown, idle, working, done, blocked | MEASURED L181, L287-L306, L411 | keep (poll) | Agents list is the rail's status source; `herdr pane read <id> --source visible --format text` gives the screen (L418). |
| 8 | herdr focus is global | `herdr workspace focus <id>` moves every attached projector | MEASURED L605 | never call from the shell | Steering one view = client-UI keys only (prefix+b sidebar ● marker, navigate). |
| 9 | Cull rule for idle herdr workspaces | candidate = not in keep set, `tab_count==1 && pane_count==1`, pane title a bare cwd (`~`, `~/today`, `~/m/dotfiles` …); skip nvim panes (title `nvim <file>`, and INSERT ● = unsaved) | MEASURED L411-L431: 225 candidates, 3 nvim kept, `herdr workspace close <id>` → `{"type":"ok"}`, 222 closed, 13 left, 9 agents intact | new: a "close idle shells" action in the switcher/controls | Tom: "TONS of herdr workspaces that qre inactive and that we can kill". |
| 10 | Start-of-day sheet | table slot / herdr ws / seat / cwd / conversation / state / waiting-on; resume commands | `~/tuesday-oct20/start.md` (hand/agent written each day) | new surface candidate: live "day start" view in the switcher or a `gpuix-shell desk` page | TOM L243 "starting the day read up ion all otehh herdr sessions and tabs i just closed". |
| 11 | Launcher Mod+d / Mod+space | `vicinae toggle`; clipboard Mod+v `vicinae cmd launch clipboard:history`; Chrome native-messaging link | `binds.conf:6-7,114`; `home/vicinae.nix:25-99` (vicinae-browser-link glibc errors in the client journal, L157) | replace (`gpuix-shell launcher`, own clipboard store) | `startup.conf:4` "Vicinae owns clipboard history; do not start a second cliphist watcher" → the shell becomes the one watcher. |
| 12 | Notifications | mako via HM `services.mako` with `include ~/.config/theme/mako.conf`; makoctl dismiss/restore binds; `osd` script = one replaceable notify-send with `-r <id>` and `int:value` progress, 1500 ms | `home/vicinae.nix:111-166`; `home/dot_local/bin/osd` (38 lines); theme fragment `home/themes/default.nix:127-139` | replace (daemon + toasts + OSD) | `osd` contract to keep: `osd <title> <body> [percent]`, id file `$XDG_RUNTIME_DIR/osd-notify.id`, exits 0 where no daemon. |
| 13 | Hardware keys | F3-F8 media/volume, F9 audio-route prompt, Shift+F9 call-record, F2/Shift+F2 theme/accent prompts, F10 sleep-monitors (repo) / brightness toggle (client), Shift+F10 pomodoro, XF86 keys `--locked`; Menu = touchpad toggle | `binds.conf:129-157`; `home.nix:149-168` (client block; Shift+F5/F6 = 2% steps; XF86AudioMicMute) | keep scripts, replace the fzf prompts with controls/OSD | `brightness` (193 lines): verbs up/down/off/restore/toggle, `brightnessctl --min-value=1`, each verb ends in one `osd` (:27, :179-181). |
| 14 | fzf-in-kitty prompt tier | `$prompt = kitty --class`; floats 640×200 (sleep-monitors/audio-route/call-record) and 640×300 (theme/pomodoro), centred, `border pixel 2` | `binds.conf:4`, `rules.conf:10-13` | replace with `gpuix-shell controls` menus | These are the menus Tom means by "mod+d menu … that presents a given functionality". |
| 15 | Monitors off / no sleep | Mod+Shift+p `monitors-off` (one-shot swayidle resume); F10 backlight toggle; "not implementing real sleep … very minimalistic" | `binds.conf:~127`; `home/dot_local/bin/monitors-off`, `sleep-monitors`, `brightness:38-42,135-149`; `hosts/client/lid.nix` | keep; power menu mirrors it | TOM L203. Lid: `bindswitch lid:on output eDP-1 disable` (home.nix:156-157). |
| 16 | Zenbook Duo outputs | eDP-1 scale 2 at 0,0; eDP-2 scale 2 at 0,900 (logical 1440×900 each, stacked); touch → eDP-1; kanshi; daemon mirrors backlight and re-emits Fn keys (fn_lock on) | `home.nix:149-152`; `modules/zenbook-duo-daemon.nix:1-60`; `startup.conf:5` | keep | Layer-shell rail anchors on eDP-1 only (GPUIX "a layer surface cannot choose its output" is a REPORTED 10-14 limit — verify on 0.11.0). |
| 17 | Chrome handling | `for_window [app_id="^chrome-.*"] shortcuts_inhibitor disable`; Chrome app window of the 8443 desk | `rules.conf:1-2`; Mod+grave branch | keep | Slot 10 = Chrome on eDP-2. |
| 18 | Theme pointer | `include ~/.config/theme/sway.conf`; `exec theme apply` at start; fragments kitty/ghostty/sway/mako/vicinae/fish/lua/meta rendered per theme; `output * bg #000000 solid_color` | `sway/config:10`; `startup.conf:10`; `home/themes/default.nix:19,75,115,127,140,181,204,224,281` | keep; add a `gpuix-shell.json` fragment | Token names used by the sway fragment: `t.border.active/inactive`, `t.ground.base/raised`, `t.fg`, `t.fgDim`, `t.red`, `t.selection.bg`. |
| 19 | Night light / cursor | `wl-gammarelay-rs run`; cursor Bibata-Modern-Classic size 48; text-scaling 1.0 | `startup.conf:3,6-8` | keep; controls may expose gamma over its D-Bus | New feature candidate for `gpuix-shell controls`. |
| 20 | herdr-web-ui desk (browser head) | Waiting-on-you rail (blocked panes answerable in place; decisions link out), `/utilities` counts, `/workspaces` "made in slot N"; 7318 behind `tailscale serve` 8443 | `~/mecattaf/herdr-web-ui` e85ffd1; `~/today/2026-10-14-convergence-soak/build` (unit `herdr-web-ui-morning`) | keep, launched by the shell; must install as-is on Frank's Mac | TOM L318, L685. Not built in dotfiles (BRIEF 8). |
| 21 | Native kit (Marwan's head) | `@agency-agency/kit` 0.1.0, four native windows, passed only on a GitHub macOS runner | REPORTED 683f L353 summary | separate | Sister project shares the kernel, not the code (TOM L751). |
| 22 | OpenUI generative surface | OpenUI Lang streamed from the local model → native render | REPORTED L769/L774; BRIEF decision 7 | new, bounded (`gpuix-shell ask`) | TOM desktop-ui.md: "the same llm generate all the front-end tooling, starting from my desktop shell all the way to webapps". |
| 23 | Voice | "hold to transcribe" split herdr-compatible + in herdr-webui; "speak" both a button and a skill; herdr-voice is macOS-only | tabs-client.md item 5; existing `speak` skill and `speak-clipboard` bind `binds.conf:36` | new candidates (rail buttons) | Low priority tonight; note only. |
| 24 | Screenshot annotation | waytator-like, "in my case we will want to have that in gpuix for the desktop" | tabs-client.md item 9; `screenshot`, `screen-ocr-area` (`binds.conf:46`) | new candidate | |
| 25 | Computer use on Sway / screen memory | lcu port to Wayland; screenpipe-style usage history; claude-in-chrome prompt adapted to "navigate my sway wm setup" | tabs-client.md 7-8, tabs-phone.md 3 | out of scope tonight | Pixel ban stands for agents (MAP.md:105). |
| 26 | Raycast-style launcher reference | oma-cast (omarchy) "interesting to have" | tabs-client.md 3 | reference for `gpuix-shell launcher` | |
| 27 | Tacit as aesthetic reference | "great inspiration for writing the gpuix project for a linux wayland shell" | tabs-client.md 10; `/home/tom/saturday-tacit` (BRIEF) | reference | Same as BRIEF §1. |

What to kill (from these sources): the 222 idle herdr workspaces (done 11:02Z); the fzf-in-kitty prompt tier once controls exist (#14); Vicinae and mako once the shell is enabled (BRIEF: never both); nothing else was named for removal in these two sessions. The MAP adds hygiene items Tom has not ruled on: `~/.wt/hyprland-solid-shell` (Hyprland staged) to commit or discard (MAP.md:239).

---

## 4. Design values found in these sources

Measured in these two sessions: almost none. The ones below are REPORTED (MAP, design-handoff) or MEASURED from config files the session read; take them as the floor, not the kit.

| Value | Number | Source | Label |
|---|---|---|---|
| Panels | eDP-1 and eDP-2, scale 2, logical 1440×900 each, eDP-2 at y=900 | `home/home.nix:150-152` | MEASURED (file) |
| Prompt floats | 640×200 px and 640×300 px, centred, border 2 px | `rules.conf:12-13` | MEASURED (file) |
| OSD timeout | 1500 ms, one replaceable notification, `int:value` progress | `osd:27-33` | MEASURED (file) |
| Brightness step | 10% (Tom 2026-09-14), fine 2% with Shift, floor 1 raw unit | `brightness:3,13`; `home.nix:161-166` | MEASURED (file) |
| Projector reconnect backoff | 1, 2, 5, 10, then 30 s; a link held ≥60 s resets the backoff | `herdr-projector:33,208` | MEASURED (file) |
| Cursor | Bibata-Modern-Classic, size 48 | `startup.conf:6-7` | MEASURED (file) |
| Wallpaper | `#000000 solid_color` | `themes/default.nix:122` | MEASURED (file) |
| Sway colours | `client.focused` border/bg/text from `t.border.active`, `t.ground.base`, `t.fg`; urgent = `t.red` | `themes/default.nix:115-123` | MEASURED (file) |
| mako theme | bg `t.ground.raised`, text `t.fg`, border `t.border.active` (low: inactive, high: red), progress `t.selection.bg`, `default-timeout=0` | `themes/default.nix:127-139` | MEASURED (file) |
| Rail geometry (desk) | 220 px rail, proportions 220/196/30/12/2/8 "lifted from views-shell"; collapsed rail 56 | MAP.md:99,103 | REPORTED |
| Brand | #D97757; Source Serif 4 as the card default; "working is blue"; "clay never marks selection" | MAP.md:103 | REPORTED |
| Fonts | Anthropic Sans / Serif / AnthropicMono Nerd Font (never public) | MAP.md:95,99 | REPORTED |
| Timings (incident) | reconnect 2 s after Wi-Fi join (11:39:24–25); human closes 1/s | L150, L194 | MEASURED (tool) |
| herdr status glyphs | blocked ◉ / working ◐ / done ● / idle ✓ / unknown ○ | BRIEF §1 (not in these sessions) | REPORTED |

---

## 5. Reusable code and data, exact paths

Worktree `/home/tom/.wt/dotfiles/gpuix-shell` (dadb1426, MEASURED `git log -1`):

- `home/dot_local/bin/herdr-picker` (574 lines, Python 3): the Sway/herdr bridge. Reuse: the mark grammar (:24-29), `walk`/`views`/`projectors`/`slot_of`/`available_slot` (:63-105), `focused_workspace` with the layer-shell fallback (:87-96), `quote_sway` (:108-113), `desktop_lock` (`$XDG_RUNTIME_DIR/herdr-sway.lock`, :116-124), `remote_snapshot` (:163), `identity`/`assigned_identity` (:186-203), `client_ready` screen check before typing (:292), `ensure_projector` (:338). Port the logic to TypeScript for the rail; keep the mark names so the Python and the shell agree during the transition.
- `home/dot_local/bin/herdr-projector` (213 lines): keep as the projector; the T-25 fix (reselect by label after reattach) goes here, not in the shell.
- `home/dot_local/bin/herdr-sway-projector` (18 lines), `herdr-chord` (24), `sway-workspace` (8): thin wrappers; the shell's CLI can replace them verb for verb (`new|close|detach|rename|restore`, `new|sidebar|rename`).
- `home/dot_local/bin/osd` (38 lines): the OSD contract. The notifications daemon must honour `notify-send -p -r <id> -a osd -h int:value:<pct>` exactly, so `brightness`/`volume` keep working unchanged.
- `home/dot_local/bin/brightness` (193), `volume` (37): keep; they call `osd`.
- `home/dot_config/sway/binds.conf` (157 lines): the key map to preserve; lines to retarget: 6-8 (launcher/picker), 114 (clipboard), 129-151 (prompts). `rules.conf` (13), `startup.conf` (11), `config:3-10` include order.
- `home/dot_config/herdr/config.toml` (309 lines): `[keys] prefix = "ctrl+b"` (:23-26), `[session]` lifecycle rule (:63-75: closing a projector or prefix+q DETACHES; explicit exit CLOSES), `[ui] window_title = ""` (:96), the prefix cheat sheet (:98-111: prefix+w picker, prefix+g navigator, prefix+shift+n new, prefix+shift+d close, prefix+q detach, prefix+b sidebar).
- `home/home.nix:149-168`: the client Sway block (outputs, lid, F10, brightness keys).
- `home/themes/default.nix:115-139`: the sway and mako fragments and their token names; add `gpuix-shell = t: ''…''` beside them and a `render` entry (:281).
- `home/vicinae.nix:111-166`: the mako service definition the HM module must not co-exist with.
- Data: `/home/tom/tuesday-oct20/start.md` (the nine-slot table of 10-20, the shape of a "day start" view); `/home/tom/tuesday-oct20/MAP.md:93-111` (§5) and `:185-258` (decisions, contradictions); tool outputs inside the transcript at L181 (235-workspace list), L412 (cull candidates with title histogram), L431 (the 13 survivors), L605 (focus test).
- The orchestrator's measured T-25 reply (L633) is the best spec of the reattach-restore automation path (read the sidebar with `kitten @ get-text`, step with navigate until the ● sits on the slot label, hide the sidebar; test on a fresh projector in a scratch Sway workspace first; check herdr 0.9.4's navigate keys).
- Other sessions these two point at (not read here): `~/.claude/projects/-home-tom-today/{f3cd04ae,56e498e4}` (10-14/10-16 shell rulings), Codex `01a1370e` (GPUIx pivot), `01a13780-*` (desktop-shell builds); workflow journals `/home/tom/.claude/projects/-home-tom-mecattaf-dotfiles/1a517fb2-…/subagents/workflows/wf_ea4bb73a-4a6/journal.jsonl` (the 15 MAP readers' full returns, including the "gpuix-code" reader the MAP cites).

---

## 6. Gaps and unknowns

1. **No first-hand 10-14/10-16 shell rulings here.** "whatever you just opened: i love it…", "herdr is the centerpiece", the three-head sentence of 10-16 and the design-kit defaults reach this source only via the MAP (second-hand, critic-corrected). Their primary lines are in the `-home-tom-today` sessions f3cd04ae / 56e498e4, assigned to other readers.
2. **D-16 is unanswered.** Whether the seven Zenbook slots were reopened after 11:04Z is not in the transcript; the Zenbook still showed workspaces 1 and 3 only at 10:53Z. Tonight's compositor tests must not assume nine projectors exist.
3. **The reattach fix is unbuilt.** T-25's "durable fix in herdr-projector" is a brief, not code; the shell's rail will meet collapsed states until it lands.
4. **herdr 0.9.4 (#563)** may change navigate keys and adds a confirm-close prompt that collides with the 1:1:1 mapping (T-18 to judge). The shell's close-slot action should be written against 0.9.3 and re-checked.
5. **Vicinae retirement is not ruled**, only implied ("retirement not yet ruled", MAP.md:247). The BRIEF's `programs.gpuixShell.enable` exclusivity is an assumption, not Tom's word in these sessions.
6. **The sister-project filing is INFERRED in one place**: the orchestrator's reading that OpenUI's language is the shared root with a project-written native runtime was filed "for Tom to confirm" (L774). Tom has not confirmed it. The BRIEF's decision 7 keeps it bounded, which is the safe reading.
7. **Design values are REPORTED only.** Nothing in these sessions measures a rail width, radius, font size or timing for the Linux head; the handoff pack (`/home/tom/today/2026-10-17-frank/design-handoff/`) is the place, assigned elsewhere.
8. **Client uid is 1001** (Zenbook) vs 1000 (strix) and the client is reachable only over Tailscale with `HostKeyAlias=client`: any smoke test that targets the Zenbook needs both facts; nothing in the BRIEF says so.
9. **`transcript-text.py` misses queued messages** (§1a). Every other reader using `--user-only` on a busy session will miss Tom's mid-turn words; the MAP's own 15 readers may have, too (the MAP does quote L218, so at least that one was caught through the filing).
10. **The 683f session's plan (L340)** proposes "Rulings week … nothing new dispatches until the 23 waiting items … are marked"; tonight's build proceeds on Tom's 22:50 order, which is newer and wins, but the sixteen open dotfiles/desk decisions in MAP.md:185-232 (D-12 … D-16, T-14, T-18) remain unruled.
11. Not verified tonight: the live state of herdr (workspace count after the cull may have changed), the Zenbook's Sway, or the 8443 desk. This reader ran only `ls`, `wc`, `git log -1`, `grep`/`sed` on the worktree and Python over the two jsonl files; nothing was started, focused, closed or filed.

End of note.
