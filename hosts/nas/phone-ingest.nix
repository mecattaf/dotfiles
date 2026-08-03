{
  config,
  lib,
  pkgs,
  unstablePkgs,
  ...
}:
# Operator tooling for pulling an Android phone's camera roll into Immich over
# USB (#143). Deliberately NOT a service: nothing here runs on its own, starts
# at boot, or touches the media stack. It is the set of tools a human needs
# present on the appliance to drive a repeatable ingest by hand.
#
# Route is adb, not MTP: adb preserves original mtimes, resumes cleanly, and
# gives exact per-folder file counts before and after a pull. MTP gives none of
# that reliably across a ~2000-file camera roll.
let
  cfg = config.myNas.phoneIngest;
  storageRoot = "/mnt/nas";
  # Staging lands on the HDD photos subvolume, not the NVMe fast tier. Pulled
  # frames are REAL USER DATA from the moment they leave the phone until they
  # are verified into Immich — and everything under /mnt/fast is, by that
  # tier's own doctrine (see hosts/nas/media.nix), either rebuildable or
  # dump-protected. Neither is true of a camera roll that may already have been
  # deleted from the handset. On photos/ it rides the subvolume's snapshot and
  # quarterly LaCie mirror story for free, and the 4 TB HDD does not care about
  # transient bulk the 'fast' disk would notice.
  stagingRoot = "${storageRoot}/photos/phone-staging";
in
{
  options.myNas.phoneIngest.enable = lib.mkEnableOption "adb + Immich CLI operator tooling for USB Android photo ingest";

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.myNas.storage.enable;
        message = "myNas.phoneIngest stages into the verified myNas.storage tree";
      }
    ];

    environment.systemPackages = [
      # Stable-sourced with the rest of the base system: adb's wire protocol is
      # ancient and stable, and nothing about it is coupled to Immich's version.
      pkgs.android-tools
      # UNSTABLE-sourced, unlike its neighbour above. The CLI's upload API is
      # versioned with the server, and this box runs the unstable Immich 3.0.3
      # (media.nix) because the restored database demands it. Stable carries
      # immich-cli 2.7.5 — the exact major-version mismatch the server package
      # is already pinned around.
      unstablePkgs.immich-cli
    ];

    # `programs.adb.enable` does not exist anymore: NixOS 26.05 removed it
    # (nixos/modules/rename.nix) once systemd 258 grew built-in ADB uaccess
    # rules, and dropped the android-udev-rules package with it.
    #
    # Those built-in rules are not sufficient here. systemd's 70-uaccess.rules
    # tags the device and leaves permissions to a logind ACL for the user of
    # the ACTIVE SEAT session — but this appliance is driven over SSH from the
    # coordinator, and an SSH session has no seat. It happens to work today
    # only as a side effect of headless.nix's getty autologin holding an active
    # tty1 session for the same uid; a logout, a VT switch, or dropping that
    # autologin would silently turn every pull into "no permissions".
    #
    # So restore the seat-independent half of what android-udev-rules did: a
    # group that owns the device node outright. The interface triple matches
    # systemd's own list — dc0201 (ADB over USB debug capability), ff4201
    # (ADB), ff4203 (fastboot). ID_USB_INTERFACES is already populated for
    # every usb_device by 50-udev-default.rules, well before this runs.
    users.groups.adbusers = { };
    users.users.tom.extraGroups = [ "adbusers" ];
    services.udev.extraRules = ''
      SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", ENV{ID_USB_INTERFACES}=="*:dc0201:*|*:ff4201:*|*:ff4203:*", GROUP="adbusers", MODE="0660"
    '';

    # Pull target. 0700 tom users, matching photos/ itself.
    #
    # No Immich API key is declared anywhere in this module, on purpose: the
    # CLI authenticates at runtime via `immich login <url> <key>` into
    # ~/.config/immich/auth.yml, which is mutable operator state and has no
    # business in a world-readable Nix store.
    systemd.tmpfiles.rules = [
      "d ${stagingRoot} 0700 tom users -"
    ];
  };
}
