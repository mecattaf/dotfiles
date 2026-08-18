{
  lib,
  fetchFromGitHub,
  buildGoModule,
  pkg-config,
  alsa-lib,
  libogg,
  libvorbis,
  flac,
  makeWrapper,
  yt-dlp,
  ffmpeg,
}:

# cliamp — terminal music player (Winamp-inspired TUI).
# Packaged from source: not in nixpkgs (verified 2026-07-06).
# Uses CGO on Linux via ebitengine/oto → ALSA (libasound).
#
# Was pinned at v1.9.0 from 2026-07-06 until 2026-08-18. That release's
# Navidrome client was 143 lines exposing exactly three Subsonic endpoints —
# getPlaylists, getPlaylist, stream — so the library could only ever be browsed
# as playlists; there was no artist or album browsing at all. Its config loader
# was likewise a flat key=value scanner over ten hardcoded keys, which silently
# dropped every [navidrome]/[soundcloud] section and did no ${VAR} expansion,
# leaving the server configurable only through NAVIDROME_URL/USER/PASS.
#
# v1.63.2 fixes both: NavidromeClient now implements provider.ArtistBrowser and
# provider.AlbumBrowser over getArtists/getArtist/getAlbum/getAlbumList2/search3,
# and the config parser understands real sections plus ${VAR} interpolation from
# the environment. home/dot_config/cliamp/config.toml depends on both.
#
# vendorHash: from `go mod vendor` on the v1.63.2 source. If it drifts on a
# version bump, rebuild with lib.fakeHash and take the value from the error.
buildGoModule rec {
  pname = "cliamp";
  version = "1.63.2";

  src = fetchFromGitHub {
    owner = "bjarneo";
    repo = "cliamp";
    rev = "v${version}";
    hash = "sha256-HqFDT8jGvrKqb6bupvXqZ5ECpvColRB5dXPwcKCX4RQ=";
  };

  vendorHash = "sha256-WYyv0w5KFA15axb+NA9tClfc1H4Znj8kI2boR8XziXg=";

  nativeBuildInputs = [
    pkg-config
    makeWrapper
  ];
  # alsa-lib for the oto audio backend; the ogg/vorbis/flac trio arrived with
  # v1.63.2's go-librespot (Spotify) dependency, which cgo-links them via
  # pkg-config and fails the build outright when they are absent.
  buildInputs = [
    alsa-lib
    libogg
    libvorbis
    flac
  ];

  ldflags = [
    "-s"
    "-w"
    "-X main.version=v${version}"
  ];

  # cliamp shells out to these by bare name for non-native formats (aac/opus/wma
  # go through ffmpeg) and for SoundCloud/YouTube/Bandcamp URLs. Wrapping keeps
  # it working regardless of what happens to be on the ambient PATH.
  postInstall = ''
    wrapProgram $out/bin/cliamp \
      --prefix PATH : ${lib.makeBinPath [ yt-dlp ffmpeg ]}
  '';

  meta = with lib; {
    description = "Terminal music player (Winamp-inspired) with Navidrome/Subsonic, Spotify, and local file support";
    homepage = "https://www.cliamp.stream/";
    license = licenses.mit;
    mainProgram = "cliamp";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
