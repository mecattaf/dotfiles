# dshd on NAS: preparation and deploy gates

This is the dotfiles implementation of dshd D16, from
`dshd.nix/doc/planning/DECISIONS.md`. Any failed or uncertain gate defers the
switch. Part 1 prepares this branch only: no release pin, push, merge, NAS switch,
instance, or real-dsh edge check is performed here. The CLI is still changing.

The integration consumes the existing `programs.dsh.package`, with only
`permissive = true` overridden for the release. PATH keeps its restrictive dsh.
Both use the existing llm-agents runtime. The ordinary native home is `~/.dsh`;
an explicit `DSH_HOME` selects a different native account. Agency Web keeps its
own home, units and processes. Nix declares no instances, timer or autostart.

The upstream implementation currently exposes `services.dshd`, reserves the
release name `default`, and makes `/etc/dshd/releases/default` point at the only
declared release. Dotfiles therefore declares `services.dshd.releases.nas`, with
no `defaultRelease` and no environment additions. This corrects D16's option
spelling and release-name example by H1 (use the producer's actual module) and
H5 (no compatibility shim). The release's `unsetEnvironment` is the wrapper's
ambient-secret list; telemetry is already set at exec. Recheck the published
module before pinning if the producer changes it again.

Permissive mode removes the fleet's section-7 overrides. Native DSH's own
`sandbox`, `sandbox-policy`, `approval` and `permission` rows remain, including
its `DSH_PERMISSION_MODE` expressions and full-access preset. D16's literal
absence of these composed rows would break native permission selection (H0).
`dsh-config` verifies their native form and the exact fleet policy minus section
7. It also accepts web and retained `acp@...` profiles without stderr.

Native web presets have separate agent-scoped plugin declarations. DSH's patch
loader descends only through host `group: true` rows, not preset
`config.plugins`. The checker follows that same boundary and separately refuses
scoped copies of protected providers/exporters. Current presets inherit the
disabled host DeepSeek, telemetry and plugin-manager services; the scoped
plugin-manager tool cannot activate without that service. The host's section-8
workflow cap stays, while native web presets retain their own capacity-based
concurrency. This corrects D16's implied all-scopes cap by H0 (preserve native
composition), then H5 (no profile transformer or overwritten preset configs).

## Resume prerequisites

1. Require the producer's complete compute check batch, including its switch VM,
   to be green for the published `v0.1.0` commit. Record the commit and receipts.
2. Pin that public commit/tag in `flake.lock`; no `git+file:` or path lock entry
   may be committed. The source input remains `github:mecattaf/dshd.nix` with
   nixpkgs following dotfiles. Existing lock nodes must remain unchanged.
3. Add and pass the **mandatory real-dsh edge gate** on compute, with the final
   CLI: web, ACP, headless, honest TUI refusal, client disconnect/reconnect, stop
   and remove. Run runtime-sensitive experiments through compute's
   `~/.local/bin/runtime-test -- ...`. This gate precedes every NAS switch; the
   older D14 optional wording does not apply. This document deliberately gives
   no lifecycle commands while the CLI is unsettled.
4. Complete the dotfiles checks, merge and push only in the resumed task. Bring
   the approved commit into `~/mecattaf/dotfiles` using a fast-forward before
   switching: NAS's raw files come from that checkout, including when the flake
   used for a switch is a worktree. Record the old and candidate commits.

## Read-only NAS preflight

Run gates as Tom on NAS. `tests/dshd-deploy/gates.py` uses only reads and emits
results on stdout; shell redirections below write receipts under `/home`, on
NVMe. It never starts/stops a unit, sends a signal, reloads a manager or reads
process environments/credential values. A nonzero result means stop. Keep all
stderr and complete outputs. Inspection failures are not a pass.

```bash
repo=/home/tom/mecattaf/dotfiles
receipt=/home/tom/.local/state/dshd-deploy/v0.1.0
install -d -m 700 "$receipt"
gate="$repo/tests/dshd-deploy/gates.py"
df -h / /nix /home /boot
nix config show max-jobs
nix config show builders
systemctl --user --no-pager --all list-units 'agency-web*' 'herdr*' 'dshd@*'
```

**Space is a real block, not a build-cache problem.** On 2026-11-10 NAS `/` is
the 57 GB eMMC with only about 211–291 MB free. `/nix` and `/home` have about
670 GB on NVMe, `/boot` about 929 MB. Do not infer activation headroom from NVMe
space. Before dry activation or switch, account for candidate writes to `/etc`,
`/var` (including logs), boot entries and other eMMC paths, and establish enough
root headroom for them. If that cannot be demonstrated, defer. Do not run GC,
delete generations, restart services, or attempt a blanket cleanup to pass this
gate. Keep build scratch space, receipts and staged sources on `/home` or `/nix`.
NAS's configured builders must still use strix-coordinator and zero local jobs;
strix-worker stays dormant. Do not change those settings or fall back locally.

### Evaluate identity and user units before building

After the release is pinned, these commands evaluate without building:

