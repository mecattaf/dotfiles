# Domicile on the Zenbook

Domicile is the only physical desktop. `hosts/client/default.nix` imports
`modules/domicile.nix`; greetd starts its physical-session launcher once and
returns to a console shell after exit. No Sway, Niri, Vicinae, Mako, Waybar,
Kanshi, external launcher, clipboard daemon or gamma relay is installed.

The client config is `home/dot_config/domicile/domicile.tsx`. It uses the
maintained Imagine shell through public Domicile capabilities. A frozen copy of
the previously running production shell lives in `pkgs/client-desktop/imagine`;
its MIT notices and provenance remain with it. Domicile source, SDK and official
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

Duo uses two native DRM displays at scale 2, stacked at (0,0) and (0,900).
DuoDocked uses only the upper panel. Prior Kanshi panel temperatures are applied
through `displays.setColorTemperature(kelvin, displayName)`: upper 3850 K,
lower 3350 K. The shell applies these when displays appear; the compositor
retains/reapplies them across modesets. Fixed per-output temperatures replace
the scheduled global night light on this seat.

Input uses the documented native `input.touchpad` and `input.mouse` settings.
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
