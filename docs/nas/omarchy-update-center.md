# Omarchy offers from the NAS

`myNas.omarchyUpdateCenter.enable` installs a manual publisher, a private HTTP
manifest endpoint at `http://100.64.0.1:8091`, and a daily cache keepalive. It does
not extend the house `update-center` build list or activate laptops. Laptops poll;
owners click the native Nix dock indicator, read the notes, and explicitly accept.
Choosing **Not now** changes nothing. Publication does not open a popup or install.

Prepare a reviewed commit in `omarchy-fleet`, including its committed lock file.
The NAS must be able to read the source: an absolute Git checkout **on the NAS**,
or a reachable HTTPS Git repository. Until the fleet has a remote, transfer a
private depth-one Git clone to the NAS; preserve `.git` and the candidate commit.
Use `git clone --depth=1 --no-tags --single-branch file:///home/tom/mecattaf/omarchy-fleet`
into a private temporary directory, remove its `origin`, and verify that
`git rev-list --all --count` is exactly one and `git rev-parse HEAD` matches the
reviewed candidate. Stream a tar archive over pinned SSH into a new root-only
directory beneath `/var/lib/omarchy-update-center/private/sources/COMMIT`.
Do not copy the original `.git` directory: that would include historical objects.
The publisher detects an absolute local shallow checkout and supplies Nix's
required `shallow=1` flag while still pinning and verifying the full revision.
Keep that transfer private: publishing the repository or its
history requires completing the credential-history audit first.
A working tree without its Git objects is not a valid source. Local uncommitted
changes do not enter a candidate pinned by `--revision`.

Run on the NAS, using the full 40-character commit ID:

```sh
sudo omarchy-update-publish \
  --source /path/on/nas/omarchy-fleet \
  --revision FULL_40_CHARACTER_COMMIT \
  --notes-file /path/on/nas/release-notes.txt
```

Both `xps` (Omar) and `zenbook-duo` (Marwan) build by default. `--devices xps`
publishes an offer only for the Dell. Each published manifest describes one
revision; omitted devices have no offer in that publication. Notes are plain
text, nonempty, at most 4000 characters, with no control characters except tabs
and newlines.

The transient `omarchy-update-publish.service` has an eight-hour runtime ceiling,
12 GiB memory ceiling and low scheduling priority. Nix runs one build at a time,
with two cores, no remote builders, and no lock-file updates. It selects only
the requested fleet toplevels; this job has no model-weight synchronization step.
The candidate is pushed in full to the existing signed Attic `fleet` cache,
including paths that also exist upstream, with at most three concurrent path
uploads. This bound also applies to keepalive. The first-fill measurement found
the single-path upload using about 1.3 CPU cores in Attic on an eight-thread NAS,
with the disk mostly idle; three paths allow parallel server work while retaining
CPU headroom. The uploader's resource limits do not cap the separate Attic server,
so this is a path-concurrency bound rather than a three-core CPU quota.
Only successful pushes are signed
with `/etc/ssh/ssh_host_ed25519_key` under namespace `fleet-update`.
Push tokens are short-lived and minted locally through `atticd-atticadm`, whose
wrapper loads the existing protected signing environment. Do not print tokens,
enable shell tracing, or put tokens or signing keys in release notes.

`/manifest.json` and `/manifest.json.sig` resolve through an atomically replaced
`current` symlink. The JSON fields are exactly `schemaVersion` (1), `revision`,
`publishedAt` (`YYYY-MM-DDTHH:MM:SSZ`), `notes`, and `devices`; each device contains
only `toplevel`. Clients verify the signature against their pinned NAS host key
with principal `nas`, read signature/manifest/signature to detect publication
races, and separately require the existing Attic cache signature for store paths.
Clients reject offers older than 90 days or more than five minutes in the future.

