# Per-display warmth on Domicile

Blue-light protection is on for the whole desktop, all the time. Tom,
2026-11-12: "i still want to have the asus monitor also have gamma applied!
i want destop-wide blue light protection on by default all the time."

The Zenbook keeps the same fixed warmth heuristic as its former kanshi
profiles: 3850 K on the upper panel and 3350 K on the lower panel. The ASUS
5K gets 4000 K. These values are a comfort setting,
not a measured physical color match or an ICC calibration. Tom dropped
physical matching as a completion condition on 2026-11-08 (#541).

## Previous kanshi behavior

Before `486cc5aa` retired the old compositor tools,
`home/dot_config/kanshi/config` ran these profile hooks:

```text
Duo:
  eDP-1 -> busctl --user set-property rs.wl-gammarelay /outputs/eDP_1 rs.wl.gammarelay Temperature q 3850
  eDP-2 -> busctl --user set-property rs.wl-gammarelay /outputs/eDP_2 rs.wl.gammarelay Temperature q 3350
DuoDocked:
  eDP-1 -> busctl --user set-property rs.wl-gammarelay /outputs/eDP_1 rs.wl.gammarelay Temperature q 3850
```

The separate old LG desktop profiles used 4000 K for DP-4 and DP-1, including
their single-display fallbacks (`96d875ef`). Those connector assignments and
temperatures do not identify the replacement ASUS monitor. The speculative
PA27JCV dock profiles were removed in `54c17bed` after physical inspection
found no external display connected. Do not reuse the old monitor serial.

## Native replacement

`home/dot_config/domicile/domicile.tsx` maps Domicile's confirmed panel IDs:

- `drm-21536134253248512`: upper panel, 3850 K.
- `drm-21536134253248513`: lower panel, 3350 K.

Imagine's `maintainDisplayTemperatures` calls
`domicile.displays.setColorTemperature(kelvin, displayName)` for each matching
display when it mounts and whenever Domicile reports a display change. An
absent panel receives no call; its temperature is restored when it returns.
Transport failures and refused requests are reported. Domicile owns gamma,
resume and modeset handling; no kanshi hook or wl-gammarelay service is needed.
Global scheduled night light is off, so it does not overwrite this policy.

`checks.x86_64-linux.domicile-display-temperatures` covers named-panel routing,
an initially absent display report, lower-panel reattachment, unsubscribe and
both transport and returned-error reporting. The home-profile check also
requires both panel IDs and their configured temperatures.

## External monitor

The PA27JCV was connected and identified on 2026-11-10 as
`drm-1886053529622275`, native 5120×2880. Its output profiles use scale 2 and
place it to the right of the upper Duo panel; both laptop panels retain their
original scale 2 and vertical stack. Tom confirmed this layout live.

It gets 4000 K, the warmth the old LG desktop monitors used. A display the
policy does not name is left unchanged; covering displays plugged in later is
for Tom's own Imagine shell work. A display without a hardware gamma table
(DisplayLink/evdi) refuses the request, and the refusal is reported (upstream
cprussin/domicile#1970 keeps the composited fallback as a known gap).

## Version history

- 2026-11-11: the OOM rollback (`c15c4937`) went to a Domicile SDK older than
  per-display gamma (upstream #1921). It dropped this policy and fell back to
  the global sunset-to-sunrise schedule.
- 2026-11-12: Domicile at `e2b4bc54` restores the per-display API and the
  redraw-on-ramp fix (#2028). The policy is back, and now includes the ASUS.

Verify on the hardware with
`ssh client python3 - < ~/notes/journal/2026/11/12/closeout/zenbook-read-gamma.py`:
each of the three outputs' `GAMMA_LUT` must be non-identity, with a lower blue
`white_rgb` on the lower panel than on the upper one.
