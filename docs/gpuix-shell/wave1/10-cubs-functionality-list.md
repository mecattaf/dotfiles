# 10 — CUBS functionality list (the Views-shell scoping, read for the GPUIX/Sway shell)

Reader: Claude (Fable 5.1), wave 1 of the overnight gpuix-shell build, 2026-10-20/21.
Source read in full: `/home/tom/mecattaf/cubs` at `a72fe27` (18 commits, all dated 2026-10-01).
Labels: **MEASURED** = read directly in the named file at the named line; **REPORTED** = the file
claims it (unverified by me tonight); **INFERRED** = my mapping or judgement. Every pointer is
`path:line` relative to `/home/tom/mecattaf/cubs` unless absolute.

What this note is for: the BRIEF (`docs/gpuix-shell/BRIEF.md:84`) names CUBS as "the earlier
Chromium-Views shell scoping; the functionality list". Tom (2026-10-20): "having a comprehensive
list of all the options is important." This note is that list, in tables, with each row mapped to
what it becomes in the GPUIX + Sway shell of BRIEF §3.

---

## 1. What this source is

| Fact | Value | Label |
|---|---|---|
| Repo | `/home/tom/mecattaf/cubs`, BSD-3, "CUBS" is a placeholder name with no expansion | MEASURED `README.md:3-5`, `docs/naming.md:23-30` |
| Date | All 18 commits on 2026-10-01 between 13:11 and 16:25 CEST (`git log`) | MEASURED |
| What it scoped | "a standalone desktop shell for Wayland … in Chromium Views C++ on wlr-layer-shell surfaces" beside a compositor someone else maintains; scroll default, sway "rides with scroll", niri, Hyprland, generic ext-workspace | MEASURED `README.md:3-11`, `:46-52` |
| Shape | one process, three faces to the same command ids: Views on layer-shell; a Chrome MV3 extension (control pages in tabs, native messaging); the `cubs` CLI over `$XDG_RUNTIME_DIR/cubs/cubs.sock` | MEASURED `README.md:22-37`, `docs/architecture.md:36-38` |
| Status when frozen | "foundation": specs, schemas, a validator (`tools/validate.sh` prints `VALIDATE-OK`), example plugins, three theme dirs, extension skeleton, lifted C++ that compiled in other trees at Chromium 148/149/150 but "does not build here yet". No shell ever ran from this repo. | MEASURED `README.md:149-162`; REPORTED for "compiled in its original trees" |
| Lineage | agency-mvp (private, Chromium 150.0.7871.124, Views bar on niri, launcher with typed input on headless sway, read-only rail mirror of niri) and the June-30 spike (Chromium 149, Views on a layer surface with translucency/paint/keyboard) | REPORTED `shell/PROVENANCE.md:13-16` |
| The one thing that ever switched a workspace | the 2026-06-27 web switcher (180 lines JS on a layer surface, `niri msg` subprocesses). "No Views switcher has ever switched a workspace." | REPORTED `shell/PROVENANCE.md:21-34`, `shell/docs/ccd-switcher-behaviour.md:3-10` |
| Why it matters tonight | It is the most complete enumeration Tom has signed off of what a shell must do: surfaces, quick-settings items, producers, command ids, plugin tiers, compositor capabilities, keybinding rendering, theme input. The rendering stack (Views) is dead; the functionality list is not. | INFERRED, consistent with BRIEF §1 "functionality pull from quickshell NOT visuals" |

Superseded by Tom's 2026-10-20 rulings (BRIEF §1): the Views/Chromium renderer (→ GPUIX), scroll as
default (→ Sway only), the Chrome extension as the settings face (→ undecided; see §6), "no file
manager" (→ Tom now wants a Pinax-like file explorer, see §2 and §6).

---

## 2. Verbatim Tom rulings in this source (all 2026-10-01 unless noted)

The repo paraphrases Tom rather than quoting him; the git history has no transcript. Where the
text says "(Tom, 2026-10-01)" it is a ruling the author recorded the same day. Quoted verbatim
from the files, with the date the file gives.

| # | Ruling (verbatim from the file) | Where | Status for the GPUIX shell |
|---|---|---|---|
| T1 | "P1 A Views file selector served as the portal's file chooser — **Out** (Tom, 2026-10-01). Google did not build one in Views, Tom will not, and it is rarely used. Nautilus serves the chooser through `xdg-desktop-portal-gnome`." | `docs/open-decisions.md:14` | KEEP for the chooser (portal → Nautilus/GTK chooser). |
| T2 | "P2 A Views file manager — **Out** (Tom, 2026-10-01), for the same reasons. Nautilus stays." | `docs/open-decisions.md:15`, `docs/rules.md:27-31` (R3) | **CHANGED 2026-10-20**: "in my case what is of interest is mainly the file explorer" (BRIEF §1). The newer ruling wins; `gpuix-shell files` is an ordinary window, not a layer surface. Record in ASSUMPTIONS. |
| T3 | "P7 Whether the old expansion appears anywhere public — **Closed** (Tom, 2026-10-01): the expansion is dead and appears nowhere." / "An earlier draft spelled out an expansion containing a Google mark; that expansion is dead (Tom, 2026-10-01)." | `docs/open-decisions.md:16`, `docs/naming.md:30-33` | Moot (new product name `gpuix-shell`). |
| T4 | "Tom has said CUBS is not the final name. A Views-adjacent name is welcome ('views-shell' was not so bad)." | `docs/naming.md:25-27` | Moot. |
| T5 | "Tom's ruling (2026-10-01): No release history. Before v1 there are no tags, no changelog, no version numbers and no compatibility promises. Tom daily-drives `main` on both seats; that is the test." | `docs/chromium-hop.md:10-14`, R27 `docs/rules.md:166-170` | KEEP the spirit: no versioning ceremony; the branch is daily-driven once Tom activates it. |
| T6 | "`#000000` is simply the background of Tom's `noir` theme; a light theme works." / "`#000000` is not a rule: it is the `background` of Tom's `noir` theme" | `README.md:91-92`, `style/tokens/README.md:7-9` | KEEP: noir default, claude-light must work (BRIEF §1 "switch to claude 'light and dark' variants"). |
| T7 | "GTK keeps its own theme (MacTahoe on Tom's seats); CUBS never writes GTK CSS." / "on Tom's seats that is MacTahoe, which is non-negotiable; no libadwaita stylesheet is generated." | `README.md:93-94`, R26 `docs/rules.md:131-134` | KEEP: the shell never writes GTK CSS. |
| T8 | "The theme format is exactly Omarchy's: a theme directory with `colors.toml`." (commit `128068f` "theme: the input is Omarchy's theme directory; black is noir's background") | `README.md:90-91`, git log | REPLACE: BRIEF §3.5 says the shell reads `~/.config/theme/gpuix-shell.json` rendered from `home/themes/default.nix`. The Omarchy key vocabulary (§3.10) is still the right key list for that JSON. |
| T9 | "Lock is a verb; unlock is not one anywhere." / "It never unlocks. `lock` is a verb; `unlock` is not one anywhere." | `examples/quick-settings-power-footer/README.md:8`, `cli/SPEC.md:82`, `schemas/plugin-protocol.md:50` | KEEP as a hard rule for `gpuix-shell power` and the CLI. |
| T10 | "No new clocks. CUBS declares no timers." (R18) | `docs/rules.md:142` | KEEP (BRIEF §1 "No cron/timers declared in dotfiles"). |
| T11 | "Every test that launches a compositor, sources a script fragment or touches a runtime directory runs under `~/.local/bin/runtime-test -- <cmd>`." (R19) | `docs/rules.md:144-150` | KEEP (BRIEF §1, with `--render-node`). |
| T12 | "The terminal is kitty with herdr. CUBS does not build a terminal, in Views or anywhere else." (R2) | `docs/rules.md:21-24` | KEEP. |
| T13 | "The lock screen is not Views … a lock screen is an existing locker's job, never a CUBS surface. Whether the seats bind a locker at all is Tom's call (swaylock is the candidate; swayidle already turns the monitors off)." (R4, P6, P31) | `docs/rules.md:33-37`, `docs/open-decisions.md:27`, `:52` | KEEP: no lock surface in gpuix-shell; P31 still open (none bound). |
| T14 | "Existing daemons only. PipeWire and WirePlumber, NetworkManager, BlueZ, UPower, power-profiles-daemon, logind, MPRIS players, compositor IPC and Wayland protocols. CUBS builds only thin producers over them." (R9) | `docs/rules.md:69-73` | KEEP verbatim (BRIEF §3.4 lists the same daemons). |
| T15 | "Capabilities, never compositor names." (R14) and "One compositor per session." (R23) | `docs/rules.md:95-96`, `:160` | SIMPLIFY: Sway is the only compositor (BRIEF §1), so capability gating collapses to the Sway column; keep the capability names as the internal vocabulary. |
| T16 | "The credential modal is core and is the only password field … never a plugin … credentials never pass through a plugin." (R25) | `docs/rules.md:98-102` | KEEP: NM secret agent + BlueZ agent + polkit agent in one modal, owned by the shell (BRIEF §3.2 does not list it; see §6 gap G3). |
| T17 | "Plugins supply data and handlers, never pixels." (R11) | `docs/rules.md:79-84` | INFERRED keep as a design principle; the T1/T2 plugin system itself is not on tonight's critical path. |
| T18 | "Chrome stays stock. One CUBS extension. No fork, no literal `cubs://`, no side panel, no content scripts, no overlay on the current tab, and no extension theme." (R15) | `docs/rules.md:107-111` | KEEP the "Chrome stays stock" half; the extension itself is not in BRIEF scope (§6 G5). |
| T19 | "No Lua … Runtime `LUA_EVAL` is never reachable from Chrome" (R13) | `docs/rules.md:87-92` | Moot on Sway (no Lua). |
| T20 | "No effort estimates. Plans give order and dependencies. They never give durations or schedules." (R21) | `docs/rules.md:155-156` | KEEP for all overnight docs. |
| T21 | "The user wins. The slot include sits before the user's own bind block, so a hand-written binding overrides a slot binding." | `schemas/keybinding-rendering.md:18-21` | KEEP if the shell ever generates Sway bind fragments (§3.9). |
| T22 | "Views first … an Ash file is ported only where Views has no twin" (commit `cb42ba0` "Views first: every quick-settings item a plugin, five Ash ports") | `docs/rules.md:41-52`, git log | Moot for the renderer; the principle "stock components, theme passed in, no component code changes for colour" maps to the Primer/Claude design kit. |

