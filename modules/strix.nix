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

    # The gfx1151 ROCm graph contains several split Composable Kernel derivations,
    # each of which honors NIX_BUILD_CORES internally. Leaving both knobs at the
    # 32-thread defaults allowed up to 32 derivations with 32 compiler processes
    # apiece and exhausted 128 GiB during the first MLX build. Four eight-core
    # jobs keep all 32 hardware threads useful without multiplying parallelism.
    nix.settings = {
      max-jobs = 4;
      cores = 8;
    };

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

    # --- mt7925e latency: keep the radio awake, 2026-07-25 ---
    # Measured on the coordinator while debugging stuttering audio to the JBL:
    # ping to the LAN gateway averaged 108ms with 600ms spikes on a link that was
    # otherwise pristine (-64 dBm, 526 Mbit/s VHT, clean 5GHz ch40, 0 beacon loss,
    # 0 tx failures, no scans, no roams). The floor was 1.0ms, so the link CAN do
    # 1ms — it just spent most of its time asleep: /sys/kernel/debug/.../mt76
    # reported runtime-pm=1, deep-sleep=1 and a doze/awake ratio of 1462744/210114,
    # i.e. the card dozing ~87% of the time behind an 83ms idle timeout. Every
    # packet arriving into a doze paid a wake-up.
    #
    # Same-window control measurements proved it is the radio and nothing else:
    # loopback 0.10ms max 0.20, thunderbolt0 0.88ms max 1.28, wifi 105ms max 521.
    # CPU was idle, the firewall logged no drops, and blocking Bluetooth (which
    # shares this combo chip's antenna) changed nothing.
    #
    # Two layers have to be turned off, because they are independent:
    #   - mac80211/NetworkManager 802.11 power save (the PM bit in frames), and
    #   - the mt76 driver's OWN firmware-level runtime PM / deep sleep, which is
    #     debugfs-only on this driver — there is no module parameter for it, so a
    #     oneshot writes it. `disable_aspm=1` above is a THIRD, separate layer
    #     (PCIe link state) and does not cover either of these.
    # Both nodes are mains-powered desktops, so the few idle watts are irrelevant;
    # this only makes the existing "keep the card out of low-power states" stance
    # (see the crash hardening above) complete rather than half-applied.
    #
    # Effect, measured: doze time froze (1462744 → 1462770) while awake climbed
    # (210114 → 1207670), and average gateway latency halved (121ms → 64ms).
    # It does NOT fix the stuttering audio that led here — with the radio
    # confirmed awake and the link at -62 dBm / 780 Mbit/s the stutter returned,
    # so that fault lies elsewhere (the JBL is driven over AirPlay/RAOP instead;
    # see modules/desktop-media.nix). Keep this anyway: it removes a real source
    # of latency variance on a box with no reason to save power.
    networking.networkmanager.wifi.powersave = false;

    systemd.services.mt76-disable-runtime-pm = {
      description = "Disable mt76 firmware runtime PM / deep sleep (wifi latency)";
      wantedBy = [ "multi-user.target" ];
      after = [ "NetworkManager.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      # debugfs only materialises once the driver has probed the phy, which can lag
      # multi-user.target; poll briefly rather than racing it. Never fail the unit
      # (`|| true`, `exit 0`) — a box with no mt76 card, or a kernel that renamed
      # these knobs, must not leave a failed unit behind for the nightly deploy to
      # trip over (refs the 2026-07-15 auto-upgrade breakage).
      script = ''
        for _ in $(seq 1 30); do
          for knob in /sys/kernel/debug/ieee80211/*/mt76/runtime-pm /sys/kernel/debug/ieee80211/*/mt76/deep-sleep; do
            [ -w "$knob" ] && echo 0 > "$knob" || true
          done
          [ -e /sys/kernel/debug/ieee80211/phy0/mt76/runtime-pm ] && exit 0
          sleep 1
        done
        exit 0
      '';
    };

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

    # Split-horizon naming: each Strix node resolves its peer's canonical name
    # over the direct TB link. The node's own canonical name remains local, and
    # devices without this module resolve the same names through MagicDNS.
    networking.hosts =
      if config.myCluster.role == "coordinator" then
        { "10.77.0.2" = [ "worker" ]; }
      else
        { "10.77.0.1" = [ "coordinator" ]; };

    # docs/old/migration-journal/ds4-dual-node-lessons.md Lesson #5 + Appendix A:
    # an untrusted TB interface
    # REJECTs cluster traffic ("No route to host") — coordinator :8081 inbound AND
    # worker inbound KV staging. Trust the point-to-point link on BOTH nodes.
    networking.firewall.trustedInterfaces = [ "thunderbolt0" ];
  };
}
