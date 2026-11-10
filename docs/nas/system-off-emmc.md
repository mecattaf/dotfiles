# NAS: /var and /tmp off the eMMC

Tom, 2026-11-10: "58gb emmc is still quite large for it to be full. i think
that only the nixos flash should be on there?", "/tmp goes straight to the
1tb" and "make sure we don't lose any information".

`hosts/nas/system-off-emmc.nix` moves `/var` and `/tmp` onto the 1TB pool
(`nvme-WD_BLACK_SN7100_1TB_26051Y809195-part1`, the disk that already carries
`@home`, `@fast` and, through `@fast/nix`, `/nix`) as the btrfs subvolumes
`@var` and `@tmp`. After it, the eMMC holds `/boot` and a root with `/etc`,
`/root` and the host identity, all of which a reflash recreates. Immich stays
on the 256GB (`hosts/nas/immich-disk.nix`). The design and its measurements
are O1 (`~/tuesday-nov10/fleet-shape/consolidated/O1-nas-storage-shape.md`,
sections 3.3 to 3.5).

The gate `myNas.systemOffEmmc.enable` defaults to false. It takes effect only
at a reboot, and the reboot is Tom's (decision D1 in O1). Nothing in this
document has been run.

## What merging changes (gate off)

- No mount. `/etc/fstab` and the initrd are byte-identical to `main` before
  the merge (checked when it was built; `tests/nas-home-disk` asserts that
  `/var` and `/tmp` are not declared and `cleanOnBoot` is off).
- One switch inhibitor, `nas-var-tmp-backing = "eMMC root"`, in
  `/run/current-system/switch-inhibitors` once the gate-off generation is
  activated. With the gate on it reads `"1TB pool @var and @tmp"`, so
  `switch-to-configuration switch` or `test` between the two states is refused
  ("There are changes to critical components of the system"). `boot` is
  allowed. That is the guard against risk 4 of O1: a live switch would mount
  the subvolumes over the running `/var` and `/tmp`. Never bypass it with
  `NIXOS_NO_CHECK=1`.

Switching the merged gate-off generation live is safe and is a precondition
below: the inhibitor only protects a running generation that already carries
the key.

## What the gate does when on

- `/var`: `subvol=@var,compress=zstd:1,noatime`, `neededForBoot`, so the
  initrd mounts it (`x-initrd.mount`). A failure here stops the boot, exactly
  like `/nix` today.
- `/tmp`: `subvol=@tmp,noatime,nosuid,nodev,nofail,x-systemd.device-timeout=10s,x-systemd.before=local-fs.target`.
  `nofail` keeps the router up if `@tmp` is missing. `nofail` alone would also
  drop the mount's ordering before `local-fs.target`, so the explicit
  `x-systemd.before=local-fs.target` keeps `systemd-tmpfiles-setup` (and the
  `cleanOnBoot` rule) from running before `@tmp` is mounted.
- `boot.tmp.cleanOnBoot = true` (`D! /tmp 1777 root root`). From the flip on,
  **`/tmp` is emptied at every boot**. Nothing that must survive a reboot
  belongs there: push branches or leave bundles first.
- `/var/lib/private/atticd` and `/var/log/journal/remote` keep their binds
  from `@fast`; systemd orders them after `var.mount`.
- `tripwire-nas-mounts` (`hosts/nas/storage-alerts.nix`) requires every
  declared mount, so it watches `/var` and `/tmp` from the flip on.

## What must survive, and how

Nothing is selected: the whole of `/var` is copied, with `rsync -aHAX
--numeric-ids -x`, which keeps owners as raw ids, modes, times, hardlinks,
ACLs (`/var/log/journal` carries them) and xattrs. On 2026-11-10 `/var` held
7.4G. The things whose loss would hurt, checked by name before the reboot:

| Path under /var | Why it matters |
|---|---|
| `lib/nixos/{uid,gid}-map`, `declarative-{users,groups}`, `auto-subuid-map` | Without them NixOS reallocates every uid and gid |
| `lib/private/AdGuardHome` | House DNS configuration and statistics |
| `lib/tailscale`, `lib/tailscale-personal` | Node keys; without them the NAS must log in to the tailnet again |
| `lib/dnsmasq` | DHCP leases |
| `lib/samba/private` | SMB accounts and secrets |
| `lib/handwriting-annotation`, `lib/handwriting-intake` | Append-only writer and review history (AGENTS.md: preserve) |
| `lib/systemd/linger/tom` | Tom's user manager at boot |
| `lib/fleet-backup-2026-10-23`, `lib/fleet-move-2026-10-23` | One-off backup and move records (2.2G) |
| `log/journal` | 4.0G of system journal |