```bash
nix eval --json "$repo#nixosConfigurations.nas.config" --apply '
  c: {
    dshDrv = c.home-manager.users.tom.programs.dsh.package.drvPath;
    homeManager = toString c.home-manager.users.tom.home.activationPackage;
  }' > "$receipt/candidate-identity.json"
python3 "$gate" identity "$receipt/candidate-identity.json"
```

`identity` compares the restrictive dsh derivation against the package actually
installed in `/etc/profiles/per-user/tom/bin/dsh`, and the HM generation against
the actual live `home-manager-tom.service` ExecStart. Equality against a
convenient source baseline alone does not satisfy D16. The live fleet revision
on 2026-11-10 reports `dirty: true, rev: unknown`; do not pretend that
`9142c18e` necessarily describes that generation. An unknown live deriver also
defers deployment.

For the evaluation-only unit gate, select an exact baseline flake whose evaluated
user tree is the live directory. Start with the branch's original base:

```bash
baseline_rev="$(git -C "$repo" rev-parse 9142c18e)"
baseline="git+file://$repo?rev=$baseline_rev"
projection="$(cat "$repo/tests/dshd-deploy/user-tree.nix")"
nix eval --json "$baseline#nixosConfigurations.nas.config" \
  --apply "$projection" > "$receipt/baseline-user-tree.json"
nix eval --json "$repo#nixosConfigurations.nas.config" \
  --apply "$projection" > "$receipt/candidate-user-tree.json"
python3 "$gate" eval-user-tree "$receipt/baseline-user-tree.json" \
  "$receipt/candidate-user-tree.json"
```

The gate first requires `baseline.userTree` to equal the resolved live
`/run/current-system/etc/systemd/user`. It then compares the systemd package,
unit packages, additional upstream units and every declared unit's complete
rendered text, generated unit path and link metadata. Only `dshd@.service` and
`dshd.target` may be added. The target's `default.target.wants/dshd.target` link
is part of the target addition; it enables no instance. If the baseline is not
live, recover the actual generation's source or defer; weakening the equality
would violate H0 zero disruption.

While preparing before publication only, add
`--override-input dshd git+file:///home/tom/mecattaf/dshd.nix --no-write-lock-file`
to candidate evaluations. Never persist that override in a lock or use it for a
NAS deployment. The parent branch's baseline has no dshd input.

### Compute build and dry activation

Use NAS's configured SSH builder: NAS evaluates, Nix sends source/build inputs
to strix-coordinator and returns the built closure. Immediately before
**every** `nix build`, inspect compute's `df -h /` and require at least 25 GB
free. Existing `max-jobs = 0` stays in force:

```bash
ssh -o BatchMode=yes -o StrictHostKeyChecking=yes strix-coordinator df -h /
# Proceed only after the 25 GB check above passes.
nix build --no-link --print-out-paths --max-jobs 0 \
  "$repo#nixosConfigurations.nas.config.system.build.toplevel" \
  > "$receipt/candidate-path"
candidate="$(cat "$receipt/candidate-path")"
```

Ensure `$candidate` is the result of the pinned candidate evaluation. Keep the
build log showing execution on `ssh-ng://tom@strix-coordinator`. For heavy
commands outside Nix, stage non-secret source on compute first and use
`fleet-exec strix-coordinator --cwd /absolute/remote/checkout -- ...`.

Once the closure is present, independently compare the realized tree too:

```bash
python3 "$gate" user-tree "$candidate/etc/systemd/user"
```

Only the two new unit files and `default.target.wants/dshd.target` may be added;
every existing file's bytes and wants/alias links must match. This reads store
files, never the user manager's runtime directory. It complements the earlier
evaluation-only gate.

After establishing eMMC headroom, run `nixos-rebuild dry-activate` with NAS's
existing remote-builder configuration and no local build jobs:

```bash
set -o pipefail
sudo nixos-rebuild dry-activate --flake "$repo#nas" --max-jobs 0 \
  2>&1 | tee "$receipt/dry-activate.log"
```

Require a successful command **and review the complete output**. It must list
no system or user unit to stop, restart or reload. Do not filter away failures,
accept an unexpected action, or substitute a successful build for this gate.
The already-built result must match `$candidate`. Re-evaluate after any source,
pin or live-generation change; earlier receipts then no longer authorize a
switch.

## Idle, snapshot, switch, compare

Identify the actual deploying Herdr pane from `herdr pane list`; pass its exact
ID explicitly. The gate calls the existing update-check `busy_reasons()` and
excludes only that pane's exact reason, preserving every load, builder,
activation and other active-pane refusal. No new idleness policy is copied.

```bash
python3 "$gate" idle --deploying-pane "$deploying_pane" \
  > "$receipt/idle.json"
```

When busy, wait and rerun this check. Do not mark other panes idle, stop their
work, or treat a failed Herdr inventory as idle. Rerun immediately before the
snapshot/switch window, after all builds and dry activation have finished.

```bash
python3 "$gate" snapshot > "$receipt/before.json"
```

