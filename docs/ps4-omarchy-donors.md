# What the Omarchy PS4 lineage contributes to ps4-dummy

The donor is the implementation behind [omarchy.mrz.sh](https://omarchy.mrz.sh/),
not its desktop theme. This audit inspected
[`meerzulee/omarchy-psx` at `2c154e11febc1c0ea500c95eaedb791868322b3d`](https://github.com/meerzulee/omarchy-psx/tree/2c154e11febc1c0ea500c95eaedb791868322b3d),
alongside the separate `linux-psx` kernel project at
`886e35141787c26c2eb5df0558109d3ac35d38ad`. NixOS remains the system base.

## The useful engineering is in the platform boundaries

| Source mechanism | ps4-dummy adaptation | Qualification boundary |
| --- | --- | --- |
| Labelled external root with an early USB-ancestry and two-partition guard | Adapted into `pkgs/ps4-platform/init`; require partition 2, a same-disk FAT `PS4BOOT`, NixOS marker and executable `/sbin/init` | Our Btrfs/512 MiB FAT layout is a new candidate, not the old 4 GiB FAT/ext4 artifact |
| Kernel, full modules, initramfs, arguments and loader treated as one boot set | Nix derivations and boot-file checksum manifest; distinct kernel release and coherent 1024 MiB recovery set | A successful build does not qualify boot, firmware or memory bandwidth |
| Internal SATA disabled and automounters absent | Global `libata.force=disable`, external USB root; fleet headless profile disables UDisks/GVfs | Controller/IDENTIFY activity can precede disable; do not claim no electrical access |
| Native Baikal Ethernet, no distro activation shim | Matched `psx_mts_net` module plus normal NetworkManager wired DHCP with MAC preserved | Fresh all-wired BE550 traffic must qualify the actual kernel/console |
| First owner, explicit credentials and key-only SSH | Existing fleet public SSH keys and a fresh local identity; manual Tailscale enrollment, no copied NAS credentials | Friend's Slim ownership is separate from Tom's permanent original consoles |
| Unsupported PC lifecycle operations removed | No GRUB/UEFI/Plymouth takeover, automatic disk conversion, PC power-profile daemon or firmware updater | NixOS declaration supplies the equivalent boundary; do not install Omarchy wrappers |
| Source-pinned firmware injection and artifact identities | Loader extracts this console's GPU firmware; early init preserves graphics firmware in tmpfs | No firmware/console HDD key is committed, fetched from arbitrary mirrors or published |
| Recorded failing graphics paths | Keep optional local desktop isolated from inference and test it independently | DCE8 gamma/DDC and Chromium GPU failures are not claims that compute is unavailable |

The main source files are
[the early init](https://github.com/meerzulee/omarchy-psx/blob/2c154e11febc1c0ea500c95eaedb791868322b3d/rootfs/initramfs/init),
[the kernel integration guide](https://github.com/meerzulee/omarchy-psx/blob/2c154e11febc1c0ea500c95eaedb791868322b3d/docs/USING-LINUX-PSX.md),
[the package exclusion list](https://github.com/meerzulee/omarchy-psx/blob/2c154e11febc1c0ea500c95eaedb791868322b3d/platforms/ps4/profiles/omarchy-full/blocked-packages.txt)
and [the runtime differences](https://github.com/meerzulee/omarchy-psx/blob/2c154e11febc1c0ea500c95eaedb791868322b3d/manual/05-whats-different-on-ps4.md).
The adapted USB guard retains the donor's MIT copyright/license in both the
repository and generated initramfs/boot-file bundle.

## What is deliberately different here

The published Omarchy kernels disable netfilter and its guide explicitly says
there is no firewall. This is a kernel configuration condition, not a PS4
hardware prohibition. Our source-built psX derivative enables netfilter,
nftables and TUN and retains the fleet firewall. Copying Omarchy's disabled
firewall into the appliance would discard the requested fleet boundary.

Likewise, Omarchy's 1024 MiB VRAM carveout is a historical desktop profile.
This inference candidate uses 128 MiB and a 7168 MiB TTM backing-page ceiling,
with the same new kernel at 1024 MiB available for comparison/recovery. The
donor's dynamic-memory discussion supplies a methodology, not a ready
runtime-resizing switch. Larger GPU allocations and native-like bandwidth
remain actual PS4 qualification work. Do not add cache/model quantization to
mask an allocation-path failure.

The donor's init supports installation, splash, whole-device filesystems,
partitioned ext4, owner provisioning and historical FPKG profiles. The NixOS
init only performs a bounded verified USB-root handoff. It has no installer,
automatic resizing, splash process, password prompt or console-internal
boot-file write. It preserves `/run` for local GPU firmware and enters the
declarative NixOS generation through `/sbin/init`.

The donor's automatic-growth mechanism verifies the running USB's transport,
labels, partition count and geometry before changing its system partition.
Our first image instead leaves automatic growth off. A later explicit USB
growth operation can adopt that verification discipline while using Btrfs
resize rather than `resize2fs`. Never copy the ext4 growth command onto this
Btrfs root.
[Storage and layout](https://github.com/meerzulee/omarchy-psx/blob/2c154e11febc1c0ea500c95eaedb791868322b3d/manual/07-storage.md).

## Performance and reliability findings

The source audit did not find a special PS4 sysctl bundle, a measured
inference clock governor, a proven universal GPU overclock or a ready 7 GiB
unified-memory allocator hidden in the distribution. Searches covered its
rootfs, package policies, profiles, boot arguments and build scripts. Do not
invent such a tuning layer from the desktop's speed.

Its useful performance work resides in the separate Linux psX kernel/Mesa
lineage: correct device/firmware initialization, the native retained-DMA
Ethernet driver, display quirks, bounded controller waits and specific
Liverpool instruction-selection fixes. These support the custom
Garlic/Bonaire inference host but do not replace that host or Bonsai's exact
PTQ/state/attention kernels. Userland memory savings come from keeping the
normally idle desktop and unrelated services inactive, not from deleting
their packages from the available fleet suite.

The native Ethernet interface is `psx0`. MAC randomization fails because the
driver has no `ndo_set_mac_address`; an ordinary preserved-MAC NetworkManager
profile is the correct adaptation. The driver retains one DMA/code generation
until power-off and must not be unloaded, reset or rearmed after publication.
Old userspace `ps4-ethernet` activation units are retired donors, not services
to restore. [Networking details](https://github.com/meerzulee/omarchy-psx/blob/2c154e11febc1c0ea500c95eaedb791868322b3d/manual/06-networking.md).

The current dev6 source already includes native MTS Ethernet. A later
instrumented `net1` module's SSH recovery followed reassociation of the
separate Wi-Fi client; that observation does not prove a required driver
fix for the all-wired BE550 deployment. Preserve the known source pairing,
then measure DHCP, interface-bound traffic, independent bidirectional hashes,
errors, repeat boots and link recovery on this hardware. Do not cherry-pick
an instrumented diagnostic module simply because its experiment is newer.

The desktop record reports a DCE8 gamma path that blacked out HDMI and a
Chromium GPU path that produced tiles. Those findings justify separate local
desktop validation and avoiding unsupported gamma/DDC operations. They do not
imply that direct amdgpu compute or all Vulkan programs are slow. The headless
appliance keeps amdgpu/render nodes available and starts no compositor during
inference. The native Garlic shader/packing reference remains the compute
control.

## Broader console support

The donor's source migration separates distribution concerns from kernel
targets. That is directly useful: keep one NixOS host/USB construction path
and select a source-pinned platform bundle for the console. The Baikal-derived
beta2 source is the current build control. Linux psX's separate `7.2-ps4`
target carries the Aeolia/Belize rmux lineage and is a concrete next source
candidate, not an already accepted universal binary. That second candidate is
now packaged explicitly in `pkgs/ps4-platform/universal.nix`: clean upstream,
the pinned 176-patch series, general config, fleet nftables/TUN and the exact
native MTS autoload adapter. It has its own release/module tree and boot
bundle. This structure leaves room for both original consoles without
changing the model-plugin API.

There is also concrete later clock-work to inspect in that general series.
Patch 0161 removes the older startup force-max SCLK driver; patch 0167 adds
a Liverpool/Gladius SMU mailbox implementation with memory-Pstate and raw
message interfaces. This exposes a possible measured-tuning path, not a
proven speed improvement or an instruction to write registers during setup.
The general config leaves `CONFIG_PS4_CPUFREQ` disabled despite having a
Jaguar CPU-frequency driver in source. Keep these distinctions in future
performance comparisons; names or hardcoded reported clocks cannot settle
the achieved clock.

## Unknowns and proposed defaults

- The exact Slim southbridge/firmware remains for the attended UI pass.
  Default: select its matching bundle explicitly rather than infer Baikal
  from the word Slim.
- The adapted USB guard, new initramfs, netfilter kernel and 128 MiB carveout
  need physical boot evidence. Default: build and verify now; qualify the
  complete paired set on the console afterward.
- Desktop applications can be available without being resident. Default:
  inference is headless, and any Kitty/Domicile/Herdr suite test is a distinct
  session with measured memory and no automatic restart of live sessions.
- Future kernel updates must move boot files and modules coherently. Default:
  keep previous closures and the separate Orbis fallback until the replacement
  boot has passed; an activated NixOS generation alone is not kernel evidence.
