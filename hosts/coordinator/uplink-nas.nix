{
  config,
  lib,
  pkgs,
  ...
}:
let
  wifiReady = builtins.pathExists ../../secrets/wifi.age;
  lanReady = builtins.pathExists ../../secrets/wifi-lan.age;
  uplink = pkgs.writeShellScript "coordinator-uplink" ''
    export PATH=${
      lib.makeBinPath [
        pkgs.networkmanager
        pkgs.iproute2
        pkgs.iputils
      ]
    }
    exec ${pkgs.python3}/bin/python3 ${./uplink.py} "$@"
  '';
  service = mode: {
    description = "Check coordinator routing and DNS (${mode})";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${uplink} ${mode}";
      RuntimeDirectory = "coordinator-uplink";
      RuntimeDirectoryMode = "0700";
      RuntimeDirectoryPreserve = "yes";
      TimeoutStartSec = "150s";
    };
  };
in
{
  # Primary: static LAN identity, NAS routing and DNS. Emergency bypass changes
  # only the active device's gateway/DNS, leaving this saved profile intact.
  networking.networkmanager.ensureProfiles.profiles.freebox-uplink = lib.mkIf wifiReady {
    connection = {
      id = "Freebox-AB3ACE";
      type = "wifi";
      interface-name = "wlp192s0";
      autoconnect = true;
      autoconnect-priority = 100;
    };
    wifi = {
      mode = "infrastructure";
      ssid = "Freebox-AB3ACE";
      # Keep the Freebox radio pin: roaming between its bands has crashed mt7925e.
      bssid = "8C:97:EA:FE:FA:E0";
      band = "a";
    };
    wifi-security = {
      key-mgmt = "wpa-psk";
      psk = "$FREEBOX_PSK";
    };
    ipv4.method = "auto";
    ipv6.method = "auto";
  };
  networking.networkmanager.ensureProfiles.environmentFiles =
    lib.optional wifiReady config.age.secrets.wifi.path
    ++ lib.optional lanReady config.age.secrets.wifi-lan.path;

  networking.networkmanager.ensureProfiles.profiles.thomas-6ghz = lib.mkIf lanReady {
    connection = {
      id = "thomas-6ghz";
      type = "wifi";
      interface-name = "wlp192s0";
      autoconnect = true;
      autoconnect-priority = 110;
    };
    wifi = {
      mode = "infrastructure";
      # No BSSID/band pin: this SSID is only on the BE550 6 GHz radio;
      # its MLD scan and association BSSIDs differ. Preserve WPA3/PMF.
      ssid = "$BE550_SSID";
    };
    wifi-security = {
      key-mgmt = "sae";
      pmf = 3;
      psk = "$BE550_PSK";
    };
    ipv4 = {
      method = "manual";
      address1 = "10.42.0.2/24";
      gateway = "10.42.0.1";
      dns = "10.42.0.1";
      ignore-auto-dns = true;
    };
    # Keep this managed LAN IPv4-only; fallback Freebox retains automatic IPv6.
    ipv6.method = "disabled";
  };

  networking.networkmanager.logLevel = "INFO";

  systemd.services.uplink-failover-watchdog = service "tick";
  systemd.timers.uplink-failover-watchdog = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "3min";
      OnUnitActiveSec = "30s";
      AccuracySec = "1s";
    };
  };
  # Return only in controlled windows. A manual daytime Freebox connection is
  # never preempted, and a working BE550 bypass is not bounced back and forth.
  systemd.services.uplink-rail-reconcile = service "boot";
  systemd.timers.uplink-rail-reconcile = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      AccuracySec = "1s";
    };
  };
  systemd.services.uplink-rail-revert = service "return";
  systemd.timers.uplink-rail-revert = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 04:00:00";
      Persistent = false;
      AccuracySec = "1min";
    };
  };
}
