# SHELL.md: the client's Wayland shell, single source of truth

Status: dry run, branch `dryrun/shell-consolidation-2026-10-22` of a local clone, written 2026-10-22 just after midnight Paris by lane 23 (`shell-md`). Nothing in this file has been applied, deployed or tested on the client. The committed copy lives at `docs/shell/SHELL.md` in the clone; this copy at `OUT/SHELL.md` is identical. OUT means `/home/tom/wednesday-oct21/dryrun/shell`.

Register. Considered prose about the configs and the evidence, unless a block says TOM (Tom's words, verbatim, dated) or "proposed" (a drafter's proposal). Labels: TOM, REPORTED (a file says so), MEASURED (a command or path is given), INFERRED (judgement).

Ownership. This file owns the description of the shell: what each layer is, which file implements it, which ruling fixes it. `DECISIONS.md` at the repository root owns the reasons for rulings that predate tonight (ruling R1). `docs/client-sway-vicinae.md` becomes a pointer to this file plus its rebuild recipe (R1, proposed; that edit is not made on this branch because lane 23 owns only `docs/shell/SHELL.md`).

## 1. What the shell is

TOM, 2026-10-21 (quoted in `/home/tom/wednesday-oct21/situated/STATE-OF-AFFAIRS-2026-10-21.md` section 6): "from the get go we use shortcut based driven environments."

REPORTED, same section, the orchestrator's reading for this desk: "the shell is a set of shortcuts over a projector, a picker and a workspace switcher, and the chat is one of the surfaces."

The shell is stock Sway on the client (the ASUS Zenbook Duo) with kitty, fish, Chrome, Vicinae 0.29.1 as the one command palette, Mako for notifications, no bar and a black background (REPORTED `docs/client-sway-vicinae.md`, `home/dot_config/sway/config` header). Navigation is a set of single chords on Super plus a leader mode in the vimium manner; everything that is not navigation is a verb in the palette. A terminal window on the client is a projector onto the one herdr server on strix: closing the window detaches, and the panes, shells and agents keep running on strix. Fonts are Tom's own families, named by family only; the bytes come from the NAS and never enter git. The next renderer is GPUIX (a GPUI based shell); tonight only its interface contract and port list exist.

## 2. Topology: a thin client over one herdr server

| Host | Role | What runs there | Source |
|---|---|---|---|
| client (Zenbook Duo) | the seat | Sway, kitty projectors, Chrome, Vicinae, Mako, PipeWire and the wlr portal | REPORTED `hosts/client/default.nix` (imports, `myDisplay`), `modules/sway.nix` |
| strix | coordinator | `herdr.service` (the only herdr server), all agents and shells; also runs the same Sway desktop on its own physical seat | REPORTED `home/herdr.nix` header (ruling B5), `docs/client-sway-vicinae.md` |
| nas | font store | three `.tar.zst` font tarballs under `nas:/mnt/fast/fonts/anthropic/`, pinned by sha256 | REPORTED `pkgs/anthropic-*.nix`, `OUT/inventory/06-fonts.md` section 1 |

Ruling R-5 (thin client) is recorded in `DECISIONS.md` around line 724 and in `hosts/client/default.nix` lines 21 through 27 (REPORTED via `OUT/inventory/01-sway-compositor.md` section 7). Raw configs under `home/` are linked out of store from the dotfiles checkout on the host, so a rebuild from a remote flake without updating the checkout is insufficient (REPORTED `docs/client-sway-vicinae.md`).

## 3. The layers, in order

Each row names the layer, the file that implements it in the clone, and the file that owns its description in more depth. Paths are relative to the repository root of the clone unless they start with `OUT/`.