Tom's reasoned ratification list is cited as `~/Downloads/wm-scoping/notes5/RATIFY.md`
(`docs/open-decisions.md:7`) — **that directory does not exist on this machine tonight**
(MEASURED: `ls ~/Downloads/wm-scoping/notes5/` fails). Same for `notes5/naming.md`,
`notes5/views-first-rebalance.md`, `notes5/theme-input.md`, `notes5/themes/nix-palette-to-omarchy.py`.

---

## 3. Feature and behaviour inventory

Columns: feature | what exactly (as the source specifies it) | where it lives today | keep / replace / drop / new | notes for the GPUIX/Sway builder.
"Today" means in CUBS (spec) and, where relevant, in Tom's live dotfiles (BRIEF §2 table).

### 3.1 Surfaces (layer-shell windows)

MEASURED from `README.md:27-30`, `docs/architecture.md:188-191`, `:353-381`, `cli/SPEC.md:33-39`,
`schemas/cubs-plugin.schema.json:842-905`, `shell/app/cowl_surface_manager.cc:137-300`,
`shell/docs/ccd-switcher-behaviour.md:13-23`. Geometry from the lifted June embedder is the
proven-on-niri recipe, not the CUBS plan; the CUBS plan is in the text.

| Surface | What exactly | Where today | Verdict | Becomes in gpuix-shell |
|---|---|---|---|---|
| **Bar** | top strip, three zones left/center/right, clock centre, height 36 DIP, layer top, anchor top+left+right, exclusive zone 36, keyboard on-demand, namespace `cubs-bar`; pills fed by source plugins through a bar slot (P28, no schema yet) | `shell/bar/bar_view.h:41-66` (lifted, `kBarHeightDip = 36`), `cowl_surface_manager.cc:137-156`, `docs/open-decisions.md:49` | **DROP** | BRIEF §1: "no top bar on the Linux head". Pill content (clock, battery, network, audio, bluetooth, tray) moves into the rail's session row / footer and into `gpuix-shell controls`. |
| **Workspace rail** (the hero) | left edge, layer top, anchor left+top+bottom, collapsed **56 DIP** with a 56 exclusive zone, expanded flyout **240 DIP** as a *separate overlay surface with no zone* "so hovering never makes the compositor re-tile"; WorkspaceNode tree after Chrome's vertical tabs; workspaces as groups, windows as rows, click to focus, rename in place, collapse to free the screen; keyboard none (rail), on-demand (flyout), exclusive only while renaming; namespaces `cubs-rail`, `cubs-rail-flyout`; config `collapsedWidth` 56 (40–96), `expandedWidth` 240 (160–480), `expandOnHover`, `showWindowCount`, `showScrollColumns`, `outputs` all/primary | `docs/architecture.md:361-364`, `examples/workspace-rail/cubs-plugin.json:18-40`, `ccd-switcher-behaviour.md:15-22`; live today: `herdr-picker`, `sway-workspace`, PR #565 Mod+i switcher | **KEEP** (replace renderer) | `gpuix-shell rail` daemon. BRIEF §3.3 geometry wins where it differs: exclusive zone 56 collapsed / 220 expanded, keyboard on-demand. Keep the CUBS rule that the hover flyout has **no exclusive zone**. Slots 1–9 + herdr status glyphs per BRIEF §1. |
| **Rail behaviour spec** (from the only switcher that worked) | fetch workspaces/windows/outputs in parallel at start; follow the event stream; keep the focused workspace as a live scalar, not per-workspace `is_focused` flags "which lags across multi-output focus changes"; group by output, sort by output name then index; show output name only with >1 output; row = index badge + label ("Workspace N" fallback) + window count (blank when zero); mark focused and per-output active; click row → focus; collapse button; **Escape toggles collapse, never hides**; Ctrl+wheel/Ctrl+-/0 ignored ("a shell surface is not a document and must not zoom") | `shell/docs/ccd-switcher-behaviour.md:25-52` | **KEEP** | Seven acceptance tests at `:59-73` become `tests/gpuix-shell/smoke_rail.py` cases (see §5). On Sway: two outputs (eDP-1 slots 1–9, eDP-2 slot 10). |
| **Quick-settings host** | one overlay layer surface; a `BoxLayoutView` of slider rows, a scrolling tile grid, cards, a footer, a page stack with host-drawn header (title + back button); host owns open/close, focus, Esc, page stack, ordering, "edit tiles" state, crash badge on a dead T2 entry; every item is a plugin (slots `tile`, `slider`, `card`, `footer`, `page`) | `docs/architecture.md:366-375`, `schemas/cubs-plugin.schema.json:1213-1341` | **KEEP** | `gpuix-shell controls` (BRIEF §3.2). Layout = SHELLS-DIGEST a.quick-controls: overlay, top+right, on-demand keyboard. Items in §3.2 below. |
| **Credential modal** | NetworkManager secret agent + BlueZ `org.bluez.Agent1` + polkit agent in one queue; overlay layer surface, exclusive keyboard; `ui::DialogModel` with a password field; the only password field in the shell | `docs/architecture.md:377-381`, R25 | **KEEP** | Not named in BRIEF §3.2. INFERRED: lives in `gpuix-shell controls` (same process as wifi/bluetooth menus) or its own `gpuix-shell agent` daemon. Needed the moment the wifi menu connects to a secured network. Gap G3. |
| **Notifications** (server + popups) | a freedesktop `org.freedesktop.Notifications` server feeding `ui/message_center` stock views; popups layer top, anchor top+right, zone 0, keyboard none, namespace `cubs-notifications`; quiet mode (`MessageCenter::SetQuietMode`) published by `cubs.notifications` source; `notify` from plugins needs the `notifications` permission; `[notifications]` theme section with "countdown as a progress ring" | `docs/architecture.md:355-357`, `cowl_surface_manager.cc:259-269`, `examples/quick-settings-dnd/README.md:3-7`, `style/theme-map.json:82` | **KEEP** | `gpuix-shell notifications` daemon (D-Bus server via dbus-next + toasts + OSD window, BRIEF §3.2). Geometry per SHELLS-DIGEST: overlay top-right, 390 wide, max 4, 140 px cards. Replaces mako; carry `herdr-attention` → Sway urgency + mako actions from branch `herdr-sway-context`. |
| **Toasts** | `cubs toast <text> [--icon]`; plugin `toast {text, icon?}`; `WidgetFadeAnimator` fades; stock composition (Ash `system_toast_view` dropped, "the toast API is kept") | `cli/SPEC.md:39`, `schemas/plugin-protocol.md:40`, `ASH-PORT-LEDGER.md:84` | **KEEP** | `gpuix-shell toast "<text>"` CLI verb over shell.sock; same window as notifications. |
| **OSD** | `cubs osd <kind> <value>` "shows a value on the OSD without owning it. Example: the `brightness` script runs `cubs osd brightness 0.42`"; overlay, anchor bottom, zone 0, keyboard none, namespace `cubs-osd`; slider face shared with quick settings (`QuickSettingsSlider`) | `cli/SPEC.md:38`, `cowl_surface_manager.cc:248-257`, `style/INVENTORY.md:80` | **KEEP** | `gpuix-shell osd volume|brightness|mic|caps <value>` replaces `~/.local/bin/osd`; BRIEF §3.3: overlay, bottom margin 96. The existing `volume`/`brightness` scripts call it exactly as CUBS planned. |
| **Launcher** | picker + launcher: stock `Textfield` + rows in a `ScrollView`, ranked by the ported `string_matching` fuzzy tokenized ranker; proven tree (June spike, niri): translucent rounded panel, search field, separator, result rows (icon swatch + primary/secondary text + right action chip), selected-row highlight, footer of key-cap hints; **760×399**, rows 56, search 58, footer 44, radius 14, max 5 rows; overlay, keyboard exclusive, zone 0, namespace `cubs-launcher`; entries from `contributes.launcher` (title, keywords ≤30, icon, optional `.desktop` export marked `X-Cubs-Managed=true`); every command is also a palette row (`ui::ActionItem`); `picker-provider` surfaces with a ≤4-char `prefix` answer `picker/query` with `{items:[{id,label,sublabel?,icon?,action}]}` | `docs/architecture.md:357-358`, `shell/PROVENANCE.md:115`, `shell/launcher/launcher_panel.h:7-35`, `:69-73`, `launcher_panel.cc:78-81`, `schemas/cubs-plugin.schema.json:1065-1098`, `:896-900`, `schemas/plugin-protocol.md:33`, `ASH-PORT-LEDGER.md:A041` | **KEEP** | `gpuix-shell launcher` (Mod+d, vicinae replacement). BRIEF §3.3 geometry wins: overlay, top margin 108, 700×580, keyboard exclusive. Sources: apps (.desktop), commands (every CLI verb), clipboard history, browser tabs (SHELLS-DIGEST), herdr workspaces, prefix providers. Keep the footer key-cap hints and the "browse mode on empty query" (`launcher_panel.h:26`). |
| **Window cycle (Alt+Tab)** | "On scroll and sway, the window cycle keeps its keys in a scroll mode bound to the release of Alt"; MRU order "recovered at start from the compositor's focus stacks" and maintained from focus events; `cubs cycle toggle` | `docs/compositor-adapters.md:164-167`, `docs/architecture.md:316-318`, `shell/wm/wm_snapshot.h:233-235`, `cli/SPEC.md:36` | **KEEP** (low priority) | `gpuix-shell switcher` already covers Mod+i; Alt+Tab is a second mode of the same window. On Sway: a `mode "cycle"` with `bindsym --release Alt` exiting it; MRU from `window::focus` events. Not in BRIEF §3.2 (gap G4). |
| **Cheat sheet** | key chips (ported `KeyboardShortcutView`); `cubs cheatsheet toggle`; on sway "config text only" for `bindings.list` (no `GET_BINDINGS`) so the sheet parses the config; hook H15 `bindsym --title` would feed it | `cli/SPEC.md:36`, `style/INVENTORY.md:81`, `docs/compositor-adapters.md:138`, `docs/scroll-fork-hooks.md:61` | **KEEP** (nice-to-have) | A tab of `gpuix-shell launcher` or `switcher`: parse `home/dot_config/sway/binds.conf` + `# @title` comments. New. |
| **Gallery** | `cubs gallery [--headless --capture <dir>]`: every component in every variant × state (normal, hovered, pressed, focused, disabled, toggled), typography page, colour page; also the conformance harness (one PNG per page + `manifest.json` of sha256) | `cli/SPEC.md:37`, `style/gallery/DESIGN.md:1-60`, `:169-178` | **KEEP** (dev tool) | `gpuix-shell gallery` as the design-kit showcase in the chosen theme; the headless capture is the visual-regression harness under runtime-test. |
| **Menus / bubbles / tooltips** | `xdg_popup` children of layer surfaces (never a toplevel); menu locations `cubs.menu/*`, `rail/workspace`, `rail/window`, `bar/context`, `tray/context`; "live acceptance is still pending (explicit-grab caveat open)" | `docs/rules.md:9-12`, `schemas/cubs-plugin.schema.json:1049-1052`, `shell/PROVENANCE.md:106` | **REPLACE** | GPUIX has one window per renderer and no popup API (SHELLS-DIGEST limits); draw context menus inside the surface's own window (rail flyout context menu as an in-window overlay). Gap G6. |
| **Control pages** (settings) | six pages in Chrome tabs: `shortcuts` (default), `appearance`, `plugins`, `compositor`, `notifications`, `connection`; `cubs open [page]`; bound `bindsym $mod+Comma exec cubs open`; new-tab override shows a workspace glance; omnibox keyword `cubs`; in-Chrome `Ctrl+Shift+K` | `cli/SPEC.md:45`, `extension/options.html:10-18`, `extension/README.md:12-18`, `extension/manifest.json:15-27` | **DROP** (as Chrome extension) | BRIEF §3.8: the shell "only launches" web utilities. A shortcuts page is still valuable; INFERRED: `gpuix-shell settings` as a GPUIX window later, or a herdr-web-ui page. Gap G5. |
| **Scrim** | "No full-output overlay is drawn except an allowlisted scrim" (R1); `[launcher]` theme section names "the launcher overlay card and scrim" | `docs/rules.md:9-11`, `style/theme-map.json:83` | **DROP** | Flat and opaque per BRIEF §1; no scrim, no dim. |
| **Dock** | lifted recipe only: layer top, anchor bottom+left+right, exclusive = height | `cowl_surface_manager.cc:270-280` | **DROP** | Out ("Out unless Tom asks: lock, wallpaper, polkit, tray, dock", SHELLS-DIGEST §4). |
| **Lock screen** | not a surface (R4) | `docs/rules.md:33-37` | **DROP** | Unchanged. |
| **T2 host** | supervised child processes, `systemd-run --user --scope` per plugin, JSON-RPC on stdio | `schemas/plugin-protocol.md:1-13` | **DEFER** | Not tonight; the shell's own surfaces are built in-process. The protocol is the template for a later plugin tier (§3.6). |
| **Files explorer** | explicitly OUT in CUBS (R3, P2) | `docs/rules.md:27-31` | **NEW** | `gpuix-shell files` (Pinax-like, ordinary xdg_toplevel), BRIEF §3.2. Nothing in CUBS to reuse. |
| **Power menu** | a bar button + anchored panel: lock, log out, suspend, hibernate (enablement `session.canHibernate`), reboot, shut down (confirm on logout/reboot/shutdown), uptime in header, `Mod+Shift+Escape` toggle, `Mod+Ctrl+L` lock; broker map: lock→`loginctl lock-session`, logout→`session.exit`, suspend/hibernate/reboot/shutdown→`systemctl …` | `examples/power-menu/cubs-plugin.json:21-65`, `examples/power-menu/bin/power-menu:16-32` | **KEEP** | `gpuix-shell power` (BRIEF §3.2). Copy the action list, the confirm set and the broker map verbatim. |

