# Migration Handoff

## What this is

Migrating from a BlueBuild-based Fedora distro (`blueprint-recipes/`) to a bootc container image based on zirconium's architecture. The target is a niri Wayland compositor setup with DMS-free quickshell, personal dotfiles, and a heavy dev/AI/networking stack.

## Source of truth

- **`comparison.yml`** — final consolidated package list with all decisions applied. Every package, COPR repo, and flatpak is listed here. Commented-out entries are intentional (kept for reference or future re-enablement).
- **`blueprint-recipes/`** — the OLD distro config. Do not modify. Reference only.
- **Zirconium build scripts** (`build_files/`, `system_files/`, `Containerfile`) — the architectural template to fork from. Modify these to match `comparison.yml`.

## Architecture

Zirconium is a bootc container image: `Containerfile` → `build_files/*.sh` → `system_files/` overlay. No BlueBuild modules.

```
Containerfile              # multi-stage build, base is quay.io/fedora/fedora-bootc:44
build_files/
  00-base-pre.sh           # dnf remove unwanted base packages
  00-base-fetch.sh         # core system packages + firmware + networking
  01-theme-fetch.sh        # DE, wayland, COPRs, codecs, fonts, dotfiles clone
  01-theme-post.sh         # systemd presets, wallpapers, cleanup
  02-nvidia-fetch.sh       # DELETE — AMD only, no nvidia
  99-misc-fetch.sh         # flathub remote
system_files/              # dropped into / at build time (systemd units, configs, etc.)
```

## Key decisions baked into comparison.yml

- **No DMS** (dms, dms-greeter, dms-cli, dgop, dsearch all removed)
- **No nvidia** — delete `02-nvidia-fetch.sh` and all nvidia references in Containerfile
- **No terra repo** — no maple-fonts from fyralabs. User has own font pipeline (see `blueprint-recipes/fonts.yml`)
- **No hyfetch**
- **Toolbox kept** (do NOT remove in `00-base-pre.sh`), distrobox also kept
- **Polkit**: only `polkit` daemon, no GUI agents
- **Login manager**: greetd + greetd-selinux (replaces sddm)
- **quickshellX-git** from COPR `mecattaf/harnessRPM` (personal fork)
- **Sway/wlroots packages**: commented out in comparison.yml, do not install
- **Chezmoi**: point to user's personal dotfiles repo, not zdots

## COPR repos needed

| COPR | Packages |
|---|---|
| `yalter/niri-git` | `niri` |
| `zirconium/packages` | `matugen`, `iio-niri`, `valent-git` |
| `mecattaf/harnessRPM` | `quickshellX-git` (+ other packages, see comparison.yml) |
| `ublue-os/packages` | `uupd` |
| `mecattaf/duoRPM` | `bibata-cursor-themes`, `wl-gammarelay-rs` |
| `mecattaf/harnessRPM` | `atuin`, `cliphist`, `eza`, `lisgd`, `mactahoe-oled`, `nwg-look`, `starship` (see comparison.yml for commented-out entries) |
| `julianve/open-any-terminal` | `nautilus-open-any-terminal` |

## Packages NOT in zirconium that must be added to build scripts

These come from the blueprint and have no equivalent in zirconium's scripts. They need to be spliced into the appropriate `build_files/*.sh`:

- **Dev tools**: cmake, cpio, fish, gcc, gcc-c++, g++, gh, git-credential-libsecret, git-lfs, make, meson, neovim, p7zip, pandoc, pipx, python3-cairo, python3-pip, ripgrep, uv, yq, zoxide, direnv, dbus-x11, libadwaita
- **Podman**: podman-compose, podman-tui, podmansh
- **Containers**: distrobox (zirconium removed toolbox; we keep both toolbox AND distrobox)
- **Local AI**: ollama, ramalama, whisper-cpp
- **ax-shell python stack**: python3-gobject, python3-ijson, python3-numpy, python3-pillow, python3-psutil, python3-pywayland, python3-ramalama, python3-requests, python3-setproctitle, python3-toml, python3-watchdog, tesseract
- **Networking**: caddy, cockpit + all cockpit-* modules, pcp-zeroconf, systemd-resolved
- **GPU/Graphics**: linux-firmware, mesa-dri-drivers, mesa-libGLU, mesa-vulkan-drivers, vulkan-tools, vulkan-validation-layers
- **Terminals**: kitty, kitty-terminfo (alongside foot)
- **Desktop apps**: imv, vlc, xarchiver, zathura, zathura-pdf-poppler
- **Media**: bluez, bluez-tools, gvfs (base), pamixer, pipewire-alsa, pipewire-jack-audio-connection-kit, pipewire-pulseaudio
- **System**: acpi, age, antigravity, aria2, bolt, sox, unrar-free, wmctrl, ydotool, yt-dlp, NetworkManager-tui, tuned-switcher, tuned-utils, kanshi
- **Portals**: dbus-daemon, dbus-tools, gsettings-desktop-schemas
- **Benchmarking**: radeontop only
- **Fonts/Themes**: fontawesome-fonts-all, gnome-icon-theme, gnome-themes-extra, google-noto-fonts-common, google-noto-sans-fonts, google-roboto-fonts, overpass-fonts, overpass-mono-fonts
- **nautilus-admin**: check if Fedora repos or needs COPR

## Flatpaks

Replace zirconium's preinstall list (`system_files/usr/share/flatpak/preinstall.d/`) with:

```
com.google.Chrome
it.mijorus.gearlever
com.hunterwittenborn.Celeste
it.mijorus.collector
com.obsproject.Studio
com.obsproject.Studio.Plugin.OBSVkCapture
org.gnome.Lollypop
```

## Execution order

1. Containerfile — strip nvidia variant, adjust build args
2. `00-base-pre.sh` — remove toolbox from the remove list
3. `00-base-fetch.sh` — add blueprint-only system packages
4. `01-theme-fetch.sh` — swap COPRs, drop DMS/terra/hyfetch, add new COPRs and packages
5. Delete `02-nvidia-fetch.sh`
6. `system_files/` — chezmoi config (point to personal dotfiles), greeter setup, systemd presets
7. Flatpak preinstall
8. Just recipes if desired

## Additional tasks

The user has additional modification tasks queued (config files, etc.) that will be applied AFTER the package migration is done. Those are tracked separately.
