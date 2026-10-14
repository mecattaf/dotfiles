# Herdr desktop validation

Run only after the implementation is complete. Tests never target the active
Sway session or live Herdr. Keep the runtime wrapper even for fixture suites:
launcher tests exercise cleanup and inherited shell state.

```sh
~/.local/bin/runtime-test -- python3 -m unittest discover -s tests/herdr -p 'test_*.py' -v
python3 tests/herdr/smoke_context.py
```

`smoke_context.py` invokes `runtime-test` itself, then adds a private network
namespace and D-Bus with no service activation directories. It creates a new
HOME, every XDG directory, a dedicated Chrome profile, two headless Sway outputs,
real Kitty windows, a real Mako server, a local HTTP chat fixture, and a read-only
`herdr api snapshot` fixture. No authenticating client or actual agent is started.
It uses installed `sway`, `swaymsg`, `kitty`, `google-chrome-stable`, `mako`,
`makoctl` and `notify-send`, finding Nix-store binaries when absent from PATH.
Failures and logs remain visible in the printed `/tmp/herdr-context-smoke-*`
directory. Cleanup addresses only processes launched by the fixture; the PID
namespace bounds detached Chrome subprocesses.

The smoke checks native app identification, exact geometry with a neighboring
tile, focus, pixel borders, hidden companions, repeated toggles, unsent browser
draft preservation, SPA pane navigation without reload, two contexts using a
single dedicated profile, rename/output moves, pair close/restore, real urgency,
real notification deduplication and actions, seen versus waiting state,
offline Terminal access, and Chat-close recovery/recreation.

The local chat fixture establishes the window/route/draft contract. It does not
prove production authentication, production web UI transcript rendering, or the
remote laptop's GPU/display stack. The existing
`tests/sway-vicinae/smoke.py` separately exercises a private real Herdr server's
projector creation and persistence. No live desktop reload or deployment is
part of either test.

`flake.nix` includes all four fixture suites in `checks.*.herdr-launchers`.
The Nix build sandbox supplies runtime isolation for that derivation; use
`runtime-test` for invoking a check from the user's desktop too.
