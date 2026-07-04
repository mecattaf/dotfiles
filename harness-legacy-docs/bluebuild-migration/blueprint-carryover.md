# Blueprint Carryover

Items from the old blueprint repo that must be ported into harness. Everything else from blueprint is either already captured in `comparison.yml` / `comparison-handoff.md` / `system-files-decisions.md`, or explicitly dropped.

## Fonts pipeline

The `bb-font/` directory contains a standalone font installer extracted from BlueBuild's fonts module. This must be integrated into a harness build script (likely its own `01-theme-fetch.sh` step or similar).

**Mechanism:** `install-fonts.sh` reads `fonts.json` and dispatches to `sources/*.sh`:
- `nerd-fonts.sh` — downloads `.tar.xz` from `github.com/ryanoasis/nerd-fonts/releases/latest` → `/usr/share/fonts/nerd-fonts/`
- `google-fonts.sh` — downloads via Google Fonts API → `/usr/share/fonts/google-fonts/`
- `url-fonts.sh` — downloads zip/tar from arbitrary URLs → `/usr/share/fonts/url-fonts/`

All three run `fc-cache --system-only --really-force` after install.

**Font list** (from `fonts.json`):

Nerd Fonts: DejaVuSansMono, FiraCode, Hack, JetBrainsMono, SourceCodePro, Iosevka, NerdFontsSymbolsOnly, IBMPlexMono

Google Fonts: Roboto, Open Sans, Work Sans, Outfit, Space Grotesk, Inter, IBM Plex Sans

URL Fonts:
- `Apple-SF` — `github.com/mecattaf/San-Francisco-family` (nerd-patched)
- `SFMono-Nerd-Font-Ligaturized` — same repo
- `MapleMono-Variable`, `MapleMonoNormal-Variable` — variable weight
- `MapleMono-TTF`, `MapleMono-TTF-AutoHint`, `MapleMonoNormal-TTF`, `MapleMonoNormal-TTF-AutoHint` — static TTF
- `MapleMono-NF-unhinted`, `MapleMono-NF`, `MapleMonoNormal-NF-unhinted`, `MapleMonoNormal-NF` — Nerd Font patched

**Note:** `comparison.yml` already lists DNF repo fonts (fontawesome, noto, roboto, overpass). The `bb-font/` pipeline is *in addition* to those — it covers fonts not available in Fedora repos.

## kargs

same as bb-fonts, make sure that bb-kargs is preserved for my amd specific setting

### bb-flatpak

make sure to peruse bb-flatpak so that we do not miss any of the functionality that is found 


## YUM repos to carry forward

Copy these `.repo` files into `system_files/etc/yum.repos.d/`:

- **`tailscale.repo`** — `https://pkgs.tailscale.com/stable/fedora/$basearch` (gpgcheck=0)
- **`antigravity.repo`** — `https://us-central1-yum.pkg.dev/projects/antigravity-auto-updater-dev/antigravity-rpm` (gpgcheck=0)

**Drop:**
- `charm.repo` — deployed in blueprint but nothing installs from it
- `leger.repo` — leger package dropped from harness

## DNS config

Copy to `system_files/etc/systemd/resolved.conf.d/99-harness.conf` (renamed from `99-blueprint.conf`):

```ini
[Resolve]
DNSSEC=allow-downgrade
DNSOverTLS=opportunistic
Cache=yes
DNSStubListener=yes
Domains=~.
```

## enable-linger service

Carry forward to `system_files/`. Creates a oneshot service that runs `loginctl enable-linger` for the UID 1000 user at boot.

Needs:
- `usr/lib/systemd/system/enable-linger.service` (the unit file)
- `usr/libexec/enable-linger` (the script — note: blueprint placed this at `usr/etc/libexec/` which is non-standard; use `usr/libexec/` in harness)

Add `enable-linger.service` to the system preset (`01-harness.preset`).

## Polkit rules

Carry forward to `system_files/etc/polkit-1/rules.d/`:

- **`10-udisks2.rules`** — allows `wheel` group to mount filesystems and unlock encrypted devices without password prompt

**Drop:**
- `10-autologin.rules` — was for SDDM autologin, no longer needed with greetd

## Systemd services — what carries from blueprint

Services from blueprint's recipe.yml `systemd` module:

| Service | Status | Notes |
|---|---|---|
| `sddm-boot.service` | DROP | SDDM gone |
| `enable-linger.service` | KEEP | See section above |
| `autologin.service` | DROP | SDDM autologin, gone |
| `tailscaled.service` | KEEP | Already in `01-harness.preset` |
| `legerd.service` | DROP | Leger dropped |
| `systemd-resolved.service` | KEEP | Already in `01-harness.preset` |

## Wayland session desktop entry

**No action needed.** The `niri` package ships `/usr/share/wayland-sessions/niri.desktop` and greetd calls `niri-session` directly. The old `scroll.desktop` is dead.

## SDDM artifacts — all dropped

- `sddm-boot.service`, `autologin.service`
- `sddm-autologin` script, `sddm-useradd` script
- `sddm.conf.d/scroll.conf`, `sddm.conf.d/theme.conf`
- `classic_nocursor` theme (custom OLED SDDM theme)
- `/usr/share/wayland-sessions/scroll.desktop`

## Skel files — NOT carried into system_files

GTK theme config, cursor theme, bookmarks — all previously baked into `/etc/skel/` — are now managed externally via chezmoi (`github.com/mecattaf/dotfiles`). Do not port these.

**Known bugs in blueprint's skel (do not reproduce):**
- Hardcoded `/home/tom/` paths in bookmarks and `.gtkrc-2.0`
- GTK4 `settings.ini` had different theme (Mocha/oomox-Catppuccin-Frappe) vs all other GTK configs (Noir/Catppuccin-SE)

## Explicitly dropped from blueprint

- Claude Code containerfile — not wanted
- DMS from `mecattaf/packages` COPR and `avengemedia/dms` COPR — already decided
- `recipes/packages.yml`, `recipes/vicinae.yml` — were already commented out / dead
- `charm.repo` — unused
- `leger.repo` + `legerd.service` — dropped
- `setup.just` (age USB decrypt + gh auth) — obsolete
- All docs (`docs/`) — outdated
- Brew recommendations — outdated
- Gamescope — not in comparison.yml
- SDDM themes package — not needed
- Benchmarking packages except radeontop — already decided in comparison.yml
- Polkit GUI agents (mate-polkit, lxpolkit, lxqt-policykit, polkit-kde) — not in comparison.yml, only `polkit` daemon kept
- Sway/wlroots packages (azote, grim, mako, rofi-wayland, waybar, etc.) — already decided
- Alacritty — replaced by kitty
- Thunar — replaced by nautilus
- Blueman, pavucontrol, network-manager-applet, firewall-config, remmina, wayvnc, swappy — GUI utilities from sway era, not carried
- `gnuplot`, `pass`, `system-config-printer` — not in comparison.yml
