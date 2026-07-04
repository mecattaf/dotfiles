# System Files Decisions

Decisions for the `system_files/` overlay, naming, and build approach. Complements `comparison-handoff.md` (packages/build scripts) and `comparison.yml` (package list).

## Build approach

- **Start from**: fork of ublue-template (NOT zirconium fork)
- **Selectively copy** from zirconium as reference — never wholesale
- **Base image**: `quay.io/fedora/fedora-bootc:44` (same as zirconium)
- **No NVIDIA**: no `BUILD_FLAVOR` arg, no `02-nvidia-*.sh`, no nvidia conditionals in Containerfile or scripts
- **Single arch**: amd64 only. No arm64 matrix.
- **Single flavor**: no flavor matrix at all

## CI/CD — GitHub Actions

### Container image build (`build.yml`)

Based on zirconium's approach (raw `podman build`, cosign signing), simplified:
- **Trigger**: push to main + daily schedule + workflow_dispatch
- **No multi-arch matrix** — amd64 only, single runner
- **No flavor matrix** — no nvidia variant
- **Rechunking**: adopt from zirconium (≤67 layers via bootc-imagectl)
- **Cosign signing**: keep (from zirconium)
- **Registry**: `ghcr.io/mecattaf/harness`
- No multi-arch manifest job (single arch = no manifest needed)

### ISO build (`build-iso.yml`)

