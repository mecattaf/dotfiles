{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  ninja,
  pkg-config,
  shaderc,
  vulkan-headers,
  vulkan-loader,
}:
let
  ggml = fetchFromGitHub {
    owner = "ggml-org";
    repo = "ggml";
    rev = "d4fcfe88a8bcf5c9840be14be6c2fbf1f5b3b2db";
    hash = "sha256-IUvCGj3hdc2R4rgNE8q11+11XHwVJUyOPg4ItLhmxAc=";
  };
in
stdenv.mkDerivation {
  pname = "qwen3-tts-khimaros";
  version = "0-unstable-2026-06-16";
  src = fetchFromGitHub {
    owner = "khimaros";
    repo = "qwen3-tts.cpp";
    rev = "0c8b2ba0e7c57a2741852f4305a92996258a71a0";
    hash = "sha256-W+WIe4uXbmv8GgpMBZgRWBmYUXqz7Q+lw2Me1941WQg=";
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
    substituteInPlace CMakeLists.txt --replace-fail ' -march=native' ""
  '';
  cmakeFlags = [
    "-DGGML_VULKAN=ON"
    "-DGGML_NATIVE=OFF"
    "-DGGML_BACKEND_DL=OFF"
    "-DBUILD_SHARED_LIBS=OFF"
    "-DGGML_BUILD_TESTS=OFF"
    "-DGGML_BUILD_EXAMPLES=OFF"
    # Audition CLI: avoid upstream configure-time network FetchContent.
    "-DQWEN3_TTS_SERVER=OFF"
    "-DQWEN3_TTS_COREML=OFF"
  ];
  doCheck = true;
  checkPhase = ''
    ./qwen3-tts-cli --help
  '';
  installPhase = ''
    install -Dm755 qwen3-tts-cli "$out/bin/qwen3-tts-khimaros"
  '';
  meta = {
    description = "Independent Qwen3 TTS Vulkan CLI for matched voice auditions";
    homepage = "https://github.com/khimaros/qwen3-tts.cpp";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
  };
}
