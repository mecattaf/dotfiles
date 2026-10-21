# 16 — herdr as the shell's data source: API, snapshot shape, slot identity, events, notifications, scripts

Reader note for the overnight gpuix-shell build (2026-10-20/21). Written from the strix (the herdr
server host; `SWAYSOCK` is empty here, so nothing about the live Zenbook Sway tree was measured —
those parts are REPORTED from scripts, docs and fixtures). Every command below was run read-only;
no herdr mutation, no Sway command, no unit touched. Labels: MEASURED = run tonight; REPORTED =
read in a doc, comment or transcript; INFERRED = my reading, say so before building on it.

Pointers use `file:line`. Main checkout is `/home/tom/mecattaf/dotfiles` (read-only for us); the
two unmerged branches are `/home/tom/.wt/dotfiles/herdr-sway-context` (c1a49b99) and
`/home/tom/.wt/dotfiles/morning-shell` (PR #565). herdr source clone (143bf5fd, 2026-10-16) is at
`/home/tom/Downloads/herdr`; the installed binary is 0.9.3.

---

## 1. What this source is

herdr is the terminal workspace manager that holds every PTY and every coding agent Tom runs.
One server, on the strix only (`home/herdr.nix:15-24`, ruling B5), as a systemd user unit that
deliberately survives the compositor (`home/herdr.nix:26-33`, ruling B6; `X-SwitchMethod =
"keep-old"` so a Nix switch never restarts it, `home/herdr.nix:104-116`). Every other host runs
the client only and reaches the server as a "projector": `herdr --remote strix` inside a kitty
window of class `herdr-projector` (`home/dot_local/bin/herdr-projector`).

For the shell, herdr is **the** source of truth for "what work is open and which agent needs me":

- `herdr status` (MEASURED): client 0.9.3, server 0.9.3 running, protocol 22, endpoint generation 1,
  socket `/home/tom/.config/herdr/herdr.sock`, restart not needed.
- `herdr api schema` (MEASURED): protocol 22, schema_version 1, five schemas (`request`, `success_response`,
  `error_response`, `event`, `subscription_event`), **102 request methods**; full JSON dumped to
  `/tmp/claude-1000/-home-tom-tuesday-oct20/94d008d7-4112-4bf7-92cd-2de4eab69681/scratchpad/herdr-schema.json`
  (272,578 bytes). Regenerate any time with `herdr api schema --json` or `--output PATH`.
- Live estate tonight (MEASURED 2026-10-20 ~23:00 CEST): 24 workspaces, 24 panes (one pane each,
  `hide_tab_bar_when_single_tab = true`), 18 agents (15 claude, 3 codex), 4 panes with no agent
  (nvim) reporting `agent_status: "unknown"`; focused workspace `wHW` (this session, status `working`).
- Three doors into it (REPORTED `tuesday-oct20/MAP.md` §5): the CLI (`herdr <group> <verb>`, JSON on
  stdout), the socket (NDJSON over `herdr.sock`), plugins (`herdr-plugin.toml`; none installed
  tonight, `herdr plugin list` → "No plugins installed." MEASURED). The shell should use the first two.

The desktop glue that exists today is all scripts in `home/dot_local/bin/` plus two branches; the
shell replaces the Vicinae/fuzzel/mako front ends of those scripts and keeps their rules.

---

## 2. Verbatim Tom rulings relevant to the desktop shell (dated)

Quotes are verbatim including typos. Source in brackets.

- 2026-09-11 — "i really do not like Tabs" [config.toml:103 comment; echoed in Codex rollout
  2026-10-07T11:19Z]. Consequence: `hide_tab_bar_when_single_tab = true`; the shell draws no
  herdr tab strip and treats one workspace = one pane as the normal shape.
- 2026-10-07T11:14:18Z — "we follow a "one herdr per sway workspace" rule: google chrome gets mod 0;
  but otherwie mod 1 through 9 are for dedicated workspaces (works like the google chrome tabs
  really, except that i dnt need to see a bespoke "tab strip". sway workspace renaming retc should
  all work, we have the sway ipc that's well st[...]" [Codex rollout
  `~/.codex/sessions/2026/10/07/rollout-2026-10-07T13-06-33-01a1160b-...jsonl` line 320].
- 2026-10-13 — "one sway-wired workspace switcher that can be toggled with mod i ; with
  herdr-provided status indicators. only for the top display" [REPORTED SHELLS-DIGEST.md:80, dig/05 s1].
- 2026-10-14T02:40:31Z — "in fact i m trying to do one hedr workspace is one sway wm workspace to
  reduce cognitive load even further" [Codex rollout 01a13843 line 161].
- 2026-10-14 00:16 CEST — "whatever you just opened: i love it. this is good enough to also become
  a functional remplacement to waybar, vicinae and mako notifications." [REPORTED MAP.md §5].
- 2026-10-14 01:26 CEST (2026-10-16T08:02:57Z re-quoted) — "herdr stays central; with even more
  synergy with the sway workspaces now" [Codex rollout 01a143b6, event_msg].
- 2026-10-17T01:09Z — "for SURE herdr is mainstay in my setup and it s really the centerpiece of
  dotfiles" [SHELLS-DIGEST.md:5; `.claude/projects/.../63d3cbe3-...jsonl` 2026-10-17T03:12:47Z].
- 2026-10-17 — "on the sway devices, the left bar of the ai chat is a waybar style workspace (1>9)
  launcher" [REPORTED SHELLS-DIGEST.md:91, from frontends/claude-desktop-decomposition.md s1].
- 2026-10-20T10:53:53Z — "i typically hae a one ot one mapping, with a limit of 9 open workspaces
  at a time; this helps with my mental overload" [REPORTED MAP.md §5 "Sway slots"].
- 2026-10-20T11:03:02Z — "in the meantime of course, hertdr and dotfiles improvements will be
  impolemented. for starters i have TONS of herdr workspaces that qre inactive and that we can
  kill. you identified the 9 important one." [`~/.claude/projects/-home-tom-mecattaf-dotfiles/1a517fb2-...jsonl`].
  (235 → 15 workspaces were closed after that order, REPORTED MAP.md §5; 24 tonight, MEASURED.)
- 2026-10-20 ~22:50 CEST — "there is a lot of herdr-web-ui centricity here especially on the left
  sidebar idea ; but having a comprehensive list of all the options is important." [BRIEF.md:16].
- 2026-10-20 ~22:50 CEST — "the crux of it is that we write scripts and functionality that is
  either a bespoke swaywm shortcut ; or a mod+d menu (vicinae remplacement) that presents a given
  functionality. notify-send remplacement to mako ; a left bar with workspace switcher that
  remplaces waybar" [BRIEF.md:13-15].

Standing design constraints derived from the scripts (REPORTED, each is a code comment or docstring):

- "Herdr APIs are read-only; focus stays in Sway." / "Never infer current identity from the
  server's global focus." [`home/dot_local/bin/herdr-picker:2-6`]. herdr focus is server-global
  (REPORTED MAP.md §5 "Today's projector incident", #512): a `workspace.focus` from the shell
  would move **every** attached projector. The shell must not call `herdr workspace focus` /
  `herdr agent focus` for navigation.
- "The pinned Herdr API's explicit `blocked` state is the only attention trigger; `idle` and `done`
  are deliberately not treated as unanswered questions." [`herdr-sway-context/home/dot_local/bin/herdr-attention:7-8`].
- "A Sway slot owns one projector, including while parked." [`herdr-picker:4`]; "When all nine
  slots are occupied or parked, creation stops with an explanation; it never silently allocates
  workspace 11." [`docs/client-sway-vicinae.md`, Keys section].
- "Unknown and unavailable states never become idle" [`morning-shell/tests/workspace-switcher/README.md:20`].

---

## 3. Feature / behaviour inventory

| feature | what exactly | where it lives today | keep / replace / new | notes |
|---|---|---|---|---|
| Read the live estate | `herdr api snapshot` → `session.snapshot` JSON (shape in §5.1) | CLI; `herdr-picker:163-183 remote_snapshot()` | keep (data), replace (consumer) | ~5 ms locally on strix (MEASURED `time herdr api snapshot` real 0.005 s); from the Zenbook it is one ssh round trip (picker uses `ssh -n -o BatchMode=yes -o ConnectTimeout=3 … strix 'herdr api snapshot'`, 6 s timeout) |
| Workspace list / agent list | `herdr workspace list`, `herdr agent list` (same records as snapshot, narrower) | CLI | keep | `workspace list` carries `label`, `number`, `agent_status` roll-up, `pane_count`; `agent list` carries `completion_seq`, `state_change_seq` |
| Event stream | `events.subscribe` over the socket, NDJSON, long-lived | socket only (no CLI wrapper); used by herdr-web-ui and herdr-bar | NEW for the shell | §5.3. Lifecycle events need no params; `pane.agent_status_changed` needs a `pane_id` per entry (MEASURED error otherwise) |
| Sway slot ↔ herdr workspace identity | label `client-slot-N-xxxxxx` + Sway marks `herdr-slot-N`, `herdr-label-…`, `herdr-workspace-w…`, `herdr-closed-<ns>`, `herdr-name-<hex>` on the kitty window | `herdr-picker:24-29` regexes; `slot_of:75-80`, `identity:186-193`, `assigned_identity:196-201` | keep rules, reimplement in TS | §5.2. The herdr `number` field is **not** the slot |
| Mod+Return: open/reuse the slot's projector | `herdr-chord new` → `herdr-picker --chord new` → `ensure_projector(create_workspace=True)` | `herdr-chord:1-24`, `herdr-picker:338-399` | keep (script), shell may call it | spawns `kitty --class herdr-projector -e ~/.local/bin/herdr-sway-projector`, waits for the window, marks it, waits for `endpoint handshake succeeded` in `~/.config/herdr/herdr-client.log`, types the label into herdr's `new workspace` form via `kitten @` |
| Mod+Ctrl+Shift+Return: projector with herdr's navigator | `herdr-chord sidebar` → ensure_projector(create_workspace=False) then chord `ctrl+b g` | `herdr-picker:511-518` | keep | |
| Mod+t / Mod+w / Mod+Shift+t / Mod+Shift+n | `sway-workspace new|close|restore|rename` → `herdr-picker --workspace …` | `sway-workspace:1-8`, `herdr-picker:419-463` | keep rules; shell issues the same `swaymsg` commands or execs the script | close = park (§5.2); restore = newest `herdr-closed-*` mark |
| Mod+Ctrl+Space picker | Vicinae dmenu over `picker_rows()`: projector rows (`Focus/Reopen <ws> · [assigned ]<status> · <label> · view <id>`), other windows, agents, actions | `herdr-picker:211-268 vicinae_menu/dmenu`, `466-498 picker_rows`, `520-562 main` | replace the Vicinae menu with a GPUIX overlay; keep `--json` output as the contract | `herdr-picker --json` prints `[{label, action:[kind, value]}]` read-only, no GUI (MEASURED help text) |
| Mod+i top-display switcher (PR #565) | fuzzel on eDP-1: rows = slots 1..9 ∪ live eDP-1 workspaces − other-output/ambiguous; herdr status sampled once at open | `morning-shell/home/dot_local/bin/sway-workspace-switcher:38-78 make_rows`, `81-103 activate`, `106-137 fuzzel_command` | replace fuzzel with `gpuix-shell switcher`; keep row logic and `--json` | `--json` → `{output, status_at_open, herdr_unavailable, workspaces:[{slot,name,output,label,parked?}]}`; toggle via `$XDG_RUNTIME_DIR/sway-workspace-switcher/<sha256(SWAYSOCK)[:16]>.sock` |
| Blocked-agent attention (c1a49b99) | 3 s poll of `herdr-context status --json`; new `blocked` episode → Sway `urgent enable` on the slot's visible window + `notify-send` with an `Open` action | `herdr-sway-context/home/dot_local/bin/herdr-attention` (442 lines), unit in `home/herdr-context.nix:33-58` | replace notify-send/mako with the shell's own notification daemon; keep episode logic (`Attention` class is pure, lines 44-115) | state file `~/.local/state/herdr-context/attention.json`; lock `$XDG_RUNTIME_DIR/herdr-attention.lock` |
| Mod+grave Kitty/Chat swap (c1a49b99) | same tile swaps kitty projector ↔ Chrome app window of the 8443 web UI, companion parked in scratchpad | `herdr-context` (657 lines), marks `herdr-context-<wid>-(terminal|chat)` | keep as script; shell only needs to tolerate the marks | needs `window_title = "{hostname}: {workspace}"` + `herdr server reload-config` on the strix (REPORTED docs/herdr/sway-context.md:80-84); not deployed |
| herdr toasts | `herdr notification show TITLE [--body] [--position] [--sound none|done|request]` → `notification.show` | CLI + API; delivery per `[ui.toast] delivery` | NEW consumer: the shell's `org.freedesktop.Notifications` server receives them when delivery is `terminal` (kitty OSC 99) or `system` | main config has **no** `[ui.toast]` → herdr default `off` → `reason: "disabled"` (INFERRED from `herdr --default-config` line 305 and `src/app/api.rs:1287`) |
| Idle-shell pruning | close workspaces whose every pane is `unknown` with the shell itself in the foreground | `herdr-prune-shells:1-44` | keep (strix-side admin) | the only script that mutates herdr (`herdr workspace close`) |
| Pane inventory with last activity | `herdr-panes [list [--json]] | close <pane_id>`; last activity = mtime of newest harness session file for the pane's cwd (herdr has no timestamps) | `herdr-panes:23-35, 52-77` | keep; the shell can reuse the mtime trick for a "last active" column | runs only where the server is |
| Projector window itself | kitty class `herdr-projector`, `herdr --remote strix --remote-keybindings server`, reconnect backoff 1/2/5/10/30 s, unit preflight over ssh | `herdr-projector:168-213`, `herdr-sway-projector:1-18` | keep | after a reattach the window "lands on the server's default target, not necessarily the workspace it was showing" (`herdr-projector:35-36`) → identity must be re-resolved, never cached |
| herdr theme follow | `[theme] name = "terminal"`: herdr paints with kitty's ANSI palette; DEC 2031 re-query on theme switch | `config.toml:28-40` | keep | the shell's `theme` switch already repaints herdr through kitty |
| Agent icons / quick switcher inspiration | herdr-bar: `◉` needs you, `◐` working, `●` done, `✓` idle; blocked & finished float to top; running time per row | `/home/tom/Downloads/herdr-bar/README.md:30-45` | mine for the launcher's "agents" section | Rust plugin, Cmd+K inside herdr; not installed |
| Web twin | herdr-web-ui fork: `GET /api/session` → `{snapshot}`, `/ws`, SSE `/api/machines/events`; rail 220/30/12/2/8 | `/home/tom/mecattaf/herdr-web-ui/shared/protocol.ts`, `server/herdr/client.ts:702-800` | reference | same `SessionSnapshot` type, generated from the same schema (`shared/herdr-api.generated.ts`) |

---

## 4. Design values found in this source

Sizes, colours, timings that the herdr-facing surfaces already use. Fonts and palette tokens for
the shell come from the theme fragment (other notes); these are the herdr-specific ones.

**Run-state vocabulary** (REPORTED SHELLS-DIGEST.md:76, binding per P-12): five `AgentStatus`
values → glyph · word · colour: blocked `◉` "Needs input" (orange), working `◐` "Working" (blue),
done `●` "New activity" (green), idle `✓` "Ready" (no mark), unknown `○` "Unknown" (never idle).
Roll-up order blocked > done > working > ready (herdr-web-ui `src/lib/status.ts:37` adds `waiting`
between working and idle; that state is derived server-side in the web UI, not a herdr value).
herdr's own TUI uses (MEASURED `src/client/shell.rs:180-198`): dots style `●` for working/blocked/done,
`○` idle, `·` unknown; symbols style `×` blocked, `◐` working, `✓` done, `○` idle, `·` unknown;
its mobile strip uses `◉` blocked, `●` done (`src/client/shell/mobile.rs:297-298`). herdr-web-ui
status words (`src/lib/status.ts:6-13`): READY / RUN / INPUT / DONE / BG / —.

**Status colours** (REPORTED herdr-web-ui `DESIGN.md:62-72`, dark | light):
`--status-idle #818898 | #52514e`; `--status-working #70b8ff | #0051c2`; `--status-blocked
#fbad60 | #9a3f00`; `--status-done #9be963 | #006b00`; rail dots `--dot-waiting #d29922 | #9a6700`
(blocked), `--dot-working #70b8ff | #0051c2`, `--dot-done #3fb950 | #1a7f37`, `--dot-error #f85149
| #cf222e`; tints working `rgba(112,184,255,.14) | rgba(0,81,194,.12)`, blocked
`rgba(251,173,96,.14) | rgba(154,63,0,.12)`, done `rgba(155,233,99,.14) | rgba(0,107,0,.12)`.
Working dot "breathes" (`Sidebar.css:429-462`, `sidebar-breathe`, `steps(6)`); the blocked dot
is still. Compact cells draw a dot only for blocked/working/done/waiting; ready and unknown keep
the label (`Sidebar.tsx:83-105`).

**Rail geometry** (REPORTED DESIGN.md:444-449, SHELLS-DIGEST.md:20): `--siderail-w 220px`, row
`30px`, inset `12px`, gap `2px`, row radius `8px`; connection dot `7px` (DESIGN.md:458).
Collapsed rail 56 (SHELLS-DIGEST I-4/item 4 default; a 30 px icon rail is a proposal only).

**Switcher menu (fuzzel, PR #565)** (`sway-workspace-switcher:126-137`): `--font=Anthropic
Sans:size=12`, `--dpi-aware=no`, `--width=56` (chars), `--horizontal-pad=16`,
`--vertical-pad=14`, `--inner-pad=12`, `--border-width=1`, `--border-radius=8`,
`--selection-radius=4`, `--layer=overlay`, `--anchor=center`, `--keyboard-focus=exclusive`,
`--output=eDP-1`, prompt `Workspaces  `, placeholder `Top display · Herdr status at open` or
`Herdr unavailable · status at open`. Row text: `● name` focused / `! name` urgent / `  name`,
then four spaces and `assigned <status>` or `no Herdr projector` or `multiple projectors`; empty
slot `N · Empty workspace`, parked `N · Parked Herdr`. Palette from
`~/.config/theme/desktop-shell.json` keys `ground.raised`, `fg`, `fgDim`, `selection.bg/fg`,
`brand`, `border.inactive`, else parsed from `kitty.conf` (`background`, `foreground`, `color8`,
`selection_background`, `selection_foreground`, `url_color`).

**Picker rows (Vicinae)** (`herdr-picker:466-498`): `Focus|Reopen <ws name|slot> · [assigned
]<status> · <label|title|Herdr> · view <con_id>`; `Window <ws> · <title> · view <id>`; `Agent ·
<status> · <agent> · <title> · <pane_id> · open navigator`; `Status unavailable · <error> · select
to retry`; actions `New Sway workspace · first available 1–9`, `Restore last closed Herdr
workspace`, `Rename current Sway workspace`, `Open Herdr in current workspace`, `Refresh Herdr
status`. Prompt `Workspaces and Herdr · status at open · Esc to dismiss`.

**Timings**: herdr-attention poll 3 s (env `HERDR_ATTENTION_INTERVAL`, 1–60; `:417-421`), Sway
event coalesce 0.3 s (`:398`), notification expire 15 000 ms, action wait 120 s, reconnect backoff
1→30 s doubling (`:200-201`). Picker: subprocess timeout 8 s (`:37`), snapshot 6 s (`:167,174`),
projector appear 8 s, client ready 20 s, form visible/entered 5 s each (`:366-396`), `kitten @`
4 s. Projector reconnect 1, 2, 5, 10, then 30 s; a link that held ≥ 60 s resets the backoff
(`herdr-projector:168-212`). herdr-web-ui polls session-plan every 2000 ms (`server/session-plan.ts:240`).
herdr `[ui.toast] delay_seconds = 1` default.

**Notification text limits** (REPORTED socket-api.mdx:323): title ≤ 80 chars, body ≤ 240, whitespace collapsed.

---

## 5. Reusable code and data, with exact paths

### 5.1 The snapshot JSON shape (MEASURED tonight; schema-confirmed)

`herdr api snapshot` prints exactly the `session.snapshot` socket response:

```json
{"id":"cli:api:snapshot","result":{"type":"session_snapshot","snapshot":{
  "version":"0.9.3","protocol":22,
  "focused_workspace_id":"wHW","focused_tab_id":"wHW:t1","focused_pane_id":"wHW:p1",
  "workspaces":[...],"tabs":[...],"panes":[...],"layouts":[...],"agents":[...]}}}
```

`herdr-picker:178` unwraps with `value.get('result', {}).get('snapshot', value)` and requires
`workspaces` and `agents` to be lists of dicts (`:179-182`). 29,819 bytes for 24 workspaces tonight.

Record shapes (required fields per `success_response.$defs`, MEASURED keys in the live output):

- **WorkspaceInfo** — `workspace_id` ("wF0", opaque, "w" + base36ish), `number` (server ordinal
  1..N in sidebar order — **not** the Sway slot), `label` (the name typed at creation; here
  `client-slot-4-f28eff`), `focused` (server-global), `pane_count`, `tab_count`,
  `active_tab_id`, `agent_status` (workspace roll-up), optional `tokens` (≤32, from
  `workspace.report_metadata`), optional `worktree`.
  Live example: `{"active_tab_id":"wF0:t1","agent_status":"idle","focused":false,"label":"client-slot-4-f28eff","number":1,"pane_count":1,"tab_count":1,"workspace_id":"wF0"}`.
- **TabInfo** — `tab_id` ("wF0:t1"), `workspace_id`, `number`, `label` ("1"), `focused`, `pane_count`, `agent_status`.
- **PaneInfo** — `pane_id` ("wF0:p1"), `terminal_id` ("term_65db98554a94fbc", stable across
  moves), `workspace_id`, `tab_id`, `focused`, `agent_status`, `revision` (output counter, not a
  time), plus optional `agent` ("claude"|"codex"|…; absent for a plain shell/nvim), `display_agent`,
  `agent_session` `{source, agent, kind: "id"|"path", value}`, `cwd`, `foreground_cwd`, `label`
  (user-set pane name), `title`, `terminal_title` ("✳ Claude Code", "◐ Sway shell gpuix …"),
  `terminal_title_stripped` (spinner/glyph removed), `scroll` `{offset_from_bottom,
  max_offset_from_bottom, viewport_rows}`, `state_labels`, `tokens`, `restore_error`.
- **AgentInfo** (= `agents[]`, one per pane with a recognised agent) — everything in PaneInfo
  minus `scroll`, plus `name` (live agent name, null unless set), `completion_seq` ("the current
  idle transition completed work, independently of who has viewed it"), `state_change_seq`
  (default 0; increments only on effective state changes — `herdr-attention:81-84` relies on it),
  `interactive_ready`, `launch_pending`, `screen_detection_skipped`.
- **layouts[]** (`PaneLayoutSnapshot`) — `{workspace_id, tab_id, area:{x,y,width,height},
  focused_pane_id, zoomed, panes:[{pane_id, focused, rect}], splits:[]}` (area in cells;
  108×32 everywhere tonight).

**`agent_status` values** (schema enum, all four schemas): `"idle" | "working" | "blocked" | "done" |
"unknown"`. MEASURED tonight across agents: done/idle/working; across panes additionally `unknown`
(the four nvim panes). Semantics (REPORTED `herdr --skill`, lines "idle and done both mean…"):
`idle` and `done` both mean ready for input; `done` = finished work nobody has looked at yet (seen
state is tracked server-side; "explicit focus commands mark the target seen, while reads do not";
each TUI client tracks viewed completions independently, so a client's Done badge can differ from
the CLI's); `blocked` = herdr recognised an approval or question UI; `unknown` = an agent is
present but unclassified ("it does not prove completion"). The `config.toml:155-159` tally note
adds: report `idle` and never `done` from a reporter, because herdr derives done from an idle row
nobody has looked at (`app/api_helpers.rs:96-105`).

`herdr workspace list` → `{"id":"cli:workspace:list","result":{"type":"workspace_list","workspaces":[WorkspaceInfo…]}}`;
`herdr agent list` → `{"result":{"type":"agent_list","agents":[AgentInfo…]}}` (MEASURED).

Live label distribution tonight (MEASURED): 24 labels, all `client-slot-N-<hex6>`; slot numbers
in labels: 1×3, 2×4, 3×2, 4×3, 5×1, 6×3, 7×2, 8×4, 9×2. So **several herdr workspaces carry the
same slot number in their label** (e.g. slot 4 = wF0, wGG, wHK): the label records which slot the
projector *was created on*, not the current owner. The current binding is the Sway mark on the
kitty window (§5.2). Do not build a rail that maps label-slot → row without the Sway tree.

### 5.2 Workspace ↔ Sway-slot identity rules (`herdr-picker`, REPORTED, verbatim regexes)

```
CLASS     = 'herdr-projector'                                           # kitty --class, :24
SLOT      = ^herdr-slot-([1-9])$                                        # :25  Sway mark, which slot the projector owns
LABEL     = ^herdr-label-((?:client|strix)-slot-[1-9]-[a-f0-9]{6})$     # :26  Sway mark = herdr workspace label
WORKSPACE = ^herdr-workspace-(w[A-Za-z0-9]+)$                           # :27  Sway mark = herdr workspace_id (reserved; never set by main today)
CLOSED    = ^herdr-closed-([0-9]+)$                                     # :28  Sway mark, time_ns when parked
NAME      = ^herdr-name-([a-f0-9]+)$                                    # :29  Sway mark, hex(utf8) of the Sway workspace name to restore
label     = f'{seat}-slot-{slot}-{uuid4().hex[:6]}'                     # :375, seat = $HERDR_SWAY_SEAT ('client'|'strix', herdr.nix:95)
```

Rules, each with its line:

1. **Slot of a projector** (`slot_of`, :75-80): the Sway workspace `num` when 1..9; otherwise
   (parked in `__i3_scratch`) the single `herdr-slot-N` mark; two marks → `None`.
2. **Live identity** (`identity`, :186-193): the kitty window title must equal
   `f'{hostname}: {label}'` (hostname = `$HERDR_PICKER_HOSTNAME`, default `strix`) and match
   exactly one snapshot workspace. "Even marks are only hints: reconnects and native Herdr
   navigation can change a projector's selected workspace. Re-resolve from its live title."
   **On main this never matches**: `config.toml:96 window_title = ""` leaves the title to kitty
   (the pane's own title, e.g. `✳ Claude Code`). `docs/client-sway-vicinae.md` says so: "Strix
   currently disables Herdr-generated window titles. Consequently, `assigned working` means the
   originally assigned Herdr workspace is working; it does not certify that the projector still
   displays that workspace". The herdr-sway-context branch sets `window_title = "{hostname}:
   {workspace}"` (its config.toml diff) and needs a one-time `herdr server reload-config`.
3. **Assigned identity** (`assigned_identity`, :196-201): snapshot workspace whose `label` is in the
   window's `herdr-label-*` marks or whose `workspace_id` is in `herdr-workspace-*` marks; exactly
   one match or `None`. Rows show `assigned <status>` (`:480`).
4. **Status word**: `state.get('agent_status', 'unknown')` from the matched **workspace** record
   (roll-up), `'unknown'` when no identity, `'unavailable'` (switcher) when the snapshot call failed.
5. **Free slot** (`available_slot`, :99-105): first of 1..9 not a live Sway workspace number and not
   the slot of any projector (parked ones included); else `BridgeError('All nine Herdr slots are
   occupied or parked. Reopen one with Mod+Ctrl+Space; detach a view to release its slot.')`.
6. **Park = Mod+w** (`workspace_action('close')`, :441-461): for the focused Sway workspace (must be
   1..9) each `herdr-projector` window gets `mark --add herdr-slot-N`, `mark --add
   herdr-name-<hex(name)>`, old `herdr-closed-*` unmarked, `mark --add herdr-closed-<time_ns>`,
   `move scratchpad`; every other window in the workspace gets `kill`; then `workspace number
   <lowest other numbered ws, else 10>` so Sway drops the empty workspace.
7. **Restore = Mod+Shift+t** (`'restore'`, :424-431 → `focus_view`, :127-160): newest
   `herdr-closed-*` mark wins; name = the single `herdr-name-*` mark if it still starts with
   `<slot>` or `<slot>:`, else `str(slot)`; if a Sway workspace with that number exists its full
   name is reused; commands: `workspace "<name>"`, `[con_id=N] move container to workspace
   "<name>"`, `[con_id=N] floating disable`, `[con_id=N] focus`, `[con_id=N] unmark herdr-closed-…`.
   Refuses when the slot already owns another projector or when two Sway workspaces share the number.
8. **Focus any row** (`focus_view`): revalidates `pid` and `app_id` against what the menu saw
   ("That window identity changed. Open the picker again.").
9. **Rename = Mod+Shift+n** (`rename_workspace`, :402-416): only slots 1..9 ("Mod+0 remains
   Chrome"); new name `f'{num}: {name}'`; `rename workspace "<old>" to "<new>"`; the projector
   on that slot gets `herdr-name-<hex>`; names may not contain `"`, `\`, `$` or control chars
   (`quote_sway`, :108-113; Sway does not round-trip JSON escapes).
10. **Creating a projector** (`ensure_projector`, :338-399): focused Sway workspace if 1..9 else
    `workspace number <free slot>`; an existing projector on the slot is re-marked and focused (no
    input ever sent to an existing client); otherwise `exec kitty --class herdr-projector -e
    ~/.local/bin/herdr-sway-projector` (`$HERDR_PROJECTOR` overrides), wait ≤ 8 s for the new
    window on that slot, `mark --add herdr-slot-N`, wait ≤ 20 s for `client_ready` (a `herdr
    client` foreground process in `kitten @ ls` whose pid appears in `~/.config/herdr/herdr-client.log`
    as `herdr starting … pid=N` followed by `endpoint handshake succeeded`), then `ctrl+b shift+n`,
    verify herdr 0.9.3's 56×7 `new workspace` form (`workspace_form_input`, :313-335: box `┌─…─┐`,
    title `new workspace`, buttons `↵ save ^c clear esc cancel`), `send-text <label>`, verify the
    field shows the label, `send-key enter`, `mark --add herdr-label-<label>`. The form appears
    because the projector runs with `HERDR_CONFIG_PATH=~/.config/herdr/sway-client.toml`
    (`herdr-sway-projector:4`), generated from `config.toml` with `prompt_new_workspace_name = true`
    inserted after `[ui]` (`home/herdr.nix:88-92`).
11. **Mutual exclusion**: every mutating action holds `flock($XDG_RUNTIME_DIR/herdr-sway.lock)`
    non-blocking (`desktop_lock`, :116-124) — the shell must take the same lock when it issues
    these Sway commands itself, or exec the script.
12. **Chat companions** (branch only): windows marked `herdr-context-<wid>-(terminal|chat)`
    (`herdr-context:36`); `available_slot` also counts them (branch diff `herdr-picker:+119`);
    Chrome app_id `^chrome-.*-HerdrSwayContext$` gets `no_focus` + `border pixel 1` in rules.conf.

What a shell row needs per slot N (INFERRED composition of the rules): Sway workspace with `num==N`
(name, output, focused, urgent) → projector window on it or parked with `herdr-slot-N` → identity
by title (when titles are enabled) else by `herdr-label-*` mark → workspace record → `agent_status`
+ the pane/agent under it (title, agent kind, `completion_seq`). Rows without a projector are
"Empty workspace" / "no Herdr projector"; parked rows are "Parked Herdr" and reopen through rule 7.

### 5.3 How a shell polls or subscribes

**Socket**: `/home/tom/.config/herdr/herdr.sock` (MEASURED `herdr status`; `ss -xl` shows it and
`herdr-client.sock` listening). Env in every herdr pane (MEASURED): `HERDR_SOCKET_PATH`,
`HERDR_BIN_PATH=/nix/store/…-herdr-0.9.3/bin/herdr`, `HERDR_ENV=1`, `HERDR_WORKSPACE_ID`,
`HERDR_TAB_ID`, `HERDR_PANE_ID`, `TERM_PROGRAM=herdr`, `SSH_AUTH_SOCK=…/herdr.sock.agent`.
Resolution order (REPORTED socket-api.mdx:632-650): `--session <name>` → `HERDR_SOCKET_PATH` →
`HERDR_SESSION=<name>` (`~/.config/herdr/sessions/<name>/herdr.sock`) → default. The socket is
`srw-------` tom only.

**Wire** (MEASURED with a raw Python client): newline-delimited JSON. Request
`{"id":"<string>","method":"ping","params":{}}\n` → reply
`{"id":"probe-1","result":{"type":"pong","version":"0.9.3","protocol":22,"capabilities":{"live_handoff":true,"detached_server_daemon":true,"endpoint_protocol_generation":1,"surface_interest":true,"health_check":true,"ssh_agent_registration":true}}}\n`.
**One request per connection**: a second request on the same socket got `EPIPE` (MEASURED);
herdr-web-ui's client also opens a connection per call (`server/herdr/client.ts:156`). Errors:
`{"id":…,"error":{"code":"invalid_request","message":"…"}}` on stderr for the CLI, exit 1;
usage errors exit 2 (`herdr --skill`).

**Snapshot read**: `{"id":"x","method":"session.snapshot","params":{}}` → 29,819 bytes
(MEASURED). CLI equivalent `herdr api snapshot` costs ~5 ms on the strix. The docs say it is
"a one-time bootstrap snapshot … not a subscription … Call session.snapshot again after
reconnecting or when the local cache may be stale" (socket-api.mdx:118-126).

**Event stream** (MEASURED): send
```json
{"id":"sub","method":"events.subscribe","params":{"subscriptions":[
  {"type":"workspace.created"},{"type":"workspace.updated"},{"type":"workspace.closed"},
  {"type":"workspace.renamed"},{"type":"workspace.focused"},{"type":"workspace.metadata_updated"},
  {"type":"pane.created"},{"type":"pane.closed"},{"type":"pane.updated"},{"type":"pane.exited"},
  {"type":"pane.agent_detected"},
  {"type":"pane.agent_status_changed","pane_id":"wHW:p1"}            // per pane; optional "agent_status":"blocked" filter
]}}
```
First frame `{"id":"sub","result":{"type":"subscription_started"}}`; then one JSON object per line
shaped `{"event":"<dotted kind>","data":{…}}` — tonight, within 8 s, the stream delivered
`{"data":{"agent":"claude","agent_status":"blocked","pane_id":"wHW:p1","workspace_id":"wHW"},"event":"pane.agent_status_changed"}`
(this very session asking for a tool approval). Facts that bite:

- Subscription `type` values (schema `request.$defs.Subscription`, 27): `workspace.{created,
  updated, metadata_updated, renamed, moved, reordered, closed, focused}`, `worktree.{created,
  opened, removed}`, `tab.{created, closed, focused, renamed, moved}`, `pane.{created, closed,
  updated, focused, moved, exited, agent_detected, output_matched, agent_status_changed,
  scroll_changed}`, `layout.updated`. Only `pane.output_matched` (`pane_id`, `source`, `match`
  `{type: substring|regex, value}`, `lines`, `strip_ansi`), `pane.agent_status_changed` (`pane_id`,
  optional `agent_status`) and `pane.scroll_changed` (`pane_id`) take parameters. Sending
  `{"type":"pane.agent_status_changed"}` without `pane_id` → `invalid_request: missing field
  pane_id` (MEASURED); sending `{"kind":…}` → `missing field type` (MEASURED).
- A subscription naming a pane that does not exist rejects the **whole** request and closes the
  connection (socket-api.mdx:790-792). So: subscribe lifecycle events first (no params), and open a
  second subscription for per-pane status that you rebuild on every `pane.created`/`pane.closed`
  — or simply treat any event as "re-read the snapshot", the herdr-bar pattern
  (`/home/tom/Downloads/herdr-bar/src/client.rs:443-449`: "The events themselves are not
  interpreted: whoever waits re-reads the snapshot, so a dropped or coalesced event costs latency,
  never accuracy.").
- No replay; `events_lost` error closes the subscription when a reader falls behind; reconcile by
  re-subscribing then calling `session.snapshot` on another connection (socket-api.mdx:795-816).
  Snapshots and events share no sequence; never replay buffered events onto a snapshot.
- `pane.updated` fires on terminal-title changes but not spinner-only changes when
  `terminal_title_stripped` is unchanged (socket-api.mdx:829).
- Payload shapes per kind are in `event.$defs.EventData` (26 `type` consts, underscore form, e.g.
  `pane_agent_status_changed` carries `agent, agent_status, display_agent, pane_id, state_labels,
  title, workspace_id`; `workspace_*` carry the full `WorkspaceInfo`; `pane_exited` carries only
  ids). Note the **subscription event envelope uses the dotted kind** (`subscription_event`
  schema: `event` ∈ `pane.output_matched | pane.agent_status_changed | pane.scroll_changed`;
  lifecycle kinds arrive the same way, MEASURED for `pane.agent_status_changed`).
- One-shot alternative: `events.wait` with `{"match_event":{"event":"workspace_focused","workspace_id":"wHW"},"timeout_ms":…}`
  → `{"type":"wait_matched","event":{…}}`; CLI `herdr agent wait <target> [--until idle|working|blocked|done|unknown]… [--timeout MS]`.

**From the Zenbook** (the physical seat; REPORTED): the socket is on the strix. Today's scripts use
one `ssh strix 'herdr api snapshot'` per read (`herdr-picker:172-174`, 6 s budget; HERDR_SWAY_LOCAL=0
on the client, =1 on the strix, `home/herdr.nix:93-96`). For a daemon, forward the socket once:
`ssh -N -L $XDG_RUNTIME_DIR/gpuix-shell/herdr.sock:/home/tom/.config/herdr/herdr.sock strix` and
point `HERDR_SOCKET_PATH` at the local path (INFERRED, not measured tonight — OpenSSH supports
Unix-socket `-L`; `herdr --machine` would be the native way but `herdr machine list --json` is `[]`
MEASURED, and machine profiles are interactive to add). herdr-web-ui's HTTP twin
(`https://strix.tail8dd1.ts.net:8443/api/session`, token-gated) is the other door.

Recommended loop for the rail daemon (INFERRED from the above): one subscribe connection for
lifecycle + per-pane status (rebuilt on pane churn) used only as a wake-up, `session.snapshot` on
wake with a 300 ms coalesce (herdr-attention's number), and a 3 s floor poll as fallback when the
stream is down; `herdr-attention:282-308` already shows the single-in-flight refresh pattern.

### 5.4 The notification path

Two separate things called "notification":

**(a) herdr → desktop** (`notification.show`, CLI `herdr notification show <TITLE> [--body TEXT]
[--position top-left|top-right|bottom-left|bottom-right] [--sound none|done|request]`, MEASURED help).
Result `{"type":"notification_show","shown":bool,"reason":"shown|disabled|rate_limited|no_foreground_client|busy"}`.
Delivery is decided by `[ui.toast] delivery` in the **server's** config (`herdr --default-config`
lines 299-309, default commented `off`): `off` → `disabled`; `herdr` → in-app toast in the
foreground TUI client (`busy` if one is showing); `terminal` → the foreground client writes an
**OSC 99** sequence to its outer terminal — kitty (`src/terminal_notify.rs:43,73-80`:
`\x1b]99;i=1:d=0;<title>\x1b\\\x1b]99;i=1:p=body;<body>\x1b\\`) — and kitty raises a desktop
notification on the **client seat's** `org.freedesktop.Notifications` server (today mako,
tomorrow `gpuix-shell notifications`); `system` → the client shell calls the OS notification
service on the host where the TUI runs (`src/client/shell/notification_policy.rs:225-240`). With
no foreground client at all the server answers `no_foreground_client`
(`src/server/headless/notifications.rs:244-252`, `src/app/api.rs:1307-1309`). Popups are
suppressed for the active tab (configuration.mdx:495). Agent-state sounds `[ui.sound]` ride the same
policy. Main `config.toml` has no `[ui.toast]` section → delivery is off today (INFERRED) → the shell
cannot expect herdr's own "agent finished" toasts unless `delivery = "terminal"` is added (a config
reload, `herdr server reload-config`, not a restart; the file is a live symlink,
`config.toml:3-7`). ASSUMPTION for the build: the shell does **not** depend on it; it derives
attention from the snapshot/events (b).

**(b) desktop attention from state** (`herdr-attention`, branch c1a49b99; REPORTED):
poll → `Attention.update()` (`:51-100`): per agent key `workspace/pane`; `waiting = agent_status
== 'blocked'`; `new_episode = waiting and (not previous.waiting or state_change_seq changed)`;
owner = the context's label (a reused workspace id with a new label does not inherit
acknowledgement); `seen` cleared on a new episode, set when the Sway workspace is focused; a
`state_change_seq` **decrease** is a server restart → resync, no alert (`:77,93`). Effects:
`swaymsg '[con_id=N] urgent enable'` on the slot's visible representative while not focused
(`reconcile_urgency`, `:212-247`; cleared on focus/exit), and
`notify-send --app-name=Herdr --urgency=normal --expire-time=15000 --action=default=Open --wait --
'Herdr · <sway workspace name>' '<title> is waiting for your answer or approval.'` (`:254-261`); the
`default` action → `swaymsg exec herdr-context activate --workspace <wid> --pane <pane_id>`
(`:349-365`, launched through Sway so the browser lands in the compositor's cgroup); one
notification per workspace per sample (`:94-97`); focusing the Sway workspace acknowledges
(`:368-376`). Status input is `herdr-context status --json` →
`{"version":1,"contexts":[{workspace_id,label,slot,sway_workspace,terminal_id,chat_id,representative_id,view,last_view,closed,pane_id,focused}],"agents":[AgentInfo…]|null,"errors":[…]}`
(`herdr-context:596-598`, row fields at `:143-150`). For the shell's own daemon the pure
`Attention` class (`:44-115`) is directly portable to TS; the shell replaces `notify-send` with its
in-process notifications surface and keeps the `urgent` marking so Sway's own urgency state (and the
rail's `!`) agree.

### 5.5 The exact commands the rail / switcher / picker must issue

Read (herdr, any host where the socket is reachable):

```
herdr api snapshot                      # the one read; ~5 ms local; JSON on stdout
herdr workspace list                    # WorkspaceInfo[] only
herdr agent list                        # AgentInfo[] only
herdr workspace get <workspace_id>      # one WorkspaceInfo
herdr agent get <pane_id|name>          # one AgentInfo
herdr pane read <pane_id> --source visible|recent|recent-unwrapped|detection [--lines N] [--format text|ansi]
herdr agent read <target> --source recent-unwrapped --lines 120      # preview column, as herdr-bar does
herdr pane process-info --pane <pane_id>                              # foreground argv / shell_pid (herdr-panes:79-83, herdr-prune-shells:33-37)
herdr agent wait <target> [--until blocked] [--timeout MS]           # one-shot wait
herdr status                             # server reachability / versions
herdr --skill                            # the agent skill text (214 lines)
```
Socket equivalents: `session.snapshot`, `workspace.list`, `agent.list`, `workspace.get
{workspace_id}`, `agent.get {target}`, `pane.read {pane_id, source, lines?, format?,
strip_ansi?}`, `pane.process_info`, `events.subscribe {subscriptions:[…]}`, `events.wait
{match_event, timeout_ms}`, `ping`.

Write (herdr) — **none** for navigation (ruling: focus stays in Sway). The scripts' only herdr
writes are `herdr workspace close <id>` (`herdr-prune-shells:41`) and `herdr pane close <id>`
(`herdr-panes:134`). Optional, display-only, not used today: `herdr workspace report-metadata
<wid> --source gpuix-shell --token slot=N --ttl-ms …` (would let the snapshot itself carry the
Sway slot; emits `workspace.metadata_updated`; ≤16 tokens per source, ≤32 sources per workspace).
`herdr notification show …` for the shell's own messages only if delivery is turned on.

Sway (`swaymsg -r -- '<cmd>'`, `swaymsg -r -t get_tree|get_workspaces|get_outputs`,
`swaymsg -m -r -t subscribe '["workspace","window","shutdown"]'`), all from `herdr-picker`,
`sway-workspace-switcher`, `herdr-attention`:

```
workspace number <N>                                  # empty slot, created on the focused output   (picker:344,435; switcher select_workspace)
workspace "<full name>"                               # existing workspace, by complete name          (picker:154; switcher)
focus output "eDP-1"                                  # switcher does this before selecting           (switcher:99)
[con_id=<id>] focus                                   # focus a projector/window                       (picker:157)
[con_id=<id>] mark --add herdr-slot-<N>
[con_id=<id>] mark --add herdr-label-<label>
[con_id=<id>] mark --add herdr-name-<hex>  /  unmark herdr-name-<hex>
[con_id=<id>] mark --add herdr-closed-<time_ns>  /  unmark herdr-closed-<ns>
[con_id=<id>] move scratchpad                         # park
[con_id=<id>] move container to workspace "<name>"    # reopen
[con_id=<id>] floating disable
[con_id=<id>] kill                                    # detach a projector (server keeps the PTY) / close other windows
[con_id=<id>] urgent enable|disable                   # attention                                      (herdr-attention:206)
rename workspace "<old>" to "<N: name>"
exec kitty --class herdr-projector -e /home/tom/.local/bin/herdr-sway-projector
exec /home/tom/.local/bin/herdr-context activate --workspace <wid> --pane <pane_id>
```
Plus kitty remote control for the create path only: `kitten @ --to unix:@kitty-<pid> ls |
send-key --match recent:0 ctrl+b | send-key shift+n | get-text --match recent:0 --extent screen |
send-text <label> | send-key enter` (`herdr-picker:270-280, 292-310, 376-397`). The shell should
exec `herdr-picker --chord new` / `--workspace <verb>` for these rather than re-implement the
kitten dance (ASSUMPTION; the create path is the fragile one and has 39+ tests behind it).

Binds today (`home/dot_config/sway/binds.conf:6-17`, MEASURED): `$mod+Ctrl+space` picker,
`$mod+Return` chord new, `$mod+Ctrl+Shift+Return` chord sidebar, `$mod+Shift+n` rename, `$mod+t`
new, `$mod+Shift+t` restore, `$mod+w` close, `$mod+Shift+q` kill; `$mod+1..9` → `workspace number
N` on eDP-1, `$mod+0` → 10 on eDP-2 (`:48-69`); branches add `$mod+i` (switcher, eDP-1) and
`$mod+grave` (context toggle), `$mod+Shift+m` (desk at 8443).

### 5.6 Files to lift

- `/home/tom/mecattaf/dotfiles/home/dot_local/bin/herdr-picker` — 574 lines, Python, no deps; the
  identity rules, Sway helpers (`ipc`, `tree`, `walk`, `views`, `projectors`, `focused_workspace`),
  `remote_snapshot`, `desktop_lock`. Both branches import it as a module
  (`sway-workspace-switcher:19-25`, `herdr-context:27-31`), so a TS port must keep the behaviour, or
  the shell shells out to `herdr-picker --json`.
- `/home/tom/.wt/dotfiles/morning-shell/home/dot_local/bin/sway-workspace-switcher` — `make_rows`
  (38-78) and `activate` (81-103) are the switcher model; `Toggle` (140-195) is the
  second-press-closes protocol.
- `/home/tom/.wt/dotfiles/herdr-sway-context/home/dot_local/bin/herdr-attention` — `Attention`
  (44-115) pure model; `watch_sway` (161-201) the swaymsg subscribe loop with backoff;
  `reconcile_urgency` (212-247).
- `/home/tom/.wt/dotfiles/herdr-sway-context/home/herdr-context.nix:33-58` — the user-unit precedent
  for a Sway-bound daemon: `ConditionEnvironment=SWAYSOCK`, `After/PartOf
  sway-physical-session.target`, `Restart=on-failure`, `RestartSec=5`, explicit `PATH`,
  `HERDR_SWAY_LOCAL`.
- `/home/tom/mecattaf/herdr-web-ui/server/herdr/client.ts:702-800` — `subscribeEvents()` in Bun:
  connect, write the request line, line-reader, `subscription_started` gate, error/close
  handling; `shared/herdr-api.generated.ts` — TS types generated from the same schema (regenerate
  with `bun run generate:types`); `src/lib/status.ts` — status words and roll-up.
- `/home/tom/Downloads/herdr-bar/src/client.rs:443-530` — the "events as wake-up only" stream.
- `/home/tom/Downloads/herdr/docs/next/website/src/content/docs/socket-api.mdx` — the API doc
  (events 773-841, transport 608-630, notifications 311-328); `config-reference.mdx`,
  `configuration.mdx:485-495` (toasts).
- Test fixtures: `/home/tom/mecattaf/dotfiles/tests/sway-vicinae/herdr_local.py` — starts a real
  private herdr server (`HERDR_CONFIG_PATH`, `HERDR_SOCKET_PATH`, `HERDR_CLIENT_LOG`, inert shell,
  `prompt_new_workspace_name = true`) inside `runtime-test`; `tests/sway-vicinae/smoke.py`;
  `/home/tom/.wt/dotfiles/herdr-sway-context/tests/herdr/test_sway_picker.py:36-38` — minimal
  snapshot stub `{'workspaces':[{workspace_id,label,agent_status}],'agents':[{workspace_id,pane_id,agent,agent_status,terminal_title_stripped}]}`;
  `/home/tom/.wt/dotfiles/morning-shell/tests/workspace-switcher/fixtures/zenbook-0221-{get_tree,get_workspaces,get_outputs}.json`
  — a real Zenbook Sway tree with five projectors, marks `herdr-slot-{1,2,3,5,4}` and labels
  `client-slot-4-9690f0`, `client-slot-2-d6929b`, `client-slot-3-02c703`, `client-slot-5-fc4d18`,
  `client-slot-4-6a3fb5` (README:48-57) — the best input for the rail's pure tests.
- Tonight's live captures (scratchpad, this session):
  `…/scratchpad/herdr-snapshot.json` (29,828 bytes), `…/scratchpad/herdr-schema.json`,
  `…/scratchpad/herdr-skill.txt` (214 lines). Copy them into `tests/gpuix-shell/fixtures/` if a
  realistic 24-workspace snapshot is wanted (labels are not secrets; titles name Tom's projects).

---

## 6. Gaps and unknowns

1. **No Sway seat here.** This note was written on the strix (`SWAYSOCK` empty); the live Zenbook
   tree, marks and projector titles were not measured. The fixture at
   `morning-shell/tests/workspace-switcher/fixtures/` (2026-10-14 02:21) is the latest real tree.
2. **Projector titles on main defeat live identity.** `window_title = ""` → `identity()` never
   matches → every row is "assigned <status>" at best, and after a reconnect a projector may show a
   different herdr workspace than its marks claim (MAP.md §5: nine projectors reattached onto the
   server's focused workspace on 2026-10-20 12:48). Fix is in the herdr-sway-context config diff
   (`window_title = "{hostname}: {workspace}"` + reload-config); the shell should treat the
   title as the authority once that lands and the marks as the fallback. Alternative worth a look:
   the API has `client.window_title.set/clear` (per requesting client shell) — unexplored.
3. **`number` ≠ slot; labels are not unique per slot.** The only durable slot binding is in the
   Sway marks. A rail that must survive a Sway restart would need either `herdr workspace
   report-metadata --token slot=N` (a write, display-only, allowed by herdr's rules but not by the
   scripts' read-only stance) or persisting its own map; ASSUMPTION to record: keep read-only,
   rebuild from marks.
4. **herdr toasts are off** on the server config (no `[ui.toast]`), so no herdr-originated desktop
   notifications exist today; `terminal` delivery through kitty OSC 99 is the natural path into
   the shell's D-Bus server but is untested here, and the policy "suppress for the active tab"
   plus "foreground client only" means only the focused projector's kitty would emit.
5. **Remote socket from the laptop.** Only ssh-per-read is proven; an `ssh -L` Unix-socket forward
   or `herdr --machine` (needs an interactive `herdr machine add`) are INFERRED options.
6. **`done` vs `idle` is per viewer.** The CLI sees the server's seen-state; a TUI client's Done
   badge can differ; "explicit focus commands mark the target seen" — the shell never focuses, so
   its `done` rows persist until Tom looks in a herdr client. Decide whether the rail should show
   herdr's `done` or its own "new since I last focused that Sway workspace" (herdr-attention only
   tracks `blocked`).
7. **No timestamps anywhere in the API** (`revision`, `completion_seq`, `state_change_seq` are
   counters). "Last activity" needs the harness-file mtime trick (`herdr-panes:52-77`) or the
   shell's own event timestamps.
8. **Per-pane status subscriptions must be rebuilt on pane churn**, and a stale `pane_id` kills the
   whole request; the simplest robust design is lifecycle-only subscription + snapshot re-read.
9. **herdr 0.9.4 (#563)** adds a confirm-close prompt that "hits almost every close under the
   1:1:1 mapping" (REPORTED MAP.md §5); the parking flow (`move scratchpad`) does not close herdr
   workspaces so it is unaffected, but `herdr-prune-shells` and any shell "close workspace" action
   may be.
10. **herdr-web-ui's `waiting` (background work) state** is computed in the web UI server
    (`background_wait`), not available from the herdr API; the rail's vocabulary stays at the five values.
11. Not run tonight (out of scope or mutating): `herdr notification show`, `herdr workspace
    create/focus/close`, `herdr-picker` itself (needs SWAYSOCK), the branch test suites. The
    `events.subscribe` probe ran for 8 s twice and was closed cleanly; `herdr-server.log` shows
    such streams end with `outcome="stream_closed"` (MEASURED, 2026-10-20 entries).

What I did: ran `herdr --help`, `api schema [--json]`, `api snapshot`, `workspace list`, `agent
list`, `status`, `--version`, `--default-config`, `--skill`, `plugin list`, `integration list`,
`machine list --json`, the `--help` of every group and verb listed in §5.5, and raw socket `ping`,
`session.snapshot`, `events.subscribe`; read the files named above in full or in the quoted
ranges. Not verified: anything marked INFERRED, and all Zenbook-side behaviour.
