# PS4 Mesa package

This host-local package carries the Linux psX GPU userspace lineage into NixOS.
It does not install an Omarchy root or desktop. `hosts/ps4-dummy/hardware.nix`
selects it only for that host; all existing fleet Mesa selections stay unchanged.

The source is official Mesa 26.2.5, pinned by archive SHA256 in `sources.json`.
The patch set is copied from `meerzulee/linux-psx` at
`886e35141787c26c2eb5df0558109d3ac35d38ad` and preserves that source manifest's
individual hashes, MIT notices and attribution:

- `0001`: recognize Liverpool/Gladius, select the GFX7 compiler family and PS4 raster layouts.
- `0002`: constrain video capability reporting to the kernel-confirmed AVC path.
- `0003`: validate the selected FMASK tile entry without requiring an unused table entry.
- `0005`: retain the caller's bounded metadata-fill offset in NIR so ACO can use the appropriate buffer addressing.

The historical `0004` HTILE-disable patch is deliberately absent because it is
absent from the pinned dev5 manifest. Do not add it merely because its filename
occurs in the donor repository.

The package builds radeonsi, RADV, EGL and GBM together from the patched source.
ACO supplies the GPU compiler; LLVM, Rusticl and an OpenCL runtime are disabled.
The package still needs the psX amdgpu kernel and console-specific boot firmware.
The custom Garlic-derived direct-libdrm backend does not require Mesa at all.

Nixpkgs supplies build dependencies and fixup machinery, while the source,
patches and selected Meson options are explicit here. The two output roots are
the drivers and split debug symbols. The check phase is CPU-side source/unit
validation, without a console or GPU submission. Building this derivation is
not evidence that Domicile, video decoding, Vulkan workloads or inference ran
successfully on a PS4.

## Required userspace CPU audit

The PS4 host keeps generic x86-64 packages, with no Strix host/ROCm profile.
The actual installed herdr-core 0.1.22 ELF reports `x86-64-baseline` in its GNU
ISA property; the exact upstream [Ghostty build script](https://github.com/herdrdev/herdr-core/blob/v0.1.22/crates/ghostty-vt/build.rs)
also passes `-Dcpu=baseline`. Its Linux Cargo/Nix flags do not request a native
or v3 CPU target. The inspected Tailscale 1.98.8 executable's embedded Go build
metadata records `GOAMD64=v1` and `CGO_ENABLED=0`. The Neovim 0.12.4 derivation
uses generic CMake flags without a native/AVX2 target; its exact resulting
executable was not available in this audit's NAS store.

The pinned Domicile flake explicitly uses Bun 1.4.4's upstream
`bun-linux-x64-baseline.zip`, rather than the default non-baseline x64 archive.
These source/build observations found no demonstrated required AVX2 path.
They do not replace executing the actual image on Jaguar, including shared
libraries and CPU-dispatched paths.

## Unknowns and proposed defaults

The donor has bounded observations on a particular Liverpool/Baikal B1 boot,
not universal API or console qualification. Default to headless operation;
qualify any requested graphics or compute path on the actual console before
calling it available for production. Keep the direct-GCN and specialized-Vulkan
execution candidates behind the same inference runtime boundary.
