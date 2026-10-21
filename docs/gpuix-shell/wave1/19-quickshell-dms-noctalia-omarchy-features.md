# 19. The "quickshell-level" feature list: Omarchy, DMS (Dux), Noctalia, caelestia, illogical-impulse, Tacit → gpuix-shell

**v2, written 2026-10-21 ~00:40 CEST** by a second wave-1 reader (Fable), on top of the v1 pass of ~23:24 CEST. Read-only; this file is the only one written. Tom is offline; nothing here waits on him. Labels: **MEASURED** (read tonight from a file, a `gh api` listing or a fetched upstream page; path or URL given), **REPORTED** (another file says so; path:line given), **INFERRED** (my reasoning). Where a Tom quote has a date it comes from the BRIEF, a dig report or a sibling wave-1 note that carries the timestamp; typos are his.

What v2 adds over v1: (a) the **stance column is now sourced row by row from Tom's March-2026 annotated feature matrix** (`~/notes/references/devlogs/1h26/april-webshell-refs/ANNOTATED-feature-matrix.md`, 280 rows with MUST/SHOULD/COULD/WONT marks; REPORTED via `wave1/30-notes-frontend-lineage-and-omarchy-dms.md` §3.1, cited below as `AM #<row> (L<line>)`), reconciled against the 2026-10-20 order; (b) the **plan column carries tonight's `SCOPE.md` row ids (`S-###`)** so a builder can jump from a feature to its acceptance row; (c) the full **IPC verb vocabularies** of Omarchy, DMS and Noctalia v5 were fetched and are tabulated as a crosswalk to `gpuix-shell` socket verbs (§3D); (d) five of v1's twelve gaps are closed (§6).

How to use this note: **§3B (the UNION table)** is the deliverable: one row per feature, which shells have it, Tom's stance with its source, and a must/should/later/out call for gpuix-shell tied to SCOPE ids. §3A is the per-shell inventory the union was built from. §2 is the authority behind every stance cell. §3C is the Sway-seat view (what runs today, keep/replace/new). §3D is the IPC crosswalk. §4 values, §5 reusable paths, §6 gaps.

Upstream snapshots used (MEASURED by `gh api repos/<owner>/<repo>/contents/...` listings and WebFetch tonight; none of the shells was run):

| Short | Repo and ref | What was read (v1 + v2) |
|---|---|---|
| OM | `basecamp/omarchy` default branch (MIT: `LICENSE` fetched, MEASURED v2) | `docs/omarchy-shell.md` (452 lines; v2 re-grepped lines 122-134, 191-219, 292), `docs/menu.md` (186), `docs/notifications.md` (225), `docs/theming.md` (headings), `shell/plugins/README.md` (130), `shell/plugins/bar/README.md` (189), `shell/plugins/agents/README.md`, `shell/plugins/osd/OsdModel.js`, `default/omarchy/omarchy-menu.jsonc` (451), `config/omarchy/shell.json` (v2: stock bar layout, idle, dock pinned), `themes/tokyo-night/` listing (v2: `colors.toml`, `shell.lock.toml`, `preview-unlock.png`), directory listings of `shell/{Commons,Ui,plugins,services}`, `config/omarchy/{defaults,extensions,hooks,themed}`, `bin/` |
| DMS | `AvengeMedia/DankMaterialShell` master (README H1 is now **"Dux Shell"**, docs at `duxlabs.dev`; CLI still `dms`, Arch package `dms-shell`, Nix module `homeModules.dank-material-shell`) | README, `quickshell/Modules/**`, `quickshell/Modals/**`, `quickshell/Services/`, `core/internal/`, `duxlabs.dev/docs/dms/keybinds-ipc` (v2: the complete target→method list, §3D), `duxlabs.dev/docs/dms/plugins-overview`, `duxlabs.dev/plugins` |
| NOC | `noctalia-dev/noctalia` main (v5, native C++ on Wayland + GLES; **not** Quickshell since v5) and `legacy-v4` (the Quickshell one) | README, `ARCHITECTURE.md`, `example.toml`, `src/**` listings, `docs.noctalia.dev/noctalia/ipc/{index,system-controls,surfaces,media-and-ui,shell}` (v2: every command, §3A.3 and §3D), `docs/user/{bar,launcher,plugins,control-center}` |
| CAE | `caelestia-dots/shell` main (GPL-3.0) | README (v2: full `shell.json` section list), `modules/**`, `services/` listings |
| II | `end-4/dots-hyprland` main (`dots/.config/quickshell/ii/`) | README (v2: "Notable features", `Super+/` keybind list), `modules/ii/**`, `services/` listings |
| TAC | Tacit ISO at `/home/tom/saturday-tacit/iso-files/usr/share/tacit/shell/` | via the three research notes below; not re-read tonight |
| GS | `/home/tom/Downloads/gpui-shell/README.md` (Rust GPUI shell, local clone) | README |

