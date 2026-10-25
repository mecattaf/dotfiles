# Desktop shell

Native Solid 1 UI through the published GPUIX 0.10.0 Linux addon. Hyprland owns
composition, effects and windows. Chrome remains the browser and Herdr/kitty
remain the terminal system.

`desktop-shell` runs the top bar. `desktop-shell launcher`, `windows` and
`controls` open separate layer-shell surfaces; repeating a popup command closes
that popup. Escape and the Close action exit only the shell popup, never a
selected application. The bar uses a 32px exclusive zone. Popups use their own
`desktop-shell-<mode>` layer namespace and exclusive keyboard interaction.

The launcher searches current Hyprland windows and installed XDG desktop
applications. Applications launch through GIO with the desktop entry path as a
single argument, not a parsed shell command. Up/Down selects results, Enter
opens, and Tab/Shift-Tab navigates controls. Window navigation includes native
workspace focus/moves and Hyprland group membership. Workspace lifecycle actions
delegate to `desktop-workspace`, preserving the existing Herdr parking policy.

Controls delegate volume, backlight, media, audio-route and screenshot behavior
to the existing commands. Network and Bluetooth open their installed controls.
Effects toggles affect the current compositor instance until configuration
reload. The package does not replace Vicinae, notification services, screen
locking, session persistence, a browser or a terminal renderer.

State comes from initial `hyprctl -j` snapshots and the Hyprland event socket.
Events coalesce over 40ms; reconnect backs off to 10 seconds. Disconnected state
disables controller actions and retains the last snapshot for orientation. An
in-flight old snapshot cannot mark a disconnected compositor healthy. System
status refreshes every 15 seconds. Linux GPUI runs on its own UI thread; the
500ms `tick` checks only whether that native loop has exited.

Colors follow `~/.config/theme/kitty.conf` and the existing `theme` symlink;
`SIGUSR1` also reloads the palette. Fonts use the installed Anthropic Sans. The
fallback palette is copied from `home/themes/noir.nix`. Surface alpha gives the
compositor its blur input; there is no CSS or WebView blur implementation.

## Build and validate

The Nix package pins every npm dependency through `package-lock.json` and a
fixed npm cache hash, runs the TypeScript check and nine controller tests,
compiles Solid with the universal compiler, and patches the published native
addon to Nix libraries. It currently supports x86_64 Linux. GPUIX and Solid have
their own upstream licenses; there is no source build of the GPUI fork here.

Do not externalize `solid-js` from the Bun build: its Node conditional export
is the server runtime. The GPUIX build plugin replaces that module with the
reactive runtime before bundling.

```sh
nix build .#desktop-shell
result/bin/desktop-shell --help
runtime-test -- result/bin/desktop-shell --check-native
runtime-test -- bun test
```

The pure tests cover exact action arguments, window-ID validation, snapshot
shape, split event framing, reconnect and stale-result ordering, desktop-entry
visibility, search, and palette parsing. Native addon loading is not evidence
of a working compositor surface. Actual GUI tests must run inside the repository
runtime isolation harness, with no live seat, input devices, manager or D-Bus
session exposed. See the integration smoke tests for rendered surface evidence.

Known boundaries: GPUIX currently does not expose an output selector here;
placement follows its compositor-selected output. The stock Linux GPU screenshot
test renderer is unavailable in this GPUIX release. No CPU, latency, multi-monitor,
IME or assistive-technology acceptance claim follows from the controller tests.
