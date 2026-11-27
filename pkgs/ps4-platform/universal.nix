{
  lib,
  stdenv,
  fetchurl,
  bc,
  bison,
  flex,
  perl,
  python3,
  pkg-config,
  openssl,
  elfutils,
  kmod,
  gitMinimal,
}:
let
  release = "7.2.11-psx-ps4-dummy-universal3";
  psxInputs = fetchurl {
    url = "https://github.com/meerzulee/linux-psx/archive/886e35141787c26c2eb5df0558109d3ac35d38ad.tar.gz";
    sha256 = "4a2879c99507c9e7034f1b1239c887e6a23dda2c0f5dd98537932d7e2f1c17d2";
  };
in
stdenv.mkDerivation {
  pname = "linux-psx-ps4-dummy-universal";
  version = release;
  # This is CLEAN upstream, not the Baikal release archive relabelled.
  src = fetchurl {
    url = "https://github.com/gregkh/linux/archive/a2de78ee6ed8bf8cd99d177c74865a6e8c3cb6ea.tar.gz";
    sha256 = "ca5258ea8a597f646d42cdb4eacd37d67d4131129f3b6193514cf07b09983caa";
  };
  nativeBuildInputs = [
    bc
    bison
    flex
    perl
    python3
    pkg-config
    kmod
    gitMinimal
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
  patchPhase = ''
    runHook prePatch
    mkdir .psx-inputs
    tar -xf ${psxInputs} --strip-components=1 -C .psx-inputs
    printf '%s  %s\n' \
      b883fdeec984f9b362eed32481e5768f4a506de4de1dee36ce59d613ec04ee30 \
      .psx-inputs/platforms/ps4/patches/7.2-ps4/series | sha256sum -c -
    patch_count=0
    while IFS= read -r entry; do
      case "$entry" in ""|'#'*) continue ;; esac
      patch_file=".psx-inputs/platforms/ps4/patches/7.2-ps4/$entry"
      git apply --check "$patch_file"
      git apply "$patch_file"
      patch_count=$((patch_count + 1))
    done < .psx-inputs/platforms/ps4/patches/7.2-ps4/series
    test "$patch_count" = 176
    # The comparison target includes MTS2, but omits the separate native
    # autoload/open patch. Apply that exact psX adapter for a normal wired
    # boot on Baikal too; Aeolia/Belize retain their built-in sky2 path.
    autoload_patch=.psx-inputs/platforms/ps4/patches/6.18-baikal-mts2/0700-network-mts/0002-net-ps4-mts-native-autoload.patch
    printf '%s  %s\n' e6e799c9d82618f1c92abfaa801cb49613feb4d4f4f033bdd79e5d5f3a0ee9b3 "$autoload_patch" | sha256sum -c -
    git apply --check "$autoload_patch"
    git apply "$autoload_patch"
    runHook postPatch
  '';
  configurePhase = ''
    runHook preConfigure
    patchShebangs scripts
    cp .psx-inputs/platforms/ps4/config/7.2-psx-ps4.config .config
    cp .config .config.psx-reference
    scripts/kconfig/merge_config.sh -m .config ${./fleet-network.config}
    scripts/config --set-str LOCALVERSION "-psx-ps4-dummy-universal3"
    scripts/config --disable LOCALVERSION_AUTO
    scripts/config --disable GCC_PLUGINS
    scripts/config --disable DEBUG_INFO
    scripts/config --enable DEBUG_INFO_NONE
    scripts/config --set-str SYSTEM_TRUSTED_KEYS ""
    scripts/config --set-str SYSTEM_REVOCATION_KEYS ""
    make ARCH=x86_64 CC=gcc HOSTCC=gcc olddefconfig
    for option in X86_PS4 DRM_AMDGPU DRM_AMDGPU_CIK BTRFS_FS BTRFS_FS_POSIX_ACL DEVTMPFS SKY2; do
      grep -qx "CONFIG_$option=y" .config || exit 1
    done
    grep -qx 'CONFIG_PS4_MTS=m' .config
    grep -qx 'CONFIG_EXTRA_FIRMWARE=""' .config
    while IFS= read -r setting; do
      case "$setting" in CONFIG_*=*) grep -Fqx "$setting" .config || {
        echo "Required fleet setting did not resolve: $setting" >&2; exit 1;
      } ;; esac
    done < ${./fleet-network.config}
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
    cp .psx-inputs/provenance/7.2-ps4.json "$out/psx-target-provenance.json"
    cp .psx-inputs/platforms/ps4/patches/7.2-ps4/series "$out/psx-series"
    printf '%s\n' ${lib.escapeShellArg release} > "$out/kernel-release"
    (cd "$out"; sha256sum bzImage config System.map > SHA256SUMS)
    runHook postInstall
  '';
  dontStrip = true;
  dontPatchELF = true;
  passthru = {
    modDirVersion = release;
    kernelRelease = release;
    supportsNetfilter = true;
    hardwareScope = "Aeolia/Belize/Baikal source comparison candidate; no physical boot qualification";
    psxCommit = "886e35141787c26c2eb5df0558109d3ac35d38ad";
    upstreamCommit = "a2de78ee6ed8bf8cd99d177c74865a6e8c3cb6ea";
    seriesPatchCount = 176;
    nativeEthernetAutoloadAdaptation = "e6e799c9d82618f1c92abfaa801cb49613feb4d4f4f033bdd79e5d5f3a0ee9b3";
  };
  meta = {
    description = "Separate Linux psX PS4 comparison kernel for original/Slim southbridge selection";
    homepage = "https://github.com/meerzulee/linux-psx";
    license = lib.licenses.gpl2Only;
    platforms = [ "x86_64-linux" ];
  };
}
