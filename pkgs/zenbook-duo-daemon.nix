{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  libevdev,
}:
# PegasisForever/zenbook-duo-daemon — the userspace dock/keyboard/display
# daemon for the ASUS Zenbook Duo UX8406 (host `client`). MIT. Talks to the
# detachable keyboard as generic USB HID + evdev and flips the bottom panel by
# writing the DRM connector's force-status file, so it needs NO kernel patch
# and never talks to the compositor: niri simply sees a hotplug event and
# kanshi re-applies a profile. Carried from omarchy-fleet
# pkgs/zenbook-duo-daemon.nix on 2026-09-11, when the laptop returned to this
# tree; the fleet's copy ran on the same metal for three days.
#
# Pinned to the last release commit. Fork-and-pin into mecattaf/ is still open.
rustPlatform.buildRustPackage rec {
  pname = "zenbook-duo-daemon";
  version = "1.2.0";

  src = fetchFromGitHub {
    owner = "PegasisForever";
    repo = "zenbook-duo-daemon";
    rev = "7955be868aba807b02ec748c02ab537aabec3ada";
    hash = "sha256-ucyjhbF/qA8/J81mwqZfC0CLTQoU0eBwO0qSScVmuRY=";
  };

  cargoLock.lockFile = "${src}/Cargo.lock";

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ libevdev ];

  # Tests need the real keyboard and root.
  doCheck = false;

  meta = {
    description = "Dock, hotkey, backlight and secondary-display daemon for the ASUS Zenbook Duo UX8406";
    homepage = "https://github.com/PegasisForever/zenbook-duo-daemon";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "zenbook-duo-daemon";
  };
}
