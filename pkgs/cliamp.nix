{ lib, fetchFromGitHub, buildGoModule, pkg-config, alsa-lib }:

# cliamp — terminal music player (Winamp-inspired TUI).
# Packaged from source: not in nixpkgs (verified 2026-07-06).
# Uses CGO on Linux via ebitengine/oto → ALSA (libasound).
#
# vendorHash: computed from `go mod vendor` on v1.9.0 source.
# If it drifts on version bump, rebuild with lib.fakeHash and update from the error.
buildGoModule rec {
  pname = "cliamp";
  version = "1.9.0";

  src = fetchFromGitHub {
    owner = "bjarneo";
    repo = "cliamp";
    rev = "v${version}";
    hash = "sha256-pNw9E/zl9i0diG2oHyV07v/RHVoQUwzNxOslICpLnMU=";
  };

  vendorHash = "sha256-M3rJmsmlfVhYx1EIAfU8kHkazJO5eWPXlxoBnRgEVFY=";

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ alsa-lib ];

  ldflags = [
    "-s"
    "-w"
    "-X main.version=v${version}"
  ];

  meta = with lib; {
    description = "Terminal music player (Winamp-inspired) with Navidrome/Subsonic, Spotify, and local file support";
    homepage = "https://www.cliamp.stream/";
    license = licenses.mit;
    mainProgram = "cliamp";
    platforms = [ "x86_64-linux" "aarch64-linux" ];
  };
}
