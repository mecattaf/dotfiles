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
}
