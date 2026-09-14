{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  ninja,
  pkg-config,
  vulkan-headers,
  vulkan-loader,
  shaderc,
}:
let
  ggml = fetchFromGitHub {
    owner = "ServeurpersoCom";
    repo = "ggml";
    rev = "77cdef82aad64f141164fac02076e36d5848474c";
    hash = "sha256-Vsg66VMSQ8V5cLytaBGQzEWeXpqlFQsuHAi4z0V1Ino=";
  };
in
stdenv.mkDerivation {
  pname = "qwentts";
  version = "0-unstable-2026-09-14";
  src = fetchFromGitHub {
    owner = "ServeurpersoCom";
    repo = "qwentts.cpp";
    rev = "71ad93d591a2811f35db77e27c02acba091c9e9b";
    hash = "sha256-zolkBFlJbh9Ve4wvXfp5hP/82V9iaH8Ze6Fq+ATsFR8=";
  };
  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
    shaderc
  ];
  buildInputs = [
    vulkan-headers
    vulkan-loader
  ];
  postUnpack = ''
    cp -R ${ggml}/. "$sourceRoot/ggml/"
    chmod -R u+w "$sourceRoot/ggml"
  '';
  postPatch = ''
    substituteInPlace tools/version.cmake \
      --replace-fail 'set(GIT_HASH "unknown")' 'set(GIT_HASH "71ad93d")'
  '';
  cmakeFlags = [
    "-DGGML_VULKAN=ON"
    "-DGGML_NATIVE=OFF"
    "-DGGML_BACKEND_DL=OFF"
    "-DBUILD_SHARED_LIBS=OFF"
    "-DGGML_BUILD_TESTS=OFF"
    "-DGGML_BUILD_EXAMPLES=OFF"
  ];
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    ./test-abi-c
    # Upstream's CLI returns 1 for --help (same parser path as bad argv).
    status=0
    ./qwen-tts --help >cli-help.txt 2>&1 || status=$?
    test "$status" = 1
    grep -q 'Usage:' cli-help.txt
    ./tts-server --help
    runHook postCheck
  '';
  installPhase = ''
    runHook preInstall
    install -Dm755 qwen-tts "$out/bin/qwen-tts"
    install -Dm755 qwen-codec "$out/bin/qwen-codec"
    install -Dm755 tts-server "$out/bin/qwen-tts-server"
    runHook postInstall
  '';
  meta = {
    description = "Qwen3 TTS with Vulkan streaming synthesis and voice enrollment";
    homepage = "https://github.com/ServeurpersoCom/qwentts.cpp";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
  };
}