Snapshot captures boot identity; InvocationID/MainPID/state/cgroup of
`user@<uid>.service`, `herdr.service`, `herdr-web-ui.service` and
`agency-web.service`; plus PID, start ticks and cgroup of every visible native
dsh process, including node-launched entrypoints. No argv or environment is
written. `--agency-unit UNIT` can be repeated if Agency Web has more live owners
or runs in a different user scope; include every discovered owner. A disappearing
process makes the snapshot uncertain: retry the snapshot rather than ignoring
the race. Both snapshots must have no `dshd@*` instances.

Only after every gate above passes, during the resumed deployment:

```bash
sudo nixos-rebuild switch --flake "$repo#nas" --max-jobs 0
python3 "$gate" snapshot > "$receipt/after.json"
python3 "$gate" compare "$receipt/before.json" "$receipt/after.json"
```

Use the same explicit Agency Web owner arguments in both snapshots if supplied.
Require identical protected unit identities and every earlier dsh PID/start
time/cgroup still present; this conservative comparison also refuses an
unexpected new dsh. Inspect/report any full diff verbatim. Do not repair it by
restarting Herdr, Agency Web, the user manager or another live session. Do not
use `boot`, reboot, GC, or generation deletion as deployment steps.

The subsequent first real NAS use remains a separate resume step: the final-CLI
web instance starts over SSH, the SSH connection ends, reconnect reaches the
same owner, and stop/remove completes. Compare the protected snapshot again
after that instance has been removed. The mandatory compute edge gate above
must already have passed. Desktop human acceptance remains Tom's.

## Retention check

The producer's current layout registers indirect release roots at
`<manager-state>/dshd/<name>/current` and `booted`, and copied profile store
roots below `gcroots/`. With NAS's ordinary manager state this is
`/home/tom/.local/state/dshd/...`. Confirm the published layout and the manager's
`XDG_STATE_HOME` with read-only inspection before first use; it must remain on
durable `/home`, outside `/tmp`.

`modules/gc-root-reaper.nix` deletes auto-root links only when their target is
dangling, or when their target is under `/tmp` and at least seven days old.
Existing `current`, `booted` and profile roots under `~/.local/state` satisfy
neither condition and are preserved. Do not run that reaper, register a test
root, or run GC to demonstrate this against live sessions.

## Preparation findings, 2026-11-10

The restrictive baseline from `9142c18e` and this change have the same package
derivation (`817hf4b4sl2xl79kq07r610yvfghza9v-dsh.drv`) and Home Manager
generation derivation (`kwhs8vi883qjp4vkfqd5a5iw56d8fqk5-home-manager-generation.drv`).
Home Manager's keyed entrypoint remains the same as the branch baseline too
(`gnzrj7dgv0mf1xjfdm2f8s6aw4z747an-dsh.drv`). These are branch comparisons;
they do not describe the running NAS.

The actual live gates **refuse deployment**:

- Installed dsh is `2khczd78p5pg0d6zxsx1w15rz9gf3jfi-dsh.drv`, and live HM is
  `zxvjb21k8xhs78mbr9s15lhfwh0nj07b-home-manager-generation`. Live dsh still
  contains the retired DS4 dummy bearer/policy and an older kitty-native plugin
  path. This is pre-existing drift from the supplied main baseline; do not
  reintroduce that retired route to manufacture equality.
- The supplied baseline's evaluated user tree is not the live tree. Candidate
  evaluation adds the two expected dshd units, but also changes
  `dbus-broker.service`'s `X-Restart-Triggers`. NixOS feeds the complete
  `system.path` into its D-Bus configuration; the added CLI and the revisioned
  `nixos-version` package change that input even without new bus services.
  Merely omitting dshd from that scan still leaves the revision change. Under
  H0 the exact-unit and no-reload gates stay closed. The resume must resolve
  this before dry activation/switch; no old trigger path is frozen and no gate
  exception is granted here.
- The initial idle probe refused load and concurrent Nix work; a later probe
  with no pane excluded was idle. This is no future deployment authorization:
  rerun with the actual deploying pane immediately before switching. Root
  headroom remains unestablished.

Two consecutive read-only live snapshots matched, including `user@1000`,
Herdr, Herdr Web UI, Agency Web and native dsh PID 5570; no dshd instance was
present. No dry activation, NAS switch, GC, generation deletion or service
restart was performed. Published-release qualification, final-CLI real-dsh
edge checks and first real NAS use remain for the resumed task.

Preparation checks passed: NAS toplevel derivation evaluation; `dsh-config`
(restrictive and permissive dumps/refusals), `dshd-nas` (brain-only wiring and
unit contract), `dsh-plugins` and `dsh-zen`, built by the configured
strix-coordinator builder with NAS `max-jobs = 0`. Strix `/` had 149 GiB free
before each build request. Nix formatting, Python parsing, unchanged lock and
whitespace checks passed. A runtime-isolated user-tree smoke accepted the two
units plus wants link and rejected changed bytes, changed link targets and
removed units. The manager state root was confirmed as
`/home/tom/.local/state`; the producer roots there are outside the reaper's
`/tmp` policy. These checks used the uncommitted local input override only;
they do not qualify the future published tag.
