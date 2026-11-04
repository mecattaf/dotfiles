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
The window title stays "Terminal control" when Herdr is attached; the LOCAL
surface and native Herdr UI identify the current destination.
Ordinary text stays in this menu. `local` opens a local fish shell with
`--no-config`, without NAS or inherited Herdr pane context. The rescue chord
opens that shell directly. Each Kitty is a new process, with no single-instance
socket, Kitty remote control, Sway IPC, pane input API or synthetic typing.

`nas` is the single explicit attach action. Before selection, the LOCAL
surface says NAS opens an **existing workspace/pane**, which may be Claude,
and ordinary keys after attachment go to that pane. No second confirmation
is required. Input is read without Python line buffering, and queued text is
discarded on selection, after the SSH preflight, and on return to local control.
A failed preflight, lost link or detach returns to the LOCAL surface. Later
ordinary keys stay local; another attachment requires a new `nas` selection.
Ctrl+C can cancel a pending connection. After explicit attachment, Herdr's native
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

The existing `herdr-projector` gains an opt-in
`HERDR_PROJECTOR_RECONNECT=0` policy: make one unit-preflight/attachment attempt
and return failures to the caller. Domicile sets this policy so a lost link
returns to LOCAL control. Existing callers retain automatic backoff/reconnect
by default. The `HERDR_BIN` adapter execs Herdr in the same child PID, preserving
native transport, unit preflight and per-child SSH/socket cleanup. The final
production child is exactly:

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
refusal, unreachable NAS, single-selection attachment, queued text at both
connection boundaries, lost-link return to local, and legacy projector reconnect.
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
The runner waits for menu text using read-only queries against private fixture
Kitty sockets before sending the first keys. It reads back the resulting local
"No action" message as well as capturing it. Production launchers enable no
remote-control socket. The runner records the initial NAS destination warning,
real Herdr UI on the fixture
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
NAS selection. This command uses mocked transport, with no actual NAS attachment.

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

## Follow-up evidence: selected binary and one NAS selection

The follow-up uses `DOMICILE_BIN=/home/tom/compute/domicile-apps-evidence/selected-stock/bin/domicile`,
a supplied symlink resolved to the available stock Nix package, without editing
the runner or using a personal HOME. The paired native package is still
unqualified; run the exact supplied-binary command above when it is available.

- `single-selection-selected-stock-03/`: successful real headless practice,
  94 sampled frames at 1024×768. Read-only fixture Kitty probes established
  readiness before initial input. The still and readback show `abc` consumed
  locally; only one `nas` selection attaches. The title is "Terminal control"
  throughout. `echo fresh` appears in the new native Herdr workspace and
  its readback, absent from the old fixture pane.
- `herdr-single-selection-01/receipt.json`: six real private Herdr checks,
  including queued-text exclusion and unchanged existing client destination.
- `followup-checks/routing.txt`: 15 passing routing tests. This includes
  lost-link return to local and the legacy default reconnect test.
  `followup-checks/existing-launchers.txt`: eight passing existing tests.
- `selected-binary-checks/receipt.json`: explicit empty, missing, relative and
  non-executable selections fail before creating an output directory.

`herdr-projector` changed: it gained the reconnect opt-out described above.
Legacy callers retain their previous reconnect behavior by default, proven by
`test_existing_projector_callers_still_reconnect_by_default`. The final practice
receipt records both facts explicitly.

Failed readiness attempts remain on Strix: `single-selection-selected-stock-01`
sent initial keys before Kitty painted, and `single-selection-selected-stock-02`
rejected a spaced Kitty match expression. The successful runner probes each
private socket directly. Their logs remain intact and are not copied as
successful proof to NAS notes. Actual NAS authentication/clipboard, physical
Zenbook behavior and portal/keyring commissioning remain unrun.

## Store-backed console trial config

A trusted trial launcher can select the desktop Herdr TOML independently of
all XDG directories and the browser profile:

```sh
env DOMICILE_DESKTOP_CLIENT_CONFIG=/nix/store/CANDIDATE/desktop-client.toml \
  domicile-apps terminal
```

This may also be exported by the trial session launcher. Only the Herdr child
uses it as `HERDR_CONFIG_PATH`; HOME, XDG_CONFIG_HOME, installed config files
and Chrome's ordinary profile are not redirected or modified. The one-selection
LOCAL surface and native workspace UI behave as before.

Without `DOMICILE_DESKTOP_CLIENT_CONFIG`, the path remains
`XDG_CONFIG_HOME/herdr/desktop-client.toml` when that variable is present,
otherwise `$HOME/.config/herdr/desktop-client.toml`. An explicit override must
be an absolute path to a
readable regular file containing valid TOML. Empty, relative, missing,
directory, unreadable, malformed and invalid-UTF-8 selections fail locally before SSH and do
not fall back to installed config. The exec adapter revalidates immediately
before attachment. Validation checks file readability and TOML syntax; the
trusted candidate's Herdr settings remain the login owner's configuration.

The pathname is passed as environment data, with no shell evaluation; spaces
and shell metacharacters stay literal. This option writes no files and reloads
no server. The existing successful UI recording remains the visual evidence;
the config-path follow-up is covered by routing tests rather than another
recording.
