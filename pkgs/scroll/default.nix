{
  lib,
  stdenv,
  fetchFromGitHub,
  makeWrapper,
  symlinkJoin,
  meson,
  ninja,
  pkg-config,
  wayland-scanner,
  scdoc,
  libGL,
  wayland,
  libxkbcommon,
  pcre2,
  json_c,
  libevdev,
  pango,
  cairo,
  libinput,
  gdk-pixbuf,
  librsvg,
  wayland-protocols,
  libdrm,
  glslang,
  hwdata,
  lua54Packages,
  vulkan-loader,
  xwayland,
  seatd,
  lcms,
  libdisplay-info,
  libxcb,
  libxcb-wm,
  libxcb-render-util,
  libxcb-errors,
  libliftoff,
  libgbm,
  readline,
  systemd,
}:
# scroll (github.com/dawsers/scroll) built from MASTER at a pinned revision.
#
# The build recipe is lifted from nixpkgs PR #544657
# (Diax170/nixpkgs@54089750d1bddc6b0fbaf97e9a96479a6243a01a,
# pkgs/by-name/sc/scroll-unwrapped/package.nix, MIT like the rest of nixpkgs),
# with three deliberate differences:
#   - src is master, pinned by rev + hash, not a release tag (Tom 2026-10-01:
#     "scroll master", report regressions upstream with the rev pair);
#   - systemd is an explicit build input: the sd-bus provider is libsystemd and
#     the tray needs it, the PR relied on it arriving transitively;
#   - the attribute names are `scroll` / `scroll-unwrapped`, which shadow
#     NOTHING in nixpkgs. pkgs.sway stays stock: modules/browser-desktop.nix
#     runs it for the headless browser seat, and flake.nix asserts it.
#
# scroll vendors its own wlroots (subprojects/wlroots, 0.21.0-dev), so the
# flake's wlroots_0_* are irrelevant. The floors that matter are libdrm
# (>= 2.4.134 since the vendored wlroots chase) and wayland-protocols
# (>= 1.48); a master bump that raises them fails here first.
#
# BUMP (the only upgrade verb; no timer, AGENTS.md D40-D51):
#   rev=$(git ls-remote https://github.com/dawsers/scroll HEAD | cut -f1)
#   nix-prefetch-url --unpack https://github.com/dawsers/scroll/archive/$rev.tar.gz
#   # convert to SRI with `nix hash convert --hash-algo sha256 --to sri <base32>`
#   # then edit rev/hash/version below and follow docs/scroll.md "Master bump".
let
  rev = "3c5a0f037ff82e0ec7968811bc13412148d41dec"; # master, 2026-10-01T10:45:20Z
  version = "1.13-dev-unstable-2026-10-01";

  unwrapped = stdenv.mkDerivation (finalAttrs: {
    pname = "scroll-unwrapped";
    inherit version;

    src = fetchFromGitHub {
      owner = "dawsers";
      repo = "scroll";
      inherit rev;
      hash = "sha256-nElrvgNevnvA5uoiHTXembaQaLJTAXjvgmh9FSxFq+Q=";
    };

    strictDeps = true;
    __structuredAttrs = true;

    depsBuildBuild = [ pkg-config ];

    nativeBuildInputs = [
      meson
      ninja
      pkg-config
      wayland-scanner
      scdoc
      # vendored wlroots
      glslang
      lcms
      hwdata
      libliftoff
    ];

    buildInputs = [
      libGL
      wayland
      libxkbcommon
      pcre2
      json_c
      libevdev
      pango
      cairo
      libinput
      gdk-pixbuf
      librsvg
      wayland-protocols
      libdrm
      systemd
      # scroll-specific (Lua 5.4 is a hard build dependency, meson.build;
      # Tom's config keeps Lua minimal, but the interpreter is linked regardless)
      lua54Packages.lua
      vulkan-loader
      seatd
      lcms
      libdisplay-info
      libliftoff
      libgbm
      readline
      # Xwayland (native in scroll; replaces niri's xwayland-satellite)
      libxcb
      libxcb-wm
      xwayland
      libxcb-render-util
      libxcb-errors
    ];

    mesonFlags = [
      (lib.mesonOption "sd-bus-provider" "libsystemd")
      (lib.mesonEnable "tray" true)
      # the vendored wlroots builds with werror=true
      (lib.mesonOption "c_args" "-Wno-error=maybe-uninitialized")
    ];

    passthru = {
      inherit rev;
    };

    meta = {
      description = "Sway fork with a scrolling tiling layout (master build)";
      homepage = "https://github.com/dawsers/scroll";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux;
      mainProgram = "scroll";
    };
  });
in
# The wrapper only defaults XDG_CURRENT_DESKTOP (portal selection reads
# scroll-portals.conf from it). The session environment proper is set by
# modules/scroll.nix's scroll-session launcher and scroll.service; there is no
# dbus-run-session fallback because scroll is only ever started inside the
# systemd user manager, whose bus already exists.
symlinkJoin {
  pname = "scroll";
  inherit version;
  paths = [ unwrapped ];
  nativeBuildInputs = [ makeWrapper ];
  postBuild = ''
    wrapProgram $out/bin/scroll --set-default XDG_CURRENT_DESKTOP scroll
  '';
  passthru = {
    inherit unwrapped rev;
    providedSessions = [ "scroll" ];
  };
  inherit (unwrapped) meta;
}
