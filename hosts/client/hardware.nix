{
  config,
  lib,
  modulesPath,
  ...
}:
# REAL, not a placeholder: `nixos-generate-config --no-filesystems` output from
# the live UX8406 at the jul5 flash (dotfiles 77eac406^), re-verified on the
# metal by omarchy-fleet on 2026-09-07 and again over ssh on 2026-09-11: vmd
# loaded with the NVMe (Sandisk SN560/SN740) behind Intel VMD, i915 bound to
# the Meteor Lake Arc, xe idle. Filesystems come from ./disko.nix.
#
# NOT carried from omarchy-fleet's copy, on purpose:
#   * the 7.2.4 kernel pin plus its vmd MTL016 backport — a kernel build is
#     not today's work; the intermittent VMD boot stall (a ~5 min wait, not a
#     brick) is accepted until the upstream ordering fix reaches a stable the
#     fleet pin already carries. Follow-up, not a footnote.
#   * hardware.cpu.intel.npu.enable — AGENTS.md's NPU decommission is worded
#     for the XDNA2 twins, but a thin client with all inference on the worker
#     has no consumer for Intel NPU firmware either; the surface stays closed.
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [
    "xhci_pci"
    # This is the docking host; the module stays in the initrd here even
    # though the twins dropped theirs with the Thunderbolt rails.
    "thunderbolt"
    # Load-bearing: root is invisible without it.
    "vmd"
    "nvme"
    "usbhid"
    "usb_storage"
    "sd_mod"
  ];
  # Early KMS for i915: two internal eDP panels want early i915 for a reliable
  # dual-eDP modeset (1c718bb0). The MEI GSC proxy goes in the initrd with it:
  # loaded only after switch-root it misses i915's proxy deadline whenever
  # root storage stalls (omarchy-fleet docs/zenbook-duo-boot-2026-09-10.md).
  # A dependency fix, not the stall fix.
  boot.initrd.kernelModules = [
    "mei"
    "mei_me"
    "mei_gsc_proxy"
    "i915"
  ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
