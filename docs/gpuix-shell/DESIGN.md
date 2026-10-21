# gpuix-shell DESIGN — visual and interaction spec

Synthesis for the overnight gpuix-shell build, 2026-10-20/21. Revision 2 (2026-10-21, after the 12:00
note revisions). Written from BRIEF.md and every wave-1 note (`wave1/01` … `wave1/36`, including the
revised 15, 18, 19, 24 and 26 and the packaging note 21). Nothing here was tested on a compositor except
the rail probe in BRIEF (56 px exclusive zone, workspace rect x=56 width=1384 on a 1440 panel) and the
Nix-built rail smoke that repeated it [w1-21 §5.9 #8].

**Labels.** `[w1-NN]` cites the wave-1 note that grounds a value. `[BRIEF]` cites BRIEF.md. **INFERRED**
marks a value I chose to fill a gap; every INFERRED decision that changes what gets built is also one line
in `ASSUMPTIONS.md` (prefix `DESIGN.md:`), indexed in §11. **MEASURED** means a first-party number from
Tom's hardware, a config file on the branch, or a probe that ran.

**Units.** Every number is a logical pixel on the Zenbook Duo client: eDP-1 1440×900 logical at (0,0),
scale 2, workspaces 1–9; eDP-2 1440×900 at (0,900), workspace 10 (Chrome) [BRIEF, w1-07 §3 #16, w1-09
§3a MEASURED]. GPUIX takes literal values; nothing in this document is a CSS expression [w1-14, w1-15].

**Scope of this file.** Colour, type, space, motion and the pixel geometry of each surface. Process
topology, IPC and data sources belong to ARCHITECTURE.md; keys to KEYS.md; the boundary to BOUNDARY.md.

---

## 1. The nineteen rules

Restated from the design kit's HANDOFF-B, with the P-corrections folded in [w1-11 §2.2, §2.3]. These bind
every surface below; a surface section only adds geometry.

| # | Rule | What it means in gpuix-shell |
|---|---|---|
| U-01 | **Colour is spent on meaning.** | Neutral chrome. Accent appears only where the keyboard cursor sits and on what Enter would do. Clay (brand) is the mark, never a button fill on the shell (P-04). Status colours are reserved for the five run states and the five status families. |
| U-02 | **Contrast where it sits.** | Text ≥ 4.5:1 against its own ground, indicators ≥ 3:1. Checked per theme in §2.3; clay text on the light ground is 2.96:1 and therefore never drawn [w1-05 §4]. |
| U-03 | **State is a field, a word and a mark.** | An agent's run state is one of five values, carried as a dot (colour), a glyph (◉ ◐ ● ✓ ○) and a word (Needs input / Working / New activity / Ready / Unknown). Unknown is drawn as unknown, never hidden. State never takes focus. |
| U-04 | **Authority and condition.** | Every surface has drawn forms for loading, empty, no results, partial, stale, disconnected, denied and failed. A surface that cannot read herdr says so in a row; it never fakes a state. Facts come from host adapters, never from a model's guess [w1-24 rev2]. |
| U-05 | **Flat and opaque.** | Tonal steps parted by hairlines. No blur, no frost, no gradient, no shadow at rest; overlays carry one 1 px `line.strong` edge instead of a shadow, in every theme (P-06). Every drawn pixel is opaque; a window is `transparent` only so that the corners of a rounded overlay can be cut (MEASURED working on Sway [w1-15 P7]), never for a translucent look (A-32). |
| U-06 | **Three voices, one root.** | One UI family (Anthropic Sans) at 12 chrome / 13 row / 14 body / 16 input; mono figures (AnthropicMono Nerd Font) for times, counts, ids; Serif only inside prose replies. Floor 11. No letter-spacing (P-13; GPUIX has none anyway). |
| U-07 | **One grid.** | 4 px grid. Short ladders. Rail exception 220/30/12/2/8. Concentric corners (inner = outer − inset). Minimum target 24 px, 40 px for pointer-first controls. |
| U-08 | **Motion only for change.** | Animate width/height/top/left/opacity/radius only. One curve, one short ladder, `motion.scale` ∈ {1, 0}. No springs, no overshoot, no colour fades (colour changes instantly). |
| U-09 | **Looking is free, acting is declared and echoed.** | Opening any surface changes nothing. Every action names itself (verb + noun) and echoes (OSD, toast or inline word) when it lands. The rail reads herdr and writes only to Sway [w1-07 §2.2, w1-09 §6 #4]. |
| U-10 | **One registry drivable at equivalence.** | A rail item, a launcher command and a CLI verb are the same registry entry drawn through three lenses; a human key, a pointer click and an agent call hit the same handler [w1-08 §2.5, w1-09 §3 #25]. |
| U-11 | **One focus model, one layer stack.** | Hover and keyboard cursor are the same row state. A 2 px accent ring appears only for keyboard focus. Escape closes the top layer only. Layer order: rail (top) < toasts/OSD (overlay) < launcher/switcher/controls/power (overlay, exclusive keyboard). |
| U-12 | **Stable under change.** | Rows keep their slot while state changes; nothing reflows under the cursor. The rail's nine slots never move. Toasts enter at the top of the stack (mako habit, A-36); the stack has no keyboard cursor, so the rule holds. |
| U-13 | **One row grammar.** | Leading cell · title (· subtitle) · trailing state · trailing action. Selected, current and focused coexist and are drawn differently (§7.1). |
| U-14 | **One object, many lenses.** | A workspace is the same row in the rail, the switcher, the launcher and a toast. A notification is the same card in the stack and the centre. 390 px is the narrowest lens. |
| U-15 | **The platform owns the frame.** | Sway places windows; the shell draws only its own layer surfaces. No title bars, no shadows, no client decorations are drawn by us. The file chooser stays the GNOME portal's Nautilus [w1-09 §2a T2]. |
| U-16 | **Agent work has one grammar.** | Status glyph, workspace name, age, and an attention count: the same four cells wherever an agent appears. |
| U-17 | **Words.** | Sentence case. Verb and noun ("Connect to Freebox", "Close workspace 3"). Relative times under a day ("4 m", "2 h"), clock times after. Ids middle-truncated in a mono slot. One dash "–" for unknown figures. Uppercase is typed into the string (P-13). |
| U-18 | **Identity is a skin over one theme file.** | Every colour, size and duration comes from `gpuix-shell.json`. Roles, never values, in components. sRGB literals in the fragment. No cascade, no calc, no colour-mix at runtime. |
| U-19 | **A gallery per renderer.** | `gpuix-shell gallery` renders every token and component in the running theme; it is the visual test and the OpenUI coverage test. |

Corrections already folded in [w1-11 §2.3]: no top bar (P-01); no app menu (P-02); Mod+i stays the
switcher (P-03); no clay on the active rail row, current uses accent (P-04); mono `figures` role for
times and counts (P-05); no shadows at rest, noir never (P-06); one easing curve (P-07); tracking 0
(P-08); notifications are toasts plus a daemon (P-09); quick controls echo through the OSD, the keys keep
their scripts (P-10); clipboard, OSD and strip added as surfaces (P-11, strip not drawn); run state bound
to herdr's five values (P-12); 390 px sizes restored (P-16).

### 1.1 Tom's own settings against the kit: how each tension is resolved

The kit (10-17) and BRIEF carry defaults an agent took; Tom's own config commits and rulings are first
person. Where they disagree, the newer first-person word wins, and the loser stays reachable by one
token [w1-18 §conflicts, w1-19 stance table, w1-21 §6 #17].

| Tension | Tom's own word or setting | Kit / BRIEF default | Resolution in this file |
|---|---|---|---|
| Toast anchor | mako "top and center not top right" (2026-10-11) [w1-05 §4, w1-06 §2.4, w1-18] | top-right 390 wide [BRIEF §3.3] | **top-centre** by default; `layout.toast.anchor` switches to top-right (A-15) |
| Corners | mako `border-radius 0`, Vicinae 0 (Tom's 2024-11 settings) [w1-18] | kit 12/16; Tacit 8–18 [w1-20] | **rounded** (12 outer / 8 row) because the 10-20 order names Tacit's look, the newest word; square = `radius.outer 0` in the fragment (A-30) |
| Launcher text size | Vicinae font "12 or 14, start at 12" (pt ≈ 16 px) (2026-10-12) [w1-04 §2.2 R9, w1-09 §2c] | kit row 13 [w1-11] | launcher input **16**, launcher row title **14**; other surfaces keep 12/13/14 (A-29) |
| Toast timeouts | mako: low/normal 5000 ms, critical persists, explicit `-t` wins [w1-18] | 3000/5000 [prior DESIGN rev1] | low 5000 · normal 5000 · critical never; a client's `expire_timeout` ≥ 0 always wins (A-35) |
| Toast stacking | mako newest on top [w1-18] | kit "new toasts enter below" | newest on top (A-36) |
| Control centre | "no control center" (March WONT) [w1-29 G1] | BRIEF `controls` surface | per-domain **list menus**, never a tile grid (A-20) |
| Function row | "keypress > sway > script, no need to tie in vicinae" (2026-10-13) [w1-05 §2.3] | — | keys keep their scripts; the shell draws only the echo (P-10) |
| OSD contract | `osd` script: `notify-send -p -r <id> -a osd -h int:value:<pct>`, 1500 ms [w1-07 §3 #12, w1-18] | `gpuix-shell osd show` | the daemon routes `app_name == "osd"` to the OSD surface unchanged; the CLI verb is a second door (A-33) |
| Sleep | "not implementing real sleep … very minimalistic" (2026-10-20) [w1-07 §2.2] | — | no Suspend row by default (A-23) |
| File chooser | "the only thing we can retain from before is the nautilus file picker" (2026-10-20) [w1-09 §2a T2] | — | the explorer is a browser, never an open/save dialog (A-37) |
| Bottom dock | "utilities like email etc can go below" is the **macOS** tab bar (2026-10-14) [w1-05 §2.2 L325, w1-06 G1] | BRIEF: no dock | not drawn on the Linux head; utilities are launcher rows (A-38) |
| Rail width | 220 only in every 10-14 source [w1-06 §4.1] | 56 collapsed [BRIEF] | 56 is MEASURED by the probe and kept as the boot width (A-08) |

---

## 2. Tokens: the `gpuix-shell.json` fragment

### 2.1 Contract

- One file per theme, rendered by `home/themes/default.nix` as `"gpuix-shell.json" = gpuixShell t;`
  beside the Vicinae fragment it replaces (`themes/default.nix:140-177` is the template) [w1-17 §3,
  w1-07 §3 #18].
- The shell reads `~/.config/theme/gpuix-shell.json` and re-reads it when the `~/.config/theme` symlink
  changes [BRIEF §3.5, w1-17]. The `theme` script retargets the symlink; no inotify event reaches the
  target files, so the watcher sits on `~/.config` and the CLI also offers `gpuix-shell theme reload`
  [w1-03 §3.1 theme follow, w1-26]. Switching is manual (`theme <name>`); noir is the default.
- The fragment is the **resolved, flat semantic layer**: every key is a literal GPUIX accepts
  (`#RRGGBB`, `#RRGGBBAA`, number, string). No references between keys, no alpha math at runtime
  [w1-11 §4.2, w1-14]. Pre-blended values are given where the kit used alpha over a known ground.
- Header key `"_generated"` carries the theme name, polarity and the generator path, as the other
  fragments do [w1-17].
- Keys are grouped by dot-separated names; the JSON is nested by group (`color.surface.base` →
  `color: { surface: { base } }`). Components import a typed `Theme` object and never a hex.
- Values that cannot be derived from the theme roles (noir's raised `#101111`, the light-theme primary
  fill `#A74B2F`, the Primer dots) are carried as per-theme literals inside `gpuixShell` in Nix, keyed by
  theme name. INFERRED (A-01).
- The three rendered fragments are checked by `checks.gpuix-shell-themes`, which runs
  `gpuix-shell --check-theme <fragment>` through the shell's own loader, so a renamed role fails in
  `nix flake check`, not on the seat [w1-21 §5.3c, §5.10].

### 2.2 Source palettes (from `home/themes/*.nix`, MEASURED tonight)

| Role | noir | claude-dark | claude-light |
|---|---|---|---|
| ground.base | `#000000` | `#1A1A1A` | `#F9F9F7` |
| ground.dim | `#000000` | `#151515` | `#F3F3F0` |
| ground.raised | `#000000` | `#20201F` | `#FFFFFF` |
| ground.desktop | `#000000` | `#20201F` | `#F0EFEC` |
| fg | `#EAECF0` | `#EAECF0` | `#131313` |
| fgDim | `#D3D7DE` | `#D3D7DE` | `#52514E` |
| comment | `#818898` | `#818898` | `#6E7687` |
| muted | `#45475a` | `#52514E` | `#A5A49A` |
| accent | `#70B8FF` | `#70B8FF` | `#0051C2` |
| brand (clay) | `#D97757` | `#D97757` | `#D97757` |
| red | `#F47B85` | `#F47B85` | `#B80A18` |
| green | `#9BE963` | `#9BE963` | `#008000` |
| yellow | `#f9e2af` | `#f9e2af` | `#A66A00` |
| orange | `#FBAD60` | `#FBAD60` | `#B24A00` |
| magenta | `#CC7BF4` | `#CC7BF4` | `#8100C2` |
| cyan | `#5EEDED` | `#5EEDED` | `#007F80` |
| blue | `#70B8FF` | `#70B8FF` | `#0051C2` |
| selection.bg / fg | `#264F78` / `#EAECF0` | `#264F78` / `#EAECF0` | `#CDE2FB` / `#131313` |
| border.active / inactive / urgent | `#555451` / `#373735` / `#F47B85` | `#555451` / `#373735` / `#F47B85` | `#A5A49A` / `#D2D1C7` / `#B80A18` |
| cursor | `#EAECF0` | `#EAECF0` | `#131313` |

Noir shares the Claude Dark inks over `#000000` grounds [w1-17 §3.5, w1-25 §4.4]. The same roles exist
in the kit's `palettes.json` (brand renamed `warm`) and were compared field by field for noir
[w1-06 §4.3]. The sway fragment already spends `border.active`, `ground.base`, `fg`, `red` and
`selection.bg`; mako spent `ground.raised`, `fg`, `border.active/inactive`, `red` and `selection.bg`
[w1-07 §4], so every colour below has a precedent on the seat.

### 2.3 Colour tokens, resolved per theme

Derivations follow the kit [w1-11 §4.1] and herdr-web-ui's palette [w1-25 §4]; the role mapping
(`canvas`, `surface`, `ink`, `muted`, `border`, `primary`, `hover`) matches the kit's `theme.ts`
derivations [w1-06 §4.3]. Alpha hex is written `#RRGGBBAA`; the line family keeps alpha because it sits
over three different grounds, everything else is opaque.

**Surfaces** (`color.surface.*`)

| key | noir | claude-dark | claude-light | role |
|---|---|---|---|---|
| canvas | `#000000` | `#1A1A1A` | `#F9F9F7` | ground.base; terminal/editor ground, never drawn by the shell |
| base | `#000000` | `#20201F` | `#F0EFEC` | panels: rail, controls, notification centre |
| raised | `#101111` | `#262625` | `#FFFFFF` | overlays: launcher, switcher, toasts, OSD, power, modals (noir = black lifted 7 % toward ink) |
| sunken | `#000000` | `#151515` | `#F3F3F0` | wells inside a panel (file list ground, section wells) |
| overlay | `#101111` | `#262625` | `#FFFFFF` | alias of raised; X1 overlays are always raised + 1 px line.strong, no scrim |
| desktop | `#000000` | `#20201F` | `#F0EFEC` | reserved; the wallpaper is solid `#000000` in every theme [BRIEF, w1-07 §4] |
| input | `#000000` | `#1A1A1A` | `#FFFFFF` | text fields; always with a line.strong edge |
| inverse | `#EAECF0` | `#EAECF0` | `#131313` | tooltips are not drawn; reserved for key caps on hover (unused tonight) |

**Inks** (`color.ink.*`)

| key | noir | claude-dark | claude-light | contrast on raised |
|---|---|---|---|---|
| strong | `#EAECF0` | `#EAECF0` | `#131313` | 17.3 / 13.5 / 17.4 |
| default | `#D3D7DE` | `#D3D7DE` | `#131313` | 14.1 / 11.0 / 17.4 |
| muted | `#818898` | `#818898` | `#52514E` | 5.6 / 4.4 (use ≥ 13 px) / 7.3 |
| subtle | `#818898` | `#8F96A5` | `#6E7687` | alias family for meta text; 4.8 on light |
| disabled | `#45475a` | `#52514E` | `#A5A49A` | below 3:1 by design; never carries information alone |
| inverse | `#000000` | `#1A1A1A` | `#F9F9F7` | ink on inverse surface |
| on-brand | `#131313` | `#131313` | `#FFFFFF` | ink on the primary fill |
| on-accent | `#131313` | `#131313` | `#FFFFFF` | ink on an accent fill (progress caps, selected key caps) |
| link | `#70B8FF` | `#70B8FF` | `#0051C2` | accent |

The three-level hierarchy strong / default / muted is the one claude.ai's own palette uses
(`#f0efec` / `#c3c2b7` / `#898781` measured from Tom's screenshot) [w1-09 §4a]; the values here come
from the theme files, the screenshot only confirms the number of levels.

**Lines** (`color.line.*`; ink `#DEDCD1` on dark and noir, `#1F1E1D` on light [w1-11 §4.1])

| key | noir | claude-dark | claude-light | use |
|---|---|---|---|---|
| hairline | `#DEDCD126` (0.15) | `#DEDCD126` | `#1F1E1D26` | dividers between rows and sections |
| default | `#DEDCD14D` (0.30) | `#DEDCD14D` | `#1F1E1D4D` | panel edges, key caps |
| strong | `#DEDCD170` (0.44) | `#DEDCD16B` (0.42) | `#1F1E1D80` (0.50) | inputs, overlay edges; ≥ 3:1 against its ground |
| focus | `#70B8FF` | `#70B8FF` | `#0051C2` | 2 px keyboard ring |
| urgent | `#F47B85` | `#F47B85` | `#B80A18` | border.urgent: critical toast edge, urgent rail row |

**Brand and accent**

| key | noir | claude-dark | claude-light | use |
|---|---|---|---|---|
| brand.mark | `#D97757` | `#D97757` | `#D97757` | the clay mark only (ask header, gallery); never text on light |
| brand.default | `#D97757` | `#D97757` | `#A74B2F` | primary fill (Enter's button in modals; `theme` row swatch) |
| brand.emphasis | `#E58B6D` | `#E58B6D` | `#913E27` | primary fill hover/pressed |
| brand.muted | `#D9775729` (0.16) | `#D9775729` | `#A74B2F1F` (0.12) | primary tint (ask "thinking" field) |
| accent.default | `#70B8FF` | `#70B8FF` | `#0051C2` | current marker, focus ring, value bars, key cap text when armed; this is the "Vicinae blue" Tom asked mako to use [w1-04 §2.2 R9, w1-06 §2.4] |
| accent.emphasis | `#8CC6FF` | `#8CC6FF` | `#003F99` | accent hover (links only) |
| accent.muted | `#70B8FF21` (0.13) | `#70B8FF21` | `#0051C21A` (0.10) | accent tint behind the current rail row's leading bar cell |

**Status families** (`color.status.<family>.{fg,bg,line,emphasis}`; bg is fg at 0.14 on dark/noir and
0.12 on light [w1-11 §4.1]; line = fg; emphasis = fg used as fill with on-accent ink)

| family | noir / claude-dark fg | claude-light fg | bg dark · light | where |
|---|---|---|---|---|
| danger | `#F47B85` | `#B80A18` | `#F47B8524` · `#B80A181F` | failed, denied, critical, destructive hold fill |
| warning | `#FBAD60` | `#B24A00` | `#FBAD6024` · `#B24A001F` | stale, partial, battery low, needs input |
| success | `#9BE963` | `#008000` | `#9BE96324` · `#0080001F` | done, connected, paired |
| info | `#70B8FF` | `#0051C2` | `#70B8FF24` · `#0051C21F` | working, progress, informational toast |
| neutral | `#818898` | `#52514E` | `#81889824` · `#52514E1F` | idle, unknown, disconnected-but-fine |

The theme's `yellow` role is not spent anywhere in the shell; it stays available for terminals.

**Run states** (`color.run.*`; the five herdr values, used on every surface except the rail and switcher
dots [w1-11 §4.1, w1-16]; the kit's `stateIdle/Working/Blocked/Done` are the same mapping [w1-06 §4.3])

| key | noir / claude-dark | claude-light | glyph | word |
|---|---|---|---|---|
| blocked | `#FBAD60` | `#9A3F00` | ◉ | Needs input |
| working | `#70B8FF` | `#0051C2` | ◐ | Working |
| done | `#9BE963` | `#006B00` | ● | New activity |
| idle | `#818898` | `#52514E` | ✓ | Ready |
| unknown | `#818898` | `#52514E` | ○ | Unknown |

herdr's `AgentStatus` is open-ended (`string & {}`); any other value is drawn as unknown and logged, never
narrowed [w1-06 §4.4, w1-16].

**Rail dots** (`color.dot.*`; herdr-web-ui's Primer dots, which Tom called "my primitives"
[w1-25 §4.3]; used by the rail and the switcher only, A-02)

| key | noir / claude-dark | claude-light | maps to run |
|---|---|---|---|
| waiting | `#D29922` | `#9A6700` | blocked |
| error | `#F85149` | `#CF222E` | failed/denied toast on a workspace row |
| working | `#70B8FF` | `#0051C2` | working |
| done | `#3FB950` | `#1A7F37` | done |

**Selection, state, scrim**

| key | noir | claude-dark | claude-light | note |
|---|---|---|---|---|
| selection.bg | `#264F78` | `#264F78` | `#CDE2FB` | text selection inside inputs; value-bar fill on toasts (mako's progress colour [w1-07 §4]) |
| selection.fg | `#EAECF0` | `#EAECF0` | `#131313` | |
| state.hover | `#161615` | `#2E2D2C` | `#E3E3E1` | pre-blended ink at 0.10 over base; also the keyboard cursor row |
| state.selected | `#242321` | `#393937` | `#D6D6D4` | pre-blended ink at 0.16; the chosen row |
| state.pressed | `#242321` | `#393937` | `#D6D6D4` | same as selected; no third step |
| state.disabled | `#45475a` | `#52514E` | `#A5A49A` | ink for disabled text and glyphs |
| scrim | `#000000B3` | `#00000099` | `#13131359` | defined, never drawn on X1 (P-06) |

Noir's hover in the kit was a translucent border tint (`border + '55'`); here it is pre-blended because
the ground is known and alpha paint is unverified on the toasts path [w1-06 §4.3, w1-03 §3.2 L12].

### 2.4 Non-colour tokens (identical in the three themes)

```jsonc
"font": {
  "ui":      "Anthropic Sans",
  "prose":   "Anthropic Serif",
  "mono":    "AnthropicMono Nerd Font",      // the installed family per fc-match; "Anthropic Mono" is wrong [w1-03 L7, w1-06 G6]
  "glyph":   "AnthropicMono Nerd Font",      // ◉◐●✓○ and nerd glyphs; one family per text node
  "weight":  { "regular": 400, "medium": 500, "semibold": 600 }
},
"type": {                                   // size / lineHeight / weight / family
  "caption": { "size": 11, "lineHeight": 16, "weight": 400, "family": "ui" },
  "meta":    { "size": 12, "lineHeight": 18, "weight": 400, "family": "ui" },
  "chrome":  { "size": 12, "lineHeight": 18, "weight": 500, "family": "ui" },
  "row":     { "size": 13, "lineHeight": 20, "weight": 400, "family": "ui" },
  "body":    { "size": 14, "lineHeight": 21, "weight": 400, "family": "ui" },
  "input":   { "size": 16, "lineHeight": 22, "weight": 400, "family": "ui" },   // launcher/ask/switcher text field (A-29)
  "title":   { "size": 16, "lineHeight": 20, "weight": 600, "family": "ui" },
  "display": { "size": 20, "lineHeight": 24, "weight": 600, "family": "ui" },
  "prose":   { "size": 15, "lineHeight": 25, "weight": 400, "family": "prose" },
  "figures": { "size": 12, "lineHeight": 18, "weight": 400, "family": "mono" },
  "figures-sm": { "size": 11, "lineHeight": 16, "weight": 400, "family": "mono" },
  "code":    { "size": 13, "lineHeight": 21, "weight": 400, "family": "mono" }
},
"space":  { "0": 0, "1": 2, "2": 4, "3": 6, "4": 8, "5": 12, "6": 16, "7": 20, "8": 24, "9": 32, "10": 40, "11": 48 },
"size": {
  "control": { "xs": 24, "sm": 28, "md": 34, "lg": 40 },
  "icon":    { "sm": 16, "md": 18, "lg": 20 },
  "target":  { "min": 24, "pointer": 40 },
  "row":     { "rail": 30, "launcher": 44, "list": 40, "dense": 34, "card": 56 },
  "chip": 20, "mark": 22, "dot": 8, "ring": 2, "keycap": 18, "header": 46, "footer": 36, "bar": 3
},
"radius": { "none": 0, "xs": 4, "sm": 6, "md": 8, "lg": 12, "xl": 16, "full": 999,
            "row": 8, "outer": 12 },        // row/outer are the two the surfaces read; outer 0 = Tom's square mako/Vicinae look (A-30)
"motion": {
  "duration": { "instant": 0, "fast": 120, "base": 180, "slow": 240 },
  "easing":   [0.2, 0, 0, 1],
  "scale":    1,                            // 0 disables all motion; durations multiply by this
  "pulse":    { "period": 600, "low": 0.55 }
},
"layout": {
  "rail":     { "collapsed": 56, "expanded": 220, "boot": "collapsed", "row": 30, "inset": 12, "gap": 2, "radius": 8,
                "rowWidth": 196, "cell": 32, "leading": 34, "trailing": 20, "footerRow": 24 },
  "launcher": { "width": 700, "height": 580, "top": 108, "input": 48, "row": 44, "section": 30, "footer": 36 },
  "switcher": { "width": 560, "top": 108, "row": 44 },
  "toast":    { "width": 390, "cardMin": 72, "cardMax": 140, "gap": 8, "max": 4, "margin": 12,
                "anchor": "top-center",                     // or "top-right" (A-15)
                "timeout": { "low": 5000, "normal": 5000, "critical": 0 } },   // 0 = never (A-35)
  "center":   { "width": 500, "height": 650 },
  "osd":      { "width": 280, "height": 56, "bottom": 96, "hold": 1500 },
  "controls": { "width": 420, "maxHeight": 640, "row": 40, "margin": 12 },
  "power":    { "width": 360, "row": 44, "hold": 1500 },
  "files":    { "width": 1000, "height": 640, "minWidth": 640, "minHeight": 400, "rail": 248, "railCompact": 60,
                "preview": 300, "previewAt": 1240, "row": 34, "rowOrigin": 48, "gridCell": [156, 176] },
  "ask":      { "width": 700, "height": 580, "top": 108 },
  "zoom":     { "min": 0.8, "max": 1.6, "step": 0.1 }     // ordinary windows only (files, ask when windowed) (A-39)
},
"focus": { "width": 2, "offsetControl": 2, "offsetRow": -2 }
```

Grounding: type ladder from the kit [w1-11 §4.2, w1-05 §4 "11, 12, 13, 14, 15, 16, 18, 22"], trimmed to
the sizes the order fixes (12/13/14/20) [BRIEF §3.6] plus the 16 px input that Tom's "Vicinae font 12"
(points) resolves to (A-29); space ladder and control sizes [w1-11 §4.2]; radii 8 controls / 12 menus
and cards [BRIEF §3.6]; motion durations and the single curve from herdr-web-ui `--dur-fast 120 /
--dur-base 180 / --ease-out (0.2,0,0,1)` [w1-25 §4.5]; rail metrics 220/30/12/2/8 [w1-25 §3, w1-06 §4.1
with the C++ lines, BRIEF]; launcher 700×580 and toast 390/4 [BRIEF §3.3]; OSD margin 96 [BRIEF §3.3];
OSD hold 1500 and the mako timeouts from the live config [w1-07 §4, w1-18]; zoom range from the kit's
`theme.ts:146-162` [w1-06 §4.2]; files from the Pinax spec [w1-20 §5].

### 2.5 Schema

```jsonc
// gpuix-shell.json — JSON Schema sketch (draft 2020-12). Enforced by a zod schema at start-up [w1-29 #178]
// and by `gpuix-shell --check-theme` in checks.gpuix-shell-themes [w1-21 §5.3c].
{
  "type": "object", "required": ["_generated", "color", "font", "type", "space", "size", "radius", "motion", "layout", "focus"],
  "properties": {
    "_generated": { "type": "object", "required": ["theme", "polarity", "by"],
                    "properties": { "theme": { "enum": ["noir", "claude-dark", "claude-light"] },
                                    "polarity": { "enum": ["dark", "light"] }, "by": { "type": "string" } } },
    "color": { "type": "object", "required": ["surface", "ink", "line", "brand", "accent", "status", "run", "dot", "selection", "state", "scrim"],
      "properties": {
        "surface":   { "$ref": "#/$defs/keys", "x-keys": ["canvas","base","raised","sunken","overlay","desktop","input","inverse"] },
        "ink":       { "x-keys": ["strong","default","muted","subtle","disabled","inverse","on-brand","on-accent","link"] },
        "line":      { "x-keys": ["hairline","default","strong","focus","urgent"] },
        "brand":     { "x-keys": ["mark","default","emphasis","muted"] },
        "accent":    { "x-keys": ["default","emphasis","muted"] },
        "status":    { "x-keys": ["danger","warning","success","info","neutral"], "x-each": ["fg","bg","line","emphasis"] },
        "run":       { "x-keys": ["blocked","working","done","idle","unknown"] },
        "dot":       { "x-keys": ["waiting","error","working","done"] },
        "selection": { "x-keys": ["bg","fg"] },
        "state":     { "x-keys": ["hover","selected","pressed","disabled"] },
        "scrim":     { "$ref": "#/$defs/hex" }
      } },
    "font":   { "x-keys": ["ui","prose","mono","glyph","weight"] },
    "type":   { "x-keys": ["caption","meta","chrome","row","body","input","title","display","prose","figures","figures-sm","code"],
                "x-each": ["size","lineHeight","weight","family"] },
    "space":  { "type": "object", "additionalProperties": { "type": "integer" } },
    "size":   { "x-keys": ["control","icon","target","row","chip","mark","dot","ring","keycap","header","footer","bar"] },
    "radius": { "x-keys": ["none","xs","sm","md","lg","xl","full","row","outer"] },
    "motion": { "x-keys": ["duration","easing","scale","pulse"] },
    "layout": { "x-keys": ["rail","launcher","switcher","toast","center","osd","controls","power","files","ask","zoom"] },
    "focus":  { "x-keys": ["width","offsetControl","offsetRow"] }
  },
  "$defs": { "hex": { "type": "string", "pattern": "^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$" } }
}
```

`x-keys` lists the required child keys; every colour leaf matches `$defs/hex`. The three value sets in
§2.3 plus the shared block in §2.4 are the complete fragment. The Nix renderer emits exactly these keys;
the shell refuses to start on a fragment that fails the schema and says which key is missing (U-04).
`layout.toast.anchor` is an enum `["top-center","top-right"]`; `layout.rail.boot` is
`["collapsed","expanded"]`.

---

## 3. Typography

| Voice | Family | Sizes | Weight | Where |
|---|---|---|---|---|
| chrome | Anthropic Sans | 12 / 18 | 500 for labels, 400 for meta | rail labels, section headers, footers, key cap labels, status words [BRIEF §3.6, w1-04] |
| row | Anthropic Sans | 13 / 20 | 400; 500 when selected | switcher, controls, files, centre and rail rows [w1-11 §4.2] |
| body | Anthropic Sans | 14 / 21 | 400 | **launcher row titles** (A-29), toast title (500) and body, modal prose, OSD label is chrome [w1-13, w1-35] |
| input | Anthropic Sans | 16 / 22 | 400 | the launcher, ask and switcher text fields: Tom's "Vicinae font 12" is 12 pt = 16 px (A-29) [w1-04 §2.2 R9, w1-09 §2c] |
| title | Anthropic Sans | 16 / 20 | 600 | files header folder name, power menu heading, controls page title, centre title [w1-20 §5] |
| display | Anthropic Sans | 20 / 24 | 600 | ask header, gallery headings, the OSD percentage when no bar is shown [BRIEF §3.6] |
| caption | Anthropic Sans | 11 / 16 | 400 | the floor: key caps, "(N more)", slot numerals in the collapsed rail footer [w1-11 U-06] |
| figures | AnthropicMono Nerd Font | 12 / 18 (11 / 16 small) | 400 | clock, battery %, ages, counts, ids, byte sizes, PIN codes [w1-11 P-05, w1-25]; the kit's 9–10 px native times were flagged too small [w1-05 §4] |
| glyph | AnthropicMono Nerd Font | 13 (rail), 12 elsewhere | 400 | ◉ ◐ ● ✓ ○ and nerd icons; always its own text node with an explicit ink (A-03) |
| prose | Anthropic Serif | 15 / 25 | 400 | ask replies only; never UI chrome [BRIEF §3.6, w1-24] |
| code | AnthropicMono Nerd Font | 13 / 21 | 400 | ask code blocks, launcher `>` command output, files path field (14) |

Rules:
- Font families are resolved by name through fontconfig; the shell never ships or registers font bytes
  (the Anthropic fonts stay out of git) [BRIEF, w1-17 §4]. The binding parses `/etc/fonts/fonts.conf`
  itself [w1-21 §5.2]. `fc-match "Anthropic Sans"` → `AnthropicSans-Roman.ttf`; the mono family on the
  seat is **AnthropicMono Nerd Font**, not "Anthropic Mono" [w1-03 §3.2 L7, w1-06 G6].
- **Weight is never the only cue.** The installed Anthropic Sans is a variable face and GPUIX 0.11
  renders every weight identical unless a static bold instance is registered with `registerFont`, which
  would put font bytes in the package [w1-15]. So selected rows also change ink (`ink.default` →
  `ink.strong`), headings also change size, and the 500/600 weights are requested but not relied on
  (A-31). The kit's variable 580 "current" weight is not used (A-04).
- One family per text node (GPUIX limit) [w1-14]. A row title that mixes a glyph and words is two nodes.
  A node's text is always one template string: mixed JSX expressions inside one `<text>` laid out badly
  in the prior shell [w1-03 §3.2 L10].
- No italic, no letter-spacing, no text-transform: uppercase is typed into the string [w1-14, w1-11
  P-13]. Unknown families fall back to mono, and text defaults to black, so the root element sets
  `color` and `fontFamily` [w1-15].
- Line heights: 1.2 for titles and display, ≈1.5 for everything else; `opsz` is left to the font's
  automatic optical sizing [w1-17 §4].
- Every text node names an ink. Every `<svg>` names a `color` or it renders untinted [w1-03 §3.2 L11].
- Text elides at the end for titles and in the middle for paths and ids (U-17). Elision is done in code,
  by measuring, since GPUIX has no `text-overflow` [w1-14].
- Numbers are tabular by family: the mono figures role aligns clocks, ages and sizes without a feature
  flag.
- The seat's Sway title font is `Anthropic Sans 11` (pt ≈ 14.7 px) and mako's was the same [w1-09 §4b,
  w1-07 §4]; the body 14 voice therefore reads at the size Tom already lives with.

---

## 4. Spacing, radii, hairlines, elevation

**Grid.** 4 px base; 2 px exists only as the rail row gap and the focus ring width [w1-11 U-07, w1-25].
Padding ladder 4 / 8 / 12 / 16; 20 and 24 appear only as panel insets; nothing in shell chrome pads more
than 16 except the launcher's 16 px side inset and the files body margin 12 [w1-30 §4.1 N6]. The
uncodixfy "Keep It Normal" ladder 4/8/12/16/24/32 is the same ladder [w1-08 §4].

**Radii.** Two tokens do the work: `radius.row` (8) and `radius.outer` (12). The rest of the ladder
exists for chips and caps.

| Element | Radius | Note |
|---|---|---|
| rows, buttons, inputs, key caps' parent, rail slot cell | 8 (`row`) | [BRIEF §3.6, w1-25]; claude.ai's own palette rows are ≈8 at this scale [w1-09 §4a] |
| menus, cards, panels, toasts, OSD, launcher, switcher, controls, power | 12 (`outer`) | [BRIEF §3.6]; Tacit 12–18 and the kit's 16 are both trimmed; Tom's square mako/Vicinae look is `outer 0` (A-30) |
| key caps, chips, small pills | 6 (`sm`) | [w1-25 §4.5] |
| files grid art, pictures | 8 / 12 | concentric with the cell |
| sheets inside files | 12 | kit `lg` replaces Pinax's 18 |
| dots, avatars, progress bar ends | full | the only pills (U-05) |
| rail surface itself | 0 | a layer surface edge against the screen edge is square |

Concentric rule: an inner element's radius = outer radius − inset, floored at 4. A 44 px launcher row
inside a 12 px panel with a 8 px inset draws at 8; a 32 px cell inside the 56 px rail draws at 8 as the
probe did (MEASURED, BRIEF).

**Hairlines.** One hairline per boundary, 1 px, `line.hairline` between rows and sections,
`line.default` on panel edges that sit over the canvas, `line.strong` on inputs and on every overlay's
outer edge [w1-11 U-05, w1-20 §4]. The rail draws exactly one: its right edge. Never two hairlines
adjacent; never a hairline under the last row. GPUIX has no per-side border colour, so a one-sided edge
is a 1 px `div`, not a border [w1-03 §3.2 L9].

**Elevation.** Two steps only: `surface.base` (attached panels) and `surface.raised` (floating overlays).
Floating = raised + 1 px `line.strong` edge, nothing else, in noir, dark and light alike [w1-11 §4.1
"X1 elevation"]. No shadow at rest, ever (P-06). No scrim behind modals; the credential modal is a raised
card over the controls panel with a `line.strong` edge (U-05).

**Opacity and window background (A-32).** The rail and the files window are `windowBackground:
'opaque'` [w1-14]. Rounded overlays (launcher, switcher, toasts, OSD, controls, power, centre) use
`windowBackground: 'transparent'`, MEASURED to work on Sway 1.12 [w1-15 P7], so the corner pixels
outside the 12 px radius are clear; every pixel inside the panel is opaque. A transparent surface is
sized to its content, never oversized, because an oversized transparent layer surface swallows clicks
below it and GPUIX has no input-region API [w1-03 §3.2 L1]. Opacity is animated only to fade a toast or
OSD in; nothing is translucent at rest. The prior shell's `background + "e6"` toasts are not carried
over: they were never rendered [w1-03 §3.2 L12].

---

## 5. Motion

One curve: `cubic-bezier(0.2, 0, 0, 1)` [w1-25 §4.5, w1-11 P-07]. One multiplier: `motion.scale` ∈
{1, 0}; 0 makes every duration 0 and stops the pulse [w1-11 U-08]. Animatable properties are the GPUIX
set: width, height, top, right, bottom, left, opacity, borderRadius [w1-14, w1-15]. Colour never
animates: a state change recolours on the next frame (U-08, kmux B13 "> yes" [w1-30 §2.4]).

| Change | Duration | Property | Note |
|---|---|---|---|
| toast or OSD appears | 120 (`fast`) | opacity 0 → 1 | only the new card; neighbours do not slide (U-12) |
| toast or OSD leaves | 0 | — | removal is instant; the stack re-packs on the next frame |
| launcher, switcher, controls, power open/close | 0 | — | summoned surfaces appear whole; Raycast-style, no scale-in [w1-30 §4.1]. The ~0.3 s spawn-per-show latency (MEASURED) is the only "animation" and is not decorated with a spinner [w1-15] |
| launcher list filters | 0 | — | rows re-render; no FLIP |
| rail expand/collapse | 0 | — | a width change recreates the layer surface (GPUIX: no resize after creation); Sway re-tiles [w1-14, w1-03 L1, BRIEF] |
| keyboard cursor moves | 0 | — | the hover/cursor fill jumps |
| power hold progress | 1500 linear | width of the fill | the one long motion; it is a measurement of the hold, not decoration |
| working dot pulse | period 600, steps | opacity 1 → 0.55 → 1 | rail and switcher only; stepped (two frames per period), not eased; off at scale 0 (A-06) |
| files sheet enter | 180 (`base`) | opacity | Pinax's 220 OutCubic replaced by the one curve |
| files rail compact toggle | 180 (`base`) | width 248 ↔ 60 | an ordinary toplevel may resize |

Tacit's restraint carries over as a ceiling: nothing exceeds 240 ms, no overshoot anywhere, exits are
never slower than entries [w1-20 §4.6]. Tom's March ruling ("i really do not care about animations
whatsoever", "none/short for snappiest experience") is the reason the default ladder is this short
[w1-29 §2.1, w1-30 §4.1]; uncodixfy's 100–200 ms band agrees [w1-08 §4].

---

## 6. Tacit's vanilla-ness, in our values

Tacit is the aesthetic reference, not a source of values: its frost, Material scheme and notch are out
[w1-20 §1, BRIEF]; Tom's 10-20 order names it ("great inspiration for writing the gpuix project for a
linux wayland shell") [w1-07 §2.7]. What "vanilla" means once translated:

| Tacit habit [w1-20 §4] | Our value |
|---|---|
| frosted panel with one 1 px border | opaque `surface.raised` with one 1 px `line.strong` edge |
| washes: hover 5 %, menu hover 10 %, selected 12 %, pill-on 12 % | pre-blended `state.hover` (ink 0.10) and `state.selected` (ink 0.16); no 5 % step |
| 1 px keyboard ring at 0.7 | 2 px `line.focus` ring, keyboard only, offset 2 (controls) / −2 (rows) |
| row 15 / meta 13 / section 22 / body 17 | row 13 / meta 12 / title 16 / body 14 / input 16 (Anthropic Sans is set smaller than Inter at equal x-height) |
| radii 8 row, 10 tile, 12 slab, 14 panel, 18 sheet | 8 row, 8 tile, 12 slab, 12 panel, 12 sheet |
| spacing 4 / 6 / 8 / 10 / 12 / 14 / 16 / 20 | 4 / 8 / 12 / 16 / 20 (no 6, 10, 14) |
| icons 13 / 16 / 18 / 20 / 24 | 16 / 18 / 20 |
| colour transitions 80–140 ms, fades 150–200, moves 400–500 | colour 0, fades 120, moves 0 or 180 |
| notification 7000 ms, OSD 1000 ms | toast 5000 (mako parity), OSD 1500 (`osd` script parity) |
| control panel 460 wide, rows 40 | controls 420 wide, rows 40 |
| accent only on "what Enter does" and "where you are" | identical rule (U-01) |
| neutral icons, coloured only for state | identical rule; glyph ink is `ink.muted` until state says otherwise |
| no dock, no widgets, no weather on the bar | identical |
| StripBar OSD: icon + 2 px track | icon 18 + 3 px track + mono figure |
| Pinax explorer 1000×640, rail 248/60, rows 34/48 | identical geometry, our type and radii (§8.8) |

---

## 7. Shared grammar

### 7.1 The row

```
┌─ 8 ─┬── leading 34 ──┬─ title / subtitle ────────────────┬─ trailing state ─┬─ trailing action ─┬─ 8 ─┐
│     │  icon 18 or    │  title 13/20 (14 in the launcher) │  figures 12 or   │  key cap or ›     │     │
│     │  glyph 13      │  subtitle 12/18 ink.muted         │  dot 8 + word    │  (focused only)   │     │
└─────┴────────────────┴───────────────────────────────────┴──────────────────┴───────────────────┴─────┘
```

- Heights: 30 rail · 44 launcher/switcher · 40 controls/centre · 34 files list · 56 cards with two lines
  [w1-11 §4.2 size.row]. Two-line rows add 16 (rail 46, files 48). claude.ai's palette rows are 44 at
  this scale, which the launcher matches [w1-09 §4a].
- Leading cell is 34 wide and holds an 18 px icon or a 13 px glyph centred; rail collapsed uses a 32×30
  cell instead (§8.1).
- Trailing state is right-aligned figures (`12 mono`), or an 8 px dot followed by a state word in chrome
  12. Trailing action is drawn only on the focused row: a key cap ("↵") or a chevron.
- Fills: none at rest · `state.hover` for hover **and** keyboard cursor (one state, U-11) ·
  `state.selected` for the chosen row (title ink `ink.strong`, weight 500 requested) · **current** adds
  a 2 px `accent.default` bar in the leading gutter (x = 0..2, height = row − 8) [w1-25 §3, w1-11 P-04]
  · focused adds the 2 px ring at −2 only when the last input was a key.
- Urgent (Sway urgency on a workspace, critical toast): 1 px `line.urgent` edge on the row.
- Disabled: inks switch to `state.disabled`; the row stays in place and still shows why (subtitle).
- The selection bar and the current bar are absolutely positioned 2–3 px `div`s inside a
  `position: relative` row (GPUIX has no per-side border colour) [w1-03 §3.2 L9].

### 7.2 Focus and layers

Hover equals keyboard cursor. The pointer moving over a row moves the cursor there; arrow keys move it
back. The ring appears only after a key event and disappears on the next pointer move (modality
detection in code; GPUIX has `focusVisible` styles but no modality) [w1-11 U-11, w1-14, w1-15]. Escape
closes the topmost layer: an open action panel before the launcher, the credential modal before the
controls panel. Tab moves between regions (input → list → footer actions) and is handled by hand at the
root `onKeyDown`; key names are lowercase strings and modifiers are `{shift, ctrl, alt, cmd}` [w1-14,
w1-03 §3.2 L8]. `<input>` takes focus only with `autoFocus` [w1-03 L8]. `keyboardFocusDim: false`
everywhere: no dimming of unfocused windows [w1-15].

Layer-shell map [w1-14, w1-15, BRIEF §3.3]:

| Surface | layer | anchor | exclusive | keyboard | margin | background |
|---|---|---|---|---|---|---|
| rail | top | left, top, bottom | 56 or 220, edge left | none | 0 | opaque |
| toasts | overlay | top (centred; or top+right) | 0 | none | [12, 0, 0, 0] (or [12, 12, 0, 0]) | transparent |
| notification centre | overlay | top, right | 0 | exclusive | [12, 12, 0, 0] | transparent |
| OSD | overlay | bottom (centred) | 0 | none | [0, 0, 96, 0] | transparent |
| launcher / ask | overlay | top (centred) | 0 | exclusive | [108, 0, 0, 0] | transparent |
| switcher | overlay | top (centred) | 0 | exclusive | [108, 0, 0, 0] | transparent |
| controls | overlay | top, right | 0 | on-demand | [12, 12, 0, 0] | transparent |
| power | overlay | none (centred) | 0 | exclusive | 0 | transparent |
| files | xdg toplevel | — | — | — | Sway tiles it | opaque |

`anchor: ['top']` centres horizontally and `height: 0` stretches, both MEASURED [w1-15]. All layer
surfaces exist on eDP-1 only: GPUIX has no output selector and the compositor places a surface on the
focused output at creation; the shell is launched while eDP-1 is focused and recreates a surface if its
output changes (A-07) [w1-14, w1-03 §3.2 L2, w1-06 G14]. A layer surface never appears in `swaymsg -t
get_tree`; tests read it back through `get_workspaces` rects and grim pixels [w1-21 §5.6, w1-06 G5].

### 7.3 Glyphs, words and figures

- Run state glyphs: ◉ blocked · ◐ working · ● done · ✓ idle · ○ unknown [BRIEF, w1-16]. Drawn as text
  in the glyph family (13 px), their own node, ink = `run.*` or `dot.*` (A-03). When the shell cannot
  read herdr, every slot shows ○ and the word "Unknown"; a stale snapshot (older than 30 s) keeps the
  last glyph and adds "stale 2 m" in figures (U-04). Nerd-glyph rendering in GPUIX is untested on this
  fleet; the gallery is the first place it is checked [w1-08 §6 #5].
- Slot numerals 1–9 (and 0 for ws 10 in the switcher): chrome 12, `ink.strong` when current.
- Indicators are Nerd Font glyphs from AnthropicMono Nerd Font (battery 󰁹 / 󰂄, Wi-Fi 󰤨, Ethernet 󰈀,
  Bluetooth 󰂯, volume 󰕾 / 󰖁, mic 󰍬, Tailscale 󰖂, bell 󰂚, recording ⏺, pomodoro 󰔛, capacity ◔):
  16 px, ink `ink.muted`, state colour only when state is not nominal [w1-17 §4, w1-18].
- Key caps: 18 px high, radius 6, 1 px `line.default` edge plus a 2 px bottom edge, figures-sm 11,
  padding 0 6 [w1-25 §4.5]; claude.ai draws them as transparent boxes with a hairline and muted glyph
  [w1-09 §4a]. Armed key cap (what Enter does): text `accent.default`.
- Words for state: Needs input · Working · New activity · Ready · Unknown; for connectivity:
  Connected · Connecting… · Off · Unavailable; for jobs: Copying 3 of 12 · Done · Failed: <reason>; for
  a slot whose projector shows another slot's workspace: "Mirrors slot N" (A-34).
- Times: "now", "4 m", "2 h", then "09:41", then "Mon 09:41" (U-17). Sizes: "1.2 MB" in figures.
- Empty states are one row in `ink.muted`: "No results for 'xyz'", "Nothing on the clipboard",
  "No networks found · Scanning…", "herdr unavailable · retrying". Never a blank panel (U-04).
- Capabilities are declared, never assumed: a page whose backend is absent (no BlueZ, no NetworkManager,
  no herdr) draws its rows disabled with the reason, in the Views-shell lineage [w1-06 §3 F39].

---

## 8. Surfaces

Each section: role, placement, geometry, anatomy, states, keyboard, wireframe. Wireframes are in logical
px; one character ≈ 8 px horizontally where a width is annotated.

### 8.1 Rail

**Role.** The left workspace bar: nine herdr slots with run state, plus the status cluster, replacing
waybar's workspaces module and the tray-less bar [BRIEF §3.3, w1-18, w1-25]. Tom's words: "a herdr
leftbar that is disjinted and contol sway workspaces", "herdr tabs on the left with sway and herdr
control", "a waybar style workspace (1>9) launcher" [w1-05 §2.1, w1-05 §2.2 L325, w1-09 §2c]. Read-only
over herdr; it acts only through Sway (`workspace number N`) [w1-16, BRIEF]. It never calls
`herdr workspace focus`, which moves every attached projector at once (MEASURED) [w1-07 §2.2, w1-09 §6 #4].

**Placement.** Layer top, anchored left/top/bottom, exclusive zone = its width, keyboard none, eDP-1
only. Two widths: **56 collapsed** (the measured probe; the default at boot, A-08) and **220 expanded**
(`gpuix-shell rail expand|collapse|toggle`). Changing width recreates the surface [w1-14]. With 56 the
workspace rect is x=56, width 1384 (MEASURED, BRIEF and the Nix smoke [w1-21 §5.9 #8]); with 220 it is
x=220, width 1220. Fullscreen on eDP-1 hides the rail (zone 0) [w1-29 #10].

**Geometry (expanded 220)** [w1-25 §3, w1-06 §4.1 (C++ `layout_constants.cc:36-44`), w1-11 §4.2]

| part | value |
|---|---|
| width | 220, one `line.hairline` at x=219 |
| inset | 12 top / 12 sides |
| row | 196×30, radius 8, gap 2; two-line row 46; content inset 8 horizontal / 6 vertical |
| leading cell | 34: slot numeral (chrome 12, `ink.strong` when current) at x=8, glyph 13 at x=20; icon slot 16, child spacing 4 |
| title | row 13/20, x=42, elide end, max 118 |
| trailing | 20: dot 8 centred at x=186 (ring 2 for `blocked`), or figures 11 count |
| current bar | 2×22 at x=0 in `accent.default` |
| footer | from y=900−12−(rows); indicator rows 24 high, 16 px glyph at x=12, figures 12 at x=36 |
| summary line | chrome 12 `ink.muted`: "2 working · 1 needs input" (the desk strip's two counts [w1-06 F22]) |

**Geometry (collapsed 56)** [BRIEF rail probe `evidence/rail-probe/rail.tsx`, MEASURED]

| part | value |
|---|---|
| width | 56, hairline at x=55 (56 = 12 + 32 + 12 [w1-06 G2]) |
| cell | 32×30, radius 8, centred (x=12), gap 2, first at y=12 |
| numeral | chrome 13 (Anthropic Sans 13 in the probe), ink `ink.default`; current → `ink.strong` + 2 px accent bar at x=0 |
| dot | 6 px at the cell's top-right (x=36, y=+6) in `dot.*`; omitted for idle; ○ outline 1 px for unknown |
| footer | glyph column, 16 px glyphs in 32×24 cells; clock as "09" / "41" stacked figures 11 (probe used mono 11 in accent; we use `ink.default`, A-09) |

**Anatomy, top to bottom.** Exactly nine slots in slot order (slot N = Sway workspace N; "a limit of 9
open workspaces at a time; this helps with my mental overload") [BRIEF, w1-07 §2.1]; ws 10 (Chrome on
eDP-2) is not a rail row. A slot with no herdr workspace is drawn dim with "–" and still clickable
(switches to the empty workspace); summary line; flexible gap; now-playing chip when MPRIS reports
playing (title elided, no menu) [ASSUMPTIONS music]; indicators in fixed order: pomodoro (only while
running), recording/privacy dot, claude-capacity, notifications (bell + unread count, DND shows 󰂛),
Tailscale, network, Bluetooth, volume, battery, clock. The order is INFERRED from the waybar module set
that was deleted and the kmux L2/M1 sidebar spec (A-10) [w1-18, w1-30 §3.3]. Utility launchers (Mail,
CRM, Projects, Agents, Files) are not rail rows (A-38).

**Identity.** Slot identity comes from Sway marks `herdr-slot-N`, `herdr-label-<label>`,
`herdr-workspace-<id>` on the projector window, never from the server's `focused_workspace_id`
("Never infer current identity from the server's global focus", `herdr-picker:3-6`) [w1-07 §2.2,
w1-09 §3a]. A slot label's number is the creation slot, not the current one [w1-09 §3a]. When marks are
missing or stale the row shows its herdr status with the word "unverified" in meta 12 (A-34).

**States.** current (focused Sway workspace) · selected is not used on the rail · hover = `state.hover`
· urgent = `line.urgent` edge (Sway urgent flag; `blocked` agents set it through the attention rule
[w1-05 F5]) · working dot pulses · blocked dot 8 + 2 px ring of the same colour · **mirrored**: two
projectors showing one herdr workspace after a reattach (Tom's F10 incident) is drawn, not hidden: the
duplicate rows carry "Mirrors slot N" and `ink.muted` glyphs (A-34) [w1-07 §2.2] · herdr unavailable:
all glyphs ○, summary "herdr unavailable" (the Zenbook reads herdr over SSH to the strix; a 6 s timeout
is a normal condition, not an error word) [w1-09 §3a].

**Input.** Click slot → `swaymsg workspace number N`. Click indicator → `gpuix-shell controls open
<page>` (network, bluetooth, audio), `notifications toggle` (bell), `launcher open --provider music`
(chip). No tooltips, no popovers, no menus on the rail (U-11; GPUIX one-window-per-process) [w1-14].
Wheel over slots → workspace prev/next (Sway bind parity) [w1-29 #17]. The rail never takes keyboard.

**Wireframe: expanded 220 (left) and collapsed 56 (right)**

```
x=0                                   219   x=0        55
┌──────────────────────────────────────┐    ┌────────────┐
│ ▌1 ◐ herdr-web-ui            ●      │ 12 │ ▌ 1 ·      │  32×30 cell, dot top-right
│  2 ◉ gpuix-shell             ◎      │ 30 │   2 ◎      │
│  3 ● paper intake            ●      │    │   3 ·      │
│  4 ✓ notes                          │    │   4        │
│  5 ○ Mirrors slot 1  unverified     │    │   5 ○      │  mirrored / unverified row
│  6 ○ –                              │    │   6        │
│  7 ○ –                              │    │   7        │
│  8 ○ –                              │    │   8        │
│  9 ○ –                              │    │   9        │
│  2 working · 1 needs input          │    │            │
│                                      │    │            │
│                                      │    │            │
│ 󰎆 Daft Punk – Around the Wo…        │    │    󰎆       │  now-playing chip 46 h
│ 󰔛 18:42                              │    │    󰔛       │  pomodoro (only while running)
│ ⏺  rec                               │    │    ⏺       │  recording / privacy
│ ◔  62 %                              │    │    ◔       │  claude-capacity
│ 󰂚  3                                 │    │    󰂚       │  notifications unread
│ 󰖂  tailscale · strix                 │    │    󰖂       │
│ 󰤨  Freebox-5G                        │    │    󰤨       │
│ 󰂯  Magic Trackpad                    │    │    󰂯       │
│ 󰕾  45 %                              │    │    󰕾       │
│ 󰁹  87 % · 3 h 10                     │    │    󰁹       │
│ 09:41  Mon 20 Oct                    │    │    09      │  stacked clock, figures 11
└──────────────────────────────────────┘    │    41      │
   ▌ = 2 px accent current bar              └────────────┘
   ● dot.done  ◎ dot.waiting ring  · dot.working (pulsing)
```

### 8.2 Launcher

**Role.** Mod+d: Raycast-grade launcher replacing Vicinae at parity (apps, commands, clipboard with
images, files, emoji, calculator, herdr workspaces, Chrome tabs, music, actions, `>` shell) [BRIEF §5,
w1-35, w1-36, w1-29 M:238]; "feature parity at least with vicinae … including how it interacts w google
chrome tabs" is the bar, Chrome tabs being the open parity gap [w1-05 §6 #4, w1-06 G3]. Also the frame
for `ask` (§8.9) and for every launcher-family provider. "Contextual": the list knows the focused Sway
workspace, the herdr pane and its status [w1-05 F2].

**Placement.** Overlay, anchored top, margin top 108 (12 % of 900 as a fixed value, A-11), 700×580,
keyboard exclusive, closes on Escape and on focus loss [BRIEF §3.3, w1-11 layout.palette]. Centred:
x = (1440 − 700)/2 = 370 on the panel; the rail's zone does not shift it (layer surfaces are placed in
output space). Spawned per show (~0.3 s) [w1-15].

**Claude.ai palette check** [w1-09 §4a, Tom: "what makes claude ai's webui so powerful is [this]"]. The
screenshot Tom pasted measures, at 2×, rows 44, row inset 16, row radius ≈8, panel radius ≈22 at 826
wide, type tabs as a filled pill, sections "Recents" / "Actions", a footer legend `Esc` `←` `→` `/`
`Alt` `↵` `Tab`, and a three-level text hierarchy. The launcher keeps rows 44, inset 16, row radius 8,
sections and a footer legend; it keeps 12 outer (not 22) and 700 wide (not 826) per the order; the type
tabs become the scope pill and the Ctrl+P scope list; `Alt+↵` opens the row's actions as on claude.ai
and `Tab` composes (hands the typed text to ask / a new herdr workspace) (A-40).

**Geometry**

| part | value | source |
|---|---|---|
| panel | 700×580, radius 12, `surface.raised`, 1 px `line.strong` | [BRIEF, A-05] |
| input row | 48 high: scope pill (chrome 12, radius 6, hairline) at x=16 when a provider is active; text **input 16** at x=16 (or after the pill + 8); caret `ink.strong`; right: clear glyph 16 on content | Vicinae 60 / kit 34 / prior shell 42 → 48 (A-12); 16 px from Tom's "font 12" (A-29) [w1-35 §4, w1-13, w1-03 §4.2] |
| divider | 1 px `line.hairline` under the input | |
| list | 580 − 48 − 1 − 36 = 495 → 11 rows of 44 with 8 px list padding; section headers 30 take one row's budget | [w1-11 size.row.launcher] |
| row | 44: icon 18 (app icon as `<img>` 18×18 or glyph) at x=16; title **body 14** at x=50; subtitle meta 12 `ink.muted` inline after the title with "·" if short, else as a second line in a 56 row; trailing: kind word chrome 12 `ink.subtle` ("Application", "Workspace 3", "Tab · Chrome"), figures (clipboard age), key cap on focus | [w1-35 §4, w1-11 U-13, A-29] |
| section header | 30: chrome 12/500 `ink.muted` at x=16 ("Top result", "Recents", "Workspaces", "Applications", "Commands", "Clipboard", "Files", "Tabs") | [w1-35 §4, w1-09 §4a] |
| footer | 36: left = provider mark + name (chrome 12); right = key caps "↵ Open" · "Alt ↵ Actions" · "Ctrl P Filter" · "Tab Compose" · "Esc"; `line.hairline` above | [w1-35 §4, w1-36, w1-09 §4a] |
| action panel | 300×(rows), anchored bottom-right inside the panel above the footer, radius 12, `surface.raised`, `line.strong`; rows 40; a filter input 36 on top when > 6 actions | Raycast/Vicinae Ctrl+B / claude.ai Alt+↵ [w1-36, w1-09] |
| scope dropdown | 240×(rows), under the input at x=16; rows 40 with a check glyph on the active scope | Ctrl+P [w1-36] |
| clipboard lens | rows 56: thumbnail 40×40 (radius 6) for images at x=16, text preview (body 14, one line, elided) at x=68, figures age right; detail column optional at ≥ 700: not drawn (one-column lens, A-13); concealed/transient items never stored, a "paused" word in the footer while history is paused | [w1-35 §4, w1-06 G12] |
| grid lens (emoji) | 8 columns, cell 76×76, glyph 28, spacing 8, inset 16; selected = `state.selected` + ring | Vicinae cols 8 spacing 10 pad 20 → 4-grid values |
| music lens | rows 56 with cover 40×40, title/artist, figures duration; a 3 px progress bar under the current track's row | [ASSUMPTIONS music, w1-29 #116] |

**Row grammar across providers.** Leading = icon or glyph; title = name; subtitle = path / app / command;
trailing state = kind word or age; trailing action = key cap. The "Top result" section shows at most one
row. Frecency order inside sections follows Vicinae's formula [w1-36]. Hidden apps come from a config
list [w1-29 #102]; Tom's removed Chrome app shortcuts and the ChatGPT/Claude desktop entries stay hidden
[w1-09 §3 #33]. App launching goes through `gio launch <desktop-file>` with the file path as one argv
[w1-03 §3.1]. `XDG_CURRENT_DESKTOP` on the seat is `sway-physical`, so `OnlyShowIn` filtering allows for
it [w1-21 §5.10].

**Keyboard** (full table in KEYS.md; Vicinae parity [w1-36])

| key | action |
|---|---|
| typing | filters; `>` enters shell-command mode, `/` or Ctrl+P picks a provider, `=` calculator, `:` emoji, `@` workspaces, `♪`/`music ` music |
| ↑ ↓, Ctrl+J/K, Ctrl+N/P | move cursor; wraps at ends |
| ← → at text edges | jump between sections (claude.ai "Change type") |
| Enter | primary action (armed cap shows it) · Shift+Enter secondary · Ctrl+Enter tertiary |
| Alt+Enter, Ctrl+B | action panel · Ctrl+K also opens it (Raycast habit) |
| Tab | compose: hand the typed text to ask or to a new herdr workspace (A-40); inside a provider with arguments, fill the argument |
| Ctrl+1..9 | quick access favourites |
| Backspace on empty | pop the provider / go back |
| Esc | close the top layer (panel → scope → launcher) |
| Ctrl+Shift+C copy · Ctrl+O open · Ctrl+Shift+P pin · Ctrl+X remove · Ctrl+Shift+X remove all · Ctrl+E edit · Ctrl+R refresh | Vicinae ids kept |

**States.** Loading provider: the section header gets "…" and the list keeps the previous rows (U-12).
No results: one `ink.muted` row "No results for 'xyz' · ↵ searches files". Provider failed: a row in
`status.danger.fg` "Clipboard store unavailable". Pinned rows carry a 12 px pin glyph in trailing state.
Chrome tabs provider absent: the "Tabs" scope is listed disabled with "needs the browser bridge"
(U-04, declared not assumed).

**Wireframe (700×580 at y=108; action panel open)**

```
                 x=370                                                        x=1070
            y=108 ┌──────────────────────────────────────────────────────────────┐
                  │ [Apps ▾]  herd▏                                          ⌫ │ 48  input 16
                  ├──────────────────────────────────────────────────────────────┤
                  │ Top result                                                   │ 30
                  │ ◐ 1  herdr-web-ui                         Workspace 1   ↵   │ 44  cursor row (state.hover), title 14
                  │ Workspaces                                                   │ 30
                  │ ◉ 2  gpuix-shell · Needs input            Workspace 2       │ 44
                  │ ● 3  paper intake · New activity          Workspace 3       │ 44
                  │ Applications                       ┌────────────────────────┐│
                  │ 󰖟 Herdr Web UI                      │ Actions          ⌕    ││ 36
                  │    chrome --app=…                  │ Open                ↵  ││ 40
                  │ Commands                           │ Rename…        Ctrl E  ││ 40
                  │ ⌘  Herdr: new workspace            │ Park            Ctrl X ││ 40
                  │ ⌘  Herdr: park workspace 2         │ Close workspace…       ││ 40
                  │ Clipboard                          │ Copy name   Ctrl ⇧ C   ││ 40
                  │ ▣  herdr api snapshot | jq .      4│ Pin         Ctrl ⇧ P   ││ 40
                  │                                    └────────────────────────┘│
                  ├──────────────────────────────────────────────────────────────┤
                  │ ⌘ gpuix-shell     ↵ Open   Alt ↵ Actions   Tab Compose  Esc │ 36  footer
            y=688 └──────────────────────────────────────────────────────────────┘
```

### 8.3 Switcher

**Role.** Mod+i: the workspace switcher as a list (Sway has no overview), same card family as the
launcher, status sampled at open [BRIEF, w1-11 P-03, w1-16]; "one sway-wired workspace switcher that can
be toggled with mod i ; with herdr-provided status indicators. only for the top display" [w1-03 §2,
w1-09 §2c]. Rows are the rail rows (slots 1–9 plus ws 10 "Chrome" and any live workspace beyond the
nine) [w1-29 #27, #173]. It replaces PR #565's fuzzel switcher and keeps its rules: second Mod+i closes
only its own menu; "no Herdr focus verb, ever" [w1-06 F02].

**Placement.** Overlay, top, margin 108, 560 wide (A-14), height = 48 + rows×44 + 36, max 580; keyboard
exclusive. Second Mod+i or Escape closes; Enter focuses the workspace via Sway and closes. If eDP-1 is
absent the switcher fails visibly (a toast "no top display"), it never chooses another output
(SH-04) [w1-03 §3.1].

**Geometry.** Input row 48 (input 16; type to filter by name or number; digits 1–9/0 jump immediately);
rows 44 in the shared grammar: leading slot numeral + glyph, title workspace name, subtitle = focused
window title (meta 12 `ink.muted`, elided), trailing = dot + state word; `●` marker (ink.strong) before
the numeral of the currently focused workspace, `!` in `line.urgent` for urgent [w1-16 herdr-bar];
footer 36 with caps "↵ Focus · Ctrl E Rename · Ctrl X Park · Ctrl ⇧ X Close · Esc". Close expects the
herdr 0.9.4 confirm-before-close prompt once #563 merges; the row shows "Closing… confirm in the
terminal" until the echo [w1-09 §6 #14].

**Ordering.** herdr-bar's order: most recent first, the current workspace never first, then by status
rank blocked < done < working < idle [w1-16]. Order is fixed while open (U-12). A "day start" lens is
not drawn tonight; the switcher is the live version of Tom's hand-written start-of-day table
[w1-07 §2.1].

**Wireframe (560 wide at x=440, y=108)**

```
┌────────────────────────────────────────────────────────┐
│ ▏                                             Mod i ⇄ │ 48  filter, input 16
├────────────────────────────────────────────────────────┤
│ ! 2 ◉ gpuix-shell                 ◎ Needs input    ↵  │ 44  cursor
│   3 ● paper intake                ● New activity      │
│   4 ✓ notes                         Ready             │
│ ● 1 ◐ herdr-web-ui                · Working           │  ● = currently focused, never first
│   0   Chrome                        eDP-2             │
│   5 ○ –                             Empty             │
├────────────────────────────────────────────────────────┤
│ ↵ Focus   Ctrl E Rename   Ctrl X Park   Ctrl ⇧ X Close│ 36
└────────────────────────────────────────────────────────┘
```

### 8.4 Toasts and the notification centre

**Role.** The `org.freedesktop.Notifications` server's visible half, replacing mako: a stack of toasts
and a history panel [BRIEF §3.2, w1-18 §mako, w1-26 §notifications]. Never runs beside mako (the HM
module asserts it) [w1-21 §5.10]. The prior shell's daemon store, close reasons and 32-action caps carry
over [w1-03 §3.1, §4.5].

**Toast placement (A-15).** Overlay, anchor **top (centred)**, margin [12, 0, 0, 0], keyboard none,
width 390, eDP-1: Tom's own mako ruling of 2026-10-11, "top and center not top right" [w1-18, w1-05 §4,
w1-06 §2.4]. `layout.toast.anchor: "top-right"` moves the stack to the kit/BRIEF position with margin
[12, 12, 0, 0] [BRIEF §3.3]. Centred, the stack spans x = 525..915. The surface is one transparent
window sized 390 × (Σ card heights + 8 × (n − 1)) and recreated when the set changes (GPUIX cannot
resize; the prior shell used the same respawn pattern) (A-16) [w1-03 §3.2 L1, w1-14]. It is never
taller than its cards, so it swallows no clicks below it (§4).

**Card geometry (content-sized, 72–140 high, A-17)** [BRIEF §3.3, w1-13, w1-18 mako 390/12/14/1 and
`height ≤ 100` with shrink]

| part | value |
|---|---|
| card | 390 × (72–140), radius 12, `surface.raised`, 1 px edge: low `line.hairline` · normal `line.default` · critical `line.urgent` (mako: low = border.inactive, high = red [w1-07 §4]) |
| padding | 14 all sides (mako parity) |
| header row | 20: app icon 16 (`desktop-entry` or `image-path`) at x=14, app name figures 11 `ink.muted` at x=36, age figures 11 right |
| title | body 14/21 `ink.strong` (weight 500 requested), one line, elide end, from y=40 |
| body | body 14/21 `ink.default`, zero to two lines, elide end; a card with no body is 72 high |
| image | `image-data`/`image-path` as a 48×48 (radius 6) thumbnail at the right of the body when present; body width shrinks by 60 |
| actions | up to two: key-cap style buttons 24 high (chrome 12, radius 6, hairline) bottom-left; the default action is armed (accent text); extra actions fold into "…" |
| value bar | `value` hint: 3 px track `line.hairline` with `selection.bg` fill across the card's bottom inside the padding (A-18); mako's progress colour [w1-07 §4] |
| gap | 8 between cards; max 4 cards; a 5th shows as a 24 px "(N more)" strip in chrome 12 under the last card [BRIEF] |

**Behaviour (A-35, A-36).** Per-urgency timeouts low 5000 · normal 5000 · critical never (mako config
parity); a client's explicit `expire_timeout` ≥ 0 always wins, including `0` = never; `-1` means the
server default [w1-18, w1-26]. New card fades in 120 ms; the stack packs **newest at the top**
(mako's `sort=-time`); replace-id updates in place; close reasons expire=1 / dismissed=2 / closed=3 /
undefined=4 [w1-26]. Flood: 20/s cap and 1 s duplicate coalescing [w1-29 #82]. DND suppresses drawing,
not storage. Hover pauses the countdown (not drawn). Mod+o dismisses the newest (PR #571's verb)
[w1-09 §3 #12]; actions are invoked from the centre with hint letters or by pointer on the toast. A
notification with `app_name == "osd"` is routed to the OSD surface and never drawn as a card (A-33).
Critical cards from `herdr-attention` carry the "Focus" action that runs the deep link / Sway focus,
and visiting the workspace acknowledges them [w1-05 F5, w1-06 F12].

**Notification centre.** `gpuix-shell notifications toggle` or the rail bell: 500×650 overlay top-right
(margin 12), keyboard exclusive, radius 12, `surface.raised` [w1-11 layout.notification-center]. Header
46: "Notifications" title 16, DND switch (chrome 12 "Do not disturb" + 32×18 switch) and "Clear all"
cap. Groups by app name, newest first, group header 30 with app icon, name and count; rows 56 (title,
body one line, age) with hint letters a–z in a 18 px key cap at the left while the panel has focus
(DMS "hints overlay" ruling) [w1-29 #77]; a row's actions open on Enter as a 240 px menu. Empty state:
"No notifications". Persistence is JSONL under `$XDG_STATE_HOME` [w1-29 #70].

**Wireframe: stack (centred, x=525..915) and centre**

```
                       x=525                           x=915
                  y=12 ┌───────────────────────────────┐
                       │ 󰊤 herdr               now    │ 20  figures 11
                       │ Workspace 2 needs input       │ 14/500 ink.strong
                       │ gpuix-shell is waiting for    │ 14
                       │ permission to run bun test.   │
                       │ [Focus ↵] [Dismiss]           │ 24 caps
                       └───────────────────────────────┘ 140 (newest, on top)
                       ┌───────────────────────────────┐ +8
                       │ 󰗃 Chrome              2 m     │
                       │ Download complete       ┌───┐ │
                       │ rail-probe.png · 1.2 MB │img│ │
                       │                         └───┘ │
                       │ ━━━━━━━━━━━━━━━━━━━━━━━━──────│ value bar 3 px
                       └───────────────────────────────┘ 112
                       ┌───────────────────────────────┐ +8
                       │ 󰂯 bluetooth           9 m     │
                       │ Magic Trackpad connected      │
                       └───────────────────────────────┘ 72 (no body)
                       (1 more)                          24

┌─ Notification centre 500×650 (top-right) ─────────────┐
│ Notifications            Do not disturb ◯━  Clear all │ 46
├───────────────────────────────────────────────────────┤
│ 󰊤 herdr                                        3      │ 30 group
│ [a] Workspace 2 needs input · permission…    now      │ 56
│ [b] Workspace 3 finished · 12 files changed  4 m      │
│ [c] Workspace 1 ready                        2 h      │
│ 󰗃 Chrome                                       1      │
│ [d] Download complete · rail-probe.png       2 m      │
│                                                       │
│                                                       │
├───────────────────────────────────────────────────────┤
│ letter Select   ↵ Actions   x Dismiss   Esc           │ 36
└───────────────────────────────────────────────────────┘
```

### 8.5 OSD

**Role.** Echo for volume, mic, brightness, touchpad, caps and audio route; one replaceable slot in the
notifications process [BRIEF §3.2, w1-18 `osd` script, w1-29 #122]. The keys keep their scripts
("keypress > sway > script execution") [w1-05 §2.3]; `brightness`, `volume` and the Caps Lock touchpad
toggle already end in one `osd` call [w1-07 §3 #13, w1-09 §3 #15].

**Contract (A-33).** The `osd` script sends `notify-send -p -r <id> -a osd -h int:value:<pct>` with a
1500 ms timeout and keeps its id in `$XDG_RUNTIME_DIR/osd-notify.id` [w1-07 §3 #12, §5]. The daemon
routes every notification whose `app_name` is `osd` to this surface: summary = label, body = optional
second word, `value` = the bar, `replaces_id` = in-place update. The scripts therefore change nothing.
`gpuix-shell osd show <kind> <value>` is a second door to the same slot for new callers (P-10).

**Placement.** Overlay, anchored bottom, margin bottom 96, 280×56 (A-19), keyboard none, eDP-1. Hidden
while the launcher or controls are open [w1-29 #129]. Hold 1500 ms after the last update (the `osd`
script's own timeout, A-19) [w1-07 §4]; a new value replaces content in place without re-animating.

**Geometry.** Panel radius 12, `surface.raised`, 1 px `line.strong`. Icon 18 (`ink.default`) at x=16;
label chrome 12 `ink.muted` at x=46 ("Volume", "Mic", "Brightness", "Speakers → Magic Trackpad…");
figures 12 right-aligned at x=264 ("45 %", "Muted", "On"); 3 px track at y=42 from x=46 to x=264,
`line.hairline`, fill `accent.default` (muted: fill `ink.disabled`, width stays). Values cap at 100 %
(Tom: 0–100 only) [w1-29 #109]. Boolean kinds (touchpad, caps) draw no track and a word instead.
Brightness steps are 10 % (2 % with Shift) and the floor is one raw unit, so the bar never reaches a
drawn 0 while the panel is lit [w1-07 §4].

**Wireframe (280×56 centred, bottom at y=804)**

```
                     x=580                                   x=860
               y=748 ┌───────────────────────────────────────┐
                     │ 󰕾  Volume                        45 % │
                     │     ━━━━━━━━━━━━━━━━━━━━━━──────────── │ 3 px, accent fill
               y=804 └───────────────────────────────────────┘
```

### 8.6 Controls

**Role.** Quick controls as **list menus, not a tile grid** (Tom's March "no control center" WONT is
honoured in shape; BRIEF's `controls` surface is honoured in function: Wi-Fi, Bluetooth pairing, audio
route, DND, theme, Tailscale peers) (A-20) [w1-29 §6 G1, w1-30 §3.1 1.12, BRIEF §3.2]. They replace the
fzf-in-kitty prompt floats (640×200 / 640×300, border 2) that F9, Shift+F9, F10, Shift+F10 and the theme
keys open today, and the `fzf-nmcli` / `blueman-manager` delegations (issues #509, #510) [w1-07 §3 #14,
w1-09 §3 #18–19, w1-03 §3.1 quick controls]. Every row shows real device state (SH-09) or a declared
"Unavailable" [w1-03 §3.1, w1-06 F39].

**Placement.** Overlay, top-right, margin [12, 12, 0, 0], 420 wide (A-21), height = content up to 640,
keyboard on-demand (exclusive while a text field is focused), radius 12, `surface.raised`,
`line.strong`. Opened to a page: `gpuix-shell controls open network|bluetooth|audio|theme|tailscale|
dnd`. Escape goes back a page, then closes.

**Pages and rows** (rows 40, grammar of §7.1; switch = 32×18 pill, knob 14, on = `accent.default`)

| page | content | source |
|---|---|---|
| Home | one row per domain with its state word and chevron: Wi-Fi · Bluetooth · Audio output · Microphone · Brightness (client) · Do not disturb (switch) · Tailscale · Theme · Night light (`wl-gammarelay-rs`, disabled with "set by kanshi" until a D-Bus adapter exists) | [w1-30 §3.1, w1-07 §3 #19] |
| Wi-Fi | header row with switch; "Connected" section: SSID row with signal glyph, lock glyph, figures "5 GHz · 72 %", trailing "Disconnect"; "Networks" section (scan 500 ms after open, then every 15 s): rows signal · SSID · lock; Enter on a secured unknown network opens the inline password row (36 high input under the row, chrome cap "↵ Connect · Esc"); "Saved" section; footer caps: "Ctrl R Rescan · Ctrl X Forget · Ctrl H Hidden network…" | `fzf-nmcli` flows [w1-26 §NM, w1-29 #133–147] |
| Bluetooth | header switch; "Your devices": name, battery figures ("72 %"), state word; Enter connects/disconnects; "Pair a new device": scanning rows with a 12 s wait word "Searching…", trust-before-pair, 4 s power watchdog; pairing confirm card: code figures 20 (44 px row), "Enter pairs · Esc refuses", Enter armed only 600 ms after the card appears | [w1-26 §BlueZ, w1-10, w1-29 #148–157] |
| Audio | "Output" rows from `wpctl` (default ticked with ✓ in accent), "Input" rows, volume and mic sliders (track 3 px radius full, knob 14, step 5) with figures; Enter routes through `audio-route` which lifts a near-silent stored volume | [w1-26 §PipeWire, BRIEF commit 97ef81a9] |
| Tailscale | status row (Connected · exit node) and peer rows: name, OS glyph, online dot, figures last-seen | `vpn-status` [w1-29 G5, w1-30 G1] |
| Theme | three rows noir / claude-dark / claude-light with a 16×16 swatch (base ground + accent dot) and ✓ on the active one; Enter runs `theme <name>` (the F2 fzf prompt's replacement; the key itself is #566's business) | [w1-17 §3, w1-09 §6 #2] |
| DND | a switch row plus "Until 18:00" quick choices (chrome rows) | [w1-29 #71] |

**Credential modal** (NM PSK, BlueZ Agent1 confirm/PIN): a 360-wide raised card centred in the controls
panel over the page, title 16 ("Password for Freebox-5G"), body 14 one line, an input 36 (`surface.input`,
`line.strong`, password dots, "Show" cap), caps "↵ Connect · Esc Cancel"; secrets never travel through
the CLI [w1-30 §3.2 SECRET-AUTH]. Denied/failed: the modal stays, the body turns `status.danger.fg`
"Wrong password · try again".

**Wireframe: Wi-Fi page (420 wide, right edge x=1428)**

```
┌─ Controls › Wi-Fi ────────────────────────────────────┐
│ ‹  Wi-Fi                                       ●━ On  │ 46 header + switch
├───────────────────────────────────────────────────────┤
│ Connected                                             │ 30
│ 󰤨 Freebox-5G 󰌾              5 GHz · 72 %   Disconnect│ 40  (cursor row)
│ Networks                                 Scanning…    │ 30
│ 󰤥 Freebox-2G 󰌾                                       │ 40
│ 󰤟 strix-hotspot                                      │ 40
│ 󰤢 Livebox-8A3C 󰌾                                     │ 40
│   Password  ••••••••▏                         Show    │ 36  inline password row
│ Saved                                                 │ 30
│ 󰤨 iPhone de Tom 󰌾                            Forget  │ 40
├───────────────────────────────────────────────────────┤
│ ↵ Connect   Ctrl R Rescan   Ctrl H Hidden…   Esc Back │ 36
└───────────────────────────────────────────────────────┘
```

### 8.7 Power menu

**Role.** DMS-style session menu: a scrollable list with press-and-hold confirmation drawn as a progress
fill [w1-29 M:95, M:493, w1-19]. The hold *is* the confirmation dialog (#222 iceboxed). It mirrors the
seat's actual habits: Mod+Shift+p `monitors-off`, F10 backlight toggle, no real sleep ("very
minimalistic") [w1-07 §2.2, §3 #15].

**Placement.** Overlay, centred on eDP-1 (anchor none), 360 wide (A-22), height = 46 + rows×44 + 36,
keyboard exclusive, radius 12, `surface.raised`, `line.strong`. Mod+Shift+e (or whatever KEYS.md binds).

**Rows** (44, grammar §7.1; destructive rows carry a `status.danger.fg` glyph; the cursor starts on the
first safe row, Tacit's session screen habit [w1-20 §3]) (A-23):

| row | key | kind | command |
|---|---|---|---|
| Monitors off | m | safe, instant | `monitors-off` |
| Backlight off | b | safe, instant | `brightness toggle` (the client's F10) |
| Log out | l | destructive, hold | `swaymsg exit` |
| Reboot | r | destructive, hold | `systemctl reboot` |
| Power off | p | destructive, hold | `systemctl poweroff` |

Not drawn: Lock (no locker is installed and ext-session-lock is out of scope; "lock is a verb, unlock
never" stays as a rule for later), Suspend (Tom: "not implementing real sleep"; hidden behind a config
flag), Hibernate (no swap) [w1-29 #203, #219, BRIEF, w1-12, w1-07 §2.2].

**Hold.** Enter or the row's letter starts a 1500 ms hold (A-24): the row's background fills left→right
with `status.danger.bg` and a 3 px `status.danger.fg` bar along the bottom edge; the trailing word counts
"Hold… 1.5 s → 0.0 s" in figures; releasing early cancels and the fill snaps back (duration 0). Pointer:
press-and-hold on the row behaves the same. Second press on a safe row is not required.

**Wireframe (360 wide, centred)**

```
┌───────────────────────────────────────┐
│ Session                               │ 46  title 16
├───────────────────────────────────────┤
│ 󰍹  Monitors off                   m   │ 44  cursor (safe)
│ 󰃞  Backlight off                  b   │
│ 󰍃  Log out                        l   │
│ 󰜉  Reboot            ▓▓▓▓▓▓▓▓░░░ 0.6 s│  holding: danger.bg fill grows, figures count down
│ ⏻  Power off                      p   │
├───────────────────────────────────────┤
│ hold ↵ or letter 1.5 s to confirm  Esc│ 36
└───────────────────────────────────────┘
```

### 8.8 File explorer

**Role.** A Pinax-like file explorer as an ordinary xdg toplevel that Sway tiles; the one surface that
is a window, not a layer [w1-20 §5, BRIEF §3.2]; "in my case what is of interest is mainly the file
explorer" [BRIEF §1]. It is a **browser**, not a chooser: open/save dialogs stay with the GNOME portal's
Nautilus (`FileChooser = "gnome"`, `modules/sway.nix:169-173`), which Tom named as the one thing to keep
(A-37) [w1-09 §2a T2, §3 #11]. Jobs run through `job.sh`-style helpers with an Undo pill; the shell never
deletes without a job record. Built without any compositor dependency so it can be lifted to the shared
side later [w1-04 G4].

**Geometry** (Pinax values rescaled to our type and radii; INFERRED where sizes shrink, A-25)

| part | value |
|---|---|
| window | default 1000×640, min 640×400; body margin 12; `surface.base`; `appId gpuix-shell-files`; `windowBackground: 'opaque'` |
| side rail | 248 full / 60 compact (Ctrl+B), rows 32, accent tick 3×16 at x=0 for the current place, glyph 18 at x=20, label row 13 at x=44; sections Now · Recent · Shelf · Places · Pinned · Drives · Trash, headers chrome 12 `ink.muted` 24 high |
| header | 44: back/forward 32×32 round buttons at x=12, folder name title 16/600, crumbs row 13 `ink.muted` separated by "›"; Ctrl+L turns crumbs into a path field (code 14, `surface.input`); view toggles list/grid/gallery 30×30 at the right (Ctrl+1/2/3); sort word (chrome 12) and hidden-files eye (Ctrl+H); "+" menu |
| filter | 36 high pill field (radius full, hairline) 140–230 wide at the header's right end; "/" focuses it |
| list rows | 34 (48 with an origin line), radius 8, glyph 20 at x=12, name row 13 at x=46 elide middle, age figures 12 in an 84 column, size figures 12 in a 72 column, both right-aligned |
| grid | cells 156×176, art 120×100 radius 8 top-centred, name row 13 two lines, meta 12 |
| gallery | strip 96 high of 88×96 tiles under a large preview |
| preview column | 300 wide, appears automatically at window width ≥ 1240, picture radius 12, facts in meta 12 (kind, size, modified, path), actions list rows 34 with ↵ cap; markdown, code, diff and images render natively (`<markdown>`, `<code>`, `<diff>`, `<img>`), PDF is "Open with…" only [w1-06 F24] |
| context menu | 236 wide, rows 34 radius 8, panel radius 12, padding 6 |
| status line | 24 high, chrome 12: "12 items · 3 selected · 48 MB" |
| sheets (rename, new folder, properties) | ≤ 460 wide, radius 12, enter 180 ms opacity |
| buttons | primary 40 high `brand.default` fill with `ink.on-brand`; quiet 36 high hairline |
| Undo pill | 60 s, bottom-centre, 36 high radius full, "Moved 3 items to Trash · Undo ↵" |
| zoom | Ctrl+= / Ctrl+- / Ctrl+0: every px through `px(n, scale)`, scale 0.8–1.6 step 0.1, reflow (A-39); Tom found zoom missing in the 10-14 windows [w1-06 §2.4, §4.2] |

**Keyboard.** Esc ladder: filter → selection → sheet → nothing. Enter opens; Space previews; Ctrl+L
path; Ctrl+H hidden; Ctrl+1/2/3 views; Ctrl+B rail; F2 rename; Delete trashes with Undo; Shift+Delete
asks via a sheet with a destructive hold (1500 ms, same drawing as the power menu). In-window keys are
Ctrl-chords (Super belongs to Sway; F6/F7 are volume keys and never reach a window) [w1-06 §5.1 keys.ts,
w1-09 §6 #1].

**Wireframe (1000×640; preview hidden below 1240)**

```
┌──────────────────────────────────────────────────────────────────────────────────────────┐
│ ‹ ›  Paper          Home › Paper                   ⌕ filter      ☰ ▦ ▤   Name ▾  󰈈  +   │ 44
├────────────┬─────────────────────────────────────────────────────────────────────────────┤
│ Now        │ 󰉋 inbox                                              2 m           –       │ 34
│ ▌ Paper    │ 󰉋 intake                                             1 h           –       │
│ Recent     │ 󰈙 scan-2026-10-20-01.png                            4 h       1.2 MB      │  cursor
│   Downloads│ 󰈙 scan-2026-10-20-02.png                            4 h       1.1 MB      │
│ Places     │ 󰈙 notes.md                                          Mon        3.4 kB     │
│   Home     │                                                                             │
│   Speech   │                                                                             │
│ Pinned     │                                                                             │
│ Drives     │                                                                             │
│   nas      │                                                                             │
│ Trash      │                                                                             │
│            ├─────────────────────────────────────────────────────────────────────────────┤
│   248      │ 5 items · 1 selected · 1.2 MB                                               │ 24
└────────────┴─────────────────────────────────────────────────────────────────────────────┘
```

### 8.9 Ask (OpenUI)

Launcher geometry (700×580 at top 108), same panel, keyboard exclusive [BRIEF §3.7, w1-24]. Input row 48
(input 16) at the bottom instead of the top (a chat reads downward); reply area above it uses prose 15
(Serif) for text, code 13 for blocks, and OpenUI components rendered natively through the adapter
[w1-14, w1-24, w1-08 §3.1]. Header 46: clay mark 22 (`brand.mark`), title 16 "Ask", status word chrome
12 `ink.muted` right ("thinking on strix…", "ready", "model unavailable").

**Facts are host-drawn, never model-written** [w1-24 rev2, w1-08 §3.3 #4]. The model composes a
program out of a fixed shell vocabulary (WorkspaceRow, AgentStatus, NotificationCard, SliderRow, Note)
and names ids; the host fills every status word, glyph, count and age from the live herdr/Sway
snapshot at render time. A component the model fills with a literal status is rejected by the validator
and drawn as a `status.danger` row "program rejected: <reason>". Generated controls carry exactly one
host action each and are drawn with `state.disabled` inks until validated; a `brand.muted` field behind
a streaming reply marks it as unfinished. Model id is config, never drawn as a number (U-17 would
middle-truncate it anyway). No Serif outside the reply area. The first draw of a program happens only
after the whole program validated (OpenUI parsing is permissive; its error list is not acceptance)
[w1-08 §3.1].

```
┌──────────────────────────────────────────────────────────────┐
│ ◖ Ask                                      thinking on strix… │ 46
├──────────────────────────────────────────────────────────────┤
│ Which workspace has uncommitted changes?                      │ 14, ink.default
│                                                               │
│ Two workspaces have changes:                                  │ prose 15 Serif (model text)
│ ◉ 2  gpuix-shell · Needs input · 14 files changed      4 m    │ WorkspaceRow, host-filled
│ ● 3  paper intake · New activity · 2 files changed     2 h    │ WorkspaceRow, host-filled
│ ┌ Open workspace 2 ┐ ┌ Show diff ┐                            │ one host action each, 34 h, disabled until validated
│                                                               │
├──────────────────────────────────────────────────────────────┤
│ ▏                                                   ↵  Esc   │ 48 input 16
└──────────────────────────────────────────────────────────────┘
```

---

## 9. What we deliberately do not draw

| Not drawn | Why | Source |
|---|---|---|
| a top bar | "no top bar on the Linux head"; `a.top-bar` is reserved, undrawn | [BRIEF, w1-11 P-01, w1-09 §4b] |
| a bottom dock / utilities tab bar | Tom's "utilities like email etc can go below" is the macOS tab bar; utilities are launcher rows here; X-option only (A-38) | [w1-05 §2.2 L325, w1-06 G1, w1-29 #13] |
| blur, frost, glass, scrims, translucency | flat and opaque; "i never needed skia.. i never even needed blur (let alone frost)"; otto's frosting "was just not enough" | [BRIEF, w1-07 §2.6, w1-20, w1-30 §4.3] |
| wallpaper colours or pickers | solid `#000000` in every theme | [BRIEF, w1-07 §4, w1-29 #57, #191–195] |
| an open/save file chooser | the GNOME portal's Nautilus stays (A-37) | [w1-09 §2a T2] |
| a task strip | zone 0 if ever; nothing tonight | [w1-11 P-11] |
| a lock screen, greeter, PAM UI | iceboxed; ext-session-lock is not layer-shell; no swaylock | [w1-29 #203–215, w1-30 G10] |
| Suspend / Hibernate rows | "not implementing real sleep"; no swap | [BRIEF, w1-12, w1-07 §2.2] |
| tray / SNI | deferred; "won't be using it personally"; the prior shell reported it "incomplete" | [w1-29 #29, w1-03 §6] |
| polkit dialog | deferred to a later packet (MUST, not tonight; recorded as a hole) | [w1-30 G2] |
| tooltips, popovers, flyouts on the rail | one window per process; no hover surfaces | [w1-14, U-11] |
| shadows at rest, spinners, springs, bounces | U-05, U-08 | [w1-11] |
| pills except dots, avatars and the Undo pill | U-05; uncodixfy "no pills" | [w1-11, w1-08 §4] |
| colour fades, animated workspace indicators | colour changes instantly | [w1-30 B13] |
| weather, calendar grid, notes, system monitor widgets, BongoCat | WONT / "serious shell" | [w1-29 #43, #240, #249, #59] |
| Material / matugen / i18n / RTL | WONT | [w1-29 #181, #197, #101] |
| a settings GUI or onboarding wizard | config is Nix; a launcher "settings" provider covers search later | [w1-29 G3, w1-30 G6] |
| a tile-grid control centre | list menus per domain instead | [w1-29 G1] |
| clay text on light grounds, clay button fills on the rail, clay as selection | 2.96:1; P-04; "clay never marks selection" | [w1-11 §4.1, w1-07 §2.6] |
| a countdown bar on toasts | motion only for change; the `value` hint bar is the only bar | [w1-11 U-08, A-18] |
| thumbnails in the switcher | later; text + state only | [w1-29 #165] |
| a visible model id, token counts or costs in the UI | config, not chrome | [w1-24] |
| key hints over the whole screen (hotkey cheat sheet) | not in BRIEF; later | [w1-30 G9] |
| a native chat window (clui-cc in GPUIX) | named by Tom, not tonight's critical path; `ask` is the bounded form | [w1-09 §2a T5, §3 #10] |
| a "day start" sheet surface | the switcher is its live form | [w1-07 §2.1] |
| screenshots inside the shell or sent to agents | "the one thing i m avoiding is the screenshot mechanism" | [w1-07 §2.6] |

---

## 10. Per-surface checklist for implementers

Before a surface is declared drawn, in the running theme, through `gpuix-shell gallery`:

1. every text node names a family and an ink; no black-by-default text (U-06, U-18) [w1-15];
2. every text node is one template string; every `<svg>` names a `color` [w1-03 §3.2 L10–L11];
3. contrast table of §2.3 holds on the ground actually used (U-02);
4. one hairline per boundary, none under the last row, `line.strong` on every overlay edge (U-05);
5. 2 px accent ring appears only after a key event (U-11);
6. empty, loading, stale, disconnected and failed states each render one row of words (U-04);
7. `motion.scale = 0` leaves the surface identical and silent (U-08);
8. switching `theme` live re-reads the fragment with no restart (U-18);
9. the same object (workspace, notification) is recognisably the same row in each lens (U-14);
10. nothing is drawn from §9;
11. the uncodixfy "Keep It Normal" audit passes: 1 px borders, radii ≤ 12, no glass, no gradients, no
    pills, transitions ≤ 200 ms, icons 16–20, body 14–16 [w1-08 §4];
12. a transparent window is no larger than its drawn panel (§4, A-32);
13. the surface reads at 390 px wide (the toast lens) or declares that it cannot (U-14).

---

## 11. Assumptions logged by this document

Each is one line in `ASSUMPTIONS.md` prefixed `DESIGN.md:`. A-15, A-17 and A-26 are revised from
revision 1; A-29 onward are new.

| id | decision |
|---|---|
| A-01 | Fragment values not derivable from theme roles (noir raised `#101111`, light primary `#A74B2F`, Primer dots, pre-blended states) are per-theme literals inside `gpuixShell` in Nix. |
| A-02 | Two state-colour families: `dot.*` (Primer, herdr-web-ui) on the rail and switcher dots; `run.*`/`status.*` everywhere else. |
| A-03 | Run glyphs ◉◐●✓○ are text in AnthropicMono Nerd Font, each its own node with an explicit ink; the collapsed rail draws a 6 px dot shape instead of the glyph. |
| A-04 | Weights 400/500/600 only; the kit's 580 "current" weight is not used. |
| A-05 | Outer radius 12 for launcher, switcher, toasts, OSD, controls, power; 8 for rows and controls; the kit's 16 rejected. |
| A-06 | Working-state pulse: opacity 1 ↔ 0.55, 600 ms stepped, rail and switcher only, off at `motion.scale 0`. |
| A-07 | All layer surfaces live on eDP-1; the shell starts them while eDP-1 is focused and recreates one whose output changes. |
| A-08 | The rail boots collapsed (56); 220 is reached by `rail expand`; width change recreates the surface. |
| A-09 | Collapsed rail clock is stacked "HH"/"MM" in figures 11 `ink.default`, not accent as in the probe. |
| A-10 | Rail footer order: now-playing, pomodoro, recording/privacy, capacity, notifications, Tailscale, network, Bluetooth, volume, battery, clock. |
| A-11 | Launcher top margin is a fixed 108 px (12 % of 900), not a percentage. |
| A-12 | Launcher input row 48 high (between Vicinae 60 and the kit control 34). |
| A-13 | Clipboard lens is single-column rows of 56 with 40 px thumbnails; no detail column. |
| A-14 | Switcher is 560 wide at the launcher's top margin, rows 44. |
| A-15 | Toasts anchor **top-centre** by default (Tom's 2026-10-11 mako ruling "top and center not top right"), margin top 12; `layout.toast.anchor: "top-right"` restores the BRIEF/kit position with margin 12 right. |
| A-16 | The toast surface is one transparent window sized to its cards (Σ heights + 8 px gaps), recreated when the set changes. |
| A-17 | Toast cards are content-sized between 72 and 140 px (mako shrinks cards); title one line, body up to two, max two actions, image 48 px. |
| A-18 | Toast `value` hint draws a 3 px bar with `selection.bg` fill; no timeout countdown is drawn. |
| A-19 | OSD is 280×56, bottom margin 96, hold 1500 ms (the `osd` script's own timeout). |
| A-20 | Controls are list menus per domain (Wi-Fi, Bluetooth, Audio, Tailscale, Theme, DND), never a tile grid. |
| A-21 | Controls panel 420 wide, max 640 high, top-right margin 12, rows 40. |
| A-22 | Power menu 360 wide, centred. |
| A-23 | Power rows are Monitors off, Backlight off, Log out, Reboot, Power off; Suspend hidden behind config; no Lock, no Hibernate. |
| A-24 | Destructive hold is 1500 ms, drawn as a left-to-right `status.danger.bg` fill plus a 3 px bar and a figures countdown. |
| A-25 | Files explorer defaults 1000×640, rail 248/60, rows 34/48, preview 300 at ≥ 1240; Pinax's 15/13 type becomes 13/12. |
| A-26 | Type ladder fixes chrome 12, row 13, body 14, input 16, title 16, display 20, floor 11, figures 12/11 mono. |
| A-27 | Status families: danger = red, warning = orange, success = green, info = accent, neutral = muted; `yellow` unused by the shell; light run.blocked `#9A3F00` and run.done `#006B00` are the kit's contrast-corrected values. |
| A-28 | The notification centre is 500×650, top-right, keyboard exclusive, with hint letters a–z while focused. |
| A-29 | Tom's "Vicinae font 12" is 12 pt ≈ 16 px, so the launcher, switcher and ask text fields are 16/22 (`type.input`) and launcher row titles are body 14; every other surface keeps the 12/13/14 ladder. |
| A-30 | Corners are rounded (`radius.outer` 12, `radius.row` 8) because the 10-20 order names Tacit's look; Tom's own mako/Vicinae `border-radius 0` is one token away (`radius.outer: 0`), logged as the X1 "square corners" option. |
| A-31 | Weight is never the only cue: the variable Anthropic Sans renders every weight alike in GPUIX 0.11 without a registered static bold, and font bytes never enter the package; emphasis is always also ink or size. |
| A-32 | `windowBackground` is `opaque` for the rail and the files window and `transparent` only for rounded overlays, each sized exactly to its panel (no input-region API; an oversized transparent surface swallows clicks). |
| A-33 | The notifications daemon routes `app_name == "osd"` (the `osd` script's `notify-send -r -h int:value`) to the OSD surface; the `osd`, `brightness` and `volume` scripts stay unchanged; `gpuix-shell osd show` is a second door. |
| A-34 | The rail draws the post-reattach "mirrored" state (two slots showing one herdr workspace) with the word "Mirrors slot N" and "unverified" when marks are missing, instead of hiding it or auto-restoring; identity comes from Sway marks only. |
| A-35 | Toast timeouts are low 5000 · normal 5000 · critical never (mako config parity); a client's explicit `expire_timeout` ≥ 0 always wins, `-1` means the server default. |
| A-36 | Toasts stack newest on top (mako `sort=-time`); U-12's "nothing reflows under the cursor" still holds because the stack has no keyboard cursor. |
| A-37 | The file explorer is a browser; open/save dialogs stay the GNOME portal's Nautilus; the shell never draws a chooser. |
| A-38 | No bottom dock or utilities bar on the Linux head; Mail, CRM, Projects, Agents and Files are launcher rows; a dock remains an X-option for Tom. |
| A-39 | Ordinary windows (files, and ask when windowed) get application-level zoom Ctrl+= / − / 0 over 0.8–1.6 in 0.1 steps; layer surfaces do not zoom. |
| A-40 | Launcher `Tab` composes (hands the typed text to ask or a new herdr workspace) and `Alt+↵` opens the row's actions, mirroring claude.ai's palette footer; Ctrl+B stays as the Raycast alias. |

---

## 12. Sources

BRIEF.md (order, rail probe MEASURED); wave1/01–02 (orientation, corpus map); wave1/03 (Codex
desktop-shell builds: prior toast 140+8, launcher 42/48, GPUIX 0.10 limits L1–L19, font family names,
one-template-string and svg-colour rules, DESKTOP-REQUIREMENTS SH-02/04/08/09); wave1/04 (look pivot
pointers, Vicinae font 12, mako blue = accent, dematerialized desktop); wave1/05 (SWAY-ONLY catalogue,
BASELINE tokens, 18 constraints, Tom's midday notes: left rail, shortcut-driven, bottom bar is macOS);
wave1/06 (boundary bucket A, kit tokens and derived roles, rail C++ lines, zoom 0.8–1.6, state vocabulary,
G1–G18); wave1/07 (nine-slot 1:1:1, projector collapse, herdr focus is global, OSD script contract,
prompt floats, brightness steps, "no real sleep", Tacit as reference); wave1/08 (OpenUI parity build:
strict validator, host-owned actions, uncodixfy "Keep It Normal", no layer-shell run, GLES2 only);
wave1/09 (claude.ai palette measured, Nautilus picker kept, Sway marks identity, herdr CLI, F6/F7
collision, Tom's 10-13/10-17 design quotes); wave1/10 (CUBS functionality list, credential modal);
wave1/11 (design kit: U-rules, P-corrections, token keys, palette derivations, surfaces table);
wave1/12 (boundary); wave1/13 (prior shell code); wave1/14–15 (GPUIX limits and the 15 measured 0.11
facts: layer-shell API, transparent background on Sway, anchor centring, animatable set, one window per
process, no resize, variable-font weights, text defaults); wave1/16 (herdr api, glyphs, herdr-bar order);
wave1/17 (dotfiles, theme system, fonts); wave1/18 (waybar/mako/Vicinae inventory, mako config values
and the G1–G24 conflicts); wave1/19 (Quickshell shells: DMS power menu, hints, stance table); wave1/20
(Tacit values, Pinax spec); wave1/21 (Nix: `--check-theme`, `checks.gpuix-shell-themes`, smoke template,
`sway-physical`); wave1/22–23 (gpui-shell OSD 280×56, launcher 600×450); wave1/24 (local model, OpenUI,
rev2 "the LLM must not guess status"); wave1/25 (herdr-web-ui rail 220/30/12/2/8, Primer dots, durations
120/180, curve); wave1/26 (Sway IPC, D-Bus servers, close reasons, theme reload); wave1/27–30 (notes repo:
Tom's March rulings, kmux sidebar spec, reversed rulings, control-centre WONT, power-menu hold, "no
hierarchy"); wave1/35–36 (Vicinae geometry, keybind ids, frecency, favourites);
`home/themes/{noir,claude-dark,claude-light,default}.nix` (palette roles, MEASURED tonight);
`home/dot_local/bin/osd`, `brightness`, `home/dot_config/sway/{layout,rules}.conf` (seat values, MEASURED
by readers 07 and 09).
