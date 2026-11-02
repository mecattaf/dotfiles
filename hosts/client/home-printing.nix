{ pkgs, ... }:
let
  gate = pkgs.writeShellApplication {
    name = "home-printing-gate";
    runtimeInputs = [
      pkgs.networkmanager
      pkgs.nftables
    ];
    text = builtins.readFile ./home-printing.sh;
  };
  refresh = "${pkgs.systemd}/bin/systemctl start --no-block home-printing-gate.service";
  rules = pkgs.writeText "home-printing-rules.nft" ''
    destroy table inet home_printing
    table inet home_printing {
      set wifi_interfaces {
        type ifname
      }
      chain output {
        type filter hook output priority -50; policy accept;
        ip daddr 10.42.0.1 tcp dport 631 oifname @wifi_interfaces accept
        ip daddr 10.42.0.1 tcp dport 631 reject with tcp reset
      }
    }
  '';
in
{
  # Keep the server address stable for applications that cache libcups's
  # configuration. Reject connections immediately unless NetworkManager says
  # this is the NAS-managed home Wi-Fi, including its gateway, DNS and lease.
  # The NAS also restricts its listener to this client's reserved LAN address.
  # Own just this table, alongside the client's existing firewall backend.
  # Restarting it closes the gate until the live Wi-Fi has been checked again.
  systemd.services.home-printing-filter = {
    description = "Limit the NAS print connection to the home Wi-Fi interface";
    wantedBy = [ "multi-user.target" ];
    postStart = refresh;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.nftables}/bin/nft -f ${rules}";
      ExecStop = "${pkgs.nftables}/bin/nft flush set inet home_printing wifi_interfaces";
    };
  };

  systemd.services.home-printing-gate = {
    description = "Offer the home printer only on NAS-managed thomas-6ghz Wi-Fi";
    after = [
      "NetworkManager.service"
      "home-printing-filter.service"
    ];
    requires = [ "home-printing-filter.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${gate}/bin/home-printing-gate";
    };
  };
  networking.networkmanager.dispatcherScripts = [
    {
      source = pkgs.writeShellScript "home-printing-dispatch" ''
        case "$2" in
          up|down|dhcp4-change|reapply|connectivity-change)
            ${refresh}
            ;;
        esac
      '';
      type = "basic";
    }
  ];
}