### 3.2 Quick-settings items (every slot entry, every bound command)

MEASURED from `examples/quick-settings-*/cubs-plugin.json` and `ui/*.json`. Order values are the
grid order (lower first). `state` is the source snapshot the tree binds to.

| Entry id (plugin) | Slot / size | Order | Binds to | Face (ui tree) | Actions it fires | Verdict → gpuix-shell controls |
|---|---|---|---|---|---|---|
| `output` (`cubs.qs-audio`) | slider | -100 | `cubs.audio/state` → `/output/{icon,volume,muted,name}` | `slider` with `iconAction` (mute) | `cubs.audio/set-output-volume {value}`, `cubs.audio/toggle-output-mute` | KEEP: slider row 1 (wpctl set-volume / toggle mute). `examples/quick-settings-audio/ui/output.json:4-13` |
| `input` (`cubs.qs-audio`) | slider | -90 | `/input/{icon,gain,present,name}` | `slider`, hidden when `!present` | `cubs.audio/set-input-gain {value}` | KEEP: slider row 2 (mic). `ui/input.json` |
| `devices` (`cubs.qs-audio`) | page "Audio" | — | `/outputs`, `/inputs`, `/output/id`, `/input/id` | two `radioGroup`s + `listItem` "Per-application volume / Opens pavucontrol" | `set-default-output`, `set-default-input`, `open-mixer` (close) | KEEP: routing page (replaces `audio-route` script). `ui/page.json:8-30` |
| `slider` (`example.quick-settings-brightness`, T2) | slider | -80 | own snapshot `/value`, `/available` | `slider` icon `brightness` | `set {value}` → `brightnessctl -n 1 -d <dev> set N%` per DRM backlight; floor 1% "so a slider dragged to the left never powers an i915 panel off"; on the Zenbook Duo "setting `intel_backlight` is enough, because the dock daemon mirrors eDP-1's level onto eDP-2"; LG 5K have no DRM backlight → slider hidden; DDC not covered | KEEP: slider row 3, reuse the existing `brightness` script's floor. `bin/quick-settings-brightness:7-12`, `README.md:11-16` |
| `tile` (`cubs.qs-network`) | tile primary | -100 | `cubs.network/state` → `/primary/{icon,label,sublabel}`, `/wifi/{enabled,available}` | `tile` toggled=wifi enabled, `detail: page` | `cubs.network/toggle-wifi` | KEEP: Wi-Fi tile. "Wi-Fi is also a palette and launcher row with no extra declaration." |
| `page` (`cubs.qs-network`) | page "Network" | — | `/wifi/*`, `/networks[]{id,name,icon,status,connected,connecting,secure}` | `switch` Wi-Fi; `scroll` (maxHeight large) of `listItem`s with trailing `progress` (connecting) + lock `icon` (secure); `listItem` "Other networks and VPN / Opens the connection editor" | `set-wifi-enabled {value}`, `activate {network}`, `open-editor` | KEEP: **the wifi menu** Tom asked for (replaces `fzf-nmcli`). Secured network → credential modal (R25). `ui/page.json:8-48` |
| `tile` (`cubs.qs-bluetooth`) | tile primary | -90 | `cubs.bluetooth/state` → `/icon`, `/summary`, `/powered`, `/adapterPresent` | `tile`, hidden without adapter, `detail: page` | `cubs.bluetooth/toggle-power` | KEEP: Bluetooth tile. |
| `page` (`cubs.qs-bluetooth`) | page "Bluetooth" | — | `/powered`, `/paired[]{address,name,icon,status,connected,battery,hasBattery}`, `/discovering`, `/discovered[]{address,name,icon}` | `switch`; "Your devices" repeat of `listItem` (selected=connected, trailing battery %); "Pair a new device" header with `progress` while discovering; repeat of discovered | `set-powered {value}`, `toggle-connection {device}`, `pair {device}`; "the source plugin scans only while a consumer has the page open, so nothing polls"; PIN/passkey → credential modal | KEEP: **the bluetooth pairing menu** Tom asked for. `ui/page.json:8-50`, `README.md:7-10` |
| `tile` (`cubs.qs-dnd`) | tile **compact** | 10 | `cubs.notifications/state` → `/quietMode` | `tile` icon `do-not-disturb` | `cubs.notifications/toggle-quiet-mode` (the one exact `call:` permission) | KEEP: DND toggle, talks to the notifications daemon over shell.sock. Also PR #571 Mod+o dismiss. |
| `sessions` (`cubs.qs-media`) | card | 0 | `cubs.media/state` → `/sessions[]` | `repeat` of `mediaSession` (stock `MediaItemUIView`), `when: session.mediaActive` | `cubs.media/control {session, verb: play|pause|next|previous|seek, position?}` | KEEP: now-playing card(s), one per MPRIS player (replaces `media` script). |
| `footer` (`cubs.qs-power-footer`) | footer | — | `cubs.power/state` → `/battery/{icon,present,fraction,timeRemaining}`; `/profile` from source `cubs.power/profiles` | `row`: battery icon + percent (tooltip time remaining) + profile label + spacer + `iconButton` settings / lock / power | `open-settings` (handler `open: settings`), `cubs.session/lock` (close), `cubs.session/power-menu` | KEEP: footer row. Settings gear → gap G5; lock → `loginctl lock-session` only if a locker is bound (P31); power → `gpuix-shell power`. |

