{
  lib,
  stdenv,
  stdenvNoCC,
  fetchurl,
  runCommand,
  callPackage,
  writeText,
  busybox,
  cpio,
  gzip,
  unzip,
  zstd,
  bc,
  bison,
  flex,
  perl,
  python3,
  pkg-config,
  openssl,
  elfutils,
  kmod,
  yasm,
  rootLabel ? "ps4-nixos",
  gpuBackingLimitMiB ? 7168,
  vramMiB ? 128,
  kernelVariant ? "baikal",
}:
let
  release = "7.2.11-psx-ps4-dummy1";
  referenceRelease = "7.2.11-psx-ps4-baikal-uvd-runtime-dev6";
  releaseBase = "https://github.com/meerzulee/linux-psx/releases/download/v7.2.11-psx-ps4-baikal-beta2";
  runtimeArchive = fetchurl {
    url = "${releaseBase}/kernel-${referenceRelease}.zip";
    sha256 = "ff9d5fa620015706b1f98f1d12244df50b02390fe6bfe380331f7e5937a4639e";
  };
  sourceArchive = fetchurl {
    url = "${releaseBase}/source-${referenceRelease}.tar.zst";
    sha256 = "2b712654d47e675a4c4f2d8379bfa2e5e5e4135fae3c1124426d1f9ee38ab535";
  };
  referenceKernel = stdenvNoCC.mkDerivation {
    pname = "linux-psx-baikal-reference";
    version = referenceRelease;
    src = runtimeArchive;
    nativeBuildInputs = [
      unzip
      zstd
    ];
    dontUnpack = true;
    dontConfigure = true;
    dontBuild = true;
    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      unzip -q "$src" -d reference
      (cd reference; sha256sum -c SHA256SUMS)
      cp reference/bzImage reference/config reference/System.map reference/artifacts.json "$out/"
      tar --zstd -xf reference/modules-${referenceRelease}.tar.zst -C "$out"
      cp reference/COPYING reference/CREDITS.md "$out/"
      runHook postInstall
    '';
    dontStrip = true;
    dontPatchELF = true;
    passthru = {
      modDirVersion = referenceRelease;
      kernelRelease = referenceRelease;
      inherit sourceArchive;
      supportsNetfilter = false;
      hardwareScope = "Recorded Baikal B1 Slim only; not all Slims or original PS4s";
    };
    meta = {
      description = "Frozen Linux psX beta2 kernel and complete matching modules, recovery/reference only";
      homepage = "https://github.com/meerzulee/linux-psx";
      license = lib.licenses.gpl2Only;
      platforms = [ "x86_64-linux" ];
    };
  };
  baikalKernel = stdenv.mkDerivation {
    pname = "linux-psx-ps4-dummy";
    version = release;
    src = sourceArchive;
    nativeBuildInputs = [
      zstd
      bc
      bison
      flex
      perl
      python3
      pkg-config
      kmod
    ];
    buildInputs = [
      openssl
      elfutils
    ];
    hardeningDisable = [ "all" ];
    enableParallelBuilding = true;
    KBUILD_BUILD_TIMESTAMP = "2026-11-27 00:00:00 UTC";
    KBUILD_BUILD_USER = "nix";
    KBUILD_BUILD_HOST = "ps4-dummy-builder";
    KBUILD_BUILD_VERSION = "1";
    SOURCE_DATE_EPOCH = "1795737600";
    configurePhase = ''
      runHook preConfigure
      # The archive is the complete patched source behind the frozen psX
      # release, including its resolved config. No network/git in the build.
      patchShebangs scripts
      cp .config .config.psx-reference
      scripts/kconfig/merge_config.sh -m .config ${./fleet-network.config}
      scripts/config --set-str LOCALVERSION "-psx-ps4-dummy1"
      scripts/config --disable LOCALVERSION_AUTO
      scripts/config --disable GCC_PLUGINS
      scripts/config --disable DEBUG_INFO
      scripts/config --enable DEBUG_INFO_NONE
      scripts/config --set-str SYSTEM_TRUSTED_KEYS ""
      scripts/config --set-str SYSTEM_REVOCATION_KEYS ""
      make ARCH=x86_64 CC=gcc HOSTCC=gcc olddefconfig
      for option in X86_PS4 DRM_AMDGPU DRM_AMDGPU_CIK BTRFS_FS DEVTMPFS \
        NETFILTER NF_CONNTRACK NF_TABLES NF_TABLES_INET NFT_CT TUN; do
        grep -qx "CONFIG_$option=y" .config || {
          echo "Required PS4/fleet kernel option did not resolve: $option" >&2
          exit 1
        }
      done
      grep -qx 'CONFIG_EXTRA_FIRMWARE=""' .config
      test "$(make -s ARCH=x86_64 kernelrelease)" = ${lib.escapeShellArg release}
      runHook postConfigure
    '';
    buildPhase = ''
      runHook preBuild
      make -j"$NIX_BUILD_CORES" ARCH=x86_64 CC=gcc HOSTCC=gcc bzImage modules
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      make ARCH=x86_64 INSTALL_MOD_PATH="$out" DEPMOD=true modules_install
      rm -f "$out/lib/modules/${release}/build" "$out/lib/modules/${release}/source"
      cp arch/x86/boot/bzImage "$out/bzImage"
      cp .config "$out/config"
      cp .config.psx-reference "$out/reference.config"
      cp System.map COPYING "$out/"
      cp ${./fleet-network.config} "$out/fleet-network.config"
      printf '%s\n' ${lib.escapeShellArg release} > "$out/kernel-release"
      (cd "$out"; sha256sum bzImage config System.map > SHA256SUMS)
      runHook postInstall
    '';
    dontStrip = true;
    dontPatchELF = true;
    passthru = {
      modDirVersion = release;
      kernelRelease = release;
      inherit sourceArchive;
      supportsNetfilter = true;
      hardwareScope = "Baikal-derived build candidate; physical boot qualification required";
    };
    meta = {
      description = "Linux psX 7.2.11 PS4 candidate with nftables, TUN and matched modules";
      homepage = "https://github.com/meerzulee/linux-psx";
      license = lib.licenses.gpl2Only;
      platforms = [ "x86_64-linux" ];
    };
  };
  universalKernel = callPackage ./universal.nix { };
  kernel = if kernelVariant == "baikal" then baikalKernel else universalKernel;
  loader = stdenv.mkDerivation {
    pname = "ps4-linux-loader";
    version = "25.3-de22b91";
    src = fetchurl {
      url = "https://github.com/ArabPixel/ps4-linux-loader/archive/de22b91e58ecbb7151cb622047e2786f9a9b9965.tar.gz";
      sha256 = "9d547a40725f4360c877b14d7cf63c82f19cad11ec6463d8f89c6473b17e0f77";
    };
    nativeBuildInputs = [
      python3
      yasm
    ];
    hardeningDisable = [ "all" ];
    dontConfigure = true;
    buildPhase = ''
      runHook preBuild
      make -C linux -j"$NIX_BUILD_CORES" payloads/linux-128mb.elf payloads/linux-1024mb.elf
      runHook postBuild
    '';
    installPhase = ''
      mkdir -p "$out/payloads" "$out/share/doc/ps4-linux-loader"
      cp linux/payloads/linux-128mb.elf linux/payloads/linux-1024mb.elf "$out/payloads/"
      cp README.md "$out/share/doc/ps4-linux-loader/"
      cp linux/ps4-kexec-common/LICENSE "$out/share/doc/ps4-linux-loader/kexec-LICENSE"
    '';
    dontStrip = true;
    dontPatchELF = true;
    meta = {
      description = "Pinned PS4 loader, firmware-extracting kexec, 128/1024 MiB presets";
      homepage = "https://github.com/ArabPixel/ps4-linux-loader";
      license = lib.licenses.bsd2;
      platforms = [ "x86_64-linux" ];
    };
  };
  initramfs =
    runCommand "ps4-nixos-initramfs"
      {
        nativeBuildInputs = [
          cpio
          gzip
        ];
        passthru = { inherit rootLabel; };
      }
      ''
        mkdir -p root/bin root/sbin root/proc root/sys root/dev root/run root/newroot root/lib/firmware
        cp ${busybox.override { enableStatic = true; }}/bin/busybox root/bin/busybox
        for applet in $(root/bin/busybox --list); do
          ln -s busybox "root/bin/$applet" || true
        done
        cp ${./init} root/init
        mkdir -p root/licenses
        cp ${./LICENSE.omarchy-psx} root/licenses/omarchy-psx-MIT
        chmod 0755 root/init
        # cpio --reproducible normalizes inode/device fields, not mtimes.
        find root -depth -exec touch -h -d '@1795737600' {} +
        mkdir -p "$out"
        (cd root; find . -print0 | LC_ALL=C sort -z | cpio --null -o --format=newc --owner=0:0 --reproducible | gzip -n -9) > "$out/initramfs.cpio.gz"
      '';
  commandLine = lib.concatStringsSep " " [
    "root=LABEL=${rootLabel}"
    "rootfstype=btrfs"
    "rootwait"
    "rw"
    "pci=nocrs"
    "intremap=off"
    "amdgpu.dc=0"
    "amdgpu.cik_support=1"
    "radeon.cik_support=0"
    "ttm.pages_limit=${toString (gpuBackingLimitMiB * 256)}"
    "libata.force=disable"
    "firmware_class.path=/run/ps4-firmware"
    "systemd.gpt_auto=0"
    "console=tty0"
  ];
  makeBootFiles =
    profile: selectedKernel:
    runCommand "ps4-nixos-${profile}-boot-files"
      {
        passthru = {
          inherit
            commandLine
            rootLabel
            vramMiB
            gpuBackingLimitMiB
            initramfs
            loader
            ;
          kernel = selectedKernel;
        };
      }
      ''
        mkdir -p "$out/payloads" "$out/recovery/gpu-1024MiB"
        cp ${selectedKernel}/bzImage "$out/bzImage"
        cp ${initramfs}/initramfs.cpio.gz "$out/initramfs.cpio.gz"
        printf '%s\n' ${lib.escapeShellArg commandLine} > "$out/bootargs.txt"
        test "$(wc -c < "$out/bootargs.txt")" -le 511
        printf '%s\n' ${toString vramMiB} > "$out/vram.txt"
        cp ${loader}/payloads/*.elf "$out/payloads/"
        # Recovery varies one platform variable, the fixed VRAM carveout. It
        # retains the current kernel/config/modules and normal firewall support.
        cp ${selectedKernel}/bzImage "$out/recovery/gpu-1024MiB/bzImage"
        cp ${initramfs}/initramfs.cpio.gz "$out/recovery/gpu-1024MiB/initramfs.cpio.gz"
        cp "$out/bootargs.txt" "$out/recovery/gpu-1024MiB/bootargs.txt"
        printf '1024\n' > "$out/recovery/gpu-1024MiB/vram.txt"
        cp ${
          writeText "ps4-${profile}-provenance.json" (
            builtins.toJSON (
              (builtins.fromJSON (builtins.readFile ./provenance.json))
              // {
                selected_profile = profile;
                candidate_release = selectedKernel.kernelRelease;
                hardware_scope = selectedKernel.hardwareScope;
                candidate_source =
                  if profile == "baikal" then
                    {
                      kind = "complete-patched-psx-beta2-source";
                      sha256 = "2b712654d47e675a4c4f2d8379bfa2e5e5e4135fae3c1124426d1f9ee38ab535";
                    }
                  else
                    {
                      kind = "clean-upstream-plus-pinned-psx-7.2-ps4-series";
                      upstream_commit = "a2de78ee6ed8bf8cd99d177c74865a6e8c3cb6ea";
                      psx_commit = "886e35141787c26c2eb5df0558109d3ac35d38ad";
                      series_patches = 176;
                      native_mts_autoload_adaptation = "e6e799c9d82618f1c92abfaa801cb49613feb4d4f4f033bdd79e5d5f3a0ee9b3";
                      hardware_boot_qualified = false;
                    };
              }
            )
          )
        } "$out/platform-provenance.json"
        cp ${./LICENSE.omarchy-psx} "$out/LICENSE.omarchy-psx"
        (cd "$out"; find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)
      '';
  bootFiles = makeBootFiles kernelVariant kernel;
  universalBootFiles = makeBootFiles "universal" universalKernel;
  baikalBootFiles = makeBootFiles "baikal" baikalKernel;
in
assert lib.assertMsg (builtins.elem kernelVariant [
  "baikal"
  "universal"
]) "PS4 kernelVariant must be baikal or universal";
assert lib.assertMsg (
  builtins.match "[A-Za-z0-9_-]+" rootLabel != null
) "PS4 root label must contain only letters, digits, underscore and hyphen";
assert lib.assertMsg (builtins.elem vramMiB [
  32
  64
  128
  256
  512
  1024
]) "PS4 VRAM must be an explicit validated power-of-two candidate";
assert lib.assertMsg (
  gpuBackingLimitMiB > 0 && gpuBackingLimitMiB <= 7168
) "PS4 backing limit exceeds the planned 7 GiB budget";
{
  inherit
    kernel
    baikalKernel
    universalKernel
    referenceKernel
    loader
    initramfs
    bootFiles
    baikalBootFiles
    universalBootFiles
    runtimeArchive
    commandLine
    ;
  sourceArchive = kernel.sourceArchive or kernel.src;
  referenceSourceArchive = sourceArchive;
  modulesTree = kernel;
}
