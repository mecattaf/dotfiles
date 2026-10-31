# 25 — herdr-web-ui fork: the rail, the palettes, the command palette, the marks

Reader note for the gpuix-shell overnight build (2026-10-20/21). Source read in full, read-only:
`/home/tom/mecattaf/herdr-web-ui` at `e85ffd1` (branch `build/claude-morning`, 29 commits by
`mecattaf` on 2026-10-14 02:22–04:07 CEST over upstream Hako's `42c6332`). This is the primary
visual reference for the native left rail (BRIEF.md §2, row "herdr-web-ui fork").

Labels: **MEASURED** = read from the file at the line cited; **REPORTED** = a commit message,
DESIGN.md prose or a comment claims it (not re-measured here); **INFERRED** = my reading.
All `file:line` pointers are relative to `/home/tom/mecattaf/herdr-web-ui/` unless absolute.

Contents
1. What this source is
2. Verbatim Tom rulings relevant to the desktop shell (dated)
3. Feature / behaviour inventory (table)
4. Design values: rail metrics, row grammar, state vocabulary, palettes, type, radii, timings
5. Reusable code and data (exact paths; SVG marks inline)
6. Gaps / unknowns

---

## 1. What this source is

- **A fork of herdr-web-ui** (upstream author "Hako", 669 commits; Tom 29). Upstream is a React
  19 + Vite browser client for herdr (workspaces, panes, chat lens, terminal lens). Tom's fork
  adds "the morning desk": a 220 px Chrome-Views-proportioned left rail, the Noir / Claude Light
  / Claude Dark palettes with the Anthropic faces, desk pages (`/workspaces`, `/utilities`,
  `/calendar`), a desk strip (clock + counts, "what waybar showed"), a bell (notification centre,
  "what mako showed"), palette providers (pages, utilities, workspaces, calculator, theme switch:
  "what Vicinae's launcher offered"), and an agents lens. MEASURED: `git log --author=mecattaf`.
- **Served live** on the strix at `127.0.0.1:7318` behind `https://strix.tail8dd1.ts.net:8443`
  (REPORTED, MAP.md §1 via the transcript index; not re-probed here).
- **Why it matters for the native rail**: Tom's order (BRIEF §1) says "there is a lot of
  herdr-web-ui centricity here especially on the left sidebar idea". The fork's rail is the only
  place where Tom's 220/30/12/2/8 geometry, his `--dot-*` state colours, the agents-first /
  shells-folded order, the "Waiting on you" groups and the "made in slot N" chip exist together
  as shipped code with proofs. The native GPUIX rail should reproduce this grammar, not the
  browser chrome around it.
- **Authority of DESIGN.md**: `DESIGN.md` (1706 lines) is mostly upstream's design system; Tom's
  commit `3bcfbaa` rewrote §2 Color (palette tables, Noir/Claude blocks), the font defaults and
  the Look row, and `conventions.test.ts` holds the tables equal to `src/styles.css`. Sections on
  chat, composer, prompt card, terminal, settings are upstream and only relevant where the shell
  reuses a primitive (menu, kbd, badge). §2 "Rules" still says "Amber is the one chrome color" —
  stale upstream prose for the amber palette, superseded by the Noir/Claude tables (INFERRED).

Files read (all MEASURED in full unless noted): `DESIGN.md`; `src/styles.css` (:root 27–264,
light 272–320, prefers-color-scheme 325–378, Claude Dark 380–391, compact 988–1004, shell
1085–1131, badge 1680–1727, kbd 1784–1796, menu 1985–2052); `src/components/{Sidebar,
AgentSidebar,CommandPalette,KeyBar,AgentMark}.tsx` and `.css`; `src/components/agentSvgMarks.ts`
(keys only, bodies skimmed); `src/components/{SlotChip,ShellsFold,WaitingOnYou}/*`;
`src/components/Machines.css` (1–60); `src/lib/{status,paletteSearch,look,slotLabel,
workspaceRows,railGroups,sidebarAgents}.ts`; `src/desk/{index,pages,snapshot}.ts`,
`src/desk/shell/*` (providers, paletteRows, useDeskPaletteKey, useDeskEvents, stripStore,
Strip, Bell), `src/desk/WorkspacesPage/*`, `src/desk/utilities/UtilitiesPage.tsx` (+css head),
`src/desk/calendar/CalendarPage.tsx` (head) and `ruling.ts`; `scripts/prepare-fonts.mjs` (head);
`/home/tom/.wt/hyprland-solid-shell/design/claude-rail/PROPORTIONS.md`;
`/home/tom/mecattaf/dotfiles/home/dot_local/bin/herdr-picker` (lines 1–80, 300–470, read-only).

---

## 2. Verbatim Tom rulings relevant to the desktop shell (with dates)

From BRIEF.md §1 and §5 (Tom, 2026-10-20 ~22:50, ~23:05 and 23:20 CEST, verbatim fragments as the
orchestrator relayed them):

- "there is a lot of herdr-web-ui centricity here especially on the left sidebar idea ; but having
  a comprehensive list of all the options is important." (2026-10-20 ~22:50 CEST)
- "a left bar with workspace switcher that remplaces waybar" (2026-10-20 ~22:50 CEST)
- "keeping the anthropic font that i have ... is important. i m also expecting us to be close to
  the current minimal 'noir' colorscheme with the possibility to switch to claude 'light and dark'
  variants that are already in scope." (2026-10-20 ~22:50 CEST)
- "on the sway devices, the left bar of the ai chat is a waybar style workspace (1>9) launcher"
  (standing ruling quoted in BRIEF §1; date not given there)
- "whatever you just opened: i love it. this is good enough to also become a functional
  remplacement to waybar, vicinae and mako" (standing ruling, BRIEF §1 — the Claude/Primer look)
- "functionality pull from quickshell NOT visuals" (standing ruling, BRIEF §1)
- "one to one mapping, with a limit of 9 open workspaces at a time" (standing ruling, BRIEF §1)

Rulings recorded inside the fork itself (the date is the one the file carries):

- `scripts/prepare-fonts.mjs:12` — "The fonts are private (Tom, 2026-09-01): public/fonts/ is in
  .gitignore and nothing here writes elsewhere." (MEASURED)
- `src/desk/calendar/ruling.ts:3` — `"Google Calendar is the ruled backend (Tom, 2026-10-13); not
  wired."` (MEASURED)
- `src/lib/slotLabel.ts:2-9` (Tom's own commit 472dc0e, 2026-10-14 02:37 CEST) — the label "says
  which slot the workspace was *made in*; it says nothing about where the window is now, so the
  chip reads 'made in slot N', never 'on slot N'. … herdr's `number` is a roster position and
  never a slot; `focused` is herdr's own focus and never 'on screen'." (MEASURED, authored as a
  code comment, so REPORTED as a ruling)
- `src/desk/shell/Strip/Strip.tsx:3-5` (commit 5c9a92a, 2026-10-14 02:37 CEST) — "What waybar
  showed that the browser can show; no slot row (the workspace switcher is Sway's, Track 4)."
- `src/desk/shell/Bell/Bell.tsx:2-4` — "What mako showed that the browser can show; nothing here
  reaches org.freedesktop.Notifications."
- `src/components/Sidebar.css:453-455` (commit 472dc0e) — "The rail's state colours, Tom's
  primitives (styles.css --dot-*): yellow calls for attention (herdr's blocked is the agent
  waiting on a person), red is an error and should be rare, blue works or waits on its own
  background work, green is done. The badge keeps its words."
- Commit `472dc0e` (2026-10-14 02:37:43 +0200), body: "The sidebar takes the Chrome Views left
  tab bar's metrics (design/claude-rail/PROPORTIONS.md): 220 wide, 30 px rows, 12 px insets, 2 px
  gaps, 8 px corners … the separator is an inset shadow so the rows keep 196 px. The default
  sidebar rows setting is one line, which is the 30 px row." (REPORTED; the CSS confirms it.)
- Commit `3bcfbaa` (2026-10-14 02:45:23 +0200), body: ":root is Noir (noir.nix through
  design/claude-primer/src/palettes.json: every ground #000000, elevated #101111 and hover
  #171818, the black lifted by 7% and 10% of the ink; borders as the ink at alpha) …
  defaults theme system, palette claude, paletteLight claude, paletteDark noir, sidebarRows one
  … the four font defaults are the Anthropic faces … speech input reads as off whatever a record
  says". (REPORTED)
- Transcript, Tom 2026-10-14T16:00:22Z (Claude seat, `-home-tom-today/1a517fb2…` grep): "ruling:
  we are using the claude cc that has 250 usd of credits to builds this out entirely. for macos.
  yesterday we did attempts to use gpuix to materialize a herdr web ui chat , a crm , an email
  tool , a backlog projects tool..." (MEASURED quote; context is the Frank macOS build, cited
  only because it dates the first GPUIX attempt at a herdr web ui chat to 2026-10-13.)

No other short typed Tom message in the five Claude transcripts listed in BRIEF §2 mentions
"rail", "sidebar", "waybar", "noir" or "herdr-web-ui" (MEASURED by a filtered grep of user
turns under 1800 chars; long tool-result turns excluded). The dated rulings above are therefore
the complete set this reader can vouch for.

---

## 3. Feature / behaviour inventory

Legend for the "keep/replace/new" column, from the native rail's point of view:
**keep** = reproduce as-is natively; **adapt** = reproduce the grammar, change the mechanism;
**drop** = browser-only, not for the shell; **new** = exists here, the shell needs its own.

| # | Feature | What exactly | Where it lives today | keep/adapt/drop | Notes |
|---|---|---|---|---|---|
| R1 | Rail geometry | 220 wide, 196×30 rows, 12 inset each side, 2 gap, 8 radius; separator is an inset 1 px shadow so rows keep 196 | `src/styles.css:197-203` (tokens), `:1124-1126` (inset shadow), `Sidebar.css:109-118` | keep | BRIEF §3 says exclusive zone 56 collapsed / 220 expanded; the 220 figure is this. PROPORTIONS.md adds a 12 top inset and 8h/6v row content inset the web does not copy. |
| R2 | Row grammar | one grid for every row: leading cell (`--side-box` = 34 px, holds an 18 px mark), the title, trailing status cell (`--side-status` = 20 px, holds an 8 px dot); ⋯ button 24 wide only on hover/focus/selected | `Sidebar.css:1-12, 50-63, 138-149, 353-400` | keep | status cell is absolutely positioned at the row's right edge, inside the selector (click/drag belongs to the row). |
| R3 | Row surfaces | hover `color-mix(bg-hover 50%, bg-panel)`, selected `bg-hover`, keyboard focus = 2 px accent ring inset, no fill; selected title → `--text-strong`, mark → `--text` | `Sidebar.css:11-12, 196-215, 278-284` | keep | "Hover and selection are one neutral fill at two strengths" (DESIGN.md:27). |
| R4 | Leading mark | the brand mark of the agent in the pane the row opens (never another pane's); shell → lucide `Terminal`; linked worktree without agent → `GitBranch`; repo with worktrees → the folder is the fold button | `Sidebar.tsx:313-324, 597-607` | keep | "one icon per row, as Chrome's tab row does" (commit 53ebafc). |
| R5 | Agents first, shells folded | workspaces that run an agent first; agentless ones behind one "Shells (N)" fold row; fold closed by default, remembered per device per PC; a selected shell stays visible under a closed fold | `src/lib/railGroups.ts:12-23, 46-57`, `ShellsFold/*`, `Sidebar.tsx:278-283, 688-710` | keep | fold key `herdr-web-ui:shells-open:<machineId>` (localStorage). Native: a file under `$XDG_STATE_HOME/gpuix-shell/`. |
| R6 | Waiting on you (herdr) | section above the list: head = 8 px `--dot-waiting` dot + "Waiting on you (herdr)" + count; one two-line row per agent pane blocked on a person; opens the pane | `railGroups.ts:24-41`, `WaitingOnYou.tsx:19-47`, `.css:1-123` | keep | native: focus the Sway workspace of that herdr workspace (via slot label) instead of opening a pane. |
| R7 | Waiting on you (projects) | same head, rows from `GET /api/desk/counts` `projects[]`, link out to the Worker | `WaitingOnYou.tsx:49-81`, `src/lib/deskCounts.ts` | adapt | Boundary (BRIEF §3.8): the shell may show counts and launch the Worker in Chrome; it does not host the project tool. |
| R8 | Slot chip | "made in slot N" muted chip after the name, from label `^client-slot-([1-9])-([0-9a-f]{6})$`; `coordinator-slot-*` and renamed labels give none | `src/lib/slotLabel.ts`, `SlotChip/*`, `Sidebar.tsx:647,653` | adapt | native rail *is* the slot list (Mod+1..9), so the chip inverts: the row is the slot, the herdr workspace is its content. See §5.6. |
| R9 | Rename guard | renaming a workspace with a slot label asks first ("Renaming removes the label the Zenbook picker uses to find this window.") | `Sidebar.tsx:409-426` | keep | same rule for any native rename action. |
| R10 | Compact status dot | blocked → filled 8 px `--dot-waiting`; working → 8 px `--dot-working` breathing; done → 8 px `--dot-done`; BG → 8 px ring of `--dot-working`, still; idle/unknown → nothing (cell kept, label for a11y); restore-error → 16 px warning triangle in `--dot-error` | `Sidebar.tsx:83-106`, `Sidebar.css:402-468` | keep | §4.3 has the full vocabulary. |
| R11 | Roll-up | a workspace row shows one state for all its panes: blocked > done > working > waiting(BG) > idle > unknown; a folded worktree parent rolls its group up | `src/lib/status.ts:32-47`, `Sidebar.tsx:574-576, 659` | keep | identical to herdr's server roll-up (REPORTED). |
| R12 | Two-line rows | Settings → Sidebar rows: One (30 px, name only, default) or Two (46 px: pane title over "workspace · folder") | `Sidebar.css:238-264`, `Sidebar.tsx:181, 578, 644-651`, `src/lib/paneName.ts taskRowLines` | keep (option) | DESIGN.md:733 says Two lines is default — contradicted by settings.ts and commit 3bcfbaa (one). Settings wins (REPORTED). |
| R13 | Worktree groups | linked worktrees indented one `--side-box` under the repo's row; folder = fold; "+N" dim count when folded; fold remembered per `machineId:repo_key` | `Sidebar.tsx:260-277, 558-607, 672-687`, `Sidebar.css:166-194` | adapt | herdr concept; keep if the native rail lists herdr workspaces, else drop. |
| R14 | Reorder | mouse drag, Alt+↑/↓, touch long-press (400 ms, 8 px) with a 2 px accent drop line; groups move as one; `moveWorkspace(id, index)` | `Sidebar.tsx:442-556`, `Sidebar.css:286-307` | drop | native rail order = Sway workspace number; no reorder. |
| R15 | Row menu (⋯ / right-click) | Rename workspace, Close workspace/group, New worktree, Open worktree…, Delete worktree checkout…, Expand/Collapse | `Sidebar.tsx:345-385`, `RowMenu.tsx` (not read) | adapt | native right-click on a slot: focus, move window here, close (herdr-picker verbs), rename Sway workspace. |
| R16 | Agents list | separate section under the workspaces: section head "Agents" (caret shows on hover/focus, count only when folded), rows 46 px: mark, title, dim context line "agent · PC · workspace · tab", live `name` in mono; ≤50 % of sidebar, floor = head + up to 3 rows; cut lists fade over 16 px | `AgentSidebar.tsx`, `AgentSidebar.css` | adapt | the native rail can show this as a second group; options Workspace cards, Pin agents, Agents order (Activity) exist (`settings.agentCards/agentPins/agentOrder`). |
| R17 | PC group header | monitor glyph in the leading cell, name `--text-strong` semibold `--fs-sm`, "Host" for the local PC, state dot (done=connected, working pulse=connecting, blocked=error, idle=disconnected), fold caret, `+` new workspace | `Machines.css:1-60`, DESIGN.md:780-788 | drop/adapt | single PC on the Zenbook; keep only if the rail projects the strix too (`herdr --remote strix`). |
| R18 | Footer | Install app, Settings, plan meters (usage chips) as rows on the same grid, no rule | `Sidebar.css:498-554`, DESIGN.md:795-813 | adapt | native footer: settings/power/theme; usage meters could read `claude-capacity`. |
| R19 | Resizable width | grip at the right edge, 240–520 px, never > 50 vw, keys ±16 px, double-click resets to 220 | DESIGN.md:529-535, `styles.css:1087-1089` | drop | layer-shell exclusive zone is fixed (56/220). |
| R20 | Drawer (≤768 px) | sidebar becomes a scrim drawer, swipe from the left 24 px edge | DESIGN.md:536-540 | drop | |
| P1 | Command palette open | `Mod+Shift+K` everywhere; `Ctrl+K`/`⌘K` only in the chat lens or on a desk page (never over a terminal); `<=480px` it is the More menu's first item | `src/desk/shell/useDeskPaletteKey.ts`, DESIGN.md:1421 | adapt | native: Mod+d toggles `gpuix-shell launcher` (BRIEF §3.2). |
| P2 | Palette geometry | width `min(100%, 640px)`, top offset 12 vh, max-height `100% − 12vh − 16px`, z 35, on `.menu` (bg-panel, hairline, radius 12, `--shadow-pop`); ≤640 px: bottom sheet `100% − 32px` tall, top radius 16 | `CommandPalette.css:1-13, 339-364`, `styles.css:1985-1994` | adapt | BRIEF §3.3 fixes the native launcher at 700×580, top margin 108 — different numbers, same anatomy. |
| P3 | Search row | input + close icon-button, padding 12, `bg-panel`, hairline below; placeholder "Search panes and actions…" | `CommandPalette.css:15-33`, `.tsx:623-626` | keep | |
| P4 | Status filter chips | radiogroup: All, INPUT, RUN, READY, DONE, BG with counts over all PCs; pill, 26 px tall (`control-h − 8`), `--fs-2xs` uppercase semibold, count mono; checked = state tint + colour (All/READY neutral); empty = dashed; hidden under `>` or folder browsing; keys b w i d a over the list, Left/Right on the chips | `CommandPalette.css:35-118`, `.tsx:627-636`, `src/lib/paletteSearch.ts:6-15` | keep | §4.3 colours. |
| P5 | Sections and order | Calculator (first, when the query is arithmetic) → Recent (≤3, empty query + All only) → one section per workspace in PC/roster order (search: best match's workspace first) → Actions → Settings pages (query only) → Plugin actions → desk Pages, Utilities, Workspaces, Theme; a status filter hides the action sections; `>` prefix = actions only | `CommandPalette.tsx:343-392`, `paletteSearch.ts:165-188`, `providers.ts:194-224` | keep | heading: PC › name, branch (mono), count right. |
| P6 | Pane row | min-height 56 (`--row-h`), 32 px mark box on `bg-elevated` radius 8, title `--text-strong` medium (+ "SELECTED" in accent caps), subtitle `--fs-xs` dim "tab · folder" / "workspace · folder", full `StatusBadge` at the right | `CommandPalette.css:169-220`, `.tsx:675-689` | keep | |
| P7 | Action row | 16 px dim icon, label (+ optional detail line), `.kbd` hints right, hints hidden ≤480 | `.tsx:670-673`, `styles.css:1996-2037` | keep | |
| P8 | Keys | ↑/↓ wrap; ←/→ at the text's edge step sections (inside text they move the caret); Enter activates; Escape closes (captured on window); `/` returns to the search; letter filters focus row 0 | `.tsx:205-217, 521-585` | keep | |
| P9 | Footer | ≥34 px, `bg-panel`, hairline above: place "PC › workspace › tab" (`--text`, medium) over mono path (`--fs-2xs`); kbd hints "← → Workspace", "> Actions" (hidden ≤640) | `CommandPalette.css:272-320`, `.tsx:695-704` | keep | |
| P10 | Ranking (panes) | fuzzy: substring → `1000 − 2·index − (len(hay) − len(needle))`; subsequence → `500 − 2·first − span − 12·runs`; best over label, title, terminal titles, cwd, foreground_cwd, workspace label, tab names, branch, agent, display_agent, machine name; ties keep session order | `paletteSearch.ts:97-157` | keep | |
| P11 | Ranking (desk rows) | every term must appear in title+detail+keywords; +10 per term at the title's start, +1 elsewhere; stable | `providers.ts:87-93, 150-156` | keep | lifted from `pkgs/desktop-shell/applications.ts` (REPORTED). |
| P12 | Calculator | bounded recursive descent (`+ − × ÷ % ^ ()`, 256 chars, no eval); row title = result, detail "expr · Copy result"; leads the list | `providers.ts:95-145, 181-186` | keep | lifted from `pkgs/desktop-shell/providers.ts` (REPORTED). |
| P13 | Theme switch rows | System / Claude Light / Claude Dark / Noir; writes `{theme, palette, paletteLight, paletteDark}` | `providers.ts:43-64`, `paletteRows.tsx:280-288, 301` | adapt | native: run `~/.local/bin/theme <name>` (retargets `~/.config/theme`). |
| P14 | Utilities rows | Mail, CRM, Projects, Browser, Music, Videos, Handwriting, Sign a document, Photos → open URL in a new tab | `providers.ts:31-41` | keep | native: `xdg-open`/Chrome app; the shell only launches them (BRIEF §3.8). |
| P15 | Folder browsing | a path-like query lists the PC's folders: "Open in Files", "..", Pinned folders (≤5), Recent folders (≤5), Folders | `.tsx:347-367`, `src/lib/paletteFolders.ts` (not read) | adapt | feeds `gpuix-shell files`. |
| P16 | Plugin actions | herdr plugin actions as rows, spinner (1600 ms, 8 steps) while running, error strip in `--danger-tint` | `.tsx:259-277, 475-503`, `.css:229-263` | adapt | herdr CLI equivalent exists? unknown (§6). |
| P17 | Recent targets | last panes, newest first, stored in localStorage `RECENT_KEY` | `src/lib/machinePalette.ts` (not read) | keep | |
| K1 | Key bar | 48 px (+safe area) row under the terminal on coarse pointers / ≤768: Esc Tab ^C, sticky Ctrl Alt Shift, Enter, arrows; keys 40×40 mono `--fs-sm` radius 6 hairline; armed = `bg-elevated` + accent border; hold-to-repeat arrows; never takes focus | `KeyBar.tsx`, `KeyBar.css` | drop | touch-only. Keycap styling (`.kbd`) and the chevron paths are reusable (§5.4). |
| M1 | Agent marks | hand-ported SVGs for claude, omp, codex, cursor, opencode, gjc, omo; `AGENT_SVG_MARKS` for agy amp cline copilot devin droid gemini grok hermes kilo kimi kiro maki muse pi qodercli qwen; fallback = initial in a disc; Mono mode (`data-marks="mono"`) hides Claude's tile and greys brand fills | `AgentMark.tsx`, `agentSvgMarks.ts`, `AgentMark.css` | keep | §5.3 has Claude and Codex path data verbatim. |
| D1 | Desk strip | 28 px row over the header: "● N working" (blue), "● N waiting on you" (orange), clock "Tue 14 Oct · 02:45" right; toggled from the palette; hidden <390 px | `src/desk/shell/Strip/*`, `stripCounts` in `providers.ts:228-240` | adapt | "no top bar on the Linux head" (BRIEF §1) → these two counts belong in the rail head or a rail footer line, not a bar. |
| D2 | Bell / centre | header bell with unread badge (`--status-blocked`), popover 360 wide ≤ min(70vh, 520), newest first, unread rows on `--accent-tint`, kinds agent/probe/count/note → dot colours, "Mark all read"; polls `GET /api/desk/events?since=` every 5 s while visible, cap 500 | `src/desk/shell/Bell/*`, `useDeskEvents.ts` | adapt | native notifications daemon owns org.freedesktop.Notifications; a centre with this row shape is the natural "history" surface. |
| D3 | /workspaces page | agents first (mark, title, label mono, "made in slot N", state word), then shells folded by label or by slot ("slot N"); one note "Live positions are on the Zenbook: Mod+I" | `src/desk/WorkspacesPage/*`, `src/lib/workspaceRows.ts` | adapt | the switcher the shell builds (`gpuix-shell switcher`, Mod+i) is this page made native and live. |
| D4 | /utilities page | three groups (Built / Built, not finished / Not started), a live dot per address, count tiles (Inbox, Follow-ups due, Waiting on you) from GET-only Worker reads, Zenbook bridges at 127.0.0.1:4187/4188 shown only when reachable | `src/desk/utilities/UtilitiesPage.tsx` | drop | utility index, not shell; the palette rows (P14) are the shell-side of it. |
| D5 | /calendar page | week grid on fixtures; "Google Calendar is the ruled backend (Tom, 2026-10-13); not wired." | `src/desk/calendar/*` | drop | out of scope for the shell. |
| D6 | Agents lens | timeline of a pane's session (chips, bars, event rows, 420 px detail split) | `src/components/AgentsLens/*` | drop | |
| T1 | Theme pointer | Settings → Look: Follow desk (System: Claude Light by day, Noir by night) / Claude Light / Claude Dark / Noir; `data-theme` + `data-palette` on `<html>` | `src/lib/look.ts`, `styles.css:272, 380` | adapt | native reads `~/.config/theme/gpuix-shell.json` (BRIEF §3.5); the four looks map 1:1 onto noir / claude-dark / claude-light (+ "follow" = none on Linux: the desk has no OS light/dark signal… see §6). |
| T2 | Contrast steps | `data-contrast` −2…+3 re-mixes text/hairlines (oklab) | DESIGN.md:228-255 | drop (later) | nice-to-have for the shell's theme JSON. |
| T3 | Density | comfortable / compact scale (`--fs-*`, control-h 34→32, row-h 56→44, chip-h 20→18, avatar 32→26); rail row stays 30 in both | `styles.css:988-1004` | drop | one density natively: comfortable. |
| T4 | Fonts | defaults `"Anthropic Sans"` (ui), `"Anthropic Serif"` (chat), `"AnthropicMono Nerd Font", "Anthropic Mono"` (terminal + code); the chosen family is put in front of upstream's stack; faces served from `public/fonts/anthropic.css`, copied by `scripts/prepare-fonts.mjs` from the Nix store, never committed | `src/lib/settings.ts:332-344`, `scripts/prepare-fonts.mjs:1-60` | keep (names) | native: `registerFont(bytes)` in @gpuix/native 0.11.0 (BRIEF §2) or fontconfig; same family names. |

---

## 4. Design values

### 4.1 Rail metrics (MEASURED)

| Token / alias | Value | Where | Meaning |
|---|---|---|---|
| `--siderail-w` | `220px` | `styles.css:199` | rail width; `--sidebar-w: var(--siderail-w)` in both densities (`:186`, `:999`) |
| `--siderail-row` | `30px` | `:200` | one-line row height (`--side-row`) |
| `--siderail-inset` | `12px` | `:201` | rail inset each side (`--side-gutter`); rows are 220 − 2×12 = **196 px** wide |
| `--siderail-gap` | `2px` | `:202` | between two rows (`Sidebar.css:111-113`, `WaitingOnYou.css:129`, `ShellsFold.css:42`) |
| `--siderail-radius` | `8px` | `:203` | row corners (`Sidebar.css:115-118`); `--radius-md` is also 8 |
| separator | `box-shadow: inset -1px 0 0 var(--border)` | `styles.css:1126` | drawn inside the inset so no pixel is taken from the 196 |
| `--side-box` | `var(--control-h)` = 34 px (compact 32) | `Sidebar.css:6` | leading cell width and trailing *glyph* cell width |
| `--side-row-2` | `control-h + space-3` = 46 px | `Sidebar.css:8` | two-line rows, agent rows, waiting rows |
| `--side-status` | `var(--space-5)` = 20 px | `Sidebar.css:9` | the status cell on a workspace row: "the width of its dot, not a glyph cell's, so the name keeps the room" |
| `--side-action` | `var(--space-6)` = 24 px | `Sidebar.css:10` | ⋯ button width (height = row height) |
| `--side-hover` | `color-mix(in srgb, var(--bg-hover) 50%, var(--bg-panel))` | `Sidebar.css:11` | pointer hover only |
| `--side-selected` | `var(--bg-hover)` | `Sidebar.css:12` | selection |
| mark icon | `--icon-size` = 18 px | `Sidebar.css:59-63`; `AgentMark size={18}` | inside the 34 px cell; PROPORTIONS.md's Chrome slot is 16 |
| status dot | `--space-2` = 8 px, `--radius-pill` | `Sidebar.css:444-449` | ring variant = 2 px border, transparent fill (`:433-436`) |
| status glyph (warning) | 16 px (`--space-4`) | `Sidebar.css:417-420` | restore-error triangle |
| row action icon | 16 px | `Sidebar.css:334-337` | ⋯, folder fold |
| section head | min-height 30, `--fs-sm`, regular, `--text-dim`, radius 8 | `Sidebar.css:25-41` | "quiet words, never a rule" |
| section spacing | `--space-4` = 16 px between sections (DESIGN.md:666); Agents section padding-top 8 | `AgentSidebar.css:180` | |
| coarse pointer | `--side-row: 40px; --side-action: 40px` | `Sidebar.css:556-560` | touch |
| footer | padding `8px 12px` (+ safe area), rows on the grid, icon 18 centred in the 34 cell, `--fs-md` regular | `Sidebar.css:499-529` | |
| resizer limits | 240–520 px, ≤ 50 vw, arrow 16 px, Home/End, dbl-click = 220 | DESIGN.md:529-535 | web only |

Chrome Views source geometry the web reproduces or skips (`PROPORTIONS.md:5-16`, REPORTED from
`/home/tom/mecattaf/views-shell/shell/tabs/layout_constants.cc`): rail 220, strip inset 12
per side and 12 top, row 196×30, gap 2, corners 8, **row content inset 8 h / 6 v**, **icon
design width 16**, child spacing 4, close affordance on active/hovered/focused rows. The web
rail uses a 34 px leading cell with an 18 px icon instead of 8+16+4; the native rail may pick
either. INFERRED: for a 56 px collapsed rail (BRIEF §3.3) the 34 px cell + 12 inset = 46 < 56,
so the collapsed rail can keep the leading cell centred with 11 px each side.

### 4.2 Row grammar (one-line workspace row, 196×30) — MEASURED from `Sidebar.tsx:585-669`, `Sidebar.css`

```
|<-12->|[ leading 34 : mark 18 ]| title (fs-md 14, regular, ellipsis) [slot chip][branch dim][+N] |[⋯ 24 (0 at rest)]|[status 20 : dot 8]|<-12->|
  hover: fill side-hover, radius 8     selected: fill bg-hover, title text-strong     focus: 2px accent ring inset
```
- Leading mark: agent brand mark → `Terminal` (shell) → `GitBranch` (linked worktree, no agent);
  for a repository workspace with open linked worktrees the leading cell is the folder button
  (`FolderOpen`/`Folder`) and the mark follows it.
- Title: `workspace.label` (the owner's name or herdr's); a linked worktree's branch in dim
  `--fs-xs` after it only when the name does not say it; `+N` dim tabular count when folded.
- Slot chip (`SlotChip.css`): `--fs-2xs` 11 px, padding 0 4, radius 6, background
  `color-mix(bg-hover 60%, transparent)`, `--text-dim`, never ellipsized (the name shortens first).
- Trailing: `.sidebar-pane-meta` absolute at right 0, 20 wide; inside it `.sidebar-status`
  (34 wide × 20 high box, centred) → effectively the dot sits centred in the last 20 px.
- Tooltip (`title`): `pane_id — label`, branch, checkout path, cwd, pane title, "Agents: a, b".
- Two-line variant: min-height 46; line 1 = pane title (what it does) + chip + count; line 2 =
  `--fs-xs` dim place "workspace · folder" with no word said twice (`taskRowLines`).
- Agent row (`AgentSidebar.css:321-407`): 46 high, mark 18 in 34 cell, `.agent-title` `--fs-md`,
  `.agent-context` `--fs-xs` dim, `.agent-name` mono `--text`; right: background count
  (layers glyph 12 px + mono `--fs-2xs`), plan count (`ListChecks` + `done/total`, working colour
  until done), compact status.
- Waiting row (`WaitingOnYou.css:135-187`): 46 high, mark, title `--fs-md`, place `--fs-xs` dim;
  head 30 high: 8 px `--dot-waiting` dot, text `--fs-sm` dim, count right tabular.
- Shells fold row (`ShellsFold.*`): caret 16 px in the leading cell, `Terminal` 12 px + "Shells",
  count in a 34 px trailing cell, `--fs-xs` tabular.
- PC header (`Machines.css:37-52`): padding 0 12, title min-height 30 `--text-strong` `--fs-sm`
  semibold; `+` 34 wide; manage button 24 wide on hover.

### 4.3 State vocabulary and colours (MEASURED)

Words (`src/lib/status.ts:6-13`), one per surface: idle **READY**, working **RUN**, blocked
**INPUT**, done **DONE**, waiting(background_wait) **BG**, unknown **—**. Roll-up order
(`:37`): blocked, done, working, waiting, idle.

Rail compact dot (Tom's `--dot-*` primitives; `Sidebar.css:429-460`, `styles.css:68-72, 299-302`):

| herdr state | word | glyph | Noir / Claude Dark | Claude Light | motion |
|---|---|---|---|---|---|
| blocked (waits on a person) | INPUT | filled 8 px dot | `--dot-waiting` `#d29922` | `#9a6700` | none |
| working | RUN | filled 8 px dot | `--dot-working` `#70b8ff` | `#0051c2` | breathe 2000 ms, `steps(6)`: 0–40 % opacity 1, 50–90 % 0.5, 100 % 1; all dots phase-locked to the document clock (`alignBreath`, `Sidebar.tsx:77-81`) |
| done (finished, not looked at) | DONE | filled 8 px dot | `--dot-done` `#3fb950` | `#1a7f37` | none |
| waiting (turn ended, background work runs) | BG | 8 px ring, 2 px stroke | `--dot-working` | `#0051c2` | none ("nothing about it moves until its work ends") |
| idle | READY | nothing drawn; cell + label kept | — | — | — |
| unknown | — | nothing drawn | — | — | — |
| restore_error (herdr could not restore the pane) | NOT RESTORED | `TriangleAlert` 16 px | `--dot-error` `#f85149` | `#cf222e` | none |

INFERRED: `#d29922 / #f85149 / #3fb950` and `#9a6700 / #cf222e / #1a7f37` are GitHub Primer's
`attention.fg / danger.fg / success.fg` (dark and light); they are *not* in `noir.nix` or
`claude-*.nix`. Tom named them "my primitives" (commit 472dc0e). The native theme JSON needs these
four `dot.*` keys beside the Claude palette.

Full badge (palette rows, workspaces page, composer; `styles.css:1680-1727`): `--chip-h` 20 px,
padding 0 8, `--fs-2xs` 11 px semibold uppercase `letter-spacing 0.06em`, radius 6, hairline
transparent border.

| state | text | fill | extra |
|---|---|---|---|
| idle READY | `--text-dim` | `--bg-elevated` | |
| working RUN | `--status-working` | `--status-working-tint` | 5 px dot before the word pulsing 1600 ms `steps(2, jump-none)` (trough 0.35); word never fades |
| blocked INPUT | `--status-blocked` | `--status-blocked-tint` | |
| done DONE | `--status-done` | `--status-done-tint` | |
| waiting BG | `--status-working` | `--status-working-tint` | still |
| unknown — | `--text-dim` | none | dashed `--border` edge |

Two colour families coexist: `--status-*` (the Claude palette's blue/orange/green: badges,
strip dots, workspaces page, bell) and `--dot-*` (Primer attention/danger/success: the rail's
compact dots and the Waiting head). Palette filter chips use `--status-*` (`CommandPalette.css:
101-118`). The BRIEF's herdr glyphs (blocked ◉ / working ◐ / done ● / idle ✓ / unknown ○) are the
TUI's, not this UI's; see §6.

### 4.4 Palettes — complete token tables (MEASURED `styles.css:27-320, 380-391`)

Noir is `:root`; Claude Light is `[data-theme="light"]` (and repeated verbatim under
`@media (prefers-color-scheme: light) :root:not([data-theme])`, `:325-378`); Claude Dark is a
short override of Noir under `[data-theme="dark"][data-palette="claude"]`. Only overridden tokens
are listed for Claude Dark; everything else is Noir's.

| Token | Noir (`:root`) | Claude Light | Claude Dark override |
|---|---|---|---|
| `color-scheme` | dark | light | — |
| `--bg` | `#000000` | `#f9f9f7` | `#1a1a1a` |
| `--bg-panel` | `#000000` | `#f0efec` | `#20201f` |
| `--bg-elevated` | `#101111` | `#ffffff` | `#262625` |
| `--bg-hover` | `#171818` | `#e7e7e5` | `#2c2c2b` |
| `--bg-input` | `#000000` | `#ffffff` | `#20201f` |
| `--border` | `rgba(222, 220, 209, 0.15)` | `rgba(31, 30, 29, 0.15)` | — |
| `--border-strong` | `rgba(222, 220, 209, 0.3)` | `rgba(31, 30, 29, 0.3)` | — |
| `--bubble-border` | `var(--border)` | `var(--border)` | `transparent` |
| `--text` | `#d3d7de` | `#131313` | — |
| `--text-dim` | `#818898` | `#52514e` | `#8f96a5` |
| `--text-strong` | `#eaecf0` | `#131313` | — |
| `--contrast-far` | `#ffffff` | `#000000` | — |
| `--accent` | `#70b8ff` | `#0051c2` | — |
| `--accent-tint` | `rgba(112, 184, 255, 0.13)` | `rgba(0, 81, 194, 0.1)` | — |
| `--primary` | `#d97757` | `#a74b2f` | — |
| `--primary-hover` | `#e58b6d` | `#913e27` | — |
| `--primary-text` | `#131313` | `#ffffff` | — |
| `--primary-tint` | `rgba(217, 119, 87, 0.16)` | `rgba(167, 75, 47, 0.12)` | — |
| `--status-idle` | `#818898` | `#52514e` | `#8f96a5` |
| `--status-working` | `#70b8ff` | `#0051c2` | — |
| `--status-blocked` | `#fbad60` | `#9a3f00` | — |
| `--status-done` | `#9be963` | `#006b00` | — |
| `--status-working-tint` | `rgba(112, 184, 255, 0.14)` | `rgba(0, 81, 194, 0.12)` | — |
| `--status-blocked-tint` | `rgba(251, 173, 96, 0.14)` | `rgba(154, 63, 0, 0.12)` | — |
| `--status-done-tint` | `rgba(155, 233, 99, 0.14)` | `rgba(0, 107, 0, 0.12)` | — |
| `--dot-waiting` | `#d29922` | `#9a6700` | — |
| `--dot-error` | `#f85149` | `#cf222e` | — |
| `--dot-working` | `#70b8ff` | `#0051c2` | — |
| `--dot-done` | `#3fb950` | `#1a7f37` | — |
| `--danger-tint` | `rgba(244, 123, 133, 0.12)` | `rgba(184, 10, 24, 0.1)` | — |
| `--danger-text` | `#f47b85` | `#b80a18` | — |
| `--notice` | `#f9e2af` | `#b24a00` | — |
| `--scrim` | `rgba(0, 0, 0, 0.7)` | `rgba(19, 19, 19, 0.35)` | `rgba(0, 0, 0, 0.6)` |
| `--bar-bg` | `color-mix(in srgb, var(--bg-panel) 72%, transparent)` | same | — |
| `--card-glass` | `color-mix(in srgb, var(--bg-elevated) 80%, transparent)` | same | — |
| `--glass-blur` | `saturate(180%) blur(20px)` | same | — |
| `--shadow-drawer` | `0 0 40px rgba(0, 0, 0, 0.6)` | `0 0 40px rgba(19, 19, 19, 0.22)` | — |
| `--shadow-pop` | `0 16px 48px rgba(0, 0, 0, 0.55), 0 0 0 1px var(--border)` | `0 16px 48px rgba(19, 19, 19, 0.16), 0 0 0 1px var(--border)` | — |
| `--shadow-card` | `none` | `none` | — |
| `--pdf-page` | `#ffffff` | `#ffffff` | — |
| `--term-bg` | `#000000` | `#f9f9f7` | `#1a1a1a` |
| `--term-fg` | `#eaecf0` | `#131313` | — |
| `--term-cursor` | `#eaecf0` | `#131313` | — |
| `--term-selection` | `#264f78` | `#cde2fb` | — |
| `--line-number` | `var(--text-dim)` | — | — |
| `--syntax-comment` | `var(--text-dim)` | — | — |
| `--syntax-function` | `var(--accent)` | — | — |
| `--syntax-inserted` | `var(--status-done)` | — | — |
| `--syntax-deleted` | `var(--status-blocked)` | — | — |
| `--syntax-keyword` | `#cc7bf4` | `#8100c2` | — |
| `--syntax-string` | `#9be963` | `#006b00` | — |
| `--syntax-number` | `#fbad60` | `#9a3f00` | — |
| `--syntax-type` | `#5eeded` | `#007f80` | — |
| `--syntax-variable` | `#eaecf0` | `#131313` | — |
| `--syntax-meta` | `#cc7bf4` | `#8100c2` | — |
| `--droplet-bg` / text / text-dim | `#000` / `#f5f5f7` / `rgba(245,245,247,0.62)` | same (one set) | — |
| `--droplet-blocked` / done | `#ff8a80` / `#9fd47a` | same | — |
| `--droplet-mark-bg` / ring / shadow | `rgba(255,255,255,0.1)` / `rgba(255,255,255,0.1)` / `rgba(0,0,0,0.35)` | same | — |

Notes (REPORTED from the block comments, `styles.css:30-37, 266-271, 380`):
- Noir's elevated `#101111` and hover `#171818` are black lifted by 7 % and 10 % of the ink.
- Hairlines are "the ink at an alpha (the claude.ai capture)".
- Claude Light darkens three palette colours to 4.5:1 on `#e7e7e5`: dim text `#52514e` (comment
  `#6e7687` is 3.7:1), blocked `#9a3f00` (`#b24a00` is 3.7:1), done `#006b00` (`#008000` is 3.5:1).
- Claude Dark's dim `#8f96a5` is the comment `#818898` lifted to AA on `#2c2c2b`.
- ANSI for xterm (DESIGN.md:185-188): Claude Dark red `#f47b85`, green `#9be963`, yellow
  `#f9e2af`, blue `#70b8ff`, magenta `#cc7bf4`, cyan `#5eeded`, white `#d3d7de`, bright black
  `#818898`, bright white `#eaecf0`; Claude Light `#b80a18 #008000 #a66a00 #0051c2 #8100c2 #007f80
  #52514e #6e7687 #131313`.
- The glass tokens (`--bar-bg`, `--card-glass`, `--glass-blur`) exist for the phone header and
  composer only. Tom's standing ruling "no blur, no frost" (BRIEF §1) means the native shell does
  not carry them.
- The `[data-theme="light"][data-palette="..."]` and dark blocks for amber, report, charcoal,
  catppuccin, lilac, forest (`styles.css:396-930`) are upstream opt-ins; DESIGN.md:113-171 has
  their prose. Not needed natively.

Look rows (`src/lib/look.ts:16-31`): `desk` = theme system + paletteLight claude + paletteDark
noir; `light` = theme light + palette claude; `dark` = theme dark + palette claude; `noir` =
theme dark + palette noir. The palette's THEME_ENTRIES (`providers.ts:59-64`) write the same.

### 4.5 Type (MEASURED `styles.css:131-163`, `settings.ts:332-344`)

| Token | Comfortable | Compact | Use on the rail / palette |
|---|---|---|---|
| `--fs-2xs` | 11 px | 10 px | slot chip, badges, kbd, section-count, strip |
| `--fs-xs` | 12 px | 11 px | row second line, fold counts, palette subtitle/footer |
| `--fs-sm` | 13 px | 12 px | section heads, PC name, menu rows, key bar caps |
| `--fs-md` | 14 px | 13 px | row title, agent title, footer actions |
| `--fs-lg` / `--fs-xl` / `--fs-display` | 16 / 18 / 22 | 15 / 17 / 21 | page titles |
| `--lh-tight` | 1.2 | | every rail line |
| `--lh-base` | 1.5 | 1.45 | body |
| `--fw-regular / medium / semibold / bold` | 400 / 500 / 600 / 700 | | rows regular; PC name + palette title semibold/medium |
| `--tracking-caps` | 0.06em | | uppercase micro labels (badges, chips, menu headings) |
| `--tracking-display` | −0.02em | | display line |
| `--ui-scale` | 1 (Settings → Interface font size over 14 px) | | multiplies every `--fs-*` but `--fs-input` |
| `uiFontFamily` default | `"Anthropic Sans"` | | goes in front of `--font-ui` |
| `chatFontFamily` default | `"Anthropic Serif"` | | |
| `terminalFontFamily` / `codeFontFamily` default | `"AnthropicMono Nerd Font", "Anthropic Mono"` | | mono figures on the rail (`.background-count`, `.agent-name`, palette path) |
| upstream `--font-ui` stack | `"Pretendard Variable", Pretendard, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Noto Sans KR", "Malgun Gothic", sans-serif` | | fallback only |
| upstream `--font-mono` stack | `"Symbols Nerd Font Mono", "JetBrains Mono Web", ui-monospace, "SF Mono", "JetBrains Mono", Menlo, Consolas, "D2Coding", monospace` | | fallback only |

Webfont source (MEASURED `scripts/prepare-fonts.mjs:22`): the seven woff2 and
`css/anthropic-fonts.css` come from
`/nix/store/pw6vc27w9cwqc3mmwxnsnvb3bc8sdqpb-anthropic-webfonts-2026-10-01/share/webfonts`
(AnthropicSans-Roman/Italic, AnthropicSerif-Roman/Italic, AnthropicMono-Roman/Italic,
Anthropicons-Variable; `public/fonts/` listing). The sheet declares weight ranges 300–800.

### 4.6 Spacing, radii, sizes, layers (MEASURED `styles.css:165-263`)

- Space: 4 / 8 / 12 / 16 / 20 / 24 / 32 (`--space-1..8`).
- Radii: sm 6, md 8, lg 12, xl 16, 2xl 24, pill 999.
- Sizes: `--control-h` 34 (compact 32), `--touch-target` 40, `--keybar-h` 48, `--row-h` 56 (44),
  `--chip-h` 20 (18), `--icon-size` 18, `--mark-size` 22, `--avatar-size` 32 (26), `--dot-size` 7
  (connection / strip / bell dots; the rail's dot is 8 = `--space-2`), `--rail-w` 3 (quote rails,
  not the sidebar), `--hairline` 1, `--content-w` 820, `--palette-w` 640, `--palette-top` 12vh.
- Focus: `--ring: 2px solid var(--accent)`, offset 2 (rows use −2, inside).
- Layers: header 4, banner 5, popover 10, scrim 15, drawer 20, modal 30, palette 35, droplet 40.
- Header: 52 px (<769), 46 px from 769 px in either density (`:183-185`, `:1007-1011`).

### 4.7 Timings and motion (MEASURED `styles.css:224-243`, DESIGN.md:1606-1640)

| Token | Value | Use |
|---|---|---|
| `--dur-fast` | 120 ms | hover/active/toggle, `--ease-out` `cubic-bezier(0.2, 0, 0, 1)` |
| `--motion-scale` | 1 (Off 0, Fast 0.5, Slow 1.75) | multiplies base and sheet durations |
| `--dur-base` | 180 ms × scale | drawer slide |
| `--dur-pulse` | 1600 ms, `steps(2, jump-none)`, trough 0.35 | badge RUN dot, reconnecting dot (two frames/cycle on purpose: "stutters a video playing beside the app") |
| `--dur-spin` | 1600 ms, `steps(8)` | palette plugin spinner |
| `--dur-breathe` | 2000 ms, `steps(6)` | rail RUN dot; replaced a spinning arc "that read as flicker beside the rows" |
| `--ease-spring` | `cubic-bezier(0.32, 0.72, 0, 1)` | sheets, voice pill |
| `--dur-sheet` / `-out` | 360 / 240 ms × scale | phone sheets |
| rules | only state changes move; dialogs ≥641 px snap (no entrance/exit animation); reduced motion removes everything except the RUN dot's opacity breath | DESIGN.md:1626-1638 |
| touch reorder | long press 400 ms within 8 px; flick 0.35 px/ms | DESIGN.md:764-768, 540 |
| in-app alert | 3.6 s dwell; 44 px one-line card (≤768) / 64 px two-line; 340 px max | DESIGN.md:1587-1591 |
| bell poll | 5000 ms while visible | `useDeskEvents.ts:9` |
| strip clock | ticks on the minute (+20 ms) | `Strip.tsx:34-47` |

### 4.8 Depth (MEASURED DESIGN.md:1642-1657, `styles.css:87-88`)

Tonal shift + hairline; shadow only on overlays (`--shadow-pop` for menus/palette/modals,
`--shadow-drawer` for the drawer); `--shadow-card: none` in Noir and Claude Light; dashed
hairline = unknown/empty; tinted lift = named tint over an opaque surface. This matches Tom's
"flat and opaque, hairlines not shadows" (BRIEF §1). INFERRED: a layer-shell launcher on a black
wallpaper should drop even `--shadow-pop` and keep the `0 0 0 1px var(--border)` ring.

---

## 5. Reusable code and data (exact paths)

### 5.1 Pure logic to port to TypeScript in `pkgs/gpuix-shell/src/` (no React, no DOM)

| Module | Exports worth lifting | Path |
|---|---|---|
| status words and roll-up | `STATUS_WORD`, `knownStatus`, `paneStatus`, `rollupStatus`, `statusEdgeRead` | `src/lib/status.ts` (57 lines) |
| rail order | `partitionRail`, `waitingOnYou`, `storedShellsOpen/storeShellsOpen` (swap localStorage for a state file) | `src/lib/railGroups.ts` (57 lines) |
| slot label | `SLOT_LABEL`, `parseSlotLabel`, `slotGroups` | `src/lib/slotLabel.ts` (35 lines) |
| workspaces page rows | `buildWorkspaceRows`, `slotOfLabel`, `stripTitle` (strips the leading state glyph ✳ ◐ braille), `deepLinkTo` | `src/lib/workspaceRows.ts` (131 lines) |
| agents list | `sidebarAgents` (join agents→panes in workspace/tab/pane order), `paneMark`, `workspaceAgentLabels`, `agentTabName`, `agentContext`, `groupRows` | `src/lib/sidebarAgents.ts` (139 lines) |
| palette ranking | `fuzzyScore` (private), `scorePanes`, `rankPanes`, `groupByWorkspace`, `recentPanes`, `statusCounts`, `parseQuery` (`>` prefix), `FILTER_KEYS` (`a b w i d`), `STATUS_FILTERS` | `src/lib/paletteSearch.ts` (203 lines) |
| desk providers | `searchScore`, `calculate`, `calculatorRow`, `providerSections`, `workspacePane`, `stripCounts`, `PAGE_CATALOG`, `UTILITY_CATALOG`, `THEME_ENTRIES` | `src/desk/shell/providers.ts` (240 lines) — itself lifted from `pkgs/desktop-shell/{providers,applications}.ts` in `/home/tom/.wt/hyprland-solid-shell/` (REPORTED) |
| look mapping | `lookOf`, `lookSettings` | `src/lib/look.ts` (31 lines) |
| pane names | `shortPathTitle`, `folderName`, `taskRowLines`, `placeLine` | `src/lib/paneName.ts` (not read in full; signatures at lines 9, 15, 27, 46) |
| display title | `displayPaneTitle` (label → title minus `user@host:` and `π` chrome → last folder → pane_id) | `src/components/Sidebar.tsx:45-63` |
| tests to copy with them | `slotLabel.test.ts`, `workspaceRows.test.ts`, `railGroups.test.ts`, `providers.test.ts`, `paletteSearch` tests | `src/lib/*.test.ts`, `src/desk/shell/providers.test.ts` |

Protocol shapes the rail reads (not read here, named for the builder): `shared/protocol.ts`
(`SessionSnapshot { workspaces, tabs, panes, agents, layouts }`, `HerdrPane { pane_id,
workspace_id, tab_id, agent, display_agent, agent_status, background_wait, background_tasks,
plan, label, title, terminal_title, terminal_title_stripped, cwd, foreground_cwd, focused,
restore_error }`, `WorkspaceInfo { workspace_id, label, number, agent_status, pane_count,
active_tab_id, worktree? }`), `shared/herdr-api.generated.ts`, `shared/desk-events.ts`
(`DeskEvent { id, at, kind: agent|probe|count|note, urgency, title, body, href?, pane_id? }`,
`DESK_EVENTS_CAP` 500). The native shell gets the same data from `herdr api snapshot`
(BRIEF §3.4); field names should match these.

### 5.2 CSS to transcribe into the native style objects

- `src/styles.css:27-264` (`:root`), `272-320` (light), `380-391` (Claude Dark) → the theme JSON
  rendered by `home/themes/default.nix` (BRIEF §3.5). Add the four `--dot-*` keys.
- `src/components/Sidebar.css` whole file → rail row styles (aliases at lines 1-18 are the
  contract).
- `src/components/AgentSidebar.css`, `WaitingOnYou/WaitingOnYou.css`, `ShellsFold/ShellsFold.css`,
  `SlotChip/SlotChip.css`, `Machines.css:1-60` → the other rail rows.
- `src/components/CommandPalette.css` + `styles.css:1985-2052` (`.menu`, `.menu-item`,
  `.menu-heading`) + `:1680-1727` (`.badge*`) + `:1784-1796` (`.kbd`) → launcher.
- `src/desk/shell/Strip/Strip.module.css`, `Bell/Bell.module.css` → counts line and
  notification centre rows.

### 5.3 Agent marks (SVG) — `src/components/AgentMark.tsx`, verbatim path data

Claude (`AgentMark.tsx:21-28`): `viewBox="0 0 512 509.64"`; tile `fill="#D77655"` with class
`agent-mark-tile` (hidden in Mono mode); glyph `fill="#FCF2EE"`, `fill-rule="nonzero"`, class
`agent-mark-glyph` (currentColor in Mono mode).

```
tile:  M115.612 0h280.775C459.974 0 512 52.026 512 115.612v278.415c0 63.587-52.026 115.612-115.613 115.612H115.612C52.026 509.639 0 457.614 0 394.027V115.612C0 52.026 52.026 0 115.612 0z
glyph: M142.27 316.619l73.655-41.326 1.238-3.589-1.238-1.996-3.589-.001-12.31-.759-42.084-1.138-36.498-1.516-35.361-1.896-8.897-1.895-8.34-10.995.859-5.484 7.482-5.03 10.717.935 23.683 1.617 35.537 2.452 25.782 1.517 38.193 3.968h6.064l.86-2.451-2.073-1.517-1.618-1.517-36.776-24.922-39.81-26.338-20.852-15.166-11.273-7.683-5.687-7.204-2.451-15.721 10.237-11.273 13.75.935 3.513.936 13.928 10.716 29.749 23.027 38.848 28.612 5.687 4.727 2.275-1.617.278-1.138-2.553-4.271-21.13-38.193-22.546-38.848-10.035-16.101-2.654-9.655c-.935-3.968-1.617-7.304-1.617-11.374l11.652-15.823 6.445-2.073 15.545 2.073 6.547 5.687 9.655 22.092 15.646 34.78 24.265 47.291 7.103 14.028 3.791 12.992 1.416 3.968 2.449-.001v-2.275l1.997-26.641 3.69-32.707 3.589-42.084 1.239-11.854 5.863-14.206 11.652-7.683 9.099 4.348 7.482 10.716-1.036 6.926-4.449 28.915-8.72 45.294-5.687 30.331h3.313l3.792-3.791 15.342-20.372 25.782-32.227 11.374-12.789 13.27-14.129 8.517-6.724 16.1-.001 11.854 17.617-5.307 18.199-16.581 21.029-13.75 17.819-19.716 26.54-12.309 21.231 1.138 1.694 2.932-.278 44.536-9.479 24.062-4.347 28.714-4.928 12.992 6.066 1.416 6.167-5.106 12.613-30.71 7.583-36.018 7.204-53.636 12.689-.657.48.758.935 24.164 2.275 10.337.556h25.301l47.114 3.514 12.309 8.139 7.381 9.959-1.238 7.583-18.957 9.655-25.579-6.066-59.702-14.205-20.474-5.106-2.83-.001v1.694l17.061 16.682 31.266 28.233 39.152 36.397 1.997 8.999-5.03 7.102-5.307-.758-34.401-25.883-13.27-11.651-30.053-25.302-1.996-.001v2.654l6.926 10.136 36.574 54.975 1.895 16.859-2.653 5.485-9.479 3.311-10.414-1.895-21.408-30.054-22.092-33.844-17.819-30.331-2.173 1.238-10.515 113.261-4.929 5.788-11.374 4.348-9.478-7.204-5.03-11.652 5.03-23.027 6.066-30.052 4.928-23.886 4.449-29.674 2.654-9.858-.177-.657-2.173.278-22.37 30.71-34.021 45.977-26.919 28.815-6.445 2.553-11.173-5.789 1.037-10.337 6.243-9.2 37.257-47.392 22.47-29.371 14.508-16.961-.101-2.451h-.859l-98.954 64.251-17.618 2.275-7.583-7.103.936-11.652 3.589-3.791 29.749-20.474-.101.102.024.101z
```

Codex (`AgentMark.tsx:30-36`): `viewBox="100 100 520 520"`, one path `fill="currentColor"`
(rides the text colour; in a selected rail row that is `--text`):

```
M304.246 294.611V249.028C304.246 245.189 305.687 242.309 309.044 240.392L400.692 187.612C413.167 180.415 428.042 177.058 443.394 177.058C500.971 177.058 537.44 221.682 537.44 269.182C537.44 272.54 537.44 276.379 536.959 280.218L441.954 224.558C436.197 221.201 430.437 221.201 424.68 224.558L304.246 294.611ZM518.245 472.145V363.224C518.245 356.505 515.364 351.707 509.608 348.349L389.174 278.296L428.519 255.743C431.877 253.826 434.757 253.826 438.115 255.743L529.762 308.523C556.154 323.879 573.905 356.505 573.905 388.171C573.905 424.636 552.315 458.225 518.245 472.141V472.145ZM275.937 376.182L236.592 353.152C233.235 351.235 231.794 348.354 231.794 344.515V238.956C231.794 187.617 271.139 148.749 324.4 148.749C344.555 148.749 363.264 155.468 379.102 167.463L284.578 222.164C278.822 225.521 275.942 230.319 275.942 237.039V376.186L275.937 376.182ZM360.626 425.122L304.246 393.455V326.283L360.626 294.616L417.002 326.283V393.455L360.626 425.122ZM396.852 570.989C376.698 570.989 357.989 564.27 342.151 552.276L436.674 497.574C442.431 494.217 445.311 489.419 445.311 482.699V343.552L485.138 366.582C488.495 368.499 489.936 371.379 489.936 375.219V480.778C489.936 532.117 450.109 570.985 396.852 570.985V570.989ZM283.134 463.99L191.486 411.211C165.094 395.854 147.343 363.229 147.343 331.562C147.343 294.616 169.415 261.509 203.48 247.593V356.991C203.48 363.71 206.361 368.508 212.117 371.866L332.074 441.437L292.729 463.99C289.372 465.907 286.491 465.907 283.134 463.99ZM277.859 542.68C223.639 542.68 183.813 501.895 183.813 451.514C183.813 447.675 184.294 443.836 184.771 439.997L279.295 494.698C285.051 498.056 290.812 498.056 296.568 494.698L417.002 425.127V470.71C417.002 474.549 415.562 477.429 412.204 479.346L320.557 532.126C308.081 539.323 293.206 542.68 277.854 542.68H277.859ZM396.852 599.776C454.911 599.776 503.37 558.513 514.41 503.812C568.149 489.896 602.696 439.515 602.696 388.176C602.696 354.587 588.303 321.962 562.392 298.45C564.791 288.373 566.231 278.296 566.231 268.224C566.231 199.611 510.571 148.267 446.274 148.267C433.322 148.267 420.846 150.184 408.37 154.505C386.775 133.392 357.026 119.958 324.4 119.958C266.342 119.958 217.883 161.22 206.843 215.921C153.104 229.837 118.557 280.218 118.557 331.557C118.557 365.146 132.95 397.771 158.861 421.283C156.462 431.36 155.022 441.437 155.022 451.51C155.022 520.123 210.682 571.466 274.978 571.466C287.931 571.466 300.407 569.549 312.883 565.228C334.473 586.341 364.222 599.776 396.852 599.776Z
```

Other hand-ported marks in the same file (lines given; copy from the file, not retyped here):
Cursor `:38-48` (5 currentColor paths, opacities .39/.8/.6/.72/.95, viewBox 0 0 24 24); OpenCode
`:50-59` (#4B4646 / #F1ECEC, viewBox 0 0 300 300); omp `:61-76` (64×64, rx 12 `#0f0a14` tile,
gradient `#ed4abf → #9b4dff → #5ad8e6`); gjc `:78-135` (hat + visor with gradients and a glow
filter); omo `:137-149` (`#F4F4F4` tile, `#041617` glyph). `AGENT_SVG_MARKS` (`agentSvgMarks.ts`,
minified lobe-icons MIT + Factory droid + maki.sh favicons) for: agy, amp, cline, copilot, devin,
droid, gemini, grok, hermes, kilo, kimi, kiro, maki, muse, pi, qodercli, qwen; `SvgMark` prefixes
every `id=` / `url(#` / `href="#` per instance so two copies never share a gradient
(`AgentMark.tsx:153-158`). Fallback (`:160-170`): circle r 11 on `--bg-elevated` with a
`--border` stroke and the agent's initial at 11 px.

Mono mode (`AgentMark.css`, `[data-marks="mono"]`): Claude's tile hidden, glyph `currentColor`;
other brand marks `filter: grayscale(1)`; codex/cursor/cline/fallback already ride currentColor.
Rationale: "a list where most rows run Claude is not a stripe of orange tiles" (`:214-218`).
INFERRED: the native rail should default to this Mono mode on Noir.

GPUIX rendering: @gpuix/native 0.11.0's API (`/home/tom/Downloads/gpuix/packages/native/index.d.ts`)
was not read here; whether it draws SVG paths natively or needs rasterised PNGs is a gap (§6).

### 5.4 Key bar bits still useful natively

Chevron paths (`KeyBar.tsx:143-148`, 20×20, stroke 1.75 round): up `M5 12.5l5-5 5 5`, down
`M5 7.5l5 5 5-5`, left `M12.5 5l-5 5 5 5`, right `M7.5 5l5 5-5 5`. Keycap (`.kbd`): 18 px high,
padding 0 5, hairline `--border-strong` with a 2 px bottom, radius 6, `--bg-elevated`, dim mono
`--fs-2xs`; "Mod resolves to ⌘ on Apple and Ctrl elsewhere" (DESIGN.md:563). Key press state
(`KeyBar.css:667-672`): `--bg-elevated` fill, `--accent` border, `--text-strong` — reusable for an
OSD keycap row.

### 5.5 Desk surfaces to mirror

- Strip (`Strip.tsx:53-76`, `.module.css`): 28 px, `--bg`, hairline below, `--fs-2xs` tabular,
  dots 7 px (`--status-working` / `--status-blocked`, `--status-idle` at zero), counts turn
  `--text` when non-zero, clock `weekday short · day · month short` + `HH:MM` with the time in
  `--text-strong` medium. `stripCounts`: working = panes with an agent and `agent_status ===
  "working"`, waiting = `"blocked"`.
- Bell (`Bell.tsx`, `.module.css`): badge 14 px pill `--status-blocked` with `--primary-text`
  9 px semibold ("99+"); centre = `.menu` 360 wide, head (title `--fs-sm` semibold, Mark all read,
  Close), rows: 7 px kind dot (agent → working blue, count → accent, probe → notice yellow, note →
  idle, urgency 2 → blocked), title `--fs-sm` strong + time `--fs-2xs` tabular, body `--fs-xs` dim,
  actions "Go to page" / "Open pane" as accent text links; unread rows `--accent-tint`.
- Workspaces page (`WorkspacesPage.module.css`): the rail's proportions at page scale (row
  `--control-h` 34, inset 12, gap 2), state word `--fs-2xs` semibold tracking .04em right-aligned
  in `--status-*`, count pill on `--bg-elevated`, `<details>` folds with a rotating chevron.

### 5.6 The "made in slot N" mapping (MEASURED, cross-checked with herdr-picker)

- Producer: `/home/tom/mecattaf/dotfiles/home/dot_local/bin/herdr-picker:365-387`
  (`ensure_projector`): on the focused Sway workspace `slot = ws.num` (1..9, else the next free
  slot), a kitty `--class herdr-projector` is spawned, marked `herdr-slot-{slot}`, and when a new
  herdr workspace is created the label is `f'{seat}-slot-{slot}-{uuid4().hex[:6]}'` with `seat =
  'strix'` on the strix, else `'client'`; it is typed into herdr's 56×7 "new workspace" form and
  the kitty con is marked `herdr-label-{label}`.
- Live position: `slot_of(node, ws)` (`herdr-picker:75-80`) = the Sway workspace number if 1..9,
  else the single `herdr-slot-N` mark. The picker regex `LABEL` accepts `(client|strix)-slot-`
  (`:26`).
- Consumer (web): `src/lib/slotLabel.ts:11` `^client-slot-([1-9])-([0-9a-f]{6})$` → chip
  "made in slot N"; `coordinator-slot-*` → none; a `strix-slot-*` label → **none** (gap, §6).
- Counts in the 00:29 strix capture (REPORTED, commit 472dc0e): slots 1:10, 2:10, 3:3, 4:12,
  5:1; 13 coordinator labels ignored; 197 workspaces, 7 agents (`site/demo/fixtures/strix-rail.json`).
- For the native rail (INFERRED from BRIEF §1 "one herdr workspace = one kitty projector window
  = one Sway workspace"): the rail's nine rows are Sway workspaces 1..9; each row's content is
  the herdr workspace whose projector sits there now (Sway tree: con with `app_id ==
  herdr-projector` and `herdr-label-<label>` mark → `herdr workspace list` row with that label →
  its roll-up state and agent mark). The label's own slot number is history only; show it as a
  dim chip only when it differs from the row's slot.

---

## 6. Gaps / unknowns

1. **Two colour families for state.** `--status-*` (Claude palette) and `--dot-*` (Primer
   attention/danger/success) both ship; the rail uses `--dot-*`, every other surface `--status-*`.
   The native theme JSON must carry both or pick one. Tom's words favour the dots for the rail
   ("my primitives"); not confirmed for OSD/toasts. **Default proposed**: dots on the rail, status
   colours elsewhere, as here.
2. **Glyph vocabulary mismatch.** BRIEF §1 lists herdr's TUI glyphs (◉ ◐ ● ✓ ○); this UI draws
   dots/rings and no glyph for ready/unknown. For a 56 px collapsed rail with no title, a dot alone
   may be too little. Unverified which Tom prefers; the web proof is the dots.
3. **DESIGN.md contradicts itself on Sidebar rows default** (`:343` one vs `:733` two lines).
   `settings.ts` and commit 3bcfbaa say one. Treat one line (30 px) as the ruling.
4. **Chrome content inset vs web cell.** PROPORTIONS.md: 8 h / 6 v inset, 16 px icon, 4 spacing.
   Web: 34 px leading cell with an 18 px icon, no vertical inset beyond centring in 30. Either is
   defensible; pick the web's since it is what Tom approved on 10-14.
5. **Collapsed 56 px rail** has no precedent here; the fork never collapses to icons (desktop
   collapse removes the column, DESIGN.md:536). Geometry for 56 px is INFERRED in §4.1.
6. **"Follow desk" look** depends on `prefers-color-scheme`; on the Sway head there is no OS
   signal, only the `~/.config/theme` symlink. Map: noir / claude-dark / claude-light; drop
   "follow".
7. **`strix-slot-*` labels get no chip** in the web UI (`slotLabel.ts` is `client` only) though
   the picker writes them on the strix seat. Native parser should accept `(client|strix)`.
8. **GPUIX SVG capability** not checked (index.d.ts unread by this reader): whether the Claude
   and Codex paths can be drawn as vector paths or must be rasterised.
9. **Fuzzy ranking vs desk ranking**: two scorers coexist (`fuzzyScore` for panes, `searchScore`
   for desk rows); sections are concatenated, not merged by score. Fine for the launcher, but
   Vicinae-style unified ranking (BRIEF §5) would need one scorer.
10. **Plugin actions** (`GET /api/pane/plugins`, `runPluginActionToEnd`) — no herdr CLI
    equivalent known from this read.
11. **Recent targets / pinned agents / shells-open** live in localStorage; the native shell needs
    an equivalent under `$XDG_STATE_HOME/gpuix-shell/` (format unspecified).
12. **Not read**: `src/lib/{paneName,paletteFolders,machinePalette,sidebarPins,sidebarOrder,
    sidebarActivity,deskCounts,touchReorder,worktreeName,tabName}.ts`, `RowMenu.tsx`,
    `Machines.css` past line 60, `MachineSidebar.tsx`, `SettingsDialog.tsx`, the amber/report/
    charcoal/catppuccin/lilac/forest blocks, `site/demo/fixtures/strix-rail.json`,
    `scripts/rail-demo-regression.ts` (the Kind B proof that measured 220/196×30/2/12). The
    fixture and the regression script are the ready-made test data for a native rail smoke.
13. **Unverified live**: that the fork still serves at :7318 and that the strix capture counts
    still hold; nothing was probed over the network (read-only rule).

What this reader did not do: run any script, probe any port, or measure rendered pixels; every
pixel value above is the stylesheet's declared value or a commit's reported measurement.