| # | Layer | Implementing path | Deeper reference |
|---|---|---|---|
| 1 | Compositor | `home/dot_config/sway/config` and its includes; `modules/sway.nix` (`/etc/sway/physical-session.conf`, session units) | `OUT/inventory/01-sway-compositor.md` |
| 2 | Keybindings and modes | `home/dot_config/sway/binds.conf`, `modes.conf`, `palette.conf`, `input.conf` (gestures); the `sway-local.conf` generator in `home/home.nix` | `docs/shell/KEYMAP.md` (generated), `OUT/spec/KEYBINDING-DOCTRINE.md` |
| 3 | Command palette | `home/dot_config/vicinae/commands.toml` (catalog), `home/dot_config/vicinae/palette` (runner), `home/vicinae.nix` (renderer); `~/.local/bin/palette` (not yet on the branch, see 3.3) | `OUT/spec/COMMAND-PALETTE.md` |
| 4 | Terminal | `home/dot_config/kitty/kitty.conf`, `font.conf`, `maps.conf`, `open-actions.conf`, `ssh.conf` | `OUT/inventory/02-kitty-fish.md`, `home/dot_config/kitty/README.md` |
| 5 | Shell | `home/dot_config/fish/config.fish` and `conf.d/` (`10-aliases`, `20-tools`, `30-shell-verbs`, `colors`, `herdr-term`, `remote`) | `OUT/inventory/02-kitty-fish.md` |
| 6 | Launcher | the same Vicinae instance as layer 3 (`home/vicinae.nix`) | `OUT/inventory/03-launcher-bar-notifications.md` |
| 7 | Bar | none, by ruling (`home/dot_config/sway/config` header) | `OUT/inventory/03-launcher-bar-notifications.md` section 3 |
| 8 | Notifications | Mako, declared in `home/vicinae.nix` | `OUT/inventory/03-launcher-bar-notifications.md` section 4 |
| 9 | Idle and lock | `home/shell/session.nix` (lane 17, commit `e0be6cbc`), imported through `home/shell/default.nix` (commit `849bd001`); before this branch only the `monitors-off` wake helper existed | `OUT/inventory/04-idle-lock-session.md` |
| 10 | Capture | `modules/sway.nix` lines 170 through 184 (portal), `home/dot_local/bin/screenshot`, `screen-ocr`, `screen-ocr-area`, `record`, `recording-toggle` | `OUT/inventory/05-capture-portal.md` |
| 11 | Fonts | `pkgs/anthropic-*.nix` (`requireFile`), `modules/common.nix` fontconfig, `home/dot_config/kitty/font.conf`, `home/dot_config/sway/layout.conf` | `OUT/inventory/06-fonts.md`, `docs/fonts/README.md` |
| 12 | Theme | `home/themes/default.nix` (writes `~/.config/theme/sway.conf`), `home/dot_local/bin/theme` | `OUT/inventory/04-idle-lock-session.md` section 7 |
| 13 | herdr projector and remote panes | `home/herdr.nix`, `home/dot_config/herdr/config.toml`, `home/dot_local/bin/herdr-projector`, `herdr-sway-projector`, `herdr-chord`, `herdr-picker`, `sway-workspace`, `herdr-panes` | `docs/shell/PROJECTOR.md` (lane 20), `OUT/inventory/07-herdr-projector.md` |
| 14 | GPUIX seam | contract and port list only | `OUT/spec/GPUIX-CONTRACT.md`, `OUT/spec/GPUIX-PORTS.md`, `docs/shell/DEFERRED.md` |

### 3.1 Compositor

