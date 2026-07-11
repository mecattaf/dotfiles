{ inputs, ... }:
# microVM host platform (microvm-nix/microvm.nix). Provides the imperative
# `microvm` CLI, the `microvm@<name>` systemd template, the /var/lib/microvms
# state dir + tmpfiles, and the `microvm` system user — i.e. the DURABLE path
# from the /microvm skill (declarative `microvm.vms` + `microvm -c/-Ru`).
#
# Enabled on the WORKER only: the Strix Halo compute node is where heavy microVM
# execution belongs, keeping the coordinator (agent conductor) light per the
# no-heavy-build-on-coordinator doctrine. The EPHEMERAL default path
# (`nix run …config.microvm.declaredRunner`) needs none of this — only the flake
# input — so it works fleet-wide regardless of this module. Move this import to
# another host if the sandbox-execution target changes.
#
# Enabling the module boots NO VM: it only installs the platform. A guest exists
# only once you `microvm -c <name>` or declare `microvm.vms.<name>`. Teardown is
# NOT automatic — see the /microvm skill's Cleanup section (no upstream reap verb).
{
  imports = [ inputs.microvm.nixosModules.host ];
  microvm.host.enable = true;
}
