> ⚠️ **SUPERSEDED (2026-07-05). Do NOT follow this document to flash anything.**
> It predates the nixos-anywhere + disko + `--extra-files` flow the fleet now uses,
> and its manual-USB path delivers NO offline ssh host key — a host flashed this way
> gets an unregistered key and agenix decryption breaks when `mySecrets.enable` flips.
> **Canonical laptop runbook: [`dell-xps-flash.md`](./dell-xps-flash.md).** The duo's
> actual jul5 flash + fixes: `notes/july-fable/july5-duo-flash/flash-log.md`.
> Kept only for historical context below this line.

---

# Flashing NixOS on the Asus Zenbook Duo — runbook (HISTORICAL)

The first real NixOS install (Layer 2 / the "first boot" milestone). Done **manually
from a USB stick** (disko/secure-boot are deferred, so no `nixos-anywhere` yet). Do NOT
do this on `harness` or the worker — only the Zenbook Duo.

The flake target is `zenbook-duo` on the **`nix` branch** of `github.com/mecattaf/dotfiles`.
No secrets are needed for this install.

---

## How to drive the install (pick one)

- **A — On the Duo directly.** Type the steps below at the Duo's installer console.
  Simplest; fine for a one-off.
- **B — Puppeteer from `harness` over SSH (RECOMMENDED).** Boot the Duo installer, do ONE
  thing at its console (network + authorize SSH — unavoidable; there's no pure-software way
  into a box that doesn't trust you yet), then run every step below over `ssh` from harness.
  No disko needed. Comfortable keyboard, copy-paste, logs on your main screen.
  ```bash
  # at the Duo installer console, ONCE:
  sudo su; passwd            # set a root password  (or: mkdir -p /root/.ssh && curl/paste your pubkey)
  systemctl start sshd
  ip -brief addr             # note the Duo's IP (use an ethernet/USB-C dongle, or iwctl for wifi)
  # then from harness:
  ssh root@<duo-ip>          # now run steps 3-7 here
  ```
- **C — Fully automated re-flashes via `nixos-anywhere`.** One command from harness
  partitions + installs. **Needs a `disko` config** (deliberately deferred — we can add a
  `hosts/zenbook-duo/disko.nix` once the manual install proves the flake). Best for
  repeatable wipes, overkill for the first boot.

Recommendation: **B for the first install** (validates the flake, no new code), then add
disko + switch to **C** if you want one-command re-flashes.

## 0. Before you start (on another computer)

- A USB stick (≥2 GB), and a second computer to write it.
- The Duo's data backed up — **this wipes the Duo's disk.**
- Know the Duo's NVMe device name (usually `/dev/nvme0n1`).

## 1. Make the NixOS installer USB (on the other computer)

```bash
# Download the latest minimal ISO (x86_64). Pick the current unstable/26.05 minimal ISO
# from https://nixos.org/download/  (e.g. latest-nixos-minimal-x86_64-linux.iso)
# Write it to the USB (replace sdX with the USB device — CHECK with lsblk first!):
sudo dd if=latest-nixos-minimal-x86_64-linux.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

## 2. Boot the Duo from the USB

- Insert the USB, power on, mash the boot menu key (Asus = F2/Esc/F8), pick the USB.
- Secure Boot: **disable it in BIOS** for now (lanzaboote is a later phase).
- You land at a root shell on the live installer. Get networking up:
  `nmcli device wifi connect "<SSID>" password "<pass>"` (or plug ethernet/USB-C dongle).

## 3. Partition + format the disk (manual; matches our placeholder labels)

```bash
DISK=/dev/nvme0n1          # <-- VERIFY with `lsblk`
# GPT: 1 GiB ESP + rest root
sudo parted $DISK -- mklabel gpt
sudo parted $DISK -- mkpart ESP fat32 1MiB 1025MiB
sudo parted $DISK -- set 1 esp on
sudo parted $DISK -- mkpart primary 1025MiB 100%

sudo mkfs.fat -F32 -n ESP   ${DISK}p1
sudo mkfs.ext4     -L nixos ${DISK}p2     # label "nixos" matches our placeholder; we replace it in step 5 anyway

sudo mount /dev/disk/by-label/nixos /mnt
sudo mkdir -p /mnt/boot
sudo mount /dev/disk/by-label/ESP /mnt/boot
```

## 4. Get the flake onto the Duo at the right path

The home-manager RAW configs symlink back to a **cloned checkout at
`/home/tom/mecattaf/dotfiles`** — clone it there so the config files resolve after boot:

```bash
sudo mkdir -p /mnt/home/tom/mecattaf
sudo nix-shell -p git --run \
  'git clone -b nix https://github.com/mecattaf/dotfiles.git /mnt/home/tom/mecattaf/dotfiles'
```

## 5. Generate the REAL hardware config and replace the placeholder

Our `hosts/zenbook-duo/hardware.nix` is a non-bootable placeholder. Generate the real
one (UUID-based) and overwrite it:

```bash
sudo nixos-generate-config --root /mnt --show-hardware-config \
  > /mnt/home/tom/mecattaf/dotfiles/hosts/zenbook-duo/hardware.nix
# sanity-check it has your real fileSystems (by UUID) + boot.initrd modules:
grep -E 'fileSystems|by-uuid|availableKernelModules' /mnt/home/tom/mecattaf/dotfiles/hosts/zenbook-duo/hardware.nix
```

> The generated file sets `fileSystems."/"` and `"/boot"` by UUID + the real
> `boot.initrd.availableKernelModules`. It REPLACES our `by-label` placeholder, so the
> label choices in step 3 don't matter past this point. Keep `nixpkgs.hostPlatform` and
> the systemd-boot loader (provided by `common.nix`).

## 6. Install

```bash
sudo nixos-install --flake /mnt/home/tom/mecattaf/dotfiles#zenbook-duo
# set the root password when prompted; then set tom's password:
sudo nixos-enter --root /mnt -c 'passwd tom'
```

## 7. Reboot

```bash
sudo reboot   # remove the USB
```

First boot lands at **greetd → niri** (RAW config). Log in as `tom`. home-manager has
already activated (it's a NixOS module), so packages, the Chrome PWA launchers, git,
mactahoe theming, and nvim (Nix-provided LSP + lazy-nix-helper store-resolved plugins)
are all in place.

---

## After first boot — known follow-ups (NOT auto-done)

These are deliberately deferred — flagged so they're not surprises:

- **Second internal display + IPU6 webcam + Zenbook-Duo daemon + touchpad palm-rejection**
  — the Duo's dual-screen is handled in niri output config (not NixOS); the daemon +
  `titdb` are out-of-nixpkgs and need packaging as flake inputs. Tracked in
  `hosts/zenbook-duo/default.nix`.
- **niri config is RAW** (hot-reload). Edits to `~/.config/niri/*` take effect live; the
  typed `programs.niri.settings` + niri-flake nixification is the post-first-boot step.
- **nvim plugins** resolve from `/nix/store` offline; the first `nvim` launch needs NO
  network (a fail-closed assertion errors loudly if any plugin didn't store-resolve).
- **Secrets** (sops / `~/.env`) — not set up; anything needing them (some fish funcs)
  degrades cleanly. Its own session.
- **Agent stack** (pi, claude-code) — comes via pi.nix / llm-agents.nix (deferred); not
  in this install.
- **Bootloader/secure-boot** — systemd-boot, Secure Boot off. lanzaboote + TPM is Phase 4.
- **Update later**: `sudo nixos-rebuild switch --flake ~/mecattaf/dotfiles#zenbook-duo`.
