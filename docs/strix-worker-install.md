# Returning worker: prepare before the fleet's single shutdown

Tom's latest 2026-10-23 ruling supersedes the staggered shutdown in the survey:
prepare all three machines, shut down the coordinator, worker and NAS together,
move the SSDs and connect the cables, then bring them up in their new roles.
This page prepares the worker. It does **not** authorize a disk write, an
installation, a shutdown or activation on any machine.

## Current disk and boot blocker

The worker's 1TB SSD is still inside the coordinator, unmounted. Read-only
`lsblk` and `blkid -p` on 2026-10-23 confirmed:

| Item | Identity / observation |
| --- | --- |
| Whole disk | `/dev/disk/by-id/nvme-WD_BLACK_SN7100_1TB_26051Y809195` |
| ESP (`-part1`) | 1G, PARTUUID `25db1b50-f51c-499b-a628-26a25fa02662`; EFI GPT type; **no detected filesystem signature** |
| Root (`-part2`) | ext4, PARTUUID `e4869fbf-f6c5-4bf5-960f-cf19376e139d` |
| Root filesystem UUID | `f6e8755c-b164-4d3b-bd0e-31f2f84a523e` |
| Contents | Retired worker NixOS and `/home/tom`, approximately 518 GB used (Tom's report) |

The root has not been mounted or inspected by this task. The blank ESP means
moving the SSD alone will **not** provide a bootable worker. The two fresh
partition UUIDs originally proposed in #608 do not describe this occupied
disk; the host now declares the measured existing UUIDs. This keeps the normal
host configuration correct after a preserving install, without a temporary
filesystem override that a later update would accidentally remove.

**Do not run disko, repartition, format the ext4 root or wipe this disk.** The
disko declaration documents the layout; its destructive installation script
is not the preserving route. No writes to this disk have been approved.

## Preferred route: offline install while it is still in the coordinator

This gives the least work at power-on: after successful preparation, move the
disk into the worker and boot it. An operator must first authorize writes to
this occupied disk and, separately, creation of the FAT filesystem on its ESP.
No full-disk wipe is required. Before writing, confirm a recoverable backup of
anything that must survive; inspect the old home and service state with Tom.
Old operator credentials, old SSH private host keys and retired Tailscale state
must be inventoried and securely archived off compute before this becomes a
clean compute host. Removing Nix secret declarations does not erase them.

Prerequisites before executing the following stages:

1. Use the **final integration** revision from
   `integration/cutover-2026-10-23`, including Linux 7.3, the matching
   Donnerkeule/Gufo RDMA work, NAS home/agent changes and the common Tailscale
   registration mechanism. Record its commit and worker toplevel path. #608
   alone is not a complete fleet cutover image.
2. Build the worker closure on the coordinator before the shutdown. Run
   `df -h /` immediately before any `nix build`; stop below 25 GB available.
   Keep the built closure rooted until installation and proof complete.
3. Confirm the disk serial, both PARTUUIDs, ext4 filesystem UUID, and that no
   partition is mounted. Inspect ESP signatures again. A different observation
   is a stop, not permission to format the newly found filesystem.
4. Generate a fresh worker SSH host key, preserving the old key in the secured
   archive. Put **only its public half** in the registry, rebuild the final
   integration closure with that public key, and install the matching private
   half under the target's `/etc/ssh/`. Do not reuse the retired worker key or
   copy the coordinator's identity. The worker remains outside every agenix
   recipient tier; no rekey is needed for its fresh host key.
5. Arrange enrollment using the NAS PR's shared registration procedure. Its
   credentials/state stay outside Nix and Git. Do not copy the coordinator's
   Tailscale state or silently reuse an old retired worker node. Device key
   expiry must be disabled and verified on the Tailscale control plane; an
   auth key's lifetime alone does not prove this.

After permission, the supervised preserving installation is:

```sh
# These commands WRITE the occupied disk. Do not execute without authorization.
worker_disk=/dev/disk/by-id/nvme-WD_BLACK_SN7100_1TB_26051Y809195
worker_root=/mnt/strix-worker-install
# Set this to the reviewed, already-built final integration worker toplevel:
worker_system=/nix/store/REPLACE_WITH_VERIFIED_WORKER_TOPLEVEL

sudo lsblk -o NAME,SIZE,SERIAL,FSTYPE,UUID,PARTUUID,MOUNTPOINTS "$worker_disk"
sudo blkid -p -o export "${worker_disk}-part1"
sudo blkid -p -o export "${worker_disk}-part2"
```

Match every identity in the table, ensure the target is not the coordinator's
root or a mounted disk, and confirm the closure is for `strix-worker`. Only if
the ESP is still the confirmed blank partition and its formatting is approved:

```sh
sudo mkfs.fat -F 32 -n WORKER_EFI "${worker_disk}-part1"
```

Never run `mkfs` on `-part2`. Mount the existing root and the worker's own ESP;
check space on the target as well as the coordinator. Install the fresh host
key and perform the agreed credential/state archival before installing:

```sh
sudo install -d -m 0755 "$worker_root"
sudo mount "${worker_disk}-part2" "$worker_root"
sudo install -d -m 0700 "$worker_root/boot"
sudo mount -o umask=0077 "${worker_disk}-part1" "$worker_root/boot"
findmnt --target "$worker_root"
findmnt --target "$worker_root/boot"
df -h / "$worker_root" "$worker_root/boot"

# After checking the mounts, identity, space, archival and public-key update:
sudo nixos-install --root "$worker_root" --system "$worker_system" \
  --no-channel-copy --no-root-passwd
```

The reviewed Nixpkgs installer copies the supplied closure and sets the target
system profile, then installs the bootloader in the target. It invokes target
boot configuration in a chroot; it does not switch the coordinator. This task
has **not** executed it. Worker `canTouchEfiVariables = false` makes bootctl
use `--no-variables`, preserving the coordinator's firmware entries while
installing the removable-path `EFI/BOOT/BOOTX64.EFI` on the worker ESP.

Before unmounting, verify the target system-profile link resolves to the
recorded worker closure, its `etc/hostname` is `strix-worker`, the ESP contains
`EFI/BOOT/BOOTX64.EFI`, and loader entries reference the new kernel/initrd.
Check authorized SSH access and account state without printing credentials;
`--no-root-passwd` does not create a usable login. Follow the shared registration
procedure for first boot. Then `sync`, unmount the ESP and root, and leave the
disk unmounted until the coordinated shutdown. Record the install result and
public host-key fingerprint. A successful build alone is not this proof.

## Fallback: installer after the move

If pre-install writes are not approved/completed, prepare an x86_64 UEFI NixOS
installer USB, keyboard/display, Ethernet and the reviewed closure/config
(locally on removable media, or available from the NAS/cache). After the SSD
move, boot that USB and perform the same identity checks and approved
preserving install. Verify the worker's actual NIC name/MAC first. This adds
an installer boot and a deliberate reboot into the installed system. It
therefore **does not** meet “new role on first power-on.” Wiping and fresh
partitioning is a separate alternative requiring explicit permission and a
verified backup; it is not needed for the preferred route.

## Cables and first-boot proof

- Coordinator keeps anchor SSD `25140U804698`; `26051Y809195` moves into the
  worker. The expected worker 500GB `260538801482` moves to the NAS only under
  its storage runbook, after its identity/data decisions are confirmed.
- Each Strix gets Ethernet to the BE550. Control/SSH, DNS, NAS Library access,
  Tailscale and build dispatch must work over Ethernet without the fast links.
  Worker is `10.42.0.5/24`, gateway `.3`, DNS `.1`, expected NIC `enp191s0` and
  MAC `9c:bf:0d:01:cc:65` (verify on arrival).
- Connect **two** host-to-host Thunderbolt 5 cables between the Strix pair,
  with ports mapped and checked by the RDMA work. Preserve the old design's
  separation of the Ethernet control/storage path from two USB4 fast paths.
  Historical rails used `10.99.0.0/30` plus a second TB rail, direct Ethernet
  fallback and loopback identities; do not import those retired NM profiles or
  their old Wi-Fi/default-route assumptions into today's BE550 Ethernet LAN.
  See `docs/usb4-pd-wedge-2026-08-21.md` for incident history, not current setup.
- NAS is the agent/home host and sole Tailscale exit/subnet router. Both
  compute hosts join the official `tailscale.com` service as plain nodes,
  using ordinary OpenSSH. Validate distinct node identities, reachability and
  non-expiring device registration for all four machines through the NAS
  procedure. Check these again after the power cycle.
- Verify Linux 7.3 and matching RDMA modules, SSH on `.2`/`.5`, NAS NFS,
  journal upload, fresh host-key trust and Tailscale on the worker. Borrow
  models explicitly from the NAS; declaration/build success does not install
  weights or prove dual-node inference. Have the RDMA/integration checks prove
  both fast links and the NAS-to-compute inference/build offload separately.

Do not issue the fleet unplug instruction until the worker's install/boot
files, NAS handover, shared registration and final integration readiness have
all been proved. This PR prepares those steps; it has not performed them.

References: [NixOS installation manual](https://nixos.org/manual/nixos/stable/),
[Tailscale device expiry](https://tailscale.com/docs/features/access-control/key-expiry),
[auth keys](https://tailscale.com/docs/features/access-control/auth-keys).
