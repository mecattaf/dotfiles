{
  config,
  lib,
  pkgs,
  ...
}:
# ─── ax-client: kubectl and the ax binaries, on a host, behind a gate ───────
#
# Issue #453, 2026-09-23. Puts `kubectl` and `pkgs.ax` (google/ax v0.3.0,
# pkgs/ax) into environment.systemPackages on the host that imports this module
# and sets `myAxClient.enable = true`.
#
# THE GATE LANDS OFF, on all three hosts that import it. Flipping it is a
# separate act and it is Tom's. Nothing here starts, schedules or contacts
# anything: both are client binaries that do nothing until invoked with a target.
#
# WHY IT EXISTS. `kubectl` is absent from every host on this fleet (MEASURED
# 2026-09-22), so the ax CLI has no way to reach a cluster even once ax itself is
# installed, and the two are useless apart. They are host-scoped rather than
# fleet-wide user packages because kubectl is: it reads /etc/kubernetes and a
# host kube context, and the NAS must never grow either.
#
# WHAT IS DELIBERATELY NOT DONE HERE, and each reason:
#   - No cluster. No k3s, no kubelet, no API server, no control plane of any
#     kind is declared by this module or anywhere else in this tree. The
#     k3s-in-microVM route was NOT run on 2026-09-23; issue #453 records
#     why (the 2026-09-20 precedent needed a MODIFIED copy of
#     home/dot_local/bin/runtime-test carrying `--dev-bind /dev/kvm`, and the
#     private global rules forbid running that experiment without the declared
#     wrapper being changed first, reviewed, in its own change).
#   - No Agent Substrate and no Redis. ax delegates every sandbox to Agent
#     Substrate and is inert without it; Substrate has no flake and is not
#     packaged (see pkgs/ax's header). This module installs the client half
#     only, knowingly.
#   - No kubeconfig, no context, no credential, no secret. Nothing in this
#     module writes to /etc or to a home directory.
#   - No service, no unit, no timer, no socket, no firewall hole.
#   - hosts/nas does NOT import this module and must not: it is pinned to
#     nixpkgs-stable with no home-manager, and it is an appliance.
#
# RUNBOOK, for the flip. On the host whose turn it is, one host at a time:
#   1. Set `myAxClient.enable = true;` in that host's hosts/<host>/default.nix,
#      beside the `false` this module landed with.
#   2. `nix build --no-link .#ax` and `nix flake check --no-build` from the repo
#      root. The ax-client-topology check in flake.nix asserts the gate's value
#      per host, so it goes RED on the flip by design: update its expectation in
#      the same commit, which is the point — the flip cannot be silent.
#   3. Tom switches. Agents do not.
#   4. `kubectl version --client` and `ax --help` on the box. Neither needs a
#      cluster to answer, so both are safe first probes.
#   5. There is still no cluster to point either at. That is a later change and
#      it is gated on issue #453 being resolved first.
let
  cfg = config.myAxClient;
in
{
  options.myAxClient.enable =
    lib.mkEnableOption "the ax control-plane client: kubectl plus the google/ax binaries, on this host";

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.kubectl
      pkgs.ax
    ];
  };
}
