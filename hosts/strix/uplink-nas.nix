{ ... }:
{
  # Permanent cupboard installation. Stage with `nixos-rebuild boot`: do not
  # move .2 off the live Wi-Fi interface during an attached agent session.
  services.resolved.settings.Resolve.DNS = "1.1.1.1 9.9.9.9";
  boot.blacklistedKernelModules = [ "mt7925e" ];
  networking.networkmanager.unmanaged = [ "interface-name:wlp192s0" ];
  networking.networkmanager.ensureProfiles.profiles.lan = {
    connection = {
      id = "strix-lan";
      type = "ethernet";
      interface-name = "enp191s0";
      autoconnect = true;
      autoconnect-priority = 200;
    };
    ipv4 = {
      method = "manual";
      address1 = "10.42.0.2/24";
      gateway = "10.42.0.3";
      # Internal names come from the NAS; public DNS remains available when
      # the NAS is unavailable. Internet routing goes directly through BE550.
      dns = "10.42.0.1";
      dns-search = "~internal";
      ignore-auto-dns = true;
      route-metric = 100;
    };
    ipv6.method = "disabled";
  };
}
