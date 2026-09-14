let pkgs = import <nixpkgs> {}; in
pkgs.bluez.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [ ./huion-note-x10-ble/patches/fix-duplicate-mtu-request.patch ];
})