Sway, native, physical seat. `home/dot_config/sway/config` includes, in this order: `/etc/sway/physical-session.conf` (from `modules/sway.nix`), `input.conf`, `layout.conf`, `binds.conf`, `palette.conf`, `modes.conf`, `rules.conf`, `startup.conf`, `~/.config/sway-local.conf` (generated by `home/home.nix`), `~/.config/theme/sway.conf` (MEASURED by reading the clone's `config`). Order matters: `palette.conf` sets `$palette` before `modes.conf` uses it, and `sway-local.conf` comes after the binds so the client's F10 and brightness lines win.

Niri and scroll were retired on 2026-10-13 and Sway kept the niri chord set (REPORTED `binds.conf` header, `DEFERRED.md` DF-CLIENT-2, commit `f62f15bf`, via inventory 01). MEASURED by inventory 01: `grep -ci sway DECISIONS.md` returns 0, so the Sway move has no `DECISIONS.md` row yet. Section 9 of this file records it.

Known scatter (REPORTED, inventory 01 section 8): output geometry is written twice (`sway-local.conf` and `home/dot_config/kanshi/config`); `output * bg #000000 solid_color` is set twice; workspace pins sit in `binds.conf`.

### 3.2 Keybindings and modes

The map. Every `bindsym` in `binds.conf`, `palette.conf` and `modes.conf` carries a machine readable comment directly above it, `## <group> | <verb> | <doc>` (MEASURED by reading the clone, commit `61b6babf`). `tools/keymap/gen-keymap.py` parses those files, the `sway-local.conf` generator in `home/home.nix`, kitty's maps and herdr's `[keys]`, and writes `docs/shell/KEYMAP.md`. At write time that table reports 167 bindings: Sway default 110, leader 26, resize 11, client only 8, kitty 4 plus 1 mouse, herdr 7 (REPORTED by the generated `docs/shell/KEYMAP.md` counts table; not rerun by this lane).

The shape rule (ruling R2). Mod plus one key navigates. Mod Shift plus a key moves or creates. Mod Ctrl plus a key opens a picker. Plain F keys and XF86 keys are hardware. The bare `Ctrl+n` and `Ctrl+Shift+n` Chrome grabs stay by Tom's request and are the flagged exception: they shadow every application's own Ctrl+N (REPORTED `binds.conf` comment).

The four owners. A keystroke passes Sway (Super namespace), then kitty (`ctrl+shift`), then herdr (prefix `ctrl+b`), then the application (bare Ctrl, Alt, letters). A layer claims keys only in its own namespace (REPORTED `OUT/spec/KEYBINDING-DOCTRINE.md` section 2).

Modes. `modes.conf` adds two modes on this branch (REPORTED by its header; nothing like it existed before 2026-10-22):
1. `leader`, entered with Mod+g: the next single key acts and Sway drops back to default. h j k l focus, H J K L move, 1 through 9 and 0 go to a slot, t new slot, w close slot, f or space open the palette, r enters resize; Escape, Return or Mod+g leave. This is the vimium style layer.
2. `resize`, entered with Mod+r or from leader.
There is no on screen mode indicator, because there is no bar; the indicator is a GPUIX port.

Protected lines. `flake.nix` asserts seven whole lines of `binds.conf` byte for byte: the three herdr chords and Alt+h/j/k/l (REPORTED `binds.conf` header). Mod+k stays Sway focus up (REPORTED `palette.conf` header, gpuix-shell KEYS rules via inventory 08 section 8).

Stale text. The keys table in `docs/client-sway-vicinae.md` lines 44 through 65 disagrees with `binds.conf` in at least three rows: Mod+0, Mod+C and Mod+Ctrl+Space (REPORTED inventory 01 section 8 item 9). `KEYMAP.md` is the table to trust; the doc table should be replaced by a link (proposed).

Unmerged. Branch `fix/sway-mod-o-dismiss-notifications` adds `bindsym $mod+o exec makoctl dismiss --all` (MEASURED by inventory 01 with `git diff HEAD...`). It is not on this branch.

### 3.3 Command palette

Ruling R3: Vicinae is the only palette, in the Linear and claude.ai manner: one key, then type a verb. Mod+space and Mod+d (and leader f and space) all exec one name, `$palette`, defined in `palette.conf` as `~/.local/bin/palette` with a fallback to `vicinae toggle` when that script is absent (MEASURED by reading `palette.conf`). The GPUIX phase swaps the backend inside that script and no key line changes (INFERRED design intent, stated in the file header). Mod+v opens Vicinae's clipboard history.

MEASURED at write time: `home/dot_local/bin/palette` does not exist on the branch (`ls` returned no such file), so the fallback is what would run. The catalog runner that does exist is `home/dot_config/vicinae/palette`.

The verb catalog. `home/dot_config/vicinae/commands.toml` holds one row per verb; `home/vicinae.nix` reads it with `builtins.fromTOML` and renders rows with scope `launcher` as Vicinae root items; `home/dot_config/vicinae/palette` reads the same file with `tomllib` and runs any row by id (REPORTED by the catalog header, commit `cf93ad07`). Native Sway commands (focus, move, layout, workspace number) are not exec targets and stay in `binds.conf` only.

Open disagreement (MEASURED by reading both): `OUT/spec/COMMAND-PALETTE.md` section 3 specifies ids of the form `scope.slug` and an `exec` argv array with scopes `window`, `workspace`, `herdr` and so on, while `commands.toml` uses hyphenated ids that double as desktop entry ids and a `scope` of `launcher`. The committed catalog wins until Tom rules; this is question Q3 in section 10.

### 3.4 Terminal

kitty. On this branch `kitty.conf` is split into `font.conf` (font resolution record) and `maps.conf` (the terminal's own chords), with dead revert blocks moved to `home/dot_config/kitty/README.md` (REPORTED commit `99db58c8`). kitty maps nothing for herdr, so `ctrl+b` passes through; `allow_remote_control yes` and `listen_on unix:@kitty-{kitty_pid}` are what `herdr-picker`'s `kitten @` calls depend on (REPORTED inventory 07 section 2). The font is AnthropicMono Nerd Font by family name.

### 3.5 Shell

fish. `config.fish` is split into `conf.d` fragments by concern on this branch (REPORTED commit `837ef9a5`). Two fragments are part of the projector contract: `herdr-term.fish` sets `KITTY_WINDOW_ID=0` inside herdr panes so Claude Code enables the kitty keyboard protocol (Shift+Enter, Ctrl+Backspace), and `remote.fish` defines `desk` as `exec ~/.local/bin/herdr-projector` on any host not named strix (REPORTED inventory 07 section 2).

### 3.6 Launcher

The launcher is the palette (layer 3): Vicinae 0.29.1 from `home/vicinae.nix`, one instance, root search plus favorites (Herdr workspaces, browser tabs, Now Playing, Search Tray). Clipboard history keeps entries one day, file search indexes Documents and Downloads, telemetry and remote favicons are off, the input helper is disabled (REPORTED `docs/client-sway-vicinae.md`). Chrome tab search uses the official Vicinae extension declared by system policy.

### 3.7 Bar

There is none. REPORTED `home/dot_config/sway/config`: "No bar: Vicinae is the command surface; Mako owns notifications." Inventory 03 found no verbatim Tom quote for the bar ruling, so it is labelled REPORTED, not TOM. What a bar would carry lives elsewhere today: slots in Mod+1 through Mod+0 and the herdr picker, agent state in the picker and herdr's sidebar, the clock in the Vicinae footer (REPORTED inventory 03 section 3). The bar returns only as the GPUIX rail.

TOM, 2026-10-13 (REPORTED via gpuix-shell wave1 note 35, cited in inventory 03): "the way we control brightness and volume should be keypress>sway>script execution, no need to tie in vicinae if we don't have to".

### 3.8 Notifications

Mako, declared in `home/vicinae.nix`, started with the physical Sway session. Normal notifications expire after five seconds, high urgency stays until dismissed, colours follow the shared palette, font Anthropic Sans (REPORTED `docs/client-sway-vicinae.md`). Dismiss and restore are palette verbs; the Mod+o dismiss chord is on an unmerged branch (3.2). The OSD script (`home/dot_local/bin/osd`) uses Mako's progress hint (REPORTED `OUT/spec/GPUIX-PORTS.md` row "osd").

### 3.9 Idle and lock

MEASURED by inventory 04 (grep over `home`, `modules`, `hosts`): no lock program and no idle timeout policy exist. `swayidle` appears only as a one shot wake helper inside `monitors-off`. The seat is deliberately unauthenticated today: passwordless login and a keyring that auto unlocks (REPORTED `modules/common.nix` greetd block, `modules/keyring-autounlock.nix`). INFERRED consequence: a lock screen has nothing to authenticate against until an authentication source is chosen.

Ruling R4 (proposed tonight): `swayidle` plus `swaylock` declared in Nix beside `sway-local.conf`. Lane 17 landed `home/shell/session.nix` (commit `e0be6cbc`): a long running swayidle bound to `sway-physical-session.target`, swaylock, and the capture tool set, gated on `osConfig.myDisplay.enable` like `home/vicinae.nix`, with portals left to `modules/sway.nix` (REPORTED by its header; this lane read only the header). It still carries the Q1 question below. The lid is inert to logind and Sway's `bindswitch` owns the panel half (REPORTED `hosts/client/lid.nix`).

### 3.10 Capture

The capture base is `wlr-screencopy` through grim and slurp, and `xdg-desktop-portal` with the wlr backend for ScreenCast and Screenshot over PipeWire, with slurp as the chooser (REPORTED `modules/sway.nix` lines 170 through 184, base portal in `modules/common.nix` lines 298 through 307). `home/dot_local/bin/screenshot` runs grim, slurp and Satty and spools to strix (REPORTED inventory 05 section 1). Recall layer hook, proposed in inventory 05: prototype on Hook A (grim over screencopy), define the recall input as a stream of frames with timestamp and output name, and let Hook B (portal ScreenCast into PipeWire) replace it at the GPUIX step. The recall layer itself is deferred.

### 3.11 Fonts

Four families pressed from Anthropic's public web cuts: `AnthropicMono Nerd Font` (terminal), `Anthropic Sans` (UI: Sway, Vicinae, Mako, GTK), `Anthropic Serif` (documents), `Anthropicons` (icons) (REPORTED `docs/fonts/README.md` via inventory 06). Bytes live on the NAS behind three `requireFile` derivations; configs name a family, never a file. `.gitignore` lines 37 through 40 block font extensions. MEASURED by inventory 06: no Anthropic font byte is in git, but five older `.ttf` files from the resume builder are (committed 2026-07-13). Lane 19 landed the guard `tools/fonts/check-no-font-bytes.sh` and marked font extensions `-diff -merge` (commit `c79d4584`).

### 3.12 Theme

Three role keyed palettes, `noir`, `claude-dark`, `claude-light`, flipped by one symlink through `home/dot_local/bin/theme`; consumers reload and the Sway background stays `#000000` in all three (REPORTED `docs/client-sway-vicinae.md`). The theme script calls `swaymsg reload`, so it is never run in this dry run.

### 3.13 herdr projector and remote panes

One herdr server, on strix, as the user unit `herdr.service`, not tied to the graphical session, `X-SwitchMethod=keep-old` so a switch never restarts it (REPORTED `home/herdr.nix` via inventory 07). On the client a terminal window is `kitty --class herdr-projector` running `herdr-projector`, a reconnect loop with backoff 1, 2, 5, 10 then 30 seconds and a unit preflight over BatchMode SSH. The slot model: Sway workspaces 1 through 9 each own one projector, parked views go to the scratchpad and keep their slot, creation stops when nine are taken (REPORTED `docs/client-sway-vicinae.md`). `herdr-picker` reads herdr only through `herdr api snapshot` and never starts a server. Closing a projector detaches; ending an agent is an explicit herdr action. Full write up: `docs/shell/PROJECTOR.md` (lane 20; MEASURED present at the second poll, not read by this lane).

### 3.14 GPUIX seam

TOM, 2026-10-21, as recorded in STATE-OF-AFFAIRS section 6 (REPORTED wording): the GPUIX implementation that uses Tom's own font is built on the 250 USD Claude cloud credits that expire on 2026-11-05, not on the seats. Ruling R5: tonight the seam is the interface contract and the port list only. The contract (`OUT/spec/GPUIX-CONTRACT.md`) sets a headless `gpuix-shell daemon core` owning `shell.sock`, a notifications daemon, a rail window daemon and toggled overlay surfaces, all beside a stock Sway, never a compositor. The port list (`OUT/spec/GPUIX-PORTS.md`) maps: no bar to rail, Vicinae launcher and clipboard to launcher, Mako to notifications, `osd` to the OSD child, `herdr-picker` to the switcher, fzf prompt menus to launcher dmenu mode, swayidle plus swaylock stays, power, controls and cheatsheet are new. The kitty herdr projector stays out of the shell. The font must load from a path outside any cloud repo; the existing gpuix-shell design reads faces through `GPUIX_SHELL_FONT_DIR` (REPORTED inventory 06 section 8). `docs/shell/DEFERRED.md` (lane 22) carries the list on the branch.

REPORTED `/home/tom/.wt/dotfiles/gpuix-shell/docs/gpuix-shell/SYNTHESIS.md`: the 2026-10-20 overnight build finished wave 1 and planning, then waves 2 through 4 never executed because the seat hit its session limit at 23:57:08; the rail probe opened a 56 px layer shell rail on an isolated headless Sway.

## 4. Binding map summary

The full table is `docs/shell/KEYMAP.md`, generated. This summary lists the families so a reader knows where to look; it is not a second source.

| Family | Chords (shape) | Owner file |
|---|---|---|
| Focus and move | Mod+h/j/k/l, Mod+Shift+h/j/k/l, Alt+h/j/k/l outputs | `binds.conf` |
| Slots | Mod+1 through Mod+9, Mod+0; Mod+t new, Mod+Shift+t restore, Mod+w close or park, Mod+Shift+n rename | `binds.conf` |
| herdr | Mod+Return projector, Mod+Ctrl+Shift+Return projector with sidebar, Mod+Ctrl+space picker | `binds.conf` (asserted by `flake.nix`) |
| Palette | Mod+space, Mod+d, Mod+v clipboard | `palette.conf` |
| Leader and resize | Mod+g leader, Mod+r resize | `modes.conf` |
| Apps | Mod+n and Ctrl+n Chrome, Mod+Ctrl+n and Ctrl+Shift+n incognito, Mod+e Nautilus, Mod+Shift+c claude.ai, Mod+Shift+w mail | `binds.conf` |
| Local terminal | Mod+Shift+Return plain kitty with fish | `binds.conf` |
| Hardware | F keys, XF86 keys; client F10 and brightness override | `binds.conf`, `sway-local.conf` generator in `home/home.nix` |
| Terminal | kitty `ctrl+shift` maps | `home/dot_config/kitty/maps.conf` |
| Inside projector | herdr prefix `ctrl+b` | `home/dot_config/herdr/config.toml` |

## 5. How to change a binding

1. Edit the line in the owning file from section 4. A new chord follows the shape rule (3.2); a hardware key goes in `binds.conf` unless it differs per host, in which case it goes in the `sway-local.conf` generator in `home/home.nix`.
2. Put the comment `## <group> | <verb> | <doc>` directly above the `bindsym`. A `bindsym` without it is a bug (REPORTED `binds.conf` header).
3. If the verb also belongs in the palette, add or update its row in `home/dot_config/vicinae/commands.toml` with the same command text (section 6).
4. Do not touch the seven `flake.nix` asserted lines; if one must change, change the assert in the same commit.
5. Regenerate: `python3 tools/keymap/gen-keymap.py` from the repository root, and commit the config and `docs/shell/KEYMAP.md` together.
6. Check offline: `nix flake check --no-write-lock-file --offline` and record the output. A Sway parse check runs only under `~/.local/bin/runtime-test`; never `swaymsg` against the live session.
7. Apply only on the client, from its checkout, with `nixos-rebuild boot` and a reboot, by Tom (REPORTED recipe in `docs/client-sway-vicinae.md`). Not part of this dry run.

## 6. How to add a palette verb

1. Add one row to `home/dot_config/vicinae/commands.toml`: `id` (stable, hyphenated, never renamed), `name` (imperative, sentence case), `description` (one line), `exec`, `scope` (`launcher` to show it in Vicinae root search).
2. If the verb needs an argument, prefer an existing `kitty --class *-prompt` fzf picker launched by the verb over a new menu; the palette stays the only palette (R3).
3. If the verb closes, kills or deletes, mark it for confirmation (field name per `OUT/spec/COMMAND-PALETTE.md` section 3, pending Q3).
4. If it also has a chord, the chord lives in `binds.conf` only; the catalog echoes the command text, it does not repeat the key.
5. Run `python3 -m py_compile` on any Python touched, and `nix eval` of the home configuration offline, and record both in `CHECKS.md`.
6. The GPUIX launcher will read the same catalog (one catalog, two renderers), so no verb is written twice.

## 7. Paths this branch adds or changes (at write time)

MEASURED with `git -C OUT/dotfiles log --oneline -10` at the second poll, newest last, on top of `032cc87d`: `cf93ad07` vicinae catalog, `837ef9a5` fish split, `99db58c8` kitty split, `61b6babf` sway annotations plus leader and resize modes plus palette routing, `af470eb6` keymap generator and `docs/shell/KEYMAP.md`, `849bd001` wiring of `home/shell` into `home/home.nix` and the client host pointing at SHELL.md, `c79d4584` font bytes guard, `6674e5fc` `docs/shell/DEFERRED.md`, `e0be6cbc` `home/shell/session.nix`. This file is the next commit.

Offline evidence: `OUT/CHECKS.md` (lane 21) records exact commands and exit codes, including a `nix flake check --no-write-lock-file --offline --no-build` that exited 0 with "all checks passed!" as an evaluation result only (REPORTED from CHECKS.md lines 70 through 78; not rerun here).

## 8. Glossary

- slot: a Sway numbered workspace 1 through 9 that owns at most one herdr projector.
- projector: a kitty window of class `herdr-projector` running a herdr client attached to strix.
- park: move a projector to the Sway scratchpad while it keeps its slot.
- palette: the one command surface, Vicinae today, the GPUIX launcher later.
- verb: one row of `commands.toml`, runnable by id.
- leader: the Sway mode entered with Mod+g, single key then back.
- seam: the GPUIX contract plus port list.

## 9. Decisions register

| Id | Date | Decision | Label and source |
|---|---|---|---|
| D-SH-01 | 2026-10-21 | Shortcut driven from the start; every surface is a verb with a key or a palette entry | TOM, STATE-OF-AFFAIRS section 6 |
| D-SH-02 | 2026-10-21 | GPUIX is built on the 250 USD cloud credits before 2026-11-05, not on the seats, with Tom's own font | REPORTED wording of a TOM ruling, STATE-OF-AFFAIRS section 6 |
| D-SH-03 | 2026-10-13 | niri and scroll retired; Sway keeps the niri chord set | REPORTED `DEFERRED.md` DF-CLIENT-2, commit `f62f15bf`; no `DECISIONS.md` row (MEASURED by inventory 01) |
| D-SH-04 | 2026-10-07 | Client desktop is stock Sway, kitty, Chrome, Vicinae, Mako, no bar, black background | REPORTED `docs/client-sway-vicinae.md` rollout section |
| D-SH-05 | before 2026-10-07 | Thin client: one herdr server on strix, the client only projects (R-5, B5) | REPORTED `DECISIONS.md` near line 724, `home/herdr.nix` |
| D-SH-06 | 2026-10-08 | Bare Ctrl+n and Ctrl+Shift+n Chrome grabs restored by request | REPORTED `binds.conf` comment |
| D-SH-07 | 2026-10-10 | Shift+F5 and F6 brightness in two percent steps | TOM per `home/home.nix` line 160 comment (REPORTED via inventory 01) |
| D-SH-08 | 2026-10-13 | Brightness and volume go keypress, Sway, script; not through Vicinae | TOM, REPORTED via wave1 note 35 |
| R1 | 2026-10-22 | SHELL.md owns description, `DECISIONS.md` owns why, `client-sway-vicinae.md` becomes a pointer | INFERRED, thesis ruling of this run |
| R2 | 2026-10-22 | Generated keymap; shape rule; bare Ctrl+N is the flagged exception | INFERRED, thesis ruling of this run |
| R3 | 2026-10-22 | Vicinae is the only palette; verbs in one catalog | INFERRED, thesis ruling of this run |
| R4 | 2026-10-22 | swayidle plus swaylock declared beside `sway-local.conf`; Mako stays; capture stays wlr portal plus PipeWire | INFERRED, thesis ruling of this run |
| R5 | 2026-10-22 | GPUIX seam is contract and port list only; fonts from a path outside any cloud repo | INFERRED, thesis ruling of this run |
| D-SH-09 | 2026-10-22 | Leader mode on Mod+g and resize on Mod+r, no indicator until the GPUIX rail | INFERRED, lane 12 commit `61b6babf` |
| D-SH-10 | 2026-10-22 | Palette keys exec one script name so GPUIX swaps the backend without key changes | INFERRED, `palette.conf` header |

The R rows are rulings of tonight's planning, not Tom's; they become TOM rows only when Tom confirms them.

## 10. Questions for Tom

1. Q1: lock with no password. Does R4 mean a visual lock only, or should the seat gain an authentication source first (3.9)?
2. Q2: merge `fix/sway-mod-o-dismiss-notifications` (Mod+o dismiss all) into the shell map?
3. Q3: verb id grammar, `scope.slug` per the palette spec or hyphenated desktop ids per the committed catalog (3.3)?
4. Q4: keep the bare Ctrl+N grabs, given that they shadow every application's Ctrl+N?
5. Q5: add a `DECISIONS.md` row for the 2026-10-13 Sway ruling (D-SH-03)?

## 11. Lane files cited, and their state at write time

MEASURED with `ls` at write time (about minute 9 of lane 23):

Present: `OUT/inventory/01-sway-compositor.md` through `08-shell-lineage.md` (all eight), `OUT/spec/KEYBINDING-DOCTRINE.md`, `OUT/spec/COMMAND-PALETTE.md`, `OUT/spec/GPUIX-CONTRACT.md`, `OUT/spec/GPUIX-PORTS.md`, `OUT/spec/KEYMAP.md`, `docs/shell/KEYMAP.md` in the clone.

Absent at the first poll and present at the second (about minute 11): `docs/shell/PROJECTOR.md` (lane 20), `docs/shell/DEFERRED.md` and `OUT/DEFERRED.md` (lane 22), `OUT/CHECKS.md` (lane 21), `home/shell/session.nix` and `home/shell/default.nix` (lanes 17 and 18), `tools/fonts/check-no-font-bytes.sh` (lane 19). Still absent at the second poll: `home/dot_local/bin/palette` (lane 16 TODO in `palette.conf`). Relative links from the committed copy: [KEYMAP.md](KEYMAP.md), [PROJECTOR.md](PROJECTOR.md), [DEFERRED.md](DEFERRED.md).

## Not verified

- No binding in this file was exercised; no Sway, kitty, fish or Vicinae ran. "Would run" statements are INFERRED from reading.
- Counts in 3.2 are copied from the generated `KEYMAP.md`; the generator was not rerun by this lane.
- `DECISIONS.md` line numbers and `hosts/client/default.nix` line ranges are REPORTED through inventory 01, not reopened.
- The wording of D-SH-02 is the orchestrator's record of Tom's ruling; the original sentence was not found in history (REPORTED by STATE-OF-AFFAIRS).
- PROJECTOR.md, DEFERRED.md and session.nix were seen by `ls` and header only; their content is not summarised here beyond what is cited.
- Whether `home/dot_local/bin/palette` landed after the second poll is unknown to this file.
- No `nix eval` or `nix flake check` was run by this lane; see `CHECKS.md`.
- No second reader (Tom's light verification rule, 2026-10-20).
