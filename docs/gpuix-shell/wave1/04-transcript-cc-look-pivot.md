# 04. Transcript read: cc session f3cd04ae (2026-10-13, "Agency startup platform")

Reader: one of the wave-1 transcript readers for the overnight gpuix-shell build (BRIEF.md section 2,
row "Transcripts"). Read-only; this file is the only write. Written 2026-10-20/21 while Tom is offline.

Labels: MEASURED = read tonight in the named file at the named line. REPORTED = a file read in that
session, or a subagent output written by that session, says so (path named). INFERRED = my reading.
Tom is quoted verbatim, typos kept. No em-dashes. Line pointers `L<n>` are line numbers of the jsonl
file unless another file is named. Timestamps are UTC as stored in the jsonl (CEST = UTC+2).

Helper used (MEASURED): `python3 /tmp/claude-1000/-home-tom-tuesday-oct20/94d008d7-4112-4bf7-92cd-2de4eab69681/scratchpad/transcript-text.py FILE --user-only`
plus a variant that prints the jsonl line number and timestamp (written to my scratchpad as `tx2.py`,
not kept). The stock helper drops two of Tom's turns because they were sent as queued messages
(`queue-operation` records, not `user` records); they are recovered below from L88 and L142.

---

## 1. What this source is

**File (MEASURED):** `/home/tom/.claude/projects/-home-tom-today/f3cd04ae-4561-4bb0-a818-95198eed2e7d.jsonl`
- 500 lines, 1,973,032 bytes, mtime 2026-10-14 08:22 local.
- Claude Code 2.1.287, cwd `/home/tom/today`, permissionMode `bypassPermissions`, model opus 5.5 for the
  main loop (cost-state at L499-500: `claude-opus-5-5` 3.16M output tokens, `claude-haiku-4-5` for 204
  web searches; `totalCostUSD` 255.36).
- AI title (L24): **"Agency startup platform"**. Slug after compaction: `refactored-brewing-sparkle`.
- Span: first turn 2026-10-13T21:29:18Z (23:29 CEST), last real turn 22:55:39Z, manual compaction at
  23:50:22Z (L480, `preTokens` 301,945 -> 15,761). Nothing after the compaction summary at L481 except
  housekeeping records. So the "10-13/14" in the brief means the night of 10-13 only; the file's 10-14
  mtime is the cost-state write.

**What the session did (MEASURED L5-L481):** Tom picked a failed Codex handoff up "one level of
abstraction above" and scoped **agency.agency** as a company. The session ran two ultracode workflows
of 3 waves x 8 Opus agents, no verify stage:
1. "Agency scoping" (task w7ut9o3xd, L376): output `/home/tom/today/2026-10-13-agency-scoping/` (wave1/01-08,
   wave2/01-08, wave3/01-07, `AGENCY-SCOPING-2026-10-13.md`, 865 lines). Script:
   `~/.claude/projects/-home-tom-today/f3cd04ae-4561-4bb0-a818-95198eed2e7d/workflows/scripts/agency-scoping-three-waves-wf_868ef072-566.js`.
2. "Cost trail" (task wuthlhcuz, L437): output `/home/tom/today/2026-10-13-cost-trail/COST-TRAIL-2026-10-13.md`.
   Script: `cost-trail-three-waves-wf_e248b3e0-183.js` in the same folder.

**The important correction for the builder.** The BRIEF calls this "the 'agency.agency' and look pivot
session". MEASURED: it is the agency.agency session, but it holds **no Tom statement about the
Claude/Primer look, the left rail, Mod+i, the one-to-one workspace mapping, Vicinae/mako/waybar
replacement or gpuix**. Tom typed five messages here (section 2.1) and all five are about Agency as a
startup, the ultracode run shape, and the cost trail. The look-pivot material lives in the sibling cc
session `56e498e4` on 2026-10-14 (section 2.4 gives line numbers so nobody has to hunt), and in the
10-07 "dematerialized desktop" file that this session re-read (section 2.2). What this session does
contribute to the shell build is (a) the **boundary** between the personal shell and the shareable
utilities, stated by Tom on 10-13/14 and worked out by 24 subagents, and (b) a REPORTED timeline of
Tom's desktop-shell rulings from 10-01 to 10-13 (section 2.3), which explains why "no native shell
whatsoever" (10-07) was superseded by the gpuix shell order of 10-20.

---

## 2. Verbatim Tom rulings relevant to the desktop shell (with dates)

### 2.1 Typed by Tom in this session (MEASURED, jsonl line and timestamp)

