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
  config = lib.mkIf cfg.enable {
    # Keep a local recovery getty without a graphical or remote desktop session.
    boot.plymouth.enable = lib.mkForce false;
    myDisplay.enable = lib.mkForce false; # an appliance has no display by definition
    # Belt and braces: ./display.nix already derives both of these from the
    # line above, and these two forces now agree with it rather than fight it.
    programs.niri.enable = lib.mkForce false;
    services.greetd.enable = lib.mkForce false;
    services.getty.autologinUser = "tom";
    users.users.tom.linger = lib.mkForce false;

    security.rtkit.enable = lib.mkForce false;
    services.pipewire.enable = lib.mkForce false;
    hardware.bluetooth.enable = lib.mkForce false;
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

    fonts.packages = lib.mkForce [ ];

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
