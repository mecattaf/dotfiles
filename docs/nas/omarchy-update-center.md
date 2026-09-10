# Omarchy offers from the NAS

`myNas.omarchyUpdateCenter.enable` installs a manual publisher, a private HTTP
manifest endpoint at `http://100.64.0.1:8091`, and a daily cache keepalive. It does
not extend the house `update-center` build list or activate laptops. Owners poll,
read the notes, and explicitly accept; closing the notification changes nothing.

Prepare a reviewed commit in `omarchy-fleet`, including its committed lock file.
The NAS must be able to read the source: an absolute Git checkout **on the NAS**,
or a reachable HTTPS Git repository. Until the fleet has a remote, transfer a
private Git bundle to the NAS and clone it there; preserve `.git` and the
candidate commit. Keep that transfer private: publishing the repository or its
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
including paths that also exist upstream. Only successful pushes are signed
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
