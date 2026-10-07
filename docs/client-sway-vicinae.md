# Sway, Vicinae and Herdr on both physical seats

Branch: `desktop/sway-vicinae-client`. Targets: `client` (Zenbook Duo) and
`coordinator` (Strix). Herdr and agents stay on Strix; the coordinator's
projectors attach locally, while the Zenbook attaches over SSH. Network
configuration is unchanged; Strix remains wireless until the wired move.

The desktop is stock Sway, Kitty, Chrome, Vicinae 0.29.1 and Mako. There is no
Waybar, overview, animated compositor or wallpaper image. The background is
`#000000`. Application colors come from the existing shared palette; Kitty
and Herdr retain AnthropicMono Nerd Font, while Sway, Vicinae and Mako use
Anthropic Sans. `theme noir`, `theme claude-dark` and `theme claude-light`
reload the consumers; the Sway background remains black in every palette.

## Pull and test on client

Run this on the Zenbook, from its canonical checkout. Raw configuration and
`~/.local/bin` are linked into this checkout, so building from a remote flake
without updating the checkout is insufficient.

```sh
cd ~/mecattaf/dotfiles
git status --short
git fetch origin
git switch --track origin/desktop/sway-vicinae-client
sudo nixos-rebuild boot --flake .#client \
  --option extra-substituters https://vicinae.cachix.org \
  --option extra-trusted-public-keys 'vicinae.cachix.org-1:1kDrfienkGHPYbkpNj1mWTr7Fm1+zcenzgTizIcI3oc='
sudo reboot
```

If the local branch already exists, use `git switch desktop/sway-vicinae-client`
then `git pull --ff-only`. Preserve any local changes before switching; do not
reset or discard them. `boot` deliberately leaves the running desktop alone
until the reboot. Existing remote Herdr agents survive the client reboot.
The first rebuild may download Vicinae dependencies; its signed upstream
cache is configured for the client. The explicit options above make that
cache available during the first build, before the new system is active.

If you prefer a temporary generation, build first, leave the graphical
session for a recovery VT, and run `sudo nixos-rebuild test --flake .#client`
there. Do not restart Strix's Herdr service to test this desktop.

## Keys and workspace behavior

| Key | Behavior |
|---|---|
| Mod+1 through Mod+9 | Dedicated Herdr workspace slots |
| Mod+0 | Chrome, Sway workspace number 10 |
| Mod+D or Mod+Space | Vicinae root launcher |
| Mod+Ctrl+Space | Vicinae Herdr/workspace picker |
| Mod+K | Sway focus up |
| Mod+V | Vicinae built-in clipboard history |
| Mod+Ctrl+V | Vertical split |
| Mod+Return | Focus/reopen the slot's projector, or create one if absent |
| Mod+T | First unused slot from 1 to 9, initially empty |
| Mod+Shift+T | Restore the most recently closed Herdr workspace |
| Mod+W | Park this workspace's Herdr view and close its other windows |
| Mod+Shift+Q | Close the focused local window; a projector detaches |
| Mod+Shift+N | Rename this Sway workspace through Vicinae |
| Mod+Up / Down | Previous / next workspace on the current output |
| Mod+C | Open Chrome; its window is assigned to workspace 10 |
| Mod+F | Toggle fullscreen |
| Alt+H/J/K/L | Focus left/down/up/right output |
| Mod+Shift+Return | Plain local Kitty shell, for client administration |

One slot owns one Herdr projector, even when it is parked. Mod+Return on
Chrome's slot chooses a free Herdr slot. A parked view still occupies its
slot, so opening a new workspace cannot overwrite it. The Vicinae picker reopens it with
its Sway name intact. When all nine slots are occupied or parked, creation
stops with an explanation; it never silently allocates workspace 11.
Native Sway numbering survives names such as `3: project review`. The rename
command accepts Unicode and ordinary punctuation, but rejects double quotes,
backslashes, dollar signs and control characters because Sway does not
round-trip JSON-style escapes in workspace names.

