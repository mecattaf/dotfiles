# Harness sweep (preliminary) — system layer

Disposition of every item in the `harness` repo, file by file. Annotate inline
or reply with commentary; ratified calls fold into `nix-decisions.md`.

Legend:
`✅` nixpkgs (SAME — just reference) ·
`🔧` overlay / source-build (ex-COPR bespoke) ·
`⚙️` NixOS/home-manager **option** (config, not a raw package) ·
`⭐` NEW (Nix-native: secrets / per-device / quadlet / my own module) ·
`❌` GONE (delete — reductive, or Fedora/image-ism with no meaning in Nix) ·
`⏳` **DECIDE — needs your call**

---

## `mkosi.conf` — image builder config
`❌` entirely. Profiles, `SecureBoot=no`, `RuntimeSize`, `ImageId`, the ASCII art
— all mkosi/bootc build machinery. Replaced by `flake.nix` + the NixOS config.
Carry-overs: `ImageId=harness` → `networking.hostName`; `SecureBoot=no` → Phase-4
note (lanzaboote is an upgrade, not parity).

## `mkosi.conf.d/harness-desktop.conf`

**`RemovePackages` / `RemoveFiles`** → `❌` N/A. Nix is additive; you never
"remove from base," you just don't include. (alacritty, fuzzel, mako, waybar,
sway, swayidle, swaylock, PackageKit, firefox, virtualbox-guest-additions,
nvtop, subscription-manager*, chrony, console-login-helper-messages, chsh,
fcitx5 desktop files — all simply absent unless re-added on purpose.)
*Note:* you removed mako+waybar here but nix-test re-added mako/rofi — so "do we
run a notification daemon / launcher at all" is a real `⏳` (see niri config later).

**`Packages` — dispositions:**
- `✅` nixpkgs (straight references): acpi, aria2, brightnessctl, cava, ddcutil,
  fastfetch, foot, fpaste, fzf, gcr, gnome-disk-utility, imv, kanshi, khal,
  nautilus(+python), pamixer, radeontop, sox, unrar-free, vlc, vulkan-tools,
  webp-pixbuf-loader, wl-clipboard, wl-mirror, wmctrl, wtype, xarchiver,
  xdg-terminal-exec, xdg-user-dirs, xwayland-satellite, yt-dlp, zathura(+pdf-poppler),
  nano, ncurses, openssh-askpass, glycin/gst thumbnailers.
- `⚙️` become module options, not packages:
  greetd(+selinux→drop selinux) → `services.greetd`; pipewire/wireplumber/
  pipewire-{alsa,jack,pulse} → `services.pipewire`; bluez(+tools) →
  `hardware.bluetooth`; bolt → `services.hardware.bolt`; gnome-keyring(+pam)/gcr
  → `services.gnome.gnome-keyring` (+gcr-ssh-agent); cockpit* →
  `services.cockpit`; tailscale → `services.tailscale`; polkit →
  `security.polkit`; gvfs → `services.gvfs`; udiskie → user service / udiskie;
  ydotool → `programs.ydotool`; xdg-desktop-portal-{gnome,gtk} → `xdg.portal`;
  flatpak → `❌` (dropped); xorg-x11-server-Xwayland → `xwayland`.
- `⭐` per-device (graphics): mesa-dri-drivers, mesa-vulkan-drivers, libva,
  **libva-intel-media-driver** (Intel-only!), libcamera → `hardware.graphics`,
  split Intel vs AMD per host.
- fonts (default-fonts*, fontawesome*, google-noto*, google-roboto, overpass*) →
  `❌` collapse to your font rule (see fonts.json below).
