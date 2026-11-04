# Domicile starter applications

Import `modules/domicile-apps.nix` beside `modules/domicile.nix`. The existing
`home/home.nix` bin-directory link installs the three new helpers automatically.
The module supplies regular Google Chrome, Nautilus and Kitty, reuses the
existing fish/Python installations, and adds four launcher entries and a
compositor-neutral Herdr client config. It owns
no server service, session lifecycle, shell startup or compositor key table.

The integration owner's existing safe table should use these argv commands:

```tsx
"Meta+Return": exec("domicile-apps", "terminal"),
"Meta+Shift+Return": exec("domicile-apps", "rescue"),
// Optional dedicated application chords:
"Meta+b": exec("domicile-apps", "chrome"),
"Meta+e": exec("domicile-apps", "files"),
```

Keep the existing removal of `Meta+Shift+Return` from `DEFAULT_KEYBINDINGS`
and `ownedChords({ keybindings })`. Do not replace the Shell export or
reintroduce the stock lock binding while integrating these commands.
No shared `modules/domicile.nix` or `domicile.tsx` was edited in this slice.

## First-key destination

Meta+Return opens a fresh Kitty OS window at **local terminal control**.
Ordinary text stays in this menu. `local` opens a local fish shell with
`--no-config`, without NAS or inherited Herdr pane context. The rescue chord
opens that shell directly. Each Kitty is a new process, with no single-instance
socket, Kitty remote control, Sway IPC, pane input API or synthetic typing.

`nas` requests remote attachment. After the projector's unit preflight, the
user must type `ATTACH nas` at a warning that the destination is an **existing
remote workspace** and ordinary keys will reach its displayed pane. Any other
answer declines attachment. The gate discards terminal type-ahead before
executing Herdr. A lost link asks for that explicit choice again before each
new attachment; Ctrl+C on unavailable NAS returns to local control.
Detach returns to local control. After explicit attachment, Herdr's native
Ctrl+B then Shift+N creates a fresh workspace/shell; Ctrl+B then W selects
a workspace; Ctrl+B then Q detaches. These are human UI actions.

The default is deliberately local because the pinned upstream Herdr v0.9.3
(`7b116c05bfda646af39d2524c54e70c751f57ee8`, protocol 22) has no public
client selector or initial-workspace attachment argument:
- `src/cli/workspace.rs`: create accepts `--no-focus`; focus accepts only a workspace ID.
- `src/api/schema/workspaces.rs`: creation has cwd/focus/label/env, no target client.
- `src/server/headless/client_views.rs`: public focus changes client locations.
- `src/server/headless/tests/mod.rs::public_workspace_focus_preserves_each_clients_remembered_tabs` explicitly expects both clients to change workspace.

The runnable isolated proof demonstrates both hazards, rather than treating a
background-create response as proof that a subsequent new view is safe.
No Herdr features were added.

## Transport and live-session preservation

The existing `herdr-projector` is byte-for-byte unchanged. The gate is its
`HERDR_BIN` child, so unit preflight, backoff, reconnect and child cleanup
remain in place. The final production child is exactly:

```
herdr --remote nas --remote-keybindings server
```

This retains the native clipboard-image transport instead of substituting an
SSH terminal. Real NAS attachment, clipboard-image transfer, authentication,
portals, keyring and Zenbook commissioning remain attended validation
boundaries. No live NAS API mutation, focus operation, server reload,
service restart, deployment, reboot, password read, push or upstream filing
was performed. The existing Herdr service and `X-SwitchMethod=keep-old`
were not changed.

## Run the checks on Strix

All commands below run from the dotfiles checkout on Strix, invoked through
`fleet-exec strix-coordinator --cwd /home/tom/compute/domicile-autonomous-apps -- …`
from the NAS harness. Use fresh absolute output directories.

```sh
~/.local/bin/runtime-test -- python3 tests/domicile-apps/test_routing.py -v
~/.local/bin/runtime-test -- python3 tests/domicile-apps/prove_herdr.py /absolute/new-herdr-proof
~/.local/bin/runtime-test -- dbus-run-session -- bash tests/domicile-apps/practice.sh /absolute/new-app-practice
```

