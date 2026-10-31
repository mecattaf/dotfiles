# 12: Boundary, claims and packets (friday16oct-planning) for gpuix-shell

Reader 12, wave 1 of the overnight gpuix-shell build, written 2026-10-20 (night, CEST) by a Claude subagent. Read-only pass. This file is the only thing written.

**Labels used.**
- **MEASURED**: I read it tonight at the path and line given, or I matched a quote against the primary transcript record.
- **REPORTED**: another document says so (path given). For Tom quotes, "REPORTED (friday register)" means the 10-16 planning run says it checked the quote against the named JSONL line. I did not re-open that line unless the entry also says MEASURED.
- **INFERRED**: my reading or proposal. Check it before relying on it.

**Path shorthands.**
- `FP` = `/home/tom/friday16oct-planning`
- `UB` = `/home/tom/agency-agency/ultrabuild` (`inputs/SEPARATION.md`, `inputs/plans/agency-launch/additional/{SWAY-ONLY,LAYERS}.md`)
- `WT` = `/home/tom/.wt/hyprland-solid-shell`
- `GS` = this worktree, `/home/tom/.wt/dotfiles/gpuix-shell`
- `WEB` = `/home/tom/mecattaf/herdr-web-ui`
- `GPX` = `/home/tom/Downloads/gpuix`

---

## 1. What this source is

### 1.1 Files read

The friday package is one planning-only research run on 2026-10-16. It started at 07:55 UTC, was paused by Tom at 10:32:26 UTC, resumed around 12:24 UTC and delivered at 12:36:56 UTC (`FP/RUN-LOG.md:3,30-34`, MEASURED). Desk thread T-38 coordinated it. Every canonical file is labelled "proposed" and authorizes no implementation (`FP/SPEC.md:14`, `FP/PACKETS.md:3`).

| File | Lines | What it holds | Read |
|---|---:|---|---|
| `FP/BOUNDARIES.md` | 102 | The canonical "personal vs shareable" matrix (12 components × owner/shared/platform/config/proof), sharing axes, journeys, seams, shared-library cuts | in full |
| `FP/PACKETS.md` | 100 | 8 execution packets: FIRST-MAC, RELATIONSHIPS, PARITY, INTEGRITY, ADAPTER, PERSONAL-SHELL, CONTEXT, HARVEST | in full |
| `FP/SPEC.md` | 124 | Rulings list plus 38 claims C1.1–C6.4 in six stages A–F, open questions Q1–Q3, out of scope | in full |
| `FP/PROVE.md` | 103 | Ledger rows P1.1–P6.4. Only P1.1–P1.3 are static-source passes; every other row is `pending` | in full |
| `FP/CONTRADICTIONS.md` | 126 | Dated supersessions, scope differences, implementation gaps, corrections | in full |
| `FP/DECISIONS.md` | 13 | Only three open user-value choices, none of them shell-specific | in full |
| `FP/GEMS.md` | 66 | Overlooked ideas | in full |
| `FP/GUIDE.md`, `SCOPE.md`, `CHARTER.md`, `README.md`, `RUN-LOG.md` | — | Reader guide, utility-family scope, charter, run log | in full |
| `FP/reviews/product-host-and-herdr.md` | 95 | GPUIx host capabilities G01–G10; Herdr ownership H01–H07 | in full |
| `FP/evidence/boundary-herdr-rail-cutlines.md` | 86 | Exact reusable cuts of the herdr-web-ui rail | in full |
| `FP/reviews/shared-library-host-extraction.md` | 136 | What is really shared (GPUIx/kit/prototypes); Tab hazard; cuts A, B, C | in full |
| `FP/reviews/utility-family-boundary-inventory.md` | 48 | Calendar, files, artifacts, print, OCR, speech, media | in full |
| `FP/reviews/product-boundary-matrix.md` | 63 | Mechanism matrix (CUL, agent-seat, Screenpipe, Otto); 5 integration shapes | in full |
| `FP/reviews/personal-shared-boundary-source.md` | 214 | Ownership axes, component matrix, rail section, repair graph | sections 29–65, 111–128, 156–214 |
| `FP/evidence/boundary-agent-entrypoints.md` | 62 | The one MCP/codemode entry | in full |
| `FP/evidence/product-t32-rulings.md` | 39 | Desk T-32 second-seat rulings | in full |
| `FP/evidence/history-claims.md`, `history-recent-claims.md`, `history-october-cohort-claims.md`, `history-breadth-claims.md`, `history-september-early-cohort-claims.md` | — | Exact Tom quotes with JSONL pointers | grepped, shell-relevant entries |
| `FP/research_notes/Convergent product and compute plan/product.md` | 172 | Product baseline; platform table; 12 acceptance scenarios | lines 1–30, 54–172 |

The friday package cites the ultrabuild planning files below as the concrete shell boundary. They are the most specific Sway-shell inventories in this lineage, so I read them as well:

| File | What it adds | Read |
|---|---|---|
| `UB/inputs/SEPARATION.md` (138 lines; last commit 9154ddd, 2026-10-15 00:48 +0200) | The binding A/B/C split. **A** = Tom's Sway-only shell (not ported). **B** = desktop apps (ported to Mac). **C** = Cloudflare deployments. Also the 15-item "Never on the Mac" list | in full |
| `UB/inputs/plans/agency-launch/additional/SWAY-ONLY.md` (301 lines, 2026-10-14 night) | The S1–S15 catalogue of everything the Sway seat does, with keys, state and file paths, and contracts C1–C6 | in full |
| `UB/inputs/plans/agency-launch/additional/LAYERS.md` (513 lines) | Seven tiers, the platform contract (TypeScript sketch), capability table, rules R1–R9 | §0, §1, §6 |

### 1.2 Three framing facts for the synthesizer

1. **"ADAPTER" in PACKETS.md is not a desktop adapter.** It means a *compute execution route*: OpenCode free GLM/DeepSeek, DSH, Console SDK, cloud or Batch (`FP/PACKETS.md:60-68`). Its only bearing on the shell is the optional `gpuix-shell ask` (OpenUI plus the local model): be honest about the route, never fall back silently, and do not hang the build on a model download. The *platform* adapter material lives elsewhere:
   - BOUNDARIES row "Shell composition" (`FP/BOUNDARIES.md:13`);
   - the source review row "Desktop/window/input adapter" (`FP/reviews/personal-shared-boundary-source.md:59`);
   - extraction cut C "Host lifecycle adapters" (`FP/reviews/shared-library-host-extraction.md:119`);
   - `UB/.../LAYERS.md` §6.3 "The platform contract".
2. **Most of the friday package is not about the shell.** It covers four strands: the first macOS owner, Projects/Substrate integrity, compute expiry, and Tom's personal shell. Only the PERSONAL-SHELL packet (`FP/PACKETS.md:70-78`) and claims C3.4/C3.5 (`FP/SPEC.md:72-73`) target the shell by name. C2.1–C2.4, C2.9, C3.6 and C4.9 also bind it, because the shell is one of the "human controls".
3. **The mechanism question has since been closed by Tom.** On 10-16 Tom said "swaywm integration is fluid conceptually, i m not fixed to one thing" (relayed at 08:12:28Z, `FP/RUN-LOG.md:8`). The friday package therefore left the compositor mechanism open on purpose: layer-shell beside Sway, in-compositor, or per-app proxy (`FP/reviews/product-boundary-matrix.md:55-63`). On 10-20 Tom ordered "staying on sway window manager (my wm of choice)" (BRIEF §1). Tonight's choice — GPUIx layer-shell surfaces beside Sway, driven by Sway IPC — is integration shape 3, "Personal shell as orchestration surface over reusable apps" (`FP/reviews/product-boundary-matrix.md:59`). The friday matrix credits it with "matches explicit personal/export boundary and protects macOS onboarding simplicity". INFERRED: nothing in the friday package conflicts with that choice.

---

## 2. Verbatim Tom rulings relevant to the desktop shell

Typos are kept. Times are UTC unless noted. The "→" line gives the consequence for gpuix-shell (INFERRED unless it says otherwise). The recipient's name is replaced by "[the first user]", as `UB/inputs/SEPARATION.md` does.

### 2.1 Personal shell versus shared tools (the boundary itself)

**R-B1 — 2026-10-14T16:08:40.602Z**
> "agency-agency is the shared github org. it has separate implementations for pure full desktop like wayland (sway for now) desktop shell and the shared with macos that overlays special features of sway: swap kitty terminla herdr and herdr web ui translated into my own implementation. sway has a contextual launcher, a herdr leftbar that is disjinted and contol sway workspaces, clipboard history.. all that stuff that macos version doesn't have. this creates a clean sepaeation layer which is much appreciated but it sits at the same library fundamentally."
- Source: `/home/tom/.claude/projects/-home-tom-today/56e498e4-f44d-40bd-8caa-6f3f54587411.jsonl:1861`.
- MEASURED: the tail from "herdr leftbar" onward matched in this record. The full text is as `UB/.../SWAY-ONLY.md:16` gives it. Friday ids: H005 / HR024.
- → The shell owns the contextual launcher, the herdr left bar that drives Sway workspaces, clipboard history and the kitty/chat swap. The library underneath (palettes, rail model, attention rule, command ids) should stay shareable.

