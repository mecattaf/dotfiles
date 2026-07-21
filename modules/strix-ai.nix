{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
# Accelerated AI package plane shared by the two Strix Halo nodes.
#
# Source split (deliberate, after inspecting both upstreams at their 2026-07-21
# heads):
#   * nix-amd-ai remains the coordinator's proven hardware.amd-npu/FastFlowLM
#     plane and supplies stable-diffusion-cpp-rocm, which hellas does not package.
#   * nix-strix-halo supplies every other GPU/runtime package below. Its gfx1151
#     DS4 build uses the targeted TheRock ROCm provider; do not also install
#     nix-amd-ai's older, manually-pinned ds4 package under the same bin names.
#
# XRT is intentionally absent here. hardware.amd-npu already composes and exports
# nix-amd-ai's XRT + amdxdna plugin on coordinator. Hellas currently pins the exact
# same upstream commits, and putting both implementations in the system profile
# would collide. They are not imported or re-exported: all NPU components have one
# source of truth, the already-live nix-amd-ai module.
let
  system = pkgs.stdenv.hostPlatform.system;
  amdAi = inputs.nix-amd-ai.packages.${system};
  strixAi = inputs.nix-strix-halo.packages.${system};

  # llama.cpp and stable-diffusion.cpp place backend shared objects in $out/bin.
  # nix-amd-ai documents that exposing those .so files through the global system
  # profile makes GLib's GIO loader try to dlopen them as plugins. Project only
  # commands into PATH while retaining the complete upstream package as a closure.
  commandsOnly =
    name: package:
    pkgs.runCommand name { } ''
      mkdir -p "$out/bin"
      for entry in ${package}/bin/*; do
        [ -e "$entry" ] || continue
        case "$(basename "$entry")" in
          *.so | *.so.*) continue ;;
        esac
        ln -s "$entry" "$out/bin/$(basename "$entry")"
      done
    '';

  llamaRocmCommands = commandsOnly "strix-llama-cpp-rocm-commands" strixAi.llama-cpp-rocm;
  llamaVulkanCommands = commandsOnly "strix-llama-cpp-vulkan-commands" strixAi.llama-cpp-vulkan;
  stableDiffusionRocmCommands = commandsOnly "strix-stable-diffusion-cpp-rocm-commands" amdAi.stable-diffusion-cpp-rocm;
in
{
  assertions = [
    {
      assertion = config.myCluster.role == "coordinator" || config.myCluster.role == "worker";
      message = "modules/strix-ai.nix is only valid on a Strix cluster role";
    }
  ];

  # User-facing engines and launchers on BOTH GPU nodes. FLM is not repeated here:
  # coordinator already receives it from hardware.amd-npu; worker deliberately has
  # no NPU runtime while amd_iommu=off preserves maximum iGPU bandwidth.
  environment.systemPackages = [
    llamaRocmCommands
    llamaVulkanCommands
    stableDiffusionRocmCommands
    strixAi.ds4-rocm
    strixAi.vllm-rocm
  ]
  ++ lib.optionals (config.myCluster.role == "coordinator") [
    # This program SSHes to both boxes and gathers the result, so only the
    # orchestrating node needs it in PATH; its vLLM/Ray closure is still shared
    # through the fleet cache with the worker's vLLM package.
    strixAi.strix-halo-vllm-pair-bench-gfx1151
  ];

  # Development/runtime libraries have no useful standalone command. Root them in
  # each generation without spraying Python/static-library trees into the global
  # profile; use `nix shell .#mlx-rocm .#tokenizers-cpp` for an interactive env.
  system.extraDependencies = [
    strixAi.mlx-rocm
    strixAi.tokenizers-cpp
  ];

  # The focused 0x80 MES blobs are the only part of upstream's `tuning` module we
  # adopt. Importing that whole module would regress our 128 GiB GTT ceiling to
  # upstream's 80 GiB default and enable unrelated tmpfs/TuneD policy.
  hardware.firmware = [ strixAi.strix-halo-mes-firmware ];

  # Not installed: ec-su-axb35-monitor is for Sixunited AXB35 boards. Both nodes
  # identify as Framework Desktop / FRANMFCP06, so its matching kernel driver would
  # no-op and the monitor would have no sysfs endpoint. It remains buildable as
  # `.#ec-su-axb35-monitor` for a future compatible machine.
  #
  # Also not a system dependency: `.#live-iso`. Rooting an installer ISO in every
  # generation would force a multi-GiB image build on each nightly switch; keeping it
  # as a flake package gives either node a reproducible on-demand build instead.
}
