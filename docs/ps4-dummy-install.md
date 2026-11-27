# ps4-dummy: prepared USB NixOS with Orbis recovery

This procedure prepares a **Linux psX-based NixOS member of the fleet**.
The first installation has a FAT32 boot partition and a Btrfs root on one
external USB drive. The PS4's entire internal disk retains Orbis and is not a
partitioning target. Once Linux starts, Orbis is inactive; it is still the
initial loader/recovery entrance after a cold boot.

The prepared kernel, initramfs, USB layout and fleet configuration require
first-boot qualification on the identified console. A built image is not
evidence that the hardware booted, that 7 GiB of GPU backing is usable, or that
Bonsai inference is implemented. No firmware update, PS4 initialization,
internal-disk write, game/save deletion, or unattended reboot is part of prep.

## The storage decision

| Device | Layout | What changes |
| --- | --- | --- |
| Selected external USB | DOS partition table; 512 MiB FAT32 `PS4BOOT`; Btrfs `ps4-nixos` | Writing the image erases this explicitly identified USB only |
| PS4 internal 500 GB disk | Existing Sony partitions, encrypted user filesystem and installed Orbis | Preserved, with internal SATA disabled in the initial Linux boot profile |
| NAS/Strix | Existing fleet configuration and build/artifact paths | One dotfiles branch/worktree; build products and receipts only |

