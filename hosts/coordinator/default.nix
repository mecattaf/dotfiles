{ inputs, ... }:
# coordinator — AMD Strix Halo (gfx1151), the main device. Router plane
# (router.nix: BE550 gateway/DHCP/DNS + NAS) and rootless quadlets
# (services.nix: adguard/immich/navidrome + sodimo demos, gated on mySecrets).
{
  imports = [
    ./hardware.nix
    ./disko.nix
    ./router.nix
    ./services.nix
    ../../modules/strix.nix
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
  # OpenAI-compatible endpoint (127.0.0.1:52625) is always available to on-box
  # consumers — zmx session titling, and the memory-flush path. `model` is the
  # ONE place to swap which model the coordinator warms; runs as tom so the pull
  # lands in ~/.config/flm/models (weights stay out of the nix store).
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
