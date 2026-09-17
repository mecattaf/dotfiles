# Theme switcher: noir, claude-dark, claude-light (2026-09-17)

Three hand-curated themes, one palette source of truth in Nix, one symlink flipped
at runtime. No palette generation from wallpapers (matugen/pywal), no Home Manager
specialisations — see "Why not" below. Research report with the full option
analysis and the light-theme ANSI derivation: `~/colors/theme-switcher-design.md`
(not in this repo; ~/colors holds the colour investigation).

## The three themes

| theme | ground (terminal) | desktop | accents | source |
|---|---|---|---|---|
| `noir` | `#000000` | `#000000` | Claude Dark's 12-role syntax palette | Tom's catppuccin-noir; accents matched claude.ai's bundle bit for bit |
| `claude-dark` | `#1A1A1A` (code-block ground) | `#20201F` (`--bg-000`) | same as noir | `~/colors/waves/capture/claude-code-theme/claude-tokens-dark.json` |
| `claude-light` | `#F9F9F7` (`--bg-100`) | `#F0EFEC` (`--bg-300`) | Claude Light's 12-role palette | `claude-themes-SOURCE.json`, `claude-tokens-light.json` |

noir and claude-dark differ only in grounds (`home/themes/claude-dark.nix` is
`noir // { ground; muted; … }`). Claude ships no 16-slot ANSI palette, so
claude-light's is designed: roles fill slots 1–6, `--warning-100` fills the yellow
Claude has no role for, and `color0/7/15` are dark (punctuation / text-secondary /
fg) because herdr's `terminal` theme uses `White`/`Gray` as foregrounds. Every slot
passes WCAG AA on white. It is a proposal to tune in `~/colors/colorlab`.

## How it is wired

```
home/themes/{noir,claude-dark,claude-light}.nix   palettes, keyed by ROLE
home/themes/default.nix                            render: palette -> per-app fragments
home/theme.nix                                     HM: ~/.config/themes/<name>/{kitty.conf,niri.kdl,colors.fish,theme.lua,meta}
                                                       + activation: bootstrap/heal ~/.config/theme
~/.config/theme  ->  ~/.config/themes/<name>       the pointer; the ONLY runtime state
home/dot_local/bin/theme                           flip the pointer, fire reloads
```

Every RAW config keeps its body raw and joins its fragment through the app's own
include of `~/.config/theme/<fragment>` — the same move as `kitty-scrollback-nix.conf`
and `niri-local.kdl` (generated files at a neutral path, included from inside a
whole-dir RAW symlink). Home Manager owns `themes/` (plural); the switcher owns
`theme` (singular). Switching needs no rebuild; adding a theme or changing a
palette value does.

| consumer | joins via | live reload on `theme <name>` |
|---|---|---|
| kitty | `include ${HOME}/.config/theme/kitty.conf` (kitty.conf) | `kitten @ --to unix:@kitty-<pid> load-config` per instance (sockets from `/proc/net/unix`) |
| niri | `include optional=true "~/.config/theme/niri.kdl"` LAST in config.kdl; sections merge, later wins | `niri msg action load-config-file` |
| herdr | `[theme] name = "terminal"`: every token is an ANSI slot | nothing — kitty reports the bg change via DEC 2031 (`CSI ?997;n`), herdr re-queries OSC 10/11/4 and repaints chrome + every pane |
| nvim | `lua/theme.lua` dofile()s `theme.lua`; catppuccin/bufferline/lualine read it | `nvim --server <sock> --remote-expr` → `require('theme').reload()` per instance |
| fish | `conf.d/colors.fish` sources the fragment; re-sources at the next prompt when the pointer moved | automatic (no universal variables: `fish_variables` is tracked) |
| starship | already ANSI-named; the one `#F47B85` became `red` | follows kitty |
| Claude Code | `theme` key in `~/.claude.json` ← `meta` `claude_code=` | written tmp+rename; takes effect on next start |
| GTK / MacTahoe | **not yet** — stays Dark on every theme (Tom, 2026-09-16) | Phase 4: gsettings ×4 + gtk-4.0 CSS under the pointer; `pkgs/mactahoe-gtk-theme.nix` already builds the Light variants |
| cliamp, zathura, qt6ct | not yet | cliamp 1.63.2 lists only built-in themes (`cliamp theme list`), so its `themes/catppuccin-noir.toml` is inert today |

`Mod+Shift+T` cycles. `theme` prints the current name; `theme list`, `theme apply`
(re-fire hooks), `theme toggle`.

## Testing before a switch

`home/themes/default.nix` is pure (`{ lib }`), so a preview renders without a
generation:

```sh
nix eval --json --impure --expr 'let lib = (builtins.getFlake (toString ./.)).inputs.nixpkgs.lib; in (import ./home/themes { inherit lib; }).fragments' \
  | python3 -c 'import json,sys,os; [ (os.makedirs(os.path.dirname(p:=os.path.expanduser("~/.cache/theme-preview/"+k.split("/",1)[1])),exist_ok=True), open(p,"w").write(v)) for k,v in json.load(sys.stdin).items() ]'
ln -sfn ~/.cache/theme-preview/noir ~/.config/theme
THEMES_DIR=~/.cache/theme-preview theme claude-dark
```

`home.activation.themePointer` re-targets a pointer left outside `~/.config/themes/`
to the live theme of the same name on the next switch.

## Why not

- **Home Manager specialisations**: HM runs as a NixOS module here
  (`flake.nix`, `home-manager.nixosModules.home-manager`), so the base generation
  re-activates at every boot and a specialisation does not survive a reboot; and
  out-of-store symlinks are theme-invariant by construction, so every themed file
  would have to leave the RAW doctrine.
- **matugen / pywal / wallust / stylix**: generators for palettes derived from a
  wallpaper; three fixed palettes need only their *template + include + reload*
  mechanics, which is what `default.nix` + `theme` are.
- **darkman**: two states, no "noir vs claude-dark". Could later *schedule*
  `theme claude-light` / `theme <dark>` by time of day.

## Hazards

- A symlink retarget fires no watcher event: the explicit kitty/niri/nvim reloads
  in `theme` are load-bearing.
- kitty's `dynamic_background_opacity` stays in the RAW kitty.conf: it cannot be
  changed by reload and must be present at startup.
- herdr's in-app settings overlay upserts `[theme] name` and `auto_switch = false`
  into the tracked `config.toml`. Do not use it; `terminal` is the one setting.
- `~/.claude.json` is rewritten by Claude Code itself: the switcher writes tmp+rename
  and accepts a lost update against a running instance. Running agents keep their
  theme until restarted.
- Client laptop: `git pull` ahead of `nixos-rebuild switch` leaves kitty/niri/fish/nvim
  including a pointer that does not exist yet. niri's include is `optional`, nvim's
  loader falls back to noir, fish and kitty fall back to their defaults — degraded,
  not broken — until the switch renders `~/.config/themes/`.
- Kitty windows reload in place; agents' TUIs, GTK4 apps and zathura restart.
