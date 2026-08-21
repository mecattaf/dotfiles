{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.myHeadless;
in
{
  options.myHeadless.enable = lib.mkEnableOption "the fleet's minimal headless appliance profile";
  # TV-endpoint carve-out (2026-08-21, Tom: "since it now has hdmi … might as
  # well do it now"): re-admits ONLY the display stack — niri + greetd
  # autologin, pipewire for HDMI audio, a minimal font set — while every other
  # appliance hardening below stands. The host supplies the rest (EDID pin,
  # wayvnc, admissions): see hosts/nas/tv.nix.
  options.myHeadless.tv.enable = lib.mkEnableOption "a niri TV/VNC session on an otherwise headless appliance";

  config = lib.mkIf cfg.enable {
    # A headless appliance still has the getty from common.nix for local recovery,
    # but (unless the tv carve-out is on) it never starts a compositor, greeter,
    # remote desktop, or user session.
    boot.plymouth.enable = lib.mkForce false;
    programs.niri.enable = lib.mkIf (!cfg.tv.enable) (lib.mkForce false);
    services.greetd.enable = lib.mkIf (!cfg.tv.enable) (lib.mkForce false);
    services.getty.autologinUser = "tom";
    users.users.tom.linger = lib.mkForce false;

    security.rtkit.enable = lib.mkIf (!cfg.tv.enable) (lib.mkForce false);
    services.pipewire.enable = lib.mkIf (!cfg.tv.enable) (lib.mkForce false);
    hardware.bluetooth.enable = lib.mkForce false;
    services.hardware.bolt.enable = lib.mkForce false;
    services.gnome.gnome-keyring.enable = lib.mkForce false;
    security.polkit.enable = lib.mkForce false;
    programs.dconf.enable = lib.mkForce false;
    services.gvfs.enable = lib.mkForce false;
    services.udisks2.enable = lib.mkForce false;
    services.power-profiles-daemon.enable = lib.mkForce false;
    services.fprintd.enable = lib.mkForce false;
    services.fwupd.enable = lib.mkForce false;
    xdg.portal.enable = lib.mkForce false;
    virtualisation.podman.enable = lib.mkForce false;

    # Household desktop fonts have no place on the NAS — except the TV session,
    # which gets a deliberately tiny set (terminal face + tofu-free text/emoji),
    # NOT the fleet list from common.nix (google-fonts alone would bloat the
    # appliance by hundreds of MB). The printer module and dotfiles bootstrap
    # are wholly gated off for this profile either way.
    fonts.packages = lib.mkForce (
      lib.optionals cfg.tv.enable (
        with pkgs;
        [
          maple-mono.NF
          noto-fonts
          noto-fonts-color-emoji
        ]
      )
    );

    # SSH is admitted explicitly by each appliance's interface-specific rules.
    # Never open it indiscriminately on every future interface.
    services.openssh.openFirewall = lib.mkForce false;

    zramSwap.memoryMax = lib.mkForce (4 * 1024 * 1024 * 1024);

    # Appliance tooling is ADDED, never mkForce'd: forcing this option also
    # discards the packages the NixOS module system itself contributes —
    # bashInteractive (every login shell and nixos-install's bootloader-chroot
    # interpreter) and the util-linux/coreutils required base. Both bit live
    # during the first DXP2800 GT install (chroot: sw/bin/bash missing, then
    # 'mount: command not found'). The desktop surface is already excluded by
    # the option forces above; common.nix only adds a handful of small CLI
    # tools, which is an acceptable price for a standard, bootable base.
    environment.systemPackages = with pkgs; [
      btrfs-progs
      ethtool
      hdparm
      iperf3
      libva-utils
      nvme-cli
      pciutils
      rsync
      smartmontools
      usbutils
    ];
  };
}