Mod+W follows the requested Chrome-like close behavior. Other application
windows in that workspace receive Sway's ordinary close request, while the
Herdr projector is moved into Sway's scratchpad. Mod+Shift+Q closes Kitty
and detaches the view. Mod+Shift+T restores the newest parked projector,
including its name and running session. This restore history lasts for the
current Sway session; it does not reopen a Kitty window explicitly killed
with Mod+Shift+Q. Chrome retains its own Ctrl+Shift+T tab restore. Neither action terminates the remote Herdr pane or
agent. End a remote shell/agent explicitly inside Herdr when that is wanted.

## What the Herdr picker reports

The picker obtains a bounded, read-only snapshot from
`herdr api snapshot` locally on Strix, or
`ssh coordinator herdr api snapshot` on the Zenbook. It never starts a Herdr server,
never sends global Herdr focus commands, and never infers agent state from
window titles. Status is a snapshot taken when the picker opens; choose
Refresh to fetch it again. If SSH fails, local window selection still works
and the error is shown as unavailable, not idle.

Fresh slots receive a unique Herdr workspace label. The launcher verifies
Herdr's new-workspace form before entering the label and verifies it again
before submitting. Existing projectors receive no such input. Each Sway projector
uses a separate generated UI configuration enabling that form; the server's
configuration and live process are unchanged.

Strix currently disables Herdr-generated window titles. Consequently,
`assigned working` means the originally assigned Herdr workspace is working;
it does not certify that the projector still displays that workspace after
manual Herdr navigation or a reconnect. Plain status without `assigned`
requires an unambiguous live title match. Unknown identity stays unknown.
This distinction is intentional until a client-specific upstream targeting
interface or a tested title policy is available.

Separate active-agent rows show Herdr's reported state. Selecting one opens
the local Herdr navigator and names the pane to select manually. It does not
silently refocus every attached client. Selecting a workspace/window row
focuses only its Sway container.

## Vicinae and notifications

The launcher includes favorite entries for Herdr workspaces, browser tabs,
Now Playing and Search Tray. It also finds the dotfiles desktop commands for
new/renamed workspaces, Mako dismissal/restoration and NetworkManager's
`nmtui` in Kitty. Native media controls and tray search work without a bar.
The [deeper investigation](vicinae-research.md) explains the wider feature
set and evaluates extension candidates.

The bridge uses Vicinae's native menu protocol with a distinct request ID.
The released CLI reuses ID 1 for every connection, and an isolated test proved
that concurrent status/browser calls can misroute a pending menu response.
The compatibility bridge avoids those IDs and validates the returned identity
and selection; it does not require a fork of the launcher package.

Chrome's official Vicinae extension is declared through system policy; its
native-messaging host is installed by Home Manager. Chrome downloads the
extension from the Web Store when it processes policy. Verify the extension
and tab search after opening Chrome; `chrome://policy` shows the managed
installation. No Chrome profile, login or tab data is copied between hosts.

Clipboard history keeps ordinary entries for one day and preserves tagged
entries. Recognized password-manager hints are ignored. File search indexes
Documents and Downloads rather than the whole home directory. The input
helper is disabled, so copy works but automatic paste and snippet expansion
are not enabled. Telemetry and remote favicon lookup are disabled. These
choices are in `home/vicinae.nix`, not hidden GUI state.

Mako starts with the physical Sway session. Normal notifications expire after
five seconds; high-urgency notifications remain until dismissed. It shares
foreground, background, border, accent and urgency colors with the palette.
Test with `notify-send 'Sway desktop' 'Mako and Anthropic Sans are working'`.
This installs the notification surface; it does not change the headless
Herdr server's notification delivery or claim to forward all remote toasts.

## Validation and recovery

The complete client closure built successfully on Strix before publication.
All 39 launcher/picker tests passed. The profile checks
assert Sway/Vicinae/Mako on the client, no Waybar and no client Herdr service,
and a shared Sway desktop on both physical seats. Herdr's keep-old and independent
server lifetime remain checked. Helper tests cover slot exhaustion,
duplicate prevention, focus identity checks, parking, rename, remote errors,
and guarded input into newly created projectors. All runtime experiments
use `~/.local/bin/runtime-test -- ...`. The headless desktop smoke runner
adds a private network namespace, D-Bus, XDG directories and a private Herdr
socket; its shell fixture treats input as literal data. It never attaches to
the production Herdr server.

