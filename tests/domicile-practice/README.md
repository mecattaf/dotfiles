# Domicile practice harness

Run the operator on **NAS**, not Strix. The only tracked files are in this
subdirectory; this does not edit the app helper, Home Manager module, login
module, key config, engine or deployed machine. No Chromium/Nix build is needed.

```sh
fleet-exec strix-coordinator --cwd /home/tom/compute/dotfiles-domicile-practice -- \
  cat tests/domicile-practice/run-nas.py > \
  /home/tom/.local/state/domicile-autonomous-20261104/practice/run-nas.py
python3 /home/tom/.local/state/domicile-autonomous-20261104/practice/run-nas.py \
  --out /home/tom/.local/state/domicile-autonomous-20261104/practice/runs
```

Each invocation gets a UTC/UUID directory. The operator uses `fleet-exec` with
an argv (no remote shell interpolation), then copies evidence back on success
**or failure**. Exit 0 means every required check passed, the compute command
exited 0 and the NAS copy passed the manifest. Exit 1 includes real baseline
failures; inspect the receipt rather than treating the runner's existence as a
successful desktop qualification. Interrupted transports can leave incomplete
receipts; those never pass. Remote scratch is retained for inspection and is
not cleaned automatically.

## What it does

`worker.py --enter` snapshots this subdirectory into the run, records git HEAD,
status, disk and wrapper SHA, captures the host PID/IPC/runtime identity and
enters **the remote** `~/.local/bin/runtime-test -- python3 ... --inside`.
The inner worker refuses matching host namespace or runtime identities before
starting anything. It sets a deliberate environment allowlist and private
HOME/config/cache/data/state, then starts its own D-Bus daemon on a socket in
that private runtime. The bus has no activation directories and cannot start a
user manager. There is no GPU/DRM passthrough. OZONE is headless; the engine
composites on the CPU.

Checks run serially:

1. Isolation plus executable identity/SHA checks.
2. A deliberately broken TSX startup must exit nonzero, report a syntax reason,
   and never announce a ready desktop. The baseline omits the file name in this
   diagnostic; the receipt records that limitation.
3. Fresh startup, built shell, seeded private RemoteDesktop session and PNG.
4. Meta+Return starts a real Kitty with its own ticking counter.
5. Meta+Shift+Return starts rescue Kitty: the former stock lock chord now runs
   the custom action. The SDK's `ownedChords` guards the fixture table. This is
   evidence of the action, **not** physical lock/PAM qualification.
6. Meta+B starts Chrome with a fresh user-data-dir, no account/extensions/sync,
   on `about:blank`; Meta+E starts Nautilus on three disposable text files.
7. Crash only the unique owned engine, identified by ancestry and its private
   broker flag. Require a different engine identity, the compositor's rejoin
   log, the same four app process identities, continued counter writes, a
   post-rejoin screenshot and a newly functioning rescue chord.
8. SIGTERM the owned Domicile launcher; require its children to leave. The CLI
   intentionally reports interruption as exit 1. Any leftover remains a failed
   check, with an individual process receipt. Reenter the same private
   HOME/config/cache and exercise rescue again, then check shutdown again.

Process identities include PID **and start time**. Signals use pidfds after an
identity check. Cleanup uses observed descendants of the harness's direct
children, including remembered identities that became orphans. There is no
`pkill`, no process-name-wide targeting, no reset-failed, no service restart,
no live user-manager call and no runtime-directory deletion. A failed test is
not rewritten to pass after cleanup. Bubblewrap kills remaining namespace
processes when the worker exits.

## Evidence and recording limits

`nas-receipt.json` records transport/copy status and archive SHA. `remote.tar.gz`
and `artifacts/` contain the compute receipt, events, config/helper/source
identity, process snapshots, `SUMMARY.txt`, screenshots, raw unfiltered logs,
and media. `manifest.json` hashes every raw log, screenshot, media and source
file; the NAS operator verifies it. Bulk disposable caches/profiles are left
on Strix, excluded from transfer. Crashpad `.dmp` files are copied to
`crash-evidence/` before transfer. Core limits and the kernel's system-coredump
route are recorded unchanged; system coredumps/journal failures are never
cleared. No credentials are copied to Strix or included in the receipt.

