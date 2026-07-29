{ inputs, ... }:
# microVM host platform (microvm-nix/microvm.nix). Provides the imperative
# `microvm` CLI, the `microvm@<name>` systemd template, the /var/lib/microvms
# state dir + tmpfiles, and the `microvm` system user — i.e. the DURABLE path
# from the /microvm skill (declarative `microvm.vms` + `microvm -c/-Ru`).
#
# Enabled on the coordinator, the durable execution and artifact front door.
# Guests are recreated from their declarative source; no mutable VM state is
# imported from another host. The EPHEMERAL default path
# (`nix run …config.microvm.declaredRunner`) needs none of this — only the flake
# input — so it works on any capable machine regardless of this module.
#
# Enabling the module boots NO VM: it only installs the platform. A guest exists
# only once you `microvm -c <name>` or declare `microvm.vms.<name>`. Teardown is
# NOT automatic — see the /microvm skill's Cleanup section (no upstream reap verb).
{
  imports = [ inputs.microvm.nixosModules.host ];
  microvm.host.enable = true;
}
