# asr-rs — local streaming speech-to-text daemon (dual-Parakeet, Wayland/Niri).
# https://github.com/mecattaf/asr-rs
#
# The `ort` crate normally downloads a prebuilt static onnxruntime at build
# time, which the sandbox forbids. We fetch the exact same archive pyke's CDN
# serves (raw LZMA2 stream containing a ustar tar with libonnxruntime.a) as a
# fixed-output derivation and hand it to ort via ORT_LIB_LOCATION — producing
# a byte-equivalent link to the upstream-verified build.
{
  lib,
  rustPlatform,
  fetchFromGitHub,
  fetchurl,
  runCommand,
  python3,
  pkg-config,
  alsa-lib,
  openssl,
  makeWrapper,
  wtype,
  wl-clipboard,
}:
let
  # Keep in sync with ort-sys's build/download/dist.txt for the pinned ort
  # version (2.0.0-rc.12 -> ms@1.24.2, target x86_64-unknown-linux-gnu, CPU EP).
  ortArchive = fetchurl {
    url = "https://cdn.pyke.io/0/pyke:ort-rs/ms@1.24.2/x86_64-unknown-linux-gnu.tar.lzma2";
    hash = "sha256-rMHLp5wzdZTq0diMpyUWFHqmAFTIQhe1M5mjHKpbpnE=";
  };
  ortLib = runCommand "onnxruntime-static-1.24.2" { nativeBuildInputs = [ python3 ]; } ''
    mkdir -p $out
    python3 - <<'PY'
    import io, lzma, os, tarfile
    raw = open("${ortArchive}", "rb").read()
    tar = lzma.decompress(raw, format=lzma.FORMAT_RAW,
                          filters=[{"id": lzma.FILTER_LZMA2, "preset": 9}])
    tarfile.open(fileobj=io.BytesIO(tar)).extractall(os.environ["out"])
    PY
  '';
in
rustPlatform.buildRustPackage rec {
  pname = "asr-rs";
  version = "0.2.0";

  src = fetchFromGitHub {
    owner = "mecattaf";
    repo = "asr-rs";
    rev = "54a415d214b0fa1c3856883d94704baa2510262e";
    hash = "sha256-3d8nw3GubIPn8heGq0qKATVZ0trscHKDRCSw2DbZuXg=";
  };

  cargoHash = "sha256-oPzj6+hbpf5j5Qk8wSkJVAt6TJFmsT7X2iXQW/lad0w=";

  nativeBuildInputs = [
    pkg-config
    makeWrapper
  ];
  buildInputs = [
    alsa-lib
    openssl
  ];

  # Static onnxruntime from the FOD above; no network in the ort build script.
  env.ORT_LIB_LOCATION = ortLib;

  # The daemon shells out for injection; make sure the chain is always there
  # even if the host profile changes (niri IPC + playerctl/pw-play degrade
  # gracefully and stay host-provided).
  postInstall = ''
    wrapProgram $out/bin/asr-rs \
      --prefix PATH : ${
        lib.makeBinPath [
          wtype
          wl-clipboard
        ]
      }
  '';

  meta = {
    description = "Fully-local dual-Parakeet streaming STT daemon for Wayland/Niri (EOU live preview + TDT finalize), with tailnet compute offload";
    homepage = "https://github.com/mecattaf/asr-rs";
    license = lib.licenses.mit;
    mainProgram = "asr-rs";
    platforms = [ "x86_64-linux" ];
  };
}
