# Imagine production payload

Frozen from the Zenbook's running 2026-11-08 production source
(`/nix/store/10lfkggi8bzf18cy8r8dp1z8vp5fjsgf-imagine`), with client-supplied
per-output temperatures added through the public Domicile display API.
The separate working Imagine repository remains untouched.

This is a vendored Nix input, not a standalone build checkout. Dotfiles checks
`domicile-config` and `domicile-display-temperatures` validate it against the
Domicile revision selected by the root flake. Only production `src` files,
package.json and LICENSE ship to the client. Unit tests stay in this checkout.

The active stylesheet derives from Manganese 75708d763800, while owned shell
modules retain their individual extraction provenance. MIT notices are in
LICENSE and src/imagine/LICENSE; provenance records are retained separately
from current qualification. Historical proof logs are not current test results.

## Imagine shell follow-up

The current Manganese launcher (Meta+D), clipboard panel (Meta+V), and native
F9 audio/recording menus are functional carryovers. Their current presentation
is not the finished Imagine aesthetic. Reworking these surfaces belongs to
Imagine's shared shell/interface design, rather than treating the existing
Manganese appearance as the desired end state. The design follow-up is
tracked in [Imagine issue 1](https://github.com/agency-agency/imagine/issues/1).

F10 is mapped to Domicile's native display sleep; Shift+F10 explicitly wakes
all displays. Input after the compositor's one-second release guard also
wakes them. This preserves window/workspace placement and brightness levels.
It requires a running compositor implementing `sleep_displays`/`wake_displays`;
an updated SDK or a shell reload alone cannot add those compositor calls.
