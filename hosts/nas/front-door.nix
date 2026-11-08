{ ... }:
# NAS front door for the plain-HTTP `.internal` sites. Caddy remains the
# media/browser/handwriting front door after private artifact hosting was
# retired on 2026-11-08; those vhosts are added here and by their host files.
#
# Bind: Tailscale Serve owns :443 on the NAS tailnet address
# (modules/herdr-web-ui.nix), so Caddy must never bind a wildcard. default_bind
# keeps every site on the LAN address and loopback only.
#
# WireGuard supplies transport security on the tailnet; `.internal` names
# never resolve publicly.
{
  services.caddy = {
    enable = true;
    globalConfig = ''
      auto_https disable_redirects
      default_bind 10.42.0.1 127.0.0.1
    '';
  };

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

  # LAN clients reach Caddy on the router address. Tailnet clients retain :80
  # for internal sites; :443 belongs to Tailscale Serve and Herdr.
  networking.firewall.extraInputRules = ''
    iifname "enp1s0" ip saddr 10.42.0.0/24 tcp dport { 80, 443 } accept comment "Caddy front door (LAN)"
  '';
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 80 ];
}