Current and previous publications retain their own Nix GC roots. A failed build,
push, or signing operation leaves the existing offer intact. Successful
publication removes older release directories and their roots; it does not run
global garbage collection. A later publication also clears interrupted staging
roots. The daily `omarchy-update-keepalive` job repushes any missing retained paths
and makes body-free HEAD requests to their Attic NAR endpoints. Attic's NAR handler
refreshes last access; merely probing narinfo or pushing already-cached paths does
not. This keeps armed updates available through Attic's month-cold retention.
See the upstream [NAR handler](https://github.com/zhaofengli/attic/blob/main/server/src/api/binary_cache.rs)
and [missing-path lookup](https://github.com/zhaofengli/attic/blob/main/server/src/api/v1/get_missing_paths.rs).

```sh
sudo journalctl -u omarchy-update-publish -n 100
sudo systemctl start omarchy-update-keepalive
sudo systemctl status omarchy-update-keepalive.timer
```

`myNas.omarchyUpdateCenter.keepalive.enable = false` parks its timer; the manual
service remains. There is no build timer and no laptop activation credential.
The manifest listener binds only the NAS Headscale address, and the firewall
admits its two distribution ports (8091 and Attic 8080) on that interface.
Headscale ACLs provide the device-level access restrictions.

## Deployment receipt — September 10, 2026

NAS deployed from dotfiles `9a84225e` with deploy-rs confirmation at 10:07 Paris.
Running system: `/nix/store/h1l9kyjn5s0257kyw1hm7h78qpq4sags-nixos-system-nas-26.05.20260731.5b4f72e`.
Headscale, tailscaled, nginx and resolved were active; failed system units: zero.
The live policy matched the restrictive repository policy. Manifest listener:
`100.64.0.1:8091` only. Coordinator SaaS Tailscale remained online at
`100.105.121.73`. The earlier 09:33 baseline deployment (`ef326be3`) passed
empty-state keepalive; its pre-deploy identity snapshot and post-deploy service
snapshot both passed isolated restore verification.

The first real offer was published successfully at 10:40:33 Paris
(`2026-09-10T08:40:33Z`), replacing the initial expected 404. Its exact fleet
revision is `7e0a1cac478fb5b268ca3c1b1fc4cf6672911dde`, transported as a private
depth-one Git checkout without the credential-bearing repository history.
Both final closures were built and validated on the coordinator, copied only to
the NAS for publication, and realized there without further compilation:

| Device | Published toplevel |
| --- | --- |
| Dell / Omar (`xps`) | `/nix/store/6pgphnadzs2r707k1p5jcghqwlh927vq-nixos-system-xps-26.05.20260727.2f5a153` |
| ASUS / Marwan (`zenbook-duo`) | `/nix/store/fibjw887qfy4s0m7sbxffc90zqmn5gfv-nixos-system-zenbook-duo-26.05.20260727.2f5a153` |

The actual fleet client verified the HTTP manifest/signature pair against the
pinned NAS host key, checked both device entries and release notes, and rejected
a deliberately altered manifest. SHA-256 receipts:

- Manifest: `c865c79aa2a9d0bef6e4ac57fbee68f5d2ede1a508e46ca375a4eabf3d71c238`.
- Signature: `cf4e57009476ca0d9dba3264eb5aff9e2f02be8acad1fab6036f0e1da0655164`.

All 2,883 closure paths were present in Attic, representing 21,849,683,296
uncompressed NAR bytes. Recursive verification against the direct fleet HTTP
cache passed with one required signature and only the pinned fleet cache key;
this was metadata-signature verification (`--no-contents`), not a full NAR
content download. The final three-job publication completed successfully in
33 minutes 22 seconds, reusing paths uploaded before that run.

Manual `omarchy-update-keepalive` then succeeded at 10:41:03 Paris in 11.3
seconds: all 2,883 paths were already cached, all received body-free NAR HEAD
retention refreshes, and no builds or laptop changes occurred. Peak service
memory was 55.7 MiB. Repeating actual client verification afterward confirmed
the manifest and signature hashes above, timestamp, revision and device paths
were unchanged.

Both laptops subsequently installed this actual signed candidate through the
fleet update client: ASUS at 10:41:38 Paris and Dell at 10:41:45 Paris. The
coordinator verified their running systems, system profiles, configuration
revision, successful client result and signatures against the published
candidate. This was operator-directed commissioning; owner GUI acceptance and
a live rollback exercise have not been performed or claimed.

At this initial receipt, owner GUI acceptance, live rollback verification and
public HTTPS/hotspot acceptance were still outstanding. Later receipts below
cover app installation; [the public Headscale checklist](overseas-headscale.md)
records the subsequently verified public transport and remaining laptop migration.

## Native-dock commissioning incident — September 10, 2026

The NAS built and published fleet `0fb5e3dcb163ea325f8386d3f2874f1db6402676`
at 11:01:06 Paris, without receiving prebuilt system closures from the
coordinator. Publication took 4m28s and pushed 77 new paths, reusing 2,803.
This preparatory release did not enable the two AI desktop apps.

Commissioning exposed a laptop installer dependency error: replacing the
cache-relay service stopped its `Requires=` dependent installer during
activation. The live systems stayed on `7e0a1cac` but their profiles had advanced.
Both exact previous profiles were restored and reactivated successfully;
running system and profile matched again, with the desktop, fleet rail and
cache relay active and no failed system units. The faulty offer was withdrawn:
`current` and `previous` pointed to the original signed `7e0a1cac` publication,
whose hashes above remained unchanged.

The withdrawn manifest and signature were archived privately under
`private/incidents/0fb5e3dcb163ea325f8386d3f2874f1db6402676`, with SHA-256
`7f718ed270aca0b1d85e58b13b76e53cfa55aabefd2064f7e13e502dcda16304` and
`6c72f588186f2cd84783aa70cc3d224667fc65b5e92757f668216e22a116824a` respectively.
Normal publisher retention may now prune the withdrawn public release without
losing that incident receipt. No owner-approved app installation is implied.

The corrected preparation `099cc20b1cf50aaf7a3443c58bda5962390960d4` was built
and published on the NAS at 11:25:51 Paris in 1m44s, with 49 new paths and
2,831 reused. Its manifest/signature SHA-256 values are
`ab81dd2209c87e00398e58d5be8b907e86ed5dffbb4573a7ae11e2266a582169` and
`4f0a7f81883e71c23ef91d3d5ef07c4006adb9665783ef336c0e01c21cf6b06f`.
Both laptops installed through independent commissioning units, preserving
signature verification and NAS-only closure copying while avoiding the original
unit dependency. Dell completed at 11:27:12 and ASUS at 11:27:44 Paris, with
matching running/profile paths and no failed system units. Native dock loading
and the active owner's scoped approval permission were checked after fresh
desktop sessions. The following two-app release remains a separate owner decision.

## App offer ready — September 10, 2026

NAS-built fleet `470fae7f9d9eead6d58c5ba21c61d92b4ddff80c` adds ChatGPT and
Claude desktop. Published at 11:38:36 Paris after 8m02s, including 106 newly
cached paths. Manifest/signature SHA-256 values:
`989860f219236375ad74f159fb117efd6abf4d007b5010a79dd3502362aa51ba` and
`3643060493b87a530df2dcac945332446cab55efc016624216f61b4cf912590c`.
Both laptops verified the offer and reported native-widget availability while
their installed systems and profiles remained on the corrected preparation.
The operator did not accept or install this app offer.

Current app and previous preparation closures passed recursive pinned-cache
metadata-signature checks. Manual keepalive refreshed all 3,302 retained paths
in 13.2 seconds, without building or activating anything. Only the two temporary
app-prefetch root links were removed, after current publication roots proved
both packages retained. No store data or recovery archive was deleted.

The [encrypted identity recovery receipt](fleet-identity-backup.md) records the
protected NAS and coordinator copies, verification scope and decryption caveat.
Overseas control-plane provisioning remains distinct from this successful local
offer-delivery test.

## Public-control preparation and pending kernel — September 10, 16:12 Paris

Both laptops subsequently accepted the app offer; later read-only checks matched
their installed targets and signatures. That app release remains the public offer.
The [public Headscale transport](overseas-headscale.md) now passes disposable
registration, restart recovery, off-LAN migration and signed/cache access tests.
The real shipped laptops still need their one-time control-URL migration and
unrelated-network checks. Nothing in this preparation round contacted them.

Kernel 7.2.4 with the ASUS-only VMD fix is **still building, not ready to install**.
The original `omarchy-kernel-89f703a-build.service` is unchanged. Queued
`omarchy-final-bc866db-build.service` waits for that kernel and then builds both
runtime candidates from exact private revision
`bc866db28b920794e20e6bcb6e21a28c894c56ea`. Later migration-tool/documentation
commits do not change those runtime candidates. Neither unit publishes an offer.

A separate capped `omarchy-final-bc866db-verify.service` waits for both final
roots and verifies their exact pinned revisions/closures, kernel version and
actual ASUS initrd modules/early-load entries, archived VMD bytes and final
interrupt ordering. Its root-private result is:
`/var/lib/omarchy-update-center/private/build-only-bc866db/verification.json`.
Missing receipt means **pending/unverified**, never success. PASS is artifact
verification, not a physical ASUS boot test, owner consent or publication.

The coordinator retains the full status/verification recipe at
`/home/tom/.local/share/fleet-recovery/nas/kernel-build-bc866db-status.md`.
All builds and checks run independently with bounded resources; there is no
automatic publication, activation or reboot. Public endpoint migration does
not require this new kernel and can proceed separately after local-console GO.