A **single bounded** `wf-recorder` probe checks the real capture backend and is
validated with ffprobe. A zero/one-frame take, short file or wedged recorder is
reported unsupported and kept, including its raw log and termination event.
Only a working probe enables short live recordings for individual launch
features, each validated separately. All `*-frame-sequence.webm` files are
**three timed screenshots, not live recordings**, with a sidecar listing the
capture offsets. They do not establish continuous rendering or lossless input.

There is no capture loop. Before the crash, every screenshot command must have
completed and every recorder must have exited. During recovery the harness
reads only process metadata, counter data and existing logs. It takes one
post-rejoin screenshot after a quiet settling period; if that fails it records
the failure without a screenshot retry loop or `load-shell` repair. The prior
experiment's screenshot-loop recovery failure is not retested or hidden.

## Integrated branch seam

The safe default is a generated fixture, not the shared starter config: the
base config's Meta+Return could attach to an existing Herdr workspace. Wait for
a reviewed integrated config/command plan, then supply overrides after `--`:

```sh
python3 /home/tom/.local/state/domicile-autonomous-20261104/practice/run-nas.py \
  --out /home/tom/.local/state/domicile-autonomous-20261104/practice/runs -- \
  --domicile /absolute/path/to/domicile \
  --config /absolute/reviewed/domicile.tsx \
  --apps-helper /absolute/reviewed/domicile-apps \
  --chords /absolute/practice-chords.json \
  --expectations /absolute/practice-expectations.json
```

`--config` is used read only at its original path so relative imports work;
a snapshot and hash are saved. The helper is copied only into the fake HOME's
`.local/bin/domicile-apps`. `--commands` optionally supplies JSON action-to-argv
arrays to the **fixture helper**; it does not rewrite a supplied domain helper.
Actions are `terminal`, `rescue`, `browser`, `files`. The helper's `start` verb
is outside this minimum harness. `--kitty`, `--chrome`, `--nautilus` and
`--recorder` accept executable paths. `--engine /absolute/engine-directory`
sets `DOMICILE_ENGINE` inside the private environment and records its chrome
and library hashes. It must contain `chrome` and `libdomicile_engine.so`. Use worker `--help` for timeouts. `--app-timeout` bounds app and counter readiness (default
20 seconds), including first-use font/cache work under concurrent builds.

A chord JSON maps actions to evdev code arrays. Defaults are `[125,28]`,
`[125,42,28]`, `[125,48]`, `[125,18]`, respectively. Expectations map each action
to nonempty argv substring arrays. All fragments must match one live owned
process; `{work}` and `{home}` expand to the disposable paths. For example:

```json
{"rescue": ["kitty", "practice-rescue"],
 "browser": ["chrome", "--user-data-dir={work}/chrome", "about:blank"]}
```

Default expectations require the fixture's titles/profile/Documents argv.
Command overrides expand `{work}`, `{home}`, `{python}`, `{app}`; use doubled
braces for a literal brace. With a custom terminal helper, an independent
throwaway Kitty counter is added for crash continuity if needed. HOME contains
refusing `ssh`, `herdr`, `herdr-picker` and `herdr-sway-projector` stubs to catch
ordinary PATH and `~/` transport calls. **This is not a filesystem or network
sandbox**: runtime-test leaves the real home and network accessible. Supplied
code must be reviewed to keep all profiles in the fake HOME and never invoke
absolute live transports, services, credentials or account work.

## Checks for the harness itself

```sh
fleet-exec strix-coordinator --cwd /home/tom/compute/dotfiles-domicile-practice -- \
  /home/tom/.local/bin/runtime-test -- \
  python3 -m unittest discover -s tests/domicile-practice -p 'test_*.py' -v
```

Headless proof does not cover greetd/PAM login, passwords, VT return, physical
keyboard/input feel, natural scrolling, Intel/i915, real panel modes/brightness
or per-panel warmth. No Zenbook action, deploy, reboot or activation is part of
this runner. It never reads `~/pass` and never starts an interactive agent.

Shutdown receipts separately list live survivors and zombies from current `/proc`
metadata, with start-time identity checks. A zombie is recorded as exited; any
live owned survivor still fails the unchanged shutdown requirement.
