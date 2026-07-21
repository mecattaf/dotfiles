{ inputs, ... }:
# coordinator — AMD Strix Halo (gfx1151), the main device. Freebox wifi uplink +
# directly-attached NAS (uplink-nas.nix) and the native media services
# (services.nix: services.immich + services.navidrome, on /mnt/nas). DNS
# ad/tracker filtering is per-box (../../modules/adguardhome.nix, a loopback
# resolver). The old rootless podman quadlet stack — AdGuard, Immich, Navidrome —
# was retired 2026-07-13 (AdGuard with the BE550 router; Immich/Navidrome moved
# to native modules), leaving this host container-free.
{
  imports = [
    ./hardware.nix
    ./disko.nix
    ./uplink-nas.nix
    ./services.nix
    # Per-machine AdGuard Home DNS filter (loopback 127.0.0.1:53, resolved
    # forwards to it). Proven on the worker first (2026-07-13) before landing on
    # this main device. Same import on worker + zenbook-duo.
    ../../modules/adguardhome.nix
    ./attic.nix # fleet binary-cache server (atticd over the tailscale mesh) — refs #42
    # Artifact serving plane: Caddy drop-dir + TTL reaper (publish-artifact
    # skill's tailnet rung). Coordinator = fleet front door; origins on worker.
    ../../modules/caddy-artifacts.nix
    ../../modules/strix.nix
    # Distributed builds — offload heavy compiles to the worker over the TB5 fast
    # lane; the result is cached (attic) so no other host rebuilds it. refs #42.
    ../../modules/build-offload.nix
    # AMD Ryzen AI NPU stack — coordinator ONLY (the worker keeps the NPU off for
    # max iGPU). Brings the amdxdna driver + XRT + FastFlowLM; requires IOMMU in
    # translated mode, set via amd_iommu=on for this role in modules/strix.nix.
    inputs.nix-amd-ai.nixosModules.default
    # Declarative `flm serve` unit + the coordinator's preloaded NPU model choice.
    ../../modules/npu-llm.nix
  ];

  networking.hostName = "coordinator";
  myCluster.role = "coordinator";
  myCluster.tbHostId = 1;

  # Flipped post-flash after the zero-TOFU host-key check (2026-07-05): the
  # delivered /etc/ssh/ssh_host_ed25519_key matched mesh-registry.nix, so
  # agenix may now decrypt against it (same two-step as the worker).
  mySecrets.enable = true;

  # NPU ON for the conductor. enableNPU wires the amdxdna kmod, XRT userspace,
  # udev + memlock, and pins iommu.passthrough=0 (translated IOMMU — required,
  # and why strix.nix sets amd_iommu=on for this role). FastFlowLM is the NPU
  # inference runtime. Lemonade / ROCm / Vulkan stay off for now (add later for
  # the AI-server UI) to keep the closure lean. tom is already in video+render.
  hardware.amd-npu = {
    enable = true;
    enableNPU = true;
    enableFastFlowLM = true;
    enableLemonade = false;
    enableROCm = false;
    lemonade.user = "tom";
  };

  # Preload a small model on the NPU and keep `flm serve` warm so the local
  # OpenAI-compatible backend (127.0.0.1:52625) stays warm behind llama-swap.
  # zmx titling and every other local consumer use llama-swap on :9292. `model`
  # is the ONE place to swap which model the coordinator warms; runs as tom so
  # the pull lands in ~/.config/flm/models (weights stay out of the nix store).
  services.npu-llm = {
    enable = true;
    model = "gemma4-it:e4b";
    user = "tom";
  };

  # asr-rs dual-Parakeet engine: this box hosts the models and serves inference
  # to tailnet thin clients (zenbook-duo dictates against it). Same trust model
  # as wayvnc:5900 — the port is open ONLY on tailscale0; the daemon binds
  # 0.0.0.0 and the interface-scoped firewall is the boundary.
  networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 8762 ];
}