**R1. The frame: Omarchy holds the one-person desktop; Agency is the team layer. L5, 2026-10-13T21:29:18Z**
> "let s pick  ths up one level of abstraction above.
> omarchy as linux is making massivem oves
> https://www.vesence.com/ is doing that sa well
>
> i can build this for companies. this is agency.agency (also retrieve that on the projects that we juts implemented)
>
> this is the full convergence of everythying from dotfiles and into something that is marketable, a full on startup that needs no capital. and we're building this today"

Note for the shell: "full convergence of everythying from dotfiles" is the sentence that later nights
turned into "the personal shell lives in dotfiles, the utilities are the product" (section 2.4, R12).
The 10-13 scoping run itself ground this cow down to "what converges is the rules and the templates;
the repo stays yours" (REPORTED `wave2/07-sacred-cows.md:70`).

**R2. Queued message, L88 (enqueued 21:30:07Z, removed 21:31:25Z):**
> "already did rese3ar4ch on vesence retrieve that."

(The research is `/home/tom/today/desktop-2026-10-07/27-vesence.md`; the session read it at L117.)

**R3. Queued message, L142 (enqueued 21:32:03Z, removed 21:32:35Z):**
> "omarchy is crushing it onthe desktop. we re just doing something that s slightly more teams oriented.
> i nteh past few days i ve build a set of personal tooling. we also have sodimo (idealized) impelemtnation paratmeters for an entire team"

Note for the shell: this is the clearest 10-13 statement that the desktop itself is **not** the
product: Omarchy "crushes" it, Tom's thing is "slightly more teams oriented". Seven days later Tom
nevertheless ordered a personal desktop shell (BRIEF section 1). INFERRED: the two are consistent
because the shell is personal ("my shell", in dotfiles, private repo) and is explicitly not what
Agency sells; see R12.

**R4. The research list and the run shape. L258, 2026-10-13T21:39:14Z**
> "https://buzz.xyz/ is another interesting to look ihto as far a sproduct offering. and openwebui compreehsively bcz it did the exact same. also remember my cloudflare centricity. herdr workspaces now offered by railway or others
>
> ultracode workfkows 8 opus per wvaes 3 wavews no verify first wavew is do the onhline research plus noters recovery from scartch the whole thing in notes my history personally all the way to what we re building now the second wave to synthesize and add in my ai startup learnings from leger and enoki days and the rob snyder approach and the third wave is to synthezise
>
> no wall clock ever. no defifitnitions
>
> heuristics:
> - never implement any code whatsoever in gh repos this is pure fucntional and project based scoping
> - sacred cows make the best burgers
> - think with a product perspective in mind: what we can build, that is missing space, that is "claude teams but orthogonal to claude desktop at its current featureset whici is consider my github plus cloudflarew plus dotfiles stack (1 or 2 opus agents to undrestand latest tsate of things)"