Not copied, on purpose:

- `lib/private/atticd` and `log/journal/remote` are already on `@fast`
  (binds). `-x` leaves an empty mount-point directory for each, and the binds
  mount over them as today.
- `lib/nfs/rpc_pipefs` is a kernel filesystem, recreated at boot.
- `/tmp` is not copied. The eMMC `/tmp` stays intact under the new mount and
  is archived in step 4 before anything is deleted.

The eMMC `/var` itself is not touched until step 4, seven days later: it is
the rollback.

## Order

1. O1 phase 0 (the hidden old home) and PR-1 (storage alerts, live switch)
   can go first; neither depends on this.
2. This change merged with the gate off, and switched live. It changes no
   mount.
3. Step 1, any day, no downtime: subvolumes and the first copy.
4. Step 2, in the reboot window Tom picks (D1): flip, `boot`, final copy,
   one-shot trial reboot.
5. Step 3: verify and accept.
6. Seven clean days.
7. Step 4: no-loss checks, archive of the old `/tmp`, reclaim, root alert at
   25%.

## Before the window

- [ ] `jq . /run/current-system/switch-inhibitors` shows
      `"nas-var-tmp-backing": "eMMC root"`.
- [ ] HDMI console attached; initrd SSH on `10.42.0.1:2222` known to work
      (`hosts/nas/initrd-ssh.nix`).
- [ ] Tom accepts that every live Herdr, Claude, Codex and dsh session on the
      NAS ends, and that DNS, DHCP and the tailnet are down for a few minutes.
