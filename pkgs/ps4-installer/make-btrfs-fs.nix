# Nixstation donor: map the build user to root when mkfs imports ownership.
# btrfs-progs 7.x bypasses fakeroot; silently shipping nixbld-owned /nix is wrong.
{
  pkgs,
  lib,
  util-linux,
  ...
}@args:
(pkgs.callPackage (pkgs.path + "/nixos/lib/make-btrfs-fs.nix") (
  builtins.removeAttrs args [
    "pkgs"
    "lib"
    "util-linux"
  ]
)).overrideAttrs
  (old: {
    nativeBuildInputs = old.nativeBuildInputs ++ [ util-linux ];
    buildCommand =
      # Leave real writable space for activation, store registration and logs.
      # Merely appending zeroes after mkfs would not grow the Btrfs filesystem.
      # The partition stays this exact size until an attended USB-only grow.
      assert lib.assertMsg (
        lib.hasInfix "touch $img" old.buildCommand
        && lib.hasInfix "--shrink $img" old.buildCommand
        && lib.hasInfix "fakeroot mkfs.btrfs" old.buildCommand
      ) "The upstream Btrfs image recipe changed; review PS4 ownership/sizing integration";
      builtins.replaceStrings
        [ "touch $img" "fakeroot mkfs.btrfs" "--shrink $img" ]
        [
          ''
            rootSizeMiB=$(du --apparent-size -sm ./rootImage | cut -f1)
            truncate -s "$(( (rootSizeMiB * 12 / 10 + 2048) * 1024 * 1024 ))" "$img"
          ''
          "unshare -r mkfs.btrfs"
          "$img"
        ]
        old.buildCommand;
  })
