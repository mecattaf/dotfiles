{
  lib,
  stdenv,
  pkg-config,
  libdrm,
  python3,
}:
stdenv.mkDerivation {
  pname = "ps4-memory-probe";
  version = "0.1.0";
  src = lib.cleanSource ./.;
  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ libdrm ];
  dontConfigure = true;
  buildPhase = ''
    runHook preBuild
    $CC -std=c11 -O2 -Wall -Wextra -Werror \
      -DPROBE_SOURCE_SHA256='"${builtins.hashFile "sha256" ./memory-probe.c}"' \
      $(pkg-config --cflags libdrm_amdgpu libdrm) memory-probe.c \
      -o ps4-memory-probe $(pkg-config --libs libdrm_amdgpu libdrm)
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    install -Dm755 ps4-memory-probe "$out/bin/ps4-memory-probe"
    runHook postInstall
  '';
  doInstallCheck = true;
  nativeInstallCheckInputs = [ python3 ];
  installCheckPhase = ''
    runHook preInstallCheck
    python3 ${./test-cli.py} "$out/bin/ps4-memory-probe" ${./memory-probe.c}
    runHook postInstallCheck
  '';
  meta = {
    description = "Explicit AMD render-node GTT allocation, GPU VA and CPU-page qualification";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "ps4-memory-probe";
  };
}
