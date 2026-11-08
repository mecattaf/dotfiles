{ callPackage, kitty }:
let
  # Owned source snapshot and upstream notices travel with this checkout.
  # The holder is built from fixed source/dependencies, never a home-directory
  # binary. Compilation follows the fleet's existing SSH builder policy.
  holderPackage = callPackage ./source/backend/zmx/source-build.nix { };
in
callPackage ./source/default.nix { inherit kitty holderPackage; }
