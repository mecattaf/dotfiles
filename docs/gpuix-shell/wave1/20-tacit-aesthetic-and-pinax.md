# 20 — Tacit: the aesthetic to stay close to, and the Pinax file explorer

Reader note for the gpuix-shell overnight build (2026-10-20/21). Read-only study of the
Tacit archive; nothing in `/home/tom/saturday-tacit` was changed. Every number below carries a
label: **MEASURED** = read from the QML/scripts (file:line given), **REPORTED** = taken from a
Tacit/Tom note that itself reports it, **INFERRED** = my reading of how it maps onto Tom's shell.

Path shorthand: `T/` = `/home/tom/saturday-tacit/iso-files/usr/share/tacit/shell/`.

---

## 1. What this source is

- `/home/tom/saturday-tacit/` is a research archive collected 2026-10-17 from
  `tacit-2026.10.17.1-x86_64.iso` (README.md:3). `iso-files/` keeps the full `/usr/share/tacit`
  tree with original paths; `preview/` is the sandbox launcher + `pinax-preview.qml` + one
  screenshot; `research/` holds three ecosystem notes; `metadata/` provenance.
- Tacit is an Arch distro whose desktop is **Hyprland + Quickshell/QML** (TACIT-OVERVIEW.md:31-33),
  forked from end-4's illogical-impulse ("ii") via end4-pC. The shell is ~34k lines of QML across
  the modules I read (wc on the target set). Shared design kit = `T/modules/common/`.
- The pieces Tom asked about:
  - **Appearance.qml** (578 lines) — the design-token singleton: m3 colour roles (matugen,
    wallpaper-derived), the ink/APCA system, radii, font scale, icon sizes, spacing, animation
    curves and durations, surface sizes.
  - **Tacit.qml** (63 lines) — the 2026-10-08 "kit": inks, colour-by-meaning, six type sizes,
    three radii. The newer, tighter layer on top of Appearance.
  - **Pinax** = `T/modules/ii/files/` (9 files, 5200 lines): FilesWindow.qml (2960), FilesRail
    (446), FilesRow (335), FilesCell (168), FilesPreview (259), GalleryView (209), RenameSheet
    (224), SaveWindow (508), FilesPanel (91). Plus `T/services/Files.qml` (437), `Jobs.qml`
    (266), `Things.qml` (177), `Origins.qml` (238), `Recents.qml`, `Devices.qml`, `Voice.qml`
    (66), `T/scripts/files/job.sh`, `T/modules/common/widgets/DropShelf.qml` (126).
  - **The notch** = `T/modules/ii/island/` + `T/services/IslandController.qml` (2254 lines).
  - **Notification popup/centre** = `T/modules/ii/notificationPopup/NotificationPopup.qml` (339)
    + `widgets/NotificationPopupList.qml`, `NotificationItem.qml`, `NotificationGroup.qml`.
  - **OSD** = `T/modules/ii/onScreenDisplay/` (4 files).
  - **Control panel** = `T/modules/ii/sidebarRight/` (18 files; Wifi 726, Bluetooth 582).
  - **Bluetooth pairing sheet** = `T/modules/ii/bluetooth/` + `T/services/BluetoothAgent.qml`.
  - **Palette/overview** = `T/modules/ii/overview/` (SearchWidget 1315, PaletteDock 539).
  - **Session screen** = `T/modules/ii/sessionScreen/SessionScreen.qml` (404).
  - **Bar** = `T/modules/ii/bar/` (39 files) — retained but **off by default**; the notch
    replaced it (Config.qml:452, IllogicalImpulseFamily.qml:81-83).
- `preview/tacit-actual-app-preview.png` (MEASURED, read as image): 2564×1644, three
  overlapping windows on a near-black ground. Front: **Graphis** (code editor) — a left pane
  with "Project ˅" + `~/Demo/Project` under it, a highlighted "New file   Ctrl N" row, "A folder ·
  no change tracking", a "Files  2" section label with a meta count, rows `<> example.py` and a
  ring-outlined `≡ README.md`, and "Pick a file on the left." centred in the empty editor.
  Behind it, **Pinax**: rail rows Home / Pictures / Project faded under Graphis, a toolbar of
  list/grid/gallery glyphs, sort, hidden-eye, `+`, a pill "Search" field, column heads "Modified
  Size", two rows "1m  —". Right: **Praxis** with "Pick a session on the left." in faint ink.
  What the shot establishes visually: generous 12–20 px gutters, 15 px row type, one hairline
  per panel, hover/selection as a faint neutral wash, a 1 px ring on the keyboard row, no
  shadows, no coloured chrome, Material Symbols glyphs at ~18–20 px. (Blur is absent because
  the preview ran under Sway, TACIT-OVERVIEW.md:71.)

---

## 2. Verbatim Tom rulings relevant to the desktop shell

Dated where a date exists. Oct 17 lines are REPORTED via `TACIT-OVERVIEW.md` (the Claude
transcripts under `~/.claude/projects` carry no user turn mentioning Tacit that day; I grepped
all of them). Oct 20 lines are from `docs/gpuix-shell/BRIEF.md` §1 and §5 with the times the
orchestrator recorded.

| When | Verbatim | Where recorded |
|---|---|---|
| 2026-10-17 | "ok this is pretty nice.." | TACIT-OVERVIEW.md:15 |
| 2026-10-17 | "the file explrer , code editor and agent interfact was pretty good despite being doen in quickshell" | TACIT-OVERVIEW.md:19 |
| 2026-10-17 | "that being said i'm not a big fan of using quickshell for everything." | TACIT-OVERVIEW.md:23 |
| 2026-10-17 | (asked to) "preserve the QML, optimisations and other useful implementation files for further study" (paraphrase in the overview, :27) | TACIT-OVERVIEW.md:27 |
| 2026-10-20 ~22:50/23:05 CEST | "lately i saw 'tacit' dotfiles ... in my case what is of interest is mainly the file explorer ... more importantly however is the aesthetic that was achieved with this tacit os quickshell config: this is what i would like to remain close to (of course, different font than the one i want, but i like the vanilla-ness of it). openUI for the desktop shell is not quite known" | BRIEF.md:25-28 |
| 2026-10-20 ~23:20 CEST | "lately i saw 'tacit' dotfiles that had some cool advanced dotfiles functionality: files explorer, text editor, llm chat... in my case what is of interest is mainly the file explorer if any of the three." | harness user request (this run) |
| 2026-10-20 | "keeping the anthropic font that i have ... is important. i m also expecting us to be close to the current minimal 'noir' colorscheme with the possibility to switch to claude 'light and dark' variants" | BRIEF.md:18-20 |
| 2026-10-20 | "functionality pull from quickshell NOT visuals"; "flat and opaque, hairlines not shadows, no blur, no frost, wallpaper is #000000 solid" | BRIEF.md:42-44 (standing rulings) |
| 2026-10-20 | "no top bar on the Linux head"; "on the sway devices, the left bar of the ai chat is a waybar style workspace (1>9) launcher" | BRIEF.md:48-49 |
| 2026-10-07 17:01Z | "the concept that 'almost everything made as a webapp' (except for the gtk/nautilus file explorer i guess) is achievable and moreso than i thought." | ~/.claude/projects/-home-tom-today/b7646300…jsonl |
| 2026-10-06 18:50Z | "its file explorer is on par with nautilus from a functionality standpoint, just want to make srue taht google chrome itself can leverage it as well. ... shortcut-driven navigation is super exciting also." (about otto; shows the bar Tom holds a file explorer to) | ~/.claude/projects/-home-tom-mecattaf-dotfiles/95fbdae1…jsonl |

