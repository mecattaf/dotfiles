{
  lib,
  stdenv,
  sherpa-onnx,
  nlohmann_json,
}:
stdenv.mkDerivation {
  pname = "sherpa-kws-fixture";
  version = "20260914";
  src = ./runner.cpp;
  dontUnpack = true;
  buildInputs = [
    sherpa-onnx
    nlohmann_json
  ];
  buildPhase = ''
    $CXX -O2 -std=c++17 -Wall -Wextra -x c++ "$src" -lsherpa-onnx-c-api -o sherpa-kws-fixture
  '';
  installPhase = ''
    mkdir -p $out/bin
    cp sherpa-kws-fixture $out/bin/
  '';
  meta.license = lib.licenses.asl20;
}