**R-B2 — 2026-10-14T16:08:40.602Z (attachment in the same record; Tom's notes file)**
> "the bottom macos tab bar: utilities like email etc can go below. herdr tabs on the left with sway and herdr control"
- Source: `56e498e4…jsonl:1862`, an attachment carrying `~/wednesday-oct14-midday.md:325`. MEASURED.
- → Herdr tabs and the rail go on the left. Utilities like email are a separate tray/dock concern. Mail/CRM are not built into the rail.

**R-B3 — 2026-10-14T16:10:24.544Z**
> "without invading into his macos desktop. this is where the diffreece lies. i give him high performance cloduflare deployed webappsthat he can use with codemode from the chat interface as well."
- Source: `56e498e4…jsonl:1878`, a queued record. REPORTED (friday register H006/HR025).
- → Nothing from gpuix-shell travels to a Mac.

**R-B4 — 2026-10-14T14:53:35.287Z**
> "this is us packaging for that withtou the window mgmt functionlity. this is building in unified email crm and other such tools ."
- Source: `/home/tom/.claude-work/projects/-home-tom-today/5024ed4c-ea37-4772-b7ea-f11cbb361dcd.jsonl:216`. MEASURED.
- → Window management is the personal (Linux) side.

**R-B5 — 2026-10-14T20:52:34.257Z**
> "it s important to separate out my swaywm-only deskto shell versus the desktop appoications like email ; herdr web ui chat ; crm and the other ones created. plus the cloudflare-side deployments ofthe agency-agency repos that need manual work and integrations on [the first user]'s account"
- Source: `56e498e4…jsonl:2908`, `queue-operation` enqueue. MEASURED.
- → This is the A/B/C split. gpuix-shell = bucket A.

**R-B6 — 2026-10-14T20:49:31Z (user-role record; the surrounding text contains "..." so it may be a pasted digest)**
> "macos has parity with the "tray/dock" items: crm, email, projects, files, the vesence ones (resurface from investigation); this is what we build as native apps."
- Source: `56e498e4…jsonl:2780`. REPORTED, with the full form in `UB/.../SWAY-ONLY.md:18`.
- → Files is a "tray/dock" app, i.e. shareable in principle. The Pinax-like explorer should keep its model platform-neutral.

**R-B7 — 2026-10-16, mid-run (relayed by the coordinator)**
> "please make sure to kee defining the xact boundary between personal shell versus 'shareable' for macos and others with a unified system"
- Source: `FP/CHARTER.md:31`, `FP/BOUNDARIES.md:3`. REPORTED (relay).
- → The boundary is a deliverable in its own right. Tom repeated it on 10-20 ("should already be clear", BRIEF §1).

### 2.2 Compositor and mechanism

**R-C1 — 2026-10-13T22:25:30.905Z**
> "i digress on the hyprland parts, i m sorry. let s tick to sway window manager. less effort.. 
> but do list all the hyprland functionality that we're "missing out on" in a way so i can decide if i want hat added potentially later or not..."
- Source: Codex `/home/tom/.codex/sessions/2026/10/13/rollout-2026-10-13T22-57-08-01a1370e-…jsonl:1802`. MEASURED (friday HR014).
- → Sway only. The prior `WT/pkgs/desktop-shell` is Hyprland-bound (hyprctl), so its controller is not reusable as-is.

**R-C2 — 2026-10-16T08:12:28Z (relayed)**
> "swaywm integration is fluid conceptually, i m not fixed to one thing"
- Source: `FP/RUN-LOG.md:8`. REPORTED.
- → Superseded in mechanism by 10-20 ("staying on sway window manager (my wm of choice)", BRIEF). It still means: don't hard-code Sway into the shared model layer.

**R-C3 — 2026-10-01T09:29:54Z**
> "anything in views c++ touches the wayland layer-shell; never a fullscreen app."
- Source: `FP/evidence/history-october-cohort-claims.md` HO006. REPORTED. Historical, from the Views era.
- → The same spirit holds now: shell surfaces are layer-shell. The files explorer is the one ordinary window (BRIEF §3.2).

**R-C4 — 2026-10-01T09:00:31Z**
> "scroll wm (based on sway) also has multi-seat; something which i would be more than happy to offer claude (you) a seat to control my desktop (if ever needed); but having this option is nice."
- Source: HO005. REPORTED.
- → Second-seat aspiration (see R-H3).

**R-C5 — 2026-10-13T23:21:38.433Z**
> "performance is not really the thing i m looking for here. "supplies another renderer" is fine for something that' react plus generic compositor functionlaity... vicinae (raycast clone) proves this theoretically ; we hae the sway ipc and omarchy's quickshell which you investigated a while back did exactly that."
- Source: Codex 01a1370e `jsonl:3454`. MEASURED.
- → React on GPUIx plus Sway IPC is exactly the requested shape. Performance is not the gate.

### 2.3 Launcher, bar, notifications, keys

**R-L1 — 2026-10-13T22:16:03.293Z**
> "whatever you just opened: i love it. 
> this is good enough to also become a functional remplacement to waybar, vicinae and mako notifications. drawing insporation from omarchy's implemetnatipn of wayshell in fact."
- Source: Codex 01a1370e `jsonl:1487`. MEASURED.
- → Replace waybar, vicinae and mako with the Claude/Primer look ("the opened file was `design/claude-primer/dist/index.html`", REPORTED `56e498e4…:2877`).

**R-L2 — 2026-10-13T22:16:59.509Z**
> "massive ultracode workflow into the blur implementation (since hyprland has full wayland blur protocol resolved
> we re doing functionality pull from quickshell NOT visuals or aesthetics whatsoever"
- Source: Codex 01a1370e `jsonl:1536`. MEASURED.
- → Pull functionality from quickshell shells, not their visuals. Tom's 10-20 wish to "remain close" to Tacit's vanilla quickshell look is the newer, narrower aesthetic exception; see §2.9.

**R-L3 — 2026-10-12T09:20:26.654Z**
> "we keep vicinae actually.. i was getting a little carried away there when i said let's delete it. it's good fucntionality."
- Source: HO051, `56e498e4`'s sibling `1376398e…jsonl:204`. REPORTED.
- → **Superseded** by R-L1 (10-13) and BRIEF 10-20 ("mod+d menu (vicinae remplacement)"). See §2.9.

**R-L4 — 2026-10-14**
> "for the launcher, feature parity at least with vicinae (already enjoyed on my setup) including how it interacts w google chrome tabs is very desirable"
- Source: `UB/.../SWAY-ONLY.md:113`, citing `CU/BRIEF.md:43`. REPORTED (second-hand).
- → The launcher must search Chrome tabs. Vicinae does this through its browser-extension bridge; `WT/pkgs/desktop-shell/providers.ts` lists it as a gap.

**R-L5 — 2026-10-07**
> "the concept of a spotlight menu sort of thing, along with all of the contextual information that it can hold at any given moment is probably the most underused item on the modern desktop and it should be really strengthened given that we're on swaywm (with its ipc) on linux, and the vicinae product is a great foundation to start"
- Source: `UB/.../SWAY-ONLY.md:113`, citing `CU/longrun/ambient-computer.md:113`. REPORTED (second-hand).
- → The launcher is contextual: it knows the focused workspace/output, the herdr pane and its status, and the Chrome host.

**R-L6 — 2026-10-13**
> "the way we control brightness and volume should be keypress>sway>script execution, no need to tie in vicinae if we don't have to"
- Source: `UB/.../SWAY-ONLY.md:186`, citing `crepuscule-2026-10-14/sessions/dotfiles-rulings.md:56`. REPORTED (second-hand).
- → Keys stay `bindsym` → `volume`/`brightness` script. The script tells the shell to show the OSD. The OSD is display only.

**R-L7 — 2026-10-07T14:00:43Z**
> "i was wrong about mod k , it should remain for  selecting the window "above" the currently focused one, thorugh sway."
- Source: HO019. REPORTED.
- MEASURED that it still holds: `GS/home/dot_config/sway/binds.conf:94` `bindsym $mod+k focus up`.
- → Never bind a shell surface to Mod+K. Use Ctrl+K only *inside* the launcher/app.

**R-L8 — 2026-10-08T13:05:48Z**
> "lots of missing functionality was removed as i've been hopping from wm to wm (until i settled for sway). all the function-row functinality for example is gone. plz bring it back"
- Source: HO026. REPORTED.
- → The function row (F2–F10: theme, media, volume, audio route, monitors, pomodoro) must keep working when the shell is enabled.

**R-L9 — 2026-10-11 and 2026-10-12**
- mako "anchored top-center (Tom, 2026-10-11)"; its "progress bar in Vicinae's blue (Tom, 2026-10-12)".
- Source: `UB/.../SWAY-ONLY.md:151`. REPORTED (paraphrase, no verbatim text).
- → Prior notification placement preference was top-center. BRIEF/SHELLS-DIGEST say toasts top-right, 390 wide. **Conflict to log in ASSUMPTIONS.md.**

**R-L10 — 2026-10-16T07:22:21Z and 07:40:04Z**
> "add CAPS LOCK toggles laptop touchpad; has notify-send when i click it"
> "good job. it worked. clean up worktrees that were done for this etc."
- Source: HR029/HR030. REPORTED.
- → `touchpad-toggle` exists and Tom accepted it. It calls notify-send, so the shell's notification server must render it. Do not reopen it.

### 2.4 Herdr, rail, workspaces

**R-H1 — 2026-10-14T02:40:31Z**
> "one hedr workspace is one sway wm workspace to reduce cognitive load"
- Source: HR022, Codex `01a13843…jsonl:161`. REPORTED. Fuller form (2026-10-14): "in fact i m trying to do one hedr workspace is one sway wm workspace to reduce cognitive load even further" (`UB/.../SWAY-ONLY.md:22`).
- → Rail rows = Sway slots 1–9 = herdr workspaces.

**R-H2 — 2026-10-14T02:41:02Z**
> "herdr "watiing for input" becomes sway workspace wayland urgency"
- Source: HR023. REPORTED. Fuller form: "…and having a deep sense of integation between them. and that way herdr "watiing for input" becomes sway workspace wayland urgency . and we can integarte notify-send just as easily aswell" (`UB/.../SWAY-ONLY.md:23`).
- → The attention rule: `blocked` → Sway urgency plus one actionable notification.

**R-H3 — 2026-10-14**
> "a herdr workspace is ONE kitty terimnal correpondance. this is something i m hapy to enfordce"
- Source: `UB/.../SWAY-ONLY.md:24`, citing TAXONOMY B.9. REPORTED (second-hand).
- → One slot = one kitty projector. The shell never spawns a second terminal per slot.

**R-H4 — 2026-10-14T01:26:30Z**
> "we prefer https://github.com/devswha/herdr-web-ui as the central tool ; and as we blur the line between selection menu ; contextual launcher ; and ai-powered suggestion machine"
- Source: H003, `d34bd9fc…jsonl:5`. REPORTED.
- → Herdr-web-ui is the central reference. The launcher may later grow AI suggestions. OpenUI `ask` is the seed, and it is optional.

**R-H5 — 2026-10-07T11:03:19Z**
> "let's keep herdr on the strix. i withdraw the nas-first requirement in that case."
- Source: HO018. REPORTED.
- → The shell reads a *remote* herdr (`herdr --remote strix`), so every herdr read can be stale or unreachable.

**R-H6 — 2026-10-07T14:12:57Z**
> "so plz restore the herdr in kitty workspaces. i had a few of them opened before you logged me out.."
- Source: HO020. REPORTED.
- → Never disrupt live herdr/kitty sessions, during deploy or tests.

**R-H7 — 2026-10-16T07:25:25Z**
> "we don t have full control over the client"
- Source: H028. REPORTED.
- → Work done locally must still be checked against the real remote herdr session.

### 2.5 Agent seat, HCI parity, keyboard-first

**R-A1 — 2026-10-14T01:08:44.850Z**
> "we can design a linear-style unified shortcut based ui, with mneumonics, in a way that the claude ai can drive at equivalence, sending in instructins that get passed on to a hci implementor"
- Source: Codex 01a1370e `jsonl:4161`. MEASURED (friday H023).
- → One command catalogue, with mnemonics, that both keys and an agent (via the CLI/socket) can drive.

**R-A2 — 2026-10-14T01:47:49Z**
> "...exposing selected functionality tot he user and watching my behavior and selfimproving from there can onyl happen bcz we have a tight grip on the actual keypresses: sway to gpuix shortcuts and fast typing.
>
> the crown jewel is obviously the chat interface, beyond clui-cc and into something that is more comprehensive."
- Source: `FP/evidence/product-t32-rulings.md:9-11`. REPORTED.
- → Sway binds → gpuix-shell CLI is the "tight grip". Chat stays herdr's; the shell launches it.

**R-A3 — 2026-10-14T01:56:12Z / 01:57:31Z**
> "how we can extend that further to sway libseatd seat 1 have that be another colored-cursor that can move around; "clicking" doesn't have to happen from that given we have control over the underlying gpuix component and we're building a shortcut-powered desktop environment that the steering agent doesn't have to eat the surplus in tokens (for tool uses) that this generates as exstra effort"
- Source: H002 and `FP/evidence/product-t32-rulings.md:19`. REPORTED.
- → Second colored seat/cursor is an investigation target only. **Not tonight.** No overlay may be passed off as the seat (`FP/SPEC.md:111`).

**R-A4 — 2026-06-09 and 2026-06-12**
> "Then expand on specifically vimium which i ve used a lot. We ll be making it sort of system-wide" / "i love system-wide vimium concept. do what you can to do it justice"
- Source: H035/H036, `notes/references/devlogs/1h26/CADE/…`. REPORTED.
- → A hint layer is a long-run aspiration (S15). Out of scope tonight, but the command catalogue should not preclude it.

**R-A5 — 2026-06-12**
> "cade must be a compositor/destop environment tool that hapens to have the same powerful protocol like CDP but for system control. let s not conflate the two." / "decouple from kitty-harness, kharness, or any harness. system control protocol is CDP-like. it s a "dumb" surface"
- Source: HB001/HB002, `notes/.../human-annotation-packet.md:172,402`. REPORTED.
- → The shell's socket protocol is a dumb, harness-independent control surface. Never couple it to Claude Code or herdr internals.

### 2.6 Fonts, assets, packaging doctrine

**R-F1 — 2026-09-16T20:49:02Z**
> "i will only be using that font for my personal use and nowhere else"
- Source: HE073. REPORTED.

**R-F2 — 2026-10-01T06:15:03Z**
> "never sharing it w anybody"
- Source: HO002. REPORTED.
- → R-F1 and R-F2 together: Anthropic fonts are never bundled in a package, git, the npm tarball or anything shareable. Load them at runtime from the system font path. Look fence in `UB/inputs/SEPARATION.md:137`.

**R-F3 — 2026-09-10T06:25:20Z**
> "nixos configs for device should NEVER be blocked on model downloading in the first place - this is now doctrine."
- Source: HE031. REPORTED.
- → `gpuix-shell ask` must never make the Nix build or activation depend on a model.

**R-F4 — 2026-09-15**
> "both of those must use the existing dotfiles infra, adding minimal steps on top."
- Source: HE065, about OCR and speak-clipboard. REPORTED.
- → Wrap existing scripts (`screenshot`, `screen-ocr-area`, `speak-clipboard`, `volume`…). Don't reimplement them.

**R-F5 — 2026-10-12T09:20:26Z and 09:36:48Z**
> "re personal utilities being on multiple workers, that is totally fine by me. but i want to be able to have claude interface with them (via mcp) in one place."
> "i want ot have a single mcp codemode for all my cf worker-deployed utilities like email and crm etc, that claude code can interact with from one place. you figure out the rest"
- Source: HO049/HO050. REPORTED.
- → Not the shell's job. The shell's CLI could later be one tool behind that entry.

### 2.7 Utilities that touch the shell

**R-U1 — 2026-10-07T20:35:58Z**
> "chat window > herdr-web as base. i want to have ocal ai speech to text, local ai text ot speech"
- Source: H018. REPORTED.
- → Breadth: calendar, WhatsApp, artifacts/Markdown, routines, OCR and media are candidate utilities, not a first tranche.

**R-U2 — 2026-10-12**
> "i already have navidrome installed and the music.internal url ; but i found the default navidrome to be honestly horrendous"
- Source: HO053. REPORTED.
- → A media/MPRIS widget is welcome. A music library UI is deferred.

**R-U3 — 2026-10-12**
> "i want to have whatsapp access to llm s. this will be done LOCAL only, not claude or other cloud services"
- Source: HO052. REPORTED.
- → Out of scope.

**R-U4 — 2026-10-03**
> "remove everything that has to do with openwakeword (even the code that refers to it, that is turned to "off" by default). i no longer need this."
- Source: HO009. REPORTED.
- → No wake-word toggles in quick settings.

**R-U5 — 2026-10-08T11:23:14Z**
> "the only thing that the pn42 runs is swaywm and google chrome."
- Source: HO025. REPORTED.
- → Clients are thin. The shell must not assume local models or heavy services on the client.

**R-U6 — 2026-10-07T20:35:58Z**
> "i have given up on the chromium fork in any shape, now decided to stick to trusty google chrome."
- Source: HO022. REPORTED.
- → Chrome app windows are the way to launch Mail/CRM web apps.

**R-U7 — 2026-10-01T22:25:59Z**
> "ok the tabs show but they don't change workspaces. fine, that at least got pixels on the screen."
- Source: HO008. REPORTED.
- → A negative control: pixels on screen are not working workspace switching. Smoke tests must assert the Sway effect, not just render.

### 2.8 Other Tom statements that frame the shell (dated, briefer)

- **2026-10-14T01:47:49Z** (T-32): "ultracode workflowsw please more depth … turning backgrounded tool use into visible actions that feel like puppetteeringthe computer live in front of me without adding load to the steering llm" (`FP/evidence/product-t32-rulings.md:15`). REPORTED.
- **2026-10-15** (H029): "So again about offloading complexity from self and onto tech (eg my nix fleet and cloud tools). this is the win with ai ; reducing my cognitive load." (`/home/tom/paris-train-thoughts-oct15.md:25`). REPORTED. → The success metric is lower cognitive load, not a feature count.
- **2026-10-12T18:58:51Z** (H025): "hold on please, what is there to ratify? if i had not caught that before the overnight run, it would have turned up an incomplete work." REPORTED. → No redundant ratification gates tonight.
- **2026-10-01T07:13:22Z** (HO003): "you DO NOT say 'oh this needs the human' and stop other lines of work that could be done proactively in the meantime." REPORTED. → Same spirit as the 10-20 order.

### 2.9 Supersession and conflict ledger for the shell

| Topic | Older | Newer | Current default for gpuix-shell | Label |
|---|---|---|---|---|
| Vicinae | 10-12 "we keep vicinae actually" (HO051). Friday default: "Retain compatibility … a new shell does not automatically require removal" (`FP/CONTRADICTIONS.md:82`) | 10-13 "functional remplacement to waybar, vicinae and mako" (MEASURED). 10-20 "mod+d menu (vicinae remplacement)" (BRIEF) | Replace, behind `programs.gpuixShell.enable`, mutually exclusive with vicinae/mako. Vicinae stays one flag flip away. Clipboard policy and Chrome-tab search must be re-supplied (Vicinae owns both today) | INFERRED from dated rulings |
| Compositor | 10-13 Hyprland tried, then "let s tick to sway" | 10-16 "integration is fluid"; 10-20 "staying on sway window manager (my wm of choice)" | Sway only. Keep the Sway provider behind an interface (LAYERS §6.3), so the "fluid" lesson survives | MEASURED + REPORTED |
| Native shell at all | 10-07 "settling for a unified interface - all through a google chroem browser, no native shell whatsoever" (HO023), self-labelled nonfinal | 10-13/14 GPUIx native direction; 10-20 "gpuix as the frontend all the way" | Native GPUIx | REPORTED |
| Quickshell visuals | 10-13 "functionality pull from quickshell NOT visuals or aesthetics whatsoever" (MEASURED) | 10-20 Tacit quickshell config "this is what i would like to remain close to (of course, different font…)", plus "without using quickshell" | Take functionality from DMS/Noctalia/Omarchy and the *aesthetic* from Tacit only (vanilla, flat). Never the quickshell runtime, and never blur/frost (the 10-13 visuals in question were Hyprland blur) | INFERRED. Synthesizer should note this explicitly |
| Notification anchor | mako top-center (Tom 10-11, REPORTED) | BRIEF/SHELLS-DIGEST toasts top-right, 390 wide, max 4 | Conflict. Record in ASSUMPTIONS. Suggested default: honour Tom's own 10-11 ruling (top-center) unless SHELLS-DIGEST quotes a newer Tom ruling | INFERRED |
| Top bar | old `WT/pkgs/desktop-shell` bar: top layer, 32 px exclusive (`WT/pkgs/desktop-shell/ui.tsx:1286-1293`) | "no top bar on the Linux head" (BRIEF); waybar deleted 2026-09-11 | Left rail only. No top bar | REPORTED (BRIEF) |
| Second agent seat | D-18 overlay recommended (stale display) | 10-14 front-door correction: keep the second Sway seat; overlay = drift (`FP/evidence/product-t32-rulings.md:33`) | Not built tonight. Never label a cursor animation as "the seat" | REPORTED |
| Workspace mapping | Friday: "Do not freeze one-to-one workspace mapping … as an invariant" (`FP/CONTRADICTIONS.md:15`) | BRIEF: "one to one mapping, with a limit of 9 open workspaces at a time" (Tom) | 1:1 with cap 9 as default policy, held in *instance config*, not hard-coded in the rail model | INFERRED |

---

## 3. Boundary matrix, feature inventory, claims, proofs, packets

### 3.1 The boundary principle, verbatim from the sources

- "The proposed boundary is **one set of useful operation, record, project and session meanings, with explicit platform and ownership adaptations**. It is not two products that happen to look alike. Sharing code/contracts does not mean sharing deployments, data, credentials, compute entitlements or personal policy." (`FP/BOUNDARIES.md:5`)
- "The division follows **reusable capability versus owner-specific composition**. It does not follow Linux versus macOS. A reusable Wayland adapter can belong in Agency tooling. Your particular monitor placement, workspace behavior, shortcuts, and fleet services belong in your personal configuration." (`FP/GUIDE.md:66-68`)
- "OS-specific code is not inherently personal." (`FP/reviews/personal-shared-boundary-source.md:64`)
- "**A stays home, B travels by `npx`, C is a manual runbook the first user follows on his own account.**" (`UB/inputs/SEPARATION.md:21`)
- "Where Tom's 'clean separation layer' sits. Between tier 2 and tiers 4a and 4b: the platform package (6.3). Everything a user sees inside an app window is tier 2. Everything that needs a compositor, a Dock, a Keychain or a packaging format is tier 4." (`UB/.../LAYERS.md` §6.1)

### 3.2 Three-way boundary matrix for gpuix-shell (distilled; INFERRED from the cited rows)

Column meanings:
- **Shared core** = platform-neutral TypeScript with no `node:child_process`, `swaymsg`, D-Bus or GPUIx imports. It could later move to `agency-agency/core` unchanged (LAYERS R2).
- **Platform adaptation** = Wayland/Sway/Linux providers. Reusable, *not* personal.
- **Tom's composition** = instance config: outputs, keys, hostnames, slot policy, chosen helpers, fonts.

| Concern | Shared core | Platform adaptation (Sway/Linux) | Tom's personal composition | Not gpuix-shell's | Friday/UB source |
|---|---|---|---|---|---|
| Herdr rail | Rail projection: grouping, status, waiting-on-you, worktree rows; machine-qualified `PaneTarget {machine_id,pane_id}`; event/snapshot ordering (`snapshotRequests`) | Layer-shell rail surface (left; exclusive zone); Sway focus on click; herdr CLI/remote transport | Rail on the top display only; 9-slot cap; slot label grammar `client-slot-N-<6hex>`; ordering | Herdr session/PTY truth and the collector (Herdr owns them) | `FP/BOUNDARIES.md:11`; `FP/evidence/boundary-herdr-rail-cutlines.md:59-71`; LAYERS §6.2 "Left rail" |
| Workspace switcher (Mod+I) | Same rows as the rail | `platform.ts`-style `DesktopCapabilities` (snapshot, focusWorkspace with before/after revalidation) | Output `eDP-1` = "top display" (personal default) | — | `FP/reviews/shared-library-host-extraction.md:73-75`; SWAY-ONLY S4 |
| Launcher (Mod+D) | Command catalogue: stable id, label, mnemonic, params, platform tag, availability reason; ranking/calculator helpers | App discovery (desktop entries / GIO), Chrome-tab bridge, Sway context read | Which scripts/apps are listed; favourites; bindings | Spotlight/Vicinae on Mac | `FP/BOUNDARIES.md:12-13`; SWAY-ONLY C4; LAYERS §6.3 |
| Notifications | Notification store (id, app, summary, body, actions, urgency, hints incl. `value`); DnD state; history | `org.freedesktop.Notifications` D-Bus server; layer-shell toasts; `makoctl`-equivalent CLI | Anchor/position, timeout policy, which apps are muted | Notification Center on Mac | SWAY-ONLY S7; LAYERS §6.3 row "Notifications with actions" |
| Attention rule | Pure rule: only `blocked` asks for a person; dedupe; quiet on reconnect; a visit acknowledges, never answers | Sway urgency hint + one actionable notification | Poll cadence, which workspaces | Answering the prompt (Herdr web/prompt path) | SWAY-ONLY C3 + S2; LAYERS §6.2 "Attention rules" |
| OSD | Value model (kind, value 0–100, muted) | Overlay layer surface | Keys→scripts (R-L6) | — | SWAY-ONLY S7/S12 |
| Clipboard history | Store schema and retention policy (ignore passwords, preserve tagged, eviction threshold) | `wl-paste --watch`, `wl-copy` | Which entries are kept; Mod+V | Mac clipboard | SWAY-ONLY S5; `GS/home/dot_config/sway/binds.conf:114` |
| Theme | Token *roles* (bg, fg, accent, hairline…); palettes as data (noir, claude-dark, claude-light) | `~/.config/theme` symlink watcher | Default noir; Anthropic font *names* | Font files (never shared) | SWAY-ONLY C6; LAYERS R6; SEPARATION "Look fence" |
| Quick settings: wifi/BT/audio/power/brightness | Operation definitions with explicit target and result (connect SSID X → confirmed/failed/unknown) | NetworkManager/BlueZ/UPower/logind D-Bus; `wpctl`; `brightnessctl` | Which toggles; default audio route; device names | — | `FP/SPEC.md:55-58` (C2.1–C2.4); C2.7 uncertain outcome |
| Files explorer | Directory/file/diff model; explicit root; read before write | Ordinary GPUIx window; `xdg-open`/GIO launch; Nautilus fallback | Default roots (Documents, Downloads, repos) | A universal filesystem authority | `FP/reviews/utility-family-boundary-inventory.md:14`; R-B6 (files is a "tray/dock" app) |
| Mail/CRM/Projects/Chat | — | Launch Chrome app windows / herdr-web-ui deep links | Which URLs (personal hostnames) | The apps themselves (bucket B / agency kit) | `UB/inputs/SEPARATION.md:17-19`; BRIEF §3.8 |
| Calendar | — | Launch Notion Calendar / Google Calendar app window | Mod+Shift+Period | Calendar backend (Google, settled) | `FP/reviews/utility-family-boundary-inventory.md:13` |
| OpenUI `ask` | lang-core evaluator → element mapping | Local model client (strix :8731) | Model name, endpoint | The model; MCP entry | `FP/PACKETS.md:60-68` (route honesty); HE031 |
| Credentials | Credential-source *interface* | 0600 token files (Linux) | Token paths | Secret values in git (never) | LAYERS §6.2 "Config and credentials resolver"; `FP/BOUNDARIES.md:19` |
| Packaging | — | `pkgs/gpuix-shell/default.nix`; HM module; systemd user units | Enabled hosts, `sway-physical-session.target` | Mac `.app`/npx kit | `FP/BOUNDARIES.md:20`; SEPARATION A12 |
| Agent entry | CLI verbs as stable operation ids | Unix socket `$XDG_RUNTIME_DIR/gpuix-shell/shell.sock` | — | The single MCP/codemode utility entry (separate work) | `FP/evidence/boundary-agent-entrypoints.md:5-7` |
| Second seat / agent cursor | Actor field on operation receipts | (future) Sway seat; GPUI single-seat TODO | — | Not tonight | `FP/reviews/product-host-and-herdr.md:18` (G04) |
| Capture/OCR/speech/print | — | Wrap existing scripts (`screenshot`, `screen-ocr-area`, `speak-clipboard`, print intake) | Strix host, model, quiet hours | Re-implementations | `FP/reviews/utility-family-boundary-inventory.md:16-21`; HE065 |

**"Never on the Mac" (`UB/inputs/SEPARATION.md:110-128`).** The list is a mirror of what is *personal-shell-only*, so all of it is legitimately in gpuix-shell:
1. Sway IPC
2. rail/left bar outside an app window, and workspace switching
3. launcher replacement / global summon key
4. notification daemon
5. Hyprland material (excluded everywhere now)
6. layer-shell bar
7. system-level Nix
8. login items/daemons/listening sockets
9. 4188 bridge
10. desk fork
11. privacy grants
12. keypress/window capture, clipboard history, stash, hint layer
13. Anthropic font files and Claude-named palettes
14. tailnet membership
15. defaults writes

Item 13 cuts both ways: gpuix-shell may *use* Claude palettes and Anthropic fonts, because it is personal. Anything gpuix-shell factors out as "shared core" must carry neither.

### 3.3 Feature and behaviour inventory

"Keep" means keep as-is and let the shell call it. "Replace" means the shell supersedes it. "New" means it does not exist. "Wrap" means the script stays and the shell adds UI on top. Keys are from SWAY-ONLY (dotfiles `2ac87891`, 2026-10-14) unless they say MEASURED at `GS` tonight.

| # | Feature | What exactly | Where it lives today | Keep / replace / new | Notes |
|---|---|---|---|---|---|
| F1 | Launcher (Mod+D, Mod+Space) | Apps; Chrome tabs via extension; clipboard; files (Documents, Downloads only); Now Playing; Search Tray; desktop entries calling scripts | `GS/home/vicinae.nix`; `GS/home/dot_config/sway/binds.conf:6-7` (MEASURED: `$mod+d`/`$mod+space exec vicinae toggle`) | Replace (gpuix-shell launcher) | Parity bar = Vicinae incl. Chrome tabs (R-L4). Keep the desktop-entry names as command ids: "Herdr workspaces", "New Herdr workspace", "Restore Herdr workspace", "Rename workspace", "Dismiss notification", "Restore notification", "Network settings" (SWAY-ONLY S3) |
| F2 | Contextual launcher | A list that knows Sway workspace/output, herdr pane + `agent_status`, Chrome host, `kb` thread | Designed only: `~/today/2026-10-14-computer-use-study/DESIGN.md` §3 (REPORTED) | New | Context capture must be taken *before* the launcher takes focus (C2.2) |
| F3 | herdr picker (Mod+Ctrl+Space) | herdr workspaces with agent status from a read-only snapshot; focuses only Sway containers | `GS/home/dot_local/bin/herdr-picker` (574 lines, REPORTED) | Wrap, then replace UI | Uses Vicinae dmenu protocol today; the shell renders the same list |
| F4 | Herdr left rail | Persistent left bar: slots 1–9, herdr status glyphs (◉◐●✓○), waiting-on-you, click → Sway workspace | Pieces only: PR #565 switcher, picker, `WT/design/gpuix-comparison/{desktop.tsx,platform.ts}`, `WT/design/claude-rail` mock, `WEB` fork rail (`--siderail-*`, commit `472dc0e`) | New (assemble) | "Nobody has put them together on Sway" (SWAY-ONLY S4). Rail click = one focus request until echo or refusal (views-shell C25.2) |
| F5 | Mod+I top-display switcher | Fuzzel menu on eDP-1, that output's slots with herdr status sampled at open; second Mod+I closes only its own menu; "no Herdr focus verb, ever" | PR #565, `/home/tom/.wt/dotfiles/morning-shell/home/dot_local/bin/sway-workspace-switcher` (MEASURED exists, 12.7 KB); 28 tests | Replace UI (gpuix-shell switcher); port its tests' semantics | Toggle semantics: a second press closes |
| F6 | Kitty ↔ web-UI chat swap (Mod+grave) | Swap kitty projector with a Chrome app window showing the same herdr workspace in Chat view; scratchpad companion | Branch `feat/herdr-sway-context` c1a49b99; `/home/tom/.wt/dotfiles/herdr-sway-context/home/dot_local/bin/herdr-context` (MEASURED exists, 32.8 KB); 69 tests | Keep (script); the shell may surface it as a command | Not merged. Conflicts with PR #565 in `binds.conf`/`flake.nix` (REPORTED) |
| F7 | Attention → urgency + actionable notification | `blocked` only; dedupe; quiet on reconnect; never switches workspace; visit = ack | Same branch, `.../bin/herdr-attention` (MEASURED exists, 20.8 KB, 442 lines REPORTED); unit on `sway-physical-session.target` | Port rule into shell core; the shell's notification server delivers Open action | One rule owner. Don't run both `herdr-attention` and a shell attention loop |
| F8 | Notifications daemon | mako: top-center, Anthropic Sans, overlay, palette from `~/.config/theme/mako.conf`, Vicinae-blue progress, high urgency persists; dismiss/restore via makoctl | `GS/home/vicinae.nix` (services.mako) | Replace (gpuix-shell notifications) | No DnD exists in dotfiles today. Prior GPUIx daemon had DnD (`WT/pkgs/desktop-shell/notifications-daemon.ts`, 79 lines) |
| F9 | Dismiss/restore notification keys | Mod+o dismiss (PR #571, BRIEF); Vicinae entries call `makoctl` | `/home/tom/.wt/dotfiles-sway-mod-o` | Replace target (CLI) | Keep the key semantics |
| F10 | OSD | One replaceable popup for volume/brightness with progress from the `value` hint | `GS/home/dot_local/bin/osd` (added 524c66f7, 2026-10-11, REPORTED) | Replace renderer; keep the scripts calling it | Keys → sway → script (R-L6) |
| F11 | Clipboard history (Mod+V) | Vicinae provider. `monitoring=true`, `ignorePasswords=true`, `preserveTagged=true`, `evictionThreshold`; input helper off (no auto-paste) | `GS/home/vicinae.nix`; `binds.conf:114` (MEASURED) | Replace (gpuix-shell store) | cliphist is installed but has no watcher. "Vicinae owns clipboard history; do not start a second cliphist watcher" (`startup.conf:4`). The new store must not run alongside Vicinae's |
| F12 | Slot lifecycle | Mod+Return focus/create projector; Mod+T first free slot; Mod+W park (Chrome-like close); Mod+Shift+T restore; Mod+Shift+N rename; Mod+Shift+Q close = detach; Mod+Ctrl+Shift+Return agents sidebar | `herdr-picker`, `herdr-chord`, `sway-workspace`, `herdr-projector`, `herdr-sway-projector` | Keep (scripts). The rail/launcher call them | Marks: `herdr-slot-N`, `herdr-label-…`, `herdr-name-<hex>`, `herdr-closed-<n>`. The projector never starts a server |
| F13 | Two-panel seat | eDP-1 top (ws 1–9), eDP-2 bottom (ws 10 = Chrome); kanshi Duo/DuoDocked; lid; dock daemon; Mod+Shift+P both panels off | `binds.conf`, `kanshi/config`, `home.nix` sway-local.conf | Keep | The rail shows only top-display slots. Output hotplug (dock) must recreate surfaces (G09 gap) |
| F14 | Capture | Mod+S screen, Mod+Shift+S area+Satty, Mod+Alt+S window → files to strix; Mod+C colour picker | `screenshot`, `colorpicker` | Keep; launcher commands | Wrap only |
| F15 | Screen OCR (Mod+Ctrl+S) | slurp+grim → ssh → strix model → wl-copy on success only | `screen-ocr-area`, `screen-ocr` | Keep | Stale comment "cliphist keeps the result" (SWAY-ONLY S5) |
| F16 | Speak clipboard (Mod+Ctrl+R) | Text → strix speech queue | `speak-clipboard` | Keep | Receipt = playback process exit, not audibility |
| F17 | Function row | F2/Shift+F2 theme/accent pickers; F3–F5 media; F6–F8 volume + OSD; F9 audio route; Shift+F9 call recording; F10 sleep monitors; Shift+F10 pomodoro | `binds.conf`, `theme`, `theme-prompt`, `media`, `volume`, `audio-route`, `monitors-off`, `pomodoro` | Keep keys. The shell may render the pickers (theme, audio route) as overlays | R-L8: function row must survive |
| F18 | Theme switch | `theme` retargets `~/.config/theme` and reloads every consumer "no rebuild" | `GS/home/dot_local/bin/theme`; `home/themes/*.nix` | Keep; add `gpuix-shell.json` fragment + watcher | Same pointer as kitty/herdr/mako/Vicinae |
| F19 | App chords | Ctrl+N/Ctrl+Shift+N Chrome; Mod+N; Mod+E Nautilus; Mod+Shift+C claude.ai; Mod+Shift+W Gmail; Mod+Shift+Period Notion Calendar; Mod+Shift+Semicolon OBS; Mod+Escape inhibitor toggle; Mod+Shift+M desk (PR #565) | `binds.conf`, `rules.conf` | Keep; also list as launcher commands | Chrome shortcut inhibitor disabled by rule |
| F20 | Quick settings / controls | Wi-Fi, Bluetooth pairing, audio, power, brightness, DnD, theme | Partial scripts: `fzf-nmcli`, `audio-route`, `brightness`, `touchpad-toggle`; prior GPUIx "controls" mode (`WT/pkgs/desktop-shell/ui.tsx`, 560×710) | New (gpuix-shell controls + wifi/bt menus) | Each action needs confirmed/failed/unknown result (C2.7). "Network settings" entry exists in Vicinae today |
| F21 | Power menu | Lock/suspend/logout/reboot/off | (not in friday sources) | New | logind via D-Bus. Never the user manager |
| F22 | Files explorer (Pinax-like) | Browse/preview/open; explicit roots | Nautilus (Mod+E); herdr-web-ui `FilesDialog` + `server/files.ts` (pane-scoped) | New (ordinary window) | Files is a "tray/dock" app (R-B6), so keep its model shareable. Not a filesystem authority |
| F23 | Touchpad toggle | CAPS LOCK → toggle + notify-send | `touchpad-toggle` (accepted 10-16) | Keep | Must render through the shell's notification server |
| F24 | Chrome tab tear-off | Chrome Ctrl+M isolates a tab, tiled by Sway | Not in dotfiles (S15) | Out of scope tonight | Tom 10-14 quote |
| F25 | Stash, quick entry "Ask Claude", hint layer, challenge, keypress capture, floating notes window | Designed only (S15) | `CU/DESIGN.md` §2–3 | Out of scope tonight; keep catalogue open | Keypress capture raises D-15 typed-text policy (unresolved) |
| F26 | Second agent seat / colored cursor | Visible agent seat on Sway | Not built | Out of scope tonight | GPUI single-seat TODO (G04) |
| F27 | Waiting-on-you (two sources) | Herdr rows (select pane; submits nothing) vs Projects rows (link only) | `WEB/src/components/WaitingOnYou/WaitingOnYou.tsx`, `deskCounts.ts` | New (rail section), herdr part only tonight | Unavailable ≠ zero (`FP/evidence/boundary-herdr-rail-cutlines.md:57`) |
| F28 | Calendar | Week grid on fixtures; Google not wired | `WEB/src/desk/calendar/*` | Launch only (Notion Calendar app window) | Google is the settled backend |
| F29 | Media widget | `playerctl` default player; Navidrome | `media`, `navidrome-scan` | New small MPRIS widget (optional) | Explicit player target |
| F30 | OpenUI `ask` | Generative native UI from the local model | `/home/tom/tuesday-oct20/build/shared-parity/` | New, optional, off the critical path | C2.9: the core works without it |

### 3.4 SPEC claims the shell must satisfy, with proof rows

All P-rows below are `pending` in `FP/PROVE.md:10-44` ("Not run; scenario defined below and in PACKETS.md"). The ledger's format is `id | claim | task | form | command | rc | result | evidence | commit | at`. Forms are local, wrangler-dev, live or human. Results are pass, fail, pending or blocked(Hn). Proposal: gpuix-shell tests append rows in this exact format to a `tests/gpuix-shell/PROVE.md`, so the friday ledger can absorb them.

| Claim | Text (verbatim) | gpuix-shell reading (INFERRED) | Test form for tonight |
|---|---|---|---|
| C1.1 (tree, P1.1 pass) | "A native kit command is registered through createCommands → its declaration contains identity, title, optional keys, a local run closure, an optional availability predicate and an optional visibility flag, without declaring a cross-process invocation interface in that declaration." (`FP/SPEC.md:49`) | The kit's command shape is the baseline. The shell's catalogue adds the missing cross-process invocation (CLI verb / socket op) and a structured availability *reason* (the kit hides unavailable commands, `FP/reviews/shared-library-host-extraction.md:49`) | bun: every catalogue entry has id, title, mnemonic, `available()` → `{ok}\|{reason}`, CLI verb |
| C2.1 (P2.1) | "A selected utility operation is exposed through human controls and an authorized agent entry point → equivalent explicit targets, arguments, preconditions, resulting state and failure semantics are observable across those entry points." (`:55`) | Launcher click, Sway key and `gpuix-shell <verb>` over the socket all call one handler with the same target and result type | bun: the same op through key handler, launcher action and CLI parser yields identical request objects |
| C2.2 (P2.2) | "A command palette or hint takes focus after selection → the operation retains the selected object's identity and relevant context revision, or refuses stale context with an explanation." (`:56`) | Launcher/switcher capture focused workspace, output and herdr pane *before* mapping the layer surface. Never retarget to "current focus" after the overlay grabs the keyboard | bun: context captured at open; op runs against it; a stale revision is refused with a message |
| C2.3 (P2.3) | "A caller asks for an operation unavailable on that platform, connection or authority → the response identifies the unavailable capability and its reason without silently switching to sample data or a different operation." (`:57`) | No BT adapter, NetworkManager down, herdr unreachable, no MPRIS player: show an explicit unavailable row with its reason. Never fixture data | bun: provider-down cases render `unavailable(reason)`; no fixtures in production builds |
| C2.4 (P2.4) | "An authorized agent performs an owned-app operation → the connected human interface exposes the latest available target, actor, progress and confirmed, partial or unknown outcome, with stale observations labeled and no extra reasoning-agent calls solely to animate feedback." (`:58`) | CLI calls from an agent carry an `actor` field. The shell shows a toast/rail mark "agent: focused ws 3". Stale herdr snapshot rows get an age label | bun: receipts carry actor; the rail labels snapshot age past a threshold |
| C2.6 (P2.6) | "An operation is already delegated within a current authorization → its caller can complete the bounded operation without a redundant approval step introduced solely by changing UI or harness." (`:60`) | No confirm dialogs for ordinary ops (focus, volume, connect known wifi). Confirm only where the effect is destructive (power off) | review rule |
| C2.7 (P2.7) | "A service commits an effect but its reply is lost → the next reachable UI or agent observation reports an uncertain outcome and a domain-supported reconciliation or safe retry path, or an explicit stop…" (`:61`) | Wi-Fi connect / BT pair timeouts report "unknown, re-check" and re-read the state; no blind retry | bun: timeout → `unknown`, then re-query state |
| C2.9 (P2.9) | "The reasoning agent is unavailable → ordinary navigation, search and directly authorized utility controls remain usable with visible connection status." (`:63`) | The whole shell works with the strix model down; `ask` shows "model unavailable" | bun: the launcher index builds with no network |
| C3.4 (P3.4) | "A personal shell view attaches to or steers Herdr work → pane, terminal, session and ownership remain explicit, and closing the view does not silently terminate unrelated work." (`:72`) | Rail/launcher only *select* and Sway-focus. They never issue a herdr focus/input/takeover. Closing or crashing a surface leaves herdr untouched | bun: no herdr mutating verbs are reachable from rail code; smoke: kill the rail process, herdr snapshot unchanged |
| C3.5 (P3.5) | "A personal host integration candidate is evaluated → isolated evidence covers its chosen surface lifecycle, output/focus targeting, human input coexistence and requested visible agent feedback before deployment claims are made." (`:73`) | Under `runtime-test --render-node`, a headless Sway proves surface map/unmap/re-map, correct output, keyboard interactivity (on-demand vs exclusive) not stealing typing in kitty, and exclusive zone reserved | smoke_*.py per surface (BRIEF §4) |
| C3.6 (P3.6) | "A utility packet is accepted → its capability description distinguishes source presence, fixture behavior and actual owner/live behavior, naming unsupported paths and required permissions per operation." (`:74`) | MORNING.md and each surface README state source-present vs unit-tested vs compositor-smoke vs live-on-Zenbook (none tonight) | doc rule |
| C4.9 (P4.9) | "An immediate human utility action needs no background reasoning or schedule → it can complete through its authorized operation path without becoming a scheduled agent job." (`:86`) | No Substrate/Projects involvement in shell ops. No cron/timers in dotfiles (BRIEF) | review rule |
| C5.3–C5.5 | Optional context/learning claims (`:94-96`) | Clipboard history and any future keypress log are *local* and *not* a learning platform. D-15 (typed-text retention) is unresolved | out of scope; don't log keystrokes |
| C6.3 (P6.3) | "A route is exhausted, rejected or retired → work stops, queues or uses an already authorized compatible alternative, without silently changing paid status, data policy or model identity." (`:102`) | `ask` uses only the local strix model. No silent fallback to a cloud API | bun: `ask` errors visibly when the endpoint is down |

PROVE family evidence for C3 (`FP/PROVE.md:53`):
> "Real owner install/connect/use/remove on the selected Mac; explicit workspace isolation and client/executor scope; separate isolated Linux surface/focus/seat/Herdr lifecycle evidence."

The last clause is the gpuix-shell part.

### 3.5 Packet acceptance criteria, rewritten as builder checklists

#### 3.5.1 PERSONAL-SHELL (`FP/PACKETS.md:70-78`), verbatim

> "**Outcome and outputs.** Compare a bounded personal integration around a useful Herdr/utility task, retaining the requested visible second agent seat/cursor outcome and human input coexistence. Deliver capability evidence for layer-shell presentation, target focus, output geometry, contextual commands and session ownership, with an explicit account of which mechanism supplies each capability."
>
> "**Acceptance.** An isolated target demonstrates stable object/surface identity across focus changes, capture/input coordinate agreement, explicit unavailable states, correct Herdr attachment/steering target, and continued unrelated human activity. A dispatched click or moving cursor is not a completion receipt. Prove selected GPUIx/window/seat lifecycle rather than inferring it from toolkit support. If embedding a utility panel, explicitly own UI context, listeners, followers and timers through mount/unmount/reopen; current process-exit cleanup is not automatically reusable panel disposal. If using separate ordinary windows, do not add embedding work as a prerequisite. Third-party app fallbacks have separate fresh-target and result checks."
>
> "**Stop and export.** Stop on a coherent capability result or reproducible incompatibility; export exact source pin, environment, observations and unknowns. Do not restart Herdr or the whole user manager to repair tests. Claims: C2.2–C2.4, C3.4–C3.5."

Builder checklist (INFERRED):
- [ ] A **capability table** in docs (`docs/gpuix-shell/CAPABILITIES.md`): one row per capability (layer-shell presentation, keyboard focus, output geometry, Sway focus, herdr read, notifications server, clipboard, OSD…). Columns: mechanism, file, test, status (source / unit / smoke / live).
- [ ] **Stable surface identity**: each surface has a fixed `namespace` (`gpuix-shell-rail`, `-launcher`…) and one process (singleton socket). A second launch toggles rather than duplicating (prior art: `WT/pkgs/desktop-shell/singleton.ts`, 73 lines).
- [ ] **Explicit unavailable states** in every surface (C2.3).
- [ ] **Correct herdr target**: rail rows are keyed `(machine_id, workspace_id)`, never bare pane id. A click Sway-focuses the slot; it does not issue a herdr focus verb.
- [ ] **Human input coexistence**: the rail uses `keyboardInteractivity:on-demand` (or none) so kitty keeps typing. Launcher/switcher use `exclusive` only while open, then release.
- [ ] **No completion claimed from dispatch**: after `swaymsg workspace N`, verify via a get_workspaces/event echo (`platform.ts` revalidate-before / verify-after; views-shell C25.2 "one FocusWorkspace request until the echo or a refusal").
- [ ] **One process per surface family** (BRIEF §3.2). This sidesteps the embedded-panel disposal requirement, but timers/followers/D-Bus handles still get explicit cleanup on SIGTERM so systemd restarts stay clean.
- [ ] **Second seat**: record it as not attempted, with the reason "GPUI one wl_seat TODO (G04); out of tonight's scope". Do not ship a cursor overlay labelled as a seat.
- [ ] **Stop/export**: each smoke test writes the GPUIx version, compositor version, runtime-test version and observations into its log. Never restart herdr or the user manager.

#### 3.5.2 Herdr rail lifecycle cases (`FP/evidence/boundary-herdr-rail-cutlines.md:73-84`), adapted for the GPUIx rail

Verbatim cases with the shell reading (INFERRED):
1. "Two machines reuse a pane ID; selection, rename and prompt actions remain machine-qualified." → Key rows by machine + workspace id. Tonight there is one machine (`strix`), but the key type is still qualified.
2. "Snapshot fetched before an event arrives cannot undo newer event state." → The poll loop has a generation counter; drop results older than the last applied (pattern: `WEB/src/lib/snapshotRequests.ts`).
3. "A remote bridge is outdated/conflicting/disconnected: existing state and source remain visible as stale/unavailable; actions do not silently target local machine." → Herdr unreachable: rows greyed with "stale Ns" and actions disabled with a reason. Never fall back to a local herdr.
4. "A split or move returns after user selects another target: view ownership follows existing guard semantics." → An async Sway focus result is applied only if the selection is unchanged.
5. "A native window closes: its local subscriptions/views end; Herdr's session/PTY stays owned by Herdr."
6. "Selecting a waiting Projects row does not impersonate a Herdr prompt answer or imply a project decision was submitted." → Projects rows are out of scope tonight. If they are added, they are links only.
7. "A credential/source changes: actual requests, source label and utility link refer to the same intended deployment."
8. "Mac ordinary window uses native window/credential integration; Tom's rail placement and NixOS service policy are not installed as prerequisites." → Shared-core files must not import Sway/HM code.

#### 3.5.3 Shared-library cut acceptance (`FP/reviews/shared-library-host-extraction.md:115-121`)

Applies only if gpuix-shell factors out a core.
- **A.** Selected service reader/action model: "Same invented target/request/result through two callers; stale selection and uncertain outcome remain truthful."
- **B.** Scoped native controls/frame tokens: "One Tab move, disabled action refusal/state, keyboard/accessibility/click agreement, correct theme/scale per mounted instance."
- **C.** Host lifecycle adapters: "Mount/unmount/reopen does not duplicate listeners or retarget pending work; closing presentation preserves Herdr sessions; output disappearance is visible and bounded."

#### 3.5.4 PARITY synthetic cases (`FP/PACKETS.md:35`) that map onto shell ops

> "Synthetic cases cover focus stolen by the palette, changed selection/revision, stale ephemeral hint, permission denial, missing service, delayed asynchronous completion, lost response after commit and duplicate retry. The result must distinguish dispatch acceptance from authoritative completion."

For the shell:
- palette focus steal: launcher open while ws 3 is focused, then run "move to ws 5" → the source is ws 3;
- missing service: NetworkManager or BlueZ absent;
- delayed completion: BT pairing;
- lost response: nmcli/D-Bus timeout;
- duplicate retry: double Enter on "connect".

#### 3.5.5 Shared-control requirement from PARITY dependencies (`FP/PACKETS.md:37`)

> "If controls are shared, include scoped UI state, single-owner Tab/default handling and actual disabled/accessibility behavior at the pinned artifact; matching appearance alone does not establish parity."

#### 3.5.6 ADAPTER (compute route) acceptance (`FP/PACKETS.md:64`), for `gpuix-shell ask` only

> "Pin installed version/profile, exact model/endpoint/auth origin and entitlement… unknown/partial usage, interruption during inference… partial outputs… Never weaken tools or spoof a client to obtain free-route admission."

For `ask`:
- pin the endpoint `http://127.0.0.1:8731` (strix) and model id `halogen-qwen3.8-flash-next` in config;
- surface errors;
- support cancel (Esc) with "stopped, partial output shown";
- no cloud fallback (C6.3).

Gap: GEMS/CONTRADICTIONS say current intent is the **Gufo** model, superseding Halogen (`FP/CONTRADICTIONS.md:11`). BRIEF names Halogen. Make the model id a config value, not a constant.

#### 3.5.7 FIRST-MAC (`FP/PACKETS.md:9-19`)

Not the shell's packet. One cross-cutting rule:
> "Missing connection or permission never appears as sample live data. … Fixture and CI evidence are labeled separately from owner acceptance."

It applies to gpuix-shell tests too: label bun-only tests as such and never call them "works on the Zenbook".

### 3.6 Contradictions and gems relevant to the shell

**From `FP/CONTRADICTIONS.md`:**
- `:15` "Sway — evolving mechanism within current personal outcome … Do not freeze one-to-one workspace mapping or current Sway mechanism as an invariant." → Keep slot policy in config.
- `:45` "Personal second seat versus overlay substitution — mechanism drift … An animated cursor is feedback, not isolated seat proof."
- `:46` "GPUIx ordinary-window-only versus actual layer-shell — source correction … Layer-shell is present in source. Global commands, desktop capture, multi-seat and multi-surface lifecycle remain separate gaps."
- `:82` Vicinae removal retraction (HO051). Superseded since; see §2.9.
- `:86` "Personal-only asset versus shareable app — license/scope distinction | Sep18 personal-only font HE073; Oct personal font constraint HO002 | Do not distribute that asset merely because prototype imports it."
- `:81` "Reactive versus scheduled … Existing clock owns scheduled work; deterministic reactive utilities keep applicable resource/hour policy without becoming agent jobs. Do not delete necessary local service/host integration." → systemd user services for shell daemons are fine. Cron/timers are not (BRIEF).
- `:120` "Shared toolkit versus shared application library … Global UI and process-exit disposal are embedding constraints, not universal current defects."
- `:121` "Toolkit source versus installed keyboard/accessibility behavior | Manual consumer Tab plus inspected host default can double advance; disabled prop mapping incomplete; artifact equivalence unproved."

**From `FP/GEMS.md`:**
- `:20` "The desktop must remain useful without the harness … Human navigation/search/direct operations must work when an agent is absent."
- `:21` "An HCI implementor can perform compact semantic instructions … Do not make the model imitate every physical keystroke." → The CLI verbs are the HCI implementor surface.
- `:22` "System-wide Vimium is a durable experience preference … Mnemonics, contextual palette and ephemeral hints can coexist. A hint is not a durable object identifier."
- `:24` "Cognitive load is the product outcome … Measure context restatement, unnecessary handoffs and manual coordination in a real journey, rather than count features."
- `:36` "An actual small desktop fix was accepted (Oct 16 HR029–030) … do not recreate the task from an older inventory." → touchpad-toggle.
- `:48` "Small deterministic compositions are useful products … Print intake, screenshot/OCR and clipboard/speech can remain direct utilities."
- `:49` "System update should not wait for model payloads (HE031)."
- `:50` "Source sharing is not asset or account sharing … personal fonts, endpoint bindings, data and credentials stay owner-scoped."
- `:55` "HA015/016 preserve focus during updates and background work." → Shell daemons must never steal focus on restart or update. Layer-shell keyboard `none`/`on-demand` for persistent surfaces.

---

## 4. Design values

The friday package is about semantics. It carries almost no visual values. Everything below comes from cited UB/WT sources or MEASURED files.

| Value | Number | Source | Label |
|---|---|---|---|
| Rail width | 220 logical px | `WT/design/claude-rail/PROPORTIONS.md` (from views-shell `SPEC.md:114` C25.1 and `layout_constants.cc`) | MEASURED |
| Rail row | 196 × 30 | same (`layout_constants.cc:38`) | MEASURED |
| Strip inset | 12 horizontal per side, 12 top | same (`layout_constants.cc:42,44`) | MEASURED |
| Row gap | 2 | same | MEASURED |
| Row corner radius | 8 | same (`layout_constants.cc:36`) | MEASURED |
| Row content inset | 8 horizontal / 6 vertical | same | MEASURED |
| Row icon slot | 16 wide; child spacing 4 | same | MEASURED |
| Rail exclusive zone (Views origin) | = rail width (220) | views-shell `SPEC.md:114` | MEASURED |
| Rail colour test | rail column > 99 % `#000000` under all-black theme | views-shell `SPEC.md:116` (C25.3) | MEASURED (a good noir regression check) |
| Rail tokens in web fork | `--siderail-*` | `WEB` commit `472dc0e` | REPORTED |
| Prior GPUIx bar | top layer; anchors top/left/right; exclusive 32; height 32; keyboard none | `WT/pkgs/desktop-shell/ui.tsx:1263-1293` | MEASURED (do not reuse: "no top bar") |
| Prior toasts | width 390; height `count*148-8`; overlay; anchor top; margin [40,0,0,0]; keyboard none | `WT/pkgs/desktop-shell/ui.tsx:1263-1300` | MEASURED |
| Prior notifications panel | 500 × 650, overlay, anchor top/right, margin [40,12,0,0], keyboard exclusive | same | MEASURED |
| Prior controls | 560 × 710, same anchoring | same | MEASURED |
| Prior launcher | 700 × 580, same anchoring | same | MEASURED (BRIEF moves the launcher to top-margin 108, centred) |
| Prior tick | `setInterval(native.tick, 500)`; avoid the stock 8 ms JS tick loop on Linux | `WT/pkgs/desktop-shell/ui.tsx:1331-1338` | MEASURED |
| mako | top-center; Anthropic Sans; overlay layer; progress in Vicinae blue; high urgency persists until dismissed | `UB/.../SWAY-ONLY.md:151` | REPORTED |
| Brightness step | 2 % on Shift | `UB/.../SWAY-ONLY.md:166` (sway-local.conf) | REPORTED |
| Palettes | noir, claude-light, claude-dark (web fork also "System") | `UB/.../SWAY-ONLY.md:188`; `GS/home/themes/*.nix` | REPORTED |
| Fonts | Anthropic Sans / Anthropic Serif / AnthropicMono Nerd Font; personal only; the kit uses `.SystemUIFont`, Georgia, Menlo | `FP/reviews/shared-library-host-extraction.md:101` | REPORTED |
| GPUIx automation initialize | reports fixed 800×600 regardless of real geometry; don't trust it in tests | `FP/reviews/product-host-and-herdr.md:26` (G08) | REPORTED |
| Workspaces | 1–9 on eDP-1 (top); 10 on eDP-2 (bottom) | `UB/.../SWAY-ONLY.md:158,166` | REPORTED |
| Slot label | `client-slot-N-<6 hex>`; marks `herdr-slot-N`, `herdr-label-…`, `herdr-name-<hex>`, `herdr-closed-<n>` | `UB/.../SWAY-ONLY.md:96,158` | REPORTED |
| Herdr deep link | `?machine=<pc>&ws=<id>-<slug>&pane=<pane>&view=chat\|agents\|terminal&…&sidebar=hidden\|shown` | `WEB/src/lib/deepLink.ts:1-30` (via SWAY-ONLY S1) | REPORTED |
| Bindsym count | 108 in this branch (`grep -c '^bindsym'`); 107 on 2026-10-14 | `GS/home/dot_config/sway/binds.conf` | MEASURED |
| Timings | none given. The friday and SWAY-ONLY house rule is "No clock times and no durations". `herdr-attention` uses "a short fixed poll" (value not stated) | — | gap |

---

## 5. Reusable code and data, with exact paths

**Herdr rail model (React/DOM, pure parts reusable)**
- `WEB/src/lib/railGroups.ts` (pure `partitionRail` at lines 16–42; localStorage pref at 45–56 is web-only)
- `WEB/src/lib/status.ts`
- `WEB/src/lib/workspaceRows.ts`
- `WEB/src/lib/snapshotRequests.ts` (read ordering)
- `WEB/src/lib/deepLink.ts`
- `WEB/shared/machines.ts:7-45` (`PaneTarget`, capability flags)

Each has a `*.test.ts` (MEASURED `ls WEB/src/lib`). Source pin in friday: `e85ffd1`; the check is against the current fork head. MIT notice applies to upstream herdr-web-ui code.

**Rail composition reference (not to port as DOM)**
- `WEB/src/components/MachineSidebar.tsx:26-49,78,115-116` (machine-bound `selectPane`, offline inert)
- `WEB/src/components/Sidebar.tsx:167-208,238-285,432-455,620-626`
- `WEB/src/components/WaitingOnYou/WaitingOnYou.tsx`
- `WEB/src/lib/actions.ts` (shared AppActions)
- `WEB/src/lib/shortcuts.ts:8` (Mod+Shift to keep PTY Ctrl free)

**Herdr status authority (do not duplicate)**
- `WEB/server/collector.ts:1-41`
- `WEB/server/input-guard.ts`

**Sway capability adapter**
- `WT/design/gpuix-comparison/platform.ts` (54 lines)
  - `DesktopCapabilities.snapshot()` / `focusWorkspace(selection)`
  - injected runner
  - revalidate-before / verify-after (comment at lines 30–42)
  - default output `eDP-1` at line 44 is personal policy; lift it into config
- `WT/design/gpuix-comparison/platform.test.ts` (26 mocked tests REPORTED)

**Workspace switcher semantics**
- `/home/tom/.wt/dotfiles/morning-shell/home/dot_local/bin/sway-workspace-switcher` and its tests (`tests/workspace-switcher`, 28 tests REPORTED)

**Attention rule and swap**
- `/home/tom/.wt/dotfiles/herdr-sway-context/home/dot_local/bin/herdr-attention`
- `/home/tom/.wt/dotfiles/herdr-sway-context/home/dot_local/bin/herdr-context`
- `/home/tom/.wt/dotfiles/herdr-sway-context/docs/herdr/sway-context.md`
- `…/docs/herdr/sway-context-validation.md` (69 tests under runtime-test REPORTED)

**Prior GPUIx shell (Hyprland-bound; reuse pieces, not the controller)**
- `WT/pkgs/desktop-shell/`, 2887 lines total (MEASURED `wc`):
  - `ui.tsx` 1338
  - `providers.ts` 277 + test 131 (ranking, calculator, provider gaps; note "Chrome tab search still requires Vicinae's browser-extension bridge")
  - `notifications.ts` 83 + test (store)
  - `notifications-daemon.ts` 79 (D-Bus server, DnD)
  - `notifications-client.ts` 43 (returns cleanup fn; not retained by `start()`, per `FP/reviews/shared-library-host-extraction.md:89`)
  - `singleton.ts` 73 (per-mode private socket, toggle by contacting the existing process)
  - `theme.ts` 149 (generated theme JSON / kitty fallback / SIGUSR1)
- `controller.ts` = Hyprland socket + hyprctl → **do not reuse**; replace with a Sway IPC controller.

**Fork lineage proving code already flows shell → shared**
- `WEB` commit `5c9a92a`: palette calculator "lifted from the desktop shell's providers.ts"; bell event feed is "the desktop shell's notifications.ts store cut to a monotonic id" (REPORTED SWAY-ONLY §0 item 6).

**Kit shared core precedent (for factoring)**
- kit `c742887` `out/kit/src/core/{keys.ts,ui.ts,window.ts,frame.tsx,token.ts}`. Snapshots under `FP/evidence/shared-library-source/kit/…`.
- Warnings:
  - `ui.ts` is a module-global singleton;
  - `keys.ts` hides unavailable commands rather than giving a reason;
  - `token.ts` returns a *fixture* token on non-Darwin. Never use it on Linux.

**GPUIx facts to code against** (paths are friday's pinned `6a5c7c1`; re-check at 0.11.0)
- `GPX/packages/native/src/renderer.rs:7299` (layer-shell options), `:7497` (mapping), `:7357` (focus/show ignored on Linux), `:2734` (screenshot unsupported on Linux)
- `GPX/packages/native/js/renderer-state.ts`: default Tab navigation runs *after* the window callback unless `preventDefault()` or `tabNavigation:false`. A boolean return does not cancel it, so the prior `ui.tsx:1303-1308` pattern would double-advance on newer artifacts.
- `GPX/packages/native/src/accessibility.rs`: no `aria-disabled` mapping, so enforce disabled in callbacks.
- `GPX/packages/react/src/reconciler/renderer.ts:386`: one global render slot per process.

**Views-shell rail claims** (behavioural tests to mirror)
- `/home/tom/mecattaf/views-shell/SPEC.md:114-118`, C25.1–C25.5:
  - "A selected tab is one `FocusWorkspace` request until the echo or a refusal, and moves nothing itself" (C25.2). The first cut sent two requests per click and a test caught it.
  - C25.4 failure: a headless seat has no pointer device; a virtual pointer exists only for a command's duration. Click smoke tests on headless Sway need a real pointer.

**Utility scripts the shell wraps** (`GS/home/dot_local/bin/`)
- `herdr-picker`, `herdr-chord`, `herdr-projector`, `sway-workspace`, `osd`, `volume`, `brightness`, `media`, `audio-route`, `screenshot`, `colorpicker`, `theme`, `theme-prompt`, `pomodoro`, `monitors-off`, `claude-capacity`, `fzf-nmcli`, `touchpad-toggle`, `screen-ocr-area`, `speak-clipboard` (BRIEF §2; utility inventory)

**Herdr Files dialog (explorer reference)**
- `FP/evidence/utility-family-source/herdr/src/components/FilesDialog.tsx`
- `…/herdr/server/files.ts` (Git-first inventory, bounded fallback walk)

**Mechanism references, not code to import (licences differ)**
- Otto `src/shell/commands.rs:31`: one handler for keys and D-Bus. Good pattern for "same op via key and CLI".
- CUL `src/server.rs:870`: explicit uncertain outcome / no blind retry for text input.
- Cua native Driver (MIT): target/observation/effect separation.
- Screenpipe: commercial restriction. Do not copy.

**Friday ledger format to adopt**
- `FP/PROVE.md:5,71` (columns and legend).

---

## 6. Gaps and unknowns

**Not verified tonight**
1. I did not re-open the primary JSONL for friday-register quotes marked REPORTED. I did verify R-B1 (tail), R-B2, R-B4, R-B5, R-C1, R-C5, R-L1, R-L2 and R-A1 against primary records.
2. The SWAY-ONLY second-hand quotes have not been traced to primary records: R-L4, R-L5, R-L6, R-H3, the Ctrl+M tear-off, and the mako 10-11/10-12 rulings.

**Pins and drift**
3. Friday's GPUIx facts are at `6a5c7c1` with GPUIx 0.10.0 consumers. Tonight's build pins `@gpuix/react`/`@gpuix/native` 0.11.0, so the Tab-ordering hazard, the single render slot, Linux focus being ignored and missing `aria-disabled` must all be re-checked at 0.11.0.
4. SWAY-ONLY keys were measured at dotfiles `2ac87891` (10-14). This branch is off `dadb1426`. I re-measured only Mod+D/Mod+Space/Mod+K/Mod+V (`binds.conf:6,7,94,114`) and the bindsym count (108). The rest may have drifted.

**Absent from these sources**
5. No timing values: poll cadence, toast timeout, OSD hide delay, animation durations.
6. The friday package has no visual design values beyond rail metrics. Colours, spacing and typography come from other readers (SHELLS-DIGEST, herdr-web-ui DESIGN.md, Tacit).
7. Nothing on lock screen/idle, power menu, wifi/BT UIs, or the files explorer beyond the herdr FilesDialog. These are new design territory.

**Conflicts and stale references**
8. Notification position conflict: mako top-center (Tom, 10-11, REPORTED) vs BRIEF top-right 390 wide. Unresolved; log it in ASSUMPTIONS.md.
9. Local model id: BRIEF says `halogen-qwen3.8-flash-next`; friday says current intent is Gufo (HR001–002, 10-13). Make it config.
10. `herdr-attention` vs shell attention: if both run, the notifications duplicate. Pick one owner: the shell, with the Sway urgency half kept. That branch is unmerged. INFERRED default: port the rule into gpuix-shell core and don't enable `herdr-attention` alongside it.
11. Clipboard: when gpuix-shell replaces Vicinae, Chrome-tab search and Vicinae's clipboard history (with its retention) are lost unless re-supplied. Vicinae's browser-extension bridge has no GPUIx equivalent yet. **Launcher parity with Vicinae for Chrome tabs (R-L4) is the largest functional gap.**

**Known source gaps**
12. GPUIx gaps from friday (static, `FP/reviews/product-host-and-herdr.md` G03–G10):
    - no global shortcuts (use Sway binds → CLI);
    - one `wl_seat` (TODO multiseat);
    - no Linux screenshot (use `grim` in smoke tests);
    - no window/surface registry in JS (one process per surface);
    - no explicit output selection in the options read (rail placement on eDP-1 needs an output option; check 0.11.0 `layerShell` for an `output` field).
    Toasts closed and reopened on count change because no dynamic resize/input-region setter was available (`FP/reviews/shared-library-host-extraction.md:85`).
13. Output hotplug (Zenbook dock turns eDP-2 off): no proof anywhere. Smoke should cover unplug/replug if runtime-test's headless Sway supports `output … disable`.

**Out of scope tonight (keep the design open)**
14. Typed-text and keypress capture policy D-15 is unresolved (`FP/DECISIONS.md:7`, `FP/SPEC.md:107` Q1). Clipboard history is already accepted under Vicinae, so the same scope is reasonable. Keypress logging is not.
15. Second seat, hint layer, stash, quick entry and Ctrl+M tear-off are designed/aspirational only.
16. The single MCP/codemode utility entry is not built anywhere. The shell's CLI could become one adapter later.

---

## 7. BOUNDARY-ready rules for the synthesizer (INFERRED; ready to adapt into `docs/gpuix-shell/BOUNDARY.md`)

Each rule cites the source that motivates it.

1. **Bucket.** gpuix-shell is bucket A, "Tom's Sway-only desktop shell". It lives in `mecattaf/dotfiles` (private). Nothing in it is shipped to a Mac or to `@agency-agency/kit` (`UB/inputs/SEPARATION.md:17,44`; R-B5).
2. **Three layers inside the package.**
   - `src/core/`: platform-neutral models, command catalogue, attention rule, rail projection, notification store, theme token roles. No `node:child_process`, D-Bus, `swaymsg`, GPUIx or filesystem imports (LAYERS R2).
   - `src/platform/sway/` (and `linux/` for D-Bus/PipeWire): reusable Wayland providers, not personal (`FP/GUIDE.md:68`).
   - `src/surfaces/`: GPUIx React views.
   - Tom's policy lives in config: outputs, slot cap, bindings, hostnames, model endpoint, fonts.
   - An import-fence test enforces the direction (LAYERS R1/R2; SEPARATION §6.1).
3. **Herdr is read-only truth.** The shell reads snapshots/events and acts only through Sway. It never focuses herdr, sends input, takes over attachments or answers prompts. Closing a surface never ends herdr work (C3.4; LAYERS R8; "no Herdr focus verb, ever", PR #565).
4. **Selection ≠ focus ≠ input ≠ completion.** Each is a distinct operation with a distinct receipt (`FP/evidence/boundary-herdr-rail-cutlines.md:36-44`; `FP/GUIDE.md:101`).
5. **Capabilities are declared, then probed. Unavailable is visible, with a reason.** No sample/fixture data in production surfaces (C2.3; LAYERS R3).
6. **One operation, many callers.** Sway key, launcher row, rail click and `gpuix-shell <verb>` (agent or human) resolve to the same handler. Requests carry target and actor. Results are `confirmed | failed(reason) | unknown` (C2.1, C2.4, C2.7; R-A1).
7. **Context before focus.** Overlays capture their target context before taking the keyboard and refuse stale context (C2.2).
8. **The shell works without any model.** `ask` is optional and off the critical path. Its route is pinned and never falls back to the cloud. The Nix build never waits on a model (C2.9, C6.3, HE031).
9. **Keys stay in Sway.** `bindsym` → script/CLI. GPUIx has no global shortcuts. Mod+K stays `focus up`. The function row keeps working (G03; R-L6; R-L7; R-L8).
10. **Personal assets stay personal.** Anthropic fonts are loaded from the system at runtime (0.11.0 `registerFont(bytes)` from the font path), never committed or bundled. Claude-named palettes are allowed here, but not in anything factored as shareable (HE073/HO002; SEPARATION "Look fence").
11. **Not in this package.** Mail/CRM/Projects/Chat UIs, the calendar backend and the utility MCP entry. The shell launches Chrome app windows and herdr-web-ui deep links only (`UB/inputs/SEPARATION.md:18-19`; BRIEF §3.8).
12. **Wrap, don't rewrite, existing utilities** (screenshot, OCR, speak, print, theme, volume, brightness, audio-route) (HE065; GEMS :48).
13. **Live-session safety.** All compositor tests run under `runtime-test --render-node`. Never restart herdr, the user manager or the live Sway. Systemd user units are bound to `sway-physical-session.target`. No cron/timers (PERSONAL-SHELL stop rule; `FP/SPEC.md:124`; BRIEF).
14. **Evidence tiers in every claim.** Each surface's status names exactly one of: source present / bun unit pass / compositor smoke pass under runtime-test / live on Zenbook (none tonight). A dispatched click or a rendered pixel is not a pass (C3.6; HO008; PERSONAL-SHELL "A dispatched click … is not a completion receipt").
15. **Not shipped, kept on record.** These stay recorded as aspirations, not shipped, and nothing substitutes for them: the second seat (R-A3), the system-wide hint layer (R-A4), keypress capture (D-15) and the attention rule's macOS twin (`FP/SPEC.md:111`; `FP/evidence/product-t32-rulings.md:33`).

---

*End of reader 12. Light pass, per the workflow rules: no independent verifier ran on this note. Quotes marked REPORTED were not re-opened at their primary JSONL lines. Section 6 lists every known unverified item.*
