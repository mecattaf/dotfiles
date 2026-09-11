{
  inputs,
  pkgs,
  ...
}:
# Accelerated AI package plane for the coordinator.
#
# Source split (deliberate, after inspecting both upstreams at their 2026-07-21
# heads):
#   * nix-amd-ai supplies the uniform hardware.amd-npu/FastFlowLM plane and
#     stable-diffusion-cpp-rocm, which hellas does not package.
#   * nix-strix-halo supplies every other GPU/runtime package below: the
#     llama.cpp ROCm and Vulkan builds an operator serves the small GGUF
#     artifacts with by hand, amdtop, and the MES firmware. The big model is
#     not served from here at all — it is Halogen Flash, a self-contained OCI
#     image on the worker (modules/halogen.nix).
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
  # User-facing engines and launchers. FLM is not repeated here: the
  # hardware.amd-npu module already provides it.
  environment.systemPackages = [
    llamaRocmCommands
    llamaVulkanCommands
    stableDiffusionRocmCommands

    # ds4-rocm, vllm-rocm, mlx-rocm and mlx-lm are deliberately ABSENT: each
    # pulls therock-rocm-sdk-gfx1151 — an 8.3 GiB NAR that no upstream cache
    # serves — into the closure, where it was the dominant term of every cold
    # nightly update-center push (#234's arithmetic), and nothing on the fleet
    # runs them. The fleet is mono-model on Halogen; llama.cpp covers the
    # small artifacts.

    # One TUI for CPU, Radeon iGPU, and XDNA NPU telemetry. Upstream packaged it
    # (hellas-ai/nix-strix-halo#161) after we carried a local pkgs/amdtop.nix;
    # sourcing it here retires that copy and puts it on the same gfx1151 plane.
    strixAi.amdtop
  ];

  # The focused 0x80 MES blobs are the only part of upstream's `tuning` module we
  # adopt. Importing that whole module would regress our 128 GiB GTT ceiling to
  # upstream's 80 GiB default and enable unrelated tmpfs/TuneD policy.
  hardware.firmware = [ strixAi.strix-halo-mes-firmware ];

  # Not installed: ec-su-axb35-monitor is for Sixunited AXB35 boards. This host
  # identifies as Framework Desktop / FRANMFCP06, so its matching kernel driver would
  # no-op and the monitor would have no sysfs endpoint. It remains buildable as
  # `.#ec-su-axb35-monitor` for a future compatible machine.
  #
  # Also not a system dependency: `.#live-iso`. Rooting an installer ISO in every
  # generation would force a multi-GiB image build on each nightly switch; keeping it
  # as a flake package gives the coordinator a reproducible on-demand build instead.
}
