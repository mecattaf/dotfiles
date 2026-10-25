# Deferred GPUI background-effect research

**Stopped at Tom’s request: retain Sway as the window manager.** This patch is
unfinished research, not an enabled feature. It is not applied by the desktop
shell package and does not modify the shipped `@gpuix/native` npm addon.

## Source and intended change

Targets `remorses/zed` revision
`c2e9f882030ca95cee55d206512a0a3ee6cd72b0`, the GPUI fork used by the researched
GPUiX source. Apply from that repository root. The patch changes only the Linux
Wayland client/window modules and the `gpui_linux` Wayland protocol dependency.

The intended behavior is to bind `ext_background_effect_manager_v1`, observe its
dynamic BLUR capability, and prefer that protocol for explicit
`WindowBackgroundAppearance::Blurred`. It keeps the existing KDE protocol as a
fallback when standard blur is unavailable. Transparent and opaque appearances
remove any requested blur. Regions use logical surface-local coordinates,
refresh on resize, and are committed through GPUI’s normal redraw/presentation
path. Effect objects are destroyed before their `wl_surface`. Capability changes
refresh existing windows without holding the client’s RefCell borrow.

## Evidence and validation actually completed

- Read exact-revision `client.rs`, `window.rs`, manifests and lockfile.
- Read the cached `wayland-protocols` 0.32.13 protocol XML and Rust module.
  `ext::background_effect::v1` exists under the already-enabled `staging` feature.
  Its NULL region disables blur; the initial region is empty. Region changes and
  destruction take effect on the next surface commit.
- Read Hyprland v0.56.0 `BackgroundEffect.cpp`: it advertises BLUR and handles
  surface commit/removal. This is source evidence, not this patch’s runtime proof.
- Created an intended implementation and a backend-selection unit test in the
  patch. **Neither the test nor the native module was compiled or executed.**
- An offline Cargo resolution attempt failed on an uncached `async-process` git
  dependency. Online resolution was then started with the complete exact-revision
  source archive. A native `cargo check -p gpui_linux --no-default-features
  --features wayland -j 8` was started in a Nix development environment, waiting
  for the shared package-cache lock. Both specific Cargo processes were terminated
  when Tom chose Sway. Dependency resolution had not completed; no compiler
  diagnostics about the patch exist.

## Incomplete work and limits

The original lockfile pins `wayland-protocols` 0.32.9 and `wayland-client` 0.31.11.
The patch raises the protocol minimum to 0.32.13, which also needs a compatible
client/scanner resolution. **No Cargo.lock update is included.** A later resumed
implementation must finish a narrowly scoped lock update, compile the whole
module/addon, run the tests, and verify live protocol requests and rendered blur
in an isolated compositor. Applyability/formatting checks remain unperformed.

This is not a general rounded-region implementation: the proposed blur region
covers the logical surface rectangle. Rounded translucent client content would
need compositor-aware validation. Registry-global hot removal remains subject
to GPUI’s existing unimplemented global-removal handler; dynamic capability
changes are handled by the proposed patch. No implementation is required for the
current Sway decision, and no service, compositor, or live session was changed
by this research.

Working source and stopped build logs were left outside the repository:

- `/tmp/gpui-ext-background-effect-c2e9f882` (original and edited files)
- `/tmp/gpui-ext-full/zed-c2e9f882030ca95cee55d206512a0a3ee6cd72b0`
- `/tmp/gpui-ext-cargo-update.log`
- `/tmp/gpui-ext-cargo-check.log`

These temporary paths are inspection aids, not durable build dependencies.
