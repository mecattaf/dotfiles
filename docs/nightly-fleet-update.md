# Nightly fleet updates

The Floor owns the existing 01:17 Europe/Paris trigger. Its DSH maintenance
tool invokes the fixed `/run/current-system/sw/bin/fleet-update-start --json`.
That starts `fleet-update.service` in Tom's NAS user manager. There is no local
timer, boot trigger, second nightly schedule, or model-dependent build step.

The separate service is necessary: the harness has `NoNewPrivileges` and its
model shell is sandboxed. Neither receives broader privileges. The fixed user
service retains NAS GitHub/SSH authentication and can call only the installed
target assessment/activation helpers through its sudo rules. Credentials and
harness sessions remain on NAS; the dormant worker receives no work.

## What a run does

`lib/fleet-update.json` selects the four package sources: compute nixpkgs, NAS
stable nixpkgs, the fresh leaf overlay (including Tailscale), and llm-agents.
Updates mean versions available from these configured Nix branches. Explicitly
pinned hardware, inference engines, Home Manager releases and project tools
remain deliberate source changes; no upstream binary/npm installer bypasses
the Nix package graph.

Each job first prepares an llm-agents-only candidate, tests/builds both system
generations on strix-coordinator, adopts its lock-only commit and installs it
when each target is idle and safe. This advances Claude Code, Codex and DSH
without coupling their new-launch versions to a Tailscale or base-system change.
It then prepares a full candidate from the selected package sources using the
same pipeline. Source and flake input trees are staged on compute; credentials
are never copied or forwarded. `df -h /` and a 25 GiB minimum gate precede every
actual build. Both system outputs and the relevant test derivations are built.

Exact output paths receive GC roots as part of `nix build`, outside disposable
source staging. Pending candidates survive GC. Roots for the newest three
resolved jobs are retained; pending jobs and installed/previous profiles are
preserved. Main adoption uses compare-and-swap against the tested base, never
an overwrite of intervening work. A dirty canonical checkout, another branch,
source drift or changes beyond `flake.lock` defer source adoption.

Before adopting a full candidate, both targets receive a fresh assessment so
unsafe base pins cannot become the following night's program-only baseline.
The installer repeats target admission under its deployment lock immediately
before the switch. It reads Herdr statuses on NAS, Nix work/load on each target,
and both Gufo processing/deferred metrics on compute. Unknown is pending.

Safety also includes NixOS dry activation, recursive inspection of changed
activation/switch entry points and helper files, Home Manager activation code
and active user units. Helper code is inspected before running dry activation.
Store-path normalization alone is never safety evidence. Herdr's native
`X-SwitchMethod=keep-old` is honored; any proposed start/restart/reload of transport,
user managers, inference or other protected services remains pending. Previous
generations are retained, protected service PIDs are checked after installation,
and actual installed command versions are verified through Tom's managed
profile. Existing sessions keep the executable they started with.

**Tailscale remains staged whenever its update requires a transport restart.**
Peer activity alone cannot prove that restarting the NAS exit/subnet router is
safe. Such candidates need a proven transport-idle or attended window. A kernel
candidate never causes an automatic reboot. Unknown activation effects likewise
remain visible exceptions; no failed activation triggers a blind rollback or
service restart.

## Durable execution and receipts

The user service outlives the DSH turn. A held file lock prevents concurrent
jobs; owner identity includes host, boot ID, PID and process start time. Busy
or unavailable targets remain pending. The same worker checks again after
60 seconds and reuses successful stages, rather than adding another schedule.
Each later Floor firing writes a nightly request through the fixed launcher.
If the prior candidate is still pending, its work is coalesced into the newest
night's candidate, with a `superseded_by` receipt. The desired full
upgrade remains pending while newer safe program updates can advance.

State lives at `~/.local/state/fleet-update/`: `active.json`,
`jobs/<night>.json`, the nested `<night>-programs.json`, stage logs, launch
receipts and terminal `completions/<night>.json`. A launch receipt has
`ok: false`; only verified completion has `ok: true`. Failures stop the worker.
Interrupted/failed non-idempotent stages require an inspected `--retry-failed`,
so a bad derivation is not rebuilt every minute. No PID-only stale-success test
is used.

```console
fleet-update-start --json                 # fixed routine/service entry point
fleet-update --status --json              # durable progress, no activation
fleet-update --resume 2026-10-28 --json    # resume exact job in the foreground
fleet-update --background --json          # detached worker for a manual run
fleet-update --prepare-only --json        # build the first candidate; do not adopt
fleet-update --resume 2026-10-28 --retry-failed --json
```

Foreground exit codes are 0 for verified completion, 75 for durable pending and
1 for failure. The service launcher returns accepted/starting, never completion.
`worker_status: interrupted` identifies a dead worker independently of its last
stage receipt. `update-check` remains the manual release-note/rolling-PR tool;
its build gate now refuses to run outside strix-coordinator and never builds on
the dormant worker. The nightly service uses `fleet-update` instead.

Commissioning requires installing this module and the trusted DSH tool, then
measuring a complete controlled transaction on both actual targets. Unit/check
builds, a PR and an enabled schedule do not establish that the fleet is updated.
