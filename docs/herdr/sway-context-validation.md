# Herdr Sway context validation — 2026-10-14

Implementation branch: `feat/herdr-sway-context`, based on `2ac878912`.
Implementation and regression tests through `6f4a283b` were reviewed and tested
without deploying, reloading, or restarting any live desktop or Herdr server.
All tests started after the implementation was complete; failures were repaired
and the affected checks repeated.

## Results

- **69 tests passed** across launcher, picker, context, and attention suites,
  invoked through `~/.local/bin/runtime-test`.
- **Nix evaluation passed:** `nix flake check --no-build --no-write-lock-file`.
  The client enables attention only with the physical Sway session; Strix has
  no attention service. Client store delivery and raw-dotfile guards passed.
- **Packaged checks passed:** `herdr-launchers` and `raw-dotfiles-guard` on
  `x86_64-linux`. Nix formatting and `git diff --check` passed.
- **Real desktop smoke passed:** Sway 1.12, Kitty 0.48, Chrome 155, Mako 1.11,
  two private headless outputs. It covered exact tile and neighboring geometry,
  both fullscreen modes, keyboard focus, hidden companions without a tab bar,
  repeated swaps preserving a draft and page instance, explicit pane routing,
  two contexts sharing one dedicated browser profile, rename/output moves,
  close/restore, urgency, notification deduplication and actions, acknowledgement,
  snapshot disconnect/reconnect, and Chat recreation. A notification opened the
  first browser after the dedicated browser exited; it survived restarting the
  attention daemon.
- **Real Herdr title smoke passed:** a disposable server and two Kitty clients
  retained independent workspace titles across focus changes. The supported
  `herdr server reload-config` preserved those test processes.

The fullscreen test exposed Sway dropping the incoming window's fullscreen
state during scratchpad swaps; the helper now explicitly transfers that state.
Native Chrome ignores `--class` in app mode and rewrites process arguments and
environment. Window rules therefore use the dedicated profile suffix, while
ownership uses the private DevTools endpoint's browser PID and random endpoint
identity. Regression tests also cover partially published endpoint files.

## Scope and retained evidence

The desktop smoke uses a local HTTP Chat fixture and a read-only Herdr snapshot
fixture. It proves desktop behavior and the routing contract, not production
authentication, transcript rendering, a production web API outage, the physical
laptop's graphics stack, or the real systemd cgroup tree. Production frontend
route and control selectors were checked against the existing local source.
The separate title smoke uses the actual installed Herdr binary and the branch's
configuration. Neither test contacts the live server.

Both smoke scripts invoke `runtime-test` themselves and additionally isolate
HOME, XDG directories, D-Bus, and networking. Logs and failed attempts were
retained, with no suppression of unexpected process failures or coredumps.

- Full desktop results: `/tmp/herdr-context-smoke-h4qqkz_w/results.json`, plus
  logs and final compositor tree in that directory.
- Real Herdr title evidence: `/tmp/herdr-title-smoke-4ll8mc8h/`, including
  `tree.json`, `snapshot.json`, and process logs.
- Nix evaluation log: `/tmp/herdr-context-flake-check.log`.

Reproduction commands and fixture requirements are in
[tests/herdr/README.md](../../tests/herdr/README.md). Usage, deployment
prerequisites, and the multi-agent pane-selection boundary are in
[sway-context.md](sway-context.md).
