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
    # A headless appliance still has the getty from common.nix for local recovery,
    # but it never starts a compositor, greeter, remote desktop, or user session.
    boot.plymouth.enable = lib.mkForce false;
    programs.niri.enable = lib.mkForce false;
    services.greetd.enable = lib.mkForce false;
    services.getty.autologinUser = "tom";
    users.users.tom.linger = lib.mkForce false;

    security.rtkit.enable = lib.mkForce false;
    services.pipewire.enable = lib.mkForce false;
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

    # Household desktop fonts have no place on the NAS. The printer module and
    # dotfiles bootstrap are wholly gated off for this profile.
    fonts.packages = lib.mkForce [ ];

    # SSH is admitted explicitly by each appliance's interface-specific rules.
    # Never open it indiscriminately on every future interface.
    services.openssh.openFirewall = lib.mkForce false;

    zramSwap.memoryMax = lib.mkForce (4 * 1024 * 1024 * 1024);

    environment.systemPackages = lib.mkForce (
      with pkgs;
      [
        # mkForce also strips the bash the NixOS bash module contributes, but
        # /run/current-system/sw/bin/bash is every user's login shell and the
        # interpreter nixos-install's bootloader chroot runs. Without it the
        # install aborts (chroot: .../sw/bin/bash: No such file or directory,
        # hit live 2026-08-01) and getty/SSH logins would fail the same way.
        bashInteractive
        age
        attic-client
        btrfs-progs
        ethtool
        git
        hdparm
        iperf3
        libva-utils
        nvme-cli
        pciutils
        rsync
        smartmontools
        usbutils
        vim
      ]
    );
  };
}