Reading of the rulings for this note (INFERRED, written down so the builder can disagree):
- "vanilla-ness" = Tacit's *restraint*: one hairline per panel, neutral washes for hover/selection
  (no coloured containers), accent used only for "what Enter does" and "where you are", text
  hierarchy by brightness not opacity, generous 12–20 px insets, radius 8–14 inside, no shadows.
- Tom's standing rulings override Tacit where they conflict: **no blur, no frost, opaque
  surfaces** (Tacit's panels are 76 % frost over compositor blur — drop), **no
  wallpaper-derived palette** (Tacit's matugen roles → Tom's noir/claude tokens), **Anthropic
  Sans** not Tacit Sans, **no top notch** ("no top bar") → the notch's *event model* survives in
  the toasts/OSD daemon and the rail, its *shape* does not.

---

## 3. Feature / behaviour inventory

Legend: **keep** = reproduce as-is in gpuix-shell; **replace** = reproduce the function with a
different surface/visual per Tom's rulings; **new** = not in Tom's current setup, add; **skip** =
not for Tom. "Where it lives today" = Tacit file; Tom's current equivalent in the notes column.

### 3.1 Pinax (file explorer) — this is the spec

| Feature | What exactly | Where it lives today | keep/replace/new | Notes |
|---|---|---|---|---|
| Window model | One real toplevel per window; Super+E reuses newest ordinary window, Super+Shift+E opens another; picker windows never reused for "open" | FilesPanel.qml:6-33, Files.qml:314-320 | keep | `gpuix-shell files` ordinary Sway window; one process per window or one process many windows (GPUIX: one window per process → one process per Files window, PLAN decides) |
| Remembered shape | Opens at last floating size (default 1000×640, min 640×400), re-tiles/maximises itself via compositor a beat after mapping; shape re-saved every 2 s while open | FilesWindow.qml:35-39, 137-155, 353-358; Files.qml:122 | keep (Sway: `swaymsg floating/resize`; drop Hyprland address dance) | Sway has stable con ids; no 150 ms address-hunt needed |
| Super+drag docking | Drop at left/right edge → joins tiling on that side; middle → floats centred; top edge → maximise | FilesWindow.qml:156-352 | skip (Sway tiling already does this; Tom's model is 9 fixed workspaces) | |
| Where to open | No folder given: a file that arrived in last 10 min → its folder with it selected and a status reason "Downloads, because X arrived 2m ago"; else focused terminal's cwd; else last folder | Files.qml:270-313 | keep | Tom: cwd of focused kitty via `/proc/<pid>/cwd` of the shell child; arrivals from own `~/Downloads` watcher |
| Rail (places) | 248 px full / 60 px compact; toggle at top (Ctrl+B, remembered); compact rail expands *over* the list after 160 ms hover, folds 260 ms after leave; sections: Now (transient, max 4), Recent, Shelf (only when parked items), Places (Home, Downloads, Documents, Pictures, Music, Videos, Desktop), Pinned (drop a folder on the rail to pin), Drives (click mounts+enters, eject glyph on hover), hairline, Large & old (only when disk ≥85 %), Trash with count | FilesRail.qml:149-186, 384-534; Files.qml:239-247 | keep | Row = 32 h, wash inset 8, accent tick 3×16 at x8 for "current", glyph at x20 (18 px), label at x44 (15 px, Medium when current), context count at end in meta ink (13 px numbers), 6 px accent dot = "new since you looked" |
| Rail drop targets | Any place/pin/trash row accepts `text/uri-list`; Shelf row parks; accent 1.5 px ring while dragging over | FilesRail.qml:263-281, 365-373 | keep | |
| Header | Back/Forward (32 px round), folder name 16 DemiBold + breadcrumb trail 13 px (root, "…", last two when >4), click empty header → path edit (mono 14, `~` expands); Ctrl+L | FilesWindow.qml:1056-1074, 1957-2069 | keep | |
| View switch | list / grid / gallery as three 30×30 glyph toggles (Ctrl+1/2/3); per-folder memory; a folder ≥60 % images (first 200) auto-picks grid once | FilesWindow.qml:1076-1108, 2071-2087 | keep | |
| Sort | "Name ↑" word button (glyph-only <900 px) opens a 5-row menu (Name/Modified/Size/Kind/flip); column heads clickable in list view; picking the active field flips direction | FilesWindow.qml:1450-1455, 2089-2101, 2186-2215 | keep | |
| Hidden files | Eye toggle, Ctrl+H; status line says "hidden shown" | FilesWindow.qml:2102-2107 | keep | |
| New | `+` menu: New folder (Ctrl+Shift+N), New file (Ctrl+Alt+N); created item immediately enters rename with stem selected (".txt" kept) | FilesWindow.qml:1425-1431, 2108-2115, 1311-1342 | keep | |
| Filter vs search | Field (36 h pill, 140–230 w) filters this folder live (120 ms debounce; hidden rows keep model index, 0 height); Enter / Ctrl+Shift+F = deep search under folder via `fd` streaming hits (first 500) flushed every 40 ms; Esc clears filter then selection | FilesWindow.qml:417-437, 475-481, 914-981, 2118-2174 | keep | gpuix: `fd` child process + line stream; same flush cadence |
| Search grammar | Words parsed: kinds (photos/videos/pdf/docs/code/archives/music), "from zen/phone/claude", screenshots, today/yesterday/this week/last month/N days, big/small; status line says "read as photos · from zen · last 7 days" | FilesWindow.qml:858-913 | keep | Origin-source words need the origin index (see Origins) |
| Recent view | Files touched under home in last 7 days (find -mtime -7, top 300), day sections Today/Yesterday/weekday/Earlier, same rows as search | FilesWindow.qml:755-857 | keep | |
| Large & old | Rail entry appears at ≥85 % disk: files >100 MB untouched 90 d, biggest first, "Disk 91% · 12 GB free" line | FilesWindow.qml:758-794 | keep | |
| Shelf view | Parked files as a list; "Take off the shelf", "Clear the shelf" | FilesWindow.qml:795-815, 2420-2422 | keep (shelf lives in the rail/toasts daemon instead of a notch) | |
| List row | 34 h (48 with origin line), radius 8, glyph 20 px at x12, name 15 px at x46 (Medium when selected, ElideMiddle), origin line 13 px secondary ink, age 84 w + size 72 w right-aligned 14 px numbers font, gap 18; selected = onSurface 12 % wash, hover 5 %, keyboard cursor without selection = 1 px outlineVariant ring @0.7; "cut" rows 50 % opacity; partial downloads (.part/.crdownload) say "downloading" in accent | FilesRow.qml:48-250 | keep | |
| Offer pill | A per-row suggestion pill before the dates: "same as X · drop the copy" (byte-twins found by size + head/tail md5 after load, ≤1500 files) or "→ Invoices" (learned habit: 2 of last 3 moves of this app|kind went there); Enter/→ takes, Esc dismisses | FilesRow.qml:192-227; FilesWindow.qml:1348-1384; Files.qml:155-184 | new (nice) | Habits persisted, "Forget where I file things" action |
| Selection | Click selects; Ctrl toggles; Shift ranges; band-select from blank ground *or* from the blank part of a row (press >40+nameWidth+12 px); Ctrl+A; cursor is a *path* not an index (survives files arriving) | FilesWindow.qml:400-410, 1110-1217, 2451-2516; FilesRow.qml:262-298 | keep | |
| Keyboard | Enter open, Backspace/Alt+Up up, Alt+←/→ history (50), Home/End/PgUp/PgDn(12), arrows (grid moves by columns), Space toggles preview column, typing jumps to name (800 ms buffer), F2 rename (many → sheet), Delete trash, Shift+Delete delete, Ctrl+C/X/V, Ctrl+Z undo, Ctrl+Shift+C copy path, Ctrl+Shift+T terminal here, Ctrl+Shift+S send to, Ctrl+W close, Ctrl+=/−/0 grid zoom, Esc ladder (stop job → dismiss offer → cancel cut → close preview → clear filter → clear selection) | FilesWindow.qml:1798-1895 | keep | Every key also reachable as `files act <name>` (perform(), :1677-1698) |
| Slow-click rename | Second click on the name of the single selected row 450–3000 ms later → inline rename (Finder) | FilesRow.qml:299-317 | keep | |
| Inline rename | Name becomes a 26 h field (radius 6, surfaceContainerHighest, primary border; error border + ink if name taken); Enter commits, Esc reverts, Tab commits and edits next row; click-away commits a good name | FilesRow.qml:139-182 | keep | |
| Rename many | Sheet at foot: "Replace text" / "Number them" modes, live preview of first 5 (clashes in risk colour), Rename waits until clean; Slab buttons | RenameSheet.qml | keep | |
| Grid cell | 156×176 base, art 120×100 (radius 10), scales with gridSize ∈ {0.75,1,1.25,1.5,2} (pinch or Ctrl+=/−), name 14 px centred, age 13 px; thumbnails only for images (256/512 px) | FilesCell.qml; FilesWindow.qml:1090-1100, 2268-2306 | keep | Thumbnails: Tacit has a native ThumbnailImage; gpuix → own thumbnailer (XDG thumbnail cache) |
| Gallery | Big preview (≤1600 px, fade-in), caption (name 16 DemiBold, facts 13), horizontal strip 96 h of 88×96 tiles (72 px art, radius 8), accent 16×3 tick under current | GalleryView.qml | keep | |
| Preview column | 300 px third column; auto-open when width ≥1240 or (≥900 and height ≥800), Space toggles otherwise; shows picture (≤260 h, radius 14) or 44 px glyph tile, name 22 DemiBold, origin line, facts (Kind/Size/Modified/Where with zero-width breaks after `/`), then the actions list = the context menu as rows (Enter's row in accent with a `↵` cap, risky rows in error colour with a warning glyph) | FilesPreview.qml; FilesWindow.qml:486-497, 2554-2574 | keep | |
| Context menu | 236 w rows 34 h radius 8 inside a 14-radius surfaceContainerHigh panel with hairline border, 6 px padding; opens from pointer with 150 ms fade + 0.94→1 scale; app icons for Open-with rows | FilesWindow.qml:2589-2658 | keep | |
| Actions (file) | Things.actions(p) (open, open in editor, show in Files, park, hand to agent, send to phone, copy path, forget origin) + Open with… (xdg-mime default first) + Unpack here (archives) + rowOps (Rename, Compress, Copy, Cut, Send to…, Move to trash, Delete for good) | FilesWindow.qml:506-547, 551-588; Things.qml:11-18 | keep (agent = herdr session; phone = skip unless kdeconnect) | |
| Actions (folder) | Open, Open in terminal, Pin/Unpin, Park on the shelf, Hand to agent, Copy path + rowOps; ground menu: terminal, new folder/file, paste, park, hand, copy path, forget habits | FilesWindow.qml:522-531, 609-617 | keep | terminal = kitty `-d` |
| Multi-selection actions | Rename…, Compress, Copy, Cut, Trash, Park, Hand to agent ("Look at these files…"), Copy paths | FilesWindow.qml:598-608 | keep | |
| Clipboard | Copy = `text/uri-list`; Cut = `x-special/gnome-copied-files` with "cut" first line (so Nautilus/Dolphin paste as move); paste reads either via `wl-paste --list-types` | FilesWindow.qml:1516-1604 | keep | same mime dance under Sway with wl-copy/wl-paste |
| Drag and drop | One window-level drag proxy (delegates may die mid-drag); drag image grabbed only once the hand moves; drop into folder row/rail/ground: internal = move, external = copy, Ctrl forces copy, Shift move; collision sheet "N already here" → Replace / Keep both / Skip | FilesWindow.qml:1238-1252, 1529-1613; FilesRow.qml:252-334 | keep | GPUIX DnD capability is a GAP (§6) |
| Jobs | Every change is a detached `setsid job.sh <id> <op> …` writing `$XDG_STATE_HOME/quickshell/user/files/jobs/<id>.json` ({state,total,done,bytes,bytesDone,current,error,results,undo}); ops: copy/move (policy replace|keep|skip), trash, restore, rename, renames, mkdir, touch, delete, compress, extract, moveback, restore-paths; cancel = touch `<id>.cancel`; outlives window/crash; status line shows it, Stop pill while running, **Undo pill for 60 s** after (Ctrl+Z) | job.sh:1-21; Jobs.qml:10-80; FilesWindow.qml:1254-1310, 1614-1625, 2526-2551 | keep | `job.sh` is bash+jq+gio+bsdtar: copy nearly verbatim into `home/dot_local/bin/` |
| Trash | gio trash; in-trash rows get "Put back" (root only) / "Delete for good"; delete always asks via sheet (Enter = safe button); "no trash on this disk" → offer delete | FilesWindow.qml:1463-1501; job.sh:31-47 | keep | |
| Status line | 15 px secondary ink: "12 items · 3 selected · 4.1 MB · matching "x" · hidden shown" or job label or reason (8 s) or "Can't: …" in error colour; right end "38 GB free" (13 px numbers) from `df` | FilesWindow.qml:715-753, 2526-2551 | keep | `Voice` phrasing (see §5) |
| Empty states | "Nothing here" / "Nothing matches" / "Nothing found" / "No permission to look in here"; folder deleted under window → go to nearest existing parent, reason "X is gone" | FilesWindow.qml:662-687, 2517-2523 | keep | |
| Picker mode | `files pick/pickdir/save/savefolder` IPC: window opens with a 52 h floating bar "Chrome wants a file · Pick a file [Cancel] [Choose]"; Choose filled accent pill appears only once something is picked; answer sent back over IPC as JSON list | Files.qml:81-116; FilesWindow.qml:2661-2740 | new (later) | Would need an xdg-desktop-portal FileChooser backend to serve Chrome — Tacit ships `tacit-portal`; out of tonight's scope |
| Save As window | Separate SaveWindow.qml (508 lines) with recent save-folder chips | SaveWindow.qml; Files.qml:104-110 | skip tonight | |
| Open-with | Lists desktop entries whose MimeType matches, default first, launches with `gio launch` | FilesWindow.qml:551-588 | keep | |
| Origins ("from") | Per-path index {kind, app, title, device, session, at}: download → browser title at the time, screenshot → window, phone, agent-written, copied-in-terminal; rows lead with the origin title over "document(3).pdf"; persisted, capped 600, pruned hourly | Origins.qml:10-60 | new (partial) | Tom: agent-written via herdr hooks; browser title via Sway IPC focused window at download time; this is the most "Tacit-only" feature |
| Devices | udisks monitor; click mounts and enters; eject = unmount (+ power off USB); failures surface in the status line | FilesRail.qml:466-498; FilesWindow.qml:1649-1666 | keep | `udisksctl` |
| Twins | Duplicate finder after load (size, then md5 of first+last 64 KiB) → offer pill | FilesWindow.qml:1348-1368 | keep | |
| IPC | `files open|another|toggle|reveal <p>|at <f>|act <name>|search <q>|shelf|pin|unpin|rename|move|windows` | Files.qml:347-372 | keep (as `gpuix-shell files …` CLI over shell.sock) | |
| Job → toast | A job finishing while no Files window is in front is announced by the notch ("copied" state, priority 70) | Files.qml:384-396 | keep → toast | |

### 3.2 The notch (Dynamic Island) — event model to keep, shape to drop

| Feature | What exactly | Where | keep/replace | Notes |
|---|---|---|---|---|
| Surface | Top-centre layer window per screen, fixed 860×540 (never resizes; mask clips input), exclusive zone 38 = 34 px header + 4; Top layer, Overlay only while media plays over fullscreen | Island.qml:33-104; Config.qml:550 | replace | Tom: "no top bar". The rail is the resting surface; peeks become toasts/OSD at bottom (SHELLS-DIGEST §4). |
| Header geometry | 34 h; centre = clock (116 w, +30 with status glyph); symmetric *wings* per state; radius 14 closed / 24 open, cove 6; open sheet 560 w | IslandController.qml:324-416 | replace | Wing widths table :337-388 is a good width budget for toast kinds |
| Priority queue | `request(name,data,priority)`: ≥ current priority preempts; lower queues FIFO depth 3 (oldest dropped); volume/brightness/workspace never queue (stale); re-firing the showing state refreshes payload and restarts hold (notifications queue instead of overwrite); `claudeAsk` yields to a meter and comes back first; `dismiss()` drops queued peeks older than 10 s except asks/notifications | IslandController.qml:182-284 | **keep** (in the toasts daemon) | This is the "event priority model" Tom's brief asks for; see §5 for the table |
| Priorities | greeting/reload 100, brief 90, battery 92, timerDone 88, chargerFault 85, charger 80, volume protection 80, volume/brightness 76, copied/devices 65-70, notification 60, download 55, network/bluetooth 50, track 45, workspace 30 | IslandController.qml (each request call) | keep | |
| Holds (ms) | greeting 4200, power 2600, battery 4000, meter 1300, notification 4000, network 2400, workspace 750, timerDone 3500, activity 30000, activityDone 2000, activityFail 4000, download (config), track/session 3000, brief 4000, copied 1200, claudeAsk 0 (waits), signedIn 2600, flow 120000, disk/pr 4000, memory 6000, notAnswering 3600000, wallpaper 7000, update 15000, updated 5000, layout 1500, chargerFault 5000, default 2000 | Config.qml:587-600; IslandController.qml:117-180 | keep | |
| Warm-up | First 900 ms after start ignored (services settle noisily), then greeting ("Morning, Tom.") + restart brief ("2 working · 1 waiting" / "repo uncommitted") | :526-545, 1637-1665 | keep (greeting optional) | herdr snapshot gives the brief |
| Ambient glyph | One status glyph at rest, first match wins: charger fault, recording, mic live, **agent waiting (back_hand)**, PR review, session just done (check), DND, charging, activity, disk ≥95 %, memory full, agent working (progress_activity), VPN, caffeine, bluetooth headset, shelf has items, unread, uncommitted >60 min, night light | :441-494 | keep → rail status cell | Maps 1:1 onto herdr states blocked ◉ / working ◐ / done ● |
| Hover/click | Hover 300 ms opens the sheet, leave closes after 100 ms; peeks do not open; click on a peek dismisses it; Esc closes | IslandContent.qml:26-33, 147-156 | replace | |
| Sheet rows | Frozen at open (no reflow under pointer): ≤6 rows (3 with player), sessions first (34 h + 26 per delegated agent, max 3, "+N more" 20), recents fill the rest, 9 px hairline between groups, 8 px bottom pad; room = 406 − 150 (player/shelf) or 12 − 36 (timer) | IslandController.qml:1553-1635 | keep → launcher "home" or rail flyout | Agent-session list is exactly herdr's workspace list |
| Shelf | Files dragged onto the notch are parked (persisted `shelf.json`, max 30, pruned); dashed 16-radius drop zone; Copy all / Clear; downloads auto-park | DropShelf.qml; IslandShelf.qml; IslandController.qml:1015-1068 | keep → rail "Shelf" + Files rail row | |
| Downloads watcher | bash loop every 2 s with `find -newer stamp` on ~/Downloads and the screenshot dir; partials sampled for size/rate; final name → origin recorded, parked, journaled, peek "name · on the shelf" (55) | :1026-1068 | keep (inotifywait is available on NixOS; same semantics) | |
| Media wings | Art left / spectrum right while playing; paused wings dim 3 s then fold; player "alive" for keepPausedMinutes (5) after pause; track change peeks 3 s | :32-105, 774-797 | replace → launcher Navidrome/MPRIS | |
| Meters | Volume/brightness/gamma peeks (76, hold 1300) with a 56×3 bar in the main ink; the OSD module is unloaded when the notch owns both | :799-855; StripBar.qml | replace → OSD at bottom | |
| Battery/charger | Low/critical announced only after holding 5 s (EC wake glitch); "Charging." / "Plugged in." / "Full. You can unplug."; chimes | :615-709 | keep | UPower |
| Network/BT | Wi-Fi connect/drop/off lines; per-device "X connected." / "X disconnected." by diffing the connected set; "Bluetooth on/off." | :886-987 | keep | NetworkManager/BlueZ via dbus-next |
| Workspace peek | "N" numeral, priority 30, hold 750 | :1004-1013 | skip (Tom's rail shows the workspace) | |
| Keyboard layout peek | 1500 ms | :1083-1103 | keep (small) | |
| Live activities | `island start/progress/end` IPC: 30 s pill then demotes to ambient glyph | :1104-1286 | keep (CLI `gpuix-shell notify --progress`) | |
| Not answering | Hyprland "app not responding" prompt drops out of the notch (520×34) | :1458-1511 | skip (Sway has no such event) | |
| Ask / address / sign-in | Quick Claude chat sheet (600 w), browser Ctrl+L sheet, browser sign-in popup under a hole in the notch (Thyris integration) | states/IslandAsk.qml, IslandAddress.qml, IslandSignin.qml | skip (Thyris-specific); Ask → `gpuix-shell ask` | |
| Dictation/sand | Native Tacit.Sand visualiser for flowd | SandLayer.qml | skip | |

### 3.3 Notifications

| Feature | What exactly | Where | keep/replace | Notes |
|---|---|---|---|---|
| One panel, one corner | Top-right (configurable), always-mapped transparent layer of fixed size (410+40 w), input mask only over the panel or the 410×60 "door" | NotificationPopup.qml:27-90, 121-146 | replace (SHELLS-DIGEST: 390 w, max 4) | |
| Popups | Rows drop out of the corner (y −12→0 on emphasizedDecel 500 ms + fade 200 ms), newest rows shown whole, rest wait in the centre; panel clips at 55 % screen | NotificationPopup.qml:148-187, 264-275; NotificationPopupList.qml:294-337 | keep | |
| Centre | Hover the door/panel 300 ms (not while popups show) or click its edge → grows into the centre: header "Notifications · N" + silent toggle + clear all; leave 100 ms → closes; Esc closes | :107-119, 189-262 | keep → `gpuix-shell notifications` window toggled from the rail | |
| Reply | Inline reply field → layer takes exclusive keyboard while typing, OnDemand while open | :58-66 | keep | |
| Grouping | By appName; expand/collapse; drag-to-dismiss (70 px threshold, neighbours follow 30 %/10 %) | NotificationItem.qml:26-68; NotificationGroup.qml | keep | |
| Row tools | Close/mute/copy appear on hover only; at rest only the app's actions | NotificationItem.qml:13-16 | keep | |
| Timeout | 7000 ms default | Config.qml:759 | keep | mako today: Tom's value in `home/vicinae.nix` |
| Urgency | critical → "notifyUrgent" tone (still no heavy colour: words in main ink) | IslandController.qml:869-883 | keep | |
| Island takeover | If the notch shows notifications the popup stands down but the centre + IPC stay | :45-54 | n/a | |
| IPC | `notifications expand <app>|open|close|toggle|count|silent|setSilent` | :322-337 | keep | |

### 3.4 OSD

| Feature | What exactly | Where | keep/replace | Notes |
|---|---|---|---|---|
| Trigger | Any volume/mute/brightness/gamma change → `osdVolumeOpen` for 1000 ms (restart on each) | OnScreenDisplay.qml:45-109; Config.qml:764 | keep (bottom, margin 96) | Tom's `osd`/`volume`/`brightness` scripts call the CLI |
| Shape | Pill (full radius) on layer0: 40 px round icon tile (secondaryContainer) + StyledSlider (M) + 46 px value tile (tertiaryContainer, 16 px tnum) ; width 180 + margins | OsdValueIndicator.qml:266-341 | replace visuals: one neutral pill, 3 px track in main ink like StripBar | Tacit's own notch meter (StripBar) is quieter than this ii-era OSD; copy the notch version |
| Hover dismiss | Pointer entering the OSD hides it | :154-158 | keep | |
| Protection | "Volume held back · reason" error pill when the sink protection trips (max +10 %, cap 99 %) | :98-109, 174-211; Config.qml:204-209 | keep | |
| Screen | Follows focused monitor | :16, 120 | keep | Sway: eDP-1/eDP-2 |

### 3.5 Control panel (sidebarRight) + Wi-Fi + Bluetooth

| Feature | What exactly | Where | keep/replace | Notes |
|---|---|---|---|---|
| Panel | Bottom-right docked, 460 w, as tall as content (≤ screen − 38), rises out of the bottom edge on DefaultSpatial, Esc/click-outside closes; OnDemand keyboard | SidebarRight.qml:64-131; SidebarRightContent.qml:21-36 | replace → `gpuix-shell controls` overlay beside the rail | |
| Contents | One row of icon pills (wifi, vpn, bluetooth, notifications, night light, mic, caffeine, "…"), brightness + volume sliders, hairline, date · tasks line (calendar/todo/timer in place), hairline, settings ⋯ session | SidebarRightContent.qml:21-36, 140-160 | keep (minus todo/pomodoro unless wanted; Tom has `pomodoro` script) | |
| Pill states | "on" pill = onSurface 12 % wash (raised), hover 16 %; right-click a pill with a list opens its section; sections are mutually exclusive | :61-65, 47-60 | keep | |
| Wi-Fi section | Header "Wi-Fi" + switch; hairline doubles as scan progress; rows 40 h (signal, name, state), max 6 then scroll; secure network without profile unfolds a password line under the row, Enter connects; scan starts 500 ms after unfold, rescans every 15 s while open; errors inline | WifiSection.qml:10-140 | keep (`nmcli` as Tom's `fzf-nmcli` does) | |
| Bluetooth section | Header + switch (pending state held until BlueZ confirms, 4 s watchdog → "did not turn on"); discovery + pairable start 500 ms after unfold, retried every 900 ms ×8; rows 40 h: click connects/disconnects (trust first), right-click unfolds forget/keep-paired; 12 s wait → "Did not answer" / "Confirm on the device"; "Show N unnamed" row | BluetoothSection.qml:11-330 | keep | |
| Night light, VPN, mixer | NightLightSection (hyprsunset), VpnSection (nmcli import), AudioSection + VolumeMixerEntry per stream | sidebarRight/* | keep (gammastep/wlsunset for Sway; `wpctl`) | |

### 3.6 Bluetooth pairing sheet (agent questions)

| Feature | What exactly | Where | keep/replace | Notes |
|---|---|---|---|---|
| Agent | `quiet-btagent` (external) holds `org.bluez.Agent1`, talks JSON over `$XDG_RUNTIME_DIR/bt-agent.sock`: `{ev:"ask", id, kind, device, address, code}` / `{ev:"hide"}`; answers `ok <id>`, `no <id>`, `value <id> <pin>`; rejects when no shell connected; socket rebuilt every 2 s until connected | BluetoothAgent.qml:21-66, 85-105 | keep (gpuix-shell can export the Agent1 object itself via dbus-next; no helper needed) | |
| Kinds | confirm (same code on both screens), authorize (no code; "only accept a device you just put in pairing mode"), service (a paired device asks for a service), pin (typed; "older keyboards use 0000"), passkey (digits typed), display (code to type on the other device; only "Hide") | BluetoothPairContent.qml:81-89, 246-291 | keep (copy the copy) | |
| UI | Full-screen overlay (exclusive keyboard while asking), 50 % scrim, sheet "opens down out of the notch": 560 w, header 34 with the time, bluetooth glyph 26 accent, title 17 "Pair with X?", address in mono when it differs, explanatory line, hairline, **code 44 px numbers letterSpacing 8**, PIN field 46 h transparent, footer hint "Enter pairs · Esc refuses", quiet "Refuse" text action, filled 44 px accent disc with check | BluetoothPairContent.qml:157-391 | replace shape (a centred modal), keep content and keys | Enter armed only 600 ms after the sheet is up (:103-132) — keep that guard |
| Lifetime | Window lingers 450 ms after answer for the fold; not shown while locked (agent holds the ask, helper gives up after a minute) | BluetoothPairing.qml:9-39 | keep | |

### 3.7 Palette / overview / session

| Feature | What exactly | Where | keep/replace | Notes |
|---|---|---|---|---|
| Palette | Docked into the bottom edge; field never moves, results rise out of it, best nearest; one line per row 52 h: 34 px tile (radius 11) at x22, title main ink, "word" at the row end in meta ink (what it is / where it lives), chosen row shows its verbs there (→/← step verbs), sand wash = what Enter does | SearchWidget.qml:15-26; SearchItem.qml:13-120 | replace geometry (Tom: overlay top margin 108, 700×580) keep the row grammar | |
| Kinds | All, apps, files, recent, clipboard, emoji, keybinds (`<`), actions, calculator, symbols, dictation (`'`), shell command, web; Tab steps kind; a question-like query puts "Ask Praxis" first; a sum is answered in the field, not as a row | SearchWidget.qml:236-331 | keep (sections map onto the Vicinae replacement) | |
| Debounce | 45 ms query timer; rows rebuilt once per event-loop turn (binding rebuilt 19–45×/letter before) | :70-78, 269-328 | keep | |
| Dock | Touching the bottom edge raises a dock (same shape, a row of programs); first letter turns it into search | Overview.qml:36-66; PaletteDock.qml | skip | |
| Workspace grid | Super+Tab grid 2×5 at 0.18 scale | Config.qml:783-790; OverviewWidget.qml | skip (Mod+i switcher exists) | |
| Session screen | Rises in the bottom-right corner (same silhouette as the control panel) over a 30 % scrim; 4 big choices (Shut down, Restart, Sleep, Lock) + 4 small text (Log out, Hibernate, Firmware, Tasks); focus starts on Lock; destructive four need a second press; stays up "Shutting down" until the session dies or systemctl refuses | SessionScreen.qml:14-130 | keep (as `gpuix-shell power`) | |

### 3.8 Bar (for completeness; off in Tacit)

Bar.qml/BarContent.qml are the ii bar: 40 px (vertical 46), left/centre/right groups of
loaders (workspaces 26 px buttons with occupied pills, active window, media, clock, resources,
tray, battery, utility buttons, power). `Config.options.bar.enable` is **off** and
`island.hideBar` true (Config.qml:452-453, 545-549); the family only loads it when the notch is
off (IllogicalImpulseFamily.qml:81-83). Nothing here is Tacit's aesthetic — skip, Tom's rail is
the bar.

---

## 4. Design values

All MEASURED unless stated. Source files: `T/modules/common/Appearance.qml` (A), `Tacit.qml`
(K), `Config.qml` (C), widgets as named.

### 4.1 Spacing scale (A:349-361)

| token | px | used for |
|---|---|---|
| tiny | 4 | glyph↔text gaps, toolbar spacing |
| verysmall | 6 | pill inner gaps |
| small | 8 | row wash inset, column padding, notification panel pad |
| smallish | 10 | menu row glyph inset |
| normal | 12 | window outer margin, row glyph inset, text-field padding |
| panel | 14 | frosted panel content inset (control panel) |
| large | 16 | status row left |
| verylarge | 20 | preview column left inset, rail label x |

Measured Pinax insets beyond the scale: window body margin 12 (FilesWindow.qml:1899), header
left 8 / top 4, hairline margins 8, list margins 8, status 16/12, preview 20/8/12, rail glyph x20
label x44 (FilesRail.qml:282-291), row glyph x12 name x46 (FilesRow.qml:110,120), menu text x38.

### 4.2 Radii (A:276-291, K:45-49)

| token | px | where |
|---|---|---|
| unsharpen | 2 | |
| unsharpenmore / rename-field | 6 | inline rename field (FilesRow.qml:143) |
| verysmall / **row** | 8 | every row wash, ToolGlyph, menu rows, sheet rows |
| chip / rowSlab | 10 | grid art tile, preview glyph tile, rename-sheet fields |
| small / slab | 12 | grid cell wash, gallery tiles, Slab |
| card / panel | 14 | rail overlay panel, context menu, preview picture |
| normal | 17 | ii text fields |
| windowRounding / pick bar / sheet | 18 | floating sheets |
| Pinax body | 20 | compositor clip cap (FilesWindow.qml:1788-1790) |
| large | 23 | screen rounding |
| open notch | 24 | |
| verylarge | 30 | docked panels (control panel, notification panel) |
| full | 9999 | pills, round buttons |

Tom's brief already says "rounded 8/12 inner corners" — matches row 8 / slab 12 / panel 14.

### 4.3 Type (A:293-335, K:35-43, C:169-177)

| Tacit | px | weight | Tom (INFERRED) |
|---|---|---|---|
| family main/numbers/title | Tacit Sans (variable, wght 450 body, 550 title) | | **Anthropic Sans** 12 UI per BRIEF §3.5; numbers/figures → AnthropicMono Nerd Font with `tnum` |
| monospace | Tacit Code | | AnthropicMono Nerd Font |
| icons | Material Symbols Rounded + Tacit's own symbol font (one weight) | FILL axis, opsz = size | Anthropicons where a glyph exists, else Material Symbols Rounded |
| rendering | `hintingPreference: PreferNoHinting`, NativeRendering, patched Qt linear-light blending (StyledText.qml:226-235) | | gpuix text stack; no hinting if the API allows |
| K.size.alarm | 40 | | (pairing code 44, letterSpacing 8) |
| K.size.headline | 30 | | |
| K.size.section | 22 | DemiBold | preview title |
| K.size.body | 17 | | pairing title |
| **K.size.row** | **15** | Normal; Medium when current/selected | rail rows, file rows, menu rows, status, Slab word |
| K.size.meta | 13 | | crumbs, counts, ages, section labels (DemiBold), column heads |
| A.pixelSize ladder | 10 / 12 / 13 / 14 / 15 / 16 / 16 / 17 / 19 / 22 / 23 | | header title 16 DemiBold; search field 15; hit rows 16/14; rename field 16 |
| A.icon | 13 / 16 / 18 / 20 / 24 | | rail/menu glyph 18, row/header glyph 20, hit glyph 22, pairing 26, preview 56 |

Weights in use: Normal (450), Medium (500 — selected row name, current rail row, clock), DemiBold
(section labels, titles, pick "Choose", status pills), never Bold.

### 4.4 Colour roles and how matugen maps (A:87-274, K:13-33)

Tacit's palette is matugen "scheme-content" from the wallpaper (C:195-199). The default (dusk)
dark values baked into Appearance.qml:87-159, for calibration only:

| m3 role | hex | role in the UI |
|---|---|---|
| background / surface / surfaceDim | #141313 | window ground (Pinax uses the terminal bg at 85 %) |
| surfaceContainerLowest | #0f0e0e | |
| **surfaceContainerLow** | #1c1b1c | K.ground: "the ground slabs and panels stand on" |
| surfaceContainer | #201f20 | dialogs (opaque), pick bar |
| **surfaceContainerHigh** | #2b2a2a | menus, sheets, rail overlay, panel frost base |
| surfaceContainerHighest | #363435 | search field fill, rename field |
| surfaceBright | #3a3939 | switch track off |
| onBackground / onSurface | #e6e1e1 | ink source; washes = onSurface at 5/10/12 % |
| onSurfaceVariant | #cbc5ca | colSubtext (~7:1) |
| outline | #948f94 | placeholder |
| outlineVariant | #49464a | hairlines (colLayer0Border = mix(outlineVariant, layer0, 0.4)), keyboard-cursor ring |
| primary | #cbc4cb (dusk "sand") | K.accent: Enter's action, where-you-are tick, drag ring, focus edge (@60 %) |
| onPrimary | #322f34 | text on filled accent pill |
| secondaryContainer / on | #4d4b4d / #ece6e9 | text selection, search-hit current row |
| error / onError | #ffb4ab / #690005 | K.risk: delete/replace buttons, "Can't:" lines, taken-name field |
| success | #B5CCBA | tone only (not words since 2026-10-15) |
| inverseSurface / inverseOnSurface | #e6e1e1 / #313030 | tooltips |

Ink levels (A:161-176, K:14-18) — **text by brightness, never by opacity**, solved by APCA on
surfaceContainerLow so they survive any palette:

| ink | definition | use |
|---|---|---|
| inkMain | APCA Lc 92 | names, titles, chosen rows |
| inkSec | mix(inkMain, Lc85, 0.25) | rail labels at rest, origin lines, section labels, status |
| inkMeta | mix(Lc85, Lc75, 0.4) | ages, sizes, counts, crumbs, column heads |
| inkFaint | Lc 60 | placeholders |
| hairline | Lc 16 | dividers (drawn at 0.4–0.5 opacity on top) |
| raised / raisedHot | mix(inkMain, ground, 0.11 / 0.17) | a slab lifted from the ground |

Washes (transparentize of onSurface): hover 0.95 (5 %), menu/sheet hover 0.90 (10 %), current
rail row 0.9 (10 %), selected row/cell 0.88 (12 %), pill-on 0.88 / hover 0.84, tiles 0.92 (8 %),
band fill primary 0.85 + 1 px primary border, reveal flash primary 0.18 fading 1200 ms, drop
ground primary 0.06.

Translucency to **drop** for Tom (no blur/frost): colPanelFrost = surfaceContainerHigh @ 0.76
(A:242-247); control panel @ 0.92 (SidebarRightContent.qml:122-125); Tacit app windows @ 0.85
(K:31-33, FilesWindow.qml:1769-1791); Hyprland layer rules `blur=true ignore_alpha=0.64` for
island/sidebarRight/notificationPopup/polkit/saveAs, 0.89 overview (`T/../hypr/tacit/rules.lua:25-38`).
Replace every frost with the opaque token of the same role.

Mapping onto Tom's themes (INFERRED, to be fixed by the theme-fragment author):

| Tacit role | noir | claude-dark / claude-light |
|---|---|---|
| ground (surfaceContainerLow) | `bg` = #000000-adjacent panel tone from `home/themes/noir.nix` | Primer-ish canvas tokens |
| surfaceContainerHigh (menus) | one step lighter neutral | canvas.overlay |
| onSurface | `fg` | fg.default |
| onSurfaceVariant | fg muted | fg.muted |
| outlineVariant | border | border.default |
| primary (accent) | the noir accent (restrained) | Claude orange / accent.fg |
| error | red | danger.fg |

The APCA solver (`inkFor`, A:56-69, 18 bisections of mix(ink, ground) then toward white/black)
is ~15 lines of pure math; precompute the five inks per theme in the Nix fragment instead of at
runtime.

### 4.5 Motion (A:363-542, widgets)

Curves are cubic-bezier `[x1,y1,x2,y2]`:

| name | curve | ms | used for |
|---|---|---|---|
| expressiveFastSpatial | 0.42, 1.67, 0.21, 0.90 | 350 | peeks/width morphs, grid cell resize, menu scale-in, rename-sheet appear |
| expressiveDefaultSpatial | 0.38, 1.21, 0.22, 1.00 | 500 | elementMove (rows reflow), panel slide-in, notch open, popup row drop |
| expressiveSlowSpatial | 0.39, 1.29, 0.35, 0.98 | 650 | |
| expressiveFastEffects | 0.31, 0.94, 0.34, 1.00 | 150 | fades (menu opacity, folder-change fade 0.3→1, gallery image in) |
| expressiveDefaultEffects | 0.34, 0.80, 0.34, 1.00 | 200 | elementMoveFast (colour/opacity), section fades |
| expressiveSlowEffects | 0.34, 0.88, 0.34, 1.00 | 300 | |
| emphasized | 0.05,0, 2/15,0.06, 1/6,0.4, 5/24,0.82, 0.25,1, 1,1 (multi-segment) | 300 (elementResize) | section unfold heights (Wi-Fi/BT lists) |
| emphasizedDecel | 0.05, 0.7, 0.1, 1 | 400 (enter) / 450 (notch fold) | element enter, dialog in, popup drop |
| emphasizedAccel | 0.3, 0, 0.8, 0.15 | 200 (exit) | element exit, dialog out, wing fade-out |
| standard | 0.2, 0, 0, 1 | 400 | settled sheets |
| standardDecel | 0, 0, 0, 1 | 200 scroll / 300 sidebar enter | ripple, scroll |
| standardAccel | 0.3, 0, 1, 1 | 250 sidebar exit | |
| durations | small 200 · normal 400 · large 600 · extraLarge 1000 | | |
| menuDecel | OutExpo | 350 | |
| clickBounce | DefaultSpatial | 400 | |

Micro-timings measured in Pinax/notch: hover wash ColorAnimation 80 ms (FilesRow.qml:67), tool
wash 90, focus ring 120, rail label fade 140, Slab press scale 0.97 over 120 ms OutCubic + colour
140 (Slab.qml:34-50), switch thumb 320 ms on `[0.42,1.5,0.28,0.95]` (StyledSwitch.qml:497-510),
ripple 1200 ms standardDecel (RippleButton.qml:19), sheet enter y from bottom 220 ms OutCubic +
fade 160, exit 120 (FilesWindow.qml:2767-2768), rail hover-open 160 ms / fold 260 ms, notch dwell
300 / leave 100, header wing crossfade 100 out · 80 hold · 140 in (IslandHeader.qml:51-79),
clock digit roll staggered 40 ms per digit (StripClock.qml:6-33), scrollbar fade 350 ms, 4 px
thumb at 50 % only while hovered/pressed (StyledScrollBar.qml).

Tom's rule of thumb (INFERRED): 80–140 ms for colour, 150–200 ms for fades, 350 ms for width
morphs, 400–500 ms for things that move, nothing above 650 ms; no spring overshoot on exit.

### 4.6 Layout proportions (surfaces)

| surface | measure | source |
|---|---|---|
| Pinax window | default 1000×640, min 640×400, body radius 20, margin 12; rail 248/60; preview 300 (+8 gap) auto ≥1240 w or ≥900×800; rail compact <720; sort word compact <900; search 140–230 (30 % w) × 36 | FilesWindow.qml:37-39, 491-496, 1897-1905, 2122-2123, 2559 |
| rail row / label | 32 h / 34 h; "Now" label 30 | FilesRail.qml:232-362 |
| list row / hit row / menu row / sheet row / preview action | 34 (48) / 46 / 34 / 38 / 34 | FilesRow:50, FilesWindow:2352, 2615, 2799, FilesPreview:210 |
| header / columns / status | 44 / 28 / ~24 | FilesWindow.qml:1972, 2191, 2527-2533 |
| grid / gallery | cell 156×176 (+120/+100 per size step), art 120×100; strip 96, tile 88×96, art 72 | FilesCell.qml, GalleryView.qml:117-182 |
| context menu | 236 w, pad 6, radius 14 | FilesWindow.qml:2590-2615 |
| sheet / rename sheet | ≤460 w (body−80), pad 18, radius 18, 48 above foot / ≤560 w, 56 above foot | :2744-2760; RenameSheet.qml:22-24 |
| pick bar | 52 h, radius 18, 40 above foot | :2664-2674 |
| Slab | 40 h accent (ring 1.5 px accent@75 %), 36 h quiet (1 px inkMain@42 %), large 50/44, min width 104/190 | Slab.qml:28-49 |
| notch | header 34, reserve 38, centre 116(+30), wings 32–204, open 560 w, window 860×540 | IslandController.qml:330-416; Island.qml:78-79 |
| control panel | 460 w, cove 12, radius 30, pad 14, rows 40, max 6 rows | SidebarRight.qml:67; SidebarRightContent.qml:39-40 |
| notification panel | 410 w (+40), cap 55 % h, pad 8, radius 30, fillet 12, centre header 34 | NotificationPopup.qml:82-83, 150-187 |
| OSD | 180 + 4×10 + 80 w, pill | OsdValueIndicator.qml:266 |
| bar (off) | 40 h / 46 w vertical, ws button 26 | A:547, 567; Workspaces.qml:24 |
| ii sizes | sidebar 460/750, media 440×160, search 210/360, wallpaper selector 1200×690 | A:546-574 |

---

## 5. Reusable code and data (exact paths)

Everything is QML/bash in the Tacit archive; nothing links into gpuix directly. What is worth
porting, by value:

| What | Path | How to reuse |
|---|---|---|
| **Job runner** (copy/move/trash/restore/rename/renames/mkdir/touch/delete/compress/extract/moveback/restore-paths with JSON progress + undo + cancel file) | `T/scripts/files/job.sh` (bash, needs jq, gio, bsdtar, python3 for URL-decoding) | Copy to `home/dot_local/bin/files-job` almost verbatim; change the report dir to `$XDG_STATE_HOME/gpuix-shell/files/jobs`. The Files surface only needs to spawn it and watch the dir. |
| Jobs watcher semantics | `T/services/Jobs.qml:1-80` (download sampling, 2.5 s reaper, `startedHere`, `jobFinished`) | Port to `src/files/jobs.ts` with `fs.watch` on the jobs dir |
| **Voice** (one phrasing for ages/sizes/counts/facts/because/can't) | `T/services/Voice.qml` (66 lines) | Port 1:1 to `src/shared/voice.ts`; use in toasts, Files status, launcher rows |
| Things (kind by extension, glyph per kind, describe, actions in one order) | `T/services/Things.qml:23-76` | `src/files/things.ts` |
| Origins (per-path provenance index) | `T/services/Origins.qml` | Later; the schema `{kind, app, title, device, session, at}` and `describe()` strings (:41-57) are the keeper |
| DropShelf (persisted parked-file list, max 30, prune missing, IPC add/remove/clear) | `T/modules/common/widgets/DropShelf.qml` | `src/shared/shelf.ts` + `gpuix-shell shelf add|clear` |
| Search grammar + fd command builder | `FilesWindow.qml:858-981` | `src/files/search.ts` (pure, testable) |
| Crumbs, decideView, gridSizes, selection/band/cursor-by-path, Esc ladder, key map | `FilesWindow.qml:1056-1252, 1798-1895` | `src/files/state.ts` + `*.test.ts` |
| Clipboard mime dance (cut = `x-special/gnome-copied-files`) | `FilesWindow.qml:1502-1604` | `src/files/clipboard.ts` with wl-copy/wl-paste |
| Open-with probe (xdg-mime + desktop grep, default first) | `FilesWindow.qml:560-588` | shell snippet reusable as-is |
| Twin finder | `FilesWindow.qml:1355` (one-line awk/md5 pipeline) | reuse as-is |
| Large & old / Recent find pipelines | `FilesWindow.qml:779, 832` | reuse as-is |
| Notch priority queue (request/enqueue/activate/dismiss/cancelState + hold table) | `T/services/IslandController.qml:107-290` | `src/notifications/peeks.ts`: the toasts daemon's scheduler; priorities/holds table in §3.2 |
| Ambient glyph ladder | `IslandController.qml:441-494` | the rail's status cell ordering |
| Sheet row budget (frozen snapshot, 34/26/20 px costs) | `IslandController.qml:1553-1635` | launcher/rail flyout row budget |
| Downloads watcher loop | `IslandController.qml:1029` | replace with inotifywait; keep the partial-file filter and 60 s dedupe |
| Bluetooth pairing copy + kinds + Enter arming | `T/modules/ii/bluetooth/BluetoothPairContent.qml:81-132, 246-291, 336-366` | copy strings; implement Agent1 via dbus-next |
| BT connect/pair retry timings (900 ms ×8 discovery, 12 s wait, 4 s power watchdog, trust-before-connect) | `BluetoothSection.qml:70-126, 272-330` | same constants in `src/controls/bluetooth.ts` |
| Wi-Fi section behaviour (scan 500 ms after unfold, 15 s rescan, password line under row) | `WifiSection.qml:54-83` | `src/controls/wifi.ts` |
| Session screen actions + two-press + waiting word | `SessionScreen.qml:76-123` | `src/power/` |
| Palette row grammar and kind list | `SearchItem.qml:13-95; SearchWidget.qml:236-258` | launcher rows |
| DockedRect silhouette (coved edge panels) | `T/modules/common/widgets/DockedRect.qml` | **not** for Tom (flat panels, no coves) |
| Slab (ring button, default/risk/quiet) | `T/modules/common/widgets/Slab.qml` | port as `<Slab tone>` in the gpuix kit: 40/36 h, ring 1.5/1 px, Medium word for the default |
| Appearance tokens (whole file) | `T/modules/common/Appearance.qml` | the §4 tables are its extraction; the `gpuix-shell.json` theme fragment should carry: inks ×5, hairline, accent, risk, ground, raised, menu, field, radii {row 8, tile 10, slab 12, panel 14, sheet 18, pill 9999}, spacing ladder, font sizes {meta 13, row 15, title 16, section 22}, curve table |
| Matugen template (which m3 roles the shell reads) | `/home/tom/saturday-tacit/iso-files/usr/share/tacit/matugen/templates/colors.json`, config `…/matugen/config.toml` | role names only; Tom generates nothing from wallpaper |
| Preview launcher (how Pinax ran standalone) | `/home/tom/saturday-tacit/preview/{pinax-preview.qml,start-native-apps}` | reference for a future side-by-side check of the GPUIX Files against the original |

---

## 6. Gaps and unknowns

- **GPUIX capabilities untested for Pinax**: native drag-and-drop (text/uri-list source + drop
  target), clipboard with custom mime types, pinch gestures, image decoding/thumbnails at scale,
  `OpacityMask`-style rounded image clipping, per-row text eliding (ElideMiddle). The 0.11.0
  `index.d.ts` must be checked before promising DnD or the gallery (BRIEF §2 row "gpuix upstream").
  Unverified tonight.
- **Fonts**: Tacit's look depends on an unhinted, linear-light text pipeline (StyledText.qml:226-230,
  README.md:39 "patched Qt text implementation"). Whether gpuix's text renders Anthropic Sans at
  13–15 px as cleanly is unknown; the 142-PPI note (A:320) means Tacit tuned sizes for a high-DPI
  panel — on the Zenbook check 15 px row type against 14.
- **Tom's exact "vanilla" preference** is not itemised: TACIT-OVERVIEW.md:25 says he "did not
  specify which individual visual details or interactions he liked most". My §2 reading
  (restraint, washes, hairlines, accent-for-Enter) is INFERRED.
- **Notch vs "no top bar"**: Tacit's whole event surface is top-centre; Tom's shell has a left
  rail and bottom OSD. Where peeks (battery, network, downloads, agent waiting) land in Tom's
  layout is a PLAN decision; I assumed toasts top-right + rail status cell.
- **Origins**: the provenance index needs hooks Tom does not have yet (browser title at download
  time, agent write hooks). herdr could supply the agent half; the browser half needs Sway IPC
  polling at the moment a file lands. Marked "new (partial)".
- **Picker/portal**: Tacit's `files pick` works because Tacit ships its own
  xdg-desktop-portal backend (`tacit-portal`, README.md:45). For Chrome to use a GPUIX file
  picker Tom would need a portal FileChooser implementation — out of scope tonight, but it is the
  thing Tom asked of otto on 2026-10-06 ("want to make sure that google chrome itself can
  leverage it").
- **Graphis / Praxis** (editor, agent UI): not read beyond the screenshot; Tom said only the file
  explorer interests him. Praxis's `SessionList.qml` is the source of the rail row measures
  ("measure for measure", FilesRail.qml:229-231) — the same 32 h / 15 px / sand-tick row would be
  the natural herdr session row; I did not open `T/modules/claude/`.
- **Native pieces not in the archive**: ThumbnailImage, Tacit.Sand, Tacit.Edit are compiled
  plugins (README.md:14); only their QML call sites exist.
- **No benchmarks / runtime observation**: everything here is static reading plus one
  screenshot. Hover timings, overshoot feel and the 60-second undo window were not experienced.
- Verification: single reader, no second pass (per the standing "go light on verification"
  rule). Line numbers were taken from `cat -n`/`awk` output at read time.