To repeat the desktop smoke test after building the client closure:

```sh
python3 tests/sway-vicinae/smoke.py --screenshot /tmp/sway-vicinae-preview.png
```

The runner invokes `runtime-test` itself, evaluates the actual client config,
retains its logs under a printed `/tmp/sway-vicinae-smoke-*` directory and
fails if isolation is unavailable. The passing run exercised all three palettes,
workspace names and numeric bindings, Chrome's app-ID placement rule, real
Herdr workspace creation/reuse/parking/detach/reconnect, Vicinae selection and
free-text entry during concurrent CLI queries, and a real Mako notification.
The Chrome-placement fixture is a harmless terminal, not a browser profile.
The systemd session hooks are deliberately
inert there, so this test does not certify a real greetd login or portal
activation on the laptop.

The client was unreachable during initial preparation, then deployed and
checked on the real laptop once it was powered on. See the rollout receipt
below. The headless test cannot prove the Duo's actual touch-device mapping,
dock transitions, audio peripherals or portal behavior.
On first login, test both screens, lid/dock behavior, Mod+0/1/9, rename,
park/reopen, repeated Mod+Return, launcher placement, browser tabs, Mako and
a client disconnect/reconnect. Use `swaymsg -t get_inputs` before replacing
the retained top-panel touch mapping with per-device ELAN rules.

For rollback, select the previous NixOS generation in the boot menu. Then
restore the previous Git branch in `~/mecattaf/dotfiles` as well, because raw
configuration follows the checkout. Niri remains installed as a recovery
option; a declarative rollback changes `myDisplay.session` to `"niri"`.
Do not stop Herdr, the user manager or the remote agent processes.

## Live client rollout, 2026-10-07

The branch is deployed on the Zenbook. The first real login exposed two
integration gaps that are now fixed: declaring a Home Manager Mako unit
replaced its vendor unit without inheriting `ExecStart`, and plain GTK
settings commands lacked Nix's schema directories. Mako now has a complete
D-Bus service definition, checked by the profile assertions. The physical
session imports both desktop and Nautilus schema paths before it starts.

Verified on the laptop after the corrected boot:

- Sway, Vicinae and Mako are active; no failed user services.
- Anthropic Sans resolves correctly; GTK reports Anthropic Sans 11,
  `prefer-dark`, and Kitty as Nautilus's terminal.
- The docked top panel runs at 2880×1800, 120 Hz, scale 2. The kernel reports
  the lower panel disconnected in the current physical configuration.
- A real client projector attached to coordinator on workspace 1 and created
  its dedicated Herdr workspace. The picker retrieved three agent rows with
  no remote-status error.
- Chrome is assigned to workspace 10. The declared extension installed, its
  native-messaging process runs, and Vicinae exposes browser-tab search.

Chrome opened an existing Unlock Keyring dialog, which is left for the user
to handle locally. Authentication and stored browser secrets were not changed.
Undocking, lower-panel touch, lid transitions and portal screen sharing still
need physical acceptance testing. Coordinator and client networking were left
unchanged; Strix remains on Wi-Fi.

## Strix cupboard move

The desktop branch leaves the server network untouched. During inspection,
Strix's default route still used `wlp192s0`; `enp191s0` had no carrier. Simply
plugging Ethernet in will not complete the cutover: the fleet currently gives
additional wired interfaces metric 700, behind Wi-Fi at 600, and the
coordinator uplink/failover policy names Wi-Fi explicitly. The wired change
needs the cable connected and the coordinator LAN/failover declarations
updated together, with SSH reachability checked before disabling Wi-Fi.
Herdr and its PTYs must remain running throughout that separate cutover.

## Unknowns and proposed defaults

The default is a functional snapshot picker with explicit assigned status,
not an always-running custom dashboard. Rich live refresh can use the same
JSON bridge later. Actual remote attachment and physical Duo behavior remain
client acceptance checks. Sway owns workspace names; Herdr owns session names
and lifecycle. Ethernet and the Strix hostname move are separate operations
and are not performed by this branch.
