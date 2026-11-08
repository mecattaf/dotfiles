{
  writeShellApplication,
  google-chrome,
  coreutils,
}:
# Local artifact viewing on the physical seat. Private artifact publishing
# was retired on 2026-11-08. Explicit URLs can still be opened, including
# public Cloudflare content; a bare slug must never recreate a private host.
writeShellApplication {
  name = "artifact-view";
  runtimeInputs = [
    google-chrome
    coreutils
  ];
  text = ''
    target="''${1:?usage: artifact-view <snapshot-dir | URL>}"

    if [ -d "$target" ]; then
      if [ ! -f "$target/index.html" ]; then
        echo "error: $target has no index.html (not a snapshot dir?)" >&2
        exit 1
      fi
      url="file://$(realpath "$target")/index.html"
    else
      case "$target" in
        http://* | https://*) url="$target" ;;
        *)
          echo "error: expected a snapshot directory or an explicit URL; private artifact slugs are retired" >&2
          exit 1
          ;;
      esac
    fi

    if [ -z "''${WAYLAND_DISPLAY:-}" ] && [ -z "''${DISPLAY:-}" ]; then
      echo "artifact-view: $(uname -n) has no display; open the snapshot or explicit URL on the client." >&2
      exit 2
    fi

    if [ -n "''${ARTIFACT_VIEW_DRY_RUN:-}" ]; then
      echo "google-chrome-stable --app=$url"
      exit 0
    fi

    exec google-chrome-stable --app="$url"
  '';
}
