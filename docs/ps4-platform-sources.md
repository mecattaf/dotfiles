# PS4 platform source and boot contract

This is the platform beneath `ps4-dummy`, a headless NixOS inference appliance.
Its GPU target is Liverpool, with inference kernels compiled for LLVM's
`bonaire`/gfx704 target. Neither Orbis userspace nor a graphical desktop runs
beside Linux inference. Orbis remains intact on the internal disk for boot,
firmware extraction and disaster recovery.

## Source identities

| Input | Exact identity | Use |
| --- | --- | --- |
| Linux psX documentation/patch project | [`886e35141787c26c2eb5df0558109d3ac35d38ad`](https://github.com/meerzulee/linux-psx/tree/886e35141787c26c2eb5df0558109d3ac35d38ad) | Current distribution-independent platform, memory, storage and hardware notes |
| Published psX beta2 | [`v7.2.11-psx-ps4-baikal-beta2`](https://github.com/meerzulee/linux-psx/releases/tag/v7.2.11-psx-ps4-baikal-beta2) | Frozen kernel, complete matching 41-module archive and corresponding patched source |
| Release recipe checkpoint | `c874f68db9287adb8f2a7b5d2d083ea000b27be9` | Publication provenance; not a claim the binary was built from clean HEAD |
| Historical native source base | `c8495a51e0bad4851015cd5d34ee61b2fde87e44` | Historical lineage, supplemented by the exact composed source archive |
| Upstream Linux | `a2de78ee6ed8bf8cd99d177c74865a6e8c3cb6ea`, Linux 7.2.11 | Stable upstream source behind the patched archive |
| PS4 loader | [`ArabPixel/ps4-linux-loader de22b91e58ecbb7151cb622047e2786f9a9b9965`](https://github.com/ArabPixel/ps4-linux-loader/tree/de22b91e58ecbb7151cb622047e2786f9a9b9965) | Firmware/southbridge detection, locally extracted GPU firmware, kernel handoff and 128/1024 MiB presets |

The source archive SHA256 is
`2b712654d47e675a4c4f2d8379bfa2e5e5e4135fae3c1124426d1f9ee38ab535`.
The frozen ZIP SHA256 is
`ff9d5fa620015706b1f98f1d12244df50b02390fe6bfe380331f7e5937a4639e`.
The loader source archive SHA256 is
`9d547a40725f4360c877b14d7cf63c82f19cad11ec6463d8f89c6473b17e0f77`.
These are immutable fetch hashes in `pkgs/ps4-platform/default.nix` and the
machine-readable `provenance.json`. Downloaded source/artifact identity was
checked during preparation. A source inspection or compilation is not a PS4
boot or memory-bandwidth result.

The kernel's GPLv2 notices and complete corresponding source remain available.
The loader's kexec code retains its BSD notices. The wrapper packages do not
redistribute firmware or a jailbreak exploit. The loader itself still needs
an already working, firmware-compatible privileged payload entrance.

## Hardware gate before the first console launch

This prepared kernel is **Baikal-derived**. The published beta2 has recorded
Slim/Baikal B1 results, including USB-root boot, graphics and ordered return to
Orbis. It is not qualified for every Slim. First-generation CUH-10xx/11xx
machines use Aeolia; they must not inherit a Baikal boot claim.

At the final attended Orbis pass, record the full CUH label, installed system
software version, existing exploit/HEN/payload entrance and the actual
southbridge. Do not update Orbis firmware to match a loader support table.
The psX DiagnostiX app's **Save console info** command can record southbridge,
firmware and Pro status to USB when a compatible GoldHEN environment is already
available. That information operation is distinct from launching its Linux
test. [Compatibility and identification](https://github.com/meerzulee/linux-psx/blob/886e35141787c26c2eb5df0558109d3ac35d38ad/manual/02-compatibility.md).

If the console is Aeolia, Belize or Belize 2, keep the prepared image and
Orbis intact and select/build the matching kernel line before launching it.
The same psX repository has a separate compile-tested `7.2-ps4` development
target carrying the rmux Aeolia/Belize lineage. It has no recorded boot on any
console, so it is a candidate to investigate, not an automatic universal
replacement. [Separate target](https://github.com/meerzulee/linux-psx/blob/886e35141787c26c2eb5df0558109d3ac35d38ad/targets/7.2-ps4.env).

## The Nix derivative

`pkgs.callPackage ./pkgs/ps4-platform { }` returns:

| Attribute | Output |
| --- | --- |
| `kernel` / `modulesTree` | `bzImage`, resolved `config`, `System.map`, all matching `lib/modules/7.2.11-psx-ps4-dummy2/` modules and build checksums |
| `referenceKernel` | Unchanged published beta2 kernel/config/modules for comparison, not the normal fleet kernel |
| `loader` | `payloads/linux-128mb.{elf,bin}` and `payloads/linux-1024mb.{elf,bin}`, built from the pinned source |
| `initramfs` | Self-contained static BusyBox `initramfs.cpio.gz`, with no store-path dependency |
| `bootFiles` | Exact paired FAT-root files, payloads, provenance and a separate 1024 MiB recovery set |
| `universalKernel` / `universalBootFiles` | Separately built Aeolia/Belize/Baikal comparison candidate and its own paired boot files; not a relabelled Baikal artifact |

The kernel rebuild uses the complete frozen psX patched source and its resolved
config. `fleet-network.config` deliberately enables netfilter, nftables,
iptables compatibility and TUN, because the published config disables
`CONFIG_NETFILTER` and `CONFIG_TUN`. The candidate has its own release name so
it cannot silently load modules from beta2. Compiler plugins and debug symbols
are disabled for the bounded build; fixed build timestamps/identity are
recorded. Those changes require their own physical boot qualification.

A generic-PC test of the actual labelled USB root reached NixOS stage 2 and
PID 1 systemd, exposing two real integration gaps: missing descriptor links
such as `/dev/fd/63`, and missing Btrfs POSIX ACL support used by journald.
The init now supplies NixOS's normal descriptor links and devpts permissions;
the `dummy2`/`universal2` kernels explicitly enable
`CONFIG_BTRFS_FS_POSIX_ACL=y`. Distinct v2 release names prevent the earlier
no-ACL kernel being paired with newer modules. This test exercises root/init
integration on a generic PC guest, not a PS4 GPU, southbridge or Orbis loader;
the completed rerun receipt governs its final result.

An explicit `kernelVariant="universal"` selects the separate
`7.2.11-psx-ps4-dummy-universal2` build. This starts from the clean pinned
upstream archive, applies the exact 176-patch `7.2-ps4` series from the pinned
psX project, then adds psX's separate native MTS autoload/open adapter. It
uses the general target's config, including built-in `sky2` for the older
southbridges, plus the same fleet network settings. Its source/config/module
identity remains separate from the Baikal-derived build. Neither the word
universal nor successful compilation is a physical support declaration.

The resolved Baikal candidate's real network options were inspected after
compilation: nftables, IPv4/IPv6 FIB/rejection, conntrack, marks, NAT,
compatibility and TUN are built in. This kernel has no `CONFIG_NFT_COUNTER`
or `CONFIG_NETFILTER_XT_MATCH_TCPUDP` symbol: `nft_counter.o` is part of
`nf_tables-objs`, and `xt_tcpudp.o` is selected by `NETFILTER_XTABLES`.
Legacy iptables filter/mangle/NAT tables require the separate legacy-table
gate and are deliberately unused by the fleet's native nftables paths.

With `boot.kernel.enable=false`, NixOS does not create its usual kernel module
tree automatically. The host explicitly supplies `system.modulesTree` from
this package and its `kernel-modules` system-output link. The whole module
tree belongs with the selected `bzImage`, including `psx_mts_net`; copying only
an Ethernet module would break the artifact contract. The native Ethernet
interface is `psx0`, so an `en*`-only DHCP rule is insufficient.
[psX artifact contract](https://github.com/meerzulee/linux-psx/blob/886e35141787c26c2eb5df0558109d3ac35d38ad/docs/ARTIFACTS.md),
[Ethernet lifecycle](https://github.com/meerzulee/linux-psx/blob/886e35141787c26c2eb5df0558109d3ac35d38ad/docs/ETHERNET.md).

## External-loader and firmware handoff

The FAT root contains `bzImage`, `initramfs.cpio.gz`, `bootargs.txt` and
`vram.txt`. `bootargs.txt` is one line under the loader's 511-byte complete
command-line limit. `boot.kernelParams` alone does not change this external
boot. The Btrfs Linux root label is `ps4-nixos`; FAT is `PS4BOOT`.

`libata.force=disable` disables libata devices globally in this external-root
boot, without guessing a SATA port number. USB-storage uses SCSI/USB and is
unaffected. The source's `ATA_QUIRK_DISABLE` branch disables devices before
normal block use; controller/link/IDENTIFY bring-up may still occur. This is
not a claim that the SATA controller performs no access at all. No initramfs
operation mounts or writes an Orbis partition.

The loader checks USB0, USB1 and then its internal boot-file paths. In the
exact pinned `main-aio.c`, those accesses are reads: no automatic copy to an
internal Orbis directory was found, despite an older README changelog entry.
An arbitrary newer loader must be re-inspected before inheriting that claim.
[File selection](https://github.com/ArabPixel/ps4-linux-loader/blob/de22b91e58ecbb7151cb622047e2786f9a9b9965/linux/main-aio.c#L375).

The loader extracts GPU firmware from the currently booting console and
appends a second cpio to the supplied initramfs. The precise names are
`lib/firmware/amdgpu/liverpool_{pfp,me,ce,mec,mec2,rlc,sdma,sdma1}.bin` for
Liverpool and `lib/firmware/edid/my_edid.bin`. This supports the built-in
amdgpu driver's early firmware requests without distributing Sony bytes.
The loader also appends a console HDD key; this init copies only the amdgpu
and EDID directories into `/run/ps4-firmware`, leaving that key in the
discarded initramfs. Never upload the appended archive or its key.
[Firmware extraction](https://github.com/ArabPixel/ps4-linux-loader/blob/de22b91e58ecbb7151cb622047e2786f9a9b9965/linux/ps4-kexec-common/firmware.c#L367).

The initramfs mounts devtmpfs/proc/sysfs and a small `/run`, waits up to 60
seconds for the explicit labelled root, proves USB ancestry, partition 2 and
a sibling FAT `PS4BOOT`, then mounts it and checks its NixOS marker. This
adapts Omarchy psX's early guard to the NixOS layout, with its MIT notice
preserved. It then moves those mounts
and executes the real `/sbin/init` bridge. The NixOS image supplies that
bridge into its selected generation. `firmware_class.path=/run/ps4-firmware`
keeps the runtime copy available. In the pinned NixOS stage 2, the existing
`/proc/1` skips redoing early mounts, so this `/run` is retained. Physical
firmware-load and repeat-boot checks remain required.

## Memory and compute settings

The candidate uses `vram.txt=128` and `ttm.pages_limit=1900544`. The former
changes the loader's fixed carveout from the one physical 8 GiB GDDR5 pool.
The latter is a total ceiling of 1,900,544 backing pages, or 7424 MiB at
4 KiB per page. This leaves 256 MiB of manager-accounting margin above a
7168 MiB user-buffer probe. It is not a 7.25 GiB reservation. The deployment aims to reclaim sufficient
system pages for unchanged Bonsai's approximately 6.72 GiB 16K model/state/KV
subtotal plus Linux and workspace; actual allocation and useful GPU bandwidth
must be measured separately.

The distinction matters: `amdgpu_gtt_mgr_new()` accounts the proposed resource
before testing total manager usage against its size, and `ttm_tt_populate()`
adds the requested backing pages before its global limit/shrink check. The
ceiling includes driver and other buffer objects, so an exact 7 GiB total
ceiling could reject a 7 GiB user buffer even when Bonsai's smaller real
working set fits. The extra 256 MiB is an implementation margin, not a model
precision change. A full allocation/touch test must first check actual
`MemAvailable` and retain at least 256 MiB of operator headroom beyond the
touched user allocation; the ceiling cannot promise physically free RAM.

The default TTM backing limit is approximately half ordinary RAM. Raising
that software limit does not prove a fast physical memory route, nor does a
successful allocation. `amdgpu.gttsize` is a deprecated separate override;
`amdgpu.gartsize` is an aperture size. Neither is the chosen backing-memory
control. Source memory/bandwidth qualification is preserved in the research
handoff and is not replaced by a boot claim.

Keep `amdgpu` and CIK enabled. Do **not** add `nomodeset` or
`amdgpu.modeset=0` merely because the machine is headless: inference needs a
working DRM render device and compute queues. `amdgpu.dc=0` retains the
existing PS4 display-bridge path while allowing an entirely headless userland.
No compositor, Vulkan swapchain, KFD, HIP or runtime OpenCL implementation is
needed by the direct libdrm/Garlic-style executor.

`recovery/gpu-1024MiB` holds the same candidate kernel and initramfs with
`vram.txt=1024`, isolating the smaller-carveout experiment without reverting
netfilter or changing module identity. It is a recovery candidate, not an
already witnessed PS4 boot. The untouched internal Orbis system is the
independent disaster fallback.

## Fleet update boundary

A NixOS activation can change the selected userspace generation and its module
tree without changing FAT's externally loaded `bzImage`. If a change includes
the platform kernel, update the matching external boot set deliberately and
retain both old kernel/modules and the old userspace closure until the new
boot passes. Merely activating a new generation does not establish that its
kernel or boot arguments ran. Conversely, a model plugin or ordinary service
change need not rebuild/rewrite the platform boot files when their identities
are unchanged. Keep the no-reboot fleet rule; a later attended boot is a
separate measurement.

## Unknowns and proposed defaults

- Exact borrowed Slim southbridge, firmware and payload entrance: record at
  the attended end-of-preparation UI pass, then select the matching bundle.
- Source build and prepared image are not hardware acceptance. Default: retain
  separate checks for USB-root boot, SSH, Tailscale, module identity, render
  device, firmware, actual memory budget and restart back into Orbis.
- Seven GiB GPU backing and native-like bandwidth are unmeasured. Default:
  preserve this boot's measured E820/MemTotal/VRAM/GTT data and test with the
  actual specialized inference runtime before describing Bonsai as qualified.
- Internal shrinking/writing is not qualified by psX. Default: boot Linux from
  the partitioned external USB and preserve every internal Orbis partition.
- The 1024 MiB recovery pair and frozen beta2 reference serve different
  purposes. Default: recovery keeps the new kernel and firewall; beta2 stays
  an explicitly selected comparison artifact.
