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
      # Prefer the direct home LAN over accepted Tailscale subnet routes, as
      # the client's home Wi-Fi profiles do (hosts/client/default.nix). With
      # --accept-routes=true the NAS's advertised 10.42.0.0/24 lands in
      # Tailscale's table 52, which is consulted before main, so LAN traffic
      # (NFS, the TP2 bootstrap, NAS SSH) hairpinned through tailscale0 and
      # this box went dark on the LAN (measured 2026-10-25, 05:54-06:06).
      # This box now runs --accept-routes=false (modules/fleet-transport.nix);
      # the rule stays as a guard against a hand `tailscale set`.
      routing-rule1 = "priority 2500 to 10.42.0.0/24 table 254";
    };
    ipv6.method = "disabled";
  };
}
