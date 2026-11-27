{
  lib,
  mesa,
  fetchurl,
}:
let
  # Reuse nixpkgs' build dependencies and Nix fixup machinery, with an isolated
  # PS4 source/driver selection. No other fleet host sees this derivation.
  base = mesa.override {
    galliumDrivers = [ "radeonsi" ];
    vulkanDrivers = [ "amd" ];
    vulkanLayers = [ ];
    withValgrind = false;
  };
  pins = lib.importJSON ./sources.json;
  isLlvm =
    p:
    lib.any (name: lib.hasInfix name (lib.getName p)) [
      "llvm"
      "clang"
      "libclc"
    ];
  isRust =
    p:
    lib.any (name: lib.hasInfix name (lib.getName p)) [
      "rustc"
      "rust-bindgen"
      "rust-cbindgen"
    ];
in
base.overrideAttrs (old: {
  pname = "mesa-ps4";
  version = pins.upstream.version;
  src = fetchurl {
    url = pins.upstream.url;
    sha256 = pins.upstream.sha256;
  };
  patches = map (pin: ./. + "/${pin.path}") pins.patches;
  # stdenv adds the debug output for separateDebugInfo itself.
  outputs = [ "out" ];
  preConfigure = "";
  env = { };
  buildInputs = lib.filter (p: !(isLlvm p)) old.buildInputs;
  nativeBuildInputs = lib.filter (p: !(isRust p)) old.nativeBuildInputs;
  # These are the psX donor's selected ACO driver features, with Nix-native
  # output paths. Do not inherit nixpkgs' OpenCL/Rust/cross-driver defaults.
  mesonBuildType = "release";
  # psX upstream Meson defaults: optional features stay optional. Nix
  # otherwise forces every auto dependency on, including unselected drivers.
  mesonAutoFeatures = "auto";
  mesonFlags = [
    "-Db_ndebug=false"
    "-Db_lto=false"
    "-Dplatforms=x11,wayland"
    "-Dgallium-drivers=radeonsi"
    "-Dvulkan-drivers=amd"
    "-Dvulkan-layers="
    "-Dglx=dri"
    "-Degl=enabled"
    "-Dgbm=enabled"
    "-Dlibgbm-external=false"
    "-Dglvnd=enabled"
    "-Dgles1=disabled"
    "-Dgles2=enabled"
    "-Dllvm=disabled"
    "-Damd-use-llvm=false"
    "-Ddraw-use-llvm=false"
    "-Damdgpu-virtio=false"
    "-Dgallium-va=enabled"
    "-Dvideo-codecs=h264dec"
    "-Dgallium-rusticl=false"
    "-Dmicrosoft-clc=disabled"
    "-Dgallium-mediafoundation=disabled"
    "-Dandroid-libbacktrace=disabled"
    "-Dteflon=false"
    "-Dvalgrind=disabled"
    "-Dintel-rt=disabled"
    "-Dbuild-tests=true"
    "-Dbuild-radv-tests=false"
    "-Dbuild-aco-tests=false"
    "-Dglx-read-only-text=true"
    "-Dtools="
  ];
  postPatch = ''
    patchShebangs .
  '';
  # This runs CPU source/unit tests only. It does not claim PS4 render, video,
  # Vulkan or inference acceptance and does not open a GPU during the build.
  doCheck = true;
  # Retain Meson's per-test time limits rather than Nix's unlimited default.
  dontAddTimeoutMultiplier = true;
  postInstall = ''
    mkdir -p "$out/share/doc/mesa-ps4"
    cp ${./sources.json} "$out/share/doc/mesa-ps4/sources.json"
    cp ${./patches}/* "$out/share/doc/mesa-ps4/"
    cp docs/license.rst "$out/share/doc/mesa-ps4/upstream-license.rst"
    cp -R licenses "$out/share/doc/mesa-ps4/licenses"
    test -f "$out/lib/libvulkan_radeon.so"
    test -e "$out/lib/dri/radeonsi_dri.so"
    test -e "$out/lib/libgbm.so.1"
  '';
  postFixup = ''
    for manifest in "$out"/share/glvnd/egl_vendor.d/*.json; do
      substituteInPlace "$manifest" --replace-fail '"libEGL_' '"'"$out/lib/libEGL_"
    done
    for manifest in "$out"/share/vulkan/icd.d/*.json; do
      substituteInPlace "$manifest" \
        --replace '"libvulkan_radeon.so"' '"'"$out/lib/libvulkan_radeon.so"'"'
    done
    rm -f "$out/lib/pkgconfig/dri.pc"
  '';
  passthru = (old.passthru or { }) // {
    ps4Lineage = {
      source = "meerzulee/linux-psx";
      revision = "886e35141787c26c2eb5df0558109d3ac35d38ad";
      candidate = pins.candidate;
      hardwareAccepted = false;
      runtime = "ACO radeonsi/RADV, no LLVM/OpenCL runtime";
    };
  };
  meta = old.meta // {
    description = "Liverpool/Gladius Mesa psX candidate, ACO OpenGL/Vulkan drivers";
    platforms = [ "x86_64-linux" ];
    outputsToInstall = [ "out" ];
  };
})