- **Schedule**: monthly (1st of month, `0 0 1 * *`) + workflow_dispatch
- **ISO tool**: `osbuild/bootc-image-builder-action` (from zirconium, replaces blueprint's `jasonn3/build-container-installer`)
- **Upload**: GitHub artifact only (30-day retention). No R2. No S3.
- **No ISO branding** with lorax/mkksiso for now (can add later)
- **iso.toml**: point `bootc switch` at `ghcr.io/mecattaf/harness:latest`
- **No GPG signing** of checksums (blueprint had this, unnecessary complexity for personal use)
- **GitHub Release**: optional, keep if ISO < 2GB
- **Going forward**: local `bootc upgrade` for updates, ISO only for fresh installs

### What to drop from blueprint CI/CD
- R2 upload (deprecated)
- GPG checksum signing
- Changelog generation job
- BlueBuild GitHub Action

### What to drop from zirconium CI/CD
- arm64 runner / matrix
- nvidia flavor / matrix
- S3 upload
- ISO branding (lorax/mkksiso/product.img)
- renovate.json5 (use dependabot only)

## Naming convention

All zirconium references become harness. No exceptions.

| Zirconium | Harness |
|---|---|
| `zjust` | `hjust` |
| `zfetch` / `zfetch.sh` | `hfetch` / `hfetch.sh` |
| `zmotd` / `zmotd.sh` | REMOVED entirely |
| `zirconium-qt-override.sh` | `harness-qt-override.sh` |
| `zirconium-font-settings.sh` | `harness-font-settings.sh` |
| `01-zirconium.preset` | `01-harness.preset` |
| `zirconium.preinstall` | `harness.preinstall` |
| `zdots` / `zdots_path` | NOT used — chezmoi points to `github.com/mecattaf/dotfiles` |
| `/usr/share/zirconium/` | `/usr/share/harness/` |
| `~/.config/zirconium/` | `~/.config/harness/` |
| `glorpfetch` | keep name (or rename), but uses `harness.txt` ASCII art |

## Container signing/verification — SKIP

- No `etc/containers/policy.json` (on-device signature enforcement)
- No `etc/containers/registries.d/*.yaml`
- No `.pub` signing keys in `/usr/share/pki/containers/`
- CI-level cosign signing during build is sufficient for now

## Greetd — minimal config

Per `greetd-conclusion.md`. No DMS greeter, no PAM wrappers.

**Keep:**
- `etc/greetd/config.toml` with:
  ```toml
  [terminal]
  vt = 1

  [default_session]
  command = "niri-session"
  user = "yourusername"
  ```

**Remove:**
- `usr/lib/pam.d/greetd-spawn`
- `usr/share/greetd/greetd-spawn.pam_env.conf`
- No greeter sysuser needed (direct user login, no greeter process)

## Systemd presets

**System preset** (`usr/lib/systemd/system-preset/01-harness.preset`):
Enable: auditd, bootc-fetch-apply-updates, brew-setup, firewalld, flatpak-preinstall, greetd, systemd-resolved, systemd-timesyncd, tailscaled, uupd

**User preset** (`usr/lib/systemd/user-preset/01-harness.preset`):
Enable: chezmoi-init, chezmoi-update.timer, fcitx5, gnome-keyring, gcr-ssh-agent, iio-niri, udiskie

Removed from user preset: `dms`, `foot-server`

## Systemd user services

| Service | Status |
|---|---|
| `chezmoi-init.service` | KEEP — change source to `github.com/mecattaf/dotfiles` |
| `chezmoi-update.service` + `.timer` | KEEP — update paths from zirconium to harness |
| `fcitx5.service` | KEEP as-is |
| `iio-niri.service` | KEEP as-is |
| `udiskie.service` | KEEP as-is |
| `dms.service` | REMOVE |
| `foot-server.service` | REMOVE |

## Systemd system services

| Service | Status |
|---|---|
| `flatpak-add-flathub-repos.service` | KEEP |
| `flatpak-preinstall.service` | KEEP |
| `rechunker-group-fix.service` | KEEP |

## Sysusers / tmpfiles

| File | Status |
|---|---|
| `dms-greeter.conf` (sysusers) | REMOVE |
| `99-dms-greeter.conf` (tmpfiles) | REMOVE |
| `resolved-default.conf` (tmpfiles) | KEEP |

## Profile.d scripts

| Script | Status |
|---|---|
| `hfetch.sh` | KEEP — alias fastfetch to hfetch. NO hyfetch binary |
| `fcitx5.sh` | KEEP as-is |
| `harness-qt-override.sh` | KEEP (renamed from zirconium-qt-override.sh) |
| `harness-font-settings.sh` | KEEP (renamed from zirconium-font-settings.sh) |
| `zmotd.sh` | REMOVE |
| `zmotd.fish` | REMOVE |
| `pure.bash` | REMOVE |

## Custom scripts in /usr/bin

| Script | Status |
|---|---|
| `hjust` | KEEP — points to `/usr/share/harness/just/00-start.just` |
| `glorpfetch` | KEEP — calls fastfetch with `harness.txt` art. No hyfetch |
| `rechunker-group-fix` | KEEP |
| `zmotd` | REMOVE |
| `zfetch` (hyfetch wrapper) | REMOVE — hfetch is a profile.d alias to fastfetch only |

## Terminal

- Default terminal: **kitty** (not foot)
- `etc/xdg/xdg-terminals.list` → set kitty
- foot package is still installed (niri ecosystem expects it) but kitty is primary

## Flatpak preinstall

File: `usr/share/flatpak/preinstall.d/harness.preinstall`
Contents defined in `comparison.yml` (Chrome, GearLever, Celeste, Collector, OBS+plugin, Lollypop)

## Justfile (00-start.just)

**Keep only:**
- `toggle-autorotation` — systemctl toggle for iio-niri
- `toggle-fcitx5` — systemctl toggle for fcitx5
- `preinstalled-flatpaks` — flatpak preinstall --reinstall

**Remove:**
- All zdots recipes (zdots-update, zdots-reset, zdots-override-all)
- `toggle-user-motd`
- `toggle-automatic-dotfiles`
- `reset-niri`
- `set-accent-color` / `set-accent-colour`
- `update-greeter`
- `enroll-secure-boot-key`

## Things explicitly NOT included

- No motd / welcome banner of any kind
- No hyfetch binary
- No DMS (dms, dms-greeter, dms-cli, dgop, dsearch)
- No shell prompt theme (pure.bash)
- No fish shell config/greeting from zirconium
- No on-device container signature verification
- No nvidia support
- No zdots — user has own dotfiles at github.com/mecattaf/dotfiles
