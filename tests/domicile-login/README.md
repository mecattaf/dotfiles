# Domicile login and recovery practice

The physical launcher stays greetd's child. It loads the login shell once,
requires a real console login, refuses a running Sway or Domicile desktop,
checks the actual startup config, imports the declared login environment,
then execs upstream Domicile through systemd-cat. Upstream owns its component
restarts, graphical-session targets and teardown. There is no new user service.

Both the launcher and `domicile-recover` are installed in the system profile.
Sway remains the base greetd session and the greeter's default command.

## Recover from a failed login or shell error page

From a physical console, Ctrl+Alt+F2 reaches another VT. Run:

```sh
domicile-recover check
domicile-recover status
```

The check reports the actual config path and saves a private log under
`$XDG_STATE_HOME/domicile-session` (default `~/.local/state/domicile-session`).
Syntax errors, evaluation errors, unknown compositor settings, missing
imports and the starter key table's chord guard fail before login environment
mutation. A source shell is also bundled. JSON can name a shipped Domicile
shell or a local module; build external shell packages separately first.

If a desktop is running, status lists its exact socket and commands. Choose
that socket explicitly:

```sh
domicile-recover --socket /run/user/1000/domicile-ipc.PID.sock rescue
domicile-recover --socket /run/user/1000/domicile-ipc.PID.sock exit
```

Inside a desktop terminal, `DOMICILE_SOCK` already selects that desktop.
Without it, rescue and exit require `--socket`; they never pick the first
socket they find. Socket ownership, peer UID and the peer's executable must
match this Domicile installation. Exit uses a pidfd to avoid signalling a
reused PID.

Rescue loads a separately checked immutable Manganese shell, retaining
windows. Meta+Shift+Return opens Kitty with fish locally. Fix the startup
config, then run check again. A config edit can reload the configured shell.
Rescue does not rewrite the config or hide its error.

Exit sends SIGTERM to that launcher and waits for it to finish. Upstream
release 67c29a99 handles the signal, tears down its children and removes its
control socket, but reports `the desktop exited (interrupted)` with status 1.
The recovery command succeeds when the selected launcher has exited; the
original status and stderr remain in its journal. It sends no force kill.
Inspect a timeout before doing anything else. Practice also produced Chromium
diagnostic minidumps at shutdown. The harness retains the profile's Crash Reports;
a passing exit/re-entry receipt does not certify crash-free Chromium shutdown.

After a physical exit, greetd's default is Sway. Re-entry requires fixing the
config, a successful check, logging out of Sway, and starting
`domicile-physical-session` from a fresh physical console login with PAM's
VT/session variables. The login check leaves dead sockets intact and allows
upstream to reclaim a stale target; it refuses any socket still listening.
The physical VT, greetd and password steps still need a supervised hardware
round.

Read login diagnostics with `journalctl -t domicile-session -b`, and greeter
diagnostics with `journalctl -u greetd -b`. Do not reset failures or restart the
user manager to recover this desktop.

## Reproduce validation on compute

All commands below run in the compute checkout. Invoke them remotely through
`fleet-exec strix-coordinator --cwd <checkout> -- ...` when the harness is on NAS.
Every build needs a fresh disk check. There is no local fallback.

```sh
df -h /
test "$(df -Pk / | awk 'NR == 2 { print $4 }')" -ge 26214400
nix build --no-link --print-out-paths \
  .#nixosConfigurations.client.config.programs.domicilePhysical.sessionPackage \
  .#nixosConfigurations.client.config.programs.domicilePhysical.recoveryPackage
nix eval --impure --json --file tests/domicile-login/evaluate.nix
```

Use the two package paths returned above in these commands. Each receipt
directory must be new; the harness retains earlier runs and their failures.

```sh
~/.local/bin/runtime-test -- python3 tests/domicile-login/test_lifecycle.py \
  --session <session-package>/bin/domicile-physical-session \
  --recovery <recovery-package>/bin/domicile-recover \
  --receipts <new-matrix-receipt-directory>

~/.local/bin/runtime-test -- dbus-run-session -- \
  python3 tests/domicile-login/practice.py \
  --recovery <recovery-package>/bin/domicile-recover \
  --kitty <kitty-package>/bin/kitty \
  --receipts <new-headless-receipt-directory>
```

The matrix runs the complete generated launcher with substituted system tools,
including its login-shell re-exec. It tests PID retention, environment cleanup,
active desktop refusal and failure propagation without calling a user manager.
Config cases use the real installed builder and compositor config checker.
A socket served by an unrelated process is refused as an exit target.

The headless round uses private HOME/config/cache/state/data, the wrapper's
private runtime/PID/IPC namespaces, and a private session bus. It waits for
the configured shell, opens a native counter window, reproduces the unguarded
semantic chord error page, loads rescue, confirms the same native process and
advancing counter, fixes the config, exits and starts again with the same
profile. It saves screenshots, process IDs, command output, launcher logs and
an event receipt. Cleanup only signals processes the harness created.

A successful headless round proves shell replacement, window survival, graceful
launcher teardown, socket removal and profile re-entry. It does not prove DRM,
input hardware, physical VT restoration, PAM authentication, greetd fallback or
user-manager target lifecycle. The practice host has no Domicile PAM service;
private-bus portal/rtkit/PipeWire and shutdown diagnostics remain in the logs.
Without a render node, native window contents are blank; the round proves their
connection/mapping, title/tab survival and a continuing native process, while
hardware rounds must prove their rendered contents.
Arbitrary rendering bugs remain possible even after config checking; the
rescue command addresses the demonstrated shell failure.

Production code is confined to `modules/domicile.nix` and
`modules/domicile-session/`. App routing and the live key table are separate
integration work.
