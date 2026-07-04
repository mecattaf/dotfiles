# Harness Build Plan

## Context

Harness is a personal Fedora 44 bootc image (atomic/immutable Linux distro) for mecattaf. It migrates from a BlueBuild-based distro ("blueprint") to a raw `podman build` approach, using zirconium's architecture as a structural template but not forking it.

**Target**: `ghcr.io/mecattaf/harness` — AMD-only, amd64-only, single-flavor, Niri WM + QuickShell + greetd.

**Source of truth**: `comparison.yml` (packages), `comparison-handoff.md` (migration plan), `system-files-decisions.md` (system files/CI), `blueprint-carryover.md` (items to port).

**Reference repos** (read-only, in `LATEST/`): `blueprint/`, `zirconium/`, `bb-font/`, `bb-kargs/`, `bb-flatpak/`.
NOTE: i am removing the blueprint and zirconium repos from the reference repo but they can be git cloned again if needed:
https://github.com/zirconium-dev/zirconium
https://github.com/leger-labs/blueprint

---

## Step 1: Repository Scaffolding

**Goal**: Create the harness repo directory structure with metadata files.

**Create directory tree**:
```
harness/
  .github/workflows/
  build_files/
  build_files/fonts/          # bb-font pipeline
  build_files/fonts/sources/
  build_files/flatpak/        # bb-flatpak pipeline
  build_files/flatpak/runtime/
  build_files/kargs/          # bb-kargs pipeline
  system_files/
    etc/greetd/
    etc/polkit-1/rules.d/
    etc/profile.d/
    etc/systemd/resolved.conf.d/
    etc/xdg/
    etc/yum.repos.d/
  system_files/usr/bin/
  system_files/usr/lib/systemd/system/
  system_files/usr/lib/systemd/system-preset/
  system_files/usr/lib/systemd/user/
  system_files/usr/lib/systemd/user-preset/
  system_files/usr/lib/tmpfiles.d/
  system_files/usr/libexec/
  system_files/usr/libexec/flatpak-manager/
  system_files/usr/share/harness/
  system_files/usr/share/harness/just/
  system_files/usr/share/flatpak/remotes.d/
  system_files/usr/share/flatpak-manager/
```

**Files**:
- `.gitignore` — adapt from zirconium's, add `output/`, `*.iso`
- `LICENSE` — Apache 2.0 (same as blueprint)
- `cosign.pub` — copy from `LATEST/cosign.pub` (or generate new)

---

## Step 2: System Files — /etc layer

All files under `system_files/etc/`. These are static configs dropped into the image at build time.

### `etc/greetd/config.toml`
Source: `greetd-conclusion.md`
```toml
[terminal]
vt = 1

[default_session]
command = "niri-session"
user = "tom"
```

### `etc/polkit-1/rules.d/10-udisks2.rules`
Source: `blueprint/files/system/usr/etc/polkit-1/rules.d/10-udisks2.rules` — copy verbatim (wheel group mount/unlock)

### `etc/profile.d/fcitx5.sh`
Source: `zirconium/system_files/etc/profile.d/fcitx5.sh` — copy verbatim

### `etc/profile.d/hfetch.sh`
Source: adapt from `zirconium/system_files/etc/profile.d/zfetch.sh`
- Alias `neofetch` and `fastfetch` to `glorpfetch`
- NO hyfetch binary, NO zfetch wrapper

### `etc/profile.d/harness-font-settings.sh`
Source: `zirconium/system_files/etc/profile.d/zirconium-font-settings.sh` — rename only

### `etc/profile.d/harness-qt-override.sh`
Source: `zirconium/system_files/etc/profile.d/zirconium-qt-override.sh` — rename only

### `etc/systemd/resolved.conf.d/99-harness.conf`
Source: `blueprint-carryover.md` DNS config section — copy verbatim (DNSSEC, DoT, cache)

### `etc/xdg/xdg-terminals.list`
Content: `kitty.desktop` (kitty is primary terminal, not footclient)

### `etc/yum.repos.d/tailscale.repo`
Source: `blueprint/files/system/etc/yum.repos.d/tailscale.repo` — copy verbatim

