final: _prev: {
  # Add-only overlay (no nixpkgs overrides). Bespoke source-builds land here:
  #   mactahoe-oled = final.callPackage ../pkgs/mactahoe-oled.nix { };  # next increment
  # Everything else from the old COPR is already in nixpkgs (referenced directly).
  # DEFERRED: asr-rs (v2 not in first push), cliamp, gws, fgp-browser.
}
