{ pkgs, ... }:
let
  preferences = [
    "--hostname=nas"
    "--advertise-routes=10.42.0.0/24"
    "--advertise-exit-node"
    "--accept-routes=false"
    "--accept-dns=false"
    "--ssh=false"
  ];
in
{
  # The closet's only Tailscale node. Reuse the already enrolled nas-saas
  # identity from the retired container, never run both daemons over it.
  # Keep /var/lib/tailscale and /var/lib/headscale intact for rollback.
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "server";
    openFirewall = true;
    disableTaildrop = true;
    extraDaemonFlags = [ "--state=/var/lib/tailscale-personal/tailscaled.state" ];
    extraUpFlags = preferences;
    extraSetFlags = preferences;
  };
  systemd.services.tailscaled = {
    conflicts = [ "container@nas-saas.service" ];
    after = [ "container@nas-saas.service" ];
    unitConfig.ConditionPathExists = "/var/lib/tailscale-personal/tailscaled.state";
  };
  # Old Serve/Funnel state belongs to the deleted Headscale transport. Reset
  # it once on explicit migration, not on every boot (future Serve is owned
  # by the operator). The command is provided below, not run by activation.
  environment.systemPackages = [
    (pkgs.writeShellApplication {
      name = "nas-tailnet-cutover";
      runtimeInputs = [
        pkgs.tailscale
        pkgs.jq
      ];
      text = ''
        tailscale status --json --peers=false | jq -e \
          '.BackendState == "Running" and .CurrentTailnet.MagicDNSSuffix == "tail8dd1.ts.net"' >/dev/null
        tailscale funnel reset
        tailscale serve reset
        tailscale set ${builtins.concatStringsSep " " preferences}
        echo "NAS SaaS identity active. Approve 10.42.0.0/24 and the exit-node role in the Tailscale admin console."
      '';
    })
  ];
  networking.firewall.interfaces.tailscale0 = {
    allowedTCPPorts = [
      22
      53
      2283
      4533
      32400
    ];
    allowedUDPPorts = [ 53 ];
  };
}