- `❌` GONE: chezmoi (→ home-manager), flatpak (→ nixpkgs google-chrome).
- `⏳` **DECIDE** (keep or drop — I suspect several are unused):
  - `fcitx5-mozc` + `ibus` — Japanese/Asian input method. Use it?
  - `ykman` — `❌` (no YubiKey) unless you tell me otherwise.
  - `gnupg2-scdaemon` — GPG smartcard daemon; only useful with a smartcard/YubiKey → likely `❌`.
  - `input-remapper` — key/button remapping GUI. Use it?
  - `steam-devices` — gaming controller udev. Gaming on these boxes?
  - `orca` — screen reader. Need it?
  - `age` — `✅` KEEP (it's a secrets/sops tool).
  - `qt6ct` + `qt6-qtmultimedia` — Qt theming/codec; keep (`⚙️` + env var).
  - `steam-devices`, `caddy` (reverse proxy — server role? keep for harness host?).

## `mkosi.conf.d/harness-devtools.conf`
- `✅` nixpkgs: cmake, cpio, dbus-x11, direnv, gcc/gcc-c++, gh,
  git-credential-libsecret, git-lfs, libadwaita, make, meson, p7zip, pandoc,
  ripgrep, uv, yq, zoxide, distrobox, podman-compose, podman-tui, whisper-cpp,
  tesseract. neovim → `✅` + **lazy-nix-helper** (decided).
- `⚙️`: fish → `programs.fish`; podman/podmansh → `virtualisation.podman`.
- python3-{cairo,gobject,ijson,numpy,pillow,psutil,pywayland,requests,
  setproctitle,watchdog} → `✅` one `python3.withPackages` bundle (backs the niri
  helper scripts).
- `❌` GONE: copr-cli (no COPR), pipx (uv/uvx covers it — already dropped).
- `⏳` **DECIDE**: toolbox (distrobox covers it — drop?); ramalama +
  python3-ramalama (container LLM runner — june18 leaned native llama.cpp +
  llama-swap on Strix Halo; keep ramalama as the easy path, or drop?).

## `mkosi.conf.d/harness-codecs.conf`
- `❌` the **fedora-multimedia repo** entirely — nixpkgs ffmpeg is full/unfree-
  capable, no third-party repo needed.
- `✅` ffmpeg(-full), ffmpegthumbnailer, gst_all_1.* (bad/base/good), lame,
  libavcodec(in ffmpeg), libjxl. (SAME, just no repo plumbing.)

## `mkosi.conf.d/harness-copr.conf` — **harnessRPM preview (it collapses here)**
- `✅` → already in nixpkgs (delete the spec): atuin, cliphist, eza, kitty,
  lisgd, nwg-look, shpool, starship, wl-gammarelay-rs, bibata-cursor-themes(→`bibata-cursors`).
- `🔧` → overlay source-builds (the genuinely bespoke): **mactahoe-oled ✅ DONE**,
  asr-rs, cliamp, gws.
- `pi` → via `lukasl-dev/pi.nix` / `numtide/llm-agents.nix` (decided).
- `❌` quickshellX-git — shell not used.

## `mkosi.conf.d/harness-extra-repos.conf`
- `✅` cloudflared (nixpkgs).
- `❌` tailscale repo (tailscale in nixpkgs), libxcrypt-compat (compat shim, N/A).
- `⏳` **antigravity** (Google Antigravity IDE) — the one real remaining
  packaging cost (`🔧` prebuilt Electron from a yum repo). Still want it?

## `mkosi.conf.d/niri-git.conf`
- niri (git via yalter COPR) → `⭐` **niri-flake** (sodiboo) for niri-git, OR
  `programs.niri.enable` for nixpkgs stable. **Leaning niri-flake** (you ran
  bleeding-edge). `⏳` the **KDL config rung** (raw file / typed settings) is the
  open one from the decisions doc.

## `mkosi.conf.d/non-rawhide.conf` + `norecommends.conf`
- `❌` updates-testing repo (N/A — nix channels).
- `✅` just (nixpkgs). Qt/KDE theming kf6-{kimageformats,kirigami,
  qqc2-desktop-style} + plasma-breeze → `✅` (for Qt-app consistency under niri).
- `⏳` **hjust** — the harness `just`-based system menu (wrapper + completions +
  `00-start.just`). Survives, gets rewritten, or dies? (nix-test open q.)

## `mkosi.conf.d/subprojects.conf` (ExtraTrees)
- `❌` ublue-brew (brew dropped); rechunker (ostree-ism).
- `⭐` luks-tpm2-autounlock → Phase 4 (secure boot/TPM), defer.
- `⭐` dotfiles → the whole home-manager migration.
- `⏳` ublue-os/just → tied to the hjust decision.

## `mkosi.conf.d/terra.conf`
- `❌` terra repo (no third-party repo).
- `✅` nautilus-open-any-terminal, xdg-terminal-exec-nautilus (`⏳` want the
  nautilus "open terminal" integration?).
- `🔧`/`⭐` **iio-niri** — screen auto-rotate daemon (Terra-only). Relevant for
  the **Zenbook Duo** tablet/tent mode; useless on the desktops → per-device
  `⏳` (package in pkgs/ for the Duo, or drop?).
- `⏳` **valent** (KDE-Connect / phone integration) — nixpkgs has it. Want it?

## `mkosi.conf.d/ublue-os-packages.conf`
- `❌` uupd — auto-updates become `system.autoUpgrade` (paired with nothing now
  that flatpak's gone).

## `mkosi.conf.d/fonts.json` → **collapse per your rule**
Keep only:
- `✅` **Maple Mono (ligaturized Nerd)** → nixpkgs `maple-mono.NF` (the
  Nerd-patched variant; Maple ships ligatures by default).
- `✅` **JetBrains Mono Nerd** fallback → `nerd-fonts.jetbrains-mono`.
- `✅` **noto-color-emoji** → keep (nothing renders emoji without it).
`❌` everything else: Apple-SF / SFMono-Liga (the url-fonts you self-host), the
other 11 Maple variants, the 7 other nerd fonts, all 7 google fonts, overpass,
roboto. (Re-add a UI sans only if something looks wrong.)

## `mkosi.extra/**` + `mkosi.postinst.chroot` — system config & build hacks
- `⚙️` keep as NixOS options (nix-test already modeled most): greetd config +
  PAM (keyring unlock, `XDG_SESSION_TYPE=wayland`), qt/font `profile.d` →
  `environment.sessionVariables`, xdg-terminals.list, udisks2 polkit rule,
  enable-linger → `users.users.tom.linger`, os-release branding →
  `system.nixos.distroName="Harness"`, wallpaper asset.
- `⭐` **coordinator host role (per-device, coordinator only):** the router plane —
  `99-router.conf` sysctl, `dns-hijack.nft`, dnsmasq-shared drop-ins (AdGuard +
  BE550 pin), resolved.conf.d; the **NAS CIFS** mount/automount; kargs.
- `⭐` **quadlets → quadlet-nix** (harness host, Phase 2): adguard, immich(+pg/
  redis/ml), navidrome.
- `❌` GONE: chezmoi-init/update services+timer (→ home-manager), flatpak
  preinstall/flathub services, rechunker-group-fix, brew (homebrew.tar.zst +
  brew-setup), cosign/policy.json/registries.d (image signing → cache signing),
  google-cloud-cli `--noscripts` hack (nixpkgs google-cloud-sdk), terra gpg sed,
  fc-cache (automatic), dracut passkeys.conf (FIDO2 — no YubiKey).
- `⏳` `dracut/lvm2.conf` → disko/hardware (Phase 3/4); `iio-niri.service`,
  `fcitx5.service` user units → tied to the iio-niri / fcitx5 decisions above.

---

## RESOLVED (your commentary, 2026-06-19)

- ❌ **Input method** — fcitx5-mozc, ibus, fcitx5.sh, fcitx5 service: drop (no CJK).
- ❌ **YubiKey/smartcard** — ykman, pam_yubico, pcsc-lite: drop. gnupg2-scdaemon:
  no action (ships w/ gnupg, inert w/o smartcard). passkeys.conf fido2/pkcs11:
  drop; TPM2 path kept for Phase-4 (`luks-tpm2-autounlock`).
- ❌ **Suspects** — input-remapper, steam-devices, orca (screen reader), toolbox: drop.
- ❌ **ramalama** drop. ☑️ **podman + quadlets KEEP** (host services). ⏳ distrobox
  (no doc decision found; lean drop unless used for non-Nix envs).
- ❌ **antigravity** drop.
- ❌ **just / hjust / gum / ublue-os just trees / 00-start.just / completions** —
  kill entirely (hjust = renamed ujust system menu; Justfile = mkosi build, gone).
- ❌ **iio-niri** don't package.
- ✅ **nautilus-open-any-terminal + xdg-terminal-exec-nautilus** keep. ❌ **valent** drop.
- ☑️ **niri** → niri-flake. ⚠️ **SUPERSEDED 2026-06-20:** rung was typed
  `programs.niri.settings` here, but the dotfiles sweep ruled **RAW for now**
  (hot-reload; typed kept as a later candidate). See `nix-decisions.md` niri row.
- ❌ **bar + notifications** — drop mako/waybar/bar-toggle; stay bar-less &
  notification-less (own shell later).
- ✅ **gcloud** → nixpkgs `google-cloud-sdk`. ✅ **gh** keep.
- ⚠️ **gws** → NOT nixpkgs `gws` (that's a different "git workspace" tool); the
  Google Workspace CLI needs the **overlay source-build** or a prebuilt binary.
- ✅ **fonts** → `maple-mono` (single pkg, all variants) + `nerd-fonts.jetbrains-mono`
  + **keep google-fonts set** + noto-color-emoji. (Nautilus UI font safe — covered
  by google/noto sans.) Drop Apple-SF/SFMono self-hosted + the rest.
- ✅ **codecs** keep (ffmpeg-full + gstreamer; fedora-multimedia repo gone).
- ✅ **cloudflared** → `services.cloudflared`. ✅ **tailscale** → `services.tailscale`
  (no timer ever existed; service is the parity) + authKeyFile via sops.
- ☑️ **gnome-keyring login unlock** keep → `security.pam.services.greetd.enableGnomeKeyring`.
- ☑️ **container policy.json** → Nix defaults (cosign image-verify was bootc-only).
- ❌ **kf6-* + plasma-breeze** drop (no KDE/Kirigami apps; qt6ct covers Qt theming).
- ❌ **libxcrypt-compat** N/A. ☑️ **cifs-utils** keep (NAS).
- ⏳ **fgp-browser** (harnessRPM) — investigate: overlay as-is vs own wrapper.
- ☑️ **microsandbox → microvm.nix** (the nix-native shape).

### `mkosi.profiles` (zirconium-inherited) — mostly auto/gone
- ❌ **VM guest agents** (open-vm-tools, hyperv-daemons, qemu-guest-agent,
  spice-vdagent, WALinuxAgent) — bare metal, drop all.
- ⚙️ **~12 firmware pkgs** → one line `hardware.enableRedistributableFirmware`.
- ❌ **`fedora-bootc-ostree/*`** (dnf5, dracut-*, efibootmgr, ostree, zram-generator,
  rechunk, bootloader/firmware confs) — bootc machinery, gone.
- ❌ **`others.conf` base** (sudo, tar, cryptsetup, lvm2, nftables, shadow-utils,
  e2fsprogs, jq, less, iproute…) — NixOS base system, not listed.
- ⚙️ keep: plymouth, zram (8 GiB cap), fwupd, NetworkManager (core), cifs-utils,
  `power-profiles-daemon` (replaces tuned/tuned-ppd).
- ⏳ remaining real per-device calls: **printing** (cups/hplip — do you print?),
  **NetworkManager VPN plugins** (which VPNs?), **fprintd** (Zenbook Duo reader?),
  **thermald + libva-intel-media-driver** (Intel hosts only), `switcheroo-control`
  (drop, not dual-GPU).

## mkosi.extra + cluster (resolved 2026-06-20)

**Key reframe:** the empty `firewalld/zones` + `system-connections` dirs are
**runtime state** (set live via `firewall-cmd`/`nmcli`, never committed) — NixOS
makes them **declarative**. Same for the ds4 headless-worker access saga
(no-password/locked-root/hand-pasted key): declarative `authorized_keys` + TB
static IP + firewall trust from first boot makes it disappear.

### common.nix (all hosts) — `⚙️`
greetd + PAM (greetd-greeter, `enableGnomeKeyring`), polkit-1 (udisks2 rule),
base sysctl.d, xdg, NetworkManager core, enable-linger → `users.users.tom.linger`,
plymouth, zram (8 GiB), **fprintd (all devices — upgraded)**, presets → per-service
`enable`. profile.d → `environment.sessionVariables` (keep font-settings + qt6ct;
drop fcitx5.sh). resolved-default tmpfiles → `services.resolved`.

### AMD-Strix only (`coordinator` + `worker`) — `⭐`
<!-- NAMING RULE (final): the AMD pair is `coordinator` (main) + `worker` (compute).
     The names `companion` AND `sodimo` NEVER appear in nix config — both dead. -->

- Router plane: adguard, dns-hijack nftables, dnsmasq-shared (be550 pin),
  resolved adguard drop-in, **NAS mount** (⚠️ verify share name: audit shows
  `//10.42.0.2/G`, nix-test wrongly had `/LaCie`).
- **Thunderbolt cluster** (from report-thunderbolt-connection.md +
  ds4-dual-node-lessons.md): static `thunderbolt0` IPs 10.77.0.1/.2 (NM profile,
  persistent) + split-horizon `networking.hosts` (`coordinator`/`worker`) +
  `networking.firewall.trustedInterfaces = ["thunderbolt0"]` **on BOTH nodes**
  (kv-disk offload dials inbound bidirectionally) + bolt auto-auth.
- **ds4 / LLM cluster** → quadlet-nix units (the docs' "TODO: systemd units").
  Quadlet `--coordinator`/`--listen`/`--role worker --coordinator` args use the
  **static 10.77.0.x IPs**, NOT the link-local `169.254.x` hardcoded in the
  runbook. **Appendix A resolved on NixOS:** with the worker's `thunderbolt0`
  declaratively trusted from first boot, the `--kv-disk-dir` bidirectional-dial
  wedge can't happen → **disk-KV offload is safe to re-enable** (the locked-root
  locked-root worker dead-end that forced dropping it is gone).
- mnt-nas, dns-hijack, var-mnt-nas units, kargs → here, not common.

### Intel only (`zenbook-duo`, `dell-xps`) — `⭐`
thermald + libva-intel-media-driver.

### Drop / N/A
- `99-no-nsresourced.preset` → Fedora/bootc tweak, N/A (confirm).
- usr/bin (hjust, rechunker-group-fix) → gone; `ocr`+scripts → dotfiles.
- adguard.network 10-byte stub, `DB_PASSWORD=changeme`, hardcoded NAS creds →
  fixed as proper Nix options / **sops secrets**.
- empty stubs (sysusers.d, share/fish, share/pki/containers, system-connections,
  firewalld/zones) → don't reproduce.

### Assets
- **wallpaper.jpg** — keep the name; place ONCE via home-manager (resolves the
  chezmoi-vs-system overlap → one source of truth). swaybg points at it.
- containers/systemd quadlets → quadlet-nix (AMD-Strix host).

### Docs
- `docs/` → renamed `harness-legacy-docs/`. Three parts: onboarding (login steps
  compress hugely via secrets), network-services (interesting avenues),
  bluebuild-migration (the PRIOR blue-build→mkosi migration logs; historical).

---

## ORIGINAL open calls (now mostly resolved above)

1. **Input method** — fcitx5-mozc + ibus + fcitx5 units: keep (you type
   Japanese/CJK) or drop entirely?
2. **YubiKey leftovers** — confirm drop: ykman, gnupg2-scdaemon, dracut passkeys.
3. **Unused-suspects** — input-remapper, steam-devices, orca, toolbox: drop?
4. **ramalama** — keep (easy container LLM) or commit to native llama.cpp only?
5. **antigravity** — still want the IDE packaged? (the one real `🔧` cost)
6. **hjust** — the system menu: keep / rewrite / kill?
7. **iio-niri** — package for the Zenbook Duo (auto-rotate) or drop?
8. **valent** + **nautilus-open-any-terminal** — keep these niceties?
9. **niri KDL rung** — raw file (hot-reload) vs typed `programs.niri.settings`.
10. **bar / notifications** — you removed waybar+mako; run a bar/notification
    daemon at all, or stay bar-less (nix-test found the system runs no bar)?
