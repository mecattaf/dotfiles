{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
# worker — AMD Strix Halo, soft-retired headless worker. It remains a fully
# declared host and optional compute target, reached exclusively over Tailscale.
let
  freeboxWifiReady = builtins.pathExists ../../secrets/wifi-freebox-worker.age;
  sodimoWifiReady = builtins.pathExists ../../secrets/wifi-sodimo-worker.age;
in
{
  imports = [
    ./hardware.nix
    ./disko.nix
    ./headless-display.nix
    ./cache-push.nix
    ./gpu-cooldown.nix
    ../../modules/strix.nix
    ../../modules/microvm-host.nix
    # Per-machine AdGuard Home DNS filter (loopback 127.0.0.1:53, resolved
    # forwards to it). Proving ground for the fleet-wide rollout — enabled here
    # FIRST because the worker is headless, so a DNS misstep can't lock Tom out
    # of Claude Code. Coordinator + zenbook get the same import once proven.
    ../../modules/adguardhome.nix
  ];

  networking.hostName = "worker";
  myCluster.role = "worker";

  # Persist both the current home uplink and the new fixed-location uplink so a
  # rebuild never depends on NetworkManager's mutable keyfiles. Freebox keeps the
  # higher priority while it is in range; elsewhere the worker joins sodimo_wifi.
  # Both ciphertexts are worker-only, and ensureProfiles substitutes their PSKs
  # without placing either one in the Nix store.
  age.secrets.wifi-freebox-worker = lib.mkIf freeboxWifiReady {
    file = ../../secrets/wifi-freebox-worker.age;
    mode = "400";
  };
  age.secrets.wifi-sodimo-worker = lib.mkIf sodimoWifiReady {
    file = ../../secrets/wifi-sodimo-worker.age;
    mode = "400";
  };
  networking.networkmanager.ensureProfiles.environmentFiles =
    lib.optionals freeboxWifiReady [ config.age.secrets.wifi-freebox-worker.path ]
    ++ lib.optionals sodimoWifiReady [ config.age.secrets.wifi-sodimo-worker.path ];
  networking.networkmanager.ensureProfiles.profiles = {
    "Freebox-AB3ACE" = lib.mkIf freeboxWifiReady {
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
      };
      wifi-security = {
        key-mgmt = "wpa-psk";
        psk = "$FREEBOX_PSK";
      };
      ipv4.method = "auto";
      ipv6.method = "auto";
    };
    sodimo_wifi = lib.mkIf sodimoWifiReady {
      connection = {
        id = "sodimo_wifi";
        type = "wifi";
        interface-name = "wlp192s0";
        autoconnect = true;
        autoconnect-priority = 50;
      };
      wifi = {
        mode = "infrastructure";
        ssid = "sodimo_wifi";
      };
      wifi-security = {
        key-mgmt = "wpa-psk";
        psk = "$SODIMO_PSK";
      };
      ipv4.method = "auto";
      ipv6.method = "auto";
    };
  };

  # Every worker service is tailnet-only at the firewall. Tailscale SSH remains
  # enabled fleet-wide, and ordinary key-based OpenSSH remains available on the
  # tailnet for deploy-rs/nixos-rebuild recovery without exposing :22 to the new
  # raw Wi-Fi LAN.
  services.openssh.openFirewall = false;
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 22 ];

  # No Tally daemon or user-visible command runs here. The merged central-executor
  # protocol requires the same binary only as a fixed, short-lived
  # `__remote-executor` helper reached by coordinator over SSH. Root it in the
  # system closure without adding it to PATH; all queues, leases, and witnesses
  # remain coordinator-side.
  system.extraDependencies = [
    inputs.tally.packages.${pkgs.stdenv.hostPlatform.system}.tally
  ];

  # GPU thermal cooldown tripwire — poll junction/Tctl, and on a sustained trip
  # ask coordinator to enqueue a non-preemptive 30-min worker-gpu hold.
  services.gpuCooldownTripwire.enable = true;

  # Flipped ON after the 2026-07-05 first boot proved the nixos-anywhere host-key
  # delivery: the same /etc/ssh/ssh_host_ed25519_key that authenticated the box
  # against mesh-registry.nix is agenix's decryption identity.
  mySecrets.enable = true;
}
