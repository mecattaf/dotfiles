# Per-display warmth on Domicile

The Zenbook keeps the same fixed warmth heuristic as its former kanshi
profiles: 3850 K on the upper panel and 3350 K on the lower panel. These
values are a comfort setting, not a measured physical color match or an ICC
calibration. Tom dropped physical matching as a completion condition on
2026-11-08 (#541).

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

Unknown displays are left unchanged. The PA27JCV was not connected during the
2026-11-08 inspection, so its Domicile identity and subjective preferred
warmth are unmeasured. Observe that identity before adding a named temperature
or output profile. A value of 6500 K means unchanged colors in Domicile's
night-light API; it does not calibrate the display.