- [ ] Anything in `/tmp` worth keeping is pushed or bundled. (It is not lost
      otherwise, only hidden until step 4's archive.)
- [ ] Step 1 is done.
- [ ] Work from the LAN (wired SSH) or the console: step 2 stops `tailscaled`.

## Step 1: subvolumes and first copy (no downtime)

```sh
POOL=/dev/disk/by-id/nvme-WD_BLACK_SN7100_1TB_26051Y809195-part1
findmnt -n -o SOURCE /mnt/fast                     # /dev/nvme0n1p1[/@fast]: same disk
sudo install -d -m 0700 /mnt/pool-top
sudo mount -o subvolid=5,noatime "$POOL" /mnt/pool-top
sudo ls /mnt/pool-top                              # expect @fast @home @snapshots
sudo btrfs subvolume create /mnt/pool-top/@var
sudo btrfs subvolume create /mnt/pool-top/@tmp
sudo chmod 1777 /mnt/pool-top/@tmp
# Pass 1, live. -x stays on the eMMC filesystem: the binds and rpc_pipefs
# become empty mount-point directories.
sudo rsync -aHAX --numeric-ids -x --info=progress2 /var/ /mnt/pool-top/@var/
sudo umount /mnt/pool-top
```

The subvolumes are inert until the gate is on. A pass-1 copy is stale by
design; step 2 brings it current.

## Step 2: flip, final copy, trial reboot (the window)

**2a. The flip commit.** Merge it now, inside the window, not earlier: a
`nixos-rebuild boot` from a `main` that carries it would stage the move for
the next unplanned boot without the final copy. The commit:

- adds `myNas.systemOffEmmc.enable = true;` after `myNas.homeDisk.enable =
  true;` in `hosts/nas/default.nix`, with the comment "O1 phase 2
  (REBOOT-ONLY, see ./system-off-emmc.nix)";
- deletes the four "merging the gate OFF changes no mount" assertions in
  `tests/nas-home-disk/default.nix`;
- in `home/agent-runtime-rules.md` ("Worktrees live under /tmp"), changes
  "`/tmp` ages out after 10 days" to "`/tmp` ages out after 10 days and is
  emptied at every boot".

**2b. Stage it, and set up the one-shot.**

```sh
git -C /home/tom/mecattaf/dotfiles pull --ff-only   # raw dotfiles come from here (AGENTS.md, #313)
fleet-exec strix-coordinator --cwd / -- df -h /     # >= 25G avail, else stop
sudo nixos-rebuild boot --flake /home/tom/mecattaf/dotfiles#nas   # BOOT; switch is refused
ls -l /nix/var/nix/profiles/ | grep system-         # N = the link just made; C = the one before
sudo bootctl list | grep -E 'id:|default'           # both nixos-generation-C.conf and -N.conf listed
sudo bootctl set-default nixos-generation-C.conf    # EFI override: C stays the default
sudo bootctl set-oneshot nixos-generation-N.conf    # N is tried exactly once
```

C is the generation running now. If it was activated by `switch` and never
booted, that is acceptable: the gate-off change leaves the initrd identical.

**2c. Quiesce the writers under /var.** From here DNS, DHCP, SMB, NFS and the
tailnet are down until the reboot.

```sh
sudo journalctl --sync
sudo journalctl --rotate            # current journal files close cleanly
sudo systemctl stop adguardhome.service dnsmasq.service tailscaled.service \
  caddy.service nginx.service handwriting-annotation.service \
  samba-smbd.service samba-nmbd.service samba-winbindd.service \
  nfs-server.service nfs-mountd.service nfsdcld.service
# Anything else holding files under /var (the @fast binds excluded)?
# Expect systemd-journald.service only; stop anything else it lists.
sudo find /proc/[0-9]*/fd -lname '/var/*' -printf '%h %l\n' 2>/dev/null \
  | grep -v -E ' /var/(lib/private/atticd|log/journal/remote)(/|$)' \
  | cut -d/ -f3 | sort -u | xargs -r ps -o unit= -p | sort -u
```

The unit list is the 2026-11-10 scan; the `find` catches anything newer.

**2d. Final copy and the no-loss checks.**

```sh
sudo mount -o subvolid=5,noatime "$POOL" /mnt/pool-top
sudo rsync -aHAX --numeric-ids -x --delete --info=progress2 /var/ /mnt/pool-top/@var/
# 1. Content: a checksum dry run must list nothing outside log/journal/.
sudo rsync -aHAXn --numeric-ids -x --delete --checksum --itemize-changes \
  /var/ /mnt/pool-top/@var/ | grep -v ' log/journal/'
# 2. Entry counts must match (journal aside).
sudo find /var -xdev | wc -l; sudo find /mnt/pool-top/@var -xdev | wc -l
# 3. The paths that must exist. MUST print nothing.
for p in lib/nixos/uid-map lib/nixos/gid-map lib/nixos/declarative-users \
  lib/private/AdGuardHome/AdGuardHome.yaml lib/tailscale lib/dnsmasq \
  lib/samba/private lib/handwriting-annotation lib/systemd/linger/tom; do
  sudo test -e "/mnt/pool-top/@var/$p" || echo "MISSING $p"
done
sudo cmp /var/lib/nixos/uid-map /mnt/pool-top/@var/lib/nixos/uid-map
sudo cmp /var/lib/nixos/gid-map /mnt/pool-top/@var/lib/nixos/gid-map
# 4. @tmp exists and is world-writable sticky (a missing @tmp would let
#    cleanOnBoot empty the eMMC /tmp before step 4 archives it).
sudo btrfs subvolume show /mnt/pool-top/@tmp >/dev/null && sudo stat -c '%a' /mnt/pool-top/@tmp   # 1777
sudo umount /mnt/pool-top
```

If check 1 lists anything outside the journal, or check 3 prints anything,
run 2d again. If it persists, abort without rebooting into N: `sudo bootctl
set-oneshot ""` (C stays the default through the override), start the units
stopped in 2c again, revert the flip commit and `nixos-rebuild boot` with the
gate off, and only then `sudo bootctl set-default ""`. Clearing the default
before that rebuild would leave N, the newest entry, as the default.

**2e. Reboot.**

```sh
sudo systemctl reboot
```

## Step 3: verify on N, then accept

```sh
readlink /run/booted-system                         # generation N
findmnt /var /tmp /nix /home /mnt/fast /var/lib/private/atticd /var/log/journal/remote
stat -c '%a %U' /tmp                                # 1777 root
id tom                                              # uid 1000, groups unchanged
systemctl --failed
journalctl -b -p err | tail
sudo test -s /var/lib/private/AdGuardHome/AdGuardHome.yaml && echo adguard-ok
tailscale status | head -3
# From a client: DNS answers, a DHCP lease renews, `tailscale ping nas`,
# Immich loads, curl -s http://nas:8080/fleet/nix-cache-info
```

Accept by clearing the EFI override; `loader.conf` (generation N) governs
again:

```sh
sudo bootctl set-default ""
```

## Rollback

In every case, keep the EFI override on C until a gate-off generation newer
than N exists: `loader.conf` names the newest entry, which is N until then.

- **N does not come up within about 5 minutes:** power-cycle. The one-shot
  entry is spent, so systemd-boot starts C. C mounts nothing over `/var` or
  `/tmp` and finds the eMMC `/var` as of step 2d. Revert the flip commit,
  check the build host, `sudo nixos-rebuild boot` with the gate off, and only
  then `sudo bootctl set-default ""`. (A `switch` from C to a `main` that
  still carries the flip is refused by the inhibitor; revert first.)
- **Stall in stage 1:** initrd SSH on `10.42.0.1:2222` or the console's
  emergency shell to read `journalctl -b`, then power-cycle as above.
- **A problem found days later, before step 4:** C must still be listed
  (`sudo bootctl list`; `configurationLimit` is 3, so do this before two more
  generations are built). `sudo bootctl set-default
  nixos-generation-C.conf` and reboot. On C the eMMC `/var` is as old as the
  flip, and everything written since is on `@var`. Before relying on C, stop
  the 2c writers, mount the pool top as in step 1 and copy the state back
  without deleting anything on the eMMC: `sudo rsync -aHAX --numeric-ids -x
  /mnt/pool-top/@var/ /var/`. Then revert the flip commit, `nixos-rebuild
  boot` with the gate off, `sudo bootctl set-default ""` and reboot into
  that generation, so the services start on the restored state.

## Step 4: after seven clean days, reclaim the eMMC

Both checks below must pass before anything is deleted.

```sh
sudo install -d -m 0700 /mnt/emmc-root
sudo mount --bind / /mnt/emmc-root                  # non-recursive: the eMMC root alone
findmnt -n -o SOURCE /mnt/emmc-root                 # MUST print /dev/mmcblk0p2
mountpoint -q /mnt/emmc-root/var && echo STOP; mountpoint -q /mnt/emmc-root/tmp && echo STOP
sudo du -xsh /mnt/emmc-root/var /mnt/emmc-root/tmp
```

**4a. Old /var: files that exist only in the old copy.**

```sh
sudo rsync -aHAXn --numeric-ids --ignore-existing --out-format='%n' \
  /mnt/emmc-root/var/ /var/ | grep -v '/$'
```

Expect only what services removed on `@var` since the flip (vacuumed journal
files, rotated logs). Copy back anything that matters before going on.

**4b. Old /tmp: archive, then verify the archive.** It holds whatever the
sessions left there up to the reboot (8.9G on 2026-11-10, 24G on 11-05),
possibly with credentials, so it goes where O1 phase 0 put the old home:
root-only, unmirrored, deleted after 30 days if nobody needed it.

```sh
df -h /mnt/nas                                      # room for it
# For the record: git work trees in the old /tmp (check them for unpushed work)
sudo find /mnt/emmc-root/tmp -xdev -name .git -prune -printf '%h\n' 2>/dev/null
A=/mnt/nas/services/archive/nas-emmc-tmp-$(date +%F).tar.zst
sudo install -d -m 0700 /mnt/nas/services/archive
sudo tar --one-file-system --xattrs --acls -C /mnt/emmc-root -cf - tmp \
  | zstd -T4 -6 | sudo tee "$A" >/dev/null
sudo chmod 0600 "$A"
sudo zstd -t "$A"
# Entry counts must match (tar skips sockets, so they are left out of both).
sudo find /mnt/emmc-root/tmp -xdev ! -type s | wc -l
sudo zstd -dc "$A" | tar -tf - | wc -l
```

**4c. Reclaim.** NixOS marks `/var/empty` immutable (`h /var/empty - - - -
+i`), so clear that first or `rm` stops on it.

```sh
sudo chattr -i /mnt/emmc-root/var/empty
sudo find /mnt/emmc-root/var /mnt/emmc-root/tmp -mindepth 1 -maxdepth 1 \
  -exec rm -rf --one-file-system {} +
sudo rm -rf /mnt/emmc-root/root/.cache
sudo umount /mnt/emmc-root && sudo rmdir /mnt/emmc-root
df -h /                                             # about 1-2G used once phase 0 is done too
```

**4d. Tighten the root alert.** Commit `myNas.storageAlerts.rootThreshold =
25;` in `hosts/nas/default.nix`, check the build host's free space, and
`sudo nixos-rebuild switch` (safe now: no mount changes and the inhibitor
value is the same on both sides).

From step 4 on, C and every older generation must never be booted: their
`/var` is gone. With `configurationLimit = 3` they leave the menu after three
more generations.

## Not verified

- Nothing above has run. The module was built on strix-coordinator with the
  gate off, and with it on through an uncommitted override; the gate-on boot
  itself is untested.
- How `switch-to-configuration` would treat the new mounts is moot while the
  inhibitor stands; it was not tested either.
- The writer list in 2c is the 2026-11-10 scan.
