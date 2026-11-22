# Domicile on the Zenbook

Domicile is the only physical desktop. `hosts/client/default.nix` imports
`modules/domicile.nix`; greetd starts its physical-session launcher once and
returns to a console shell after exit. No Sway, Niri, Vicinae, Mako, Waybar,
Kanshi, external launcher, clipboard daemon or gamma relay is installed.

The client config is `home/dot_config/domicile/domicile.tsx`. It uses the
bespoke Imagine shell from [agency-agency/imagine](https://github.com/agency-agency/imagine) through public Domicile
capabilities. Its implementation, tests and provenance live in that repository;
dotfiles pins the source and supplies shortcuts and device configuration.
Domicile source, SDK and official
engine are selected together by the upstream flake. The compositor has no local
engine patches. The config and every relative production import are checked and
bundled together before installation.

Domicile owns Finder/application launch, clipboard, notifications, screenshots,
recording, native input settings and quick settings. Finder includes Quick
settings plus direct dock audio routes and INZONE noise controls. `zoneout`
remains available for explicit hardware volume/balance values. The retired
fzf desktop menus and compositor-specific scripts have been deleted. `fzf`
remains a terminal tool for interactive shells.

Meta+Return opens a fresh NAS terminal; Meta+Shift+Return opens a local recovery
terminal. Meta+j/k switch outputs. The existing Imagine workspace, chat and
terminal policy is retained. NAS continues to own Herdr and agent sessions.
Client notification clients use the desktop's notification service.

Imagine uses plain tree tiling by default; the scrolling layout was retracted
on 2026-11-19 ("i retract the scrolling window mgmt logic. prefer good old tiling.").
Meta+F cycles the nearest horizontal split and Meta+G the nearest vertical split
through one quarter, one half and three quarters; Shift reverses. Other siblings
share the remaining space proportionally. No split on that axis means no change.
`tiling: { gap: 13 }` adds about 3 mm between windows on the scale-2 5K output,
with no outer margin. Plain tiles have no individual title bar and restore all
four border edges. Tabbed and stacked groups retain their tab strips.
Window focus uses the existing Noir/Sway border roles from `home/themes/noir.nix`:
active `#555451`, inactive `#373735`, at 1px. The checked config bundles those
roles as `window-borders.json` and passes them to Imagine; it paints the actual
window border when focus moves. No separate near-black focus outline is used.

Meta+Ctrl+Space switches between Tiling and Floating; the rail also offers both.
Floating retains its geometric size presets and tab groups. Every decorated
float has three circles at the top right: green zoom, yellow minimize and red
close. Their centered SVG icons come from Manganese (maximize, four squares and
X); their existing actions are preserved. Tab strips reserve room beside tabs
and the new-tab button. The separate per-tab close X uses its original
Manganese color, without a red override.
Titles use the stylesheet paired with the installed Domicile SDK, including
its active-title text rule. Meta+minus restores minimized windows;
Meta+Ctrl+G keeps grouping. Meta+= remains true fullscreen.
Fake fullscreen remains future work.

Old saved scrolling mode choices migrate to tiling. No ribbon, viewport clipping,
Meta-wheel panning or scroll-position persistence remains. Mode choices survive
desktop starts; topology, native IDs and floating geometry stay process-scoped.
Solo groups suppress border paint without changing content bounds.

See Imagine's [desktop intent](https://github.com/agency-agency/imagine/blob/main/docs/DESKTOP-INTENT.md).
Shell changes use the existing watched-config/load-shell path; installing a
closure alone does not prove that a running shell has loaded it.

Duo uses two native DRM displays at scale 2, stacked at (0,0) and (0,900).
DuoDocked uses only the upper panel. With the ASUS PA27JCV attached, Duo5k
and DuoDocked5k keep those panel scales and positions and put the 5120×2880
external display at (1440,0), to the right of the upper panel, also at scale 2.
Its confirmed Domicile identity is `drm-1886053529622275`. The larger physical
text on the ASUS is intentional (Tom, 2026-11-10).

Meta+1–5 stay on the upper Zenbook panel; Meta+6–9 belong to the ASUS while
connected, including empty workspaces. Unplugging it returns 6–9 to the upper
panel; reconnecting restores their ASUS homes without moving their windows
between workspaces. Meta+0 stays on the lower panel, falling back to the upper
panel when the keyboard covers the lower one. Windows keep their horizontal
split layout on every display.

Domicile matches profiles against the exact set of connected monitors.
Explicit external-monitor profiles prevent hotplug from falling back to the
engine's default horizontal layout and scale 1. They precede the laptop-only
profiles; unplugging the monitor restores Duo or DuoDocked without changing
the laptop's scaling. Prior Kanshi panel temperatures are applied
through `displays.setColorTemperature(kelvin, displayName)`: upper 3850 K,
lower 3350 K. The shell applies these when displays appear; the compositor
retains/reapplies them across modesets. Fixed per-output temperatures replace
the scheduled global night light on this seat.

Input uses the documented native `input.touchpad` and `input.mouse` settings.
Keyboard repeat is explicitly 200 ms at 25 repeats per second through
`input.keyboard.repeat`, preserving Tom's preferred response in native clients
and browser pages instead of the upstream 500 ms default.
Touch and stylus devices map to their respective DRM panels. No reconnect
script is needed: Domicile applies settings to newly discovered devices.
Tom recovered Magic Trackpad tracking and scrolling by power-cycling it on
2026-11-08; that observation is not evidence of a compositor fix or a diagnosed
Bluetooth fault. No pinch tuning or experiment was performed.

Builds run on strix-coordinator after checking at least 25 GiB free. Runtime
experiments use target `runtime-test`. A system closure on disk does not change
the running engine. An engine update needs a physical login transition after
preserving live work; ordinary shell changes use the watched config. Never
restart Herdr or the user manager to perform this update.

From a physical recovery console, use `domicile-recover status`,
`domicile-recover check`, or `domicile-recover rescue`. Run `domicile` to enter
the installed desktop. `domicile-console-trial` uses the checked immutable
candidate without changing the installed system or kernel.

## Repeating the fan and rendering measurements

From the NAS, run a passive observation of the existing client desktop:

```sh
domicile-perf record --label two-codex --seconds 30
domicile-perf latest
domicile-perf latest --json
domicile-perf compare /path/to/earlier-run.json
```

Runs are timestamped JSON files in `$XDG_STATE_HOME/domicile-perf` (normally
`~/.local/state/domicile-perf` on NAS). `latest.json` points to the last successful
run. A failed SSH connection, GPU restart or counter reset leaves it intact.
`~/.local/state/domicile-perf/run` retains the latest successful runner, so
`~/.local/state/domicile-perf/run latest` also works before the PATH command
is installed. The exact sampler source is retained by its SHA256 beside each run.
The JSON includes interval samples, means/ranges, actual running Domicile/engine
provenance, session age, display modes/scales, shell path, window sizes, power
profile, battery state and measurement CPU/read overhead. Window text, titles,
URLs and process arguments are omitted. The source SHA256 identifies the sampler.
The label describes what the caller observed; it does not certify a static screen.

The SSH target defaults to `client`; `--host local` measures the local desktop.
Both need passwordless `sudo -n` to read RAPL and DRM counters. The collector
runs as root, but desktop CLI queries run as the desktop's user against the
socket found in its compositor environment. It refuses ambiguous desktops.
Nothing is installed on the target. There is no resident service or schedule.
It reads the real desktop, so this diagnostic is deliberately outside
`runtime-test`; it never starts a compositor, sources shell fragments, cleans
runtime directories, changes the shell, or changes window placement. Fixture
tests of the utility run under `runtime-test`.

For a reproducible workload, run this in an otherwise quiet visible Kitty:

```sh
domicile-perf animate --hz 10 --seconds 60
```

It changes one terminal character ten times per second and exits. Measure from
another agent or terminal with `record --label one-spinner-10hz --seconds 30`.
Keep the measurement terminal static or hidden. A busy agent's progress indicator
can itself cause redraws; keyboard idle time is not proof of a static screen.
The fixture is a proposed repeatable workload, not a completed equivalence test
against Codex's rendering behavior.

Use the same display layout/scales, power profile, shell, terminal geometry,
workload rate and warm-up for each comparison. Measure a fully static desktop,
one animated terminal on an internal display, one on the 5K, then both displays.
Allow the temperature to settle and repeat conditions in reverse order to check
thermal history. `--delay 30` allows a one-shot settling interval before sampling.
Do not stop live sessions to obtain a static baseline: wait until they finish.
Each record is one labelled observation, not an automated pass/fail verdict.

GPU percentages are render-engine activity from unique DRM clients of Domicile's
Chromium GPU process, not total CPU or whole-GPU utilization. RAPL watts cover
the processor package, not wall power or the monitor. Temperature and RPM are
device-specific lagging outcomes; the software regression metrics should be
matched-workload render activity, package power and eventually damage/frame cost.
Missing sensors remain unavailable, never zero. A comparison of two different
labels or layouts is diagnostic, not proof of a regression. This passive sampler
does not record frame latency, damaged area or optical input-to-photon latency.
Those require an owning-layer trace or a controlled upstream benchmark.

Historical observations (project dotfiles T-156, Nov 14–22, 2026): the Nov 12
build sustained 45–55% Domicile render activity and 11–13.5 W with fan noise.
After the Nov 19 update, a truly static desktop reached 0%, 3.5–4 W and fan off;
one animated 5K terminal measured 16–20%, about 7.5 W and fan cycling. On Nov 22,
two active Codex terminals on separate displays measured about 31.7%, 10.24 W,
61–63°C and 2900 RPM. These are different observed workloads, not a controlled
version-by-version benchmark or proof of an uptime leak.