Shape ruling P29: "one host with a grid (as now), or independent per-domain bubbles anchored to bar
indicators — One host." (`docs/open-decisions.md:50`). INFERRED: keep one host; with no top bar there
is nothing to anchor bubbles to anyway.

### 3.3 Source plugins (producers) and their command ids

MEASURED `docs/architecture.md:333-338` (the list), `examples/network-source/cubs-plugin.json`
(the only fully written one), command ids as referenced by the `ui/*.json` trees and manifests.
Producers "publish full snapshots, not patches. A feature is dropped by not registering it" (R10).

| Producer id | Over which daemon | Snapshot (`<id>/state` fields the trees use) | Command ids (MEASURED where a file names them; INFERRED-from-trees otherwise) | gpuix-shell data source (BRIEF §3.4) |
|---|---|---|---|---|
| `cubs.network` | NetworkManager (`dbus:system:org.freedesktop.NetworkManager`), helper `nm-connection-editor` (optional, nixpkgs `networkmanagerapplet`) | `wifi.enabled`, `wifi.available`, `primary.{icon,label,sublabel}`, `networks[]` | `toggle-wifi`, `set-wifi-enabled {value:bool}`, `activate {network}`, `deactivate {network}`, `forget {network}` (confirm), `open-editor`, `state` (json). CLI mount `cubs network wifi|connect|disconnect|forget|state` (`examples/network-source/cubs-plugin.json:16-33`) | NetworkManager via dbus-next; CLI `gpuix-shell network …` with the same verbs |
| `cubs.audio` | PipeWire + WirePlumber, "the same one the volume OSD reads" | `output.{icon,volume,muted,name,id}`, `input.{icon,gain,present,name,id}`, `outputs[]`, `inputs[]` | `set-output-volume`, `set-input-gain`, `toggle-output-mute`, `set-default-output`, `set-default-input`, `open-mixer` (pavucontrol) | `wpctl` (BRIEF) or pipewire via dbus-less socket; keep per-app mixer = pavucontrol |
| `cubs.bluetooth` | BlueZ (`device/bluetooth` in CUBS) | `powered`, `adapterPresent`, `icon`, `summary`, `paired[]`, `discovering`, `discovered[]` | `toggle-power`, `set-powered {value}`, `toggle-connection {device}`, `pair {device}` | BlueZ over dbus-next (`org.bluez.Adapter1/Device1`, agent in credential modal) |
| `cubs.power` | UPower + power-profiles-daemon | `state`: `battery.{icon,present,fraction,timeRemaining}`; second source `profiles`: `profile` | (none named; INFERRED `set-profile`) | UPower + `org.freedesktop.UPower.PowerProfiles` via dbus-next; the live `claude-capacity` script is unrelated (Claude usage) |
| `cubs.brightness` | sysfs / brightnessctl | `value`, `available` | `set {value}`, `state` | reuse `home/dot_local/bin/brightness` |
| `cubs.session` | logind, compositor `session.exit` | `session.canHibernate`, `session.mediaActive` (context keys) | `lock`, `power-menu`, (logout/suspend/hibernate/reboot/shutdown via power-menu example) | logind via dbus-next; `swaymsg exit` |
| `cubs.media` | MPRIS players | `sessions[]{id,…}` | `control {session, verb, position?}` | MPRIS via dbus-next (replaces `media` script / playerctl) |
| `cubs.notifications` | the shell's own server | `quietMode` | `toggle-quiet-mode` | the `gpuix-shell notifications` daemon itself |
| tray | StatusNotifierItem | — | — | DROP by default (SHELLS-DIGEST "Out unless Tom asks"); INFERRED |
| polkit | polkit agent | — | — | folded into the credential modal |
| launcher index | .desktop files | — | — | `gpuix-shell launcher` app source |
| `cubs.workspace-rail` (T0, hero) | compositor adapter | `state` (rail model JSON) | `focus-workspace {workspace}`, `focus-window {window}`, `rename-workspace {workspace,name}` (enablement `compositor.workspaces.rename`), `move-window {window,workspace}`, `toggle-collapsed` (key `Mod+Grave`), `toggle`, `state`; CLI `cubs rail toggle|collapse|focus|rename|state`; menus `rail/workspace` rename, `rail/window` move; events `workspace`, `window`, `output` (`examples/workspace-rail/cubs-plugin.json:22-59`) | Sway IPC + herdr snapshot. **Conflict**: `Mod+Grave` is taken by branch `herdr-sway-context` (kitty/Chrome swap, BRIEF §2). Use a different collapse key. |

### 3.4 Core CLI verbs (`cli/SPEC.md`, MEASURED)

Conventions `:11-19`: every verb accepts `--json`; exit codes 0 ok, 1 failed, 2 usage, 3 permission
or capability missing, **69** not running (`EX_UNAVAILABLE`); help and fish/bash/zsh completions
generated from manifests; plugins never put binaries on PATH; destructive verbs ask on a TTY and
need `--yes` otherwise.

