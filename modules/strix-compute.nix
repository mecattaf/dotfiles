{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  coordinator = config.networking.hostName == "strix-coordinator";

in
{
  imports = [
    ./strix.nix
    ./microvm-host.nix
    ./cli-anything.nix
    ./fleet-hosts.nix
    ./fleet-transport.nix
    ./journal-upload.nix
    ./library-client.nix
    ./attic-cache-tripwire.nix
    ./qwen-tts.nix
    ./immich-ml.nix
  ];

  assertions = [
    {
      assertion = config.myFleet.has "compute";
      message = "The Strix compute profile requires the compute role.";
    }
  ];
  myDisplay.enable = false;
  hardware.bluetooth.enable = lib.mkForce false;
  mySecrets.enable = lib.mkDefault false;
  services.qwen-tts.enable = true;
  services.utilityModel.enable = true;
  # A request-scoped renderer, not a daemon or a print queue. The NAS sends
  # Markdown over its pinned SSH channel and keeps submission/receipt ownership.
  environment.systemPackages = lib.optionals coordinator [ pkgs.paper-render ];
  # No mDNS on compute: the printer queue lives on the NAS (modules/printing.nix).
  services.avahi.enable = lib.mkForce false;

  # Tom canceled the second Strix (#698). The pair-only driver/profile,
  # metadata interface and credential are archived rather than imported.

  # Tom permanently retired the local DeepSeek bundle on 2026-11-08; its
  # disabled ds4 module was removed on 2026-11-13 (#536).

  services.power-profiles-daemon.enable = lib.mkForce false;
  systemd.services.power-profile-balanced = {
    description = "Pin the platform profile and CPU energy preference to balanced";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    # amd_pmf is a udev-loaded module; give /sys/firmware/acpi/platform_profile
    # a moment to appear at boot rather than racing it.
    script = ''
      for _ in $(seq 1 40); do
        [ -w /sys/firmware/acpi/platform_profile ] && break
        sleep 0.5
      done
      echo balanced > /sys/firmware/acpi/platform_profile
      for p in /sys/devices/system/cpu/cpufreq/policy*; do
        echo powersave > "$p/scaling_governor"
        echo balance_performance > "$p/energy_performance_preference"
      done
    '';
  };

}
