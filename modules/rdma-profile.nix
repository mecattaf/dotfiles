{ config, lib, ... }:
# thunderbolt_ibverbs option profiles for the Strix pair. Both ranks must load
# the same build with the same options (tests/gufo-rdma compares them), so the
# profile is selected once, in modules/strix-compute.nix.
let
  profile = config.myCompute.rdmaProfile;
in
{
  options.myCompute.rdmaProfile = lib.mkOption {
    type = lib.types.enum [
      "phase-a"
      "framework-host-credits"
    ];
    default = "phase-a";
    description = ''
      thunderbolt_ibverbs module-option profile.

      - `phase-a`: the base options and four-rail path options of
        modules/strix-compute.nix, with no DMA-BUF keys.
      - `framework-host-credits`: the lfthht README driver profile at 6ec2fb9
        (docs/framework-desktop.md "Temporary two-cable profile" plus
        `dmabuf_host_credits=1`). It needs the
        mecattaf/donnerkeule `codex/framework-7-3-host-credits` port, which adds
        that parameter. Unqualified on 7.3 hardware until a two-box run passes.
    '';
  };

  config = lib.mkIf (profile == "framework-host-credits") {
    hardware.thunderbolt-ibverbs.config = {
      # dmabuf_verbs=1 requires all five path options (kernel/main.c). These
      # values equal the Phase A ones, so the two definitions merge.
      bind_services = true;
      allocate_rings = true;
      start_rings = true;
      negotiate_native = true;
      enable_tunnels = true;
      native_domain_mask = 3;
      dmabuf_verbs = true;
      dmabuf_push_done = true;
      dmabuf_credits = true;
      nhi_interrupt_throttle_ns = 0;
      dmabuf_poll_us = 25;
      dmabuf_poll_control = true;
      dmabuf_batch_doorbell = true;
      dmabuf_post_burst = 128;
      dmabuf_coalesce_copy = true;
      dmabuf_reuse_buffers = true;
      # Host credits apply only to MRs that pass the direct-host DMA check.
      dmabuf_host_direct = true;
      dmabuf_host_credits = true;
    };
  };
}
