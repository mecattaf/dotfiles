# Isolated desktop smoke test

From the dotfiles checkout, with the client closure's packages available:

```sh
python3 tests/sway-vicinae/smoke.py \
  --screenshot /home/tom/today/sway-vicinae-preview-2026-10-07.png
```

The script invokes `~/.local/bin/runtime-test` itself. It refuses to run without
that wrapper and bubblewrap. Required tools are Nix, Python 3, Kitty/kitten,
wtype, grim and dbus-run-session, plus the installed Anthropic fonts. Sway,
Vicinae, Mako, libnotify and Herdr paths come from the evaluated client flake.
The test evaluates configuration but does not build or activate the system.

The private seat has separate runtime/PID/IPC/network namespaces, XDG
configuration/data/cache/state directories, a fresh D-Bus without activation
service directories, and a private X11 socket directory. It never starts or
restarts a systemd unit. Real Sway startup/session hooks are replaced with inert
fragments. File indexing, clipboard collection, input injection, telemetry,
extensions and network refresh are disabled for the test. All inherited
`HERDR_*` selectors are removed before any process starts.

It exercises:

- All three delivered Sway theme fragments with native `sway -C`, preserving
  raw keybindings, input settings, window rules and the generated client slot.
- Two software-rendered 2880×1800 panels at scale 2, native Mod+1–9 bindings,
  renamed numbered workspaces, and Chrome's workspace-10 app-id assignment.
  Chrome placement uses an explicitly labelled harmless Kitty fixture.
- Workspace-name rejection and punctuation/Unicode round trips through actual
  Sway IPC. An early version caught JSON-style escapes being retained by Sway.
- Real Herdr 0.9.3, using an explicit private API/client socket and fresh
  configuration. Its only pane program echoes literal input; it cannot execute
  commands. The production bridge recognizes the complete new-workspace form,
  submits one unique label, reuses the projector on the next action, parks and
  restores it, and detaches/reconnects Kitty without replacing pane/terminal IDs.
- The actual raw Kitty configuration and rendered palette for that projector;
  scrollback-editor startup is inert and shell integration is disabled.
- Real Vicinae startup, Mod+D activation, rendered custom theme, selected-row
  dmenu, and empty-input free-form naming. Concurrent stock `state open` calls
  verify the bridge's unique-request-ID workaround for Vicinae 0.29.1's global
  pending-reply collision. The first version of this test reproduced the native
  CLI receiving a DescribeResponse instead of its DMenuResponse.
- Real Mako notification delivery and Anthropic Sans font availability.

A persistent virtual keyboard stands in for the physical keyboard; creating
and destroying the only keyboard for each keystroke would reset layer focus.
Free-form input is typed at a human rate and allowed to settle before Enter.

Every run retains `metadata.json`, `results.json` on success, all process logs,
private Herdr snapshots, its rendered terminal screen, and dmenu screenshots
under the printed `/tmp/sway-vicinae-smoke-*` directory. Only children belonging
to that test are terminated. There is a three-minute outer deadline.

The complete successful run on 2026-10-07 is recorded at
`/tmp/sway-vicinae-smoke-esud64_n/results.json`; the requested screenshot is
`/home/tom/today/sway-vicinae-preview-2026-10-07.png`. The image is a synthetic
headless preview, not the live Zenbook or any live agent.

Logs are deliberately retained without filtering. Missing systemd/portal/system
D-Bus interfaces and first-run metadata are expected in this isolated seat.
Kitty also logged `Unsupported screen mode: 9 (private)` from the Herdr client
and `Unknown keymap format: 0` during virtual-keyboard lifecycle changes; these
were not hidden. Herdr logged terminal I/O closure when the fixture Kitty was
intentionally detached. No crash was observed. These tests do not establish
physical GPU/input behaviour, Duo touch identifiers, real Chrome native-host
integration, SSH transport behaviour, or portal screen sharing.