Internal dual boot has a real research precedent, but it is not a normal
partition shrink: the reported design uses a per-console encrypted mapping and
a fixed extent map of a filesystem image inside Orbis's UFS2 user area.
Moving the image can invalidate the map. The current psX documentation does
not supply a portable installer or qualify internal writes. Keep this as a
follow-up after external recovery works. The external-first route already
delivers NixOS plus Orbis fallback. [psX internal-storage record](https://github.com/meerzulee/linux-psx/blob/886e35141787c26c2eb5df0558109d3ac35d38ad/platforms/ps4/docs/INTERNAL-STORAGE.md),
[contributor's internal-root report](https://github.com/meerzulee/linux-psx/issues/5).

## Prepare before touching the PS4 UI

1. Review the branch's `hosts/ps4-dummy`, `pkgs/ps4-platform` and
   `pkgs/ps4-installer`. Record the dotfiles commit, platform source pins and
   exact USB image checksum in the installation receipt.
2. Confirm the hardware gate from known records if available. The initial
   psX kernel recipe targets **Baikal**; neither the word Slim nor a sales
   region proves that southbridge. The final attended audit records the
   actual CUH and firmware before a payload is chosen.
3. Build on **strix-coordinator**, after `df -h /nix` confirms at least 25 GB
   free. The NAS runs no compilation and no fallback build. Use the one
   staged branch prepared by the orchestrator; do not create another worktree.

   ```sh
   fleet-exec strix-coordinator --cwd /tmp/ps4-dummy-build -- df -h /nix
   fleet-exec strix-coordinator --cwd /tmp/ps4-dummy-build -- \
     nix build .#ps4-dummy-usb-image .#ps4-installer --no-link
   ```

4. The image contains the NixOS closure and registration data, a real initial
   `/sbin/init` executable, and the selected system profile. It does not need
   a download to create its first operating system. It contains no private
   SSH host key, Tailscale enrollment token, harness login or personal home.
5. Use a USB drive whose **actual capacity exceeds the final uncompressed
   image**, with room for system generations and logs. An external USB SSD
   is a better permanent writable root than an unspecified small flash
   stick. Choose its identity from `lsblk --bytes` and `/dev/disk/by-id` on
   the machine where that USB is physically attached.

   ```sh
   lsblk --bytes --paths --output PATH,TYPE,TRAN,MODEL,SERIAL,SIZE,MOUNTPOINTS
   ```

6. Run the packaged `ps4-usb` first **without `--write`**. Replace all three
   uppercase values with the selected USB's real values; there is no default
   disk, guessed `/dev/sdX`, or internal-disk fallback.

   ```sh
   ps4-usb --image /nix/store/IMAGE/sd-image/ps4-dummy-nixos.img \
     --device /dev/disk/by-id/usb-EXACT_DRIVE_ID \
     --expect-serial EXACT_SERIAL --expect-size-bytes EXACT_BYTE_COUNT
   ```

   The JSON plan verifies the complete image's structure/labels/hash and the
   USB's serial, capacity, whole-disk USB transport, mount/swap state and
   holders. Inspect the plan and unmount only that selected USB's mounted
   filesystems if necessary. The helper never unmounts anything automatically.

7. At the attended write step, repeat the same arguments with `sudo`,
   `--write --confirm-erase EXACT_SERIAL`. This overwrites that USB's
   partition table and contents. The helper obtains an exclusive block-device
   handle, writes the image, flushes it and compares a full readback SHA256.
   Save its JSON receipt; a failed checksum means the media is not ready.
   Unplug only after successful completion. The helper does not expand the
   filesystem or write beyond the image's exact length.

The final image is intentionally uncompressed for this guarded writer.
`ps4-usb --image <path>` without a target is a read-only image inspection.
No installer may run disko or a generic whole-disk NixOS installer against the
PS4's internal SATA disk.

## Final attended Orbis UI pass

Do this **after preparation**, with controller, working display and Ethernet
available together as the physical arrangement permits. Record settings as
observed; do not reset the console or install a system update.

1. Photograph the exterior CUH label and note the controller's confirm/cancel
   convention. In **Settings > System > System Information**, record the
   exact system-software version and network addresses. Keep serial numbers
   and local addresses in the private installation receipt, not the public
   repository. [Sony's System Information guide](https://manuals.playstation.net/document/en/ps4/settings/system.html).
2. In **Settings > System > Automatic Downloads**, disable System Software
   Update Files and Allow Restart. Inspect queued downloads and cancel any
   pending system update without launching it. Application updates are not
   needed for the appliance. Online access alone must not select a newer
   firmware or change the compatibility baseline. [Sony's automatic-download settings](https://manuals.playstation.net/document/en/ps4/settings/autoupdate.html).
3. In **Settings > Power Save Settings > Set Features Available in Rest
   Mode**, record existing choices and disable Internet connectivity during
   rest for this installation pass. Do not test suspend/resume as a boot
   shortcut. [Sony's rest-mode settings](https://manuals.playstation.net/document/en/ps4/settings/standbymode.html).
4. In **Settings > Network**, select the LAN cable and verify DHCP. Record
   the wired MAC, address, prefix, gateway and DNS from View Connection
   Status, and match the lease on the BE550. A successful DHCP lease is
   different from PlayStation Network sign-in, which is not needed. Do not
   replace working DNS with an arbitrary public exploit host. [LAN setup](https://manuals.playstation.net/document/en/ps4/settings/nw_settings.html),
   [connection status](https://manuals.playstation.net/document/en/ps4/settings/nw_status.html).
5. Inventory the **existing** authorized homebrew/payload entrance, its exact
   version, and whether it survives an ordinary Orbis boot. Select the
   firmware-compatible entrance and the pinned Linux payload only after the
   observed firmware and southbridge match the documented gate. A Linux
   loader's firmware table is not a demonstration of a working jailbreak
   entrance on every firmware. Do not run a random browser payload during
   this audit. The inspected AIO loader warns that direct WebKit loading can
   crash its host process. [Pinned loader documentation](https://github.com/ps4-linux/ps4-linux-loader/blob/de22b91e58ecbb7151cb622047e2786f9a9b9965/README.md).
6. Check that the prepared USB's FAT partition is visible if the current
   payload entrance provides a file browser. **Do not choose Format as
   Extended Storage**: that is Sony game-storage formatting and destroys the
   prepared layout. Leave all other boot USB drives disconnected. [Sony's USB-device settings](https://manuals.playstation.net/document/en/ps4/settings/usbstorage.html).
7. Record the intended physical recovery: normal Orbis power-on, known
   controller/display path, selected USB removable while powered down, and
   the known payload entrance. No games or saves need deleting. The ordinary
   Orbis recovery remains installed; no PUP/reinstallation is required by
   this external-root design.

Do not proceed to payload execution if the real console differs from the
prepared kernel's southbridge recipe, firmware entrance, or networking plan.
Resolve the specific mismatch by rebuilding/selecting the correct artifacts.

## First boot and trust establishment

The selected loader reads the complete FAT-root set: `bzImage`,
`initramfs.cpio.gz`, `bootargs.txt`, `vram.txt`. Keep them paired with
`SHA256SUMS`; USB has priority over internal boot-file fallbacks. Do not mix
one new kernel with an older initramfs or remove just one of these files.
The kernel's matching module tree is in the NixOS closure. The initramfs
mounts the labelled Btrfs root and executes its real `/sbin/init`, which
enters the chosen NixOS system. This is not PC UEFI/GRUB installation.

1. At the supervised boot step, execute the verified payload exactly once.
   Keep the display for the first transition and observe the Linux console.
   Router lease discovery must show the same wired device. Orbis settings
   do not supply Linux's NetworkManager configuration; the image has its own
   wired DHCP profile.
2. At the local NixOS console, verify `hostname` is `ps4-dummy` and obtain
   its newly generated host-key fingerprint:

   ```sh
   sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub -E sha256
   ip -br address
   ```

   Compare that physical-console fingerprint before accepting the first SSH
   connection. Do not bypass host checking or copy another fleet member's
   private host key. Add the verified public key to the fleet registry in the
   normal review path. The private key remains on this PS4.
3. Connect from the NAS using the existing fleet public login key. Run the
   host readiness command documented by this branch, inspect the real
   `/proc/cmdline`, kernel release, `MemTotal`, Ethernet route, firewall,
   module/firmware health and `/dev/dri/renderD*` permissions. No inference
   endpoint is exposed until an actual runtime is installed and qualified.
4. Enroll **this PS4's own** Tailscale identity using its on-device login
   flow. Verify the new node in the tailnet administration view, then verify
   SSH by its pinned host key over that path. Never clone NAS/Strix's
   tailscaled state or enrollment token.
5. Recheck a normal Orbis boot and its Ethernet connection at an attended
   recovery checkpoint before leaving the prototype headless. A NixOS
   generation rollback does not change the externally loaded kernel; retain
   both the prior NixOS generation and paired boot set.

The boot bundle includes `recovery/gpu-1024MiB`, a separately named 1024 MiB
set using the **same** candidate kernel/initramfs and firewall/module support.
This isolates the low-VRAM memory-map change. Switching recovery must
replace the complete four-file FAT-root set and recheck hashes; merely
selecting a 1024 MiB ELF while `vram.txt` still says 128 changes nothing.
The historical frozen reference kernel is a separate source/control artifact,
not a replacement fleet boot set with a mismatched module tree.

## Capacity, suite and later deployment

The initial recipe requests a 128 MiB loader GPU reservation and a 7168 MiB
TTM backing ceiling. That leaves most unified GDDR5 available to Linux and
keeps the amdgpu render path enabled. The relevant loader memory map, TTM
limit, successful GPU virtual mappings and useful bandwidth are separate
tests. Reading a large `MemTotal` or raising a ceiling does not demonstrate
seven GiB of resident, correctly coherent GPU-accessible buffers.

Keep the first successful boot headless. The optional fleet-suite
specialisation makes the requested Kitty/Domicile/herdr-core packages
available without starting a compositor or occupying the inference budget
by default. Local sessions and their memory must be measured before combining
them with Bonsai's full weights, FP16 cache and FP32 recurrent state. The
model/plugin runtime work is separate from this boot installer.

The image does **not** resize itself automatically. Its initial root is sized
from the shipped closure plus 20% and 2 GiB of writable headroom; capture
`df -h /` after boot. To use remaining USB
capacity, first verify `/` resolves to `ps4-nixos` on the same physical USB,
record its serial and current table, then grow only its final partition and
Btrfs filesystem in a separately reviewed USB-only operation. No generic
autoexpander is enabled against an unverified disk. Model files stay outside
Nix store generations and arrive through the existing explicit Library/loan
workflow when model runtime work is ready.

After the PS4 has a verified host key and tailnet identity, the fleet deploy
path can copy a built closure to it with local PS4 builds disabled. Never
activate another live fleet host, restart the NAS's user manager or Herdr, or
reboot a machine as a side effect of adding this one.

## Unknowns and proposed defaults

- The actual CUH, southbridge, firmware, exploit entrance, USB serial/capacity
  and wired network are not assumed. Default: record and match them during
  the final attended audit before selecting and writing the final image.
- Kernel/source/image checks are preparation evidence. Default: retain the
  actual build log and image/write/readback receipts; first hardware boot,
  Orbis recovery, Ethernet duration and GPU memory/bandwidth need measured
  results from this console.
- The internal disk remains unused by Linux. Default: external root first;
  investigate a console-specific contained-image mapping only after a
  reliable recovery path, without treating ordinary partition shrink as safe.
- Hands-free power-loss boot is not established by successful headless Linux
  operation. Default: retain the attended Orbis-to-Linux entrance until a
  compatible, independently qualified automation path exists.
