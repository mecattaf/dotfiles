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
   Worker raw helpers are carried in the Nix store, like the client's, so
   first boot does not depend on the old checkout or cloning `main`.
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
5. Arrange enrollment using the NAS PR's shared `modules/fleet-transport.nix`
   procedure: interactive login to the official service, then disable device
   key expiry in the admin console for each of the four machines. Its
   credentials/state stay outside Nix and Git; `authKeyFile` stays null. Do not
   copy the coordinator's Tailscale state or silently reuse an old retired
   worker node. An auth key's lifetime alone does not prove device key expiry.
   The offline OS install does not enroll it. Use the optional pre-enrollment
   stage below to do that same interactive login before the move, or accept
   a one-time login after first boot. No temporary daemon was started by this
   task. See #607's `docs/nas-agent-transport.md` for the four-node procedure.

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
procedure below before unmounting if immediate tailnet membership is required.
For model services to be ready on first boot, also stage the **final integration
closure's** wanted artifacts from the NAS Library while this root is mounted.
The existing borrow tool supports an alternate target without activation:

```sh
# Future approved disk writes; /mnt/library/weights must be the NAS Library.
sudo env LOCAL_MODELS_MANIFEST="$worker_system/etc/local-models/wanted.json" \
  LOCAL_MODELS_LIBRARY=/mnt/library/weights \
  LOCAL_MODELS_ROOT="$worker_root/var/lib/local-models" \
  LOCAL_MODELS_BORROW_LOCK=/var/tmp/strix-worker-models-borrow.lock \
  "$worker_system/sw/bin/local-models-borrow" --dry-run
# Review the complete plan and target free-space reserve, then repeat --yes.
```

Borrowing verifies newly copied files but skips existing files of the expected
size. Verify pre-existing artifacts against every SHA-256 `oid` in that wanted
manifest too. Missing Library objects, insufficient target space or unavailable
NAS storage block this stage; do not download weights directly on compute or
delete old contents to make space without Tom's decision. Without verified
weights, bootable NixOS is not evidence of a ready model service.

Then `sync`, unmount the ESP and root, and leave the disk unmounted until the
coordinated shutdown. Record the install result and public host-key fingerprint.
A successful build alone is not this proof.

### Optional pre-enrollment on the mounted final worker root

This uses the **same interactive user login and console non-expiry mechanism
as #607**, with a fresh worker state directory. It is a prepared, unexecuted
procedure, requiring the disk-write authorization above plus Tom's supervised
tailnet login. It changes the tailnet and writes private worker node state.
Do not experiment with the live coordinator daemon or its socket/state.

Prerequisites: the NAS node is already named `nas` and its exit/subnet role is
approved as in #607; the worker's retired state has been securely archived;
the target directory is not a symlink to a live path. The installed closure's
Tailscale must support the flags below (`--help` was checked on 1.98.8).
The Tailscale policy must permit an initially portable, unencrypted node state;
if policy requires hardware attestation/TPM binding, enroll on the actual
worker instead. State encrypted with the coordinator's TPM cannot move to the
worker. Keep this state root-only and never copy it off its final worker SSD.

In one supervised terminal, with the previous mount/closure variables:

```sh
# Future supervised operation only; fresh state, never the coordinator state.
sudo install -d -m 0700 "$worker_root/var/lib/tailscale"
sudo test ! -e "$worker_root/var/lib/tailscale/tailscaled.state"
worker_socket_dir=$(sudo mktemp -d /var/tmp/strix-worker-enroll.XXXXXX)
sudo "$worker_system/sw/bin/tailscaled" \
  --tun=userspace-networking --port=0 \
  --socket="$worker_socket_dir/tailscaled.sock" \
  --statedir="$worker_root/var/lib/tailscale" \
  --state="$worker_root/var/lib/tailscale/tailscaled.state" \
  --encrypt-state=false --hardware-attestation=false
```

Run the daemon in the foreground, with no proxy listeners. Userspace mode
creates no TUN interface or host routing changes. In a second supervised
terminal, use those same `worker_system` and `worker_socket_dir` values:

```sh
sudo "$worker_system/sw/bin/tailscale" --socket="$worker_socket_dir/tailscaled.sock" \
  login --login-server=https://controlplane.tailscale.com \
  --hostname=strix-worker --accept-dns=false --ssh=false \
  --accept-routes=true --exit-node=nas --exit-node-allow-lan-access=true
```

Tom opens that login URL, approves this fresh worker identity and disables its
device key expiry in the Machines console. Record its stable device ID and
non-expiry receipt; check the temporary daemon's status through **only its
private socket** and use #607's read-only checker. This can prove enrollment,
not the actual worker's firmware, NIC, kernel, SSH or RDMA operation.

When complete, Ctrl-C **only this foreground temporary daemon**, wait for it
to exit and flush state, and do not log out: logging out would invalidate the
identity being staged. It must be stopped before unmounting or moving the SSD.
Never run it alongside the real worker using that identity. The normal worker
daemon will use this same `/var/lib/tailscale/` on first boot; its normal
`tailscaled-set` applies #607's complete preferences. Recheck identity and
expiry after the move. If pre-enrollment is not performed, first-boot LAN SSH
plus Tom's interactive login is still required; do not claim unattended
tailnet readiness.

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
  using ordinary OpenSSH. They select the NAS exit node with LAN access
  allowed and accept its subnet route; neither advertises routes. Retain the
  coordinator's existing enrolled state. After worker login, run the shared
  `fleet-transport-check` from each machine and retain admin-console evidence
  of **Key expiry disabled** for all four. The read-only checker requires four
  distinct online identities, correct tailnet, no reported key expiry and NAS
  exit/subnet approval and selection. Check these again after the power cycle.
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
[auth keys](https://tailscale.com/docs/features/access-control/auth-keys),
[bootctl install and EFI options](https://www.freedesktop.org/software/systemd/man/latest/bootctl.html),
[userspace networking](https://tailscale.com/docs/concepts/userspace-networking),
[daemon flags](https://tailscale.com/docs/reference/tailscaled),
[TPM-bound node state](https://tailscale.com/docs/features/secure-node-state-storage).
