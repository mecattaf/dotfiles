{
  lib,
  pkgs,
  ...
}:
# The home Wi-Fi ladder (Tom, 2026-10-25: "i want to put in a rule for it to
# connect to thomas-6ghz network in priority all the time, so that future nas
# failures do not kill my internet access yet when nas (and all sysems) are
# running properly we don't run into problems").
#
#   rung 1  thomas-6ghz         DHCP from the NAS: gateway and AdGuard DNS are
#                               the NAS (hosts/nas/router.nix). Normal life.
#   rung 2  thomas-6ghz-direct  the same SSID, static 10.42.0.16 (the address the
#                               NAS pins to this MAC anyway), BE550 .3 as gateway
#                               and DNS: the strix pair's own path, NAS bypassed
#                               ("an accepted bypass", router.nix). The LAN,
#                               strix-coordinator and strix-worker stay direct.
#   rung 3  Freebox-AB3ACE      the ISP box's own Wi-Fi; an imperative keyfile
#                               (created with nmtui on 2026-10-25, priority 0).
#
# DOWN the ladder:
#   * DHCP never answers (NAS down at association): NetworkManager alone. Rung
#     1 gives up after two 20 s DHCP attempts and autoconnect picks rung 2
#     (priority 100 < 110); a missing thomas-6ghz SSID leaves only rung 3.
#   * The NAS dies under a live lease (2026-10-25 01:00-02:00): the lease is
#     `infinite`, so NetworkManager never notices. Its connectivity check
#     (below) raises connectivity-change; the dispatcher starts
#     wifi-ladder-guard, which steps down only when a NAS-specific probe fails
#     three times in ~30 s AND the next rung actually works. An internet
#     outage behind the Freebox fails every rung alike and moves nothing.
# UP the ladder: nothing on this box learns that the NAS came back (one radio,
#   and NetworkManager never preempts an active profile), so
#   wifi-ladder-return runs ONLY while rung 2 or 3 is active, probes the NAS
#   once a minute, and steps back up after three healthy probes. A step-down
#   within 15 min of a return doubles its wait (cap 1 h). `wifi-ladder hold`
#   pauses returns until reboot; `wifi-ladder status` shows every probe.
#   This loop is the ladder's one clock: dispatcher-started, bounded to the
#   fallback state, no timer and no OnCalendar (AGENTS.md "Scheduled work").
let
  haveLanSecret = builtins.pathExists ../../secrets/wifi-lan.age;

  ladder = pkgs.writeShellApplication {
    name = "wifi-ladder";
    runtimeInputs = [
      pkgs.networkmanager
      pkgs.dnsutils # dig
      pkgs.iputils
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.util-linux # flock
    ];
    text = builtins.readFile ./wifi-ladder.sh;
  };

  systemctl = "${pkgs.systemd}/bin/systemctl";
  dispatch = pkgs.writeShellScript "wifi-ladder-dispatch" ''
    # $1 interface (empty for connectivity-change), $2 action. Never block the
    # dispatcher queue: hand off to units and return at once.
    case "$2" in
      connectivity-change)
        if [ "''${CONNECTIVITY_STATE:-}" != FULL ]; then
          ${systemctl} start --no-block wifi-ladder-guard.service
        fi
        ;;
      up)
        [ "$1" = wlo1 ] || exit 0
        case "''${CONNECTION_ID:-}" in
          thomas-6ghz) ${systemctl} stop --no-block wifi-ladder-return.service ;;
          thomas-6ghz-direct | Freebox-AB3ACE) ${systemctl} start --no-block wifi-ladder-return.service ;;
        esac
        ;;
    esac
    exit 0
  '';
in
lib.mkIf haveLanSecret {
  # NetworkManager's own connectivity check is the guard's only trigger. 60 s
  # instead of the 300 s default so a dead NAS is seen within ~1.5 min. Same
  # endpoint GNOME ships; it answers "NetworkManager is online" (measured over
  # the Freebox and through AdGuard, 2026-10-25).
  networking.networkmanager.settings.connectivity = {
    uri = "http://nmcheck.gnome.org/check_network_status.txt";
    interval = 60;
  };

  networking.networkmanager.ensureProfiles.profiles.thomas-6ghz-direct = {
    connection = {
      id = "thomas-6ghz-direct";
      type = "wifi";
      autoconnect = true;
      autoconnect-priority = 100;
    };
    wifi = {
      mode = "infrastructure";
      ssid = "$BE550_SSID";
    };
    wifi-security = {
      key-mgmt = "sae";
      pmf = 3;
      psk = "$BE550_PSK";
    };
    ipv4 = {
      method = "manual";
      address1 = "10.42.0.16/24";
      gateway = "10.42.0.3";
      # The BE550's resolver answers on .3 (measured 2026-10-25); Quad9 behind
      # it in case it does not. No AdGuard here, by construction: this rung
      # exists for when the NAS is gone. Fleet names come from /etc/hosts.
      dns = "10.42.0.3;9.9.9.9;";
      # Same reason as rung 1: the LAN stays direct, never via the (dead) NAS
      # subnet route that tailscale0's table 52 would otherwise pick.
      routing-rule1 = "priority 2500 to 10.42.0.0/24 table 254";
    };
    ipv6.method = "ignore";
  };

  networking.networkmanager.dispatcherScripts = [
    {
      source = dispatch;
      type = "basic";
    }
  ];

  systemd.tmpfiles.rules = [ "d /run/wifi-ladder 0755 root root -" ];

  # Neither unit has wantedBy: only the dispatcher starts them.
  systemd.services.wifi-ladder-guard = {
    description = "Home Wi-Fi ladder: step down when the NAS stops serving the LAN";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${ladder}/bin/wifi-ladder guard";
      TimeoutStartSec = "5min";
    };
  };
  systemd.services.wifi-ladder-return = {
    description = "Home Wi-Fi ladder: step back up to thomas-6ghz once the NAS answers";
    serviceConfig = {
      Type = "simple";
      ExecStart = "${ladder}/bin/wifi-ladder return";
      Restart = "no";
    };
  };

  environment.systemPackages = [ ladder ];
}
