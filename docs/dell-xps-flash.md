# dell-xps flash runbook (device 3 of 4)

Canonical laptop-flash procedure, distilled from the jul5 worker + zenbook-duo flashes.
The XPS 13 9315 is deliberately identical in process to the duo. Supersedes the stale
`zenbook-duo-flash.md` (which predates nixos-anywhere/disko/extra-files).

## Pre-flight (do these BEFORE touching the installer)

1. **Disable Secure Boot** in the XPS BIOS (F2/F12 at boot → Security). The unsigned
   NixOS installer ISO will not boot with SB on. Non-negotiable — it cost a physical
   round-trip on the worker.
2. **Check Intel VMD / RAID-On / Optane** in BIOS (Storage/SATA settings). The 9315
   commonly ships VMD **on**, which hides the NVMe. Either disable it, OR keep it and
   confirm `vmd` survives hardware-config regen (step 3). `hosts/dell-xps/hardware.nix`
   already lists `vmd` in `initrd.availableKernelModules` proactively.
3. Boot the same 128GB SD installer (25.11, baked Freebox wifi) → it auto-joins wifi
   and answers as `nixos-installer.local`. Both laptops answer to that name, so flash
   one at a time or use the IP.

## Drive it from the coordinator (over ssh, raw podman)

The `nixflash` container pattern (no native nix on this box):
`podman start nixflash` (or run per auto-memory). Keys already inside at
`/root/.ssh/tom-mesh_ed25519`.

1. **Confirm the disk device** — do NOT trust `disko.nix`'s `/dev/nvme0n1` blindly:
   ```
   ssh -i ~/.ssh/tom-mesh_ed25519 root@<installer-ip> 'lsblk -dno NAME,SIZE,MODEL /dev/nvme*'
   ```
   Fix `hosts/dell-xps/disko.nix` if it differs.
2. **Regenerate the real hardware.nix** from the live box (the committed one is a
   placeholder):
   ```
   ssh -i ~/.ssh/tom-mesh_ed25519 root@<installer-ip> \
     'nixos-generate-config --no-filesystems --show-hardware-config'
   ```
   Overwrite `hosts/dell-xps/hardware.nix` with the output (keep the disko/no-filesystems
   pattern). **Confirm `vmd` is present** if VMD stayed on. Commit.
3. **Build the toplevel in the container** and fix eval/build errors OFF the target:
   `nix build .#nixosConfigurations.dell-xps.config.system.build.toplevel`
4. **Flash** (nixos-anywhere is NOT a container binary — `nix run` it):
   ```
   nix run github:nix-community/nixos-anywhere -- \
     --flake .#dell-xps \
     --extra-files /root/host/mecattaf/nix-secrets-staging/install-files/dell-xps \
     -i /root/.ssh/tom-mesh_ed25519 \
     --ssh-option StrictHostKeyChecking=no --ssh-option UserKnownHostsFile=/dev/null \
     --target-host root@<installer-ip>
   ```
   The extra-files bundle carries the **offline ssh host key** (zero-TOFU; pub already
   in `mesh-registry.nix`) AND the **wifi profile** (`Freebox-AB3ACE.nmconnection`,
   mode 600) — both already staged at `nix-secrets-staging/install-files/dell-xps/`.
5. **Pull the SD card during the reboot** so it boots the NVMe, not the installer.

## First boot is self-provisioning

- Wifi auto-connects via the delivered NM profile (no console step — laptops get no
  wired/tether, ever).
- `dotfiles-bootstrap.service` (in `modules/dotfiles-bootstrap.nix`) clones
  `github.com/mecattaf/dotfiles` (**branch `main`**) → `~/mecattaf/dotfiles` **before
  greetd**, so niri
  reads the real config (the out-of-store symlinks resolve). Idempotent; skips once
  `.git` exists. *(Optional optimization: stage a full clone into a second
  `--extra-files` tree with `--chown /home/tom/mecattaf/dotfiles 1000:100` to skip the
  first-boot clone entirely.)*
- greetd autologins tom → niri (fleet-wide). If the session ever fails, **Ctrl+Alt+F2**
  gives a getty autologin console (tom is password-locked; this is the only console
  recovery).

## Post-install verification (over ssh as tom; shell is fish → pipe via `bash -s`)

- hostname `dell-xps`, `sudo -n true` (passwordless), wifi `nmcli con show --active`.
- **Zero-TOFU gate before secrets:** confirm the delivered host key matches the registry:
  ```
  ssh -i ~/.ssh/tom-mesh_ed25519 tom@<ip> 'ssh-keygen -y -f /etc/ssh/ssh_host_ed25519_key'
  ```
  must equal `dell-xps.hostKey` in `modules/mesh-registry.nix`.
- niri session up (`pgrep -ax niri`), wayvnc `:5900` listening, kanshi `Laptop` profile
  (single eDP) applied.
- Then flip `mySecrets.enable = true` in `hosts/dell-xps/default.nix`, rebuild, verify
  `/run/agenix/claude-credentials` decrypts (mirrors the worker battery).

## XPS-specific notes

- `hosts/dell-xps/default.nix` already carries the `nixos-hardware.dell-xps-13-9315`
  module (which sets thermald/i915-PSR/fprintd) — don't re-derive those.
- Single internal panel → none of the duo's dual-eDP niri hang risk. `git`/`gh`: a
  private push needs a one-time `gh auth login` on the box (can't be baked in).
