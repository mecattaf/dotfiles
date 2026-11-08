{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  coordinator = config.networking.hostName == "strix-coordinator";
  # Tom, 2026-11-08 (#698): the second Strix is canceled. Keep the old
  # transport definitions inert until the separately scoped obsolete-code
  # sweep; no active or dormant host installs the dual-host stack.
  dualHost = false;
  rdma = config.hardware.thunderbolt-ibverbs;
  tokenCiphertext = ../secrets/gufo-tp2-control-token.age;
in
{
  imports = [
    inputs.donnerkeule.nixosModules.default
    ./strix.nix
    ./rdma-profile.nix
    ./ds4.nix
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

  # Each NHI has two payload ring pairs. Donnerkeule's four-rail mode owns
  # both on each cable: the old tbnet + tbstream consumers cannot share that
  # budget (#272/#276; 77778237). Ethernet carries management/bootstrap.
  boot.blacklistedKernelModules = lib.optionals dualHost [ "thunderbolt_stream" ];

  # The lfthht README driver profile (DMA-BUF fast path plus host credits) on
  # both ranks, selected once so the two hosts cannot diverge. Draft until a
  # two-box qualification on 7.3; "phase-a" restores the base options.
  myCompute.rdmaProfile = if dualHost then "framework-host-credits" else "phase-a";

  hardware.thunderbolt-ibverbs = lib.mkIf dualHost {
    enable = true;
    blacklist.enable = true;
    # With this false the upstream mkOverride 900 does not apply. The module
    # is built against modules/strix.nix's actual fleet kernel, never its own.
    kernel.useProjectKernel = false;
    package = (rdma.packageFor config.boot.kernelPackages).overrideAttrs (old: {
      passthru = (old.passthru or { }) // {
        donnerkeuleRevision = inputs.donnerkeule.rev;
        kernelVersion = config.boot.kernelPackages.kernel.version;
      };
    });
    userspaceTools.package = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.rdmaCoreUsb4;
    config = {
      profile = "linux_perf";
      tbnet = "prefer_rdma";
      lanes = "2";
      # The five path options default off in the driver (kernel/main.c): no
      # service binding, rings or native negotiation means zero rails even with
      # a live peer. Both hosts must load the same build with these set.
      # native_domain_mask 3 = both USB4 controllers (domain0, domain1), two
      # payload rails each: four rails. Phase A only; no dmabuf/host-credit keys.
      bind_services = true;
      allocate_rings = true;
      start_rings = true;
      negotiate_native = true;
      enable_tunnels = true;
      native_domain_mask = 3;
      register_verbs = true;
      roce_netdev = "tbv0";
      native_write_striping = true;
    };
    check = {
      enable = true;
      minReadyRails = 4;
      expectedRailSpeed = "20Gb/s";
      timeoutSeconds = 300;
    };
  };

  # GID metadata only. No IP packets travel over the USB4 cables; bootstrap
  # and control use the existing wired LAN. 10.77/30 is the NAS installer.
  networking.networkmanager.ensureProfiles.profiles.tbv0 = lib.mkIf dualHost {
    connection = {
      id = "tbv0";
      type = "dummy";
      interface-name = "tbv0";
      autoconnect = true;
    };
    ipv4 = {
      method = "manual";
      address1 = if coordinator then "10.99.0.1/30" else "10.99.0.2/30";
      never-default = true;
    };
    ipv6.method = "disabled";
  };

  # Keep the dormant worker's historical single-host DS4 definition. The
  # coordinator's pair-only TCP rank is retired with the missing second box.
  services.ds4 = {
    # The retained worker definition is single-host SSD streaming. The
    # coordinator no longer declares a TCP rank waiting for an absent peer.
    enable = !coordinator;
    role = if coordinator then "coordinator" else "worker";
    peerAddress = if coordinator then "10.42.0.5" else "10.42.0.2";
  }
  // lib.optionalAttrs (!coordinator) {
    mode = "single-ssd";
    dspark = false;
    apiAddress = "10.42.0.5";
  };

  services.gufo.tp2 = {
    enable = dualHost;
    rank = if coordinator then 0 else 1;
    peerAddress = if coordinator then "10.42.0.5" else "10.42.0.2";
  };
  # A service credential, independent of the disabled operator-secret tier.
  # Tom creates the ciphertext after recording the worker's fresh host key.
  age.secrets = lib.optionalAttrs (dualHost && builtins.pathExists tokenCiphertext) {
    gufo-tp2-control-token = {
      file = tokenCiphertext;
      mode = "0400";
    };
  };

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
