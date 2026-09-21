{
  lib,
  rustPlatform,
  makeWrapper,
  python3,
  onnxruntime,
}:
let
  runtime = onnxruntime.override { rocmSupport = true; };
in
rustPlatform.buildRustPackage {
  pname = "parakeet-service";
  version = "0.1.0";
  src = lib.cleanSource ./.;
  cargoLock.lockFile = ./Cargo.lock;
  nativeBuildInputs = [ makeWrapper ];
  postCheck = ''
    ${python3}/bin/python3 ${../../tests/parakeet-service/test_transport.py} transport.py
  '';
  postInstall = ''
    mkdir -p $out/lib
    cp transport.py $out/lib/
    wrapProgram $out/bin/parakeet-service-engine \
      --set ORT_DYLIB_PATH ${runtime}/lib/libonnxruntime.so \
      --prefix LD_LIBRARY_PATH : ${runtime}/lib
    makeWrapper ${python3}/bin/python3 $out/bin/parakeet-service \
      --add-flags $out/lib/transport.py \
      --prefix PATH : $out/bin
    makeWrapper ${python3}/bin/python3 $out/bin/parakeet-relay \
      --add-flags "$out/lib/transport.py relay"
  '';
  meta = {
    description = "Socket-activated coordinator Parakeet TDT with private framed audio transport";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
  };
}