| Verb | Does | Verdict → `gpuix-shell` CLI (shell.sock, BRIEF §3.2) |
|---|---|---|
| `cubs call <plugin-id> <command> [--arg k=v]… [<json>]` | invoke any command id | KEEP as `gpuix-shell call <surface>/<command> [json]` |
| `cubs <name> <verb>` | plugin-mounted verb | KEEP shape: `gpuix-shell network wifi on`, `gpuix-shell rail focus 3` |
| `cubs commands [--plugin]` | list commands with enablement | KEEP (feeds the launcher's command source) |
| `cubs bar toggle|show|hide <bar-id>` | one bar | DROP (no bar) |
| `cubs launcher|rail|quick-settings|notifications|cycle|cheatsheet toggle|show|hide` | per-surface | KEEP: `gpuix-shell launcher toggle`, `switcher toggle`, `controls toggle`, `notifications toggle|dismiss`, `rail toggle|collapse` |
| `cubs gallery [--headless --capture <dir>]` | design-kit gallery / conformance | KEEP (dev) |
| `cubs osd <kind> <value>` | show a value without owning it | KEEP verbatim |
| `cubs toast <text> [--icon]` | short toast | KEEP verbatim |
| `cubs open [page]` | control page in Chrome; pages `shortcuts appearance plugins compositor notifications connection` | REPLACE: `gpuix-shell open <url|app>` launches Chrome apps/herdr-web-ui (BRIEF §3.8) |
| `cubs native-host [--manifest]` | Chrome native messaging host | DROP |
| `cubs plugin list|add|enable|disable|update|remove|clone|validate|check|render` | Omarchy-style plugin lifecycle; `render --compositor --out` works offline at Nix build time | DEFER (plugin tier later); `render` idea → generated Sway bind fragment at Nix build |
| `cubs config get|set <plugin>.<key>` | reads/writes `cubs.json`; refuses when Nix-managed and prints the path | KEEP shape: `gpuix-shell config …` over the HM-rendered JSON; refuse + print path |
| `cubs theme apply [<name>]` / `theme list` | live re-theme, writes Chrome policy request file | REPLACE: the existing `~/.local/bin/theme` retargets `~/.config/theme`; the shell watches the symlink (BRIEF §3.5). `gpuix-shell theme reload` optional |
| `cubs compositor` | active adapter, version, capability set | KEEP as `gpuix-shell compositor` (`swaymsg -t get_version` + capability list) |
| `cubs wm [--json]` | WmModel dump | KEEP as `gpuix-shell wm` (outputs, workspaces, windows, focus, herdr slot map) |
| `cubs service status|logs` | the user service | KEEP (`systemctl --user status gpuix-shell-*`) |
| `cubs version` | commit, protocol version, Chromium base | KEEP (commit, @gpuix/native version) |
| never: raw compositor commands, Lua eval, `unlock`, writing the user's own config | `cli/SPEC.md:79-84` | KEEP all four |

### 3.5 Native messaging verbs and pushes (the extension ↔ shell contract)

MEASURED `extension/README.md:73-92`. Useful tonight as the **shape of shell.sock's JSON-RPC
surface** even though the extension is dropped.

| Request verb | Returns | Push | When |
|---|---|---|---|
| `status` | `{machine, compositor, capabilities, theme:{name,mode,background,foreground,light_foreground,muted,accent,red}}` | `bindings-changed` | a slot file changed |
| `bindings.list` | `{key, command, plugin?, locked, file?, line?}` rows; locked = user's own config | `reload` | relayed from the compositor |
| `bindings.set {plugin,index,key}` | writes slot file then applies live or by reload; refused for locked | `config-error` | compositor rejected a reload |
| `plugins.list` / `plugins.enable` / `plugins.disable` / `plugins.config {plugin,values}` | refused `{code:"read-only", path}` when Nix-managed | `wm` | model changed (only while subscribed) |
| `commands.list` / `commands.invoke {plugin,command,args,source:"chrome"}` | | `theme` | `cubs theme apply` ran |
| `wm` | WmModel snapshot | `open {page}` | `cubs open` ran |

INFERRED mapping: `gpuix-shell`'s socket protocol = these verbs minus plugins/bindings.set, plus
`osd`, `toast`, `notify`, `surface.toggle`. The `source` field (`views|chrome|cli|keybinding|menu|launcher`,
`schemas/plugin-protocol.md:27`) is worth keeping on every invoke for logging.

### 3.6 Plugin model (tiers, manifest, contribution points, permissions)

MEASURED `README.md:60-86`, `schemas/cubs-plugin.schema.json`, `schemas/plugin-protocol.md`.
Verdict for tonight: **DEFER** the plugin host; **KEEP** the vocabulary as the internal registry
(`src/registry.ts` in BRIEF §4) so a later tier can be added without renaming.

| Concept | Exactly | Pointer |
|---|---|---|
| Tiers | T0 built-in (first-party, in-tree), T1 declarative manifest (no code), T2 any-language subprocess, JSON-RPC 2.0 on stdio, sends a `ui` tree; T3 JavaScript host "later", "not accepted yet" | `README.md:67-75`, schema `:82-83` |
| Manifest | `cubs-plugin.json`: `schemaVersion` (number 1), `id` `publisher.name` (`cubs.*` reserved), `name`, `version` semver, `engines.cubs` (never `*`), `engines.protocol` (T2), `runtime.mode` builtin/declarative/process + `exec`/`target`, `permissions[]`, `requires.{compositor.{required,optional}, helpers[{bin,nixpkgs,optional}], plugins[]}`, `contributes`, `chrome.{settingsPages,pages}` | schema `:8-341` |
| Contribution points | `commands` (the spine: id, title, category, icon, enablement `when`, surface, verb toggle/show/hide/summon, confirm, result none/text/json, args[{name,type,required}], T1 `handler`), `surfaces` (kinds `bar-widget`, `bar`, `panel`, `overlay`, `menu`, `service`, `picker-provider`; `defaultSection`, `allowMultiple`, `anchor` `surface:<id>|pointer|output-center`, `keyboard` none/on-demand/exclusive, `ui`, `prefix`, `when`), `configuration` (JSON-Schema subset, formats `keybinding|path|color-role|command`, scope global/instance), `keybindings` (`command`, `key` or `keyFrom config.x`, `args`, `when`, `release`, `locked`, `mode`), `menus` (locations above), `launcher`, `cli` (name not in `plugin call open bar help version gallery service`; verbs with `confirm`), `compositor.scroll.{lua,config}`, `events` (`workspace|window|output|mode|binding|reload|session.(lock|unlock|idle|resume)|scroll.(scroller|trails)`), `sources` (id, description, schema), `quickSettings` (slot tile/slider/card/footer/page; ui; state; size primary/compact; page; title ≤48; order -1000..1000; when) | schema `:684-1344` |
| T1 handler kinds | `{compositor: <capability>, args}`, `{exec, args}`, `{call: <commandRef>, args}`, `{open: <page>}` | schema `:771-838` |
| Permissions | `exec:<program>`, `path:read|write:<glob>`, `network[:host[:port]]`, `notifications`, `media`, `clipboard:read|write`, `dbus:session|system:<name>`, `compositor:<capability>`, `scroll.lua`, `scroll.lua.eval`, `call:<plugin>/<command|*>`, `state:read:<plugin>/<source>`; undeclared → JSON-RPC `-32001` | schema `:637-672`, protocol `:46-48` |
| `when` context | expressions over `config.*`, `compositor.*`, `session.*`, `surface.*` with `! && \|\| == !=` and literals; "evaluated by CUBS, never by a shell" | schema `:674-678` |
| Key chord grammar | `(Mod|Super|Ctrl|Alt|Shift)+` … one key from a fixed list incl. `F1-12`, `XF86*`, `Grave`, `Print` | schema `:679-683` |
| T2 lifecycle | `initialize {protocol,cubsVersion,pluginId,capabilities,config,locale}` → `{protocol}`; `shutdown`; → plugin: `command/invoke`, `surface/opened|closed`, `config/changed`, `event`, `picker/query`, `source/changed`; ← plugin: `snapshot` (full), `surface/setTree`, `source/snapshot`, `notify`, `toast`, `exec` → `{exitCode,stdout,stderr}`, `compositor/command {capability,args}`; one `systemd-run --user --scope` per plugin, backoff restart, crash badge; P30 memory ceiling open | `schemas/plugin-protocol.md:9-51` |
| Settings store | `cubs.json`: "presence means enabled, built-ins appear only as deviations, runtime state lives under `$XDG_STATE_HOME/cubs`" | `docs/architecture.md:328-331` |
| Validator | `tools/validate.py` + 23 invalid fixtures (`tools/fixtures/invalid/*.json`) encode the manifest rules (e.g. `ui-colour-literal`, `slider-with-size`, `page-without-title`, `reserved-id-process`) | `tools/` listing |

### 3.7 The `ui` tree vocabulary → GPUIX/React components

MEASURED `schemas/ui-tree.schema.json`. 29 node types, semantic roles only ("no colour literals, no
pixel sizes and no custom painting"). Bindings are JSON Pointers (`$bind`) into the latest snapshot,
`./` relative inside `repeat`, formats `text|percent|duration|bytes|time|relative-time`, optional
cross-plugin `source`. Actions: `{command, args, confirm?, close?}`.

| Node | Props (beyond `id visible enabled tooltip accessibleName flex`) | Views twin (CUBS) | gpuix-shell component (INFERRED; design kit names from the handoff where they exist) |
|---|---|---|---|
| `column` / `row` | `spacing none|tight|normal|loose`, `align start|center|end|stretch`, `container none|rounded|rounded-top|rounded-bottom` | BoxLayout | `<Stack dir>`; container → rounded 8/12 inner corners + hairline |
| `stack` | children overlaid | FillLayout | absolute `<Box>` |
| `grid` | `columns 1..6`, spacing | TableLayout | CSS-grid-like `<Grid>` for tiles |
| `scroll` | `maxHeight small|medium|large|surface`, one child | ScrollView + OverlayScrollBar | GPUIX scroll container |
| `repeat` | `items` binding, `key` for animated add/remove/move, `direction` | AnimatingLayoutManager | React list with keys |
| `label` | `text`, `typography display|title|headline|body|body-strong|button|annotation|label`, `role default|subtle|primary|positive|warning|alert|disabled`, `elide tail|middle|head|none`, `maxLines ≤20` | Label | `<Text>` with the type scale (Anthropic Sans 12 base) |
| `markdown` | emphasis, strong, code, links (invoke commands or open in Chrome) | StyledLabel | small MD subset → `<Text>` runs |
| `icon` | `icon` (vector name or `xdg:` freedesktop name), `size small|medium|large`, role | ImageView | Anthropicons glyph font / `xdg:` lookup |
| `image` | `src`, `size thumbnail|small|medium|large`, `rounded`; "never used to paint chrome" | ImageView | `<Image>` |
| `badge` / `dot` | text + role / role (urgency, counters) | Badge, DotIndicator | status glyph (herdr ◉ ◐ ● ✓ ○) |
| `separator` / `spacer` | — / size | Separator | hairline / flex spacer |
| `progress` | `value` (absent = indeterminate), `shape bar|ring` | ProgressBar, DrawProgressRing | bar + ring (notification countdown) |
| `button` | `label`, `icon`, `variant default|primary|secondary|floating|alert|accent`, action | MdTextButton default/tonal/prominent/text | Primer-style button variants |
| `iconButton` | `icon`, `size xsmall..xlarge`, `variant default|prominent|floating`, `toggled`, `accessibleName` required | ImageButton | icon button |
| `switch` / `checkbox` / `radioGroup` / `select` | value + action (`{value}`), options literal or bound `{value,label,icon}` | ToggleButton, Checkbox, RadioButton, Combobox | switch, checkbox, radio list, select |
| `slider` | `icon`, `value 0..1`, `toggled`, `action {value}` ("CUBS coalesces drags"), `iconAction` (mute) | ported QuickSettingsSlider | slider row with leading icon button |
| `textfield` | `placeholder`, `value`, `size`, action fires on Enter | Textfield | input (launcher search, rename) |
| `listItem` | `icon`, `label`, `sublabel`, `selected`, `trailing` node, action | composed Button+BoxLayout | list row (wifi/bluetooth/launcher rows) |
| `tile` | `variant primary|compact`, icon, label, sublabel, `toggled`, action, `detail` (page id) | ported FeatureTile | quick-settings tile (primary = icon+label+sublabel+drill-in; compact = icon+label) |
| `tabSlider` | 2–5 options, value, action | row of MdTextButton (tonal selected) | segmented control |
| `keyChips` | `keys` text | ported KeyboardShortcutView | key-cap chips (launcher footer, cheat sheet) |
| `mediaSession` | `session` binding, action `{verb: play|pause|next|previous|seek, position?}` | `MediaItemUIView` | now-playing card (art, title, artist, transport, seek) |

Four "genuinely new paints" CUBS kept out of core: range slider, HSV colour picker, line graph,
screen corner (`style/INVENTORY.md:92-95`). The colour picker is relevant to the live `colorpicker`
script; INFERRED: keep it a script.

### 3.8 Compositor capability table, Sway column, and the Sway IPC recipe

MEASURED `docs/compositor-adapters.md:120-162` (table), `:48-69` (scroll/sway rows),
`shell/wm/adapters/scroll/README.md:13-24`, `shell/wm/compositor_adapter.h:33-47`, `:56-111`,
`shell/wm/wm_snapshot.h:198-236`.

| Capability | sway | Use in gpuix-shell |
|---|---|---|
| `outputs.list`, `workspaces.list`, `workspaces.focus`, `workspaces.rename`, `windows.list`, `windows.focus`, `windows.move-to-workspace`, `windows.fullscreen-state`, `windows.urgency` | yes | rail, switcher, cycle; `GET_OUTPUTS`, `GET_WORKSPACES`, `GET_TREE`; `workspace number N`, `[con_id=42] focus`, `rename workspace 3 to "web"`, `move container to workspace` |
| `bindings.events` (the `nop` dispatch) | **yes** | `bindsym $mod+d nop gpuix-shell launcher toggle` emits a `binding` event the rail daemon reads: "Nothing forks per keypress … harmless when CUBS is not running". INFERRED: tonight BRIEF §3.2 says binds call the CLI; the `nop` path is the zero-fork upgrade for later (gap G7). |
| `bindings.list` | "config text only" | cheat sheet parses `binds.conf` |
| `config.reload`, `config.include-slot` | yes | `swaymsg reload`; `include ~/.config/sway/gpuix-shell.d/*.conf` if fragments are generated |
| `scratchpad.toggle` | yes | `[app_id=…] scratchpad show` (music scratchpad example) |
| `overview.toggle` | **no** | none |
| `session.exit` | yes | `swaymsg exit` from the power menu (logout) |
| `windows.geometry-events` | no ("sway polls") | avoid needing geometry |
| `bindings.gesture-events` | "with H4 via sway" (not on stock) | `bindgesture swipe:3:up exec gpuix-shell launcher toggle` |
| `windows.border-colour-rule` | no | none (the orange prompt border is unavailable on Sway) |
| scroll-only (`scroll.*`, `overview.events`, `windows.placement-hook`) | no | none |

IPC recipe (KEEP verbatim for `src/sway/ipc.ts`):
- socket `$SWAYSOCK` (then `$I3SOCK`; scan `$XDG_RUNTIME_DIR` for `sway-ipc.*.sock` when started outside the session) (`adapters/scroll/README.md:15`);
- framing `i3-ipc` magic, uint32 length, uint32 type, native byte order, JSON (`:16`);
- **two connections**: one subscribed, one for requests "so a slow reply never blocks events" (`compositor-adapters.md:54`);
- **subscribe before query**: `SUBSCRIBE ["workspace","window","output","mode","binding","shutdown","tick"]`, then `GET_WORKSPACES`, `GET_TREE` (coalesced, one in flight, dirty flag), `GET_OUTPUTS` (`:55-56`, README `:18-19`);
- **landed barrier**: `SEND_TICK` with a unique payload after every command; the matching `tick` event means all caused events were delivered; "a command is never assumed to have worked. The redraw waits for the observed echo" (R6) (`:58`, `compositor_adapter.h:106-111`);
- reconnect with backoff, full resync on reconnect, never publish a patch (`:37-40`);
- a `workspace` event with `change: "reload"` → full resync (README `:23`);
- "Sway numbers workspaces globally. Per-monitor workspace numbering is done by CUBS's naming, not by the compositor." (`:64-65`) — matches Tom's 1–9 top / 10 bottom scheme;
- WmSnapshot shape: `WmOutput{id,name,width_px,height_px,scale,focused}`, `WmWorkspace{id,name,index,output,focused,active,urgent}`, `WmWindow{id,toplevel_id,app_id,title,workspace,focused,fullscreen,urgent}`, `mru[]` (`wm_snapshot.h:198-236`);
- WmModel observer diff: `OnChildAdded/Removed/Moved`, `OnItemChanged`, `OnFocusChanged` (`wm_model.h:140-150`) — the React equivalent is keyed lists, but the "model changes only on echo" rule stays;
- `WmCommand.Kind`: focus workspace/window, rename, move to workspace, toggle scratchpad, session exit, reload config (`compositor_adapter.h:34-42`); errors `kNotConnected|kCapabilityMissing|kRejected|kNoEcho`.

Tests the adapter spec demands (`:187-198`): unit tests against recorded IPC transcripts (frame
split across reads, reconnect mid-snapshot); run gate under a nested headless compositor with
`SWAYSOCK`/`I3SOCK`/… unset first; first acceptance target "a rail click that switches a workspace
and is observed through the echo".

### 3.9 Keybinding rendering (slot files)

MEASURED `schemas/keybinding-rendering.md`. Verdict: **KEEP the principles, DEFER the generator**
(tonight's binds are hand-written in `home/dot_config/sway/binds.conf`).

| Principle | Exactly | Pointer |
|---|---|---|
| Slots, not ownership | the dotfiles declare `include ~/.config/sway/cubs.d/*.conf` and `set $mod Mod4` / `set $cubs_rail_width 56`; the shell writes only the included files | `:8-11`, `:130-131`, `:137-142` |
| One file per plugin per slot; write first, then apply | live binding where allowed, else reload ("a reload discards runtime bindings") | `:12-17` |
| The user wins | slot include sits before the user's bind block; the shortcuts page shows overridden rows as locked with file and line | `:18-21` |
| Conflicts block enable | `plugin check` compares every fragment and the compositor's live bindings | `:22-23` |
| Dispatch on sway | `bindsym $mod+Shift+Escape nop cubs example.power-menu toggle`; payload `nop cubs <plugin-id> <command> [<json>]` | `:159-166`, `:181-186` |
| Flags | `release` → `bindsym --release`; `locked` → `bindsym --locked`; `mode` → `mode "<name>" { … }`; `when` evaluated by the shell at dispatch | `:208-213` |
| Key translation | `Mod`→`$mod`, `Super`→`Mod4`, `Alt`→`Mod1`, `Comma`→`comma`, letters lower case | `:146-155` |
| Gestures | `bindgesture swipe:3:up exec cubs call cubs.launcher toggle` (no binding event for gestures) | `:228-234` |
| Other slots | menus `$XDG_STATE_HOME/cubs/slots/menu/<plugin>.json`; launcher `.desktop` files `X-Cubs-Managed=true` | `:134-135` |
| Golden outputs | `cli/testdata/{scroll,niri,hyprland}/*.conf|kdl` re-rendered by `tools/validate.sh` | `cli/README.md:9-11` |

Keys CUBS itself proposed (MEASURED): `Mod+Shift+Escape` power menu, `Mod+Ctrl+L` lock,
`Mod+Grave` rail collapse (**conflicts** with herdr-sway-context's Mod+grave), `F9` music scratchpad,
`$mod+Comma` open settings, `$mod+d` launcher (`compositor-adapters.md:59`), in-Chrome `Ctrl+Shift+K`.

### 3.10 Theme input

MEASURED `style/tokens/README.md`, `style/theme-map.json`, `examples/themes/*/colors.toml`,
`examples/themes/README.md`.

| Aspect | Exactly | Verdict |
|---|---|---|
| Format | an Omarchy theme directory: `colors.toml`, `icons.theme`, `backgrounds/`, optional `shell.toml`, optional `light.mode`; community Omarchy themes work unchanged | REPLACE with `~/.config/theme/gpuix-shell.json` (BRIEF §3.5) but **use the same key names** so a later Omarchy import is a rename |
| Canonical keys | `mode`, `accent`, `selection`, `muted`, `background`, `dark_background`, `lighter_background` (+`darker_background` in light), `foreground`, `dark_foreground`, `light_foreground`, `bright_foreground`, `red yellow orange green cyan blue magenta` + `bright_*` | KEEP as the JSON schema |
| Cascade | `color0 = background`, `color7 = foreground`, `color8 = muted`, `color15 = bright_foreground`, `bright_*` = +20 % white when absent, `cursor` and `selection_foreground` = `bright_foreground` (`theme-map.json:11`) | KEEP in the HM renderer |
| Extra keys (Tom's) | `brand` `#d97757`, `desktop_background`, `hyprland_active_border`, `inactive_border`, `tab_indicator_inactive`, `nvim_catppuccin_flavour`, `claude_code_theme`, `terminal_color7`, (`terminal_color0` light) — "kept, readable by plugins, never pinned"; P18 bare names | KEEP; `brand` is the Claude orange accent to use sparingly |
| Three application layers | 1 seed (`user_color` = background neutralised: "if max+min <= 16, or max >= 250 with chroma <= 4, use the channel average"); 2 exact pins (`theme-map.json:21-76`: background→base/surface/header; dark_background→base container/inactive header; lighter_background→surface1-5/elevated/section; foreground→on-surface; light_foreground→secondary/variant; dark_foreground→subtle/**disabled**; muted→divider/outline; accent→primary/**focus ring**/on-surface-primary; `on_accent` derived by contrast; selection/selection_foreground→text highlight; red→error); 3 per-surface `shell.toml` sections | KEEP the **role mapping** as the shell's token table (see §4) |
| `shell.toml` sections | `[bar]` background/background-alpha/text/active, `[popups]`, `[tooltip]`, `[notifications]` (countdown ring), `[launcher]` card+scrim, `[menu]` selected-background(-alpha)/selected-text, `[polkit]`, `[controls]` hover/pressed alphas, `[font] base-size`, `[spacing] scale`, `[lock]` ignored | OPTIONAL per-surface overrides in the JSON |
| Unmapped by design | blue/cyan/magenta/orange/brown and `bright_*`: no chrome role; green/yellow: no success/warning role in ui/color — status pills read them by name; gradients → first stop | KEEP: positive=green, warning=yellow, alert=red as the `role` enum needs |
| Live switching | `cubs theme apply` rebuilds mixers, resets the colour cache, every view gets `OnThemeChanged()`; "No surface is rebuilt" | KEEP: watch the `~/.config/theme` symlink (inotify), hot-swap the token object in React context, no restart |
| Chrome follows | `BrowserThemeColor` managed policy from a six-hex-digit request file via a system `.path` unit + root writer (P19; not in the repo) | Out of scope tonight; worth noting Tom's Chrome 152 supports `--refresh-platform-policy` (REPORTED `style/tokens/README.md:316-318`) |
| GTK | never written; `gtk.theme` names MacTahoe-Dark-grey / MacTahoe-Claude-Dark-orange / MacTahoe-Claude-Light-orange; icons MacTahoe-dark/-light | KEEP: untouched |
| No blur | "No CUBS panel asks for blur. Panels take the theme's background." | KEEP (BRIEF §1 "no blur, no frost") |

### 3.11 Rules R1–R27 mapped

| Rule | Keep / replace / drop for gpuix-shell |
|---|---|
| R1 Views only on layer-shell (never a toplevel) | **REPLACE**: layer-shell for rail/launcher/switcher/controls/notifications/OSD/power; `files` is an ordinary toplevel by Tom's new wish |
| R2 no terminal | KEEP |
| R3 fullscreen belongs to others; no file manager | KEEP first half; file explorer now in (T2) |
| R4 lock screen not a surface | KEEP |
| R5/R6 Views first, seam law (command then observed echo) | KEEP R6 verbatim; R5 → "design kit first, no custom paint" |
| R7 licences (MIT/BSD copied with notice, GPL read only) | KEEP: gpui-shell (Rust), tacit (QML) — check licences before copying |
| R8 single writers (shell writes only slot files; one GTK writer = `theme`; one owner per D-Bus connection) | KEEP |
| R9/R10 existing daemons only; one producer per domain, full snapshots | KEEP |
| R11–R14 plugins: data not pixels; words; minimal Lua; capabilities not names | KEEP as vocabulary; Lua moot |
| R15/R16 Chrome stock; bridge trusts only the extension | KEEP "Chrome stock"; bridge dropped |
| R17 stock components in the theme you pass; "no theme doctor and no icon fallback chain" | KEEP (design kit + token JSON) |
| R18 no new clocks | KEEP |
| R19 runtime-test | KEEP (`--render-node`) |
| R20 strict patches | n/a |
| R21 no effort estimates | KEEP |
| R22 unsandboxed, no Flatpak | KEEP (GPUIX binary via Nix) |
| R23 one compositor per session | KEEP (Sway) |
| R24 a Views program, not a browser | REPLACE: a GPUIX program, not a browser; no webview in the shell (GPUIX 0.10 has none anyway) |
| R25 credential modal is core, only password field | KEEP |
| R26 GTK themes are the user's | KEEP |
| R27 no release history before v1 | KEEP |

### 3.12 Open decisions P-list, re-read for tonight

| P | CUBS state | Tonight |
|---|---|---|
| P6/P31 lock screen / locker bound | none bound; swayidle turns monitors off | unchanged; `lock` verb runs `loginctl lock-session` (no-op without a locker) — note in MORNING.md |
| P8 slot-file location | `~/.config/<wm>/cubs.d/` vs `$XDG_STATE_HOME` because `~/.config/sway` is a symlink into the checkout | relevant if binds are generated: prefer `$XDG_STATE_HOME/gpuix-shell/sway.d/` included by absolute path |
| P9 `ui` node set vs the 33 atoms in the theming notes vs Views Canvas `JsonViewBuilder` | first cut (29 nodes) | the design-kit handoff atoms (U-01..U-19) are the reference now |
| P18 theme paths, extra keys bare | PROPOSED | moot (JSON fragment) |
| P19 Chrome policy writer | dotfiles, system `.path` unit | out of scope |
| P21 MacTahoe translucency without blur | unfrosted | Tom 10-20: flat and opaque; moot |
| P26 ported tile/slider faces vs pure stock | ported for the look | design kit decides |
| P28 bar pills fed by sources | planned, no schema | no bar; pills → rail footer |
| P29 one QS host vs bubbles | one host | one host |
| P30 T2 memory ceiling / crash budget | none | n/a tonight |

---

## 4. Design values found in this source

CUBS deliberately carries almost no visual constants ("stock components in the theme you pass").
What exists, with labels. BRIEF §3.3 / SHELLS-DIGEST §4 values win where they differ.

| Value | Number | Where | Label / status |
|---|---|---|---|
| Rail collapsed width = exclusive zone | 56 DIP (config 40–96) | `docs/architecture.md:362-363`, `examples/workspace-rail/cubs-plugin.json:34`, `keybinding-rendering.md:141` | MEASURED; BRIEF agrees (56) |
| Rail expanded flyout width | 240 DIP (160–480), **no exclusive zone** | `examples/workspace-rail/cubs-plugin.json:35`, `shell/rail/rail_view.h:52` | MEASURED; BRIEF says 220 with zone 220 (X1 option) — Tom's herdr-web-ui rail is 220/30/12/2/8. Use 220; keep CUBS's "flyout has no zone" for the hover case. |
| Proven June rail widths | output/8 expanded (12.5 %), output/20 collapsed (~5 %, ~128 px @2560); "36px … read as too cramped for the workspace badges" | `cowl_surface_manager.cc:118-128` | MEASURED (lifted, niri) |
| Bar height | 36 DIP ("--bar-height (32) + a little breathing room") | `bar_view.h:45`, `cowl_surface_manager.cc:143` | MEASURED; bar dropped |
| Launcher panel | 760×399 = 58 search + 1 separator + 5×56 rows + 44 footer + 16 insets; radius 14; glass fill `ARGB(0xCC,0x1c,0x1c,0x1e)` ("the ONE documented raw-color exception … alpha is load-bearing for niri blur-through") | `launcher_panel.h:65-73`, `launcher_panel.cc:56`, `:78-81` | MEASURED; BRIEF 700×580 wins; **no glass** (flat opaque) — row 56 / search 58 / footer 44 are reasonable row metrics to keep |
| Launcher max rows | 5 (fixed surface) | `launcher_panel.h:73` | MEASURED; GPUIX can grow, but a cap keeps the window stable |
| QS grid | `grid.columns` 1..6 | `ui-tree.schema.json:408-411` | MEASURED |
| Typography tokens | display, title, headline, body, body-strong, button, annotation, label | `ui-tree.schema.json:117-126` | MEASURED; map onto the Anthropic Sans scale |
| Spacing tokens | none, tight, normal, loose; `[spacing] scale` multiplier | `:107-113`, `theme-map.json:88` | MEASURED; INFERRED 0/4/8/16 px on Tacit's generous padding |
| Corner containers | none / rounded / rounded-top / rounded-bottom "from the LayoutProvider's shape tokens" | `:318-326` | MEASURED; BRIEF: 8/12 inner radii |
| Icon sizes | small/medium/large; iconButton xsmall..xlarge; image thumbnail..large | `:565-571`, `:776-784`, `:597-604` | MEASURED; numbers unspecified |
| Colour roles | default, subtle, primary, positive, warning, alert, disabled | `:95-105` | MEASURED |
| Palettes (noir / claude-dark / claude-light) | background `#000000` / `#1a1a1a` / `#f9f9f7`; accent `#70b8ff` / `#70b8ff` / `#0051c2`; selection `#264f78` / same / `#cde2fb`; muted `#818898` / same / `#6e7687`; foreground `#eaecf0` / same / `#131313`; light_foreground `#d3d7de` / same / `#52514e`; dark_foreground `#45475a` / `#52514e` / `#a5a49a`; red `#f47b85` / same / `#b80a18`; yellow `#f9e2af` / same / `#a66a00`; orange `#fbad60` / same / `#b24a00`; green `#9be963` / same / `#008000`; cyan `#5eeded` / same / `#007f80`; magenta `#cc7bf4` / same / `#8100c2`; brand `#d97757` all three; inactive_border `#373735` / `#373735` / `#d2d1c7`; hyprland_active_border `#555451` / same / `#a5a49a`; desktop_background `#000000` / `#20201f` / `#f0efec`; light: dark_background `#f3f3f0`, darker_background `#f0efec`, lighter_background `#ffffff` | `examples/themes/*/colors.toml` | MEASURED; converted "with no loss" from `home/themes/*.nix` (REPORTED `examples/themes/README.md:3-7`) — the live `.nix` files are the source of truth, these are a convenient flat view |
| Timings | none specified anywhere (fades via `WidgetFadeAnimator`, no durations) | `style/INVENTORY.md:51` | MEASURED absence |
| Fonts | "Fonts come from the user's configuration"; `[font] base-size` scale | `style/INVENTORY.md:68` | MEASURED absence; BRIEF: Anthropic Sans 12 UI, mono for figures |
| Notification cards / toasts | no numbers | — | SHELLS-DIGEST: 390 wide, max 4, 140 px cards |

---

## 5. Reusable code and data (exact paths)

Nothing in CUBS runs; what is reusable is **data, specs and small Python**. Licence BSD-3 (Tom's own
repo), so everything below may be copied with its header.

| What | Path | How to reuse tonight |
|---|---|---|
| Three palettes as flat key/value | `/home/tom/mecattaf/cubs/examples/themes/{noir,claude-dark,claude-light}/colors.toml` | cross-check the `gpuix-shell.json` fragment rendered from `home/themes/*.nix`; the key names are the JSON schema |
| Omarchy-key → colour-role binding | `/home/tom/mecattaf/cubs/style/theme-map.json:21-76` | the role table for `src/theme/tokens.ts` (base/surface/elevated/on-surface/secondary/subtle/disabled/divider/outline/primary/focus-ring/on-primary/highlight/error) |
| The `ui` tree schema (29 nodes, bindings, actions) | `/home/tom/mecattaf/cubs/schemas/ui-tree.schema.json` | the checklist for the design kit's component set; also a candidate JSON format for OpenUI → GPUIX mapping (BRIEF §3.7) since both are declarative trees with semantic roles |
| Plugin manifest schema + 23 invalid fixtures | `/home/tom/mecattaf/cubs/schemas/cubs-plugin.schema.json`, `/home/tom/mecattaf/cubs/tools/fixtures/invalid/*.json`, `/home/tom/mecattaf/cubs/tools/validate.py` | the shape of `src/registry.ts` (commands with id/title/icon/enablement/args/confirm/result; surfaces with kind/keyboard/anchor; keybindings; cli verbs) |
| Quick-settings trees (wifi, bluetooth, audio, dnd, media, footer, brightness, power menu) | `/home/tom/mecattaf/cubs/examples/quick-settings-*/ui/*.json`, `/home/tom/mecattaf/cubs/examples/power-menu/ui/{button,panel}.json` | translate 1:1 into React components for `gpuix-shell controls` and `power`; the field names are the snapshot schema for each producer |
| T2 JSON-RPC loop (complete, never run against a host) | `/home/tom/mecattaf/cubs/examples/power-menu/bin/power-menu` (120 lines), `/home/tom/mecattaf/cubs/examples/quick-settings-brightness/bin/quick-settings-brightness` (121 lines) | the brightness one is a drop-in sysfs reader: `drm_backlights()`, `read_level()`, floor-1 % `set_level()` → port to TS in `src/controls/brightness.ts`; the power-menu `ACTIONS`/`BROKER` tables → `src/power/actions.ts` |
| Sway/scroll IPC recipe | `/home/tom/mecattaf/cubs/docs/compositor-adapters.md:48-69`, `/home/tom/mecattaf/cubs/shell/wm/adapters/scroll/README.md`, `/home/tom/mecattaf/cubs/shell/wm/compositor_adapter.h`, `wm_model.h`, `wm_snapshot.h` | spec for `src/sway/ipc.ts` (two sockets, subscribe-then-query, GET_TREE coalescing, SEND_TICK barrier, backoff) and `src/sway/model.ts` types |
| niri IPC client (lifted C++: FdWatcher, line decoder, reconnect/backoff, resync) | `/home/tom/mecattaf/cubs/shell/wm/adapters/niri/niri_ipc_client.{h,cc}`, `niri_events.{h,cc}` | pattern only (C++), not Sway |
| Rail acceptance tests (7) | `/home/tom/mecattaf/cubs/shell/docs/ccd-switcher-behaviour.md:59-73` | `tests/gpuix-shell/smoke_rail.py`: groups/order; focused row follows compositor focus; click → focus only after echo; collapse changes width and zone together and the usable area by the same amount; Escape never unmaps; Ctrl+wheel no zoom; compositor window list holds no shell window |
| Layer-surface geometry per surface (proven on niri) | `/home/tom/mecattaf/cubs/shell/app/cowl_surface_manager.cc:131-300` | sanity values for `render(node,{layerShell:{…}})`: osd overlay/bottom/zone 0/keyboard none; notifications top/top+right/zone 0/none; launcher overlay/zone 0/exclusive; rail top/left+top+bottom/zone = width/on-demand |
| CLI spec and exit codes | `/home/tom/mecattaf/cubs/cli/SPEC.md`, dispatch skeleton `/home/tom/mecattaf/cubs/cli/cubs` (Python) | `gpuix-shell` CLI verbs and exit codes (0/1/2/3/69) |
| Headless eval harness pattern | `/home/tom/mecattaf/cubs/shell/tools/headless-eval.sh` (refuses to run unless PID 1 is bwrap; unsets `SWAYSOCK`, `I3SOCK`, `NIRI_SOCKET`, `HYPRLAND_INSTANCE_SIGNATURE`) | copy the guard into every `tests/gpuix-shell/smoke_*.py` |
| `no_stubs.py` + fixtures | `/home/tom/mecattaf/cubs/shell/tools/no_stubs.py`, `no_stubs_fixtures/` | a "no TODO/stub" lint for the TS tree if wanted |
| Extension native-messaging verbs | `/home/tom/mecattaf/cubs/extension/README.md:73-92`, `/home/tom/mecattaf/cubs/extension/lib/host.js` | shape of the shell.sock JSON-RPC verbs |
| Power-menu / rail / scratchpad golden Sway fragments | `/home/tom/mecattaf/cubs/cli/testdata/scroll/*.conf` | exact `bindsym … nop …` lines if the `nop` dispatch is adopted |

---

## 6. Gaps, unknowns, conflicts

| # | Gap | Detail | Suggested assumption (for ASSUMPTIONS.md) |
|---|---|---|---|
| G1 | **File explorer ruled OUT in CUBS, IN on 2026-10-20** | R3/P1/P2 (Tom 2026-10-01): "Nautilus stays". BRIEF §1 (Tom 2026-10-20): "what is of interest is mainly the file explorer". | Newer ruling wins. `gpuix-shell files` is an ordinary toplevel window (not layer-shell), and the GTK portal chooser still goes to Nautilus (P1 stands). |
| G2 | **Notes5 scoping corpus missing** | `docs/open-decisions.md:7` and six other pointers cite `~/Downloads/wm-scoping/notes5/` (RATIFY.md, naming.md, views-first-rebalance.md, theme-input.md, scroll-fork-hooks.md, themes/nix-palette-to-omarchy.py, "the 33 component atoms in the theming notes"). The directory does not exist on this machine. | Treat this note + the design handoff as the reference; do not search further tonight. |
| G3 | **Credential modal not in BRIEF §3.2** | R25 makes it core; the wifi menu (secured networks) and bluetooth pairing (PIN/passkey) cannot work without an NM secret agent and a BlueZ agent. polkit too. | Put the agents in `gpuix-shell controls` (one overlay window, exclusive keyboard while a prompt is up). Register `org.freedesktop.NetworkManager.SecretAgent` and `org.bluez.Agent1` over dbus-next. Polkit agent deferred. |
| G4 | **Alt+Tab window cycle and cheat sheet not in BRIEF** | CUBS lists `cycle` and `cheatsheet` as core surfaces with CLI verbs. | Fold both into `gpuix-shell switcher` as modes (Mod+i workspaces; Alt+Tab MRU windows via a Sway `mode "cycle"` with `--release`; `?` cheat sheet from binds.conf). Low priority. |
| G5 | **Where settings live** | CUBS: six Chrome-extension pages (shortcuts, appearance, plugins, compositor, notifications, connection). BRIEF §3.8: the shell only launches web utilities; `herdr-web-ui` is Tom's rail/desk. | No settings surface tonight; `gpuix-shell config get|set` + the HM-rendered JSON is the settings story; a shortcuts list ships inside the launcher. |
| G6 | **No popups in GPUIX** | CUBS relies on `xdg_popup` children for menus, bubbles, tooltips (never proven live either: "explicit-grab caveat open", `shell/PROVENANCE.md:106`). GPUIX 0.10/0.11: one window per renderer, no popup API (SHELLS-DIGEST §4 limits). | Context menus and tooltips are drawn inside the owning window (the flyout is already its own overlay surface). Verify in the GPUIX API (`/home/tom/Downloads/gpuix/packages/native/index.d.ts`) whether a second `render()` per process is possible in 0.11. |
| G7 | **`nop` binding dispatch vs CLI calls** | CUBS's zero-fork key path (`bindsym … nop cubs …` → `binding` IPC event) is real on Sway. BRIEF §3.2 says "Sway binds call the CLI". | Start with CLI calls (simple, works when the daemon is down); keep `nop` as a documented upgrade in the rail daemon (it already holds the subscribed socket). |
| G8 | **Mod+Grave collision** | CUBS rail `toggle-collapsed` = `Mod+Grave` (`examples/workspace-rail/cubs-plugin.json:43`); branch `herdr-sway-context` binds Mod+grave to kitty/Chrome swap (BRIEF §2). | Rail collapse on a different chord (INFERRED `Mod+Shift+grave` or a rail button only). |
| G9 | **Rail width 240 vs 220** | CUBS 240 (Chrome vertical tabs); BRIEF/herdr-web-ui 220. | 220. |
| G10 | **No timings, no fonts, no icon sizes in CUBS** | by design (stock Views). | Take from the design handoff; Tacit's QML `Appearance.qml` (BRIEF §2) for timings. |
| G11 | **Producer snapshot schemas never written** | `contributes.sources[].schema` is optional and no example ships one; field names are only what the trees bind to (§3.2–3.3). | Define TS types per producer from the tree bindings in §3.2; treat them as the schema. |
| G12 | **DDC brightness for external displays** | explicitly "not covered" (`examples/quick-settings-brightness/README.md:14-15`); LG 5K on the coordinator has no DRM backlight. | Hide the slider when no DRM backlight; `ddcutil` later. |
| G13 | **Lock** | `loginctl lock-session` does nothing without a locker (P31 none bound). | Ship the verb; MORNING.md asks Tom whether to bind swaylock. |
| G14 | **Tray** | CUBS lists a tray producer and `tray/context` menu location but no spec; SHELLS-DIGEST says out unless asked. | Out. |
| G15 | **Chrome theme following** | the `BrowserThemeColor` policy writer (P19) is the only piece that would make Chrome match the shell theme live; it needs a root-written policy file. | Out of scope tonight; note for Tom. |
| G16 | **Licence check for the other shells to mine** | R7: GPL read-only. gpui-shell (Rust), tacit (QML) licences not checked in this note. | Reader of those sources must check before copying. |
| G17 | **Nothing here was ever run** | every C++ file "does not build here yet"; the T2 examples "never run against a CUBS process"; the Lua "has not been run". | All MEASURED/REPORTED claims above are about text, not behaviour. |

What I did not verify: the claimed Chromium compile status of the lifted code, the claim that
`tools/validate.sh` prints `VALIDATE-OK` (not executed; read-only task), and the "no loss"
conversion of the `.nix` palettes (the converter script is missing, G2).

End of note. Read-only task; this file is the only write.
