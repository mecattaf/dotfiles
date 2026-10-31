# 09 — Codex transcripts of 2026-10-20 (the "rest"): Recover Sway view toggle + the memory/parity subagents

Reader note for the overnight gpuix-shell build. Read-only extraction; nothing in the sources was
changed. Labels: **MEASURED** (a command in these sessions observed it, or I re-measured it tonight
from a file on disk), **REPORTED** (a session or a project record says so; not re-checked tonight),
**INFERRED** (my reading). Times are UTC with CEST (= UTC+2) in brackets where it matters.

Pointer convention: `S1:L9` = physical line 9 of the S1 JSONL file below (open with
`sed -n '9p' FILE | python3 -m json.tool`). Repo pointers are `path:line` in the gpuix-shell worktree
`/home/tom/.wt/dotfiles/gpuix-shell` (base `dadb1426`) unless another root is named; I checked
that the worktree lines match the cited ones.

---

## 1. What this source is

Five Codex rollouts from 2026-10-20, all with cwd `/home/tom/tuesday-oct20`, Codex CLI 0.160.0.
Directory: `/home/tom/.codex/sessions/2026/10/20/`.

| Tag | File | Role | Window (UTC) | Desktop relevance |
|---|---|---|---|---|
| **S1** | `rollout-2026-10-20T16-36-21-01a159bd-ed15-7303-8970-e758368aaf07.jsonl` (259 lines) | **Root session "Recover Sway view toggle"**. Tom typed into it directly. Spawned 3 subagents: `sway_mapping`, `toggle_history`, `parallel_chat` | 14:39:22 → 14:54:01 (16:39–16:54 CEST) | **HIGH**: 6 direct Tom turns on the terminal/chat toggle, clui-cc, Nautilus picker, OpenUI, herdr-web-ui aesthetic |
| **S2** | `rollout-2026-10-20T16-39-51-01a159c1-1f31-7962-9ee9-ca4dada71ca6.jsonl` (98 lines) | Subagent `/root/parallel_chat` ("Mendel") of S1 | 14:39:51 → 14:41:01 | MEDIUM: live `herdr workspace list` / `agent list`, finds the parallel OpenUI chat and Tom's 16:12/16:22 turns |
| **S3** | `rollout-2026-10-20T14-10-32-01a15938-6c51-7993-b880-12baeb8b9dcd.jsonl` (2984 lines) | Subagent `/root/claude_history` ("Laplace") of root Codex `01a15935` ("Check for memory model notes", herdr pane `wHP:p1`) | 12:10 → 14:44 | MEDIUM: memory research first, then estate audit (captured all project threads to evidence JSON), then built the **shared-parity web UI**, the A11Y chapter and the native F6/F7 activity proof |
| **S4** | `rollout-2026-10-20T14-10-39-01a15938-89d0-7e53-b4de-9f80899d0549.jsonl` (2503 lines) | Subagent `/root/codex_routines` ("Lovelace") of `01a15935` | 12:10 → 14:34 | **HIGH for measurements**: read-only live inspection of the Zenbook Sway tree, herdr snapshot, kitty projectors (12:14–12:20Z); later built shared-parity core + native GPUIx evidence manifest |
| **S5** | `rollout-2026-10-20T14-11-34-01a15939-5f60-7433-8fcc-c59fd32bc16a.jsonl` (881 lines) | `codex exec` fourth investigator for `01a15935` | 12:11 → 13:34 | LOW: memory/routine architecture, intent ledger; desktop content only via quoted Tom turns |

Not in my list but their answers are inside S1: subagents `sway_mapping` (`01a159c0-f52e`, final at
S1:L133) and `toggle_history` (`01a159c1-07a7`, final at S1:L180). The root `01a15935` session itself
(4585 lines) belongs to another reader; I quote three of its Tom turns because S2 and S5 surfaced them.

**Important side products of these sessions that live on disk (all MEASURED present tonight):**

- `/home/tom/tuesday-oct20/research_notes/Memory policy and harvest history/05-live-workspace-intake.md`
  (139 lines; S4 wrote it at 12:20Z) + `live-client-sway-tree.json`, `live-herdr-snapshot.json`,
  `live-client-workspace-{1..7}.txt`, `live-pane-*.json` — a frozen photograph of the Zenbook desktop.
- `/home/tom/tuesday-oct20/research_notes/Project contracts and implementation assessment/evidence-project-state/`
  — S3 captured every project thread as JSON at ~12:57Z, including the desktop threads
  `dotfiles-T-{2,14,18,19,25}-2026-10-20.json` and `desk-T-{30,31,32,38,40}-2026-10-20.json`.
  Those JSON files carry **Tom's verbatim messages with timestamps**; section 2 quotes them.
- `/home/tom/tuesday-oct20/build/shared-parity/` — evidence + docs + native GPUIx adapter that S3/S4
  built and measured (another reader covers the code; I record what was measured).

The image Tom pasted at S1:L168 (the claude.ai search palette) is embedded in the JSONL as base64;
the clipboard file `/tmp/herdr-clipboard-images-1000/client-413-...png` is gone. I extracted it to
`/tmp/claude-1000/-home-tom-tuesday-oct20/94d008d7-4112-4bf7-92cd-2de4eab69681/scratchpad/r09/tom-palette-shot.png`
(1695×1467 px). **A builder should copy it into `docs/gpuix-shell/assets/`**. Re-extract with:

```sh
python3 - <<'PY'
import json,base64
f='/home/tom/.codex/sessions/2026/10/20/rollout-2026-10-20T16-36-21-01a159bd-ed15-7303-8970-e758368aaf07.jsonl'
l=open(f).read().splitlines()[167]          # S1:L168
for c in json.loads(l)['payload']['content']:
    if c.get('type')=='input_image':
        open('claude-ai-search-palette.png','wb').write(base64.b64decode(c['image_url'].split(',',1)[1]))
PY
```

---

## 2. Verbatim Tom rulings relevant to the desktop shell

Typos are Tom's. Ordered newest first inside each group. "Newer is truer" (Tom's standing heuristic,
quoted in desk T-38 root 2026-10-16).

### 2a. Typed directly into S1 today (2026-10-20)

**T1 — 14:39:23Z (16:39 CEST), S1:L9 — the toggle and the 1:1 mapping**
> in dotfiles repo: i had a mechanism i was trying to achieve whereby i could "toggle" between herdr-web-ui web view and terminal view. on my own dotfiles sway implekentation, this switch is a little "special" as we can toggle between a native termoinal and a gpuix based chat window.
> there are fragments of this in the parallel chats i m having (see other herdr workspaces) as well as jsonl chat history regrding specificllay this "sway tabbed view that we toggle, without having a highlight that changes.
> recover this w a few subagents. dnt implement anything just let me know
> i hope youo ll apreciate hwio cucrently swaywem workspaces have one to one with herdr and the kitty termianl carrying it.
> gpuix chat window based competely on the herdr-web-ui is unbuilt but should not be too difficult. check the other codex chat herdr thta isopen, about using shortcut-driven accessibility funcitonality plus openUI in order to achireve a parallel with the claude.ai web chat interface

