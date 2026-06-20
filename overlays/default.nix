final: _prev: {
  # Add-only overlay (no nixpkgs overrides). Bespoke source-builds live here.
  # Everything else from the old COPR is already in nixpkgs (referenced directly).

  # mactahoe — the PROVEN source-build + OLED postPatch (NOT nix-test's prebuilt
  # tarball). Built/verified in a nixos/nix container 2026-06-19. Lives at
  # ~/mecattaf/mactahoe-oled/ originally; lifted verbatim into pkgs/.
  mactahoe-gtk-theme = final.callPackage ../pkgs/mactahoe-gtk-theme.nix { };
  mactahoe-icon-theme = final.callPackage ../pkgs/mactahoe-icon-theme.nix { };

  # DEFERRED bespoke pkgs: asr-rs (v2 not in first push), cliamp, gws, fgp-browser.
}
