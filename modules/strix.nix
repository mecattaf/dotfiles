{
  inputs,
  lib,
  config,
  ...
}:
# AMD Strix Halo layer — imported by `coordinator` + `worker` ONLY.
{
  imports = [
    # Framework Desktop / Ryzen AI Max 300 series (gfx1151). Pulls amd cpu+gpu+ssd tuning.
    inputs.nixos-hardware.nixosModules.framework-desktop-amd-ai-max-300-series
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
    # Strix Halo unified-memory tuning (128 GiB pinnable for the iGPU; iommu off = lower latency).
    boot.kernelParams = [
      "amd_iommu=off"
      "ttm.pages_limit=33554432"
    ];

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