Local sources (MEASURED, read in full): `/home/tom/saturday-tacit/research/ecosystem/{shells.md,apps_framework.md,tacit.md}`, `/home/tom/saturday-tacit/research/Quickshell apps and desktop ecosystem.md`, `/home/tom/today/2026-10-17-frank/design-handoff/dig/02-quickshell.md` (160 lines), `/home/tom/.wt/dotfiles/gpuix-shell/docs/gpuix-shell/{BRIEF.md,ASSUMPTIONS.md}`, `SCOPE.md` (headings + the rows cited), and the sibling wave-1 notes `11`, `18`, `23`, `30` in this folder (v1 also read `01`, `02`, `04`, `05`, the worktree's `home/dot_config/sway/*`, `home/vicinae.nix`, `home/dot_local/bin/{osd,wallpaper}`, `docs/vicinae-research.md`).

---

## 1. What this source is

This is a feature census, not a design study. The four Tacit-era notes (2026-10-17, `/home/tom/saturday-tacit/research/`) answer "what does Quickshell host beyond a bar"; dig 02 (2026-10-17 05:30) answers "what does Omarchy donate"; both already tell the gpuix-shell builder the rule that governs this whole note: **"we re doing functionality pull from quickshell NOT visuals or aesthetics whatsoever"** (Tom, 2026-10-14; REPORTED dig/02:11 and wave1/01:90). Tonight's addition is the exhaustive per-shell list the orchestrator asked for ("having a comprehensive list of all the options is important", BRIEF:16-17) and the union with a plan column.

The second authority behind this note is older than any of the shells' current docs: in **March 2026** Tom annotated, row by row, a 280-feature matrix compiled from 16 Quickshell shells (DMS, noctalia, Ambxst, caelestia, eqsh, nucleus, whisker, tpaau, sshell, ChromeX, dart, Kriti, HyprQuick, binarylinuxxdots, snes19xx, niri-panel) with MUST / SHOULD / COULD / WONT / DONT and a sentence of reasoning each (`~/notes/references/devlogs/1h26/april-webshell-refs/ANNOTATED-feature-matrix.md`; counts 77 MUST, 55 SHOULD, 97 COULD, 51 WONT; REPORTED wave1/30:30 and :304). That is the "deeply annotated priorities list" Tom pointed at in the 23:20 addendum (BRIEF:148-151). It was written for niri + QuickshellX + SolidJS; the compositor and runtime are gone, the **feature marks still stand unless a later ruling reversed them**, and §2 lists every reversal.

Three corrections to older lists, so nobody builds against stale names (MEASURED tonight):

1. **DankMaterialShell has been renamed Dux Shell** (README H1 "# Dux Shell"; docs `duxlabs.dev`; sister repos `dux-greeter`, `dux-calendar`, `dux-gop`, `dux-search`, `dux-qml-common`, `dux-go`). This note says DMS throughout.
2. **Noctalia v5 is not a Quickshell shell.** README: "Built on Wayland and OpenGL ES with no Qt or GTK dependency." Only `legacy-v4` is QML (REPORTED `shells.md:54-60`; MEASURED `ARCHITECTURE.md`). It is the closest public analogue to a gpuix shell in architecture (four-phase frame, one layer surface per panel, `CompositorPlatform` with a `sway` backend, Luau plugins) and is cited here for **function**, never for look (it "always publishes blur regions", dig/02:142).
3. **Tacit's Sway backend is commented out** (`services/WM.qml:24`, REPORTED `tacit.md:51`); Tacit's aesthetic is the reference Tom named ("the aesthetic that was acheived with this tacit os quickshell config: this is what i would like to remain close to", BRIEF:25-28), but none of its compositor wiring ports.

---

## 2. Verbatim Tom rulings relevant to the desktop shell (with dates)

Newest first inside each theme. A ruling marked **superseded** is kept so a builder sees the reversal.

**The order (2026-10-20, ~22:50 and ~23:05 CEST, BRIEF:9-31)**
- "the 'ultimate' gpuix-based shell ; that would be at the same level as quickshell as it was scoped for the desktop environment: in the case of dankmaterialshell ; noctalia ; and omarchy"
- "the crux of it is that we write scripts and functionality that is either a bespoke swaywm shortcut ; or a mod+d menu (vicinae remplacement) that presents a given functionality. notify-send remplacement to mako ; a left bar with workspace switcher that remplaces waybar"
- "there is a lot of herdr-web-ui centricity here especially on the left sidebar idea ; but having a comprehensive list of all the options is important."
- "keeping the anthropic font that i have ... is important. i m also expecting us to be close to the current minimal 'noir' colorscheme with the possibility to switch to claude 'light and dark' variants that are already in scope."
- "the rest, including scripts and other functionality, you can use what comes instinctively to you. for wifi menu, or bluetooth pairing menu; etc."
- "lately i saw 'tacit' dotfiles ... in my case what is of interest is mainly the file explorer ... more importantly however is the aesthetic that was achieved with this tacit os quickshell config: this is what i would like to remain close to (of course, different font than the one i want, but i like the vanilla-ness of it). openUI for the desktop shell is not quite known"
- "the 'boundary' between personal desktop os shell versus common utilities (webui + macos native + wayland native; say for the email or crm utilities) should already be clear."

**Addendum (2026-10-20, 23:20 CEST, BRIEF:143-166)**
- "make sure that the work you do will set the foundation for my subsequent work on achieving the world's most complete linux desktop shell without using quickshell. gpuix as the frontend all the way"
- "as early as 6 months ago did i describe the 'ultimate desktop shell' with at one time a very detailed set of rulings with deeply annotated priorities list ... the spirit was very correct, even though i had not captured yet that i would be using herdr as centrally" → the March matrix (§1) and the June-11 "Ultimate Desktop Shell" taxonomy (wave1/30:32).
- "the vicinae implementation is also of interest so make sure to capture that as well" and "a full implementation of the linux wayland sway facing https://github.com/vicinaehq/vicinae ... would be impressive to see. gpuix for the win."
- "i would like to have a navidrome music selection in the gpuix shell ; so a demo implementation of that would be very nice to have tomorrow morning ... raycast+spotify level searching and playing control from within the launcher"
- "this is NOT ONLY about navidrome.. but indeed a welcome set of utilities you can demo for me"
- "using https://github.com/thesysdev/openui fully with what's given ; following my own desired anthropic font and existing colorscheme"

**Look and what to copy (2026-10-13/14, Codex pivot night; REPORTED wave1/01:81,90,122,130 and dig/02:11)**
- "whatever you just opened: i love it. this is good enough to also become a functional remplacement to waybar, vicinae and mako notifications. drawing insporation from omarchy's implemetnatipn of wayshell in fact." (10-14 ~22:16Z)
- "we re doing functionality pull from quickshell NOT visuals or aesthetics whatsoever" (10-14 ~22:25Z)
- "as if it was designed by anthropic claude 1st party native implementations - bar the font" (10-13/14, wave1/05:124)
- "i want to use the claude anthropic font, the color scheme and selector, and the github primer react theme kit" (10-13, wave1/01:74)
- "hyprland is just sway with animations and best in class blur." then "let s tick to sway window manager. less effort.." (10-14; wave1/01:60, dig/02:22). INFERRED with BRIEF:43-44: no blur, no frost, flat and opaque.
- 2026-10-06, on dropping the otto compositor: "Frosting, animations and the otto file manager was just not enough" (wave1/04:167).
- 2026-09-25/26 on Tacit (`~/notes/.../browser-tab-bankrupcy/watchlist-unixporn.md:30-35`, REPORTED wave1/30:127): "amazing qt work: browser, file explorer, jsonl-thread converter and what is seemingly a coding editor; … we keep looking for htis. the looks of these dotfiles are stunning."

**The separation (2026-09-27, `FE/00-RULING-2026-09-27-the-separation.md:5-8`, REPORTED wave1/30:129)**
- "views for OSD: 'anything that goes through fzf launcher for me today' plus notifications, bar, launcher with icons, workspace switcher, clipboard menu. on the CUBS side we control wifi, bluetooth etc. (in a lit-style default interface that can be controlled)." → tonight's surfaces are this list with "views" replaced by GPUIX; wifi/bluetooth moved into `controls`.

**Bar, rail, switcher**
- 2026-10-07: "i have been using a bar-less setup for almost a year now. the only thing that would have been useful is a left sidebar" (dig/02:24).
- `home/dot_config/sway/config:2` (MEASURED): "# No bar: Vicinae is the command surface; Mako owns notifications."
- 2026-10-13: "one sway-wired workspace switcher that can be toggled with mod i ; with herdr-provided status indicators. only for the top display" (wave1/01:122).
- 2026-10-13: "for ht left bar, i want you to copy the same proportions as the views c++ left tab bar that we saw from google chrome." (wave1/01:130) → 220/30/12/2/8.
- 2026-10-14 (cc 56e498e4 idx [37]): "sway has a contextual launcher, a herdr leftbar that is disjinted and contol sway workspaces, clipboard history.. all that stuff that macos version doesn't have." and "macos has parity with the 'tray/dock' items: crm, email, projects, files, the vesence ones".
- 2026-10-14 midday (wave1/05:96): "the bottom macos tab bar: utilities like email etc can go below. herdr tabs on the left with sway and herdr control ;"
- 2026-10-17 (SHELLS-DIGEST:252): "on the sway devices, the left bar of the ai chat is a waybar style workspace (1>9) launcher".
- BRIEF:48: "no top bar on the Linux head"; BRIEF:36-38: Mod+1..9 top display, Mod+0 bottom display = Chrome, nine-slot cap.
- March 2026, AM #27 (L75): "MUST, in fact in my concepts i had the workspace switcher as a separate left horizontal bar, whereas all the other modules exist in the top bar." → the left bar won; the top bar died.
- AM #20 (L56): "MUST, and very important … one ipc toggle should control only one bar (in case there are multiple bars)"; AM #12 (L41): "i will in fact have multiple simultaneous bars in my config, and want to be able to toggle one but not the other"; AM #28 (L77) clock: "MUST, but no need to do anything fancier than configurable time and date. the minimal eqsh one was sufficient."

**Launcher, clipboard, keys**
- March 2026, AM L238 (general note): ">>> GENERAL NOTE on 1.4 LAUNCHER: my shell's launcher in its ideal form will be visual equivalent to macos' RAYCAST. i found it to be the most powerful feature by far. there was a qt launcher called vicinae that tried to reproduce raycast; i could revisit it. but dankmaterialshell's launcher does a great job at getting close to it. we start with the dms implementation as reference and then decide if we want to go beyond"
- 2026-10-14 01:26Z: "for the launcher, feature parity at least with vicinae ... including how it interacts w google chrome tabs is very desirable" (dig/02:23).
- 2026-10-12 (dotfiles T-2): "we keep vicinae actually.. i was getting a little carried away there when i said let's delete it. it's good fucntionality." — **superseded** by the 10-20 order "mod+d menu (vicinae remplacement)" (wave1/05:130).
- 2026-10-12: "volume keys through viciane popup yes i roll back on that; the way we control brightness and volume should be keypress>sway>script execution, no need to tie in vicinae if we don't have to" (wave1/05:115). Binding; the shell's OSD is a *display* the scripts call.
- 2026-10-12: "make the font larger than 11 (12 or 14, need to decide, start at 12)" (MEASURED `home/vicinae.nix:37` comment).
- AM #86 (L203): "MUST, it's important for me to have the clipboard history shown in the same aesthetic as the launcher; also making sure that we are displaying images (i use cliphist, prefer not to create special rust functionality as i found DMS reinventing the wheel with their clipboard implementation)"; AM gap row L634: native clipboard manager "COULD. discussed externally. to be revisited later. could convince me to move away from cliphist". BRIEF:113 chooses an own store fed by `wl-paste --watch`; tension recorded (SCOPE S-145 builds the own store).
- AM #90 (L211): favourites "MUST, and caelestia's sqlite frequency is very cool"; #96 (L223) action panel "SHOULD, this is a nice addition that makes our launcher raycast-like"; #98 (L227) web search "COULD … little added value"; #101 (L233) i18n "DONT i explicitly reject i18n support for now. this is MY shell".
- Nov 2025 wishlist (`devlogs/1h26/dms-productivity/final-shell-function.md:1-8`, REPORTED wave1/30:9): "tailscale status in bottom right / clipboard manager with picture support / emoji picker / augment current pomodoro / ocr on text select / on screen keyboard / hotkeys visualizations / mod k leads to something different, new launcher: experimenting w vicinae".

**Notifications, OSD**
- AM #65 (L156): daemon "MUST this one is non-negociable"; #67 (L160) centre "MUST, although the specific aesthetic of it is not clear in my mind."; #70 (L166) JSON history "MUST, useful"; #74 (L174) per-urgency timeouts "MUST"; #77 (L180) keyboard nav "MUST, dms hints overlay philosophy is very desirable"; #82 (L190) flood protection "MUST, to avoid dangerous or strange behavior on my system"; #71 (L168) DND "SHOULD, likely something i toggle with a keybind or a button on bar"; #72 (L170) rules engine "MUST, nice to have from DMS"; gap rows L623-654: scheduled DND "WONT", inline reply "WONT", snooze "WONT", per-app sounds "WONT; i barely expect nofitication sounds anyway".
- AM #122 (L281): "MUST. an OSD is very imprtant to have. I found the eqsh one to be very nice (which i m using right now)"; #123 (L283) brightness: "MUST but with a small caveat: i really don't care if the brightness is managed by my shell … doesn't really have to be fully integrated with the shell if it adds work"; #127 (L291) "SHOULD, like the dms 8 positions"; #129 (L295) "OSD suppression when panel open: SHOULD, since dms has it"; #130 (L297) interactive slider "COULD"; #131 (L299) glass OSD "COULD, if glassmorphism is easy" → **superseded** by no-blur.
- dig/02:109 (SHL-04): run state "never steals focus"; "only 'blocked' or 'needs input' may also notify".

**Control centre, network, bluetooth, power**
- AM L597 (blanket on rows 268-280): ">> WONT. i do not need a control center. this is not in scope for my project." → **superseded** by BRIEF:104-105 (`gpuix-shell controls`) and "wifi menu, or bluetooth pairing menu; etc."; June 2026 D20 "Network + Bluetooth: v1 scope — TOM RULED: critical to v1" (`cade-june11-reconciliation/02-DECISIONS.md:269-270`, REPORTED wave1/30:112). SCOPE §6 resolves it as "one domain list at a time", not a tile grid.
- AM #133-#147 (L307-335): WiFi scan/connect/password, disconnect, radio toggle, forget, saved list, hidden SSID, band/channel/BSSID detail, ethernet detail, VPN, airplane mode, NM SecretAgent: all "MUST"; #144 (L330) "MUST with special focus on tailscale"; #41 (L103) "MUST. it is CRUCIAL for me to know if i'm connected to tailscale, and possibly to know what other devices are connected on my tailscale network."
- AM #148-#151 (L337-343) BT power/scan/connect/pair-forget "MUST" ×4; #152 (L346) pairing agent "SHOULD"; #153 battery "SHOULD"; #154-#157 codec/pinning/discoverable/RSSI "SHOULD".
- AM #218 (L492) power menu: "MUST and in fact i want to mention that i like the new DMS powermenu the most with the ability to scroll/select through a list AND press and hold a given key to get the desired action"; #219/#220 hibernate detection, suspend-then-hibernate "SHOULD, low hanging fruit".
- AM #216 (L488) polkit: "MUST. i do not like the classic gtk greeter … dms and others have proven to me that polkit is implemented and easy to do with regular quickshell. this is low-hanging fruit"; #256 (L571) "MUST this one is important".
- AM #106 (L249) output/input device picker "MUST"; #109 (L255) ">100 % volume: DONT explicitly i like to have volume going from 0 to 100"; #113/#114 (L263-265) audio spectrum "DONT i don't care about that"; #115-#117 MPRIS play/seek/shuffle "MUST, love the progress bar".

**Lock, idle, session, settings**
- AM #203 (L463): "COULD this functionality is quite secondary. i bypass lockscreen by default on reboot (already implemented in my os with greetd automation); and when i need to rest my desktop i do `systemctl sleep`. … icebox for now"; L508 (rows 225-232): "COULD the entire idle management suite is not so important for me, i prefer to icebox for now"; #212 video screensaver "WONT, too fancy"; #267 "WONT i do not use SSDM whatsoever".
- AM #174 (L400) settings GUI "MUST" vs #200 (L452) "COULD … in my case it s a custom shell written for one person, so the utilities/plugins i need are configured from the dotfiles themselves. no need to 'enable' plugins or browse through them. … an ephemeral pomodoro widget has the same place as the main launcher (there is no hierarchy)"; 2026-06-30 (`june30/noon-chat.md:221`, REPORTED wave1/30:116): "i never asked for a toml config, not even sure that's the best way to configure things here". → config is Nix-rendered JSON, no settings surface (SCOPE S-009).
- AM #178 (L408) validation "SHOULD, but has to be something that is not hardcoded - it has to validate the config schema programaticaly".

**Theming, wallpaper, motion**
- AM #181 (L414): "WONT whatsoever: no material or material you (i don't like it); no matugen whatsoever as I explained we do not have a strict colorscheme we follow a standard minimal css token"; #186 (L424): "WONT … i do not need help managing my gtk or qt theme etc. that is what dotfiles are for"; #185 (L422) OLED: "MUST. OLED mode ie make the black colors #000000 is something that i do by default"; #184 (L420) auto dark/light "WONT: even if i do eventually add a light mode this should only be toggled manually"; #188 (L428) animation speed "WONT … i would make it none/short for snappiest experience"; #194 (L440) parallax "WONT i explicltly don't need parallax because it makes me dizzy"; #202 (L456) gradient/halftone "WONT"; #246 (L552) desktop widgets "WONT. i do not like widgets"; #57 (L135) wallpaper selector "COULD, i m not too big on wallpaper changing and other cosmetic trivialities".
- kmux B12/B13 (2026-03-26, REPORTED wave1/30:56-57): "One animation duration: 50ms for everything … `cubic-bezier(0.16, 1, 0.3, 1)`" "> yes for now"; "Animate ONLY opacity and transform" "> yes for nw". The kit later fixed the curve at (0.2, 0, 0, 1) (dig/02:146); the single-token rule stands.

**Utilities Tom has already ruled on**
- AM #234 (L528) screenshots "WONT because existing niri window manager is sufficient" (today: `screenshot` script + Satty); #236 annotation "WONT"; #237 (L534) colour picker "MUST but … the screenshot tool exists and is sufficient"; #238 (L536) OCR "SHOULD but with a twist … handled with qwen 3.5 opensource multimodal llm model" (today `screen-ocr-area` → Halogen); #235 (L530) recording "COULD … i already use OBS Studio"; #240 (L540) calendar grid "WONT. the calendar month grid display will be handled by a bespoke, fullscreen, on-brand calendar app FAR later down the line"; #243 (L548) night light "WONT, my gamma control and night light is set once and not from the shell. skip entirely"; #244 (L548) weather "COULD. very secondary"; #249 (L558) notepad "WONT. i use github-backed md notes"; #250 (L560) pomodoro "SHOULD … this will be the first feature i release AFTER base webshell"; #252 (L566) KDE Connect "SHOULD … 'android phone notification' is extremely desirable"; #254 Google Lens "WONT"; #257-#259 screen pin/measure/palette "WONT"; #29 (L79) tray "SHOULD, very nice to have but i won't be using it personally"; #39 (L99) privacy indicators "MUST, and i'll likely develop a specific widget around it"; #60 (L141) recording indicator "MUST, i will use that"; #59 BongoCat "WONT, we're building a serious shell"; #247 (L554) AI "COULD but much later down the line. i do not need an ai integration the way it is done in the reference qml shells. i have some ideas here so not marking this as won't".

**Not a shell ruling, so nobody misreads it**: "no wall clock ever. no defifitnitions" (2026-10-13, cc f3cd04ae idx [3]) is about planning documents, not about drawing a clock; AM #28 says the clock is "MUST".

**Standing facts (BRIEF:33-54)**: Sway only; herdr read-only, act through Sway; wallpaper `output * bg #000000 solid_color` (MEASURED `home/dot_config/sway/layout.conf:16`); themes noir/claude-dark/claude-light via `~/.config/theme` symlink; fonts Anthropic Sans / Serif / AnthropicMono Nerd Font; "performance is not really the thing i m looking for here"; never restart herdr or live Sway; no cron/timers in dotfiles; no secrets in git.

---

## 3A. Per-shell inventories (MEASURED from listings; names verbatim)

Each row names the surface as the upstream names it. "Sway?" says whether that shell runs on Sway at all.

### 3A.1 Omarchy shell (Quickshell, Hyprland-only, MIT; Sway? no)

One `omarchy-shell` process; everything is a plugin of six kinds `bar-widget | bar | panel | overlay | menu | service` (`docs/omarchy-shell.md:37-46`); IPC `omarchy-shell <target> <method>` with host methods `ping, summon, hide, toggle, togglePanelAt, call, rescanPlugins, reloadConfig, applyTheme <colorsB64> <shellB64>, toggleBarTransparency, cycleInput, setPluginEnabled <id> "true", enablePlugin, putBarWidget, moveBarWidget, setBarWidget, listPlugins, listShellConfig, debugBarGeometry` (`:112-134`). Stock config `config/omarchy/shell.json` (MEASURED v2): `version 1`; `idle {screensaver 150, lock 300}`; `bar.position top`, `bar.background opaque`, `bar.layout` left `[omarchy.menu, omarchy.workspaces]`, centerBegin `[omarchy.indicators]`, center `[omarchy.clock {format "dddd HH:mm", formatAlt "d MMMM 'W'ww yyyy", verticalFormat "HH\n—\nmm"}]`, centerEnd `[elsewhen, weather, system-update]`, right `[tray, keyboard-layout, agents, bluetooth, network, audio, monitor, power]`; `dock.position bottom`, `dock.pinned [org.gnome.Nautilus, chromium, foot, omacalc, omawrite, X, YouTube, …]`.

| Surface | Omarchy names (`shell/plugins/...`) | Notes |
|---|---|---|
| Bar | `omarchy.bar`; sections `left, centerBegin, center, centerEnd, tray, right`; drag to reorder, double-click to cycle background `clear/glassy/opaque`; `omarchy bar use|reset|defaults|position|background|put|move|set|get` | `bar/README.md:17-19`, `omarchy-shell.md:95-97`. Vertical bars 28 px, horizontal 26 px (`bar/README.md:81,176`). Notch-aware (`omarchy-shell.md:406-414`). |
| Bar widgets | `omarchy.menu, workspaces, clock (month grid, ISO weeks, timezone), media (MPRIS), indicators, system-update, tray, weather, microphone, audio, network, tailscale, agents, power, bluetooth, monitor, elsewhen (world clock), keyboard-layout, spacer, active-window`; custom `type: command` (Waybar-style JSON) and `type: qml` modules | `bar/README.md:57-75,95-138` |
| Bar indicators (inside `omarchy.indicators`) | `Dnd, NightLight, PasswordlessSudo, Reminder, RemoteSession, ScreenRecording, StayAwake` | `bar/indicators/` listing |
| Panels (popups off bar widgets) | `panels/{audio, bluetooth, clock, disk-speedtest, dropbox, elsewhen, monitor, network, power, speedtest, tailscale, weather, wifiqr}` | audio = master slider + output picker + per-app mixer; network = Wi-Fi scan, signal, connect, DNS provider; power = battery stats, power profiles, system info; monitor = brightness and laptop display |
| Agents panel | `agents/` (`Agent.qml, Main.qml, Panel.qml`): one icon + panel per AI subscription; limits first; several accounts with ACTIVE/Use/Autoswitch; prepaid balance; reads `~/.local/state/omarchy/agents/usage/*.json` written by `omarchy-agent-usage-update` | `agents/README.md:1-60`. The only shell surface that knows Claude/Codex/Grok quotas (dig/02:57-59). |
| Menu (launcher) | `omarchy.menu`: JSONC data tree `default/omarchy/omarchy-menu.jsonc` + user `~/.config/omarchy/extensions/omarchy-menu.jsonc`; entries with `icon, label, title, action, target, provider, aliases, description, when/checked/disabled` guards batched into one bash; providers `apps, fonts, power-profiles, languages`; `omarchy menu toggle|summon <route>|close|refresh|ping`; dmenu modes `select` and `input` with tempfile handshake, `--multiple`, `--on-change`, `--change-key` | `docs/menu.md:21-186`. Root tree (`omarchy-menu.jsonc` lines): `apps 24, learn 25, appearance 26, trigger 27, setup 28, install 29, remove 30, update 31, about 32, system 33` |
| Menu: `system` | `screensaver, lock, suspend, hibernate, logout, reboot, shutdown` (`:36-42`) | = power menu |
| Menu: `learn` | `keybindings, omarchy, hyprland, arch, neovim, bash, tmux-keybindings, herdr-keybindings, community` (`:45-53`) | keybind cheatsheet lives here (`omarchy-menu-keybindings`, `omarchy-menu-herdr-keybindings` in `bin/`) |
| Menu: `appearance` | `theme, background, font, top-bar.{hide,show,position,background,indicators.clock.*}, windows.{gaps,corners,transparency,one-window-ratio}, branding, dock.{autohide,always-on,position}, workspace-layout.{dwindle,scrolling,floating}, animations-on/off, unlock` (`:56-125`) | |
| Menu: `trigger` | `toggle.{idle-lock, notifications, nightlight, screensaver, crash-capture}, emoji, clipboard-history, reminder.{set,show,clear}, capture.{screenshot, screenrecord(.stop,.no-audio,.desktop-audio,.microphone,.webcam), text (OCR), qr, color}, transcode, share.{clipboard,file,folder,receive} (tailscale send), hardware.{laptop-display, mirror-display, hybrid-gpu, touchpad, touchpad-haptics, touchscreen}, tests.{network-speedtest, disk-speedtest}` (`:128-179`) | the "utilities" set Tom means by "wifi menu, or bluetooth pairing menu; etc." |
| Menu: `setup` | `monitors, keybindings, input, typing.{keyboard,input}, language, network.{dns.*, qr}, default.{agent (15 agents), browser, dictation, terminal, editor}, plugin.{enable,disable,add,clone,remove}, security.{fingerprint, fido2, sshd, ssh-agent, sudoless-docker, passwordless-sudo}, config.{hyprland,hyprsunset,xcompose}, direct-boot, reset` (`:182-256`) | |
| Menu: `install` / `remove` / `update` | package catalogues with `disabled:` presence guards (`:259-285`) | out of scope on NixOS |
| Notifications | `omarchy.notifications` service: own `org.freedesktop.Notifications`; one Overlay layer surface per output, input-masked to the deck; decks grouped per source (per site for browser notifications); toast lifetimes 5 s low / 8 s normal / critical sticky, ≤30 s; click routing order (`omarchy-exec-argv` → default action → sender pid → window by class/title → site → first link → focus app); persistence `live.json / history.json / quiet.json` (≤100 rows, 24 h); DND + per-source snooze; bypass for `omarchy-action`, critical `notify-send`, verification codes; icons resolved in-shell, never fetched; IPC `dismissOne, dismissAll, invokeLast, dismissStack, count, expand, snooze, snoozeAll, unsnooze, snoozes, codes, act, offer, togglePanel, openPanel, openSettings, closePanel, probe, clear, toggleDnd, setDnd, dndState` | `docs/notifications.md:1-110`. Files: `Service.qml, Toast.qml, DeedButton.qml, NotificationPanel.qml, Picker.qml, Store.js, Markup.js, Detect.js, Security.js, Icons.js, Layout.js, Delivery.js, Settings.js`; JS modules load in Node for tests. **MIT** (MEASURED v2) so porting pure JS by copy is allowed with attribution. |
| OSD | `omarchy.osd` panel: kinds `volume(-muted/low/medium/high), microphone(-muted), keyboard (backlight), brightness/display` (`osd/OsdModel.js:11-18`) | |
| Lock | `omarchy.lock` service on `WlSessionLock`, PAM `omarchy-lock-password` + `omarchy-lock-fingerprint`, blurred wallpaper poster; themes ship `shell.lock.toml` + `preview-unlock.png` (MEASURED `themes/tokyo-night/`) | keepLoaded |
| Polkit | `omarchy.polkit` service, `Quickshell.Services.Polkit.PolkitAgent` (`plugins/README.md:95-100`) | |
| Dock | `omarchy.dock` service: shown on floating workspaces only; `dock.pinned` desktop ids; `omarchy-shell omarchy.dock apps` grid | |
| Clipboard | `omarchy.clipboard` overlay + `capture.sh`; menu route `trigger.clipboard-history` | |
| Emojis | `omarchy.emojis` overlay | |
| Image picker | `omarchy.image-picker` overlay: wallpaper and theme picker, selection/done tempfile round-trip, async thumbnails (`plugins/README.md:55-82`) | |
| Reminders | `omarchy.reminders` overlay (`ReminderFlow.qml`), bar indicator `Reminder` | |
| Background | `background` plugin (layer Background) | wallpaper |
| Services | `battery, idle (screensaver 150 s, lock 300 s), media (MPRIS + bar widget), nightlight, remote-session` | `omarchy-shell.md:143-146` |
| Dev gallery | `dev-gallery` plugin | the "gallery per renderer" idea (U-19) |
| Theming | `themes/<name>/colors.toml` (accent, selection, muted, 4 bg, 4 fg, named hues; `red` = urgent) + `shell.toml` generated from `default/themed/shell.toml.tpl` (`omarchy-shell.md:216-219`, path named by the doc; **not fetched**, the `default/` listing was truncated); machine `~/.config/omarchy/shell.toml` watched live and wins over the theme's (`:191-194`); sections `[bar] [controls] [popups] [tooltip] [notifications] [launcher] [menu] [polkit] [lock] [image-picker] [spacing] [font]`; `[controls]` states `normal / hover-cursor / focus / selected` fill alphas + border; `[font] base-size` 12 with multipliers caption 0.833, bodySmall 0.917, body 1.0, subtitle 1.083, title 1.167, heading 1.333, display 2.0, displayLarge 2.333, iconLarge 1.5; `[spacing] scale` 1.0; pushed live by `applyTheme`; font family = fontconfig `monospace` alias | `omarchy-shell.md:197-404` |
| Plugin system | git repo with `manifest.json` (`schemaVersion, id, name, version, author, description, kinds, entryPoints, barWidget{displayName, category, allowMultiple, defaultSection, defaults, schema}`), `keepLoaded`; entry points expose `open(payloadJson)` / `close()`; capability-scoped facades but "unsandboxed code"; `omarchy plugin add|update|remove|enable|disable|clone|list|validate|catalog` | `omarchy-shell.md:12-98` |
| CLI surface (bin/) | ~330 `omarchy-*` scripts; shell-relevant families: `omarchy-audio-*`, `omarchy-brightness-*`, `omarchy-capture-{screenshot,screenrecording(-with-webcam),webcam-resize}`, `omarchy-clipboard-*`, `omarchy-menu-*` (clipboard, emoji, file, images, input, keybindings, plugin, select, share, timezone), `omarchy-network-*` (band, password, qr, speedtest, status), `omarchy-notification-*` (battery, dismiss, send, time, wait, weather), `omarchy-osd`, `omarchy-power-*`, `omarchy-reminder`, `omarchy-screensaver`, `omarchy-system-{lock,sleep-lock,lid-close,stats,wake}`, `omarchy-theme-*`, `omarchy-toggle-*` (animations, bar, idle, nightlight, notification-silencing, screensaver, touchpad, touchscreen, suspend), `omarchy-dictation*`, `omarchy-tailscale-{send,receive}`, `omarchy-weather-*`, `omarchy-webapp-*`, `omarchy-launch-or-focus(-webapp,-tui)` | MEASURED listing of `bin/` |

### 3A.2 DMS / Dux Shell (Quickshell QML + Go daemon; Sway? **yes**, named among "works best with")

| Surface | DMS names | Notes |
|---|---|---|
| Bars | `DankBar` (widgets below), `DBar`, island forms `DIsland` ("island" IPC: `open, toggle, show, close, cycle, status, notifications, openOn … centerOn, openInstance, toggleInstance, move, center`), `DDot`; IPC `bar reveal|hide|toggle|status|autoHide|manualHide|toggleAutoHide|toggleReveal|getPosition|setPosition` | `quickshell/Modules/` listing; `keybinds-ipc` page (MEASURED v2) |
| Bar widgets (`DankBar/Widgets/`) | `AppsDock, AudioVisualization, Battery, CapsLockIndicator, ClipboardButton, Clock, ColorPicker, ControlCenterButton, CpuMonitor, CpuTemperature, DWLLayout, DiskUsage, FocusedApp, GpuTemperature, IdleInhibitor, KeyboardLayoutName, LauncherButton, Media, MediaLyricLine, MonitorPill, NetworkMonitor, NotepadButton, NotificationCenterButton, PowerMenuButton, PrivacyIndicator, RamMonitor, RunningApps, SystemTrayBar, SystemUpdate, Vpn, Weather, WorkspaceSwitcher` | |
| Launcher | `DLauncherV2` (Spotlight-style; `spotlight open|close|toggle|openWith|toggleWith <all|apps|files|plugins>|openQuery|toggleQuery <q>`; `spotlight-bar` same verbs); sources: apps, files (`dsearch`), emojis, running windows, calculator, commands, plugins; `ClipboardLauncherPreview`, `AppEditView`, context menu, `Scorer.js`, `SourceBadge` | `Modals/DLauncherV2/` |
| App drawer | `AppDrawer` | |
| Control center | `ControlCenter` (`control-center open|close|toggle`) with tiles `Action, AudioDevice, Battery, Bluetooth, Brightness, ColorPicker, DarkMode, DiskUsage, Dnd, IdleInhibit, Network, NightMode, Plugin, RunningApps, User` and details `AudioInput, AudioOutput, AudioPort, BluetoothCodec, Bluetooth, Brightness, DiskUsage, DoNotDisturb, IdleInhibitor, Network, RunningApps, Vpn` | `Modules/ControlCenter/{Widgets,Details}/` |
| Dashboard | `DankDash`: tabs `Overview, MediaPlayer, Wallpaper, Weather` (+ `wellbeing, notifications`); IPC `dash open|close|toggle|openAt|toggleAt` | |
| Notifications | `Notifications/{Center,Popup}`, `DndPresets`, swipe rows, grouping, rich text, keyboard nav; IPC `notifications open|close|toggle|clearAll|dismiss|dismissAllPopups|toggleDoNotDisturb|getDoNotDisturb|enableDoNotDisturbIndefinitely|enableDoNotDisturbUntilTomorrowMorning|enableDoNotDisturbUntil`; `Toast.qml` + `toast info|infoWith|warn|warnWith|error|errorWith|hide|dismiss|status` (1.5 s / 3 s / 5 s / 8 s) | |
| OSD | `OSD` module; settings tab `OSDTab`; `niri showTouchpadOsd` | |
| Lock / session | `Lock` (PAM, `FadeToLock`, `FadeToDpms`, `VideoScreensaver`, lock widgets), `Greetd` + `dank-greeter`; IPC `lock lock|lockAndOutputsOff|demo|isLocked`, `sessions list|refresh|open|activate|switchTo`; idle `inhibit toggle|enable|enableFor <min>|disable|status|reason` | |
| Power menu | `PowerMenu`, `PowerMenuModal` (`powermenu open|close|toggle`), `PowerProfileModal` (`powerprofile open|close|toggle|list|status|set|cycle`) | |
| Wallpaper | `WallpaperBackground`, `BlurredWallpaperBackground`, `BlurredWallpaperLive`, `WallpaperCyclingService`; IPC `wallpaper get|set|clear|next|prev|getFor|setFor|nextFor|prevFor`; `profile getImage|setImage|clearImage`; theming by matugen + dank16 | |
| Dock | `Dock` (`dock reveal|hide|toggle|status|edit|autoHide|manualHide|toggleAutoHide|autoHideFor|revealFor|hideFor|editFor|statusFor|toggleFor`) | |
| Clipboard | `Modals/Clipboard/*` (history, image preview, editor, keyboard controller); `clipboard open|close|toggle`; Go `core/internal/{clipboard,clipolicy}` | |
| Color picker | `ColorPicker` module + modal (`color-picker open|openColor <c>|close|closeInstant|toggle|toggleInstant`), Go `core/internal/colorpicker` | |
| Screenshot | `niri screenshot|screenshotScreen|screenshotWindow` (niri-only); Go `core/internal/screenshot` | |
| Screen record | not a module; plugin registry type "Event Watcher" only | gap in DMS |
| System monitor | `ProcessList` + modal (`processlist open|close|toggle|focusOrToggle`), `DgopService` (dux-gop), `SystemMonitorWidget` desktop widget, bar monitors | |
| Updates | `SystemUpdate` module + modal (`systemupdater toggle|open|close|updatestatus`) | |
| Keybind cheatsheet | `KeybindsModal` (`keybinds open|openWithPath|close|toggle|toggleWithPath`; provider ∈ hyprland, sway, mangowc…) | reads the compositor config. **MEASURED v2: the `keybinds-ipc` page carries no Sway `bindsym` block**; DMS's Sway defaults are not published there. |
| Calendar | `CalendarService` with `CalendarDankBackend` (dux-calendar: local, Google, Microsoft, CalDAV, iCloud) and `CalendarKhalBackend` | |
| Weather | `WeatherService`, `Weather` bar widget, `WeatherTab` | |
| Notepad | `Notepad` + button (`notepad open|close|toggle`) | |
| Network / BT / VPN | `Network` module, `WifiPasswordModal`, `WifiQRCodeModal`, `NetworkInfoModal`, `BluetoothPairingModal`, `VPNService`, `TailscaleService`, `DMSNetworkService` | |
| Audio | `AudioService`, `PipewireAudioBackend`, `CavaService`, `AudioVisualization`; IPC `audio setvolume|increment|decrement|mute|setmic|micmute|cycleoutput|setmono|getmono|status`, `mic setvolume|increment|decrement|mute|status`, `mpris list|play|pause|playPause|previous|next|stop` | |
| Brightness | `brightness set|increment|decrement|status|list|enableExponential|disableExponential|toggleExponential` | |
| Night light | `NightModeService` (`night toggle|enable|disable|status|gamma|contrast|getCurrentTemp|getTargetTemp|getDayTemp|setTargetTemp|setDayTemp|getSchedule|automation|schedule|location`) | |
| Polkit | `PolkitAuthModal`, `PolkitService` | |
| Desktop widgets | `DesktopWidgetLayer`, editor, `BuiltinDesktopPlugins/{DesktopClockWidget, SystemMonitorWidget}`; IPC `desktopWidget list|status|enable|disable|toggleEnabled|toggleOverlay|setOverlay|toggleClickThrough|setClickThrough|toggleSyncPosition|setSyncPosition`; `widget toggle|openWith|toggleWith|openQuery|toggleQuery|list|status|visibility|reveal|hide|reset` | |
| Surface widgets | `SurfaceWidgets/` (ApplicationStrip, MediaActivity, MorphSurface, VectorSpringMotion) | the island/dot animation layer |
| Window rules / workspace rename | `window-rules open|close|toggle` (niri), `workspace-rename open` (niri, Hyprland) | |
| Outputs | `DisplayService`, `WlrOutputService`, `outputs listProfiles|current|setProfile|cycleProfile|cycle|status|refresh` | |
| Wellbeing | `wellbeing toggle|enable|disable|status|today|dailyLimit|appLimit` | screen time |
| Printers | `CupsService`, `PrinterTab` | |
| Default apps | `defaultApp browser|fileManager|textEditor|pdfReader|imageViewer|videoPlayer|musicPlayer|mail|calendar` | |
| Settings app | `Modules/Settings/*` (≈90 tabs incl. `KeybindsTab` editor, `NotificationRulesTab`, `DisplayConfigTab`, `GammaControlTab`, `ThemeScheduleTab`, `TypographyMotionTab`, `ShadowsTab`, `PluginsManageTab`, `RegistryBrowserWindow`); IPC `settings open|openWith <tab>|close|toggle|toggleWith|focusOrToggle|focusOrToggleWith|tabs|get|set`; `welcome open|doctor|page`; `file browse` | |
| Theming | matugen + dank16 from wallpaper; `theme toggle|light|dark|getMode`; `ThemeAutoService`, `ThemeScheduleTab`, `PaletteInjectService` (apps), `ICCService` | ruled out for gpuix-shell (wallpaper colours) |
| Plugin system | `plugin.json` with `type ∈ widget | launcher | daemon | desktop | dash | dashCard | composite`, `component(s)`, `trigger` (launcher prefix), `permissions` (e.g. `settings_write`); registry types Bar Widget, Desktop Widget, Launcher, Control Center, Event Watcher, Wallpaper; `~/.config/dms/plugins.lock.json` pins commits; IPC `plugins list|status|reload|enable|disable` | `plugins-overview` page |
| CLI / IPC | `dms run`, `dms ipc call <target> <method>`; 40 targets (full list §3D) | `keybinds-ipc` page (MEASURED v2) |
| Compositor layer | Go `core/` + QML `CompositorService` with `HyprlandService, NiriService, MangoService, LabwcService`; `hypr openOverview|closeOverview|toggleOverview`; Sway via `Quickshell.I3` (dig/02:80) | |

### 3A.3 Noctalia v5 (native C++, Wayland + GLES; Sway? **yes**, `src/compositors/sway/`)

| Surface | Noctalia names | Notes |
|---|---|---|
| Bars | `[bar.<name>]` per monitor; `position, auto_hide, smart_auto_hide, reserve_space, layer top|overlay, thickness 34, background_opacity, compositor_blur, border, radius 12 per corner, concave_edge_corners, margin_ends 100, padding 14, widget_spacing 6, capsule_*`; sections `start / center / end`; dead-zone gestures bound to IPC commands; IPC `bar-show|bar-hide|bar-toggle|bar-reserve-toggle [bar-name] [monitor-selector]`, `bar-auto-hide-set <on|off|smart>`, `bar-layer-set <top|overlay>` | `docs/user/bar/index.mdx`; ipc/surfaces (MEASURED v2) |
| Bar widgets (`src/shell/bar/widgets/`) | `active_window, audio_visualizer, battery, bluetooth, brightness, caffeine, clipboard, clock, control_center, custom_button, idle_inhibitor, keyboard_layout, launcher, lock_keys, media, network, nightlight, notification, plugin, power_profile, privacy, screenshot, session, settings, spacer, sysmon, taskbar, text, theme_mode, tray, volume, wallpaper, weather, workspaces` | |
| Launcher | layouts `full` (760 wide, views Recent/Pinned/All/Categories/Providers) and `simple` (560×500); providers `app, calculator (/calc, libqalculate), emoji (/emo), panels (/pan), wallpaper (/wall), session (/session), windows (/win), dmenu (stdin and persistent `[shell.launcher.dmenu.entry.<id>]`), plugin providers`; usage boosting; `noctalia dmenu -p`; IPC `panel-toggle launcher [query]` | `docs/user/launcher/index.mdx`; `src/launcher/` |
| Control center | tabs `home, media, audio, monitor, system, network (NM, wpa_supplicant, iwd; 802.1X; cellular), bluetooth (pairing agent, trust), weather, calendar, notifications, screen-time, power`; sidebar full/compact/none; width 700; IPC `panel-toggle control-center [tab]` | `docs/user/control-center/index.mdx` |
| Panels (generic) | `panel-open <id> [context]`, `panel-close [id]`, `panel-toggle session|clipboard|wallpaper|<author/plugin:entry> [context]` | ipc/surfaces |
| Notifications | own daemon, toasts with stable slots, history store, DND; IPC `notification-dnd-set on|off`, `notification-dnd-toggle`, `notification-dnd-status`, `notification-show <summary>`, `notification-invoke-latest`, `notification-clear-active`, `notification-clear-history` | `src/notification/`; ipc/media-and-ui (MEASURED v2) |
| OSD | `[osd]`; IPC `osd-enable|osd-disable|osd-toggle`, `osd-show <icon> [value]`, `volume-osd [n]`, `mic-volume-osd [n]`, `brightness-osd <n>` | ipc/system-controls (MEASURED v2) |
| System controls IPC | `volume-set|volume-up [n]|volume-down [n]|volume-mute`; `mic-volume-set|mic-volume-up|mic-volume-down|mic-mute`; `brightness-set [monitor|*] <n|n%>`, `brightness-up|brightness-down [monitor] [n]`; `nightlight-enable|disable|toggle|force-toggle`; `wifi-enable|disable|toggle|status`; `bluetooth-enable|disable|toggle|status`; `caffeine-enable|disable|toggle`; `power-set <profile>`, `power-cycle`; `dpms-on|dpms-off` | ipc/system-controls |
| Shell IPC | `status` (JSON), `log-level-status|log-level-set`, `config-reload`, `settings-open [context]|settings-open-plugin <id>|settings-close|settings-toggle`; `window-switcher [hold|current|close]` (scope all/output/workspace/current); `session lock|suspend|lock-and-suspend|logout|reboot|reboot-uefi|shutdown` | ipc/shell (MEASURED v2) |
| Media / clipboard / wallpaper / theme / screenshots IPC | `media previous|next|toggle|play|pause|stop|previous-player|next-player`; `clipboard-clear|clipboard-copy <text>|clipboard-text`; `wallpaper-random|next|previous|get|set [connector] [path]`; `theme-mode-get|toggle|set dark`, `color-scheme-get|set builtin <name>`, `templates-apply`; `screenshot-region|screenshot-fullscreen [pick|<output>|all]|screenshot-window|screenshot-annotate`, `annotate [file]` | ipc/media-and-ui |
| Lock | `src/shell/lockscreen/`, `ext-session-lock`, lockscreen widgets (`lockscreen-widgets-edit|exit|toggle-edit`) | |
| Session | `src/shell/session/` (logout, suspend, reboot, shutdown, lock, custom) | |
| Wallpaper | `src/shell/wallpaper/`, `[wallpaper]`, theme `source = wallpaper` | |
| Dock | `src/shell/dock/`; `dock-show|hide|toggle|reload` | |
| Clipboard | `src/shell/clipboard/`, `clipboard_enabled`, `clipboard_history_max_entries` | |
| Screenshot | `src/capture/` (screencopy, region overlay, annotation document/raster, toplevel thumbnails); screen recorder is an **official plugin** | |
| Window switcher | `src/shell/switcher/` (Alt-Tab, `hold`) | |
| Overview, desktop widgets | `src/shell/overview/`, `src/shell/desktop/` (`desktop-widgets-edit|exit|toggle-edit|show|hide|toggle`) | |
| Hot corners, screen corners, backdrop, tooltip, profile, greeter, setup wizard, settings | `src/shell/{hot_corners, screen_corners, backdrop, tooltip, profile, greeter, setup_wizard, settings}` | |
| Polkit | `src/shell/polkit/`, `polkit_agent` | |
| Services (`src/system/`) | battery warning, brightness, cpu freq/stat/temp, day-night schedule, disk mounts, easyeffects, gamma, hardware info, keyboard backlight, location, lock keys, rfkill, screen time, system monitor, telemetry, weather | |
| Idle | `src/idle/` (`ext_idle_notifier_v1`), `[idle.behavior.*]` | |
| Theming | `Palette` / `ColorRole` / `ColorSpec`; `[theme] mode dark|light|auto`, `source builtin|wallpaper|community`; templates for apps; `transparency_mode solid|soft|glass` | |
| Plugins | Luau, `plugin.toml` with `plugin_api`, entries `[[widget]] [[shortcut]] [[service]] [[desktop_widget]] [[launcher_provider]] [[panel]]`; sources official/community/git/path; `noctalia msg plugins …`; official plugins `screen_recorder, translator, timer, bongocat, wallhaven, wallpaper_depth, mpvpaper, world_clock` | `docs/user/plugins/*.mdx` |
| Architecture | four phases `PrepareFrame → Update → Layout → Render`; one `noctalia-panel` layer surface per panel; `CompositorPlatform` with `hyprland, niri, sway, mango, labwc, dwl, kde, umbriel, ext_workspace` backends; `[hooks]` (`started`, …) | `ARCHITECTURE.md` |

Legacy v4 (Quickshell) for completeness (MEASURED `legacy-v4` listings): Modules `Background, Bar, Cards, DesktopWidgets, Dock, LockScreen, MainScreen, Notification, OSD, Panels, Toast, Tooltip`; bar widgets `ActiveWindow, AudioVisualizer, Battery, Bluetooth, Brightness, Clock, ControlCenter, CustomButton, DarkMode, KeepAwake, KeyboardLayout, Launcher, LockKeys, MediaMini, Microphone, Network, NightLight, NoctaliaPerformance, NotificationHistory, PowerProfile, SessionMenu, Settings, Spacer, SystemMonitor, Taskbar, Tray, VPN, Volume, WallpaperSelector, Workspace`; panels `Audio, Battery, Bluetooth, Brightness, Changelog, Clock, ControlCenter, Dock, Launcher, Media, Network, NotificationHistory, Plugins, SessionMenu, Settings, SetupWizard, SystemStats, Tray, Wallpaper`.

### 3A.4 caelestia (Quickshell, Hyprland-only, GPL-3.0; Sway? no)

Modules (`modules/`): `areapicker, background, bar, dashboard, drawers, launcher, lock, nexus, notifications, osd, session, sidebar, utilities, windowinfo`. Bar components: `ActiveWindow, Clock, OsIcon, Power, StatusIcons (lock, audio, mic, kb layout, network, bluetooth, battery), Tray, workspaces`. Launcher: apps, wallpapers, `M3Variants`, `Schemes`; `>` actions `calculator, scheme, wallpaper, variant, random wallpaper, light/dark, shutdown/reboot/logout, lock, sleep, settings`; vim keybinds; favourites/hidden apps; "dangerous actions" switch. Dashboard: `Media, Performance (CPU/GPU/mem/storage/net/battery), WeatherTab`. Sidebar: notification groups and dock. Utilities: toasts, VPN, quick toggles (`wifi, bluetooth, mic, settings, gameMode, dnd, vpn`, MEASURED README v2), recording delete modal. Nexus (settings) pages: `About, Apps, Audio, Bluetooth, LanguageAndRegion, Network, Panels, Services, WallpaperAndStyle` (Display TODO, REPORTED `shells.md:19`). Services: `Audio, Brightness, Colours, Hypr, Nmcli, NotifData, Notifs, Players, Recorder, Screens, ShellState, Time, VPN, Wallpapers, Weather`. Lock: fprint + Howdy. README (MEASURED v2) `shell.json` sections: `appearance` (deformScale, rounding, spacing, padding, font {clock, workspaces, headline, title, body, label, mono, icon}, animation durations, transparency), `general` (logo, showOverFullscreen, apps {terminal, audio, playback, explorer}, idle timeouts, battery warnings), `background` (wallpaper, desktopClock, visualizer), `bar` (persistence, hover, scroll actions, popouts, workspaces, activeWindow, tray, clock, statusIcons, entries), `border`, `dashboard`, `launcher` (maxShown, prefix characters, dangerous actions, keybind style, favorites, hidden apps, fuzzy toggles, custom actions), `lock`, `nexus`, `notifs` (expiration, fullscreen behaviour, timeouts, thresholds), `osd` (toggle, hide delay), `services` (units, clock format, GPU type, increments, max volume, colour-scheme intelligence, default player, lyrics backend), `session` (keybind style, custom command icons/actions), `sidebar`, `utilities`, `paths`. Keybinds via Hyprland global shortcuts over D-Bus (`keybinds.lua`). IPC `caelestia shell <target> <method>` (`mpris getActive trackTitle`, `wallpaper`, `nexus open`), `caelestia shell -s` lists all. No user plugin system (dig/02:72). Companion `12errh/caelestia-settings` (REPORTED `apps_framework.md:14`).

### 3A.5 illogical-impulse / end-4 (Quickshell, Hyprland-only; Sway? no)

README "Notable features" (MEASURED v2): "Overview: Shows open apps with live previews / AI: Gemini, Ollama, and more / QoL: screen translation, anti-flashbang, Google Lens / Material themes: Choose your wallpaper, done, enjoy"; keybinds `Super+/` = keybind list, `Super+Enter` = terminal; Hyprland 0.55 "Luaification" transition. Modules (`modules/ii/`): `background, bar, cheatsheet, dock, lock, mediaControls, notificationPopup, onScreenDisplay, onScreenKeyboard, overlay, overview (live window previews + SearchWidget), polkit, regionSelector, screenCorners, screenTranslator, sessionScreen, sidebarLeft (AiChat, Anime/Booru, Translator), sidebarRight (bluetoothDevices, calendar, nightLight, notifications, pomodoro, quickToggles, todo, volumeMixer, wifiNetworks, QuickSliders), verticalBar, wallpaperSelector`; families `common, ii, settings, waffle`. Bar: `ActiveWindow, Battery(+Popup), Clock(+Popup), HyprlandXkbIndicator, Media, NotificationUnreadCount, Resources(+Popup), SysTray(+Menu), UtilButtons, Workspaces, weather`. Services: `Ai (Gemini / OpenAI-compatible / Mistral adapters; tools edit shell config, run commands), AppSearch, Audio, Battery, BluetoothStatus, Booru, Brightness, Cliphist, DateTime, EasyEffects, Emojis, FirstRunExperience, GoogleCloud, HyprlandAntiFlashbangShader, HyprlandConfig/Data/Keybinds/Xkb, Hyprsunset, Idle, KeyringStorage, LatexRenderer, LauncherApps/Search, MaterialThemeLoader, MprisController, Network, Notifications, PolkitService, Privacy, ResourceUsage, SessionWarnings, SongRec, SystemInfo, TaskbarApps, TimerService, Todo, Translation, TrayService, Updates, Wallpapers, Weather, Ydotool`. Separate `settings.qml` entrypoint sharing services (REPORTED `shells.md:17`). Nix "work-in-progress" (`shells.md:40`).

### 3A.6 Tacit (Quickshell; the aesthetic reference; Sway backend commented out)

From `tacit.md` and the overview note (REPORTED, with ISO paths): notch/island as the event coordinator (`services/IslandController.qml:183,450`: queued notifications, priority of transient events, unanswered agent permissions kept, waiting/working agent state, parked files on a shelf); overview + SearchWidget with files, calculator, command/web/Praxis sections (`modules/ii/overview/SearchWidget.qml:267`); region selector with screenshot, image search, OCR, capture-to-Claude, park on shelf (`modules/ii/regionSelector/RegionSelector.qml:46`); system dialogs lock, polkit, Bluetooth pairing, keyring, screen-share picker, "Open with" via a Unix-socket `DialogBridge` (`services/DialogBridge.qml:9`); voice `Tacit.Sand` visualiser fed by `flowd` (`modules/ii/island/SandLayer.qml:1`); boot lock (`bootlock.qml:11`); standalone apps Viewer (image/video/audio/PDF, IPC `open/present/state`), Settings, Apps store, Activity (cgroup attribution incl. agent scopes), Setup; **Pinax** files explorer instantiated by the main shell (`panelFamilies/IllogicalImpulseFamily.qml:87`, `bin/files-open:4`); design kit `modules/common/Tacit.qml:6` (semantic ink/accent/risk colours, six text sizes, radii, window transparency, contrast helper) and `widgets/Slab.qml:6` (default/risk/quiet actions); `MaterialThemeLoader.qml:10` per app. Old bar and vertical bar are default-off fallbacks (`IllogicalImpulseFamily.qml:81`). The deeper read is wave1/20.

### 3A.7 Other public references the notes cite

- **Flea** (`thisisgm/flea`): Quickshell file manager with Rust backend over newline JSON (`docs/protocol.md`); list/columns/grid/dual panes, tabs, Quick Look, copy/move/rename/trash/archive with undo, tags, search, devices; hard-depends on Omarchy (`apps_framework.md:9-13`). Closest architecture reference for `gpuix-shell files` (SCOPE S-155..S-160).
- **omarchy-ask / Ask Anywhere** (`Xn4m3d/omarchy-ask`): agent composer overlay with screenshot/clipboard/file attachments, streamed answers, history, terminal handoff; `hyprctl` context (`apps_framework.md:33-34`). Pattern for `gpuix-shell ask` (SCOPE S-200).
- **DankCalendar / dux-calendar**: standalone Quickshell + Go calendar (`shells.md:20`). Out of the shell (boundary).
- **quickshell-music-player**, **sluets/quickshell-hyprland** music window over MPD (`apps_framework.md:16-17`): the two music patterns; the Navidrome demo (SCOPE S-085, `docs/gpuix-shell/MUSIC.md`) follows the second (a daemon owns playback, the launcher is a client).
- **gpui-shell** (`/home/tom/Downloads/gpui-shell/README.md`, MEASURED): layer-shell bar, launcher with prefix routing, control center (libpulse, brightness, libnm, bluez, UPower, notification center with DND, MPRIS), OSD, compositor abstraction, single-instance socket, privacy mode. Rust; the D-Bus list is the checklist (wave1/23 §3.4 has the exact interface names).

---

## 3B. UNION table: feature | which shells have it | Tom's stance | gpuix-shell plan

Plan words: **must** = in the overnight scaffold or the first PR (SCOPE P0); **should** = next after the core stands (P1); **later** = foundation only (registry id, socket verb, doc; P2); **out** = ruled out or not the shell's job. "Stance" cites §2 (`AM #n` = March-2026 mark, quoted in §2 or wave1/30 §3.1); "—" means no ruling found and the plan is my default (INFERRED). `S-###` = SCOPE.md row.

Shell codes: OM Omarchy, DMS Dux, NOC Noctalia v5, CAE caelestia, II illogical-impulse, TAC Tacit, GS gpui-shell, VIC Vicinae (today's launcher, REPORTED `docs/vicinae-research.md`).

### Chrome: bars, rails, docks

| Feature | Shells | Tom's stance | gpuix-shell plan |
|---|---|---|---|
| Top status bar | OM (stock `position top`), DMS, NOC, CAE, II, GS | "no top bar on the Linux head" (BRIEF:48); `sway/config:2` "No bar"; "bar-less setup for almost a year" (10-07); AM #27 "all the other modules exist in the top bar" → reversed by the left-bar order | **out** as a drawn surface; kit keeps `a.top-bar` undrawn (SHELLS-DIGEST:31) |
| Left rail with workspace switcher | legacy NOC vertical bar, II `verticalBar`, OM `bar.position=left` (28 px), TAC vertical bar (off) | "a left bar with workspace switcher that remplaces waybar" (10-20); "copy the same proportions as the views c++ left tab bar" (10-13) → 220/30/12/2/8; AM #8 vertical bar "MUST, in fact i have a very specific use case in mind"; collapsed 56 (SHELLS-DIGEST:248); exclusive zone proven 23:45 (BRIEF:176-183) | **must**: `gpuix-shell rail` (S-001 process; S-020..S-041 rows), layer top, anchor left/top/bottom, zone 56/220, slots 1..9 with ◉ ◐ ● ✓ ○ (S-022) |
| Workspace widget (compositor workspaces, click to focus) | all | AM #27 "MUST"; herdr workspace = Sway slot; "no Herdr focus verb, ever" (wave1/05:147); click = `workspace number N` then wait for the Sway echo | **must** (S-005 herdr reader, Sway IPC) |
| One IPC toggle per bar, multiple bars | OM `toggleBarTransparency`/`omarchy-toggle-bar`, DMS `bar toggle`, NOC `bar-toggle [bar-name] [monitor-selector]` | AM #20 "one ipc toggle should control only one bar"; AM #12 "multiple simultaneous bars … toggle one but not the other" | **must**: `gpuix-shell rail toggle --output eDP-1` (S-041 per-output config) |
| Auto-hide / fullscreen hide | OM, DMS `autoHide`, NOC `bar-auto-hide-set on|off|smart` | AM #9 "MUST … more important for me is that i want to toggle bars with a keybind"; AM #10 fullscreen hide "MUST" | **should**: hide when the focused container is fullscreen (Sway `window` events); hover reveal optional |
| Active-window title widget | OM, DMS, NOC, CAE, II, GS | AM #36 "MUST" → herdr title preferred (wave1/30 §3.1 #36) | **later** (rail header shows the herdr workspace name; app_id fallback) |
| Taskbar / running apps strip | NOC `taskbar`, DMS `RunningApps`, II `TaskbarApps`, OM dock | AM #62 apps dock in bar "COULD, wouldn't use it directly"; "the bottom macos tab bar: utilities like email etc can go below" (10-14) | **later** as the X1 "app bar" option; registry entries for Mail/CRM/Projects/Files/Chat exist from day one so the launcher can open them (S-060 PWA entries) |
| Dock (pinned apps, autohide) | OM (floating workspaces only; stock pinned list), DMS, NOC, II | AM #13 "COULD" | **later** (same row as app bar) |
| Clock + calendar popover | all (OM clock month grid + ISO weeks + `elsewhen`) | AM #28 "MUST, but no need to do anything fancier than configurable time and date"; AM #240 month grid "WONT" | **must** rail clock (S-025); **should** popover date/week/timezones, no grid (S-170) |
| Battery indicator + popup (profiles, stats) | OM `power`, DMS, NOC, CAE, II, GS | AM #30 "MUST"; #54 power profile "COULD, very secondary" | **must** UPower glyph (S-029 INFERRED id); **should** detail + PPD selector (S-131) |
| Network indicator + Wi-Fi menu (scan, connect, password, forget, hidden, detail, QR) | OM `network` (+DNS, `wifiqr`), DMS (+`WifiPasswordModal`, `WifiQRCodeModal`), NOC network tab (NM/iwd/802.1X/cellular), CAE, II `wifiNetworks`, GS | "for wifi menu, or bluetooth pairing menu; etc." (10-20); AM #133-#147 all "MUST"; June D20 "critical to v1"; `fzf-nmcli` today | **must**: rail glyph (S-027) + `controls open wifi` (S-126) + launcher view (S-072); NM SecretAgent and QR **later** |
| Bluetooth indicator + pairing agent | OM, DMS (+codec), NOC (agent, trust), CAE, II, TAC pairing dialog, GS | AM #32 "MUST"; #148-#151 "MUST" ×4; #152 agent "SHOULD" | **should**: glyph (S-028) + `controls open bluetooth` (S-127) with BlueZ Agent1 sheet; codec/pinning/RSSI **later** |
| Tailscale / VPN indicator + peers | OM `tailscale` widget + panel, DMS `Vpn` + `TailscaleService`, NOC (VPN in network), CAE VPN | AM #41 "MUST. it is CRUCIAL for me to know if i'm connected to tailscale … what other devices are connected"; #144 "MUST with special focus on tailscale"; Nov-2025 wish "tailscale status in bottom right" | **should**: glyph from `tailscale status --json` (S-031) + peers menu (S-129) |
| Audio widget: master slider, output picker, per-app mixer, mic | OM `audio` + `microphone`, DMS, NOC audio tab, CAE, II `volumeMixer`, GS | AM #106 device picker "MUST"; #105 per-app "COULD"; #109 ">100 % DONT"; "keypress>sway>script execution" (10-12); `volume`, `audio-route` on F6-F9 | **must** `controls open audio` = `audio-route` behaviour (S-128); per-app streams **later**; keys keep the scripts; clamp 0-100 |
| Brightness widget | OM `monitor`, DMS, NOC, CAE, II, GS | AM #123 "MUST but … doesn't really have to be fully integrated"; `brightness` script | OSD **must**; a controls row **should** |
| Tray (StatusNotifier host) | OM `tray`, DMS `SystemTrayBar`, NOC `tray`, CAE, II `SysTray`, GS (libtray) | AM #29 "SHOULD, very nice to have but i won't be using it personally"; Vicinae `tray.enabled = false` (`vicinae.nix:40`) | **later** (S-168 P2; `core:search-tray` S-079 empty state until then) |
| Keyboard layout indicator | OM, DMS, NOC, CAE, II, GS | AM #42 "COULD, nice to have but i won't be using it" | **out** |
| System monitor widgets (CPU/RAM/GPU/temp/disk/net) | DMS (many), NOC `sysmon`, CAE performance, II resources, GS, TAC Activity | AM #40 "SHOULD, good to have but i don't intend to use it myself"; #245 "COULD. very secondary"; "performance is not really the thing" | **later** (S-176 P2) |
| Privacy indicator (mic/camera/screen share) + recording dot | DMS `PrivacyIndicator`, NOC `privacy`, OM `ScreenRecording`, GS privacy mode | AM #39 "MUST, and i'll likely develop a specific widget around it"; #60 "MUST, i will use that" | **should**: recording dot from the scripts' state file (S-033); PipeWire privacy dots (S-024 order) |
| Idle inhibitor / caffeine / stay awake | OM `StayAwake`, DMS `IdleInhibitTile`, NOC `caffeine`, CAE, II | AM #45/#232 "COULD"; idle suite "icebox"; `monitors-off` script | **should** as a controls toggle (cheap) |
| Night light | OM service + indicator, DMS `NightModeTile`, NOC `nightlight`, CAE, II Hyprsunset | AM #243 "WONT, my gamma control and night light is set once and not from the shell. skip entirely"; #53 "COULD … wl-gammarelay-rs" | **out** (SCOPE lists `night-light` as a controls domain; this note's reading of #243 says drop it; recorded in §6) |
| Weather | OM, DMS, NOC, CAE, II | AM #43 "COULD, nice to have but i won't be using it"; #244 "COULD. very secondary" | **out** |
| Reminders / timers / pomodoro | OM reminders + indicator, II pomodoro + timer, NOC timer plugin | AM #250 "SHOULD … this will be the first feature i release AFTER base webshell"; `pomodoro` script, Shift+F10 | **should**: rail item + launcher provider wrapping the script (S-024 "pomodoro") |
| Updates indicator | OM `system-update`, DMS `SystemUpdate`, II `Updates` | AM #47 "SHOULD … fedora atomic" → NixOS now; #248 "COULD far later" | **later** (S-178 P2: generation + fwupd, no polling) |
| Agents / AI subscription limits panel | OM `agents` (only one) | `claude-capacity`, `seats` scripts; herdr is the status producer; U-16 no quota in the workspace rows | **should**: rail footer row from `claude-capacity`; never Omarchy's record format |
| Notification count / unread badge | DMS, II `NotificationUnreadCount`, NOC `notification` widget | AM #35 "MUST" | **must** in the rail status cluster (S-024 "notifications bell") |
| Custom IPC button (click/right/middle/scroll) | OM `type: command`, NOC `custom_button`, DMS plugin widget | AM #58 "SHOULD" | **should**: registry item kind `command` |
| Hot corners | NOC hot corners, II screenCorners | AM #26 "SHOULD, niri itself also has hot corner but this one clearly has more potential" | **later** (rail-edge hover → launcher) |
| Desktop widgets (clock, monitor on the background) | DMS, NOC, CAE desktop clock | AM #246 "WONT. i do not like widgets" | **out** |

### Launcher and commands

| Feature | Shells | Tom's stance | gpuix-shell plan |
|---|---|---|---|
| Launcher window (Mod+d) with fuzzy apps | all; VIC | "a mod+d menu (vicinae remplacement)"; "feature parity at least with vicinae"; AM L238 "visual equivalent to macos' RAYCAST"; AM #83 "MUST" | **must**: `gpuix-shell launcher` (S-050..S-061), overlay 700×580, top margin 108, exclusive keyboard; apps provider S-060 |
| Command registry with stable ids, keybind → IPC → same command | OM menu routes, DMS `spotlight openQuery`, NOC `panel-toggle launcher [query]`, VIC `vicinae cmd launch <id>` | U-10 "One registry, drivable at equivalence" (SHELLS-DIGEST:47); AM #88 "MUST, dms provider concept is powerful" | **must**: `src/registry.ts`, `gpuix-shell cmd ls|launch` (S-061), every Sway bind calls the socket |
| Prefix / mode routing (`/calc`, `>`, `openWith apps|files|plugins`) | NOC prefixes, CAE `>`, DMS modes, GS prefixes | AM #100 "SHOULD, explore in second iteration" | **should** (S-053: `=` `>` `:` `/` `@` `♪` `?`) |
| Calculator (units, currency, bases) | DMS, NOC (libqalculate), CAE, II, TAC, VIC | AM #84 "COULD, nice to have"; built once 10-14 | **must** basic (cheap); units/currency **later** |
| Favourites, frecency, hidden apps | CAE sqlite frequency, DMS, NOC usage boosting, VIC | AM #90 "MUST, and caelestia's sqlite frequency is very cool"; #91 "SHOULD"; #102 blacklist "SHOULD because easy" | **must** (S-052 `bun:sqlite` frecency) |
| Action panel per item | VIC/Raycast, DMS context menu | AM #96 "SHOULD, this is a nice addition that makes our launcher raycast-like" | **must** (S-054 Ctrl+B) |
| Running windows / workspaces provider | DMS, NOC `/win`, GS, VIC, OM dock | Mod+i switcher is the workspace surface; AM #165 thumbnails "COULD … Not trivial" | **should**: `windows` provider from `get_tree`; switcher stays text + herdr status (S-090) |
| Chrome tabs provider | VIC only (extension + native host) | "including how it interacts w google chrome tabs is very desirable" (10-14) | **should** (S-067); biggest parity risk (wave1/05:258) |
| Files provider (search) | DMS (dsearch), TAC overview, VIC indexer | AM #85 "MUST, and fd plugin seems sufficiend, dms' dsearch was overkill" | **must** via `fd`, no indexer (S-065) |
| Clipboard history (text + image previews, pin, edit) | OM, DMS, NOC, II `Cliphist`, VIC | AM #233 "MUST the clipboard manager is very important to me"; #86 "MUST … same aesthetic as the launcher … displaying images (i use cliphist …)"; Mod+v today; BRIEF:113 own store | **must**: own store on `wl-paste --watch` (S-145), launcher view (S-064), Mod+v; tension with cliphist recorded |
| Emoji picker | OM, DMS, NOC `/emo`, II | AM #87 "SHOULD, emoji is somehting i have had for years"; Nov-2025 wish | **should** (`:` prefix) |
| Snippets / quick notepad | DMS `Notepad`, VIC snippets | AM #249 "WONT. i use github-backed md notes"; #63 "COULD" | **out** (notepad); `snippets:*` ids kept only for Vicinae parity (S-061) |
| Session / power actions in launcher | OM `system`, NOC `/session`, CAE `>`, DMS `powermenu`, II `sessionScreen` | AM #218 "MUST … scroll/select through a list AND press and hold a given key" | **must** (S-070 launcher rows → S-140 hold-to-confirm) |
| Theme / accent switcher | GS, CAE `>scheme`, DMS `theme toggle`, OM `appearance.theme`, NOC `theme-mode-set` | F2 / Shift+F2 `theme-prompt`; AM #184 "only be toggled manually" | **must**: launcher actions calling `theme`; shell reloads on the symlink (S-180 INFERRED id) |
| Wallpaper picker | OM image-picker, DMS, NOC `/wall`, CAE, II | wallpaper `#000000 solid`; AM #57 "COULD … cosmetic trivialities"; #191-#196 superseded | **out** (S-185 asserts `canAccess(Wallpaper) === false`) |
| dmenu / select / input mode for scripts | OM `omarchy-menu-select` (`--multiple`, `--on-change`), NOC `noctalia dmenu` + persistent entries, DMS `dmenuipc` | fzf-in-floating-kitty prompts today (`theme-prompt`, `audio-route`, `call-record-menu`, `sleep-monitors`, `pomodoro menu`, `fzf-nmcli`) | **must**: `gpuix-shell select` reading stdin (every fzf prompt moves without rewriting scripts) |
| Keybind cheatsheet | OM `learn.keybindings`, DMS `keybinds open sway`, II `Super+/`, NOC settings | Nov-2025 wish "hotkeys visualizations" | **should** (S-165 parses `binds.conf`; S-166 collision lint) |
| Plugin / extension providers | DMS `type: launcher` + `trigger`, NOC `[[launcher_provider]]`, VIC React extensions + script commands | "refuse in-process third-party code" (dig/02:75); AM #200 "no need to 'enable' plugins or browse through them" | **should**: script commands (S-071) + Vicinae-compatible extension host in Bun Workers (S-096); no plugin browser |
| Music search and control (Navidrome) | none (MPRIS widgets only) | 10-20 order "raycast+spotify level" | **should** (S-085; `docs/gpuix-shell/MUSIC.md`; separate workflow) |
| "Ask" / agent composer | OM ask plugin, II AiChat, TAC Praxis | AM #247 "COULD but much later … i have some ideas"; OpenUI bounded (BRIEF:118-120) | **later** (S-200/S-201 P2) |
| Web search, translator, Booru, screen translator, Circle to Search | II, NOC translator plugin, TAC | AM #98 web search "COULD … little added value"; #254 Lens "WONT" | **out** |
| Shell command execution with live output | DMS commands, NOC, VIC script `fullOutput` | AM #99 "SHOULD, makes us raycast-like" | **should** (`>` prefix, S-053) |
| Categories / grid view / preview panel | NOC categories, DMS grid | AM #89 "SHOULD, noctalia 12 categories is good enough"; #94 list only; #95 "COULD, extremely secondary" | **later** (list only tonight) |

### Notifications and feedback

| Feature | Shells | Tom's stance | gpuix-shell plan |
|---|---|---|---|
| `org.freedesktop.Notifications` daemon (replaces mako) | OM, DMS, NOC, CAE, II, GS | "notify-send remplacement to mako" (10-20); AM #65 "MUST this one is non-negociable" | **must**: `gpuix-shell notifications` (S-100 INFERRED id; S-012 never both with mako) |
| Toasts (position, max N, actions, replace id, urgency timeouts) | all; OM 5 s / 8 s / sticky | AM #66 position "MUST"; #74 per-urgency "MUST"; #69 actions "COULD" but herdr-attention needs them; 390 wide max 4 (BRIEF:107-108) | **must** |
| Notification centre / history (JSON persistence) | OM panel + `history.json`, DMS center, NOC tab, CAE sidebar, II | AM #67 "MUST, although the specific aesthetic of it is not clear"; #70 "MUST, useful"; #80 restore "COULD"; PR #571 Mod+o | **should** (store + Mod+o dismiss + launcher `notifications:history`, S-078); centre window after |
| Keyboard navigation / hint letters | DMS hints overlay | AM #77 "MUST, dms hints overlay philosophy is very desirable" | **must** (hint letters on toasts) |
| Grouping per app / site | OM (per site), DMS | AM #68 "MUST, seems trivial" | **should** |
| Flood protection / rate limit | DMS | AM #82 "MUST, to avoid dangerous or strange behavior" | **must** (20/s cap + 1 s duplicate coalescing, wave1/30 #82) |
| DND (+ presets, until-tomorrow, per-source snooze, scheduled) | OM snooze/codes bypass, DMS presets + `enableDoNotDisturbUntil…`, NOC `notification-dnd-*`, CAE | AM #71 "SHOULD … keybind or a button"; gap rows: scheduled DND "WONT", snooze "WONT" | **should** toggle only (S-133); no snooze, no schedule |
| Rules engine (per-app) | DMS `NotificationRulesTab` | AM #72 "MUST, nice to have from DMS" | **later** (config-driven rules, v2) |
| Click routing to the sender window | OM (7-step order) | act through Sway | **should** (focus by pid/app_id via `get_tree`) |
| Sounds, inline reply, swipe, privacy mode, image cache | DMS, OM | #75 "SHOULD"; gap "per-app sounds WONT; i barely expect nofitication sounds"; inline reply "WONT"; #73 swipe "COULD"; #79 privacy "SHOULD"; #81 "SHOULD" | **out** (reply, swipe, sounds); **later** (privacy mode, image cache) |
| OSD for volume / brightness / mic / caps / kb backlight / audio-route | OM, DMS, NOC (`osd-show <icon> [value]`), CAE, II, GS | AM #122 "MUST. an OSD is very imprtant"; #126 output-switch OSD "SHOULD"; #127 position "SHOULD, like the dms 8 positions"; #129 suppress while panel open "SHOULD"; #130 slider "COULD"; `bin/osd` today | **must**: `gpuix-shell osd <kind> <value>` overlay bottom margin 96 (SCOPE §4); scripts call it instead of `notify-send -r`; position from config; suppressed while launcher/controls open |
| Toast API for scripts (`toast info|warn|error`, `notification-show`) | DMS, NOC, OM `omarchy-notification-send` | — | **should**: same socket verb; `notify-send` keeps working |
| Agent-event island (queued permissions, shelf) | TAC notch, DMS island | herdr state drives the rail dot; "never steals focus"; "only 'blocked' … may also notify" | **must** the attention path only (S-109/S-190: blocked → one notification with "Go"); **later** the queue model; no notch |
| Phone notifications (KDE Connect / Valent) | DMS plugin, NOC android plugin | AM #252 "SHOULD … 'android phone notification' is extremely desirable" | **later** (S-110: accepted as fd.o clients) |

### Session, security, system

| Feature | Shells | Tom's stance | gpuix-shell plan |
|---|---|---|---|
| Lock screen (PAM, fingerprint, face, lock widgets) | OM, DMS, NOC (`ext-session-lock`), CAE, II, TAC | AM #203 "COULD … icebox"; no lock bind in `binds.conf`; GPUIX has no `ext-session-lock` | **out** tonight; seam `gpuix-shell lock` exits 69 (S-188 P2) |
| Idle management (screensaver, dpms, lock-before-sleep) | OM idle service, DMS, NOC idle, CAE | AM L508 "icebox"; swayidle one-shot via `monitors-off` | **out** (swayidle); `inhibit` only; logind delay-lock seam S-141 |
| Polkit agent | OM, DMS, NOC, II, TAC | AM #216 "MUST … this is low-hanging fruit"; #256 "MUST this one is important" | **later** (S-189 P2: no PAM path in GPUIX tonight; modal core shared with wifi/BT secrets). Tom's MUST vs tonight's P2 is recorded as a gap. |
| Keyring / secret prompts | TAC | — | **out** |
| Power menu (hold-to-confirm, hibernate detection) | DMS `PowerMenu`, OM `system`, NOC `session …`, CAE, II | AM #218 "MUST … press and hold"; #219/#220 "SHOULD, low hanging fruit"; #222 confirm dialog "COULD" → the hold is the confirm | **must** `gpuix-shell power` (S-140) |
| Screenshot (region/window/screen, annotate) | OM capture, DMS (niri), NOC `screenshot-*` + `annotate`, CAE areapicker, II regionSelector, TAC | AM #234 "WONT because existing … is sufficient"; #236 annotation "WONT"; `screenshot` + Satty on Mod+s | **keep** scripts; **must** result toast with preview (S-148); annotation **out** |
| Screen recording (+webcam, audio) | OM, NOC plugin, CAE recorder, II | AM #235 "COULD … OBS Studio"; `record`, `recording-toggle` | **keep** scripts; dot **should** (S-033, S-149) |
| OCR / capture-to-agent | OM `capture.text`, TAC capture-to-Claude, II Lens | AM #238 "SHOULD but with a twist … qwen 3.5"; `screen-ocr-area` → Halogen | **keep**; toast with "Send to agent" **should** (S-151, S-194) |
| Color picker | OM `capture.color`, DMS modal, II | AM #237 "MUST but … the screenshot tool exists and is sufficient"; `colorpicker` on Mod+c | **keep**; launcher row **must** (cheap) |
| QR of Wi-Fi / text, share via Tailscale | OM `wifiqr`, `share.*`, DMS QR modal | — | **later** |
| Display / output profiles, mirror, clamshell | OM hardware menu, DMS `outputs`, NOC | AM #172 "COULD, for now i use `kanshi`" | **out** (kanshi) |
| Input toggles (touchpad, touchscreen, haptics) | OM hardware menu, DMS | `touchpad-toggle` on Menu key; Caps → touchpad OSD (commit 7e082fbb) | **keep**; launcher row **should** |
| Dictation / voice | OM dictation, TAC `flowd` + Sand | `voxtype`, `speak-clipboard`, hold-to-dictate scope | **later**: action + OSD state only (SCOPE §21 lists "wake word / dictation" out tonight) |
| User switching, greeter, session select | DMS, NOC greeter | AM #213-#215 "COULD, icebox"; #267 no SDDM | **out** |
| Power profiles | OM, DMS, NOC `power-set|power-cycle`, CAE | AM #54 "COULD, very secondary" | **should** inside battery detail (S-131) |
| Airplane mode | NOC rfkill, DMS | AM #146 "MUST" | **should** (S-136) |
| Wellbeing / screen time | DMS, NOC | — | **out** |
| Printers | DMS | AM #262 "COULD … icebox"; paper-daemon prints | **out** |
| Settings app / wizard / doctor | OM setup menu, DMS (~90 tabs, `welcome doctor`), NOC settings + wizard, CAE Nexus, II settings, TAC Settings | AM #174 "MUST" vs #200 "no need to 'enable' plugins or browse"; "i never asked for a toml config" (06-30); config is Nix | **out**; read-only `core:settings` list **later** (S-082); zod validation **must** (S-009, AM #178) |
| Containers / systemd units view | DMS plugin (dockerfiles) | AM #251 "SHOULD Container management is very desirable"; #263 "extend to see running systemd services and quadlets" | **later** (not in SCOPE; recorded §6) |

### Theming, plugins, IPC, files

| Feature | Shells | Tom's stance | gpuix-shell plan |
|---|---|---|---|
| Palette file + per-surface token file, pushed live | OM `colors.toml` + `shell.toml` (machine override wins) + `applyTheme`; NOC Palette/ColorRole + `templates-apply`; DMS matugen; CAE schemes + `shell-tokens.json` | noir/claude-dark/claude-light from `home/themes/*.nix`; "close to the current minimal 'noir' colorscheme …"; dig/02:67 "keep Omarchy's split"; AM #186 cross-app theming "WONT … that is what dotfiles are for" | **must**: `gpuix-shell.json` fragment beside `mako`/`vicinae` in `home/themes/default.nix`; watch `~/.config/theme`; per-surface sections (Omarchy names) **should** |
| Wallpaper-derived colours (matugen/Material) | DMS, NOC `source=wallpaper`, CAE, II, TAC | AM #181 "WONT whatsoever: no material … no matugen whatsoever" | **out** |
| Blur / glass / transparency modes | NOC `transparency_mode glass`, OM bar `glassy`, DMS blur, CAE | "flat and opaque, hairlines not shadows, no blur, no frost" (BRIEF:43-44); AM #189 superseded | **out** |
| OLED black | — (shells have dark modes) | AM #185 "MUST. OLED mode ie make the black colors #000000" | **must** (noir) |
| Interactive-state alphas (normal/hover/focus/selected) | OM `[controls]` 0.04/0.08/0.18/0.22 (dig/01:32) | U-03, "one neutral fill at two strengths" (dig/02:144) | **must** as tokens |
| Font scale root + multipliers | OM `[font] base-size`, NOC `scale`, CAE font roles | Anthropic Sans 12 UI (BRIEF:116); 13 chrome in the kit; AM #187 superseded | **must**: one `uiScale`; `registerFont(bytes)` in gpuix 0.11 |
| Animation duration / off switch | OM durations → 0, CAE durations, NOC `shell.animation`, DMS springs | AM #188 "WONT … none/short"; kmux B12 one 50 ms token; curve (0.2,0,0,1) | **must**: one duration token, `motionScale` may be 0 |
| Plugin system (manifest, kinds, enable/disable, registry, lockfile) | OM (6 kinds, git, diff on update), DMS (7 types, lockfile, registry), NOC (Luau, 6 entry kinds, sources) | AM #4 "MUST, it is important to be able to 'turn any functionality' into a bar addition"; #200 "no hierarchy"; "refuse in-process third-party code" | **must** the registry row shape `(id, kind, entry, settings schema, summon, hide)` in `src/registry.ts`; **out** marketplace/enable UI; extensions out-of-process only (S-096) |
| IPC / CLI to the running shell | OM `omarchy-shell <target> <method>`, DMS `dms ipc call`, NOC `noctalia msg`, CAE `caelestia shell`, `qs ipc call/wait/listen` | AM #20 IPC toggle "MUST"; AM #199 IPC config changes "SHOULD"; BRIEF:100-103 one CLI over `shell.sock` | **must**: verbs in §3D; `ui-tree` test seam (S-010); event `listen` **should** |
| Hot reload of code / config | Quickshell QML reload; OM `rescanPlugins`/`reloadConfig`; NOC `config-reload` | theme live; code via Nix (dig/02:159) | theme/config reload **must**; code reload **out** |
| Multi-output surfaces (one per output) | OM notifications per output, NOC bars per monitor, DMS `*On`/`*For` verbs | AM #5 "MUST", #6 per-screen "MUST"; GPUIX 0.11 has no output selector (dig/02:92) | **gap**; one process per surface, follows compositor-chosen output; eDP-2 reduced rail (S-041) |
| Input regions / click-through | OM input-masked decks, DMS `setClickThrough` | AM #11 "COULD"; GPUIX has none (dig/02:93) | **gap**; size each surface to its content |
| Files explorer | TAC Pinax, Flea, DMS `file browse` picker, OM image picker | "mainly the file explorer" (10-20); Tom on Tacit 09-25 "file explorer … stunning" | **should** `gpuix-shell files` ordinary window (S-155..S-160; wave1/20 has the Pinax grammar); nautilus stays |
| Image / media viewer | TAC Viewer | — | **later** |
| App store, installer, setup wizard | TAC Apps/Setup, DMS welcome, NOC wizard, OM install | AM #265 "MUST but … specific scoping" → Nix | **out** |
| Calendar (accounts, sync, events) | DMS dux-calendar, NOC calendar tab, II calendar, OM clock grid | AM #239 "SHOULD keep this idea for later"; #240 grid "WONT"; boundary (BRIEF:121-124); Notion Calendar PWA | **out** of the shell |
| Mail / CRM / projects / chat | none (TAC Praxis is chat) | boundary: launched, not built | **out**; launcher rows that open the Chrome apps **must** (S-060) |
| Dev gallery / conformance harness | OM `dev-gallery` | U-19 "A gallery per renderer"; "storybook" wish (06-30) | **should**: `gpuix-shell gallery` window rendering every component in three themes |
| Default-apps registry | DMS `defaultApp <kind>`, OM `setup.default.*` | — | **later** (config keys; `xdg-mime` stays) |

---

## 3C. Feature/behaviour inventory in the orchestrator's row shape (feature | what exactly | where it lives today | keep/replace/new | notes)

The Sway-seat view of the union: what Tom runs now, and what tonight's plan does to it.

| Feature | What exactly | Where it lives today | keep / replace / new | Notes |
|---|---|---|---|---|
| Launcher | Vicinae on Mod+d / Mod+space; providers apps, scripts, browser tabs, calculator, files, clipboard, snippets, media | `home/vicinae.nix`, `binds.conf:6-7`, `docs/vicinae-research.md:3,26-48` | **replace** (`gpuix-shell launcher`, SCOPE §2) | parity list in 3B; Chrome tabs is the open risk |
| Clipboard history | Vicinae `clipboard:history` on Mod+v; `ignorePasswords`, `preserveTagged` | `binds.conf:114`, `vicinae.nix:70-86`, `startup.conf:4` | **replace** (own store, S-145) | cliphist installed, no watcher; AM #86 tension |
| herdr picker | `herdr-picker` on Mod+Ctrl+space (fzf) | `binds.conf:8`, `dot_local/bin/herdr-picker` | **replace** by rail + switcher; script stays as fallback | |
| Mod+i switcher | PR #565 fuzzel top-display switcher with herdr status | `/home/tom/.wt/dotfiles/morning-shell` (BRIEF:79) | **replace** (`gpuix-shell switcher`, SCOPE §5) | semantics in wave1/02:181 |
| Workspace ops | `sway-workspace new/rename/restore/close` on Mod+t / Shift+n / Shift+t / Mod+w; `herdr-chord new/sidebar` | `binds.conf:9-15` | **keep**; the rail calls them | |
| Notifications | mako (`services.mako`, theme fragment `mako = t:`), Mod+o dismiss PR #571 | `vicinae.nix:112-124`, `themes/default.nix:127` | **replace** (daemon + toasts, SCOPE §3) | |
| OSD | `bin/osd` one replaceable mako popup with progress hint | `dot_local/bin/osd` | **replace** (`gpuix-shell osd`, SCOPE §4) | keep the script's CLI shape so `volume`/`brightness` do not change |
| Volume / brightness / media keys | scripts on F-keys and XF86 keys | `binds.conf:139-157`, `dot_local/bin/{volume,brightness,media}` | **keep** (scripts call the OSD) | 10-12 ruling; AM #123 |
| Theme switch | `theme`, `theme-prompt` on F2 / Shift+F2; symlink `~/.config/theme` | `dot_local/bin/theme`, `home/theme.nix`, `docs/theme-switcher-2026-09-17.md` | **keep**; **new** `gpuix-shell.json` fragment; launcher actions | |
| Screenshots / OCR / colour | `screenshot screen|area|window` (+Satty), `screen-ocr-area`, `colorpicker` | `binds.conf:33-46` | **keep**; launcher rows + result toasts **new** (S-148, S-151) | AM #234/#237/#238 |
| Audio route, call record, sleep monitors, pomodoro prompts | fzf prompts in floating kitty (`--class *-prompt`) | `binds.conf:148-151` | **keep** scripts; **new** `gpuix-shell select` | |
| Wi-Fi | `fzf-nmcli` (255-line Python NM menu) | `dot_local/bin/fzf-nmcli` | **replace** by `controls open wifi` (S-126; script stays) | AM #133-#147 |
| Bluetooth | none (bluetoothctl by hand) | — | **new** (S-127 + agent) | AM #148-#152 |
| Tailscale status | `vpn-status` "Outputs JSON for bar widget" | `dot_local/bin/vpn-status` (REPORTED wave1/30 #41) | **new** rail glyph (S-031) | AM #41 |
| Power menu | none (no lock/suspend bind; Mod+Shift+p `monitors-off`) | — | **new** (S-140) | AM #218 |
| Wallpaper | `output * bg #000000 solid_color`; `wallpaper` script for imagine accents | `layout.conf:16`, `dot_local/bin/wallpaper` | **keep** | shell draws no background layer (S-185) |
| Idle | swayidle one-shot via `monitors-off`; kanshi | `binds.conf:127`, `startup.conf:5` | **keep** | AM L508 |
| Chrome apps (Claude, Gmail, Notion calendar) | Mod+Shift+c / w / period | `binds.conf:28-30` | **keep**; registry entries **new** | |
| Files | nautilus on Mod+e | `binds.conf:25` | **new** `gpuix-shell files` (S-155; nautilus stays) | |
| Touchpad toggle | `touchpad-toggle` on Menu; Caps → touchpad OSD | `binds.conf:141` | **keep** | |
| Keybind cheatsheet | none | — | **new** (S-165) | Nov-2025 wish |
| Polkit agent | "polkit enabled, no agent" (fleet ledger P4, REPORTED wave1/30 #216) | — | **new**, P2 (S-189) | AM #216 MUST; gap |
| Old waybar | deleted 2026-09-11 | `git show 1d926f2e^:home/dot_config/waybar/` | n/a | pre-herdr reference only |

---

## 3D. IPC crosswalk: Omarchy / DMS / Noctalia verbs → `gpuix-shell` socket verbs

Everything a Sway bind or a script may call. Left three columns MEASURED tonight (§3A); right column is the proposed `gpuix-shell <verb>` over `$XDG_RUNTIME_DIR/gpuix-shell/shell.sock` (BRIEF:100-103, SCOPE §22), tagged with the June-11 class (READ / WRITE-reversible / ACTION-irreversible / SECRET-AUTH; `design/00-IDEAL-TARGET.md:13-18`, REPORTED wave1/30 §3.2).

| Domain | Omarchy (`omarchy-shell <target> <method>`) | DMS (`dms ipc call <target> <method>`) | Noctalia (`noctalia msg <cmd>`) | gpuix-shell verb (class) |
|---|---|---|---|---|
| Liveness / status | `ping`, `listPlugins`, `listShellConfig`, `debugBarGeometry` | `bar status`, `settings tabs|get` | `status` (JSON), `log-level-*` | `ping`, `status --json`, `<surface> ui-tree` (READ) |
| Surface summon | `summon <id>`, `hide`, `toggle <id>`, `togglePanelAt`, `call <id> <method>` | `<target> open|close|toggle|focusOrToggle` | `panel-open <id> [context]`, `panel-close`, `panel-toggle <id> [context]` | `toggle|show|hide <surface> [--view v] [--query q]` (WRITE-rev) |
| Bar / rail | `toggleBarTransparency`, `putBarWidget|moveBarWidget|setBarWidget` | `bar reveal|hide|toggle|autoHide|setPosition` | `bar-show|hide|toggle|reserve-toggle|auto-hide-set|layer-set [bar] [monitor]` | `rail toggle|show|hide [--output X]`, `rail expand|collapse` (WRITE-rev) |
| Launcher | `omarchy menu toggle|summon <route>|close|refresh` | `spotlight open|close|toggle|openWith <src>|openQuery <q>` | `panel-toggle launcher [query]`, `noctalia dmenu -p` | `launcher toggle [--view music|wifi|…] [--query q]`, `cmd ls|launch <id>`, `select` (stdin dmenu) (WRITE-rev) |
| Notifications | `notifications dismissOne|dismissAll|invokeLast|count|toggleDnd|setDnd|dndState|openPanel|closePanel|snooze…` | `notifications clearAll|dismiss|dismissAllPopups|toggleDoNotDisturb|getDoNotDisturb|enableDoNotDisturbUntil…`; `toast info|warn|error…` | `notification-dnd-set|toggle|status`, `notification-show`, `notification-invoke-latest`, `notification-clear-active|history` | `notify dismiss [--last|--all]`, `notify restore-last`, `notify invoke-last`, `notify dnd on|off|toggle|status`, `notify count`, `toast <level> <text>` (WRITE-rev; invoke = ACTION) |
| OSD | `omarchy-osd` kinds volume/mic/keyboard/brightness | side effect of `audio`/`brightness`/`mic` verbs; `niri showTouchpadOsd` | `osd-enable|disable|toggle`, `osd-show <icon> [value]`, `volume-osd|mic-volume-osd|brightness-osd [n]` | `osd <volume|mic|brightness|caps|touchpad|audio-route|media> [value|label]` (cosmetic) |
| Audio / mic / media | panels `audio`; `omarchy-audio-*` | `audio setvolume|increment|decrement|mute|cycleoutput|status`, `mic …`, `mpris list|play|pause|playPause|previous|next|stop` | `volume-*`, `mic-*`, `media previous|next|toggle|play|pause|stop|previous-player|next-player` | **none**: keys keep `volume`/`media`/`audio-route` scripts (10-12 ruling); `controls open audio` for the picker; `music <verb>` for Navidrome (S-085) |
| Brightness | `omarchy-brightness-*` | `brightness set|increment|decrement|list|status` | `brightness-set|up|down [monitor|*] [n]` | **none**: `brightness` script stays; it calls `osd brightness <n>` |
| Network / BT | panels `network`, `bluetooth`, `tailscale`, `wifiqr` | control-center tiles; `niri`-only extras | `wifi-enable|disable|toggle|status`, `bluetooth-enable|disable|toggle|status` | `controls open wifi|bluetooth|tailscale|audio|battery|input` (WRITE-rev); connect/pair inside = SECRET-AUTH |
| Night light / caffeine / power profile / dpms | services `nightlight`, indicator `StayAwake`; `omarchy-toggle-*` | `night toggle|…`, `inhibit toggle|enableFor`, `powerprofile set|cycle` | `nightlight-*`, `caffeine-enable|disable|toggle`, `power-set|power-cycle`, `dpms-on|off` | `controls open battery` (profiles), `inhibit on|off|toggle` (WRITE-rev); night light **out** (AM #243); dpms = `monitors-off` script |
| Clipboard | overlay + `omarchy-clipboard-*` | `clipboard open|close|toggle` | `clipboard-clear|copy <text>|text` | `clipboard ingest` (from `wl-paste --watch`), `clipboard open`, `clipboard clear`, `clipboard text` (WRITE-rev) |
| Power / session | menu `system.*`; `omarchy-system-lock|sleep-lock` | `lock lock|lockAndOutputsOff|isLocked`, `powermenu toggle`, `sessions …` | `session lock|suspend|lock-and-suspend|logout|reboot|reboot-uefi|shutdown` | `power toggle` (menu), `power <monitors-off|suspend|logout|reboot|poweroff|hibernate>` (ACTION: hold-to-confirm inside the menu; CLI requires `--yes`), `lock` (exit 69 until a locker exists) |
| Screenshot / capture | `omarchy-capture-*`, menu `trigger.capture.*` | `niri screenshot…` | `screenshot-region|fullscreen|window|annotate`, `annotate` | **none**: `screenshot`, `screen-ocr-area`, `colorpicker` scripts stay; their `notify-send` lands in the daemon (S-148) |
| Wallpaper / theme | `applyTheme <colorsB64> <shellB64>`, `omarchy-theme-*` | `wallpaper …`, `theme toggle|light|dark|getMode` | `wallpaper-*`, `theme-mode-*`, `color-scheme-*`, `templates-apply` | `reload-theme` (also on symlink change); wallpaper **none** (S-185) |
| Config / plugins | `rescanPlugins`, `reloadConfig`, `setPluginEnabled`, `omarchy plugin …` | `plugins list|status|reload|enable|disable`, `settings get|set` | `config-reload`, `plugins list|enable|disable|update|source …` | `reload` (config fragments), `registry ls --json` (READ); no enable/disable |
| Keybinds | menu `learn.keybindings` | `keybinds open [provider]|openWithPath` | settings | `cheatsheet toggle`, `cheatsheet lint` (READ) |
| Windows / workspaces | (Hyprland) | `hypr toggleOverview`, `workspace-rename open`, `window-rules` | `window-switcher [hold|current|close]` | `switcher toggle` (Mod+i); workspace ops stay `sway-workspace`/`herdr-chord` |
| Outputs | menu `setup.monitors` | `outputs listProfiles|setProfile|cycleProfile` | — | **none** (kanshi) |
| Files | `omarchy-menu-file`, image picker | `file browse` | — | `files open <path>`, `files pick --multiple --dirs` (S-160 P2) |
| Events | — (`qs ipc wait|listen` at Quickshell level) | — | `[hooks]` | `listen` (JSON event stream: surface shown/hidden, notification, herdr state) **should** |

INFERRED: three vocabularies, one shape: `<surface|domain> <verb> [args]`, verbs limited to `toggle|show|hide|open|close|status` for surfaces and domain verbs for state. Every Noctalia and DMS verb above that is **not** on the right is either a script Tom already has (keys), a compositor job (Sway/kanshi), or ruled out (wallpaper, night light, settings GUI).

---

## 4. Design values carried by the shells (for calibration, not for copying)

Tom's binding values come from the kit (wave1/11, SHELLS-DIGEST:233), DESIGN.md and the BRIEF; the numbers below are **what the donors use**, listed so a builder can see where Tom's values sit (MEASURED from the docs read tonight unless marked).

| Value | Omarchy | Noctalia v5 | DMS | caelestia | Tom / gpuix-shell |
|---|---|---|---|---|---|
| UI font size root | 12 (`[font] base-size`), monospace alias | bar `scale 1.0`, `font_weight 500` | Material scale | font roles clock/workspaces/headline/title/body/label/mono/icon | Anthropic Sans **12** UI (BRIEF:116), chrome 13 in the kit; mono figures |
| Type multipliers | caption .833, bodySmall .917, body 1, subtitle 1.083, title 1.167, heading 1.333, display 2, displayLarge 2.333, iconLarge 1.5 | — | — | — | kit: 11 floor, 13 chrome, 14 body, 15 reading (wave1/05:195) |
| Bar thickness | 26 horizontal / 28 vertical | 34 | — | — | no bar; rail 56 collapsed / 220 expanded |
| Rail/list row | — | — | — | — | 30 px rows, 12 inset, 2 gap, 8 radius (views-shell) |
| Corner radius | theme `cornerRadius`; square on Tom's seat (dig/02:137) | 12 per corner, concave edge corners | Material large | `appearance.rounding` | 6 / 8 / 12; outer corners square on Sway layer surfaces (SHELLS-DIGEST:88) |
| Control state alphas | normal/hover-cursor/focus/selected fill 0.04 / 0.08 / 0.18 / 0.22 (dig/01:32) | capsule fill `surface_variant` | — | — | ink at alpha 0.15 rest / 0.3 strong borders (dig/02:140); hover = keyboard cursor |
| Toast timings | 5 s low / 8 s normal / sticky critical, ≤30 s; ≤100 live; history 24 h | stable slots | info 1.5 s / warn 3 s / error 5 s / errorWith 8 s | `notifs` expiration + thresholds | BRIEF: 390 wide, max 4 (SHELLS-DIGEST:68) |
| Launcher size | — | full 760 wide (560-1100), simple 560×500 | — | `maxShown` | 700×580, top margin 108 |
| Control centre width | — | 700 (600-1200) | — | — | one domain list at a time (SCOPE §6) |
| Idle timings | screensaver 150 s, lock 300 s (`shell.json`) | `[idle.behavior.*]` | AC/battery split | `general` idle timeouts | swayidle (out of shell) |
| Clock format | `dddd HH:mm`, alt `d MMMM 'W'ww yyyy`, vertical `HH\n—\nmm` | — | — | `services` clock format | `HH:MM`, date in expanded mode (S-025) |
| Motion | durations → 0 switch | `shell.animation` | springs (`VectorSpringMotion`) | durations in `appearance` | one curve (0.2, 0, 0, 1); one duration token × scale that may be 0 |
| Blur / opacity | bar clear/glassy/opaque (stock **opaque**) | `compositor_blur` default **true**, `transparency_mode` | blur services | `appearance.transparency` | opaque only |

Colours: none copied. Tom's are `home/themes/{noir,claude-dark,claude-light}.nix` (noir `fg #EAECF0`, `fgDim #D3D7DE`, `accent #70B8FF`, selection `bg #264F78`, MEASURED `noir.nix:22-48` in v1); the wallpaper is `#000000`.

---

## 5. Reusable code or data, with exact paths

Nothing QML is reusable as code (wrong runtime; GPL for caelestia/II, LGPL Quickshell). What is reusable is **data shapes, protocols and pure JS**:

1. **Omarchy menu tree as data** (MIT): `basecamp/omarchy:default/omarchy/omarchy-menu.jsonc` (451 lines). Entry schema `icon, label, title, action, target, provider, aliases, description, when/checked/disabled` (`docs/menu.md:33-44`). INFERRED: the `src/registry.ts` row can be this schema minus bash guards (guards become TS predicates) so the launcher's action tree is data, hot-reloadable, user-extendable with a second JSON.
2. **Omarchy notification semantics** (MIT, MEASURED v2): `docs/notifications.md` lifetimes, click routing order, store format (`live.json`, `history.json`, `quiet.json`), bypass rules, icon resolution order. The JS modules `shell/plugins/notifications/{Store.js, Markup.js, Detect.js, Security.js, Layout.js, Delivery.js}` "also load in Node" (`notifications.md:12-14`): a test oracle for a TS port of the pure parts (row layout → placements; markup sanitising; code/link detection). Copy with the MIT notice.
3. **Omarchy OSD kinds**: `shell/plugins/osd/OsdModel.js:11-18` = `volume(-muted/low/medium/high), microphone(-muted), keyboard, brightness/display`.
4. **Omarchy theme contract**: `docs/omarchy-shell.md:197-404` sections, `[controls]` state table (`:258-263`), font multipliers (`:350-362`), spacing tokens (`:312-323`); stock `config/omarchy/shell.json` (bar layout zones, idle, dock pinned) as the shape of a rail config fragment. Tom's palettes already exist in Omarchy format: `/home/tom/mecattaf/views-shell/examples/themes/claude-dark/colors.toml` (REPORTED dig/02:65).
5. **DMS IPC vocabulary** (MEASURED v2, complete in §3A.2/§3D): the checklist for socket verbs, especially `spotlight openWith/openQuery`, `notifications enableDoNotDisturbUntil…`, `toast info|warn|error`, `inhibit enableFor`, `keybinds open sway`, `island/dot *On/*For` (per-output addressing), `defaultApp <kind>`.
6. **DMS plugin manifest shape**: `type ∈ widget|launcher|daemon|desktop|dash|dashCard|composite`, `trigger`, `permissions` (plugins-overview page) → the registry "kind" column.
7. **Noctalia** (MEASURED v2): `docs.noctalia.dev/noctalia/ipc/{system-controls,surfaces,media-and-ui,shell}` verb table (§3A.3); `ARCHITECTURE.md` four-phase frame + per-panel layer surfaces; `docs/user/launcher/index.mdx` provider design (`global` vs `prefixed`, usage boosting, `/` overview, persistent dmenu entries `[shell.launcher.dmenu.entry.<id>]` with `command, label, prefix, glyph, global, exec "{selection}"`) → the script-provider contract; `src/compositors/sway/` as a native Sway IPC backend to compare against `controller.ts`.
8. **Quickshell `I3` module** semantics for the Sway adapter: `$SWAYSOCK`, `get_workspaces/get_tree/get_outputs`, subscribe `workspace, window, output`, `run_command` (dig/02:83). Already drafted in `/home/tom/.wt/hyprland-solid-shell/design/gpuix-comparison/platform.ts` (REPORTED wave1/02:166).
9. **Previous GPUIX shell**: `/home/tom/.wt/hyprland-solid-shell/pkgs/desktop-shell/{ui.tsx, notifications.ts, notifications-daemon.ts, notifications-client.ts, providers.ts, singleton.ts, theme.ts, controller.ts, default.nix}` (BRIEF:66).
10. **Tom's scripts** the shell wraps: `home/dot_local/bin/{osd, volume, brightness, media, audio-route, screenshot, screen-ocr-area, colorpicker, theme, theme-prompt, pomodoro, monitors-off, claude-capacity, fzf-nmcli, touchpad-toggle, record, call-record-menu, sleep-monitors, wallpaper, sway-workspace, herdr-picker, herdr-chord, vpn-status}`.
11. **Vicinae builtins and extension catalogue**: `docs/vicinae-research.md:37-48, 50-58, 96-100, 110-127`; the deep inventory is wave1/35 and wave1/36.
12. **Tacit design kit**: `/home/tom/saturday-tacit/iso-files/usr/share/tacit/shell/modules/common/{Tacit.qml,widgets/Slab.qml}` and `modules/ii/{files,island,notificationPopup,onScreenDisplay,overview}/` (BRIEF:86): read for spacing, type sizes and the Slab action grammar; copy values, not code (wave1/20).
13. **Tom's March-2026 matrix**: `~/notes/references/devlogs/1h26/april-webshell-refs/ANNOTATED-feature-matrix.md` (701 lines; byte-identical copy at `devlogs/1h26/may26/cade/cowl-secondpass/docs/history/ANNOTATED-feature-matrix.md`), parsed row by row in wave1/30 §3.1. A builder who wants the reasoning behind any stance cell reads `L+1` of the row.
14. **June-11 taxonomy**: `~/notes/references/devlogs/1h26/CADE/cade-june11-idealized/research/ultimate-shell-feature-set.md` (per-domain D-Bus service + verb + READ/WRITE/ACTION/SECRET class) and `design/00-IDEAL-TARGET.md:13-18`: the class column of §3D.
15. **gpui-shell** (`/home/tom/Downloads/gpui-shell/crates/`): D-Bus integration list; wave1/23 §3.4 has exact interface names.

---

## 6. Gaps and unknowns (with the default taken)

Closed since v1: Omarchy licence (**MIT**, MEASURED); Noctalia IPC command names (complete, §3A.3); DMS IPC target list (complete, §3A.2/§3D); DMS Sway keybind block (**the page has none**; default: cheatsheet parses Tom's `binds.conf`, S-165); Omarchy `shell.toml.tpl` location (doc says `default/themed/shell.toml.tpl`, `omarchy-shell.md:218`; content not fetched; the section/keys list in §3A.1 comes from the doc and suffices).

Open:

1. **Which Vicinae features are "parity"** is wave1/35-36's job; this note lists the launcher-side union only. Default: Vicinae's root set (apps, favourites, scripts, browser tabs, calculator, clipboard, files, media) is the floor (SCOPE S-051/S-052/S-061).
2. **Chrome tab search** has no gpuix path yet. Default: provider stub returning "bridge not installed" (S-067).
3. **No output selector / input region in GPUIX 0.11** (dig/02:92-93). Default: one process per surface, surfaces sized to content, rail intended for eDP-1 by launch order; file the upstream request.
4. **Three Tom MUSTs that tonight's SCOPE puts at P2**: polkit agent (AM #216/#256 MUST → S-189 P2 because GPUIX has no PAM path), tray (AM #29 SHOULD, fine), and **containers/systemd-units view** (AM #251 SHOULD, #263; not in SCOPE at all). Default: leave as P2, but list them in MORNING.md so Tom sees the deferral.
5. **Night light**: SCOPE §6 lists `night-light` among controls domains; AM #243 says "WONT … skip entirely" (the later AM #53 says "COULD … wl-gammarelay-rs"). Default taken here: **out**; the builder of `controls` should drop the domain or keep it as a stub. Record in ASSUMPTIONS.
6. **Clipboard store**: AM #86 prefers cliphist, BRIEF:113 an own store, SCOPE S-145 builds the own store. Default: own store (image previews and pin/evict need it), cliphist left installed; recorded as the "could convince me to move away from cliphist" case (AM L634).
7. **Clock placement**: every shell puts time in a bar; AM #28 "MUST" but no placement ruling. Default: rail bottom zone (S-025), mono figures, no seconds; popover without month grid (S-170).
8. **illogical-impulse and caelestia on Sway**: neither runs on Sway; their rows in 3B are function names only.
9. **Tacit's Pinax internals** were not re-read here (wave1/20 covers them); Flea's `docs/protocol.md` is the documented backend protocol. Default: `gpuix-shell files` with a bun backend speaking newline JSON (S-155).
10. **Omarchy `agents` panel data**: reads `~/.local/state/omarchy/agents/usage/*.json`; Tom's `claude-capacity`/`seats` have their own shape. Default: rail footer reads `claude-capacity`.
11. **Codex transcripts**: the 10-13/10-14 Tom quotes are taken from wave1/01, wave1/02 and dig/02, which read them directly; not re-verified by me.
12. **DMS rename**: docs and repo say Dux; the Nix module and CLI names may lag. Nothing here depends on it.
13. **Caelestia keybinds** (`keybinds.lua`) and **Noctalia plugin IPC** (`plugins` page) were not enumerated; neither affects the plan column.

What I did not do: run any shell; open any Hyprland; read Tacit's QML beyond the research notes; fetch `shell.toml.tpl` or `keybinds.lua`; touch `/home/tom/mecattaf/dotfiles`, herdr, systemd or the live Sway. Verification was light by standing rule (`agent-workflow-rules.md`): one reader, no refute pass; every MEASURED cell names its source so the morning can spot-check.
