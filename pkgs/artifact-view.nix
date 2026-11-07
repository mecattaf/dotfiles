{
  writeShellApplication,
  google-chrome,
  coreutils,
  namespace,
}:
# artifact-view <snapshot-dir | slug | URL> — rung 0 of the artifact ladder.
# Opens an artifact in a BOUNDED Chrome app window (no tab bar) — the same
# --app mechanism as the PWA launchers in home.nix (mod+shift+c/m), applied ad
# hoc. A local snapshot dir opens via file:// with NO server, no URL, no TTL,
# no teardown debt: this is md-artifact's default terminal state; the
# publish-artifact skill chains on top only to broadcast. `namespace` is
# injected from modules/artifacts-defaults.nix via overlays/default.nix.
#
# RUNG 0 IS THE SEAT'S RUNG. Agents run on a headless host;
# the display belongs to the client. So on a host
# with no Wayland or X display this command does not fail obscurely inside
# Chrome — it refuses, explains that rung 0 does not exist there, and prints the
# rung that DOES: the publish-artifact skill. Keep the serving recipe there;
# duplicating it here repeatedly recreated HTTP-only .dev sites (#678).
writeShellApplication {
  name = "artifact-view";
  # coreutils is explicit now that the no-display branch spends `uname`,
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
        *)
          if ! command -v artifact-publish >/dev/null 2>&1; then
            echo "artifact-view: install the external artifact-publish utility to resolve a private artifact slug." >&2
            exit 1
          fi
          url="$(artifact-publish url "$target")"
          ;;
      esac
    fi

    # No display here -> rung 0 does not exist here. Name the next rung instead
    # of dying inside Chrome. See the header.
    if [ -z "''${WAYLAND_DISPLAY:-}" ] && [ -z "''${DISPLAY:-}" ]; then
      {
        echo "artifact-view: $(uname -n) has no display: open the artifact on the viewing client."
        echo "The seat (client) is the only host with a screen. Give the artifact a URL and open it there."
        if [ -n "$slug" ]; then
          echo
          echo "Publish privately: artifact-publish publish $(realpath "$target") --slug $slug"
          echo "The external publish-artifact skill covers Tailscale-local URLs and explicit Cloudflare publication."
          echo "${namespace} is reserved for public publication. Private artifacts use Tailscale Serve."
          echo "Verify the exact published URL and its assets from that client before handing it over."
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