### `etc/yum.repos.d/antigravity.repo`
Source: `blueprint/files/system/etc/yum.repos.d/antigravity.repo` — copy verbatim

---

## Step 3: System Files — Systemd Units & Presets

### System services

**`usr/lib/systemd/system/enable-linger.service`**
Source: `blueprint/files/systemd/system/enable-linger.service`
- ExecStart path: `/usr/libexec/enable-linger` (fix from blueprint's non-standard `/usr/etc/libexec/`)
- After=multi-user.target, before display manager

**`usr/lib/systemd/system/flatpak-add-flathub-repos.service`**
Source: `zirconium/system_files/usr/lib/systemd/system/flatpak-add-flathub-repos.service` — copy verbatim
- ConditionPathExists guard so it runs once

**`usr/lib/systemd/system/rechunker-group-fix.service`**
Source: `zirconium/system_files/usr/lib/systemd/system/rechunker-group-fix.service` — copy verbatim

### System preset: `usr/lib/systemd/system-preset/01-harness.preset`
```
enable auditd.service
enable bootc-fetch-apply-updates.timer
enable brew-setup.service
enable cockpit.socket
enable enable-linger.service
enable firewalld.service
enable greetd.service
enable systemd-resolved.service
enable systemd-timesyncd.service
enable tailscaled.service
enable uupd.timer
```

### User services

**`usr/lib/systemd/user/chezmoi-init.service`**
Source: `zirconium/system_files/usr/lib/systemd/user/chezmoi-init.service`
- Change ConditionPathExists to `!~/.config/harness/chezmoi`
- Change chezmoi init source to `github.com/mecattaf/dotfiles`
- Touch `~/.config/harness/chezmoi` on success

**`usr/lib/systemd/user/chezmoi-update.service`**
Source: `zirconium/system_files/usr/lib/systemd/user/chezmoi-update.service` — copy verbatim (--keep-going)

**`usr/lib/systemd/user/chezmoi-update.timer`**
Source: `zirconium/system_files/usr/lib/systemd/user/chezmoi-update.timer` — copy verbatim (5m boot, 1d interval)

**`usr/lib/systemd/user/fcitx5.service`**
Source: `zirconium/system_files/usr/lib/systemd/user/fcitx5.service` — copy verbatim

**`usr/lib/systemd/user/iio-niri.service`**
Source: `zirconium/system_files/usr/lib/systemd/user/iio-niri.service` — copy verbatim

**`usr/lib/systemd/user/udiskie.service`**
Source: `zirconium/system_files/usr/lib/systemd/user/udiskie.service` — copy verbatim

### User preset: `usr/lib/systemd/user-preset/01-harness.preset`
```
enable chezmoi-init.service
enable chezmoi-update.timer
enable fcitx5.service
enable gnome-keyring-daemon.service
enable gcr-ssh-agent.socket
enable iio-niri.service
enable udiskie.service
```
(Removed vs zirconium: dms.service, foot-server.socket/service)

### Tmpfiles

**`usr/lib/tmpfiles.d/resolved-default.conf`**
Source: `zirconium/system_files/usr/lib/tmpfiles.d/resolved-default.conf` — copy verbatim (symlink resolv.conf to systemd-resolved stub)

---

## Step 4: System Files — Scripts & Branding

### `/usr/libexec/enable-linger`
Source: `blueprint/files/system/usr/etc/libexec/enable-linger`
- Fix path (use `/usr/libexec/` not `/usr/etc/libexec/`)
- Same logic: `loginctl enable-linger` for UID 1000 user

### `/usr/bin/hjust`
Source: adapt from `zirconium/system_files/usr/bin/zjust`
- Point to `/usr/share/harness/just/00-start.just`

### `/usr/bin/glorpfetch`
Source: adapt from `zirconium/system_files/usr/bin/glorpfetch`
- Call fastfetch with `--logo /usr/share/harness/harness.txt`
- No hyfetch

### `/usr/bin/rechunker-group-fix`
Source: `zirconium/system_files/usr/bin/rechunker-group-fix` — copy verbatim

### `/usr/share/harness/harness.txt`
Source: `LATEST/harness.txt` — the ASCII art logo

### `/usr/share/harness/fastfetch.jsonc`
Source: adapt from `zirconium/system_files/usr/share/zirconium/fastfetch.jsonc`
- Replace all zirconium references with harness
- Use harness.txt as logo path

### `/usr/share/harness/just/00-start.just`
Minimal hjust — only 3 recipes:
```just
toggle-autorotation:
    systemctl --user toggle iio-niri.service

toggle-fcitx5:
    systemctl --user toggle fcitx5.service

preinstalled-flatpaks:
    flatpak-manager apply
```
No ublue imports. No zdots recipes. No motd toggle. No accent color. No greeter update.

---

## Step 5: bb-flatpak Integration

Copy and adapt `LATEST/bb-flatpak/` into `build_files/flatpak/`:

### Files to create:
- `build_files/flatpak/install-flatpaks.sh` — from `bb-flatpak/install-flatpaks.sh`, verbatim
- `build_files/flatpak/flatpaks.json` — from `bb-flatpak/flatpaks.json`, verbatim (Chrome, GearLever, Celeste, Collector, OBS+plugin, Lollypop)
- `build_files/flatpak/runtime/user-flatpak-setup` — verbatim
- `build_files/flatpak/runtime/user-flatpak-setup.service` — verbatim
- `build_files/flatpak/runtime/user-flatpak-setup.timer` — verbatim
- `build_files/flatpak/runtime/flatpak-manager` — verbatim

These files are self-contained. The `install-flatpaks.sh` is called during the build (from 01-theme-post.sh or 99-misc-post.sh) and installs the systemd user timer + CLI tool into the image.

---

## Step 6: bb-font Integration

Copy and adapt `LATEST/bb-font/` into `build_files/fonts/`:

### Files to create:
- `build_files/fonts/install-fonts.sh` — from `bb-font/install-fonts.sh`, verbatim
- `build_files/fonts/fonts.json` — from `bb-font/fonts.json`, verbatim
- `build_files/fonts/sources/nerd-fonts.sh` — verbatim
- `build_files/fonts/sources/google-fonts.sh` — verbatim
- `build_files/fonts/sources/url-fonts.sh` — verbatim

Called from `01-theme-fetch.sh` during the build.

---

## Step 7: bb-kargs Integration

Copy and adapt `LATEST/bb-kargs/` into `build_files/kargs/`:

### Files to create:
- `build_files/kargs/set-kargs.sh` — from `bb-kargs/set-kargs.sh`, verbatim
- `build_files/kargs/kargs.json` — from `bb-kargs/kargs.json`, verbatim (`amd_iommu=off`, ttm limits)

Called from the Containerfile or a build script.

---

## Step 8: Build Scripts

All scripts in `build_files/`. These run inside the container during `podman build`.

### `00-base-pre.sh`
Source: adapt from `zirconium/build_files/00-base-pre.sh`
**Remove these packages** (from comparison.yml header):
```
firefox firefox-langpacks virtualbox-guest-additions nvtop sway yggdrasil
adcli libdnf-plugin-subscription-manager python3-subscription-manager-rhsm
subscription-manager subscription-manager-rhsm-certificates
```
Also remove from zirconium's list: `console-login-helper-messages chrony sssd*`
**Do NOT remove**: toolbox (explicitly kept)
Enable keepcache.

### `00-base-fetch.sh`
Source: adapt from `zirconium/build_files/00-base-fetch.sh`, heavily expanded per comparison.yml

**Package groups** (all from comparison.yml "DNF PACKAGES" sections):
- Networking: all NetworkManager-* plugins, tailscale, wireguard-tools, whois, vpnc, openconnect, mobile-broadband-provider-info
- Networking extras: caddy, cockpit, cockpit-machines, cockpit-networkmanager, cockpit-podman, cockpit-selinux, cockpit-storaged, cockpit-system, pcp-zeroconf, systemd-resolved
- Firmware: alsa-firmware, alsa-tools-firmware, atheros-firmware, brcmfmac-firmware, intel-audio-firmware, iwlegacy/iwlwifi-*, kernel-modules-extra, mt7xxx, nxpwireless, realtek, tiwilink
- Media hardware: alsa-sof-firmware, bluez, bluez-tools, gvfs, gvfs-mtp, pamixer, pipewire + alsa + jack + pulseaudio, wireplumber
- Camera: libcamera, libcamera-gstreamer, libcamera-tools, libcamera-v4l2
- Printing: cups, cups-pk-helper, dymo-cups-drivers, hplip, printer-driver-brlaser, ptouch-driver, system-config-printer-libs, system-config-printer-udev
- Filesystem/iOS: cifs-utils, fuse, fuse-common, gvfs-archive, gvfs-nfs, gvfs-smb, ifuse, jmtpfs, libimobiledevice, libimobiledevice-utils
- Virtualization: hyperv-daemons, open-vm-tools, open-vm-tools-desktop, qemu-guest-agent, spice-vdagent, systemd-container
- Security: audispd-plugins, audit, firewalld, fprintd, fprintd-pam, gnome-keyring-pam, gnupg2-scdaemon, openssh-askpass, pam_yubico, pcsc-lite, ykman
- GPU: linux-firmware, mesa-dri-drivers, mesa-libGLU, mesa-vulkan-drivers, vulkan-tools, vulkan-validation-layers
- System core: acpi, age, antigravity, aria2, bolt, dnf5-command(config-manager), flatpak, fpaste, fwupd, fzf, gcr, git-core, gum, just, khal, libratbag-ratbagd, man-db, man-pages, plymouth, plymouth-system-theme, rsync, switcheroo-control, systemd-oomd-defaults, tuned, tuned-ppd, tuned-switcher, tuned-utils, unzip, usb_modeswitch, uxplay, zram-generator-defaults
- System extras: sox, unrar-free, wmctrl, ydotool, yt-dlp

### `00-base-post.sh`
Source: adapt from `zirconium/build_files/00-base-post.sh`
- Copy all `system_files/` into root filesystem: `cp -r /ctx/system_files/* /`
- Configure uupd.service (disable distrobox module)
- Configure bootc-fetch-apply-updates (quiet, 7-day timer)
- Configure rpm-ostreed (AutomaticUpdatePolicy=stage, LockLayering=true)
- Enable all system services from preset (run `systemctl enable` for each)

### `01-theme-fetch.sh`
Source: adapt from `zirconium/build_files/01-theme-fetch.sh`, heavily modified

**Add COPR repos**:
```
yalter/niri-git
zirconium/packages          # for matugen, iio-niri, valent-git
ublue-os/packages           # for uupd
mecattaf/duoRPM
mecattaf/harnessRPM
julianve/open-any-terminal
```

**Add YUM repos** (already in system_files, but also via `dnf config-manager`):
- negativo17 fedora-multimedia (for codecs)

**COPR packages**:
niri, iio-niri, matugen, valent-git, quickshellX-git, uupd, bibata-cursor-themes, wl-gammarelay-rs, atuin, cliphist, eza, lisgd, mactahoe-oled, nwg-look, starship, nautilus-open-any-terminal

**DNF packages** (grouped):
- Wayland env: brightnessctl, kanshi, playerctl, webp-pixbuf-loader, wl-clipboard, wtype
- Niri core: foot, xdg-desktop-portal-gnome, xdg-terminal-exec, xwayland-satellite
- Login: greetd, greetd-selinux
- Qt theming (--setopt=install_weak_deps=False): kf6-kimageformats, kf6-kirigami, kf6-qqc2-desktop-style, plasma-breeze, qt6ct, qt6-qtmultimedia
- Polkit: polkit
- Codecs: ffmpeg, ffmpegthumbnailer, gstreamer1-plugins-*, lame, lame-libs, libavcodec, libjxl, @multimedia
- Desktop apps: cava, chezmoi, ddcutil, fastfetch, glycin-thumbnailer, input-remapper, nautilus-python, orca, wl-mirror, gnome-disk-utility, gnome-keyring, imv, kitty, kitty-terminfo, nautilus, udiskie, vlc, xarchiver, zathura, zathura-pdf-poppler
- Input: fcitx5-mozc, ibus
- Fonts (DNF): default-fonts, default-fonts-core-emoji, fontawesome-fonts-all, glibc-all-langpacks, gnome-icon-theme, gnome-themes-extra, google-noto-color-emoji-fonts, google-noto-emoji-fonts, google-noto-fonts-common, google-noto-sans-fonts, google-roboto-fonts, overpass-fonts, overpass-mono-fonts
- Portals: dbus-daemon, dbus-tools, gsettings-desktop-schemas, xdg-desktop-portal-gtk, xdg-user-dirs
- Dev tools: cmake, cpio, dbus-x11, direnv, fish, g++, gcc, gcc-c++, gh, git-credential-libsecret, git-lfs, libadwaita, make, meson, neovim, p7zip, pandoc, pipx, python3-cairo, python3-pip, ripgrep, uv, yq, zoxide
- Podman: podman-compose, podman-tui, podmansh
- Local AI: ollama, ramalama, whisper-cpp
- ax-shell deps: python3-gobject, python3-ijson, python3-numpy, python3-pillow, python3-psutil, python3-pywayland, python3-ramalama, python3-requests, python3-setproctitle, python3-toml, python3-watchdog, tesseract
- Benchmarking: radeontop

**Run font pipeline**:
```bash
bash /ctx/build_files/fonts/install-fonts.sh
```

### `01-theme-post.sh`
Source: adapt from `zirconium/build_files/01-theme-post.sh`
- Create `/usr/share/harness/` directory
- Remove fcitx5 desktop launchers from `/usr/share/applications/`
- Modify greetd PAM: add `pam_gnome_keyring.so` to auth and session
- Enable user systemd services globally (from user preset)
- Rebuild font cache: `fc-cache --system-only --really-force`
- Generate hjust shell completions (bash/zsh/fish)
- Run bb-flatpak installer: `bash /ctx/build_files/flatpak/install-flatpaks.sh`

### `99-misc-fetch.sh`
Source: adapt from `zirconium/build_files/99-misc-fetch.sh`
- Add flathub remote to system flatpak: download `.flatpakrepo` to `/usr/share/flatpak/remotes.d/`

### `99-misc-post.sh`
Source: adapt from `zirconium/build_files/99-misc-post.sh`
- Set hostname: `harness`
- Modify `/usr/lib/os-release`:
  - NAME="Harness"
  - No VERSION_CODENAME
  - HOME_URL=https://github.com/mecattaf/harness
  - BUG_REPORT_URL=https://github.com/mecattaf/harness/issues
  - SUPPORT_URL=https://github.com/mecattaf/harness
  - Remove VARIANT_ID, REDHAT_* fields
- Disable Fedora flatpak remote service, enable flathub
- Remove chsh binary
- Enable rechunker-group-fix service
- Verify critical files exist (uupd, systemd units)
- Create `/usr/local` → `/var/usrlocal` and `/opt` → `/var/opt` symlinks

### `99-dracut.sh`
Source: `zirconium/build_files/99-dracut.sh` — copy verbatim
- Generate initramfs with ostree support, reproducible, zstd compression

---

## Step 9: Containerfile

Source: adapt from `zirconium/Containerfile`, heavily simplified.

### Context stage (FROM scratch AS ctx)
```dockerfile
COPY build_files /ctx/build_files
COPY system_files /ctx/system_files
COPY cosign.pub /ctx/cosign.pub
```

### Brew import (FROM ublue-os/brew AS brew)
Copy brew system files for brew-setup.service.

### Main stage (FROM quay.io/fedora/fedora-bootc:44)
```
--mount=type=bind,from=ctx,src=/ctx,dst=/ctx
--mount=type=bind,from=brew,src=/...,dst=/ctx/brew_files

RUN bash /ctx/build_files/00-base-pre.sh
RUN bash /ctx/build_files/00-base-fetch.sh
RUN bash /ctx/build_files/00-base-post.sh
RUN bash /ctx/build_files/01-theme-fetch.sh
RUN bash /ctx/build_files/01-theme-post.sh
RUN bash /ctx/build_files/kargs/set-kargs.sh
RUN bash /ctx/build_files/99-misc-fetch.sh
RUN bash /ctx/build_files/99-misc-post.sh
RUN bash /ctx/build_files/99-dracut.sh

# Cleanup
RUN rm -rf /var/* && mkdir -p /var/tmp
RUN bootc container lint
```

**Not included**: nvidia stages, arm64 conditionals, BUILD_FLAVOR arg, multi-stage nvidia compilation.

**Labels**: OCI standard (description, source, vendor, version) + bootc containers.bootc=1.

---

## Step 10: GitHub Actions

### `.github/workflows/build.yml`
Source: adapt from `zirconium/.github/workflows/build.yml`, simplified.

- **Trigger**: push to main + daily schedule + workflow_dispatch
- **No matrix**: single job (no flavor, no platform matrix)
- **Runner**: ubuntu-24.04
- **Steps**:
  1. Checkout
  2. BTRFS mount for container storage (from zirconium)
  3. `podman build -t ghcr.io/mecattaf/harness:latest -f Containerfile .`
  4. Rechunk via bootc-base-imagectl (max 67 layers)
  5. Push to GHCR (with tag: latest + date-based)
  6. Cosign sign

### `.github/workflows/build-iso.yml`
Source: adapt from `system-files-decisions.md` CI/CD section + zirconium's workflow.

- **Trigger**: monthly (1st of month) + workflow_dispatch
- **ISO tool**: `osbuild/bootc-image-builder-action`
- **Upload**: GitHub artifact (30-day retention)
- **Optional**: GitHub Release if ISO < 2GB
- **No**: R2, GPG signing, branding/lorax, changelog generation

### `iso.toml`
```toml
[customizations.installer.kickstart]
contents = """
%post
bootc switch --mutate-in-place --transport registry ghcr.io/mecattaf/harness:latest
%end
"""

[customizations.installer.modules]
enable = ["Storage", "Runtime", "Network", "Security", "Services", "Users", "Timezone"]
disable = ["Subscription"]
```

No `iso-nvidia.toml`.

---

## Step 11: README

Brief README with:
- What harness is (one paragraph)
- Installation (bootc switch command + ISO)
- Key specs (Fedora 44, Niri, greetd, kitty, AMD-only)
- Link to comparison.yml for full package list
- Build instructions (podman build)
- License (Apache 2.0)

---

## Execution Sequence for Agents

Each step below is a self-contained unit of work for one Claude Code Opus agent session:

| Order | Step | Dependencies | Est. Files |
|-------|------|-------------|------------|
| 1 | Scaffolding (dirs, .gitignore, LICENSE, cosign.pub) | None | 3 |
| 2 | System files: /etc layer | Step 1 | 11 |
| 3 | System files: systemd units & presets | Step 1 | 12 |
| 4 | System files: scripts & branding | Step 1 | 7 |
| 5 | bb-flatpak integration | Step 1 | 6 |
| 6 | bb-font integration | Step 1 | 5 |
| 7 | bb-kargs integration | Step 1 | 2 |
| 8 | Build scripts (all 8 .sh files) | Steps 2-7 | 8 |
| 9 | Containerfile | Step 8 | 1 |
| 10 | GitHub Actions + iso.toml | Step 9 | 3 |
| 11 | README | Step 10 | 1 |

Steps 2-7 can potentially run in parallel (no interdependencies), but sequential is safer for agents.

---

## Verification

After all steps complete:

1. **Lint**: `podman build --no-cache -t harness:test .` locally (or dry-run review)
2. **File tree**: verify all expected files exist with correct paths
3. **Systemd presets**: grep for all expected services in both presets
4. **Package coverage**: diff comparison.yml packages against build scripts to ensure nothing is missing
5. **No zirconium references**: `grep -r "zirconium\|zdots\|zmotd\|zfetch\|zjust" .` should return zero hits (except in comments referencing the source)
6. **No removed items**: grep for DMS, nvidia, sway, SDDM, hyfetch, distrobox, steam — none should appear in active (non-commented) lines
7. **bb-flatpak**: verify `user-flatpak-setup.timer` is globally enabled at build time
8. **bb-font**: verify fonts.json lists all expected font families
9. **bb-kargs**: verify kargs.json has amd_iommu=off and ttm limits
