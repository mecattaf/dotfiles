{ writeShellApplication
, google-chrome
, namespace
}:
# artifact-view <snapshot-dir | slug | URL> — rung 0 of the artifact ladder.
# Opens an artifact in a BOUNDED Chrome app window (no tab bar) — the same
# --app mechanism as the PWA launchers in home.nix (mod+shift+c/m), applied ad
# hoc. A local snapshot dir opens via file:// with NO server, no URL, no TTL,
# no teardown debt: this is md-artifact's default terminal state; the
# publish-artifact skill chains on top only to broadcast. `namespace` is
# injected from modules/artifacts-defaults.nix via overlays/default.nix.
writeShellApplication {
  name = "artifact-view";
  runtimeInputs = [ google-chrome ];
  text = ''
    target="''${1:?usage: artifact-view <snapshot-dir | slug | URL>}"

    if [ -d "$target" ]; then
      if [ ! -f "$target/index.html" ]; then
        echo "error: $target has no index.html (not a snapshot dir?)" >&2
        exit 1
      fi
      url="file://$(realpath "$target")/index.html"
    else
      case "$target" in
        http://* | https://*) url="$target" ;;
        # tailnet rung is plain HTTP in v1 (TLS = DNS-01 follow-up)
        *) url="http://$target.${namespace}" ;;
      esac
    fi

    exec google-chrome-stable --app="$url"
  '';
}
