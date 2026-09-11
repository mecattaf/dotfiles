{ writeShellApplication
, google-chrome
, coreutils
, namespace
}:
# artifact-view <snapshot-dir | slug | URL> — rung 0 of the artifact ladder.
# Opens an artifact in a BOUNDED Chrome app window (no tab bar) — the same
# --app mechanism as the PWA launchers in home.nix (mod+shift+c/m), applied ad
# hoc. A local snapshot dir opens via file:// with NO server, no URL, no TTL,
# no teardown debt: this is md-artifact's default terminal state; the
# publish-artifact skill chains on top only to broadcast. `namespace` is
# injected from modules/artifacts-defaults.nix via overlays/default.nix.
#
# RUNG 0 IS THE SEAT'S RUNG (2026-09-11). Agents run on the coordinator, which
# is headless; the only display in the fleet belongs to the client. So on a host
# with no Wayland or X display this command does not fail obscurely inside
# Chrome — it refuses, explains that rung 0 does not exist there, and prints the
# rung that DOES: the publish-artifact drop-file recipe plus the URL to open on
# the seat. An agent that reads that stderr has everything it needs to finish
# the job without a second round trip.
writeShellApplication {
  name = "artifact-view";
  # coreutils is explicit now that the no-display branch spends `uname`, `date`,
  # `basename` and `realpath` rather than leaving them to the ambient PATH.
  runtimeInputs = [
    google-chrome
    coreutils
  ];
  text = ''
    target="''${1:?usage: artifact-view <snapshot-dir | slug | URL>}"

    slug=""
    if [ -d "$target" ]; then
      if [ ! -f "$target/index.html" ]; then
        echo "error: $target has no index.html (not a snapshot dir?)" >&2
        exit 1
      fi
      url="file://$(realpath "$target")/index.html"
      slug="$(basename "$(realpath "$target")")"
    else
      case "$target" in
        http://* | https://*) url="$target" ;;
        # tailnet rung is plain HTTP in v1 (TLS = DNS-01 follow-up)
        *) url="http://$target.${namespace}" ;;
      esac
    fi

    # No display here -> rung 0 does not exist here. Name the next rung instead
    # of dying inside Chrome. See the header.
    if [ -z "''${WAYLAND_DISPLAY:-}" ] && [ -z "''${DISPLAY:-}" ]; then
      {
        echo "artifact-view: $(uname -n) has no display: rung 0 does not exist here (the coordinator is headless since 2026-09-11)."
        echo "The seat (client) is the only host with a screen. Give the artifact a URL and open it there."
        if [ -n "$slug" ]; then
          until_date="$(date -d '+7 days' +%Y%m%d 2>/dev/null || echo YYYYMMDD)"
          echo
          echo "Publish rung (publish-artifact skill, tailnet, TTL in the filename) — run here:"
          echo "  cp -r $(realpath "$target") /var/lib/artifacts/$slug"
          echo "  write /var/lib/artifacts/$slug.until-$until_date.caddy  ->  http://$slug.${namespace}:80 { root * /var/lib/artifacts/$slug ; file_server }"
          echo "  sudo systemctl reload caddy"
          echo
          echo "Then open on the client:  http://$slug.${namespace}"
        else
          echo
          echo "Open on the client:  $url"
        fi
      } >&2
      exit 2
    fi

    if [ -n "''${ARTIFACT_VIEW_DRY_RUN:-}" ]; then
      echo "google-chrome-stable --app=$url"
      exit 0
    fi

    exec google-chrome-stable --app="$url"
  '';
}
