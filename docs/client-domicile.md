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
Floating retains its geometric size presets and tab groups. Controls are on the
right: green zoom, yellow minimize, red close, including manually floated
windows on a Tiling workspace. Room is reserved beside tabs
and the new-tab button. Titles use the stylesheet paired with the installed
Domicile SDK, including its active-title text rule. Meta+minus restores minimized windows; Meta+Ctrl+G keeps
grouping. Meta+= remains real fullscreen. Fake fullscreen remains future work.

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
