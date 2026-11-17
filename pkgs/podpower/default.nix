{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  dbus,
}:
rustPlatform.buildRustPackage {
  pname = "podpower";
  version = "0.1.1-unstable-2026-11-17";
  src = fetchFromGitHub {
    owner = "t4t5";
    repo = "podpower";
    rev = "58202c955851f4517dda13c3c19bf29c21b2b828";
    hash = "sha256-Q7SQaQbxhND0PX6ekOZeebw98knvE7GNXhNGpgTubrI=";
  };
  cargoLock.lockFile = ./Cargo.lock;
  patches = [ ./battery-parser.patch ];
  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ dbus ];
  meta = {
    description = "On-demand AirPods BLE battery readings as JSON";
    homepage = "https://github.com/t4t5/podpower";
    license = lib.licenses.mit;
    mainProgram = "podpower";
    platforms = lib.platforms.linux;
  };
}
