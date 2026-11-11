# Imagine production payload

Frozen from the Zenbook's running 2026-11-08 production source
(`/nix/store/10lfkggi8bzf18cy8r8dp1z8vp5fjsgf-imagine`), with client-supplied
a client-supplied fixed whitepoint through the public Domicile display API.
The stability rollback uses the original global-only API: 3850 K on every
connected output, including after docking and undocking. Different temperatures
per panel require a newer qualified engine.
The separate working Imagine repository remains untouched.

This is a vendored Nix input, not a standalone build checkout. Dotfiles checks
`domicile-config` and `domicile-display-temperatures` validate it against the
Domicile revision selected by the root flake. Only production `src` files,
package.json and LICENSE ship to the client. Unit tests stay in this checkout.

The active stylesheet derives from Manganese 75708d763800, while owned shell
modules retain their individual extraction provenance. MIT notices are in
LICENSE and src/imagine/LICENSE; provenance records are retained separately
from current qualification. Historical proof logs are not current test results.