Standing rules a builder should carry over: "no wall clock ever. no defifitnitions" (no time
estimates, no glossary sections in notes); "sacred cows make the best burgers" (any component may be
dropped). "never implement any code whatsoever in gh repos" bound **that** scoping run, not tonight's
build (Tom's 10-20 order explicitly asks for code).

**R5. The cost-trail run. L321, 2026-10-13T21:53:58Z**
> "one partallel massive run (ultracode workflow 3x8) : on my trail in the last few months, from decision model routing to local ai model optimization (tunguz skill distillation at massive scale) all the way to bayesian gambardella functionality but for cutting costs."

Not about the shell. Listed for completeness: these are all five of Tom's turns.

### 2.2 Tom's words re-read by this session from files (REPORTED; the file is the source)

The session read `~/today/dematerialized-2026-10-07/00-TOM-WORDS-AND-FRAME.md` at L118/L136 (tool
result persisted at `/home/tom/.claude/projects/-home-tom-today/f3cd04ae-4561-4bb0-a818-95198eed2e7d/tool-results/bt34drk4n.txt`).
That file records Tom on **2026-10-07 late evening**:

**R6. Supersede Vicinae; herdr-web-ui is the starting point (10-07).** `00-TOM-WORDS-AND-FRAME.md:5-7`
> "just read the md file you prepared in the initla md format, specificlaly the parts on openclaw. i like it but it's the wrong aperature.
> i also push back completely on its "keep vicinae" framing.. i would like to fully supersede this.
> https://github.com/devswha/herdr-web-ui was updated to latest version 2 hrs ago, and it s literally growing more now. my observation of it is that it honestly looks great; like a wonderful starting point"

This is the earliest "Vicinae goes" ruling I found in material this session touched. It predates the
10-13 ideal-state sheet that said "Vicinae stays and grows" (REPORTED `wave1/06-history-2026-to-now.md:212,286`),
and both predate the 10-20 order "a mod+d menu (vicinae remplacement)". Newest wins: Vicinae is replaced.

**R7. The dematerialized Claude desktop, harness-agnostic (10-07).** same file `:9-19`
> "so let me put it plainly then, once: we have tried doing this in the past but now i am conceiving somehting more ambitious in scope. we are to imagine how a dematerialized claude desktop would be. the only difference is that i want to be agent-harness agnostic.
> this is not just the claude.ai chat interface by the way. claude has many thingsthat i want:
> - mananged agents platform (conceptually, the conwip factory concept)
> - routines
> - Projects (that i ve analyzed many times over)
> - in claude code: ultracode-workflows shaped like jsonl (in our case this goes through ax kubernetes... in our world we keep herdr for "live, hunan-centric interactions" and use those other agents to spread the compute and have things executed overnight in the background
> - the chat interface itself (we already have)
> - the full suite of connectors, my email, crm, etc all in one place
> > we even saw what a hypothethical claude/anthropic calendar was (all the way to screenshots)... i m htinking we can achieve that now for a single-person.
> - claude now has documents, spreadsheets and presentations... basically like a google suite of sorts.
>
> the idea of "stateless" or impermanent nixos config as an enforceway to have the "kill your darlings" interpretation on nix, meaning the whole local ai fleet is in the closet and from my perspective it's exactly like having claude "expanded and selfhosted": dematerialized"

Why it matters for the shell: "the chat interface itself" + "connectors in one place" are the
utilities side of the boundary; the shell only launches them (BRIEF decision 8). The Claude/Primer
look of the shell is the visual consequence of "a dematerialized claude desktop".

**R8. Desk memory rulings read at L44/L53 (`project memory show desk`, REPORTED):**
- 2026-10-12: "my goal for this was to have a personal "unified mcp" (codemode) that connects to my email; crm; calendar; backlog (or whatever becomes of backlog). no cloudflare-access-gating either." and "re personal utilities being on multiple workers, that is totally fine by me. but i want to be able to have claude interface with them (via mcp) in one place. that's the ergonomics that are apealing to me" (cc 1376398e L204).
- 2026-10-12: "diagrams? i dnt care about that. i didn t ask for  a onepager." (cc 1376398e L1509). Builder note: no unrequested diagrams in docs.
- 2026-10-12: "i don't like these questionaires." (cc 03d0141c L186).
- 2026-10-13: "your use of self-referential items like "the 27-front mapping" makes no sense to me, you have to assume that i don't have knowledge about what those are ... i want ot speak in plain language to it, and it should handle the complexity." Builder note: MORNING.md must be plain language, no internal labels.
- 2026-10-13: "given that we have my Projects+Substrate funcitonal, the right behavior there is for claude (you, the orchestrator) to NOT delve into the code right away: intead we would schedule the work on the conwip."

**R9. dotfiles thread T-2 read at L93 (`project thread list dotfiles`, REPORTED):**
"T-2 Launcher clean-up across the fleet, Vicinae font 12, mako blue [Idle]" with the front-door note:
"Vicinae settings are written by Nix from `home/vicinae.nix` (font 11 there; INFERRED cause), so font 12
and the two hidden commands go in that file. Removing the soundcloud shortcut also removes the Mod+M
SoundCloud pane (`flake.nix:186`); default: remove both." Builder note: the launcher font Tom asked for
on Vicinae was **12**, and mako's accent was to become **blue** (the theme's accent); the gpuix launcher
and toasts should start from those two values. `home/vicinae.nix` is listed in BRIEF as the file to replace.

### 2.3 The desktop-shell timeline recovered by this session's subagents (REPORTED)

`/home/tom/today/2026-10-13-agency-scoping/wave1/06-history-2026-to-now.md` section 11-13 (written
2026-10-13 23:54 by a wave-1 reader of this session; it cites `~/today/UNIFIED-SURFACE-2026-10-07.md`,
`~/today/FINAL-STATE-2026-10-07.md`, `~/today/ideal-state-2026-10-13/RULING-SHEET-2026-10-13.md`). The
rulings, in order, each still binding unless a newer one overrides it:

| Date | Tom (verbatim, REPORTED via wave1/06) | Line in wave1/06 | Status on 10-20 |
|---|---|---|---|
| 10-01 | "i have been stuck on dreaming about this full control over chromium aura, when i should hvae instead realized that the wlroots-based system that i use is already good enough; and there is no need to reinvent this exact wheel." / "no forking my browser" | 172 | stands: Sway (wlroots) is the compositor |
| 10-06 | otto compositor dropped: "Frosting, animations and the otto file manager was just not enough" | 174 | stands; INFERRED it also explains "no blur, no frost" in BRIEF |
| 10-07 am | "herdr itself is becoming the true cornerstone of this setup. truely: herdr+kitty+chrome+claudecode + vicinae"; "think about herdr as if it was the "headless google chrome"" | 175 | stands minus Vicinae (R6, 10-20 order) |
| 10-07 pm | "settling for a unified interface - all through a google chroem browser, no native shell whatsoever. this is the boundary where i stand now." | 176 | **superseded** by the 10-20 order for a gpuix native shell; the Chrome-webapp half (utilities) stands |
| 10-07 pm | "i have given up on the chromium fork in any shape, now decided to stick to trusty google chrome." / "notes and dotfiles are what i m aiming for." | 176 | stands |
| 10-10 | "i insist that no frontend gets built until the funcitonality is all green."; "i will not be buying more technology at all"; "i want to use the hardware that i own to the maximum" | 185 | stands for the utilities; the 10-20 order makes the shell itself the functionality |
| 10-12/13 | "prefer to remain as close to "claude defaults" as possible" | 187 | stands; INFERRED it is the root of "Claude/Primer look" |
| 10-13 | "20. CUBS (the browser) this project in its entirety we actually decided that i was not going to work on that" | 196 | stands; CUBS stays a feature list to mine (BRIEF row CUBS) |
| 10-13 | utilities index: "post-cfos ... the herdr-web-ui era where i fork and customize the existing herdr-web-ui plugin" | 194 | stands: herdr-web-ui fork is the chat view; the shell reads herdr state |
| 09-20 | "i don't want to have systemd-driven timers whatsoever." | 219 | stands (BRIEF: no cron/timers in dotfiles) |

wave1/06 itself flags the contradiction (line 286): "Vicinae: "no native shell whatsoever" (10-07)
against "Vicinae stays and grows" (10-13 sheet) ... Tom's "newer is truer" rule picks the 10-13 lines;
nobody has asked him." The 10-20 order resolves it a third way: Vicinae is replaced by the gpuix launcher.

### 2.4 Where the actual "look pivot" rulings are (MEASURED pointers to the sibling session)

Not this file. `/home/tom/.claude/projects/-home-tom-today/56e498e4-f44d-40bd-8caa-6f3f54587411.jsonl`
(12.5 MB, 2026-10-14 to 10-15) holds these Tom turns, quoted here because they are the shell boundary
and the left-rail statements the BRIEF paraphrases:

**R10. L1512, 2026-10-14T13:37:43Z, the gpuix breakthrough and the classification of notes:**
> "the major breakthrough is the recent gpuix react products plus terminal that can be "mirrored to a front end""
> "... we classify things between:
> - how the computer is being used; direct functinality skills or sway shortcuts or commands
> - inspiration : owui pipelines era , leger thoughts and back and forth ; cloudflare-os implementation."
> "... this is something that we have started doing inm y local dotfiles all the way to the hold space for dictation functionality (omarchy voice style)"

**R11. L1802, 2026-10-14T16:00:22Z, macOS twin and the utilities list:**
> "yesterday we did attempts to use gpuix to materialize a herdr web ui chat , a crm , an email tool , a backlog projects tool... all those have agency oss repos"

**R12. L1861, 2026-10-14T16:08:40Z, THE BOUNDARY (personal Sway shell vs shared utilities):**
> "agency-agency is the shared github org. it has separate implementations for pure full desktop like wayland (sway for now) desktop shell and the shared with macos that overlays
>
> special features of sway: swap kitty terminla herdr and herdr web ui translated into my own implementation.
> sway has a contextual launcher, a herdr leftbar that is disjinted and contol sway workspaces, clipboard history.. all that stuff that macos version doesn't have. this creates a clean sepaeation layer which is much appreciated but it sits at the same library fundamentally.
>
> the design prompts for two claude design web sessions should be done at some point. read @~/wednesday-oct14-midday.md for some notes on that and the geist radix or react primer and so on and so forth implementations and variatipons until we iron out completely the entire set of possibles and distill a minimla set of design elements that can cerate a definite top tier interface. the starting point is yesterday's demo's of email. crm, chat that i m using today in https://strix.tail8dd1.ts.net:8443/?ws=wGK-client-slot-2-fc7de0&pane=wGK%3Ap1&view=chat already which is great and can t wait ti use it for the full suite of projects as well
> ...
> macos has parity with the "tray/dock" items: crm, email, projects, files, the vesence ones (resurface from investigation); this is what we build as native apps. there is the massive backdrop that has the cloudflrae."

Read for the builder: the Sway-only features are **(1) swap kitty-terminal herdr <-> herdr-web-ui**
(the Mod+grave swap in `herdr-sway-context`), **(2) a contextual launcher** (Mod+d), **(3) a herdr
leftbar that is "disjointed" from the chat and controls Sway workspaces** (the rail), **(4) clipboard
history**. Shared with macOS and NOT the shell: crm, email, projects, files, "the vesence ones", as
native apps, "at the same library fundamentally" (gpuix). This is the exact boundary BRIEF decision 8
encodes. Note the "files" app sits on the **shared** side in R12 but BRIEF decision 2 puts `gpuix-shell
files` (Pinax-like) in the shell; see Gaps G4.

**R13. L2841, 2026-10-14T20:49:58Z, the design system reference:**
> "the design system is close to what was built in the local gpuix proof of concept on the linux desktop ; we port that functionality like email crm etc. there"

**R14. Tom's own note the R12 turn points at: `/home/tom/wednesday-oct14-midday.md:325-329` (MEASURED, mtime 2026-10-14 16:04):**
> "the bottom macos tab bar: utilities like email etc can go below. herdr tabs on the left with sway and herdr control ;
>
> desktop env we'll whiteglove go onto those files ; then ensure the learning-as-we-go algorithm is implemented. ha that be the whole desktop. te unified claude bot in gpuix that can "ru my life"
> i like the idea of interchangeability between terminal and herdr-web-ui
> it's utilities and skills and things that get a shortcut to that. the idea is that we "puppetteer" the desktiop interface without consuming lots of effort from the claude controlling llm. the desktop interfaces are sortcut driven."

and `:274`:
> "2x esign agents end to end then one attempt per: vercel radix gh react ; claude; pure react ; claude instinctive ; cf design systems; views-c++ and the other desktop shells ; the whole thing end to end individually with the same ystsem prompts and identifying the minimum needed set of "design constraints" (even more abstract than components) that we can get satisfactory interfaces out of yet that remain well written and unified."

Read for the builder: **"herdr tabs on the left with sway and herdr control"** is the left rail in
Tom's own words (10-14); "utilities like email etc can go below" is a macOS-side bottom tab bar, not
the Linux head ("no top bar on the Linux head" per BRIEF). "the desktop interfaces are sortcut driven"
+ "puppetteer the desktop interface without consuming lots of effort from the claude controlling llm"
= every surface must be reachable by a Sway bind and by the `gpuix-shell` CLI (BRIEF decision 2), so an
agent can drive it cheaply.

The other two transcripts the BRIEF lists were scanned for the same keywords (MEASURED, user turns
only): `683f84a0` has 0 hits; `1a517fb2` (dotfiles cwd, 10-20) has one hit at L493 ("the unified gpuix
workspaces") which is today's MAP.md order, already summarised in MAP.md section 5.

---

## 3. Feature and behaviour inventory

Everything this session (and the files it read or produced) says about pieces the gpuix shell touches.
"Where it lives today" is REPORTED from `wave1/08-state-dotfiles-tooling.md` (written 2026-10-13 23:53,
MEASURED against the dotfiles checkout then) unless marked otherwise; it may have moved since 10-13.

| Feature | What exactly | Where it lives today (10-13 state) | Keep / replace / new | Notes and source |
|---|---|---|---|---|
| Compositor | Sway only; niri and scroll removed; Hyprland tried 10-14 and dropped | `home/dot_config/sway/*`, client host `67165e0c` on 10-13 | keep | wave1/08:37 "niri and scroll, so Sway is the only compositor"; R-10-01 "wlroots-based system ... already good enough" |
| Launcher | Mod+d menu; Vicinae today, font 12 requested, two commands hidden, Mod+M SoundCloud pane removal | `home/vicinae.nix` (font 11 in Nix), `flake.nix:186` | replace (gpuix launcher) | R6 "fully supersede"; T-2 (R9); 10-20 order "mod+d menu (vicinae remplacement)" |
| Notifications | mako; accent to become blue | `home/vicinae.nix` services.mako; `home/themes/default.nix` mako fragment | replace (gpuix notifications daemon) | T-2 "mako blue" (R9); 10-20 order "notify-send remplacement to mako" |
| Workspace bar | waybar deleted 2026-09-11; today nothing on the Linux head | `git show 1d926f2e^:home/dot_config/waybar/*` (BRIEF) | new (left rail) | R12 "a herdr leftbar that is disjinted and contol sway workspaces"; R14 "herdr tabs on the left with sway and herdr control" |
| Left rail content | herdr workspaces as tabs with agent status; Sway workspace 1..9 control | herdr-web-ui fork `/home/tom/mecattaf/herdr-web-ui` (DESIGN.md, 220/30/12/2/8 per BRIEF) | new | wave1/08:65 on 10-13: "No herdr web UI is declared in dotfiles and none runs on strix ... The fork is "not started; a demo ran on 10-07, nothing kept"". By 10-14 Tom was using it daily (R12 URL on strix:8443) |
| Terminal <-> chat swap | kitty projector herdr pane swapped with herdr-web-ui view | `herdr-sway-context` branch Mod+grave (BRIEF) | keep, wrap in shell | R12 "swap kitty terminla herdr and herdr web ui"; R14 "interchangeability between terminal and herdr-web-ui" |
| herdr reach | `herdr-projector` over SSH (LAN) / Tailscale; herdr 0.9.3 user unit on strix, `X-SwitchMethod=keep-old`, `OOMPolicy=continue` | `home/herdr.nix` | keep, read-only from the shell | wave1/08:65,69. Never restart herdr (BRIEF) |
| Clipboard history | Vicinae's today | Vicinae | replace (own store) | R12 "clipboard history.. all that stuff that macos version doesn't have"; BRIEF decision 4 |
| Dictation / hold space | "hold space for dictation functionality (omarchy voice style)" started in dotfiles | not located this pass | keep as a Sway bind | R10 (10-14). Not in BRIEF's script list; see G5 |
| Theme | noir default, claude-dark, claude-light; `~/.config/theme` symlink | `home/themes/*.nix`, `~/.local/bin/theme` | keep, add `gpuix-shell.json` fragment | BRIEF; not discussed in this session |
| Fonts | Anthropic Sans / Serif / Mono Nerd | `pkgs/anthropic-ui.nix`, `pkgs/anthropic-mono-nerd.nix` | keep | BRIEF; not discussed in this session |
| Shared browser | `browser.internal`: headless Sway seat + Chrome via noVNC on strix | strix only | keep, out of shell scope | wave1/08:78 |
| Chrome web apps | utilities (mail, crm, projects) as Chrome apps on workspace 10 | `home/vicinae.nix` desktop entries (BRIEF) | keep; the shell launches them | 10-07 "views-shell is gone, replaced by Chrome web apps" (wave1/06:211) |
| Utilities (mail, CRM, project tool, calendar, one MCP) | Cloudflare Workers; mail 49,936 msgs / 6 accounts; CRM 2,040 orgs; project tool 5 projects; calendar = Google; one code-mode MCP not started | `~/agency-agency/{mail,crm}`, project Worker | NOT in the shell | R8 10-12 "unified mcp"; wave1/08 section 2.3; BRIEF decision 8 |
| Print / speech drops | `~/Paper/intake`, `~/Speech/intake` path units on strix | strix | out of shell scope; a launcher action at most | wave1/08 section 2.4 |
| Call recording | `call-record` on the client, diarization on strix | client | out of scope; a launcher action at most | wave1/08 section 2.4 |
| Local model | Halogen Qwen3.8-Flash-Next at `strix:8731`, Gufo declared but off | `modules/gufo.nix` | keep for `gpuix-shell ask` only | wave1/08:74; BRIEF decision 7 |
| Factory / substrate | CONWIP floor Worker, puller/pusher on strix, 12 runs max | `hosts/strix/default.nix:94` | out of scope; the rail may show "runs in flight" later | wave1/08:72; R8 10-13 "schedule the work on the conwip" |
| Timers | none in dotfiles | n/a | keep (none) | 09-20 ruling (wave1/06:219) |
| macOS twin | same gpuix library, native apps crm/email/projects/files, bottom tab bar | `agency-agency` org (10-14) | NOT in dotfiles | R11, R12, R14 |

INFERRED ordering for tonight from R12: the four Sway-only features (swap, launcher, left rail,
clipboard) are the shell's reason to exist; everything else in the table is either kept untouched or
launched.

---

## 4. Design values (sizes, colours, fonts, radii, timings)

MEASURED: this session contains **no numeric design values**. Tom typed nothing about sizes, colours,
fonts or timings in it, and the subagent outputs are product scoping, not UI. The only UI-adjacent
numbers in material this session touched:

| Value | Source | Label |
|---|---|---|
| Launcher font 12 (Vicinae; Nix had 11) | dotfiles T-2 as listed at L93 | REPORTED |
| mako accent "blue" | dotfiles T-2 title at L93 | REPORTED (no hex given) |
| herdr-web-ui rail 220 / 30 / 12 / 2 / 8 | BRIEF row "herdr-web-ui fork" (not this session) | REPORTED |
| Rail exclusive zone 56 collapsed / 220 expanded; launcher 700x580 top margin 108; toasts 390 wide max 4; OSD bottom margin 96 | BRIEF decision 3 (from SHELLS-DIGEST, not this session) | REPORTED |

Design direction words from Tom that do bear on values (all 10-14, R12/R14, sibling session): "geist
radix or react primer ... distill a minimla set of design elements"; "the desktop interfaces are
sortcut driven"; "design system is close to what was built in the local gpuix proof of concept".
For numbers, go to `/home/tom/today/2026-10-17-frank/design-handoff/HANDOFF-B.md` and
`/home/tom/mecattaf/herdr-web-ui/DESIGN.md` (BRIEF rows), not here.

---

## 5. Reusable code or data, with exact paths

Nothing in this session is shell code. What is reusable:

**Tom's words, verbatim, already extracted (MEASURED, still on disk):**
- `/tmp/claude-1000/-home-tom-today/f3cd04ae-4561-4bb0-a818-95198eed2e7d/scratchpad/tom1.txt` (R1), `tom3.txt` (R3), `tom4.txt` (R4), `tom5.txt` (R5), `tom-root-build.txt`. These are `/tmp` and will not survive a reboot; the jsonl lines above are the durable pointers.
- `/home/tom/today/dematerialized-2026-10-07/00-TOM-WORDS-AND-FRAME.md` lines 5-19: the 10-07 "supersede vicinae" and "dematerialized claude desktop" statements (R6, R7). Also persisted as the tool result `.../f3cd04ae-.../tool-results/bt34drk4n.txt`.
- `/home/tom/wednesday-oct14-midday.md:274, 325-329` (R14): the left-rail and shortcut-driven sentences.

**Subagent outputs of this session worth mining for the shell (REPORTED content, MEASURED paths):**
- `/home/tom/today/2026-10-13-agency-scoping/wave1/06-history-2026-to-now.md` sections 11-13 (lines 165-220): the dated ruling table for the desktop (Aura, otto, views-shell, CUBS, Vicinae, timers). Section 17 item 8 and the Unknowns list name the Vicinae contradiction.
- `/home/tom/today/2026-10-13-agency-scoping/wave1/08-state-dotfiles-tooling.md` section 2 (lines 58-110): one-line state of every fleet piece on 10-13 with MEASURED labels (herdr unit flags, client revision, browser.internal, print/speech paths, Halogen port). Section 2.6 is cited as "12 nix files in dotfiles name the user `tom`" (a portability note if the shell is ever shared).
- `/home/tom/today/2026-10-13-agency-scoping/wave1/07-state-github-cloudflare.md` lines 48-71, 105-111, 130, 142: the graveyard of earlier shells (views-shell 175 commits, `agency` Chromium shell, `spec`, `appliance`, `agency-mvp`, `theming-kit`, `cubs-campaign`) and the fact that on 10-13 no herdr-web-ui ran anywhere for Tom. Use it to avoid re-mining dead repos; the BRIEF already points at CUBS docs for the feature list only.
- `/home/tom/today/2026-10-13-agency-scoping/wave2/07-sacred-cows.md` lines 48, 70-71, 130-144: the case for and against "Linux and Omarchy in the offer" (ground out of the product; irrelevant to the personal shell but it is why the shell stays private).
- `/home/tom/today/2026-10-13-agency-scoping/wave3/03-product.md` line 44 and 202-217, and `AGENCY-SCOPING-2026-10-13.md` lines 278-295, 606, 621, 626-627: the product-side boundary table ("the desktop: Windows, macOS, Claude Desktop, and Omarchy for one person on Linux" is NOT built by Agency; "a browser or a shell: ruled out by Tom on 2026-10-13"; killed cow 27 "The herdr web UI as the team's surface"; killed cow 30 "Omarchy as the frame for clients"; kept ruling 17 "Tom's personal rulings on Access, front ends and limits: they stand for his own setup and are reversed only for what a client receives").
- `/home/tom/today/desktop-2026-10-07/27-vesence.md` (read at L117): Vesence's "Desktops and the Dock" (2026-09-22), inbox and tiling; R12 says "the vesence ones (resurface from investigation)" are candidate utilities for the macOS side, not the shell.

**Workflow scripts (MEASURED paths, reusable as shape for tonight's fan-outs):**
- `/home/tom/.claude/projects/-home-tom-today/f3cd04ae-4561-4bb0-a818-95198eed2e7d/workflows/scripts/agency-scoping-three-waves-wf_868ef072-566.js`
- `/home/tom/.claude/projects/-home-tom-today/f3cd04ae-4561-4bb0-a818-95198eed2e7d/workflows/scripts/cost-trail-three-waves-wf_e248b3e0-183.js`
  Both are 3 waves x 8 agents with barriers and a 7-writers-plus-1-integrator wave 3; Tom's 10-20 rule
  (agent-workflow-rules.md) still says no verify stages.

**Helper:** `/tmp/claude-1000/-home-tom-tuesday-oct20/94d008d7-4112-4bf7-92cd-2de4eab69681/scratchpad/transcript-text.py`.
Known gap (MEASURED): it skips queued user messages (`type: queue-operation`) and prints no timestamps
or jsonl line numbers; other readers should scan `queue-operation` records too (this session had two
real Tom turns there, R2 and R3).

---

## 6. Gaps and unknowns

- **G1. Misattributed source (MEASURED).** The BRIEF's "look pivot session" label does not fit f3cd04ae.
  The look-pivot words are in `56e498e4` L1512, L1802, L1861, L2841 (10-14) and in
  `/home/tom/wednesday-oct14-midday.md`. Whoever reads `56e498e4` for wave 1 should treat section 2.4
  above as a head start, not as complete: I scanned only user turns matching shell keywords, not the
  assistant turns or the "whatever you just opened: i love it" exchange that BRIEF quotes (that line
  did not match in any of the three listed transcripts' user turns; it may be in
  `/home/tom/.claude-work/projects/-home-tom-tuesday-oct20/4253a15b-....jsonl` or a Codex rollout).
  Default: the orchestrator re-points reader 04's slot at `56e498e4` or `4253a15b` if a second pass is run.
- **G2. "No native shell whatsoever" (10-07) vs the 10-20 gpuix shell order.** Not reconciled by Tom in
  words I read. Default (INFERRED from R12, 10-14): the 10-14 "sway ... desktop shell" sentence already
  reversed 10-07, and 10-20 confirms it. Record in ASSUMPTIONS.md.
- **G3. "Omarchy is crushing it on the desktop" (10-13) vs building a shell.** Tom never said the shell
  competes with Omarchy; the scoping run killed "Omarchy as the frame for clients". Default: the shell
  is personal, in the private repo, never in the Agency offer; Omarchy remains a feature-mining source
  (its dock and floating mode, wave1/03 says merged 10-11/10-13), nothing more.
- **G4. Where the files explorer sits.** R12 (10-14) lists "files" among the macOS-parity native apps
  (shared library side); BRIEF decision 2 makes `gpuix-shell files` a shell surface; Tom's 10-20 words
  want "mainly the file explorer" from Tacit. Default: build it in dotfiles tonight as an ordinary
  gpuix window with no compositor dependency, so it can be lifted to the shared side later.
- **G5. "hold space for dictation functionality (omarchy voice style)"** (R10): started in dotfiles per
  Tom, not in BRIEF's script list, not located in this pass. Default: a reader of `home/dot_local/bin`
  greps for `speech`/`dictat`/`hold`; if found, it gets a launcher action and an OSD state, not a rewrite.
- **G6. mako "blue"** (T-2): no hex. Default: the theme's accent token from `home/themes/noir.nix`.
- **G7. herdr-web-ui state moved fast.** On 10-13 the fork was "not started" and nothing ran (wave1/08);
  on 10-14 Tom used it daily at `strix:8443` (R12). The 10-13 inventory in section 3 is therefore stale
  for that row; BRIEF's `/home/tom/mecattaf/herdr-web-ui/DESIGN.md` is the live source.
- **G8. Two of Tom's five turns are invisible to the stock helper** (queued messages). Any other wave-1
  transcript note produced with `--user-only` alone may be missing turns the same way.
- **G9. Not verified:** nothing in this note was run against the live system; all "where it lives today"
  rows are REPORTED from 10-13 subagent reads and should be re-checked against the gpuix-shell worktree
  by the surface owners. No verify pass was run on this note (agent-workflow-rules.md).

## What I did and did not do

Did: read BRIEF.md in full; dumped every user, assistant and tool-result turn of f3cd04ae with line
numbers and timestamps; recovered the two queued turns; read the persisted 10-07 frame file as that
session saw it; grepped the 24 wave files and the integrated document that this session produced for
every shell-related line and read the relevant sections; scanned the three other Claude transcripts
the BRIEF lists for user turns with shell keywords and read the matching 10-14 turns in full; read
`/home/tom/wednesday-oct14-midday.md:268-329`.
Did not: read the assistant turns of `56e498e4`, any Codex rollout, or `4253a15b`; touch anything
outside this file.
