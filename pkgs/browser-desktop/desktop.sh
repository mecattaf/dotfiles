# Session-local environment: do not import this display into the user manager.
umask 077
runtime="${XDG_RUNTIME_DIR:?}/browser-desktop"
mkdir -p "$runtime"
export FARA_BROWSER_RUNTIME="$runtime"
case "${1:-start}" in
  start)
    exec 9>"$runtime/session.lock"
    flock -n 9 || { echo 'The browser desktop is already running.' >&2; exit 1; }
    unset DISPLAY WAYLAND_DISPLAY SWAYSOCK NIRI_SOCKET
    export WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 WLR_RENDERER=pixman
    export XDG_CURRENT_DESKTOP=sway XDG_SESSION_TYPE=wayland
    cat >"$runtime/sway.conf" <<EOF
output HEADLESS-1 mode 1440x900 scale 1
output * bg #202020 solid_color
xwayland disable
font monospace 10
default_border pixel 1
focus_follows_mouse no
seat seat0 fallback true
input type:keyboard {
  xkb_layout us
  xkb_options caps:none
}
for_window [app_id="google-chrome"] shortcuts_inhibitor disable
for_window [app_id="google-chrome"] border pixel 0
exec "$0" inside
EOF
    exec sway --config "$runtime/sway.conf"
    ;;
  inside)
    printf 'export WAYLAND_DISPLAY=%q\nexport SWAYSOCK=%q\n' \
      "${WAYLAND_DISPLAY:?}" "${SWAYSOCK:?}" >"$runtime/environment"
    cleanup() {
      rm -f "$runtime/environment"
      swaymsg exit >/dev/null 2>&1 || true
    }
    trap cleanup EXIT
    trap 'exit 0' TERM INT
    cat >"$runtime/wayvnc.conf" <<EOF
enable_auth=false
xkb_layout=us
EOF
    # Only the existing Caddy LAN front door exposes this WebSocket.
    wayvnc --config "$runtime/wayvnc.conf" --disable-resizing --render-cursor \
      --output HEADLESS-1 --socket "$runtime/wayvncctl" ws:127.0.0.1:5901 &
    vnc_pid=$!
    wait "$vnc_pid" || exit 1
    ;;
  *) echo 'Usage: browser-desktop [start|inside]' >&2; exit 2 ;;
esac
