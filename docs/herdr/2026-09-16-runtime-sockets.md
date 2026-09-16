# Herdr launch and missing runtime sockets — 16 September 2026

## Cause and evidence

Herdr PID 1716 stayed alive with 77 panes and no service restarts. The host had
about 115 GiB available memory. The projector warning was a failed service-status
query, not a Herdr crash or pane-count limit.

At 11:04:33 CEST Tally first reported `sd_notify failed: No such file or directory`.
The live `/run/user/1000` tree was missing `bus`, `systemd/private`, and
`systemd/notify`, although the corresponding processes and open sockets survived.

The `/home/tom/today` Claude smoke-test transcript records a validation command
between 11:03:48 and 11:05:20 that sourced this extraction:

```sh
sed -n '/^require_result/,/^}/p' test/run-matrix.sh
```

The start pattern also matches later calls to `require_result`. Those ranges
reach the end of the script, including `rm -rf "$XDG_RUNTIME_DIR"`, without
including the earlier assignment of a private test runtime. A read-only
extraction from the retained evidence reproduces that inclusion. This explains
the runtime deletion at the matching time; there was no syscall audit recording.

The source transcript is
`~/.claude/projects/-home-tom-today/178f37b2-adfd-4490-b746-e71294b721ea/subagents/agent-asmoke-pi-halogen-81e4e61293e8ab35.jsonl`.
The retained script is
`~/today/campaign-2026-09-16/evidence/smoke-pi/repo/appliance/test/run-matrix.sh`.

The coredump episode came from the experimental `appliance` binary in the same
campaign, not Herdr. Its SIGABRTs need correction in that project. The failure
reporter must continue surfacing unexpected crashes.

## Changes

- `herdr-chord new` always creates a new Kitty projector before sending its
  new-workspace chord. It never replaces the view in an existing window.
- `herdr-projector` preserves the service-check diagnostic, distinguishing SSH
  failures, user-manager transport errors, and inactive units. It still refuses
  to attach when the service cannot be verified, preventing unmanaged servers.
- The failure reconciler connects directly to the user's systemd private socket
  through `runuser`. It no longer creates a transient `systemd-stdio-bridge`
  service whose failure could generate another alert. Failed/empty health
  queries retain markers rather than claiming recovery.
- `runtime-test -- command args...` masks `/run/user` with private tmpfs, uses
  private PID/IPC namespaces and a minimal private `/dev`, and clears inherited
  live-session socket variables. Standard devices remain usable inside the
  user namespace; physical devices are not exposed by this wrapper.
  A cleanup using either `$XDG_RUNTIME_DIR` or a hardcoded `/run/user/<uid>` cannot
  delete host runtime files through those paths. The wrapper fails if bubblewrap
  cannot establish isolation. It preserves command exit status.

Use the wrapper for shell-fragment, runtime-cleanup and compositor experiments.
This is **not a general sandbox**: source files, home, `/tmp`, and networking
remain available. It does not automatically wrap existing agents or SSH commands,
and does not prevent software bugs, all possible filesystem access, or coredumps.
The same rule is declared for future agent sessions through Codex's global
`~/.codex/AGENTS.md` and a Claude user rule in all three account directories;
`AGENTS.md` also records it in this checkout. Instructions guide adoption;
the namespace boundary is enforced only for commands run through the wrapper.
See [Codex instruction discovery](https://learn.chatgpt.com/docs/agent-configuration/agents-md)
and [Claude user rules](https://code.claude.com/docs/en/memory#user-level-rules).
Use a disposable microVM for
untrusted programs or tests needing a complete service manager.

## Validation and activation

`python3 tests/herdr/test_launchers.py` tests per-window targeting and failure
diagnostics with mocked desktop/SSH commands. `nix build .#checks.x86_64-linux.herdr-launchers`
also checks shell syntax with ShellCheck. The failure-reconciliation regression
test is `nix build .#checks.x86_64-linux.failure-marker-reconcile`.

Outside the Nix build sandbox, `python3 tests/runtime-test/test_isolation.py`
performs real namespace isolation, deletes disposable runtime contents, confirms
the host sentinel survives and host PIDs are hidden, and checks exit propagation.

The launcher scripts are raw links into `~/mecattaf/dotfiles`. Updating those
files on **client** takes effect on the next chord/projector launch; no NixOS
switch, reboot, Herdr restart, or fleet flash is needed. An already-running
projector reconnect loop keeps its old shell code until relaunched.

The reconciler is store-packaged: activate its NixOS change on hosts that run
failure surfacing. The bubblewrap package declaration needs a Home Manager/NixOS
activation only where it is not already available. Use normal targeted builds
and switches; do not deploy unrelated checkout changes across the fleet.

Applied in this repair: the three launcher/config files were patched on client
without changing its other checkout content; `niri validate` passed. Coordinator
has the runtime-test wrapper and the four global rule links. The new reconciler
was built and activated on coordinator alone with a temporary runtime drop-in,
`/run/systemd/system/failure-marker-reconcile.service.d/90-runtime-socket-fix.conf`.
Its hardened service completed successfully; Herdr stayed at PID 1716. A GC root
at `~/.local/state/herdr-runtime-fix-reconciler` retains the built unit and program.
After a normal coordinator switch installs the declared reconciler, remove that
specific runtime drop-in and GC-root symlink, then `systemctl daemon-reload`.
The runtime drop-in disappears on reboot, so install the declarative fix first.
Other hosts have not received the reconciler or global rule changes in this repair.

## Existing runtime damage

Sending the documented reexecution signal (`RTMIN+25`) to user-manager PID 1443
recreated `systemd/private`; the Herdr preflight then passed from client. Herdr's
PID and all 77 panes were unchanged. This did **not** recreate `bus` or
`systemd/notify`, which remained open but unlinked. Tally still cannot complete
its notification handshake. A NixOS switch is not evidence these sockets recover.

Do not restart `herdr.service` or `user@1000.service` as an unattended repair.
Arrange a maintenance point after the running agents have saved their work for
full user-session recovery. Restarting the user manager interrupts its services
and PTYs; layout restoration is not process preservation.

## Browser and keyring follow-up

The noVNC menu reports `keyring: unavailable` while the user bus is missing.
Its disabled Open window button is a consequence of that failed probe, not a
regression in TPM auto-unlock. Boot logs prove automatic unlock succeeded on
September 14. The launcher now explains that the coordinator session needs
repair instead of suggesting a password can solve an unavailable keyring.

A separate, older portal failure affected interactive Chrome: its Wayland
environment was passed only to Chrome, while D-Bus activated the GTK portal
without a display. The browser desktop now publishes an environment file for
both portal units. They are ordered after the compositor, stop with it, and
are conditioned on the environment file. No global display is imported into
the user manager. Stop/crash cleanup removes the file. TPM unlock follows
user-manager restarts as well as boot.

The September 15 print renderer fix was already deployed. It disables D-Bus
only for the headless Chrome subprocess. A September 16 receipt confirms a
14-page job completed after the runtime incident. It did not remove sockets.

On September 16 Tom confirmed all chats were saved and authorized client and
coordinator maintenance, including runtime recovery. This supersedes the earlier
requirement to keep the two agent processes alive during that maintenance.
