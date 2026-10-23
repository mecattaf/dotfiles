{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./strix.nix
    ./gvisor.nix
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
  myGvisor.enable = lib.mkDefault false;
  services.qwen-tts.enable = true;
  services.utilityModel.enable = true;

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
