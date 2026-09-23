{
  config,
  lib,
  pkgs,
  ...
}:
# gvisor.nix: gVisor's `runsc` on the host PATH, and nothing else (G1,
# 2026-09-23 evaluation). GATE OFF on every host that imports it.
#
# WHY THIS FILE EXISTS APART FROM #447
# The 2026-09-23 runtime lane MEASURED that rootless `runsc run` on a
# generated OCI bundle works on the twins (rc propagated, rw worktree bind,
# $HOME hidden, `claude --version` ran), and that runsc is installed on no
# host: the only dotfiles carrier is draft #447 (`modules/k3s-fleet.nix`),
# where gVisor arrives as a containerd shim behind a k3s gate. The direct
# path needs neither k3s nor containerd, so it gets its own gate and can
# land, and be flipped, independently of the cluster decision.
#
# WHAT ENABLING IT DOES
#   * adds `pkgs.gvisor` (runsc and containerd-shim-runsc-v1) to
#     environment.systemPackages, which also roots the store path in the
#     system profile (the spike's copies were unrooted and collectable).
# WHAT IT DELIBERATELY DOES NOT DO
#   * no containerd, no podman runtime entry, no k3s RuntimeClass (#447 owns
#     those, and uses the same `pkgs.gvisor`, so the two cannot drift);
#   * no state directory: runsc's `--root` must be passed by the caller and
#     must point under ~/.local/state, never under $XDG_RUNTIME_DIR (the
#     rootless default), per the house rule on /run/user;
#   * no network policy: `--network=host` jobs reach whatever the host
#     reaches. An egress fence is a separate, open decision.
# Worker first is the lane's recommendation; the gate line is explicit on
# both twins so the flip is a one-line, host-scoped edit.
let
  cfg = config.myGvisor;
in
{
  options.myGvisor = {
    enable = lib.mkEnableOption "gVisor's runsc on PATH for rootless, direct `runsc run` jobs (no k3s, no containerd)";
    package = lib.mkPackageOption pkgs "gvisor" { };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];
  };
}