The routing suite uses fake Kitty/SSH/Herdr endpoints and real PTYs, including
type-safe argv, local ordinary input, missing neutral config, noninteractive
refusal, unreachable NAS, cancellation, explicit attachment and reconnect.
The isolated proof runs a real Herdr server, two native clients and a fixture
shell that records actual received bytes by pane ID. Fake SSH and remote
dispatch then route an explicit projector attachment to that same real
private server. No credentials or actual NAS connection are used.

The practice runner runs the already built upstream Domicile and installed
applications under runtime-test, a private D-Bus and a fixture HOME. Its
private Chrome profile is never a personal browser profile. The recording is
a sampled screenshot sequence encoded at nominal 2 fps; `frame-times.txt`
gives actual capture times. Keyboard events in that runner are test stimuli
to the isolated fixture desktop, never production launcher behavior.
The runner records the explicit NAS gate, real Herdr UI on the fixture
server, and native new-workspace creation, as well as Chrome, Files and local
rescue. `receipt.json` contains artifact hashes and `video.json` the encoded
frame count and duration.

Supply a Domicile build with `DOMICILE_BIN`, an absolute executable path.
All desktop startup, control and screenshot calls use that selected binary.
Symlinks such as `result/bin/domicile` are resolved once before execution.
An explicitly empty, missing, relative or non-executable path fails before
creating the output directory; it never falls back to the stock build.
Omitting the variable retains the original stock Domicile default. Other
application tool paths remain the locally available store paths near the top.

Exact invocation from NAS, with a fresh output directory on Strix:

```sh
fleet-exec strix-coordinator \
  --cwd /home/tom/compute/domicile-autonomous-apps -- \
  /home/tom/.local/bin/runtime-test -- \
  env DOMICILE_BIN=/absolute/paired-package/bin/domicile \
  dbus-run-session -- bash tests/domicile-apps/practice.sh \
  /home/tom/compute/domicile-apps-evidence/paired-native-01
```

Replace only the supplied binary and fresh output path. The runner still
creates a fixture HOME, private Chrome profile and private Herdr server inside
runtime-test and a private D-Bus; no personal HOME or profile becomes the
desktop's configuration. It retains the local first-key sequence and explicit
NAS gate. This command uses mocked transport, with no actual NAS attachment.

`domicile-build.json` records the selection before any desktop starts.
The same object appears at `receipt.json.domicile` on success:
`selected_by`, `requested_binary`, resolved `binary`, resolved package root
(parent of `bin/`, or null for another layout), and executable `sha256`.
The Nix package store path identifies the supplied build and its dependencies.
The receipt does not claim that a later paired native package passed when
only the available stock build has run.

Never silently substitute a live desktop or personal HOME. No build is needed
for these scripts. Before any future `nix build`, check `df -h /` on the build
host and stop below 25 GB.

## Measured evidence

Evidence root on Strix: `/home/tom/compute/domicile-apps-evidence/`.
- `herdr-06/receipt.json`: real server/client destinations, default local input,
  explicit mocked remote attachment, unchanged original client, and the public
  API focus hazard. The fixture input files are exact byte receipts.
- `module-eval.json`: extended client NixOS configuration evaluates all four
  application entries and neutral Herdr config; it declares no client Herdr server.
- `desktop-03/`: reviewed Chrome fixture page, Nautilus fixture documents,
  Kitty menu consuming ordinary first keys, and local rescue executing
  `echo local`. `apps.mp4` is 55 sampled frames at 1024×768.
- `desktop-05/`: expanded fixture recording with the explicit gate and native
  Herdr UI (review result recorded separately in the final evidence receipt).

Earlier attempts are retained honestly: `desktop-01` and `desktop-02`
contain the failed wf-recorder attempt (a changing input frame format broke
its filter graph and it stalled; only the positively identified test-owned
recorder was killed). The final runner uses sampled screenshot capture.
The first Chrome trial used a split profile-directory argument that opened
an error tab; using `--user-data-dir=PATH` fixed the fixture. The production
launcher never supplied that fixture-only flag.

Private-bus logs retain the unavailable user-manager scope, missing FUSE,
portal backend and GPU warnings; these runs establish window paint and the
tested keyboard destinations, not a complete portal or physical-seat pass.
No unexpected failures or coredumps were hidden or cleared.
