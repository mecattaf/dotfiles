# Isolated native desktop and blur proof

`smoke.py` runs the real built native shell and Hyprland on a nested Sway
headless output. All compositors and clients are below `runtime-test` with one
validated render-only DRM node, private runtime/PID/IPC namespaces, a private
non-activating D-Bus session, no physical input or display nodes, and no network.
The inner bubblewrap explicitly carries only the **already isolated** `/dev`.
No user-manager or Herdr socket is reachable.

Stock Aquamarine 0.13 cannot nest on the current parent compositors: it binds
`xdg_wm_base` and `wl_compositor` v6 regardless of advertised version. It also
queues its initial surface commit after its initial dispatch and does not flush
it, leaving the first output waiting for a configure event. The test-only
`aquamarine-nested.nix` clamps those two binds and flushes the initial output.
The audited requests require wl_compositor v4 and xdg_wm_base v1; the parent
Sway offers v6 and v5 respectively. This changes **only the isolated child's
library lookup**, not the production package or host session. Evidence records
the exact library path. A successful run is not stock nested-backend validation.

Build the fixture:

```sh
nix build --impure --no-link --print-out-paths --expr \
  'let f = builtins.getFlake (toString ./.); in import ./tests/hyprland/aquamarine-nested.nix { pkgs = f.nixosConfigurations.client.pkgs; }'
nix build --no-link .#nixosConfigurations.client.pkgs.wayland-utils
```

Run with the resulting library and desktop-shell package:

```sh
python tests/hyprland/smoke.py \
  --shell /nix/store/…-desktop-shell-0.1.0/bin/desktop-shell \
  --nested-library /nix/store/…-aquamarine-nested-test-0.13.0/lib
```

The test verifies the actual delivered Hyprland configuration, live window
movement, advertised standard background-effect and existing output-manager
protocols, native layer-shell mapping, rendered screenshots and popup singleton
closure. It places a deterministic high-frequency terminal background behind the
controls surface and captures compositor blur off/on. `blur-metrics.json` records
pixel difference, edge-energy change, surface geometry, and short isolated CPU
samples. Those CPU samples are smoke evidence, not a production performance claim.
Every run retains its own `/tmp/hyprland-solid-smoke-*` directory with exact
metadata, stdout/runtime logs and screenshots, including unsuccessful runs.

Current protocol boundary: Hyprland 0.56 implements `ext-background-effect-v1`.
The GPUI fork pinned by the current npm addon instead implements KDE's older blur
protocol. Transparent native surfaces plus the Hyprland namespace blur rule give
real compositor blur today. A source patch for GPUI's ext protocol is a separate
artifact until a native addon built from that patch is packaged and tested.
