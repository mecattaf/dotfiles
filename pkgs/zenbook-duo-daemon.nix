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

  # Vendored copy of ${src}/Cargo.lock at the pinned rev (DF-5, 2026-09-23).
  # Reading "${src}/Cargo.lock" was an import-from-derivation: evaluation had to
  # fetch src first, so `nix flake check --no-build` passed or failed on whether
  # the source happened to be in the store (#455). The copy keeps evaluation
  # store-independent; checks.zenbook-duo-daemon-lock fails at build time if a
  # rev bump leaves this file behind upstream's.
  cargoLock.lockFile = ./zenbook-duo-daemon.Cargo.lock;

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
