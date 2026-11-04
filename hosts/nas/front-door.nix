{ ... }:
# NAS front door for the plain-HTTP `.internal` sites and the artifact drop-dir.
# Decided 2026-10-31: the NAS hosts every internal website, so Caddy lives here
# and strix-coordinator runs none. The artifact plane (drop-dir import, tmpfiles,
# reaper) comes from modules/caddy-artifacts.nix; the browser and handwriting
# vhosts are added by their own host files.
#
# Bind: Tailscale Serve owns :443 on the NAS tailnet address
# (modules/herdr-web-ui.nix), so Caddy must never bind a wildcard. default_bind
# keeps every site on the LAN address and loopback only.
#
# Plain HTTP by the same posture as the artifact plane: WireGuard is the
# transport security on the tailnet and `.internal` never resolves publicly.
{
  imports = [ ../../modules/caddy-artifacts.nix ];

  services.caddy.globalConfig = ''
    default_bind 10.42.0.1 127.0.0.1
  '';

  # Memorable intranet names for the media services the NAS runs itself
  # (hosts/nas/media.nix). AdGuard answers 10.42.0.1 for each of them
  # (modules/adguardhome.nix); the port URLs stay available beside them.
  services.caddy.virtualHosts = {
    "http://photos.internal".extraConfig = ''
      reverse_proxy 127.0.0.1:2283
    '';
    "http://music.internal".extraConfig = ''
      reverse_proxy 127.0.0.1:4533
    '';
    "http://videos.internal".extraConfig = ''
      # Plex answers 401 on its bare API root; the human entrance is /web.
      redir / /web/ 302
      reverse_proxy 127.0.0.1:32400
    '';
  };

  # LAN clients reach Caddy on the router address. Tailnet clients get :80 here
  # (artifact records point at the NAS); :443 is already admitted on
  # tailscale0 for Tailscale Serve.
  networking.firewall.extraInputRules = ''
    iifname "enp1s0" ip saddr 10.42.0.0/24 tcp dport { 80, 443 } accept comment "Caddy front door (LAN)"
  '';
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 80 ];
}