**T2 — 14:50:19Z, S1:L168 — clui-cc, the palette screenshot, the Nautilus picker**
> [Image #1: claude.ai search palette, see §4a]
> what makes claude ai's webui so powerful is [Image #1]
> we can in fact now come full circle with https://github.com/lcoutodemos/clui-cc something that i had previously. that was immensely interresting. however we have more modern tools now. the gpuix implementation can enter flawlessly. the only thing we can retain from before is the nautilus file picker (same as what google chrome uses) ; and the clui-ccc behavior (using the "unified" components collectin that i have. and it will intergrate with herdr-web-ui the same way.

**T3 — 14:50:54Z, S1:L202 — experimental, OpenUI start, herdr-web-ui look not yet "dematerialized"**
> this is an ambitious and experimental run. openUI as a starting point, the esthetic that exists in myown https://strix.tail8dd1.ts.net:8443/?ws=wHP-client-slot-7-695519&pane=wHP%3Ap1&view=chat implementation that s a good starting point - yet not yet "dematerialized"

**T4 — 14:51:52Z + 14:51:58Z, S1:L233 + S1:L243** (one sentence split across two sends)
> that's a herdr-web-ui that / s at a previous version that is deployed locally

**T5 — 14:53:57Z, S1:L253 — the scope sentence for the chat surface**
> well, no need for an "older" one. it s just the clui-cc reimplementation in gpuix really, with attention to herdr-centrality

The assistant filed T2 and T3 into `project memory dotfiles` (S1:L189, S1:L220). Its closing
paraphrase (S1:L256, assistant, not Tom): "reimplement clui-cc's experience in GPUIX using your
unified components and OpenUI, with Herdr owning the sessions throughout ... Keep the existing native
file picker. Your deployed web UI supplies aesthetic guidance; its version isn't a requirement."

### 2b. Tom turns of today quoted inside these sessions (verbatim from their original records)

- **2026-10-20 14:22:36Z** (root `01a15935` L3470, surfaced by S2): "we will "find the ideal tool" to write gpuix plus cf workerd deployed as we go. react , solidjs (leaning towards react). what about the 'kb shortcut accessibility feautre" cha[ter?"
- **2026-10-20 14:12:30Z** (root L3126, surfaced by S2): "understand again: it is important that fron t end we buikld built from the ground up with openUI methodology AND thezhortcut driven method as well (so that my human clicks on the webUI is the same as an agwent's usage of the api with "trailing clicks" happening by another aent thst just shows what is being worked through. the above being the final desired design implementation. just building yet anoter email frontend now without accumulating these insights and making it parity between gpuix and cf worker (webui) accessible for frank has no use"
- **2026-10-20 13:47:28Z** (root L2484, S2:L54): "right. we drew the boundary of things that are my own versus things that we can all use are: the gpuix local shell. and that has been scoped very well previopusly"
- **2026-10-20 13:11:39Z** (root L1473; `direction-ledger.json` sources[14]): "there are several other open herdr workspaces on my swaywm from client. those are all ongoing work, some of them mid-sessiob limit reset in 2hrs or so"
- **2026-10-20 ~11:03Z (13:03 CEST)** (quoted by the coordinator in dotfiles T-25 and T-18): "but recover the last sway workspaces > herdr workspaces > kitty terminals (i typically have a one to one mapping, with a limit of 9 open workspaces at a time; this helps with my mental overload)"
- **2026-10-20 12:03:43Z / filed 12:04:14Z** (Claude `1a517fb2` L751 queue-operation, absorbed mid-turn; also desk T-38 and dotfiles T-14 records; S4:L304, S3:L715):
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
- **2026-10-20 10:50:13Z and 10:50:58Z** (Claude `1a517fb2` L69/L108 queue-operations; S4:L305) — the F10 incident:
  > i did f10 to close and all the 10 workspaces disappreared along w the workspaces i was woprerking on it / i m on the zenbook btw just so we re clear
  > i m not sure what clweared theworkspaces. maybe it was loss of interent connection. since this is not "sleep" it s just brithness zero on the device, basically nothing happened. i moved around w the laptop that s why

  (F10 on the client is `brightness toggle`, `home/home.nix:158`; root cause measured in dotfiles T-25, §3/§6.)

### 2c. Older Tom turns captured by S3 into the evidence JSON (dates as recorded)

From `dotfiles-T-14-2026-10-20.json` ("Build Hyprland and Solid GPUIX desktop"):
- **2026-10-16 09:57:48Z**: "recall the gpuix email + crm implementation, and launch on the client (zenbook) latest version use 2 subafgents to go through latest"
- **2026-10-14 13:13:13Z**: "increase brightness on my asus zenbook to the max. this should become a shortcut like f1 f2 perpahs ; and a vicinae-remplacement-launcher"
- **2026-10-13 23:18:45Z**: "i see. get 3 subagents to give me side by side implementations in gpuix so that i can see them side by side. let s do email app and "desktop""
- **2026-10-13 23:16:21Z**: "... are those demos gpui or google chrome btw? ..." (answer recorded by the coordinator 10-14 01:40Z: they were **Chrome renderings of Primer React**, not GPUIx — "Do not let a Chrome approval stand in as a GPUIX approval.")
- **2026-10-13 22:34:34Z**: "one mroe subagent: for ht left bar, i want you to copy the same proportions as the views c++ left tab bar that we saw from google chrome."
- **2026-10-13 22:33:38Z**: "one more agent: herdr-web-ui with the existing implemetnation / similarly, one sway-wired workspace switcher that can be toggled with mod i ; with herdr-provided status indicators. only for the top display (consult kanshi config to know which one i m talking about, and existing vicinae herdr wrkspaces item as well if needed. ...)"
- **2026-10-13 22:32:08Z**: "have subagents: keep producing clickable things, even if mockups, just making sure htat we keep true to the anthropic (colors on github i think? ) theme kit, show me what a menu and sidebar etc etc could look. impress me visually. mockups are king here."
- **2026-10-13 22:26:16Z**: "i digress on the hyprland parts, i m sorry. let s tick to sway window manager. less effort.. but do list all the hyprland functionality that we're "missing out on" in a way so i can decide if i want hat added potentially later or not..."
- **2026-10-13 22:17:28Z**: "massive ultracode workflow into the blur implementation (since hyprland has full wayland blur protocol resolved / we re doing functionality pull from quickshell NOT visuals or aesthetics whatsoever"
- **2026-10-13 22:16:43Z**: "whatever you just opened: i love it. / this is good enough to also become a functional remplacement to waybar, vicinae and mako notifications. drawing insporation from omarchy's implemetnatipn of wayshell in fact."
- **2026-10-13 22:04:45Z**: "the first task is to introspect into my existing claude ui, i tried replicating the claude managed agents ui , and tyhe claude calendar implementation. first step is finailzing the look and aesthetic. i want to use the claude anthropic font, the color scheme and selector, and the github primer react theme kit"

From `dotfiles-T-2-2026-10-20.json` ("Launcher clean-up ..., Vicinae font 12, mako blue"), **2026-10-12 09:20Z** (superseded on the Vicinae point by 10-13 22:16):
> vicinae settings stuff ... i also wanted to make the font larger than 11 (12 or 14, need to decide, start at 12). we keep vicinae actually.. i was getting a little carried away there when i said let's delete it. it's good fucntionality.
> regarding the chrome app shortcuts, nice find. i'll want them gone. installed chatgp and claude apps must also be gone. ... i ONLY use neovim (nvim) ...

From `desk-T-31-2026-10-20.json` ("Fork Primer React and prepare the complete Anthropic-style Claude Design kit"):
- **2026-10-17 01:12:51Z**: "... the views c++ ; the quickshell ; the invetigation into all the desktop shells; all their perceived overlaps. this is my own local gpuix shell; for linux... but stylistiacally it s exactly the same as what is used for the frontend (gpuix whatever js - react or other - you end up using) ; for all users. email crm etc all the shebang. if the answer is a "minimal, claude" feel you already have done some of those designs ..."
- **2026-10-17 00:23:29Z**: "... the design kit ... deliberately omits things like the font (to be configured) becasue i like the anthropic-derived one but dnt want to share it on the interned.. these are locally deployed personal tools ..."
- **2026-10-14 01:10:03Z**: "resruface from notes w subagent in meantime: vimium-based navigation concept i had discussed ..."
- **2026-10-14 01:08:55Z**: "we can design a linear-style unified shortcut based ui, with mneumonics, in a way that the claude ai can drive at equivalence, sending in instructins that get passed on to a hci implementor, that feels basically as if claude code or grok bot with "web browsre steering" abilities was context-aware. the same way the user can do ctrl k and see a contextual menu of sorts.."
- **2026-10-13 23:50:43Z**: "... recording every single keypress, compacted into one place. ... to create the dream desktop envoronment. plus sway window manager's multiseating"
- **2026-10-13 23:47:15Z**: "one more introspection in ~/notes on the ctrl k contextual menu idea ... this is something that is interesting now that it may all be gpuix-controlled ; potentially giving control of my desktop to the ai"
- **2026-10-13 23:33:29Z**: "... a design kit (set of constraints) that is a good enough set in order for us to have a claude anthropic-maximalist look "as if it was done by anthropic claude" but for desktop os ; in a way that we can use it in gpuix."
- **2026-10-13 23:23:12Z**: "i m not intersted in "native advantage" . performance is not really the thing i m looking for here. "supplies another renderer" is fine for something that' react plus generic compositor functionlaity... vicinae (raycast clone) proves this theoretically ; we hae the sway ipc and omarchy's quickshell which you investigated a while back did exactly that."
- **2026-10-13 23:20:58Z**: "explain more about why prier react components don't directly become native gpuix controls. ... gpuix is a cool project but we can use it as stylistic inspiration if it's not adapted. ..."
- **2026-10-13 23:08:00Z**: "... i am expecitng it to be a react (solidjs compat) superset of github primer, cloudaflare kumo + cloudflare-os. that can do all the way from my desktop shell to the functional desktop that exists. the idea is to keep "grinding" at a unified set of requirements that can outlast any coding language of framework, with react being the real world implementation of it"
- root **2026-10-13 23:03:25Z**: "... have claude design prepare a comprehensive 1:1 kit with everything from anthropic "as if it was designed by anthropic claude 1st party native implementations - bar the font" ..."

From `desk-T-40-2026-10-20.json` ("Decompose Claude Desktop ...; investigate gpuix, gpuix-svelte, gpui-shell and herdr-gpui"):
- root **2026-10-17 00:10:56Z**: "systematically decomposing anthropic claude's desktop program, with the separation that: - on the sway devices, the left bar of the ai chat is a waybar style workspace (1>9) launcher ; and there is the macos implementation ... https://github.com/remorses/gpuix https://github.com/khromov/gpuix-svelte https://github.com/andre-brandao/gpui-shell https://github.com/penso/herdr-gpui SUPER important.. but the idea is that we really find that agnosticity measure and make it super central"
- **2026-10-17 00:45:55Z**: "herdr voice in is important as ew have a great SST model.. "reading out loud" given my slash-voice skill is also feasible https://github.com/brogrammerMW/herdr-voice / and also te autotabtitle and ctrl k is PHENOMENAL inspiration for the workspaces coupling with herdr panes meaning one terminal per sway workspace; and https://github.com/jeffarese/herdr-bar which we can integrate conceptually flly on my local device"
- **2026-10-17 00:45:55Z**: "sidenote 2: https://headlessui.com/ when you parle de "components""

From `desk-T-38-2026-10-20.json` ("Friday planning: convergent GPUIx product"), **2026-10-16 08:12:14Z**:
> swaywm integration is fluid conceptually, i m not fixed to one thing. ... we have a very clear separation of concerns being gpuix-specialized entire wayland shell and programs (email, crm, etc "a la Vesence") that are alos macos specific; all on the github+cloudflare+ai harness model. herdr-centril all the way, how hersr-web-ui is decomposed eg the leftbar becomes sway compatible. the nuance is that gpuix-shell is for ME and the substrate actual tooling is exported to macos native etc. by design. subagents must deliberte ont hius line (what goes in poersonal nixos dotfiles fleet vs external tooling that goes in agency gh org ; i already did that wiht email and crm i think)

From `desk-T-30-2026-10-20.json` ("One clickable implementation by morning: herdr + herdr-web-ui fork + Sway"):
- root **2026-10-13 22:33:11Z**: "... in my caes it's herdr and herdr-web-ui that i tried out in the last few days. combined with sway we can do some great work ..."
- **2026-10-14 02:08:44Z** (the nav list he expected in the morning build): "you should have Platform / Vesence Desktop / Research / Projects / Editor / Agents / Compare / Mail / Calendar"

From dotfiles project memory (printed at S1:L55; dated lines in `project memory show dotfiles`):
- **2026-10-14**: "the crown jewel is obviously the chat interface, beyond clui-cc and into something that is more comprehensive." and "watching my behavior and selfimproving from there can onyl happen bcz we have a tight grip on the actual keypresses: sway to gpuix shortcuts and fast typing."
- **2026-10-14**: "turning backgrounded tool use into visible actions that feel like puppetteeringthe computer live in front of me without adding load to the steering llm (intent is taken by claude code, just with more visual feedback)"
- **2026-10-14**: "herdr stays central; with even more synergy with the sway workspaces now"

From the 2026-10-14 Codex session `01a13843` (recovered by `toggle_history`, S1:L128 and S1:L180;
original file `/home/tom/.codex/sessions/2026/10/14/rollout-2026-10-14T04-35-37-01a13843-e8ef-7b60-b14a-d38c1717c976.jsonl`):
- **L96, 02:38:47Z**: "see how i use herdr-webui right now? what if i want to change between kitty terminal (herdr session) and web-ui chat window (rathern than the xterm js termianl)? can use some sway tabbing trickery perhaps? hwo would you approach this?"
- **L133, 02:39:47Z**: "generally how we can "interleave" between several window types on sway without the user feeling the differnce and without that taking sway tabbed space. i dnt want to "see" the tabs however.. would be itnersting. would need some sort of "contextality" here"
- **L155, 02:40:22Z** (REPORTED excerpt): "a herdr workspace is ONE kitty terimnal correpondance. this is something i m hapy to enfordce"
- **L161** (REPORTED excerpt): "one hedr workspace is one sway wm workspace to reduce cognitive load even further"
- **L171** (REPORTED summary): deep integration, herdr waiting-for-input becomes Sway workspace urgency and `notify-send`.

Finding of S1 (MEASURED by two subagents): **no older literal statement about "a highlight that
changes" was found**; the evidenced requirement is "no visible Sway tabs / no tab-strip space".
I read T1's "without having a highlight that changes" as: the toggle must not move focus highlight,
border colour, or rail selection — the workspace stays the same, only the view inside the tile flips
(INFERRED).

### 2d. Contradictions and how they resolve (newest wins unless noted)

| Older | Newer | Resolution for tonight |
|---|---|---|
| "we keep vicinae actually" (10-12) | "functional remplacement to waybar, vicinae and mako" (10-13 22:16) | Replace, but **sequenced**: Vicinae + mako stay until the shell proves out; each retirement needs Tom's word (memory 10-14, REPORTED). Matches BRIEF `programs.gpuixShell.enable` being exclusive with vicinae/mako. |
| "drawing insporation from omarchy's ... wayshell" (22:16) | "functionality pull from quickshell NOT visuals" (22:17) | Function only from Quickshell/Omarchy/Noctalia/DMS; visuals from Claude/Primer (+ Tacit vanilla-ness per BRIEF). |
| Hyprland blur ask (22:17) | "let s tick to sway" (22:26) | Sway only; no blur. |
| Coordinator on T-14 (10-20 12:07Z, **not Tom**): "do not pull its code into dotfiles ... What crosses the boundary is documented knowledge, not source." | Tom (10-20 ~22:50 CEST, BRIEF): "in my ~/dotfiles with an experimental branch" | Tom's newer word wins: the shell lives in dotfiles `experimental/gpuix-shell`. The "SEPARATE project" in Tom's 12:03Z text means separate **from the shared agency.agency product**, not from dotfiles (INFERRED from the sentence structure). Record in ASSUMPTIONS.md. |
| Accepted look = Claude/Primer preview (10-13) | That preview was a **Chrome** rendering (coordinator 10-14 01:40Z) | The look is accepted; its GPUIx rendition is not yet approved by Tom. Fonts/text rendering will differ. |
| Tom "React, solidjs (leaning towards react)" (10-20 14:22Z) | BRIEF decision 1 picks React | Consistent. |

---

## 3. Feature / behaviour inventory

Keep = keep the existing mechanism and have the shell read/drive it; Replace = shell supersedes it;
New = nothing exists yet.

| # | Feature | What exactly | Where it lives today | Keep / Replace / New | Notes (evidence label) |
|---|---|---|---|---|---|
| 1 | **Slot model 1:1:1** | One Sway workspace = one herdr workspace = one kitty projector; slots 1–9 on eDP-1, ws 10 on eDP-2 | `home/dot_config/sway/binds.conf:48-60`; `home/dot_local/bin/herdr-picker:24-28` (marks regexes), `:338-374` (`ensure_projector`), `:99-105` (`available_slot`) | Keep; shell reads it | MEASURED live (§3a). Picker error text: "All nine Herdr slots are occupied or parked. Reopen one with Mod+Ctrl+Space; detach a view to release its slot." |
| 2 | **Nine-slot cap visible** | Rail shows exactly nine slots + ws10, not an unbounded list | — | New (rail) | Tom 10-20 "limit of 9 ... mental overload"; coordinator on T-14 10-20 11:07Z: "the UI should read as those nine slots with their herdr status rather than as an unbounded list" (REPORTED) |
| 3 | **Terminal ⇄ chat toggle (Mod+grave)** | Same tile, both windows alive, no tab strip, focus stays on the same workspace; first toggle creates the companion | Unmerged: `/home/tom/.wt/dotfiles/herdr-sway-context` (`feat/herdr-sway-context` @ `c1a49b99`): `home/dot_local/bin/herdr-context` (657 lines; swap at `:482-505`, park at `:541-558`, Chrome launch `:389-465`), doc `docs/herdr/sway-context.md`, receipt `docs/herdr/sway-context-validation.md` | Keep mechanism; **replace the Chrome companion with a GPUIx chat window** later | 69 fixture tests + private Sway/Kitty/Chrome/Mako smoke passed 10-14 (REPORTED). `Mod+grave` is unbound in the worktree's `binds.conf` (MEASURED: no `grave` match). |
| 4 | Toggle commands | `herdr-context toggle`, `show terminal/chat`, `show chat --choose-pane`, `activate --workspace w1 --pane p1`, `status --json`, `reconcile` | `sway-context.md:28-43` | Keep CLI shape; gpuix-shell can call it or absorb it | Args are herdr IDs, not Sway numbers |
| 5 | Herdr attention → Sway urgency + notification with actions | Only `blocked` requests attention; snapshot every 3 s, Sway events between; dedup across polls; activating a notification returns to workspace + pane; visiting acknowledges | Unmerged `home/dot_local/bin/herdr-attention` (442 lines) + `herdr-attention` user unit on `sway-physical-session.target` (`sway-context.md:16-26,45-51`) | Keep logic; shell's notifications daemon becomes the sink instead of mako | Issue #573 "Expose a read-only, platform-neutral attention snapshot with Sway/Herdr adapter" (MEASURED open 12:56Z) |
| 6 | Multi-agent pane chooser | Snapshot does not say which pane a kitty client shows; one agent = unambiguous; several = chooser restricted to the workspace | `sway-context.md:86-101`; `herdr-context --choose-pane` | Keep | MEASURED: herdr API protocol 22 has no client list (S4:L319) |
| 7 | **Mod+i top-display workspace switcher with herdr status** | Switcher on eDP-1 only; herdr status indicators | PR #565 `feat/morning-shell` @ `7464298c`; `/home/tom/.wt/dotfiles/morning-shell`; runtime bind installed into the live client session 10-14 (not from config) | Replace with `gpuix-shell switcher` | Mod4+i is runtime-only (REPORTED); not in `binds.conf` (MEASURED) |
| 8 | **Left rail = waybar-style workspace launcher 1→9** | "on the sway devices, the left bar of the ai chat is a waybar style workspace (1>9) launcher" | herdr-web-ui rail (aesthetic); Chrome Views C++ left tab bar proportions (10-13 ruling) | New | Old waybar removed 2026-09-11 (BRIEF) |
| 9 | **Palette / launcher (Mod+d, Ctrl+K lineage)** | claude.ai search model: type tabs, Recents, Actions, footer key hints, compose (§4a) | `binds.conf:6` `$mod+d exec vicinae toggle`; web proof `shared-parity/src/ui/shortcuts.ts`; herdr-web-ui `src/lib/shortcuts.ts` (Mod+Shift+K) | Replace Vicinae | "the palette finds or changes the work; the terminal/chat toggle changes how you view it" (assistant S1:L195, INFERRED good framing) |
| 10 | **Chat window = clui-cc in GPUIx, herdr-centric** | Summonable chat, resumable conversations, visible approvals, attachments; herdr owns sessions; integrates with herdr-web-ui "the same way" | Unbuilt. Aesthetic ref: herdr-web-ui fork `~/mecattaf/herdr-web-ui` @ `e85ffd1` (`identity/claude-primer`), served at `https://strix.tail8dd1.ts.net:8443` → `127.0.0.1:7318` | New (not tonight's critical path) | `shared-parity/docs/native.md:48` (REPORTED): "a complete native chat composer/navigation shell is not implemented" |
| 11 | **File picker = Nautilus via GNOME portal** | Keep the existing chooser; GPUIx surfaces call `org.freedesktop.portal.FileChooser` | `modules/sway.nix:169-173` (`services.dbus.packages=[nautilus]`; `FileChooser = "gnome"`), `:13` `nautilus-open-any-terminal` | **Keep** | Tom T2. Distinct from a file *explorer* surface (BRIEF's Pinax idea): do not build an own open/save dialog |
| 12 | Notifications (mako replacement) + Mod+O dismiss-all | Server + toasts + actions + dismiss | `home/vicinae.nix` (mako); PR #571 `fix/sway-mod-o-dismiss-notifications` @ `f14ada65` | Replace | Mod+o not in worktree `binds.conf` (MEASURED) |
| 13 | Brightness keys | Runtime: F1 down, F2 up, Shift+F2 max; theme/accent moved to Mod4+F2/Mod4+Shift+F2; three desktop entries | PR #566 `fix/zenbook-brightness-shortcuts` @ `894b1cb4` (draft) | Keep binds; OSD by shell; launcher entries move into palette | Worktree `binds.conf:139-140` still has F2/Shift+F2 = theme/accent (MEASURED) → conflict with #566 |
| 14 | F10 = backlight toggle (client) | `bindsym --no-warn F10 exec ~/.local/bin/brightness toggle` | `home/home.nix:158` (sway-local.conf); generic `binds.conf:150` F10 = sleep-monitors prompt | Keep | Tom's 10:50Z incident (§2b) |
| 15 | Caps Lock toggles touchpad + OSD; Duo Caps LED shows touchpad off | — | commits `7e082fbb`, `e46e595d` (in `dadb1426`) | Keep script; OSD via shell | MEASURED in `git log` (S3:L656) |
| 16 | F9 audio route picker; Shift+F9 call record; Shift+F10 pomodoro | `$prompt ...` kitty prompts | `binds.conf:148-151`; commit `97ef81a9` | Keep scripts; menus become shell menus (New) | — |
| 17 | F3–F8 media/volume | F3 play, F4 prev, F5 next, **F6 mute, F7 vol down**, F8 up | `binds.conf:142-147` | Keep | **Collides with shared-parity's in-app F6/F7** (§6) |
| 18 | Wi-Fi menu | Replace terminal fallback | Issue #509 "Vicinae Wi-Fi menu: replace the terminal settings fallback"; script `fzf-nmcli` (BRIEF) | New in shell | — |
| 19 | Bluetooth pairing menu | Package/verify pairing flows | Issue #510 | New in shell | — |
| 20 | Clipboard history | Paste into Herdr/Kitty and Chrome | `binds.conf:114` `$mod+v exec vicinae cmd launch clipboard:history`; issue #508 | Replace | — |
| 21 | Herdr workspace identity / close / restore navigation | Durable identity | Issue #512 | Keep picker; shell reads | — |
| 22 | Reattach restore of slot views | After a lost link every projector lands on the server's focused workspace | dotfiles T-25 (Waiting on Tom) | Gap; shell should *show* mismatch, never "fix" it via server focus | MEASURED by `1a517fb2` (§3a) |
| 23 | Workspace naming chain | task title > herdr tab > workspace topic > Sway "N: topic" > rail row | desk T-40 status (REPORTED 10-17) | New | Inspirations: `jeffarese/herdr-bar` (Cmd+K + auto tab titles), `kryptamine/herdr-auto-title` (per-workspace topic) |
| 24 | Herdr metadata tokens for the rail | `herdr workspace report-metadata <id> --source ID --token NAME=VALUE --ttl-ms N` | herdr CLI (MEASURED S2:L43) | New use | Lets the shell annotate workspaces without a plugin |
| 25 | Shortcut catalogue with stable IDs | Human key, palette row, button and agent call hit the same handler | `shared-parity/src/ui/shortcuts.ts` (21 lines), `src/parity/catalog.ts` (88 lines); herdr-web-ui `src/lib/shortcuts.ts`, `src/lib/actions.ts` | Reuse pattern | Tom 14:12Z "human clicks ... same as an agent's usage of the api" |
| 26 | "Trailing clicks" / follow-agent presenter | Agent events projected without re-dispatch; human input pauses following; F6 toggle follow, F7 next; ≤1 event / 600 ms | `shared-parity/src/native/main.ts:78`, `src/native/adapter.ts:34`, `src/parity/presenter.ts` | Reuse; rebind keys | MEASURED order [1,2,3], revision 3, no redispatch (`evidence/native/ordered-activity-worker/activity-result.json`) |
| 27 | OpenUI → GPUIx native adapter | lang-core evaluate → `createElement/appendChild/setText/setStyle/setCustomProp/setEventListener/setRoot/destroyElement` via `applyBatch` | `shared-parity/src/native/adapter.ts` (150 lines), `src/openui/contract.ts` | Reuse for `gpuix-shell ask` | MEASURED 49/49 unit tests (manifest) |
| 28 | herdr-web-ui deep links | `?machine&ws=<id>-<slug>&pane&view=chat/agents/terminal&file&settings&section&new&cwd&name&agent&sidebar=hidden/shown` | `~/mecattaf/herdr-web-ui/src/lib/deepLink.ts:1-24` | Keep (Chrome-companion fallback) | Slug ≤24 chars (`deepLink.ts:66`) |
| 29 | Voice in | Hold-to-dictate (herdr-web-ui Mod+Shift+Space); herdr-voice as inspiration | herdr-web-ui `VoiceInput.tsx`; desk T-40 | Later | herdr-voice: macOS only, cloud realtime, "do not install" (REPORTED T-40) |
| 30 | Theme toggle | Dark/light flip; dotfiles `theme` symlink | herdr-web-ui `toggleTheme`; `home/dot_local/bin/theme` | Keep (BRIEF) | — |
| 31 | Native GPUIx Mail / CRM apps | Shared utilities, launched not built by the shell | Client user services `agency-kit-mail-c742887`, `agency-kit-crm-c742887` from `~/Downloads/agency-kit-c742887` (fixture mode, 10-16) | Boundary: launch only | REPORTED 10-16; not declared in Nix |
| 32 | Keypress recording / agent cursor / puppeteering | Record Tom's own interactions; visible agent actions | desk T-32 (Waiting on Tom: overlay vs real second pointer) | Out of tonight's scope | Tom 10-14 "guinea pig" consent is recorded (REPORTED) |
| 33 | Chrome app shortcuts / ChatGPT + Claude apps | Tom wants them gone from the launcher | dotfiles T-2 | Launcher must not list them | Tom 10-12 |

### 3a. Engineering facts measured in these sessions (Sway / herdr / kitty / GPUIx)

**Zenbook (`client`) desktop at 2026-10-20 12:14–12:17Z** (S4:L188–L354; files in the intake folder):
- SSH: `client` alias resolves to LAN `10.42.0.16` and failed "No route to host"; Tailscale `100.121.160.100` with `-o HostKeyAlias=client` worked. `hostname` = `client`. (MEASURED)
- `systemctl --user show-environment`: `SWAYSOCK=/run/user/1001/sway-ipc.1001.1946.sock`, `WAYLAND_DISPLAY=wayland-1` → uid **1001**, Sway pid 1946. (MEASURED, S4:L193)
- `swaymsg -t get_workspaces` (S4:L203): workspaces 1–7 on **eDP-1**, rect **1440×900 at (0,0)**, `layout splith`, `border none`, `representation "H[herdr-projector]"`, ws 7 focused; ws **10 on eDP-2, rect 1440×900 at (0,900)**, empty. (MEASURED) → logical 1440×900 per panel, panels stacked vertically.
- Every projector window: `app_id herdr-projector`, Sway `name` (title) = `herdr-sway-projector`. Process: `kitty --class herdr-projector -e /home/tom/.local/bin/herdr-sway-projector` → bash `herdr-projector` → `herdr --remote strix --remote-keybindings server` → `ssh -C ... ControlMaster=auto ControlPersist=600 -T strix ... herdr remote-client-bridge`. (MEASURED, S4:L210, L227, L250)
- herdr client env on the client: `HERDR_CONFIG_PATH=/home/tom/.config/herdr/sway-client.toml`, `HERDR_SWAY_LOCAL=0`, `HERDR_SWAY_SEAT=client`, `KITTY_WINDOW_ID=1`. (MEASURED, S4:L312)
- Sway marks (S4:L347): ws1 `herdr-label-client-slot-1-67a4d0, herdr-name-31, herdr-slot-1`; ws2 `herdr-slot-2, herdr-label-client-slot-2-c65189`; **ws3 `herdr-slot-3` only (no label)**; ws4–7 slot + label. (MEASURED)
- **Views do not follow marks**: by reading kitty text (`kitten @ --to unix:@kitty-<pid> get-text --match recent:0`), ws1 and ws3 both showed herdr pane `wGG:p1`; ws1's label mark was stale. (MEASURED, S4:L354; intake note §1 l.27)
- `~/.local/state/herdr/client-shell/local-*.json` = 18 files, all `{"sidebar_collapsed": true}` except one `false`. `/run/user/1001/herdr-sway.lock` exists. `herdr-sway.service` MainPID=0. (MEASURED, S4:L275, L312, L333)
- Client NixOS `configurationRevision dadb1426...` at 13:08Z (= this branch's base). Strix at `2ac87891`. (MEASURED by S3: `client-tailnet-version.json`, `local-host-version.json`)

**herdr server (strix)**
- `herdr api snapshot` keys: `agents, focused_pane_id, focused_tab_id, focused_workspace_id, layouts, panes, protocol, tabs, version, workspaces`. Pane rows carry `agent, agent_status, cwd, foreground_cwd, pane_id, revision, scroll{viewport_rows...}, tab_id, terminal_id, terminal_title(_stripped), workspace_id`. (MEASURED, S4:L193)
- `herdr api schema --json`: `protocol 22, schema_version 1`; no `client_list` / `client_id` → **per-client (per-kitty) selection is not observable**. (MEASURED, S4:L319)
- 12:14Z: 18 workspaces/panes, 14 agents (12 claude, 2 codex), 4 nvim; 14:40Z: **21 workspaces, every one 1 tab / 1 pane**, labels `client-slot-N-xxxxxx` where **N repeats** (slot-8 ×4, slot-2 ×3, slot-4 ×3 ...) — the label's slot is the creation slot, not the current one. `agent_status` values seen: `idle, unknown, done, working` (no `blocked` at that moment). `herdr agent list` rows add `completion_seq`, `state_change_seq`. (MEASURED, S2:L49)
- CLI surface (MEASURED, S2:L43): `herdr workspace list|create [--cwd --label --env --focus|--no-focus]|get|focus|rename|report-metadata <id> --source ID [--token NAME=VALUE] [--clear-token NAME] [--seq N] [--ttl-ms N]|close [--group]`; `herdr agent list|get|read [--source visible|recent|recent-unwrapped|detection]|send-keys|prompt [--wait --until]|rename|focus|wait|attach [--takeover]|start --kind KIND --pane ID|explain`; kinds `pi|claude|codex|gemini|cursor|devin|agy|cline|omp|mastracode|opencode|copilot|kimi|kiro|droid|amp|grok|hermes|kilo|qodercli|qwen|letta|maki|muse`. `herdr pane read <id> --source visible|recent|recent-unwrapped|detection [--lines N] [--format text|ansi]`, `herdr pane process-info --pane <id>`.
- **`herdr workspace focus <id>` is global**: focusing wHH moved BOTH attached projectors (kitty 7251 and 54356) at once. prefix+w in herdr 0.9.3 is a NAVIGATE mode, not a typed picker; one `down` key via kitty remote control did not visibly change selection within 1.5 s; prefix+b sidebar shows a `●` on the selected workspace. (MEASURED by `1a517fb2` 10-20 13:20–13:35 CEST, captured in `dotfiles-T-25-2026-10-20.json`)
- herdr 0.9.4 (PR #563, unmerged) "newly asks before closing a workspace's only pane, which every Mod+Return workspace has". (REPORTED)
- 10-17: "Live herdr on strix: 102 socket methods, 219 one-pane workspaces, no plugins installed." Missing piece named: "a projector plugin (events.subscribe in, workspace.report_metadata tokens out, agent.view.set focus, notification on blocked)". (REPORTED, desk T-40 status)
- herdr socket rules from herdr-web-ui `AGENTS.md:20` (MEASURED file): "NEVER pool herdr RPC connections: herdr closes the socket after each response. Use one connection per call (10 s timeout). Only `events.subscribe` stays open, and a second subscribe on an open connection is silently ignored, so reopen it with the full set." Socket path: `$HERDR_SOCKET` or `~/.config/herdr/herdr.sock` (`server/herdr/client.ts:20-24`). **On the Zenbook there is no local herdr server**: reads go `ssh -n -o BatchMode=yes -o ConnectTimeout=3 -o ServerAliveInterval=2 -o ServerAliveCountMax=1 strix 'herdr api snapshot'` with a 6 s timeout (`herdr-picker:163-176`).
- Canonical herdr config: `[ui] window_title = ""` (kitty owns titles) and `sidebar_start_collapsed = true` (`home/dot_config/herdr/config.toml:96,100`). `herdr-picker identity()` (`:186-195`) matches Sway title `strix: <label>`, which therefore never matches in the deployed config; the unmerged branch sets `window_title = "{hostname}: {workspace}"` and needs `herdr server reload-config` (a reload, not a restart; REPORTED in `sway-context.md:80-84`). (MEASURED config lines; INFERRED consequence)
- herdr-projector reconnect loop: backoff 1, 2, 5, 10, then 30 s; a session that held ≥60 s resets backoff; exit 0 ends, exit 2 not retried; preflight `systemctl --user is-active herdr.service` over ssh; "After a reattach the window lands on the server's default target, not necessarily the workspace it was showing." (MEASURED file text, S4:L250; `home/dot_local/bin/herdr-projector`)

**Sway mechanics proven on the unmerged branch (REPORTED, receipt 10-14)**
- Hidden companion = `move scratchpad`; toggle = `swap container with con_id`, then explicitly transfer fullscreen (`fullscreen disable` on the outgoing, `enable` / `enable global` on the incoming) because Sway drops it during scratchpad swaps (`herdr-context:496-505`).
- Native Chrome ignores `--class` in app mode; window rules key off the dedicated profile suffix; ownership via the private DevTools endpoint's browser PID. Smoke ran Sway 1.12, Kitty 0.48, Chrome 155, Mako 1.11 on two private headless outputs.

**GPUIx native (shared-parity, 2026-10-20 14:18–14:36Z)** — `evidence/native/manifest.json` (MEASURED file):
- Scope string: "Actual Linux GPUIx native addon; private Sway GLES2 + renderD128; isolated runtime; fictional workspace data only". `gpuixPackage 0.10.0`, `gpuixSource 6a5c7c14...` (vendored git-archive in `agency-agency/ultrabuild@9154ddd2`), `openuiSource 9823ec05...`, 49/49 unit tests via `runtime-test -- node --import tsx --test ...`.
- **Pixman headless fails**: `wgpu_hal::vulkan ... ERROR_SURFACE_LOST_KHR` then "Failed to open the GPUI window: No GPU adapter found that can configure the display surface" (`evidence/native/failure-pixman/native.log`). **GLES2 + `WLR_RENDER_DRM_DEVICE=/dev/dri/renderD128` works.**
- **Sway cursor injection produced no input event** in GPUIx; working input used `renderer.simulateClick` / `renderer.simulateKeystrokes` (manifest `limits`).
- Native API used (`src/native/main.ts`): `renderer.init({title, appId, width:960, height:900})`, `setWindowKeyEvents(true,false,0)`, `getElementBounds(id)`, `getFocusedElementId()`, `getAllText()`, `getPaintedText()`, `tick()` every 16 ms, `simulateKeystrokes`, `simulateClick`.
- Keyboard: Tab / Shift+Tab traverse action controls, Enter/Space activate, held-key repeat ignored, focus restored after redraw; native focus-visible styling. Not covered: AT-SPI/screen reader, IME, physical input, palette/modal. (REPORTED `docs/native.md`)

---

## 4. Design values found

### 4a. The claude.ai search palette Tom pasted (MEASURED from pixels; scale INFERRED 2×)

Screenshot 1695×1467 px. The Zenbook renders at 2× (2880×1800 → 1440×900 logical), so halve px for
logical units (INFERRED).

| Element | Measured | Logical (÷2) |
|---|---|---|
| Panel background | `#20201f` | — |
| Panel outer hairline | `#3b3b3a`–`#424241`, 1 px | 0.5–1 px |
| Divider hairlines (under tabs, above footer) | `#343433`, 1 px | 1 px |
| Backdrop outside panel | `#0e0e0e` / `#0a0a0a` (dimmed page) | — |
| Selected row fill / selected type pill | `#313130` | — |
| Primary text (selected row, active tab, close ×) | `#f0efec` | — |
| Secondary text (unselected rows, row icons) | `#c3c2b7` | — |
| Muted text (placeholder "Search", inactive tabs, section headers "Recents"/"Actions", meta "Shared with you", footer labels, ↵ hint) | `#898781` | — |
| Keycap (footer `Esc`, `←`, `→`, `/`, `Alt`, `↵`, `Tab`) | border `#3d3d3a`, glyph `#a5a49a`, transparent fill | — |
| Panel width | 1653 px (x 24→1677) | ~826 |
| Panel outer radius | ~42–45 px | ~22 |
| Row height | 88 px (y 379→467) | 44 |
| Row inset from panel edge | 31 px | ~16 |
| Row corner radius | ~14–16 px | ~8 |
| Type pill ("All") | 86×67 px | ~43×34 |
| Content left padding (text start) | ~60 px | ~30 |
| Icon → label gap | ~64 px | ~32 |
| Footer height | ~100 px | ~50 |

Structure (top→bottom): placeholder "Search" + close × (top-right) → type tabs **All · Artifacts ·
Sessions · Code · Projects · Scheduled** (selected = filled pill) → hairline → section **Recents**
(rows: icon, title, optional right meta "Shared with you"; selected row shows `···` and `↵`) → section
**Actions** ("New session") → hairline → footer key legend: **Close `Esc` · Change type `←` `→` ·
Filters `/` · Actions `Alt` `↵` · Compose `Tab`**. Icons are thin-stroke outline glyphs (chat bubble,
pin, people, artifact). Mapping for gpuix-shell (INFERRED): types → Workspaces (herdr slots) · Apps ·
Files · Projects · Commands · Clipboard; Compose `Tab` → hand the typed text to the chat/agent;
`Alt+↵` → per-row actions menu.

Note these are claude.ai dark-theme values, close to but not identical with `home/themes/claude-dark.nix`;
the builder should take tokens from the theme files and use these only to check proportions and the
three-level text hierarchy (INFERRED).

### 4b. Other values recorded in these sources

- Sway look (MEASURED `home/dot_config/sway/layout.conf`): `font pango:Anthropic Sans 11` (:2), `gaps inner 0`, `gaps outer 0`, `default_border pixel 1` (:7), `hide_edge_borders smart`, `output * bg #000000 solid_color` (:16).
- Zenbook logical outputs: eDP-1 1440×900 at (0,0); eDP-2 1440×900 at (0,900) (MEASURED §3a).
- Design-kit defaults recorded on desk T-31 (REPORTED, 10-17, "Defaults taken that Tom can overturn"): **clay never marks selection; working is blue; sentence case; controls 32/34 at radius 8; serif for assistant prose; comfortable density; the Linux head has a left rail and layer surfaces and no top bar.** Open X1 options: bottom app bar, rail inside the chat window, task strip, square outer corners. Handoffs: `~/today/2026-10-17-frank/design-handoff/{HANDOFF-A.md,HANDOFF-B.md,SHELLS-DIGEST.md,OPERATOR-CARD.md,VERIFICATION.md}` (rules U-01..U-19).
- Launcher font: Vicinae font 11 → Tom wants 12 ("12 or 14, need to decide, start at 12"); "mako blue" / "the Vicinae-matched blue" is the accent the shell inherits (dotfiles T-2; memory 10-14). (REPORTED)
- herdr-web-ui app shortcuts (MEASURED `~/mecattaf/herdr-web-ui/src/lib/shortcuts.ts:8-23`; Mod = Ctrl on Linux, Meta on mac): palette **Mod+Shift+K**, find Mod+Shift+F, **switch chat/terminal Mod+Shift+J**, scroll Mod+Shift+PageUp/PageDown, toggle sidebar Mod+Shift+B, new workspace Mod+Shift+O (N reserved by Chrome incognito), previous/next pane Mod+Shift+↑/↓, settings Mod+Shift+",", dictate (hold) Mod+Shift+Space. IME guard: ignore `isComposing` or keyCode 229.
- shared-parity catalogue (MEASURED `src/ui/shortcuts.ts`): `commands.open` Control+k / Meta+k; `surface.dismiss` Escape; `commands.next/previous` ↓/↑; `commands.first/last` Home/End; `commands.activate` Enter. "app-local bindings; nothing installs Sway ... global shortcuts."
- Activity presenter: advance at most 1 event / **600 ms**; F6 pause/resume following, F7 present next; UI keeps ≤100 trail entries (A11Y-CHAPTER, REPORTED).
- Timings: herdr-attention snapshot every **3 s**; projector backoff 1/2/5/10/30 s; herdr-picker SSH ConnectTimeout 3 s / run timeout 6 s; wait for new projector 8 s, attach 20 s (`herdr-picker:366-368`); herdr RPC per-call timeout 10 s.
- Test compositor (MEASURED `shared-parity/tests/native-compositor.py:25`): `output HEADLESS-1 mode 1080x1000`, `xwayland disable`, `seat seat0 fallback true`, `default_border none`.
- A11Y bounded checks S3 ran on the web UI (REPORTED 14:43Z): text contrast passes, composer focus outline >3:1 against both neighbours, all views fit at **320 CSS px** width.
- Chat-first default lens: herdr-web-ui `defaultView` stays upstream `auto` (terminal lens on desktop) where the spec wanted chat first (`src/lib/paneLens.ts:10-14`; memory 10-14, REPORTED known gap).

---

## 5. Reusable code and data (exact paths)

**Sway/herdr glue (in this worktree; keep, call, or port)**
- `home/dot_local/bin/herdr-picker` — slot/mark model, `available_slot` (:99), `remote_snapshot` (:163, the SSH read pattern), `identity` (:186), `ensure_projector` (:338). Tests: `tests/herdr/test_sway_picker.py`, `tests/herdr/test_launchers.py`.
- `home/dot_local/bin/herdr-sway-projector` (local vs remote client; refuses unmanaged server), `home/dot_local/bin/herdr-projector` (reconnect loop + cleanup), `home/dot_local/bin/herdr-chord` (Mod+Return new), `home/dot_local/bin/sway-workspace`.
- `modules/sway.nix:169-178` portal config (FileChooser=gnome; nautilus on dbus).
- `docs/herdr/2026-09-16-runtime-sockets.md`, `docs/herdr/herdr-kitten-input.md` (MEASURED present in this worktree). Note `herdr-picker:1-7` calls itself "Vicinae's Sway/Herdr bridge" and states the rule "Never infer current identity from the server's global focus."

**Unmerged branches to mine**
- `/home/tom/.wt/dotfiles/herdr-sway-context` @ `c1a49b99`: `home/dot_local/bin/herdr-context` (toggle/swap/park/Chrome+CDP), `home/dot_local/bin/herdr-attention` (blocked→urgency+notify, dedup), `home/herdr-context.nix` (`services.herdrContext.webUrl` → `~/.config/herdr/context.json`), `docs/herdr/sway-context.md`, `docs/herdr/sway-context-validation.md`, `tests/herdr/README.md`.
- `/home/tom/.wt/dotfiles/morning-shell` (PR #565) — Mod+i switcher + tests.
- PR #566 `fix/zenbook-brightness-shortcuts` @ `894b1cb4`; PR #571 `fix/sway-mod-o-dismiss-notifications` @ `f14ada65`; PR #574 `fix/client-touchscreen-mapping` @ `875db342` (Zenbook touchscreen/stylus for both panels).

**herdr-web-ui fork** `~/mecattaf/herdr-web-ui` @ `e85ffd1` (`identity/claude-primer`, upstream `devswha/herdr-web-ui`, **not pushed anywhere**: GitHub fork lookup returned 404, `evidence-project-state/herdr-ui-repo.json`)
- `src/lib/shortcuts.ts`, `src/lib/actions.ts` (one `AppActions` object shared by header, sidebar, palette, settings — the "same handler" pattern), `src/lib/deepLink.ts`, `src/lib/paneLens.ts`, `src/desk/shell/{Bell,Strip,paletteRows.tsx,useDeskEvents.ts,useDeskPaletteKey.ts}`, `server/herdr/{client.ts,methods.ts}`, `shared/herdr-api.generated.ts` (typed herdr API), `shared/desk-events.ts`, `shared/notify-policy.ts`, `DESIGN.md`, `src/styles.css`.
- Live: `https://strix.tail8dd1.ts.net:8443` (tailscale serve) → `127.0.0.1:7318` (unit `herdr-web-ui-morning`). Worktrees per track: `/home/tom/.wt/herdr-web-ui-build-{rail,palette,workspaces,shellfunctions,utilities,calendar,agentslens}`.

**shared-parity build** `/home/tom/tuesday-oct20/build/shared-parity/`
- `src/native/adapter.ts`, `src/native/main.ts`, `src/native/activity.ts`, `src/openui/{contract.ts,host.ts,library.tsx,programs.ts,OpenUIChat.tsx}`, `src/ui/shortcuts.ts`, `src/parity/{catalog.ts,presenter.ts,engine.ts}`, `src/model/stream.ts` (local model call).
- `tests/native-compositor.py` (93 lines) — **template for `tests/gpuix-shell/smoke_*.py`**: asserts no inherited `WAYLAND_DISPLAY/SWAYSOCK`; env `WLR_BACKENDS=headless WLR_HEADLESS_OUTPUTS=1 WLR_RENDERER=$TEST_WLR_RENDERER (use gles2) WLR_RENDER_DRM_DEVICE=/dev/dri/renderD128 WLR_LIBINPUT_NO_DEVICES=1 SWAY_DISABLE_SD_NOTIFY=1 DBUS_SESSION_BUS_ADDRESS=unix:path=/nonexistent-test-bus VK_ICD_FILENAMES=/run/opengl-driver/share/vulkan/icd.d/radeon_icd.x86_64.json GPUIX_BINDING=...@gpuix/native/index.js`; waits for `sway-ipc*.sock` and `wayland-*`; captures with `grim -o HEADLESS-1`.
- Docs: `docs/native.md`, `docs/A11Y-CHAPTER.md`, `docs/PARITY.md`, `docs/FRAMEWORK-EVALUATION.md`, `docs/SHOWCASE.md`; evidence `evidence/native/manifest.json` and `evidence/native/{pointer-local,keyboard-worker,keyboard-focus-worker,model-worker,ordered-activity-worker,failure-pixman,failure-compositor-cursor}/`.
- Lineage: `/home/tom/agency-agency/ultrabuild/design/claude-suite/CTRL-K-LINEAGE.md` (five-step "GPUIX-era contract": capture context before palette focus; resolve commands with stable IDs + schemas; one invocation path; NL composition; present outcomes), `.../REQUIREMENTS.md` (A11Y-01..04 at :72-75, VIS-05 at :67, PORT-01..07 at :85), `.../RENDERER-DECISION.md:3`.

**Frozen live data for fixtures** (`/home/tom/tuesday-oct20/research_notes/Memory policy and harvest history/`)
- `live-client-sway-tree.json` (real Zenbook `get_tree`, 29.8 KB) — use as a Sway IPC fixture for rail/switcher tests.
- `live-herdr-snapshot.json` (real `herdr api snapshot`, 22.6 KB) — fixture for the herdr adapter.
- `live-client-workspace-{1..7}.txt` (kitty text per slot), `live-pane-*.json` (process info + visible text per pane).

**Project records with Tom's words** (`.../Project contracts and implementation assessment/evidence-project-state/`):
`dotfiles-T-{2,14,18,19,25}-2026-10-20.json`, `desk-T-{30,31,32,38,40}-2026-10-20.json`,
`dotfiles-record-2026-10-20.json`, plus GitHub snapshots `agency-agency-*-github-2026-10-20.json`.

**Desktop-relevant open dotfiles issues/PRs at 12:56Z** (MEASURED S3:L494): #573 attention snapshot,
#567 "no seamless way to apply and reload dotfile edits on the Zenbook from a remote session", #541
zenbook duo screen calibration, #539 Navidrome browsing (Subsonic clients, Vicinae), #512 herdr+Vicinae
workspace identity, #510 Bluetooth menu, #509 Wi-Fi menu, #508 clipboard paste, PRs #574 #571 #566 #565 #563.

---

## 6. Gaps, unknowns, risks

1. **F6/F7 collide.** shared-parity's in-app "F6 pause/resume · F7 next result" (`src/native/adapter.ts:34`) cannot reach a GPUIx window on the Zenbook: Sway grabs F6 (volume mute) and F7 (volume down) globally (`binds.conf:145-146`). Pick other keys (e.g. inside-window Ctrl+. / Ctrl+]) or bind via Sway → gpuix-shell CLI. (INFERRED from MEASURED binds)
2. **F2 collides.** PR #566 makes F2 brightness-up at runtime; the worktree `binds.conf:139` still binds F2 to the theme prompt. The shell must not take F1/F2 until #566's fate is known. (MEASURED both)
3. **Sway-workspace → herdr-workspace identity is not reliable from live state.** Titles are all `herdr-sway-projector`, marks go stale (ws1) or are missing (ws3), herdr has no per-client view API, herdr labels repeat slot numbers. A rail that shows "slot N = herdr workspace X" needs (a) the unmerged `window_title = "{hostname}: {workspace}"` + `herdr server reload-config`, or (b) reading kitty text, or (c) a herdr projector plugin. Until then the rail should show herdr status per **slot via marks** and flag "unverified" (herdr-picker already "explicitly shows its assigned workspace" for unverifiable views, `herdr-picker:4-5`). (MEASURED facts; INFERRED approach)
4. **Never call `herdr workspace focus`** from the shell to "switch": it moves every attached projector (MEASURED T-25). Switch Sway workspaces; let each projector keep its own view.
5. **Reattach collapse (T-25)** is unsolved; after a link loss every projector shows the server's focused workspace. Tom's F10 incident is this. The shell can surface it (slot shows a pane that belongs to another slot) but should not auto-restore without Tom (T-25 is "Waiting on you").
6. **The herdr adapter on the Zenbook runs over SSH** to strix (no local socket). Polling `herdr api snapshot` over SSH every few seconds costs a connection each time; `events.subscribe` would need one long-lived SSH-forwarded socket. Not decided; BRIEF says "polled". (INFERRED)
7. **Toggle "without a highlight that changes"**: no older literal source found (MEASURED by two subagents). Default: the toggle changes only the tile's content; rail selection, Sway focus border and workspace stay unchanged. (INFERRED)
8. **GPUIx chat window** (clui-cc reimplementation) is unbuilt; composer, attachments, approvals, transcript rendering, IME and accessibility are all open. herdr-web-ui reads agent transcripts from each agent's own session store (README:126), so a native chat needs the same reader or the herdr-web-ui server as backend. Which one is undecided. (REPORTED + INFERRED)
9. **The window class/app_id of a GPUIx window**: shared-parity sets `appId` in `renderer.init`; whether layer-shell surfaces and ordinary windows can be targeted by Sway rules the same way as Chrome's profile suffix was not tested here.
10. **Pixman headless does not work for GPUIx**; tests must use GLES2 + render node (MEASURED). Pointer injection through Sway does not reach GPUIx; use native simulation APIs for smokes (MEASURED).
11. **Chrome ≠ GPUIx approval**: Tom approved the Claude/Primer look in Chrome; text rendering and fonts in GPUIx are unproven against it. `registerFont(bytes)` exists only from @gpuix 0.11.0 (BRIEF); 0.10.0 proofs used system fonts.
12. **Unknown scale of the palette screenshot**: logical values in §4a assume 2×.
13. **"Same kernel"** in Tom's 12:03Z sentence is ambiguous (coordinator asked; no answer recorded). Default: same Nix fleet/flake (INFERRED).
14. herdr 0.9.4 "confirm before closing the only pane" (PR #563) may add nine prompts of friction to Tom's close flow; the shell's close action should expect a confirmation step after #563 merges. (REPORTED)
15. Not read in full: the 4585-line root session `01a15935` (other reader), S3/S4 bodies between 12:20Z and 14:00Z that concern memory/projects/CRM contracts (not desktop), and encrypted inter-agent payloads (unreadable). The A11Y/native claims of S3/S4 are taken from their docs and manifests; I re-read the manifest and failure logs but did not re-run any test.
