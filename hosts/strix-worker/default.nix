{ config, lib, ... }:
# Returning Framework Desktop, adapted from 135e0ff9^:hosts/worker.
# Confirm the wired NIC MAC and interface name at installation.
{
  imports = [
    ./hardware.nix
    ./disko.nix
    ../../modules/strix-compute.nix
  ];
  networking.hostName = "strix-worker";
  myFleet.roles = [ "compute" ];
  mySecrets.enable = false;
  # Offline installation must not change the coordinator's EFI NVRAM. bootctl
  # still installs EFI/BOOT/BOOTX64.EFI on the worker's own ESP for first boot.
  boot.loader.efi.canTouchEfiVariables = lib.mkForce false;
  fileSystems."/mnt/nas/documents" = {
    device = "nas:/documents";
    fsType = "nfs4";
    options = config.fileSystems."/mnt/library".options;
  };
  services.tailscale.enable = lib.mkForce false;
  boot.blacklistedKernelModules = [ "mt7925e" ];
  networking.networkmanager.unmanaged = [ "interface-name:wlp192s0" ];
  networking.networkmanager.logLevel = "INFO";
  networking.networkmanager.ensureProfiles.profiles.lan = {
    connection = {
      id = "strix-worker-lan";
      type = "ethernet";
      interface-name = "enp191s0";
      autoconnect = true;
      autoconnect-priority = 200;
    };
    ipv4 = {
      method = "manual";
      address1 = "10.42.0.5/24";
      gateway = "10.42.0.3";
      dns = "10.42.0.1";
      ignore-auto-dns = true;
      route-metric = 100;
    };
    ipv6.method = "disabled";
  };
}
