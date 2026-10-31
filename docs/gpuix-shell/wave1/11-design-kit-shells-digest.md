# 11. Design kit: the shells digest, the surfaces table, the tokens (DESIGN source for builders)

Written 2026-10-20/21 overnight by one reader agent of the gpuix-shell build (Fable seat). Read-only
except for this file. Labels: **MEASURED** = I read it tonight at the file:line given; **REPORTED** =
the source file itself says so and cites a third file (its label is carried through, e.g. "digest:
REPORTED dig/05 s6"); **INFERRED** = my reasoning or a conflict I resolved for the builders. Tom's
words are verbatim, typos kept, with the date the source attaches to them.

Source set, all under `/home/tom/today/2026-10-17-frank/design-handoff/` (abbreviated `DH/` below):

| Short | File | Lines | What it is |
|---|---|---|---|
| SD | `DH/SHELLS-DIGEST.md` | 91 | One-page digest of the four dig reports, written 2026-10-17 05:45 for Tom |
| VF | `DH/VERIFICATION.md` | 169 | The finalizer's record of 126 findings and what won in each conflict |
| HB | `DH/HANDOFF-B.md` | 392 | The design-session brief (the one with no component library named); sections 4 to 8, 10, 14 to 16 read |
| D01 | `DH/dig/01-shells-overlaps.md` | 147 | Candidate shells, their overlaps, the 19 reconciled rules U-01..U-19 |
| D02 | `DH/dig/02-quickshell.md` | 160 | Quickshell and Omarchy as donor; GPUIX 1:1 mapping; five stylistic facts |
| D03 | `DH/dig/03-views-cpp.md` | 207 | Chromium Views numbers re-measured at 154; what survives |
| D05 | `DH/dig/05-gpuix-shell-state.md` | 152 | Tom's Linux seat surface inventory; GPUIX 0.10.0 limits; herdr protocol 22 fields |

How to use this note: section 3 (the surfaces table) and section 4 (the values) are what a builder
codes against. Section 2 is the authority behind each value. Section 6 lists what is still open, with
the default the handoff already took, so no builder waits on Tom.

---

## 1. What this source is

MEASURED (SD:1-5, VF:1-9). On 2026-10-17 Tom asked for two Claude Design sessions (A and B, one per
cloud account) to produce "the design system that we need", and for a dig into "the views c++ ; the
quickshell ; the invetigation into all the desktop shells; all their perceived overlaps". Eight dig
agents wrote `dig/01..08`; a finalizer folded them into `HANDOFF-A.md` and `HANDOFF-B.md` (identical
except line 1 and line 32, VF:9) and into `SHELLS-DIGEST.md`, then recorded every edit in
`VERIFICATION.md`. The handoff is a brief for a *design kit* (tokens, a component catalogue of 93 ids,
14 compositions X1..X14, a gallery per renderer). Its section 7 ("Desktop shell inputs") is the part
that binds the gpuix-shell: HB:108 "Treat it as binding input."

What it is not: it is not a spec of the gpuix-shell program. It designs a kit that spans three heads
(X1 Tom's Sway seat, X2 a macOS user, X3 a Chromebook user) and names the X1 layer-shell surfaces as
the one head with compositor capabilities (HB:24). The kit was written for publication, so it strips
the names "Claude" and "Anthropic" (HB:198-200). The gpuix-shell is private (BRIEF §1: "this branch
stays in Tom's private repo"), so the font names come back in; nothing else changes.

Relation to the BRIEF (`/home/tom/.wt/dotfiles/gpuix-shell/docs/gpuix-shell/BRIEF.md`): BRIEF §3
item 3 says "Surfaces and layer-shell geometry follow SHELLS-DIGEST §4". That table is SD:62-70; its
fuller form with notes is HB:153-175. Where the two differ, I note it in section 3 and section 6.

Provenance chain for the numbers (so a builder knows how hard a value is):
- Rail 220/30/12/2/8 and 196/8/6/16/4/56: views-shell C++ constants, re-read in
  `/home/tom/.wt/hyprland-solid-shell/design/claude-rail/PROPORTIONS.md:5-16` (MEASURED tonight) and
  Chromium 154 (D03:97, MEASURED there).
- Chrome text 13/20, body 14/20, radii 4/8/12/16, curve (0.2,0,0,1): Chromium 154
  `typography_provider.cc`, `layout_provider.cc`, `tween.cc` (D03:89-99, MEASURED there).
- Palette hex values: Tom's `home/themes/{claude-light,claude-dark,noir}.nix` and the herdr-web-ui
  desk he uses daily (HB:70 "studies the owner accepted and ... the web client the owner uses daily").
- Contrast ratios: computed by the finalizer (VF:18-22, HB:66, HB:289, MEASURED there).
- GPUIX limits: `~/Downloads/gpuix` at tag `@gpuix/solid@0.10.0` and main `515df19` (D05:61-80,
  MEASURED there). The BRIEF pins 0.11.0; see section 6 for what to re-check.

---

## 2. Verbatim Tom rulings relevant to the desktop shell (with dates)

All MEASURED in the source files named; the sources mark most as REPORTED from transcripts.

### 2.1 Chronological

| Date | Tom, verbatim | Where it binds | Source |
|---|---|---|---|
| 2026-07-16 | T1 "Segmented control: build custom", T2 gradients "DROPPED", T3 "Views' FocusRing wins", T4 "Leo→Views mapping must be TOTAL" | parity: every component gets a verdict per head | D03:26 |
| 2026-09-27 | "we start with web components, and only then will we get to chromium views ... port over that aesthetic into views which is in fact a much smaller subset anyway" | shell is the smaller subset of the same aesthetic | D03:28 |
| 2026-09-27 | "we investigated chromium's views c++ ... there was an "equivalency table" between view c++ components and front-end webtech for "mock/rendering") - this is the "rosetta stone" of sorts" | component vocabulary | D03:29 |
| 2026-09-11 | "i really do not like Tabs" (comment in `DF/home/dot_config/herdr/config.toml:103`) | rail rows, not tab strips | D05:27 |
| 2026-10-01 | "the rule in fact that we can derive is that anything in views c++ touches the wayland layer-shell; never a fullscreen app. this is the mistake that quickshell made. views c++ items are ONLY for layer-shell. fullscreen things are either terminal or chrome tabs/browser windows. with the occasional gtk filepicker and nautilus; that's totally tolerable" | **the shell is layer-shell only; full-screen things are kitty or Chrome** | D03:31, D05:22 |
| 2026-10-07 | "no need for chromium-derived functionality / i have been using a bar-less setup for almost a year now. the only thing that would have been useful is a left sidebar, without the need for those complex tabs." | no top bar; the left rail is the one wanted surface | D03:32, D02:24 |
| 2026-10-10 | "views-shell: you're correct that this is gone, however it will be remplaced by webapps (chrome --app) utilities for sway workspace switcher that's herdr-based" | views-shell retired; herdr-based switcher | D03:33 |
| 2026-10-12 | "make the font larger than 11 (12 or 14, need to decide, start at 12)" (Vicinae font) | launcher UI font 12 | `/home/tom/mecattaf/dotfiles/home/vicinae.nix:37` (MEASURED tonight) |
| 2026-10-13 | "vicinae (raycast clone) proves this theoretically ; we hae the sway ipc and omarchy's quickshell which you investigated a while back did exactly that." | launcher = registry host over Sway IPC | D02:21 |
| 2026-10-13 | "similarly, one sway-wired workspace switcher that can be toggled with mod i ; with herdr-provided status indicators. only for the top display" | **Mod+i switcher, eDP-1 only, herdr status** | D05:23, SD:80 |
| 2026-10-14 | "let s tick to sway window manager. less effort.." | Sway only | D02:22, D05:24 |
| 2026-10-14 01:26Z | "for the launcher, feature parity at least with vicinae ... including how it interacts w google chrome tabs is very desirable" | launcher sources include Chrome tabs | D02:23 |
| 2026-10-14 | "we re doing functionality pull from quickshell NOT visuals or aesthetics whatsoever" | borrow function, never looks | D02:11, SD:12, D01:32 |
| 2026-10-14 (dotfiles T-14, undated) | "for ht left bar, i want you to copy the same proportions as the views c++ left tab bar that we saw from google chrome." | rail 220/30/12/2/8 | D03:34 |
| (undated, `C` 1.1) | "a herdr leftbar that is disjinted and contol sway workspaces" | rail is separate from apps, drives Sway | D01:38 |
| (undated, `C` 1.1) | "the bottom macos tab bar: utilities like email etc can go below" | the app-bar idea (optional, board only) | D01:116 |
| (undated, `S/shells.md` 11) | "keypress>sway>script execution" | quick controls stay scripts; GUI is feedback only | D01:56 |
| (undated, `dematerialize/01`) | "the nuance is that gpuix-shell is for ME and the substrate actual tooling is exported to macos native etc. by design." | the boundary | D05:26 |
| (undated, `onboarding/04-design-kit-plan.md:33`) | "it's not registering ctrl +\- for zooming" | GPUIX zoom gap | D05:80 |
| (undated, `repo-andre-brandao-gpui-shell.md` s7) | on Vicinae: "i would like to fully supersede this." | launcher replaces Vicinae | D05:47 |
| 2026-10-17 | "lots to dig on those: the views c++ ; the quickshell ; the invetigation into all the desktop shells; all their perceived overlaps. this is my own local gpuix shell; for linux... but stylistiacally it s exactly the same as what is used for the frontend (gpuix whatever js - react or other - you end up using) ; for all users." | **one skin for shell and apps** (U-15, U-18) | SD:5, D02:19, D05:19 |
| 2026-10-17 | "for SURE herdr is mainstay in my setup and it s really the centerpiece of dotfiles" | herdr is the data of the shell | SD:5, D05:19 |
| 2026-10-17 | "on the sway devices, the left bar of the ai chat is a waybar style workspace (1>9) launcher" | rail = workspace launcher 1..9 | SD:91, D05:25 |
| 2026-10-17 | "the "parity" mechanism, forcing us to write meticuluosy so that it ends up seemless, is important" | gallery, byte fixtures, totality | VF:5, D03:176 |
| 2026-10-17 | "i m expecting the two claude design prompts (one per cloud accounts) so that they produce the design system that we need." | the kit exists to feed this build | D05:19 |

Also binding from config, not speech (MEASURED by the digs): `DF/home/dot_config/sway/config:2`
"No bar: Vicinae is the command surface; Mako owns notifications." (D05:11); `startup.conf:4`
"Vicinae owns clipboard history; do not start a second cliphist watcher." (D05:50); `flake.nix` 1220
and 1223 assert `!programs.waybar.enable` (D01:35).

### 2.2 The nineteen rules U-01..U-19, full sentences (MEASURED HB:112-130; identical in D01:66-94 except where noted)

The kit's CONSTITUTION.md starts from these with their numbers and wording kept (HB:110). The
gpuix-shell should adopt them as-is; a shell-only addendum can start at U-20.

**Meaning**
- **U-01 Color is spent on meaning:** everything is neutral until it means something, with accent for focus, selection, current place and links, primary for the one consequential action per view, brand for identity only, and status hues only beside a state word. [DC-01]
- **U-02 Contrast where it sits:** text reaches 4.5:1 and indicators 3:1 on every surface, theme and contrast step, and a selected or current item has one cue at 3:1 or one that is not color. [DC-02; SHL-01 test]
- **U-03 State is a field, a word and a mark:** states come from a closed vocabulary kept apart from status text, show as a word or named glyph, keep the dot for agent run state, draw unknown as unknown, and never take focus. [DC-03, SHL-04]
- **U-04 Authority and condition:** a view says whether it is sample, read-only or writable, gives loading, empty, no results, partial, stale, disconnected, denied and failed their own screens, and hides what it cannot know. [DC-04; SHL-03 part]

**Form**
- **U-05 Flat and opaque:** resting surfaces are tonal steps parted by hairlines, only floating layers carry a listed shadow, and glass is at most an optional macOS window material no meaning needs. [DC-05, SHL-05]
- **U-06 Three voices, one root:** interface, reading and mono faces are role-bound theme values sized from one root (chrome 13, body 14, reading 15, nothing under 11), with no proprietary face shared and nothing relying on letter spacing. [DC-06, SHL-06]
- **U-07 One grid:** space is a 4 px grid and sizes come from short ladders times a density factor that never changes structure, with named measured exceptions (the rail's 220/30/12/2/8), concentric corners, a legal radius factor of 0 and 24 px targets. [DC-07, SHL-07]
- **U-08 Motion only for change:** only size, position, opacity and radius move, on one curve, with durations times a scale that can be 0, no springs, no color fades, nothing waiting on animation. [DC-08, SHL-09]

**Behaviour**
- **U-09 Looking is free, acting is declared and echoed:** viewing never writes, focuses elsewhere or attaches, every action declares its consequence, reversible ones offer Undo, and outside changes show pending until the authority answers. [DC-09; SHL-03 echo]
- **U-10 One registry, drivable at equivalence:** every action is a command with a stable id, a verb-and-noun label, an unavailable reason, a consequence and one binding grammar, shared by buttons, menus, palettes, the desktop launcher and agents, and every control exposes role, name, id and state. [DC-10; SHL-03; SHL-10 roles] (D01:79 says "the Sway launcher" where HB says "the desktop launcher".)
- **U-11 One focus model, one layer stack:** states are one ink at fixed alphas with hover equal to the keyboard cursor, a 2 px accent ring appears on keyboard focus only, composites are one tab stop, Escape closes the top layer and returns focus, and every flow works by keyboard. [DC-11; SHL-08; SHL-10 parity]
- **U-12 Stable under change:** arriving content never moves what the person points at, focuses or reads; reorders wait or are announced, and placeholders reserve final geometry. [DC-18]

**Structure**
- **U-13 One row grammar:** every list draws one row (leading cell, title, trailing state, trailing action), declares navigate, select or tree, and keeps selected, current and focused as three coexisting looks. [DC-12; SHL-08 part]
- **U-14 One object, many lenses:** an item keeps one id across lens, host, width (390 px to full, by explicit navigation) and app; names are never keys, and links carry view state. [DC-13; SHL-02 width]
- **U-15 The platform owns the frame:** every surface declares its layer; the shared library draws only app chrome and content through declared capabilities; Linux shell surfaces (rail, launcher, clipboard, switcher, notifications, on-screen display, strip) live in the builder's personal shell; macOS keeps its Dock and menu bar; the browser draws no frame of its own. [DC-14, SHL-02]
- **U-16 Agent work has one grammar:** answers read settled, with work folded into verb, target and result rows and failures open; every ask is one numbered card at the composer; finished work lights up without taking focus. [DC-15; SHL-04 part]

**Expression**
- **U-17 Words:** sentence case without styled capitals, verb-and-noun actions, confirmations reusing the verb, errors saying what happened and then what to do, relative times, middle-truncated ids, one dash for unknown. Middle truncation is computed into the string from a character budget in the mono slot, on every head, so DOM and GPUIX cut at the same character. [DC-16]
- **U-18 Identity is a skin over one theme file:** components name roles, never values, and each skin's theme file resolves per host into CSS variables or literal GPUIX values with explicit text color, in sRGB, without cascade, `calc()` or `color-mix()`; this warm identity is one skin among others. [DC-17, SHL-01]

**Harness**
- **U-19 A gallery per renderer:** every component renders headless, in every variant, state and skin, under each renderer whose head draws it, every absent verdict names its substitute, and each is compared at each upgrade; the first parity proof is one button rendered in React DOM and in GPUIX from the same tokens. The GPUIX gallery runs headless on macOS only. X1 surfaces are checked by compositor capture in a nested Sway under the owner's runtime isolation wrapper, and stay unverified until that harness exists. The gallery renders their content as an ordinary GPUIX window on macOS. [SHL-10; CONSTRAINTS 1.4]

INFERRED by the digest (SD:58, D01:96): U-15 and U-18 together are the answer to "stylistiacally it
s exactly the same": the shell is a separate layer on the same skin. For the gpuix-shell that means:
the rail, launcher, toasts and OSD are their own processes and surfaces, but every colour, size, radius
and word comes from the same `gpuix-shell.json` theme fragment and the same component rules as the apps.

### 2.3 The sixteen corrections the handoff applied (P-01..P-16), as rulings a builder inherits

MEASURED SD:80 and D01:104-121. Each one reverses something an earlier draft got wrong.

| # | Ruling now in force | Why |
|---|---|---|
| P-01 | **No top bar** on the Linux head; `a.top-bar` is a reserved, undrawn record | "No bar" (sway/config:2); Tom 10-07 |
| P-02 | No app menu in GPUIX; commands live in the palette | GPUIX cannot declare app menus |
| P-03 | **Mod+I switcher kept** (reversing D01's "drop Mod+I") | Tom 10-13, quoted in 2.1 |
| P-04 | No clay on the active rail icon; current item uses accent | DC-01; clay is 2.96:1 on Light |
| P-05 | Mono not for timings in prose; a `figures` role (mono) for row times and counts | G4 default restored (VF:20) |
| P-06 | No shadows at rest; elevation 0 and 1 carry none; Noir never | DC-05 |
| P-07 | One easing curve | DC-08 |
| P-08 | Tracking optional, 0 in GPUIX | GPUIX has no letter-spacing |
| P-09 | Notifications = in-app run state + kit-themed desktop toasts + a daemon theme | Mako owns the bus until the gpuix daemon passes its checks |
| P-10 | Quick controls = OSD feedback only; keys keep running scripts | "keypress>sway>script execution" |
| P-11 | Clipboard history, OSD, task strip added as surfaces/sources | they were missing from the prompts |
| P-12 | Run-state vocabulary bound to herdr's five values | SHL-04, G3 |
| P-13 | GPUIX facts corrected; `canvas` and `registerFont` removed from 0.10.0 claims | 0.10.0 has neither (0.11.0 adds registerFont, BRIEF §2) |
| P-14 | One shared constitution U-01..U-19 for both sessions | parity |
| P-15 | Theme source of truth left open (Unknown 1) | reverses the dotfiles' direction; Tom's call |
| P-16 | 390 px sizes restored (toast width; narrow lens) | DC-13 |

---

## 3. Feature and behaviour inventory

### 3.1 The Linux head surfaces (X1), exact layer-shell values

MEASURED HB:153-161 (the authoritative table) merged with SD:62-70 and D05:42-55. Every X1 surface is
one GPUIX layer-shell surface in its own process, with a fixed size set when it opens; "exclusive zone
-1 reserves nothing, and 0 lets the compositor place the surface without reserving space" (HB:151).

| Surface | Kit id | Layer | Anchor | Exclusive zone | Keyboard | Size | Notes (HB:155-161 verbatim where quoted) |
|---|---|---|---|---|---|---|---|
| Left rail | `a.rail-surface` (hosts `c.rail`, `a.session-row`) | top | left, top, bottom | **220** (collapsed launch: **56**) | on-demand, "fixed at open (Sway gives it focus only on click or a bound key)" | 220 wide (56 collapsed), full height | "top display only; footer carries clock and status, since there is no bar; collapsed (56 wide) is a separate launch with its own width and exclusive zone, never an animated collapse; rename and reorder by keyboard happen in the switcher (keyboard exclusive), which shows the same rows" |
| Task strip (optional) | `a.projection-strip` | top | top, left, right | 0 | none | one row | "not drawn by default; frame-board option only; when drawn, exclusive zone 0, top display; agent tasks first, then items waiting on the owner; activating an item opens the switcher" |
| Workspace switcher | `a.workspace-switcher` | overlay | top, margin **[108, 0, 0, 0]** | -1 | exclusive | (same card as launcher, INFERRED) | "top display; Mod+I; rows are rail rows" |
| Launcher | `a.launcher` (hosts `c.command-palette`) | overlay | top, margin **[108, 0, 0, 0]** | -1 | exclusive | **700 x 580** | "sources: all, windows, browser tabs, workspaces, applications, commands, clipboard, files; same rows and ids as c.command-palette" |
| Toasts + notification centre | `a.notification` (hosts `c.toast`) | overlay | top, right | -1 | none for toasts, exclusive for the centre | toasts **390 wide, at most 4, each a fixed 140 px card**; centre **500 x 650** | "must also work as a theme for an existing notification daemon" |
| On-screen display | `a.osd` | overlay | bottom, margin **[0, 0, 96, 0]** | -1 | none | one slot | "one replaceable slot: label, icon and a level bar" |
| Quick controls (optional) | `a.quick-controls` | overlay | top, right | -1 | on-demand | (DS precedent 560 x 710, D05:51) | "delegates to the same key-driven scripts; never required" |
| App bar (optional) | `a.app-bar` | (board option (b) only) | | | | | HB:165 lists it among X1 records; not drawn by default (SD:85) |
| Top bar | `a.top-bar` | **not drawn on any head** | | | | | HB:297: "write its record as 'not drawn on any head'" |

Margin arithmetic (HB:163): "The top margin is 12 percent of the output height, read by the Sway
adapter: 108 at 900 high." So the 108 is a derived value: compute `round(0.12 * output_height)` from
`swaymsg -t get_outputs`, do not hard-code it. The OSD 96 is given as a fixed margin.

Anchor rules (HB:163): "the protocol centres a single-edge anchor on the other axis. Vertical centring
is not available in 0.10.0, and an empty anchor list becomes top, left and right (a full-width bar),
so no surface leaves it empty."

Behaviour rules for X1 surfaces (HB:165-175, MEASURED; each a one-liner a builder can test):
1. Shared ids (`c.rail`, `c.toast`, `c.command-palette`, `a.session-row`) carry `layerShell: null`; only the surface records above fill it.
2. Outer corners are a platform-frame property recorded in `layerShell`; "Draw Linux layer surfaces with the same outer radii as their macOS and web counterparts (toast and menu 12, launcher 16)". The square-outer variant is an X1 board option for Tom.
3. "X1 layer surfaces carry no shadow and no scrim in any theme. Elevation is the elevated surface value plus a 1 px `line.strong` edge, as in Noir, and the surface size equals the visible card."
4. "Every X1 surface paints an opaque ground first ... the theme resolver also emits pre-blended solid hover and selected fills, so no overlay ever carries an alpha ground." (So: `transparent: false` is the intent; the DS precedent's `transparent: true` at `ui.tsx:1283` was for Hyprland blur and is refused.)
5. "The X1 rail and strip surfaces draw no tooltip, menu, popover or flyout. Row actions (rename, park, restore, close, move) are commands reached from the switcher and the launcher."
6. "The collapsed rail shows only slot numbers and run-state glyphs, and opens the switcher for names."
7. Toasts: "a fixed 140 px card: the title on one line, the body clamped to two lines, at most two actions. A change in count reopens the stack surface; nothing slides between counts, and only the new card fades in by opacity." Toast actions are also launcher commands.
8. "X1 overlays snap open complete on their first frame, with no enter motion, and launcher history and selection are restored from the adapter. Opening one exclusive overlay closes the others through the adapter."
9. Zoom (HB:316): "X1 surfaces follow the output scale and are exempt from in-app zoom; a factor change reopens them."
10. Out unless Tom asks (SD:72, HB:149): lock, wallpaper, polkit, tray, dock.

INFERRED conflict with the BRIEF: BRIEF §3.3 reads "exclusive zone 56 collapsed (220 expanded, X1
option)", which makes 56 the default. HB:155 and SD:64 make **220 the default** and 56 the separate
collapsed launch; VF:45 "Collapsed 56" and SD:87 "Now fixed at 56 in both prompts" refer to the
collapsed width, not the default. D05:149 worried that 220 may not fit eDP-1 (about 1440x900 logical,
INFERRED there). Default I recommend for the builders: ship both launches (`gpuix-shell rail` at 220,
`gpuix-shell rail --collapsed` at 56), start the unit at 220, and log the choice in ASSUMPTIONS.md.

### 3.2 Who owns each function on the Linux head (MEASURED HB:134-145; SD:25-34)

| Function | Linux today (MEASURED by digs) | Owner in the kit (X1) | Keep / replace / new |
|---|---|---|---|
| Commands | Vicinae on `$mod+d`, `$mod+space`; `herdr-picker` on `$mod+Ctrl+space` (D01:36) | "one registry; the desktop launcher overlay and every in-app palette are entry points to it" | replace (launcher) |
| Clipboard history | Vicinae `$mod+v`; "do not start a second cliphist watcher" (D05:50) | "a launcher source; opening it never pastes" | replace (launcher source) |
| Notifications | Mako owns `org.freedesktop.Notifications` (D05:48) | "in-app run state first; desktop toasts styled by the kit; only 'needs input' and finished work may notify" | replace (daemon), never both |
| Workspaces | Sway `$mod+1..9` eDP-1, `$mod+0` eDP-2; herdr projectors one per slot (D05:44) | "the herdr rail plus Sway keys (Mod+1 to Mod+9) and the switcher overlay" | new (rail, switcher) |
| Session list inside an app | herdr-web-ui sidebar | "none on X1 while the shell rail is present (the app checks a declared capability `shell.rail` and draws no workspace sidebar)" | new capability flag |
| Top bar | none | none | keep absent |
| App bar / dock | none | "none by default (optional board item in X1)" | board only |
| Quick controls | F-key fzf prompts in floating kitty 640x200/300 (D05:51) | "keys run scripts; the shell draws only feedback (on-screen display)" | keep scripts; new OSD |
| OSD | `~/.local/bin/osd` = `notify-send -r` into Mako with progress hint (D05:49) | `a.osd` | replace |
| Layout | Sway | the compositor | keep |
| Theme input | `home/themes/*.nix` fragments (kitty, ghostty, sway, mako, vicinae, fish, lua, meta) | "one theme file, rendered for every Linux program" | new fragment `gpuix-shell.json` |
| Lock | none found; swayidle for monitor wake (D02:52) | out of scope; if ever, `ext-session-lock`, never an Exclusive layer surface | absent |
| Wallpaper | `output * bg #000000 solid_color` (D02:53) | out of scope | keep |
| Tray | Vicinae `tray.enabled = false` (D02:101) | out of scope; GPUIX has no StatusNotifier host | absent |

### 3.3 Feature inventory table (the builders' checklist)

Columns: feature | what exactly | where it lives today | keep/replace/new | notes. MEASURED unless
tagged; "DS" = `/home/tom/.wt/hyprland-solid-shell/pkgs/desktop-shell/`.

| Feature | What exactly | Where it lives today | Keep/replace/new | Notes |
|---|---|---|---|---|
| Rail: workspace rows 1..9 | One row per Sway slot; content = the herdr workspace bound to that slot's projector; row = icon cell + title + state text in 196x30; title 13/18 | no surface; slots are Sway marks `herdr-slot-N` (D05:44); geometry in `claude-rail/PROPORTIONS.md` | new | Slot is X1 shell state in a `slot` field, never in an entity id (HB:179). "Never infer current identity from the server's global focus" (herdr-picker:5-6, D05:58) |
| Rail: slot states | live, parked (closed window, session kept), restorable | Mod+w park, Mod+Shift+t restore (D05:52) | new | "Mod+w and Mod+Shift+t are Chrome's close tab and reopen closed tab, applied to terminals" (D05:59) |
| Rail: agents list | Independent list of agent rows, two lines (title over workspace), monogram per `display_agent` | herdr-web-ui DESIGN.md roster | new | "Workspaces and agents are two independent lists" (HB:180) |
| Rail: footer | Clock and status (there is no bar) | none | new | HB:155; D01:139 "clock and status in the rail footer" |
| Rail: collapsed 56 | Slot numbers + run-state glyphs only; opens switcher for names | none | new | separate launch, not an animation (HB:155) |
| Rail: selected/current cues | Selected: title at weight 500; current: + 2 px accent leading bar | herdr-web-ui | new | HB:100, VF:19 (D9/G17 fix) |
| Rail: no flyouts | No tooltip/menu/popover on rail or strip | | rule | HB:171; GPUIX popups cannot leave their surface anyway |
| Switcher (Mod+i) | Overlay, keyboard exclusive, eDP-1, same rows as rail + rename/reorder/park/restore/close/move commands | PR #565 fuzzel `sway-workspace-switcher --output eDP-1`, "Herdr status read once at open" (D05:46) | replace fuzzel | Needs output choice GPUIX lacks (section 6) |
| Launcher | 700x580 overlay; sources all, windows, browser tabs, workspaces, applications, commands, clipboard, files; rows 44 (compact 40); palette = launcher at 700 wide; width 640 for in-app palette | Vicinae; DS `launcher` providers `all, windows, applications, commands, clipboard, files` (D05:47), 20 fixed commands (D02:73) | replace Vicinae | Vicinae gaps DS listed: "Chrome tab search, a tray host, indexed files, unit conversion, clipboard retention" (D02:115). Chrome tabs come via Vicinae's native messaging host today (`vicinae.nix:98-99`) |
| Launcher: registry | Command ids `<app>.<object>.<verb>`; entity ids `<app>:<type>/<id>` e.g. `herdr:workspace/<workspace_id>` | | new | HB:336. Letter keys never taken from the query; scope chips (D01:36) |
| Launcher: clipboard | A source; opening never pastes | Vicinae `Mod+v` | replace | owner switch is all-or-nothing (D05:146) |
| Notifications daemon | `org.freedesktop.Notifications` server over dbus-next; toasts top-right 390 wide, max 4, 140 px cards; centre 500x650 keyboard exclusive | Mako; DS `notifications-daemon.ts` (79 lines) + `toasts` mode (`ui.tsx:1239-1302`) | replace Mako | Only "needs input" and finished work may notify (HB:138). Also ship a Mako theme as fallback (P-09) |
| Attention → urgency | herdr attention to Sway urgency + notification actions | branch `herdr-sway-context` `herdr-attention` 442 lines (D05:12) | reuse logic | not on main |
| OSD | One replaceable slot: label, icon, level bar; overlay bottom margin 96, no zone, no keyboard | `~/.local/bin/osd` via Mako (D05:49); called by `volume`, `brightness`, `touchpad-toggle` | replace | keep the scripts; replace their sink |
| Quick controls | Optional overlay delegating to scripts | F-key fzf kitty floats; DS `controls` 560x710 | optional | "never required" (HB:161) |
| Task strip | Optional one-row top strip: agent tasks, then waiting-on-you | not built | board option (d) | zone 0 (VF:16 conflict 4) |
| Theme reload | Watch `~/.config/theme` symlink, reload live | DS `theme.ts` watches + `SIGUSR1` (D02:65, D02:159) | reuse pattern | fragment `gpuix-shell.json` per BRIEF §3.5 |
| Density | comfortable default; compact = each size minus 1, floor 11 | | new | HB:234 |
| Motion scale | Off 0, Fast 0.5, Default 1, Slow 1.75 | herdr-web-ui `--motion-scale` | new | HB:98 |
| Run-state glyphs | 16 px monochrome svg icons with explicit ink, never text glyphs, never animated | herdr-bar text glyphs (D05:124) | new | HB:192 |
| Working dot pulse | opacity 1.0 ↔ 0.55 every 600 ms, timer-driven, duration 0; still under motion scale 0 | | new | HB:98 |
| herdr down | rows show "unavailable"; switching workspaces still works | SH-06 (D05:126) | new | HB:192 |
| Keyboard focus ring | 2 px accent, keyboard-only; +2 offset on controls, -2 inset on rows "drawn in 0.10.0 as a reserved 2 px border on rows"; driven by app focus + last-input-was-keyboard flag | | new | HB:100; set `keyboardFocusDim: false` where the option exists (HB:342) |
| Hint labels | `c.hint-labels`: hint letters over rows/windows of the current view, stale state | | later | HB:299 |
| File explorer | `c.file-browser` (roots, previews, provenance), X14 | | new (BRIEF: Pinax-like) | ordinary window, not layer-shell |
| Projector (terminal) | stays kitty; never gpuix | kitty `herdr-projector` | keep | Tom 10-01 |
| Desk (chat, projects) | stays Chrome `--app` | herdr-web-ui | keep | D05:53 |
| Zoom | Ctrl+plus/minus/0 as one root factor via the theme resolver; X1 surfaces exempt | | new (apps) | HB:316 |

---

## 4. Design values

### 4.1 Palette, three themes (MEASURED HB:44-64 section 5; HB:74-86 section 6.1)

Names: the kit says light / dark / noir; dotfiles say claude-light / claude-dark / noir. Default:
"Light by day, Noir by night" (HB:40); the BRIEF says noir default for the shell.

Section 5 source roles (these are Tom's `home/themes/*.nix` keys; `noir.nix` MEASURED tonight
confirms fg #EAECF0, fgDim #D3D7DE, comment #818898, accent #70B8FF, brand #D97757, selection.bg #264F78):

| Source role | Light | Dark | Noir |
|---|---|---|---|
| ground.base | #F9F9F7 | #1A1A1A | #000000 |
| ground.dim | #F3F3F0 | #151515 | #000000 |
| ground.raised | #FFFFFF | #20201F | #000000 |
| ground.desktop | #F0EFEC | #20201F | #000000 |
| fg (strong ink) | #131313 | #EAECF0 | #EAECF0 |
| fgDim (body ink) | #52514E | #D3D7DE | #D3D7DE |
| comment | #6E7687 | #818898 | #818898 |
| brand (clay) | #D97757 | #D97757 | #D97757 |
| accent | #0051C2 | #70B8FF | #70B8FF |
| border.active | #A5A49A | #555451 | #555451 |
| border.inactive | #D2D1C7 | #373735 | #373735 |
| red (urgent) | #B80A18 | #F47B85 | #F47B85 |
| green | #008000 | #9BE963 | #9BE963 |
| yellow | #A66A00 | #F9E2AF | #F9E2AF |
| orange | #B24A00 | #FBAD60 | #FBAD60 |
| cyan | #007F80 | #5EEDED | #5EEDED |
| magenta | #8100C2 | #CC7BF4 | #CC7BF4 |
| selection bg / fg | #CDE2FB / #131313 | #264F78 / #EAECF0 | #264F78 / #EAECF0 |
| primary fill / hover / text | #A74B2F / #913E27 / #FFFFFF | #D97757 / #E58B6D / #131313 | same as Dark |

Section 6.1 role values (the ones the shell paints with):

| Role | Light | Dark | Noir |
|---|---|---|---|
| canvas | #F9F9F7 | #1A1A1A | #000000 |
| panel (rail, chrome) | #F0EFEC | #20201F | #000000 |
| elevated | #FFFFFF | #262625 | #101111 ("black lifted 7 percent toward ink") |
| hover fill (daily client; kit uses state.hover) | #E7E7E5 | #2C2C2B | #171818 |
| input ground | #FFFFFF | #20201F | #000000 |
| line ink | #1F1E1D | #DEDCD1 | #DEDCD1 |
| line hairline / default / strong (alpha of line ink) | 0.15 / 0.30 / **0.50** | 0.15 / 0.30 / **0.42** | 0.15 / 0.30 / **0.44** |
| text / text dim / text strong | #131313 / #52514E / #131313 | #D3D7DE / #8F96A5 / #EAECF0 | #D3D7DE / #818898 / #EAECF0 |
| run working / needs input / done | #0051C2 / #9A3F00 / #006B00 | #70B8FF / #FBAD60 / #9BE963 | as Dark |
| danger text / notice | #B80A18 / #B24A00 | #F47B85 / #F9E2AF | as Dark |
| scrim | #131313 at 0.35 | #000000 at 0.60 | #000000 at 0.70 |
| terminal bg / fg / cursor / selection | #F9F9F7 / #131313 / #131313 / #CDE2FB | #1A1A1A / #EAECF0 / #EAECF0 / #264F78 | #000000 / #EAECF0 / #EAECF0 / #264F78 |

Deliberate AA lifts (HB:88): body dim #52514E not comment #6E7687; needs-input #9A3F00 not #B24A00;
done #006B00 not #008000.

Contrast facts to design around (HB:66, HB:289, VF:18-22, all MEASURED by the finalizer):
- Clay #D97757 on Light base 2.96 → clay text fails in Light. White on clay 3.12. Dark ink on clay 5.95.
- Light primary fill #A74B2F: 5.40 on base, 5.69 with white text. ink.on-brand Dark/Noir #131313 on #D97757: 5.95.
- ink.on-accent on accent: 7.10 Light, 8.84 Dark/Noir.
- Light yellow on base 4.25 → never small text.
- Opaque borders are decorative: Light border.active 2.38, border.inactive 1.46; Noir border.inactive on black 1.76.
- Ink-at-alpha borders: 0.15 → 1.35 / 1.46 / 1.30; 0.30 → 1.90 / 2.30 / 2.09. Hence `line.strong` at 0.50 / 0.42 / 0.44 → 3.20 / 3.26 / 3.38 on canvas, 3.27 / 3.14 / 3.49 on elevated. **Inputs and X1 surface edges use line.strong** (≥ 3:1).
- ink.subtle: #666D7E Light (4.91 canvas, 4.51 desktop); #878E9D Dark (5.29; 4.61 raised); #818898 Noir (5.91; 5.32 raised).

Pre-blended state fills (HB:274-275; VF:30), use these literal solids in GPUIX, never an alpha ground:

| | Light | Dark | Noir |
|---|---|---|---|
| state.hover = ink at 0.10 | #E3E3E1 | #2E2D2C | #161615 |
| state.selected = ink at 0.16 | #D6D6D4 | #393937 | #242321 |

Category tints (HB:90, calendar/timeline lanes, tool chips): rose Light #F0D9E3 on #773452, Dark
#452D38 on #E4ABC3; mint Light #BCD1CA on #284F42, Dark #263C34 on #B8D5C9; violet Light #CBCADB on
#4C456C, Dark #363445 on #CBC5E9; blue Light #D9E4F0 on #355C82, Dark #293847 on #B1CEE8. Noir = Dark.

Terminal ANSI 0..15 (HB:92): Light: 0 #2B303B, 1/9 #B80A18, 2/10 #008000, 3/11 #A66A00, 4/12 #0051C2,
5/13 #8100C2, 6/14 #007F80, 7 #52514E, 8 #6E7687, 15 #131313. Dark: 0 #1A1A1A, 1/9 #F47B85, 2/10
#9BE963, 3/11 #F9E2AF, 4/12 #70B8FF, 5/13 #CC7BF4, 6/14 #5EEDED, 7 #D3D7DE, 8 #818898, 15 #EAECF0.
Noir: as Dark with 0 #000000.

### 4.2 Token schema: names and accepted values (MEASURED HB:202-234, section 10)

Format: DTCG 2025.10 (`$value`, `$type`, `$description`, `$extensions.kit` {usage, rules, avoid}).
Colors `{"colorSpace":"srgb","components":[r,g,b],"hex":"#RRGGBB"}` + optional `alpha`; dimensions
`{"value":n,"unit":"px"}`; durations `{"value":n,"unit":"ms"}`; easings `[0.2,0,0,1]`; line heights
unitless (3 decimals); weights numbers. Files: `base.tokens.json` (section 5 rows as `palette.<role>`),
`semantic.tokens.json` (every key below), `theme.<name>` and `density.<name>` hold only overrides. CSS
names `--kit-` + path with hyphens (`--kit-color-surface-canvas`). INFERRED for this build: the
dotfiles fragment `gpuix-shell.json` should be the *resolved* semantic layer for one theme (flat, no
references), since GPUIX takes literals; keep the key names below so a future kit export maps 1:1.

Group and key names (fixed; additions only via PROPOSALS, never renames):

- `color.surface`: canvas, base, raised, sunken, overlay, desktop, input, inverse
- `color.ink`: default, muted, subtle, disabled, inverse, on-brand, on-accent, link
- `color.line`: hairline, default, strong, focus
- `color.brand`: default, emphasis, muted
- `color.accent`: default, emphasis, muted
- `color.status.{danger,warning,success,info,neutral}`: fg, bg, line, emphasis
- `color.run`: idle, working, blocked, done, unknown (each fg and dot; display words separate)
- `color.selection`: bg, fg ("GPUIX sets selectionColor explicitly to color.selection.bg so its 35 percent accent default never shows")
- `color.state`: hover, pressed, selected, disabled (overlays; plus pre-blended solids for GPUIX)
- `color.scrim`: default
- `color.data`: cat-1..8, seq-1..5, div-1..7, up, down
- `color.terminal`: ansi-0..15, fg, bg, cursor
- `font.slot`: ui, prose, mono
- `font.weight`: regular 400, medium 500, semibold 600, bold 700, current 580 (600 if not variable)
- `type` (composite slot/size/line-height/weight/tracking 0): caption 11/16, meta 12/18, small 13/20, body 14/21, prose 15 @1.65, prose-long 17 @1.65, prose-page 20 @1.65, title 16 @1.2, heading 18 @1.2, page 24 @1.2 w600, display 22 @1.2, code 13 @1.6 mono, code-small 12 @1.6 mono, figures 12/18 mono
- `space`: 0..11 = 0, 2, 4, 6, 8, 12, 16, 20, 24, 32, 40, 48
- `size.control`: xs 24, sm 28, md 34 (compact 32), lg 36; `size.icon`: sm 16, md 18, lg 20; `size.target`: min 24, touch 40
- `size.row`: list 56 (compact 44), rail 30, launcher 44 (compact 40); `size.chip`: 20 (compact 18); `size.mark`: 22; `size.header`: 46
- `radius`: none 0, xs 6, sm 8, md 12, lg 16, xl 24, full 9999
- `elevation`: 0..3 (surface, line, shadow)
- `motion.duration`: instant 0, fast 120, base 180, slow 240, sheet-in 360; `motion.easing`: standard, enter, exit (all three = the one curve); `motion.scale`: default 1, reduced 0
- `z`: base 0, raised 10, dropdown 100, overlay 200, modal 300, toast 400, tooltip 500 (GPUIX: anchored priority for dropdown..tooltip, tree order for base/raised)
- `layout.rail`: width 220, row 30, inset 12, gap 2, radius 8, row-width 196, content-inset-x 8, content-inset-y 6, icon 16, child-gap 4, collapsed 56
- `layout.content`: reading 820, chat-min 820, chat-max 960; `layout.palette`: width 640, top 12 percent; `layout.launcher`: width 700, height 580; `layout.toast`: width 390, max 4; `layout.notification-center`: width 500, height 650
- `layout.breakpoint`: compact 480, medium 768, wide 1080
- `focus`: width 2, offset-control 2, offset-row -2, style solid
- Modes: theme (light, dark, noir) x density (comfortable default; compact = each size minus 1, floor 11)

Key bindings table 10.1 (HB:238-287; every colour key's value or formula). "Ink" = the 6.1 line ink.

| Key | Light | Dark | Noir |
|---|---|---|---|
| surface.canvas, surface.base | #F9F9F7 | #1A1A1A | #000000 |
| surface.raised, surface.overlay | #FFFFFF | #262625 | #101111 |
| surface.sunken | #F3F3F0 | #151515 | #000000 |
| surface.desktop | #F0EFEC | #20201F | #000000 |
| surface.input | #FFFFFF | #20201F | #000000 |
| surface.inverse | #131313 | #EAECF0 | #EAECF0 |
| ink.default | #131313 | #D3D7DE | #D3D7DE |
| ink.muted | #52514E | #8F96A5 | #818898 |
| ink.subtle | #666D7E | #878E9D | #818898 |
| ink.disabled | ink.default at 0.38 | same | same |
| ink.inverse | #F9F9F7 | #1A1A1A | #000000 |
| ink.on-brand | #FFFFFF | #131313 | #131313 |
| ink.on-accent | #FFFFFF | #131313 | #131313 |
| ink.link | = accent.default | = | = |
| line.hairline / default / strong | ink 0.15 / 0.30 / 0.50 | ink 0.15 / 0.30 / 0.42 | ink 0.15 / 0.30 / 0.44 |
| line.focus | = accent.default | = | = |
| brand.default | #D97757 | #D97757 | #D97757 |
| brand.emphasis (primary fill) | #A74B2F | #D97757 | #D97757 |
| brand.muted | clay at 0.12 over canvas | clay at 0.16 | clay at 0.16 |
| accent.default, accent.emphasis | #0051C2 | #70B8FF | #70B8FF |
| accent.muted | accent at 0.10 over canvas | accent at 0.13 | accent at 0.13 |
| status.danger.fg | #B80A18 | #F47B85 | #F47B85 |
| status.warning.fg | #B24A00 | #F9E2AF | #F9E2AF |
| status.success.fg | #006B00 | #9BE963 | #9BE963 |
| status.info.fg | = accent.default | = | = |
| status.neutral.fg | = ink.muted | = | = |
| status.*.bg | fg at 0.12 over canvas | fg at 0.14 | fg at 0.14 |
| status.*.line, .emphasis | = that fg | = | = |
| run.working fg/dot | #0051C2 | #70B8FF | #70B8FF |
| run.blocked fg/dot | #9A3F00 | #FBAD60 | #FBAD60 |
| run.done fg/dot | #006B00 | #9BE963 | #9BE963 |
| run.idle | = ink.muted, not drawn in rows | same | same |
| run.unknown | = ink.muted, only with ○ and the word Unknown | same | same |
| selection.bg / fg | #CDE2FB / = ink.default | #264F78 / = ink.default | #264F78 / = ink.default |
| state.hover (pre-blended) | #E3E3E1 | #2E2D2C | #161615 |
| state.selected (pre-blended) | #D6D6D4 | #393937 | #242321 |
| state.pressed | ink at 0.16 | same | same |
| state.disabled | canvas at 0.50 over the control | same | same |
| scrim.default | #131313 at 0.35 | #000000 at 0.60 | #000000 at 0.70 |
| data.cat-1..8 | #0051C2 #B24A00 #008000 #8100C2 #007F80 #B80A18 #A66A00 #6E7687 | #70B8FF #FBAD60 #9BE963 #CC7BF4 #5EEDED #F47B85 #F9E2AF #818898 | as Dark |
| data.seq-1..5 | accent at 0.20/0.40/0.60/0.80/1.00 over canvas | same | same |
| data.div-1..7 | danger 1.00/0.66/0.33; ink.muted 0.20; accent 0.33/0.66/1.00 | same | same |
| data.up / down | = run.done / = status.danger.fg | same | same |
| elevation.0 | canvas, no line, no shadow | same | same |
| elevation.1 | raised, line.hairline, no shadow | same | same |
| elevation.2 | raised, line.default, `0 2px 8px` black 0.13 | same | raised, line.default, **no shadow** |
| elevation.3 | overlay, line.default + 1 px ring, `0 16px 48px` black 0.16 | same at 0.55 | overlay, line.strong, **no shadow** |

Note for the shell: X1 layer surfaces always use the Noir-style elevation (elevated surface + 1 px
line.strong, no shadow, no scrim) in **every** theme (HB:169), so in the shell only elevation.3-noir
shape is ever drawn for overlays.

### 4.3 Typography (MEASURED HB:94 section 6.4, HB:196 section 8, HB:222)

- One root, one scale factor (`--ui-scale` on the web; a single root factor in GPUIX, HB:316).
- Sizes: chrome, controls and row titles **13/20**; body **14/21**; chat reading 15; meta 12; **floor 11**; header and modal titles 16; markdown h1 18; display 22; page headings 24 w600. Rail row title **13/18** (HB:192).
- Compact density: each size minus 1, never below 11.
- Line heights: 1.2 titles, 1.5 body (1.45 compact), 1.6 code, 1.65 prose.
- Weights 400, 500, 600, 700; 580 for the current nav item when variable.
- Three slots: **ui** (sans), **prose** (serif, assistant answers and authored reading), **mono** (code, ids, terminals, the `figures` role for row times and counts). "The person types in sans; the assistant answers in serif" (HB:38).
- For Tom's seat the slots resolve to installed families (BRIEF §1): ui = "Anthropic Sans", prose = "Anthropic Serif", mono = "AnthropicMono Nerd Font"; glyph font "Anthropicons". DS precedent named `Anthropic Mono` (`theme.ts:26-30`), which is the wrong family name for the Nerd build; use the BRIEF's.
- Vicinae today: Anthropic Sans 12 (Tom 10-12); Mako: "Anthropic Sans 11" (`vicinae.nix:114`). INFERRED for the shell: launcher rows and rail titles at 13 per the kit; the BRIEF says "Anthropic Sans 12 UI". Default: kit 13 for row titles, 12 for meta/figures; record in ASSUMPTIONS.md.
- GPUIX: no letter-spacing, italic or text-transform; "uppercase is written into the string", italic is a separate installed face (HB:196). One font family string per text node (HB:351).
- Code blocks and tool output never wrap; horizontal scroll inside the block; multi-line plain output split one text node per line (HB:94).
- Links in prose: body ink + 1 px ink.muted underline; `color.ink.link` only in chrome (HB:94).
- Middle truncation computed into the string from a character budget in the mono slot (U-17).

### 4.4 Space, sizes, radii (MEASURED HB:96 section 6.5; D03:88-104)

- 4 px grid; steps 0, 2, 4, 6, 8, 12, 16, 20, 24, 32, 40, 48. Related controls 8 apart, unrelated groups 16.
- Controls xs 24, sm 28, md 34 (compact 32), lg 36; touch 40; min target 24x24. Control height = text line + two equal paddings (Views rule, D03:95).
- Rows: list 56 (compact 44); palette/launcher 44 (compact 40); rail 30; chips 20 (18); icons 16/18/20; agent marks 22; app header 46.
- Rail contract (exact): width 220, row 196x30, side inset 12, top inset 12, gap 2, row corners 8, content inset 8 h / 6 v, icon slot 16, child spacing 4, collapsed 56 (PROPORTIONS.md:5-16 MEASURED; HB:230). Multiline agent row: 30 + 16 per token line, at most two (HB:192).
- Radii: 6 chips; **8 buttons, inputs, rows**; 12 menus, popovers, toasts, chat surfaces; 16 modals, sheets, **the launcher**; 24 the chat composer only; full for avatars and status dots only. Inner radius = outer minus inset. Never pills (D03:164).
- Launcher outer 16, toast and menu outer 12 on X1 (HB:167); square variant on the board.
- Dialog widths (Views, reference only): 320, 448, 512 (D03:102).

### 4.5 Motion (MEASURED HB:98 section 6.6)

- Durations: fast 120 (hover, press, toggle), base 180 (drawers), slow 240 (sheets out), sheet-in 360; times motion scale Off 0, Fast 0.5, Default 1, Slow 1.75.
- One curve: **cubic-bezier(0.2, 0, 0, 1)**. The desk's sheet curve (0.32, 0.72, 0, 1) is retired.
- Only state changes move; colour changes instant; nothing rotates or scales; dialogs from 641 px wide snap open.
- p.spinner: three 4 px dots, opacity 1.0 / 0.55 / 0.55 stepping every 240 ms by timer, duration 0. Working dot: 1.0 ↔ 0.55 every 600 ms. p.skeleton static. Indeterminate progress moves a clipped bar by left and width. Motion scale 0 holds everything still; the state word carries meaning.
- X1 overlays: no enter motion at all (HB:175); toasts: only the new card fades in by opacity (HB:173).

### 4.6 States, focus, depth (MEASURED HB:100 section 6.7)

- Hover = ink 0.10, selected/pressed = ink 0.16; hover equals the keyboard cursor.
- Selected row: title weight 500. Current item: + 2 px accent leading bar.
- Tints: accent 0.10 Light / 0.13 Dark; primary 0.12 / 0.16; status 0.12 / 0.14.
- Focus ring: 2 px accent, keyboard only; offset +2 on standalone controls, -2 inset on rows; in 0.10.0 "a 2 px accent boxShadow spread, or a reserved 2 px border", driven by application focus state + a last-input-was-keyboard flag.
- Touch press dims to 0.55.
- Resting surfaces: no shadow; depth = tonal step + hairline. Popovers `0 16px 48px` at 0.16 Light / 0.55 Dark + 1 px ring; small dialog `0 2px 8px` 13 percent. **Noir: no shadow at all.** X1 surfaces: no shadow in any theme.

### 4.7 Icons (MEASURED HB:102)

Lucide (ISC), stroke 1.5 (proposed), at 16 and 20 px, monochrome SVG path data taking an ink role,
plus a local icon slot. Run-state glyphs as 16 px monochrome svg with explicit ink (HB:192). Agent
marks: neutral monograms (a letter in a small rounded square), 22 px (HB:9, HB:225). For the private
shell the monogram rule can relax; the BRIEF names "Anthropicons" as the glyph font.

### 4.8 herdr run-state vocabulary (MEASURED HB:182-192; D05:111-126; SD:76)

`AgentStatus` = `idle | working | blocked | done | unknown` (herdr protocol 22, schema MEASURED by D05).

| Value | Glyph | Colour role | Display word | Rule |
|---|---|---|---|---|
| blocked | ◉ | run.blocked (orange: #9A3F00 L / #FBAD60 D,N) | **Needs input** | may notify |
| working | ◐ | run.working (blue: #0051C2 / #70B8FF) | Working | dot pulses 1.0↔0.55 / 600 ms |
| done | ● | run.done (green: #006B00 / #9BE963) | **New activity** | herdr "derives done from an idle row nobody has looked at yet"; `completion_seq` marks it; may notify |
| idle | ✓ | none | Ready | "a ready row draws no state at all" |
| unknown | ○ | none (ink.muted) | Unknown | "never shown as idle"; drawn only with the ○ glyph and the word |

Rules: roll-up order per workspace **blocked, then done, then working, then ready**; default sort with
no query: recent first, then attention (blocked, done, working); "the item you are in is never first";
glyphs in text never animate and never rely on colour; herdr unreachable → rows show "unavailable",
workspace switching still works. Connection states for `a.session-row` (HB:297): live, reconnecting,
disconnected, unavailable; slot states: parked, restorable.

herdr field names a row carries (HB:179-181, D05:103-109):
- Workspace row: `workspace_id`, `number`, `label`, `focused`, `agent_status`, `tab_count`, `pane_count`, `tokens`, `worktree {repo_name, checkout_path}` (full WorkspaceInfo also `active_tab_id`, `worktree.repo_key/repo_root/is_linked_worktree`).
- Agent row: `pane_id`, `workspace_id`, `name`, `display_agent`, `title`, `cwd`, `agent_status`, `state_labels`, `completion_seq` (full AgentInfo also `tab_id`, `terminal_id`, `revision`, `focused`, `agent`, `agent_session`, `terminal_title_stripped`, `foreground_cwd`, `state_change_seq`, `interactive_ready`, `launch_pending`, `tokens`).
- Toast: `title` ≤ 80 chars, `body` ≤ 240, `sound` none | done | request, `position`.
- Metadata: `tokens` (≤ 16 keys `^[A-Za-z0-9_-]{1,32}$`), `ttl_ms` ≤ 86,400,000, `source`, `seq`.
- Events: `workspace_{created,renamed,closed,focused,moved,reordered,updated,metadata_updated}`, `pane_agent_status_changed {pane_id, workspace_id, agent_status, agent, display_agent, title, state_labels}`, `pane_agent_detected`; bootstrap via `session.snapshot` (`herdr api snapshot`); "Event history is not durable".
- Verbs: `workspace.focus`, `workspace.create {cwd, label, focus, env, source_workspace_id}`, `workspace.rename`, `agent.focus`, `pane.focus`, `tab.focus`, `notification.show`, `workspace.report_metadata`, `pane.report_metadata`, `client.window_title.set`.
- Row anatomy already in Tom's herdr config (`config.toml:161-175`): `["state_icon","agent","state_text"]`, then `["$summary"]`, then `["$attempt","$campaign"]`; token lines vanish when unreported (D05:125).

### 4.9 Renderer facts, GPUIX 0.10.0 (MEASURED HB:340-353 section 14; D05:65-80; D02:87-101)

- Host elements: div, text, img, svg, input, textarea, anchored, code, diff, markdown, virtual-list. No canvas, no terminal, no web view.
- Style is a typed object with `hover` and `active` keys only; not CSS; no class cascade; no `focus-visible`, no `outline`, one `boxShadow` per element without inset, no Button/Dialog primitive, no Escape layer stack, Tab not bound by default. **Main 515df19** (72 commits after tag) adds focusVisible, outline with offset, keyboardFocusDim, shadow lists, inset shadows, Button, Dialog, layer stack. Where the option exists, render roots with `keyboardFocusDim: false`.
- Text does not inherit colour: "text with no color paints black". Every text node names an ink.
- No letter-spacing, italic or text-transform. One font family string per text node. text-overflow only ellipsis at end or start.
- Animatable: width, height, top, right, bottom, left, opacity, borderRadius; one bezier per transition; no springs/keyframes; colour instant.
- No element blur or backdrop (vibrancy macOS only). Background at most a two-stop linear gradient. `svg` monochrome, colour required.
- One renderer = one window = one process per surface; share state through herdr or a local adapter.
- `layerShell` options (Linux only): `namespace` (fixed at creation), `layer` background | bottom | top | overlay (default top), `anchor` (default top,left,right), `exclusiveZone`, `exclusiveEdge`, `margin [t,r,b,l]` (exactly four), `keyboardInteractivity` none | on-demand | exclusive (default none); `appId` "Required in practice". **No output selector, no resize, no input region; popups cannot leave their surface.**
- `focus` and `show` ignored on Linux; no Linux headless screenshot; Linux visual checks = compositor capture under runtime-test.
- Fonts 0.10.0 = installed faces by family; `registerFont(bytes)` TTF/OTF lands in 0.11.0 (BRIEF §2); WOFF/WOFF2 never.
- Accessibility: exposes label, description, expanded, selected, level, value string; checked/pressed/current/disabled/invalid travel as words in aria-valuetext or aria-description; live announcements unverified; AT-SPI on layer surfaces unverified; IME in the launcher field unverified.
- No z-index: overlays order by anchored priority then paint order; an overlay needs an opaque fill.
- Required absent verdicts: `a.terminal-frame` (X1 = kitty themed from color.terminal), `a.artifact-frame` (provenance card + Open in browser), `c.chart-frame` and `c.sparkline` (one monochrome svg path per series, else table). `a.top-bar` absent on every head.
- Zoom: in-app only, via one root factor; X1 surfaces exempt.
- Quickshell → GPUIX 1:1 (D02:89-101): PanelWindow+WlrLayershell ↔ layerShell (1:1); `screen`/`Variants` per output ↔ **gap**; `mask` input region ↔ **gap** (size the surface to its rows); `PopupWindow` outside the bar ↔ **gap** (separate processes); `NotificationServer` ↔ `notifications-daemon.ts` on dbus-next (built); `I3` singleton ↔ Sway IPC client to write; `IpcHandler`/`qs ipc call` ↔ CLI + socket (partial today); `WlSessionLock` ↔ out of scope; `screencopy` ↔ not wanted ("fed by events, never by pixels"); `background_effect` blur ↔ not needed; `status_notifier` tray ↔ gap, tray disabled anyway.

### 4.10 Architecture and accessibility constraints the shell inherits (MEASURED HB:359-369)

- Presentation separate from service clients; tokens, behaviour contracts (state machines, keyboard maps, roles, command ids), domain operations and host adapters separately consumable; shared parts import no UI framework; their tests run without a window. (Matches BRIEF §4 "pure-logic *.test.ts".)
- One stable command id per action shared by button, menu, shortcut, launcher row and agent call; every rendered entity carries its id in accessible and test attributes.
- Compositor, notifications, launching and herdr behind host-capability adapters; "components name capabilities, never compositor names". Opening or rendering a view never switches workspaces, attaches or starts work.
- One theme file per skin, emitted once, rendered for every consumer: CSS vars (web), typed literals (GPUIX), flat resolved values per mode (terminal, launcher, notification daemon, compositor borders, herdr).
- WCAG 2.2 AA in all themes and densities: text 4.5:1 (3:1 large), boundaries and focus 3:1, targets 24x24, visible focus never obscured, nothing by colour alone, reduced motion honoured, zoom 200 percent with reflow, keyboard paths for rename/reorder/resize, focus return after every overlay, IME-safe editing.

---

## 5. Reusable code or data, exact paths

All paths MEASURED tonight to exist with the line counts given, unless marked REPORTED.

| What | Path | Reuse |
|---|---|---|
| The surfaces table and its rules | `/home/tom/today/2026-10-17-frank/design-handoff/HANDOFF-B.md:151-175` | copy into `docs/gpuix-shell/SURFACES.md`; code the `layerShell` literals from it |
| Token schema + 10.1 bindings | `HANDOFF-B.md:202-289` | derive `gpuix-shell.json` keys; the Noir column is the shell default |
| Section 6 accepted values | `HANDOFF-B.md:68-104` | type, space, radii, motion, states |
| The 19 rules | `HANDOFF-B.md:110-130` (also `dig/01-shells-overlaps.md:61-96`) | `docs/gpuix-shell/CONSTITUTION.md` U-01..U-19 verbatim |
| herdr fields per record | `dig/05-gpuix-shell-state.md:97-126` and `HANDOFF-B.md:177-192` | `src/herdr/types.ts` |
| Run-state glyph/colour/word table | `HANDOFF-B.md:184-190` | `src/theme/run-state.ts` |
| Rail geometry with C++ provenance | `/home/tom/.wt/hyprland-solid-shell/design/claude-rail/PROPORTIONS.md:5-16` (34 lines) | `layout.rail` literals; the smoke there asserts 220/196/30/12/2/8 |
| Rail web mock (React, three palettes, Ctrl+I) | `/home/tom/.wt/hyprland-solid-shell/design/claude-rail/` (`dist/index.html`, `smoke.mjs`, `screenshots/`) REPORTED by its README | visual reference for the rail; not code to port |
| Previous GPUIX shell: layer-shell launch block | `/home/tom/.wt/hyprland-solid-shell/pkgs/desktop-shell/ui.tsx:1239-1302` (file 1338 lines) | the `render(node, {title, appId, width, height, layerShell:{namespace, layer, anchor, exclusiveZone, keyboardInteractivity, margin}})` shape; toasts sized `toastCount * 148 - 8`, max 4; comment at 1239 on the missing input-region setter. Change: `transparent: false`, margins to [108,0,0,0] and [0,0,96,0], kit sizes |
| Previous shell: theme loader | `/home/tom/.wt/hyprland-solid-shell/pkgs/desktop-shell/theme.ts` (149 lines; roles at 7-25, fonts 26-30, `parsePalette` 52-89, watch + SIGUSR1 reload) | pattern for `~/.config/theme/gpuix-shell.json` watcher; replace its 17 roles with the section 10 keys |
| Previous shell: notifications server | `/home/tom/.wt/hyprland-solid-shell/pkgs/desktop-shell/notifications-daemon.ts` (79 lines) | `org.freedesktop.Notifications` on dbus-next; extend with `sound`, actions, DND, history |
| Previous shell: singleton + modes | `pkgs/desktop-shell/main.ts` (59), `singleton.ts` (73) | one process per surface, repeat-command-closes |
| Previous shell: launcher providers | `pkgs/desktop-shell/providers.ts` (277) | 20 commands + windows/apps/clipboard/files; the five gaps vs Vicinae are listed inside |
| Previous shell: Hyprland controller (to replace) | `pkgs/desktop-shell/controller.ts` (238; 40 ms coalesce, 10 s backoff) | reconnect/stale logic carries over to the Sway IPC client |
| Previous shell: Nix build | `pkgs/desktop-shell/default.nix` (47 lines; buildNpmPackage, nodejs_24, cliphist on PATH at :37 which conflicts with `startup.conf:4`) | the `pkgs/gpuix-shell/default.nix` precedent |
| Sway capability adapter | `/home/tom/.wt/hyprland-solid-shell/design/gpuix-comparison/platform.ts` (54 lines; `DesktopCapabilities {snapshot(); focusWorkspace(selection)}`, eDP-1 only, 26 mocked tests REPORTED) | seed of `src/sway/adapter.ts`; add workspace move/rename/park/restore |
| Theme fragment generators | `/home/tom/mecattaf/dotfiles/home/themes/default.nix:19` kitty, `:115` sway, `:127` mako, `:140` vicinae, `:224` meta, `render = t:` at `:281-290` | add `"gpuix-shell.json" = gpuixShell t;` to `render`; the worktree precedent is `desktop-shell.json` at `/home/tom/.wt/hyprland-solid-shell/home/themes/default.nix:294` (REPORTED D02:65) |
| Palette sources | `/home/tom/mecattaf/dotfiles/home/themes/{noir,claude-dark,claude-light}.nix` (noir keys at lines 10-55) | the section 5 rows map 1:1 onto these keys |
| Vicinae look today | `/home/tom/mecattaf/dotfiles/home/vicinae.nix:35-54` (font 12, `material = "none"`, `rounding = 0`, `shadow_size = 0`), Chrome native host at `:98-99`, Mako at `:111-166` (font "Anthropic Sans 11", `makoctl dismiss/restore` binds) | the floor the launcher must match; the Chrome-tab bridge to replace |
| herdr-web-ui rail tokens | `/home/tom/mecattaf/herdr-web-ui/src/styles.css:141-151` (`--ui-scale`, 11..22 px ladder), `:175-180` radii 6/8/12/16/24/pill, `:199-203` `--siderail-w 220px / -row 30px / -inset 12px / -gap 2px / -radius 8px`, `:221-222` `--ring: 2px solid var(--accent); --ring-offset: 2px`, `:227-243` `--motion-scale`, `--dur-base 180ms`, `--ease-out cubic-bezier(0.2,0,0,1)`, `--dur-sheet 360ms`, `--dur-sheet-out 240ms`; compact ladder at `:989-997` | the same numbers as the kit, proof the web head already matches; `DESIGN.md` for the roster row |
| Old OSD script | `/home/tom/mecattaf/dotfiles/home/dot_local/bin/osd` (REPORTED D05:49: `notify-send -r`, `value` hint) | keep the callers (`volume`, `brightness`, `touchpad-toggle`); point them at `gpuix-shell osd` |
| Mod+i switcher (fuzzel) | branch `/home/tom/.wt/dotfiles/morning-shell` (PR #565, `sway-workspace-switcher --output eDP-1`, tests/workspace-switcher) | behaviour and tests to port; fuzzel stays as the interim with `--output` |
| herdr attention → urgency | branch `/home/tom/.wt/dotfiles/herdr-sway-context` (`herdr-attention`, 442 lines, 69 tests) | logic for the notification daemon's attention path |
| Fixtures for a demo/test rail | `HANDOFF-B.md:328` (slots 1..7 with states incl. unknown and parked; agents with monograms C/W/A) | `tests/gpuix-shell/fixtures/rail.json` |
| Operator defaults list | `/home/tom/today/2026-10-17-frank/design-handoff/OPERATOR-CARD.md:45-62` | the morning rulings list for MORNING.md |
| Quickshell I3 module (Sway IPC template) | `gh api repos/quickshell-mirror/quickshell/contents/src/x11/i3` (REPORTED D02:37; LGPL, read-only) | shape only: `$SWAYSOCK`, `get_workspaces/get_tree/get_outputs`, subscribe `workspace`, `window`, `output`, `run_command` |

---

## 6. Gaps and unknowns, with the default already taken

Each row: the open point, who flagged it, the default the handoff (or I) took so builders do not wait.

| # | Open point | Source | Default for tonight |
|---|---|---|---|
| 1 | **Theme source of truth**: kit DTCG canonical emitting per-program files (reverses dotfiles' direction) vs `home/themes/*.nix` canonical | SD:84 Unknown 1 (P-15) | Dotfiles stay canonical tonight (BRIEF §1): `home/themes/default.nix` emits `gpuix-shell.json` with the section 10 key names, so a later kit export is a rename-free swap |
| 2 | **Rail default width** 220 vs 56 (BRIEF §3.3 vs HB:155) | INFERRED here, section 3.1 | Start at 220; `--collapsed` launch at 56; both are separate launches, never animated |
| 3 | **Does 220 fit eDP-1?** logical width INFERRED ~1440x900 | D05:149 | Assume it fits; measure `swaymsg -t get_outputs` under runtime-test |
| 4 | **Placing layer surfaces on eDP-1**: no output selector in 0.10.0 (and not reported for 0.11.0) | SD:90, D05:147, D02:92 | Launch rule: start the rail/switcher process with the top display focused; interim fuzzel for the switcher has `--output`; a small gpuix patch passing `wl_output` later. Re-check `index.d.ts` at 0.11.0 for an output key before writing the patch |
| 5 | **Who owns `org.freedesktop.Notifications` and clipboard on the seat** | SD:89, D05:145-146 | Mako and Vicinae until the gpuix daemon/launcher pass checks under runtime-test; never both; a single HM switch (`programs.gpuixShell.enable` vs vicinae/mako, BRIEF §2) |
| 6 | **Outer corners on Sway**: square (every current Linux surface is square: Vicinae rounding 0, Mako radius 0) vs the kit's same-outer-radii | SD:88, D02:137-138, VF:17 | Rounded: launcher 16, toast/menu 12; square variant on the X1 board for Tom |
| 7 | **App bar / dock** (board option (b)) | SD:85, D01:140 | Not built; only if launcher + rail footer prove short |
| 8 | **Task strip** (board option (d)) | VF:52, OPERATOR-CARD:59 | Not drawn by default; zone 0 if drawn |
| 9 | **Rail as the chat window's own left bar** (option (c)) vs a separate rail surface | SD:91 Unknown 8 | Separate rail surface; apps check capability `shell.rail` and draw no workspace sidebar |
| 10 | **Run-state display words** | SD:86 (I-4) | herdr's five values; "blocked" displays "Needs input", "done" displays "New activity" |
| 11 | **Is the rail hidden under Mod+f fullscreen?** | D05:148 | INFERRED yes (layer top under fullscreen, overlay above); measure under runtime-test |
| 12 | **AT-SPI on layer surfaces; IME in the launcher field; live announcements** | HB:350, VF:96 | Unverified; mark in RENDERERS; do not block |
| 13 | **GPUIX version**: kit designed to 0.10.0 + main 515df19; BRIEF pins **0.11.0** | VF:169, HB:353, BRIEF §3.1 | Re-read `/home/tom/Downloads/gpuix/packages/native/index.d.ts` and CHANGELOG at 0.11.0 for: focusVisible, outline, keyboardFocusDim, inset shadow, layer stack, any output key. Use what shipped; list the rest as next |
| 14 | **Font sizes for the shell**: kit 13 chrome vs BRIEF "Anthropic Sans 12 UI" vs Vicinae 12 vs Mako 11 | INFERRED here | Row titles 13/18 (kit); meta and figures 12; nothing under 11; record in ASSUMPTIONS.md |
| 15 | **Font family for mono**: DS used "Anthropic Mono"; installed name is "AnthropicMono Nerd Font" | BRIEF §2 vs `theme.ts:26-30` | Use the BRIEF's family names |
| 16 | **Lock screen** | D02:152 | Not drawn; if ever, `ext-session-lock` |
| 17 | **Hot reload of code in gpuix** | D02:159 | None; theme reload via file watch (and SIGUSR1 as DS did); code rebuilds via Nix/bun |
| 18 | **Kit naming ban** ("Claude"/"Anthropic" in no token, file, id) | HB:198-200 | Applies to the public kit only; the private shell names its fonts; keep token keys brand-free anyway so the kit export stays 1:1 |
| 19 | **Launcher margin**: kit 108 top (12 percent of 900) vs DS `[40,12,0,0]` anchored top-right | HB:158,163 vs `ui.tsx:1296-1301` | Kit wins: anchor top only (centred), margin computed as 12 percent of output height |
| 20 | **Toast pitch**: kit fixed 140 px card vs DS `toastCount * 148 - 8` (140 card + 8 gap) | HB:173 vs `ui.tsx:1273` | Same thing: 140 card, 8 gap, surface height `n*148 - 8`; reopen on count change |
| 21 | **Quick controls surface** | HB:161 | Optional; not on the critical path; scripts + OSD first |
| 22 | **Strip content order** | D05:151 | herdr agents, then Projects "Waiting on you", then substrate runs |
| 23 | **Chrome tab source for the launcher** | D02:23 (Tom), `vicinae.nix:98-99` | Vicinae's native-messaging host goes away with Vicinae; needs its own bridge (Chrome DevTools protocol or a tiny extension). Unverified; log as a follow-up |
| 24 | **Live seat state** never measured (Zenbook off limits) | D05:152 | Owners come from config on main |

What I did not verify: I did not run anything; every "exists" claim about code paths is an `ls`/`wc`/
`sed` read on the strix filesystem tonight. I did not open `HANDOFF-A.md` (identical to B except two
lines, VF:9), `dig/04`, `dig/06-08`, nor the Quickshell or gpuix trees. The contrast ratios are the
finalizer's, not re-measured by me.
