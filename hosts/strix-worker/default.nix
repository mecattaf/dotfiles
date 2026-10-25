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
  # Not on the tailnet (Tom, 2026-10-25: "worker's tailnet login: fine, and i
  # was thinking let's not"). The NAS reaches it over the house LAN
  # (10.42.0.5, modules/fleet-hosts.nix), so no tailscaled, no tailscaled-set
  # and no login to keep alive. modules/fleet-transport.nix leaves it out.
  services.tailscale.enable = false;
  # The worker also holds Flash-Next Q8 (TP2 only; 191.92 GB with its
  # projector). The coordinator's disk cannot (108 GB free, D-A), so this is
  # the worker's alone, ordered after the boot set. ds4's Q2 joins this set
  # through services.ds4.wanted.
  services.local-models.artifacts = lib.mkAfter [ "qwen38-flash-next-q8-gguf" ];
  mySecrets.enable = false;
  # First boot must use the reviewed closure's helpers, not the retired
  # worker's checkout (or a network bootstrap of main).
  home-manager.users.tom.rawDotfiles.inStore = true;
  # Offline installation must not change the coordinator's EFI NVRAM. bootctl
  # still installs EFI/BOOT/BOOTX64.EFI on the worker's own ESP for first boot.
  boot.loader.efi.canTouchEfiVariables = lib.mkForce false;
  fileSystems."/mnt/nas/documents" = {
    device = "nas:/documents";
    fsType = "nfs4";
    options = config.fileSystems."/mnt/library".options;
  };
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
      # Keep 10.42.0.0/24 on the main table ahead of any Tailscale table 52;
      # same rule as the coordinator's LAN profile
      # (hosts/strix-coordinator/uplink-nas.nix). Inert without Tailscale.
      routing-rule1 = "priority 2500 to 10.42.0.0/24 table 254";
    };
    ipv6.method = "disabled";
  };
}
