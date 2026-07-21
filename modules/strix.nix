{
  inputs,
  lib,
  config,
  pkgs,
  ...
}:
# AMD Strix Halo layer — imported by `coordinator` + `worker` ONLY.
{
  imports = [
    # Framework Desktop / Ryzen AI Max 300 series (gfx1151). Pulls amd cpu+gpu+ssd tuning.
    inputs.nixos-hardware.nixosModules.framework-desktop-amd-ai-max-300-series
    # Shared accelerated inference/tooling packages from nix-strix-halo plus the
    # one noamsto-only GPU backend. Host-role details stay in that module.
    ./strix-ai.nix
    # Native local-model proxy/control plane on coordinator + worker only.
    ./llama-swap.nix
    # Typed model catalog, guarded store materialization, and host projections.
    ./local-models.nix
  ];

  options.myCluster = {
    role = lib.mkOption {
      type = lib.types.enum [
        "coordinator"
        "worker"
      ];
      description = "Role on the AMD Strix Halo Thunderbolt cluster.";
    };
    tbHostId = lib.mkOption {
      type = lib.types.int;
      # coordinator=1, worker=2 → static thunderbolt0 IPs 10.77.0.{1,2}
      default = if config.myCluster.role == "coordinator" then 1 else 2;
      description = "Host id on the deterministic Thunderbolt link (drives the static /30).";
    };
  };

  config = {
    # THE one model-install switch. Keep false until the reviewed roster and the
    # external cold-storage migration are ready; false roots zero model weights.
    services.local-models.downloadAllModels = false;

    # One TUI for CPU, Radeon iGPU, and (on the coordinator) XDNA NPU telemetry.
    environment.systemPackages = [ pkgs.amdtop ];

    # Strix Halo unified-memory tuning (128 GiB pinnable for the iGPU).
    # IOMMU is the ONE per-role knob: the coordinator runs the NPU, whose amdxdna
    # driver binds via IOMMU SVA/PASID and needs IOMMU ON in translated mode
    # (hardware.amd-npu additionally pins iommu.passthrough=0). The worker keeps
    # the NPU off and takes amd_iommu=off for lower GPU-memory latency / max iGPU.
    boot.kernelParams = [
      (if config.myCluster.role == "coordinator" then "amd_iommu=on" else "amd_iommu=off")
      "ttm.pages_limit=33554432"
    ];

    # --- mt7925e (RZ717 wifi) crash hardening, 2026-07-16 ---
    # The MT7925 driver has a remaining wcid list-corruption race on the STA
    # teardown/setup path (kernel BUG at lib/list_debug.c:32 → instant hard
    # lockup: LEDs on, zero video, zero network, manual power-cycle needed).
    # Fired twice on the coordinator within 12h of the BIOS 3.02→3.05 update
    # after weeks of silence on 3.02 — prime suspect is 3.05 changing PCIe
    # ASPM/power-state timing. Kernel 7.1 already has the upstream fixes for
    # the KNOWN instances of this bug class (zbowling v7 series), so until the
    # remaining race is fixed upstream we keep the card out of ASPM low-power
    # states via the driver's own escape hatch. Cost: ~1W idle. Both nodes
    # carry the same RZ717 card. The roam TRIGGER is separately removed by the
    # BSSID pin in hosts/coordinator/uplink-nas.nix.
    boot.extraModprobeConfig = "options mt7925e disable_aspm=1";

    # Hardware watchdog (sp5100_tco, /dev/watchdog0 — present but unfed until
    # now): systemd pets it at runtime; if the kernel ever hard-locks again
    # (this bug or the next one) the chip force-resets the box after 30s
    # instead of it sitting "on but dead" overnight until someone finds it —
    # the exact 2026-07-16 failure mode, twice. rebootTime bounds a hung
    # reboot/shutdown the same way.
    systemd.watchdog.runtimeTime = "30s";
    systemd.watchdog.rebootTime = "2m";

    # --- Thunderbolt cluster fabric (direct coordinator↔worker cable) ---
    boot.kernelModules = [ "thunderbolt-net" ]; # host-to-host TB networking (thunderbolt0)

    # Deterministic static /30 on the direct TB cable; keep NetworkManager's hands
    # off it (NM-assigned link-local IPs were the fragile part).
    networking.networkmanager.unmanaged = [ "interface-name:thunderbolt0" ];
    networking.interfaces.thunderbolt0 = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = "10.77.0.${toString config.myCluster.tbHostId}";
          prefixLength = 30;
        }
      ];
    };

    # The scripted one-shot that assigns the static IP races the TB XDomain
    # handshake: if thunderbolt0 appears after systemd's 90s device timeout, the
    # job fails and never re-runs → headless box with no address until a lucky
    # power cycle. Hooking the service onto the device unit re-fires it whenever
    # the link (re)appears — idempotent, the script uses `ip addr replace`.
    systemd.services."network-addresses-thunderbolt0".wantedBy = [
      "sys-subsystem-net-devices-thunderbolt0.device"
    ];

    # Naming fabric: both nodes resolve both TB endpoints by role name
    # (-tb suffix so LAN/tailscale resolution of the plain hostnames is untouched).
    networking.hosts = {
      "10.77.0.1" = [ "coordinator-tb" ];
      "10.77.0.2" = [ "worker-tb" ];
    };

    # ds4-dual-node-lessons.md Lesson #5 + Appendix A: an untrusted TB interface
    # REJECTs cluster traffic ("No route to host") — coordinator :8081 inbound AND
    # worker inbound KV staging. Trust the point-to-point link on BOTH nodes.
    networking.firewall.trustedInterfaces = [ "thunderbolt0" ];
  };
}
