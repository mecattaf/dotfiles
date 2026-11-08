# Measured practice results — 2026-11-04

The harness is implemented and run. The tested desktop is **not fully green**:
10 of 11 required checks passed in each complete run. Shutdown after the
intentional engine crash leaves one owned backlight monitor. The runner returns
1 and preserves that failure; its final identity-scoped cleanup leaves no owned
processes. This is an implementation/test result, not Zenbook acceptance.

Source base: `efa52f55eb3052106cc8b808e762e503b46a606d`.
Upstream source inspected: `/home/tom/compute/domicile-release`,
`67c29a9906905bd5e1679803232c2f510b3fed9e`.
Verified executable:
`/nix/store/sz1pfpfw4wjyxbi6w7ils7nwip8kajy1-domicile/bin/domicile`.
SHA256: `a2167f3bc8acaf32470af90dece55d25197724bc37fe3e316bc6f73273fed6c6`.
No build, deployment or activation was performed.

## Authoritative baseline receipt

NAS root:
`/home/tom/.local/state/domicile-autonomous-20261104/practice/runs/20261104T110444Z-5e6bdc16`.
Remote retained scratch:
`/home/tom/compute/domicile-practice-runs/20261104T110444Z-5e6bdc16`.
Worker source snapshot records clean commit `64d04727`.

- `nas-receipt.json`: transport exit 1, archive exit 0, 104 manifest files
  verified; archive SHA256
  `bacc57b31d1a9799cedef25618ba52d5c1aa95b6228ae6194b33abb4daaaa4e2`.
- `artifacts/receipt.json`: required checks, timings, executable/config hashes,
  namespaces, intentional fault identity and unchanged coredump policy.
- `artifacts/events.jsonl`, `artifacts/raw/`: raw command/event/desktop evidence.
- `artifacts/shots/`: 17 screenshots. `startup.png`, launch `*-after-1.png`,
  `crash-after-rejoin.png`, `crash-after-rescue.png`, `reentry-rescue.png`.
- `artifacts/media/`: four short `*-frame-sequence.webm` clips plus sidecars;
  **timed screenshots, not live recordings**. Failed one-frame
  `live-probe.mkv` and `raw/live-probe.log` are retained.
- `artifacts/desktop-first-shutdown-leftovers.json`: PID 2060, observed start
  time 88141719, parent compositor 259,
  `udevadm monitor --kernel --subsystem-match=backlight`.
- `artifacts/cleanup.json` and `receipt.json.cleanup_remaining`: no owned
  processes remain after the harness cleanup.

| Check | Result / observation |
|---|---|
| Isolation + inputs | Pass: distinct PID/IPC namespaces and private runtime inode; executable hashes saved. |
| Broken startup | Pass: exit 1 and `Expected identifier but found end of file`; no ready desktop. Baseline diagnostic omits filename. |
| Fresh startup | Pass: shell and portal ready, screenshot; measured ready time 10.514 s. |
| Terminal | Pass: new real Kitty and its own counter child. |
| Former lock chord | Pass: Meta+Shift+Return launches new rescue Kitty; no PAM/physical locking claim. |
| Chrome | Pass: new owned process, disposable profile, about:blank; screenshot. |
| Nautilus | Pass: new owned process on disposable Documents; screenshot shows three fake files. |
| Engine crash | Pass: exact engine SIGKILL, different engine rejoins in 1.490 s; all four app identities survive, counters progress, fresh rescue action works. |
| First shutdown | **Fail**: owned backlight monitor survives the launcher and 8 s grace period. |
| Reentry | Pass: same private HOME/config/cache starts again in 6.505 s and rescue works. Earlier leaked watcher persists until final harness cleanup. |
| Second shutdown | Pass for the second desktop's descendants. |

The screenshot pair after rejoin and after rescue was visually inspected:
Nautilus still draws the fake Documents, then a new rescue Kitty draws its
counter. The crash window has no recording or screenshot polling; screenshots
resume only after the rejoin log and a further settling interval. This does not
prove preservation of every tiling/layout state or continuous rendering.

## Parameterized round and repeatability

A supplied config/helper/commands/chords/expectations round also completed:
NAS `.../runs/20261104T110642Z-4306ae2a`, remote
`/home/tom/compute/domicile-practice-runs/20261104T110642Z-4306ae2a`.
It records commit `d53963ce`, 104 verified files, the same 10/11 outcome and
1.479 s engine rejoin. Its archive SHA256 is
`fe591b1ff18a0a919e7f6d84e9ce71b61b0099987b73c22c8726c4f9255c997d`.
The supplied config and helper were **the earlier safe fixture**, not the other
agents' integrated starter. Its exact parameter argv is in `nas-receipt.json`.
`fixtures/commands.json` demonstrates an argv override and placeholders;
`fixtures/expectations.json` demonstrates process matching with disposable paths.

Earlier complete run IDs `20261104T105816Z-1388b907` and
`20261104T110315Z-194f1c8a` have the same shutdown finding and engine rejoins
of 1.476 and 1.477 s. All four complete rounds retain their original failure.
The first development run `20261104T105652Z-3841ddfd` is also retained: an
over-strict filename assertion and unhandled wedged recorder probe ended it.
Those harness defects were corrected; its receipt was never rewritten.

Seven focused harness tests pass under the remote runtime-test wrapper:
host namespace refusal before starting a bus, ancestry exclusion, reused-PID
refusal, crash-capture gate, failure receipt retention, owned argv matching,
and receipt retention after failed transport/corrupt archive. The final run used
`-W error::ResourceWarning`. NAS log:
`/home/tom/.local/state/domicile-autonomous-20261104/practice/safety-tests.log`.

## Remaining boundaries

No successful live recorder exists on this tested wlr backend: wf-recorder
reported `the frame was already copied`, wrote one frame and wedged at stop;
its bounded INT/TERM/KILL handling and ffprobe result are logged. There are no
claimed live clips. The prior screenshot-loop crash-recovery failure was not
repeated. The backlight-watcher shutdown finding needs a domain-code fix and a
new practice receipt; this harness does not edit the upstream implementation.

The real integrated config/app/login/input/display changes have not been
provided to this thread yet. The runner accepts their executable and reviewed
config/helper plans without a new Chromium build. Physical greetd/PAM, VT
return, Intel/i915 panels, natural scrolling, actual input and per-panel warmth
still require hardware proof. No password, Zenbook switch, reboot, live
user-manager change, account access or Herdr attachment took place.
