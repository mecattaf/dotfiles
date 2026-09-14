{ pkgs }:
pkgs.stdenvNoCC.mkDerivation {
  pname = "intel-npu-compiler-isolated";
  version = "1.35.0";
  src = pkgs.fetchurl {
    url = "https://github.com/intel/linux-npu-driver/releases/download/v1.35.0/linux-npu-driver-v1.35.0.20260722-29947505341-ubuntu2404.tar.gz";
    hash = "sha256-OYND5T/axgI60IVu+Iu2ARseEkR6ESvlXoXifvf5bGY=";
  };
  nativeBuildInputs = [
    pkgs.dpkg
    pkgs.autoPatchelfHook
  ];
  buildInputs = [
    pkgs.stdenv.cc.cc.lib
    pkgs.zlib
    pkgs.zstd
    pkgs.onetbb
  ];
  sourceRoot = ".";
  unpackPhase = ''
    tar -xf $src
    dpkg-deb -x intel-driver-compiler-npu_*.deb unpacked
  '';
  installPhase = ''
    mkdir -p $out/lib $out/share
    cp -a unpacked/usr/lib/x86_64-linux-gnu/. $out/lib/
    if test -d unpacked/usr/share; then cp -a unpacked/usr/share/. $out/share/; fi
  '';
}
