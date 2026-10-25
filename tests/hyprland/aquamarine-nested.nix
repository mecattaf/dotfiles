# Test-only Aquamarine 0.13 nested backend compatibility fixture.
# Existing compositor bytes remain stock. Set LD_LIBRARY_PATH only on the
# isolated Hyprland child to use this library. Never add this to fleet overlays.
# wl_surface damage_buffer requires v4; xdg_toplevel requests used here are v1.
# v6 xdg suspend is an event and is simply unavailable from a v5 parent.
{ pkgs }:
pkgs.aquamarine.overrideAttrs (old: {
  pname = "aquamarine-nested-test";
  postPatch = (old.postPatch or "") + ''
    substituteInPlace src/backend/Wayland.cpp \
      --replace-fail '&xdg_wm_base_interface, 6)' '&xdg_wm_base_interface, std::min(version, 6u))' \
      --replace-fail '&wl_compositor_interface, 6)' '&wl_compositor_interface, std::min(version, 6u))' \
      --replace-fail '    createOutput();' '    createOutput(); wl_display_flush(waylandState.display);'
  '';
})
